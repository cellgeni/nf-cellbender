#!/usr/bin/env python3
"""Prepare a CellBender remove-background run.

Finds the raw matrix in a Cell Ranger or STARsolo output folder (or takes a bare .h5 file or .mtx
folder), lists the features CellBender should leave out of its model, and works out
--expected-cells, --total-droplets-included and --low-count-threshold. Writes the CellBender
arguments to --args-file, one per line, every feature left out of the model to --excluded-file
(index, id, name, type, umis, reason, decision), and a summary to stdout.

A value given for the sample (--expected-cells, --total-droplets, --low-count-threshold) is always
passed as given. --preset decides what fills the ones not given:
  auto    CellBender's own estimate: CellBender 0.3 makes it itself, so nothing is passed; for
          CellBender 0.2 the copy of 0.3's code in cellbender_priors.py makes it here;
  mapper  the mapper preset, from the mapper's cell calls;
  off     nothing: expected cells and total droplets must be given, and a missing low-count
          threshold is left to CellBender's default.

The same file is in the CellBender 0.2 and 0.3 modules; keep the two copies identical.
"""

import argparse
import gzip
import logging
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

import h5py
import numpy as np
import pandas as pd

CHUNK = 20_000_000  # matrix entries read at once

# CellBender's --low-count-threshold default per version, used when --preset off leaves it unset
CELLBENDER_LOW_COUNT_DEFAULT = {"0.2": 15, "0.3": 5}

# Mapper preset constants, as in the original preset.sh
PRESET_CELL_UMI = 200       # a called cell needs more than this many UMIs
PRESET_EMPTY_RANK = 20_000  # rank whose UMI count can become the low-count threshold
PRESET_MIN_UMI = 10         # lowest low-count threshold


INPUT_ERROR = 3  # exit status for an input the module cannot use: retrying will not help


class PrepareError(Exception):
    """An input problem, reported as one line on stderr with exit status INPUT_ERROR."""


# ------------------------------------------------------------------------------------------------
# Reading matrices


def with_gz(folder, *names):
    """First of names (or names.gz) that exists in folder, or None."""
    for name in names:
        for candidate in (folder / name, folder / f"{name}.gz"):
            if candidate.is_file():
                return candidate
    return None


def read_tsv(path, columns):
    return pd.read_csv(path, sep="\t", header=None, usecols=columns, dtype=str,
                       compression="gzip" if path.suffix == ".gz" else None)


def decode(values):
    values = np.asarray(values)
    return values.astype(str) if values.dtype.kind == "S" else np.array(
        [v.decode() if isinstance(v, bytes) else str(v) for v in values])


def matrix_group(h5):
    """The matrix group of a 10x HDF5 file: 'matrix' (Cell Ranger 3+) or the genome group (2)."""
    return h5["matrix"] if "matrix" in h5 else h5[list(h5.keys())[0]]


@dataclass
class MatrixIndex:
    barcodes: np.ndarray = None
    feature_ids: np.ndarray = None
    feature_names: np.ndarray = None  # the IDs when the matrix has no names (peaks)
    feature_types: np.ndarray = None  # None when the matrix does not record them
    target_sets: np.ndarray = None    # indices of features in a probe set (Flex), or None


def read_index(path, barcodes=True, features=True):
    """Barcodes and features of a 10x matrix: an .h5 file or a folder with barcodes/features files."""
    index = MatrixIndex()
    if path.is_file():
        with h5py.File(path, "r") as h5:
            group = matrix_group(h5)
            if barcodes:
                index.barcodes = decode(group["barcodes"][:])
            if features:
                if "features" in group:
                    feats = group["features"]
                    index.feature_ids = decode(feats["id"][:])
                    index.feature_names = decode(feats["name"][:]) if "name" in feats else index.feature_ids
                    if "feature_type" in feats:
                        index.feature_types = decode(feats["feature_type"][:])
                    if "target_sets" in feats and len(feats["target_sets"]):
                        # Cell Ranger stores the feature indices of a probe set as strings
                        index.target_sets = np.unique(np.concatenate(
                            [decode(feats["target_sets"][name][:]).astype(np.int64) for name in feats["target_sets"]]))
                else:
                    index.feature_ids = decode(group["genes"][:])
                    index.feature_names = (decode(group["gene_names"][:]) if "gene_names" in group
                                           else index.feature_ids)
        return index

    if barcodes:
        barcode_file = with_gz(path, "barcodes.tsv")
        if barcode_file is None:
            raise PrepareError(f"no barcodes.tsv[.gz] in {path}")
        index.barcodes = read_tsv(barcode_file, [0])[0].to_numpy(str)
    if features:
        feature_file = with_gz(path, "features.tsv", "genes.tsv")
        if feature_file is not None:
            table = pd.read_csv(feature_file, sep="\t", header=None, dtype=str,
                                compression="gzip" if feature_file.suffix == ".gz" else None)
            index.feature_ids = table[0].to_numpy(str)
            index.feature_names = table[1].to_numpy(str) if table.shape[1] >= 2 else index.feature_ids
            if table.shape[1] >= 3:
                index.feature_types = table[2].to_numpy(str)
        else:
            peaks = with_gz(path, "peaks.bed")
            if peaks is None:
                raise PrepareError(f"no features.tsv[.gz], genes.tsv[.gz] or peaks.bed in {path}")
            table = read_tsv(peaks, [0, 1, 2])
            index.feature_ids = (table[0] + ":" + table[1] + "-" + table[2]).to_numpy(str)
            index.feature_names = index.feature_ids
    return index


@dataclass
class Sums:
    per_barcode: np.ndarray           # UMIs per barcode, all features
    per_feature: np.ndarray           # UMIs per feature, all barcodes, or None
    per_barcode_analysed: np.ndarray  # UMIs per barcode over the features CellBender analyses, or None


def h5_sums(path, analysed, per_feature):
    """UMI sums of a 10x HDF5 matrix (features x barcodes, CSC), CHUNK entries at a time. Feature
    indices are read only when per-feature sums or the analysed features are needed."""
    with h5py.File(path, "r") as h5:
        group = matrix_group(h5)
        indptr = group["indptr"][:].astype(np.int64)
        n_features, n_barcodes = int(group["shape"][0]), len(indptr) - 1
        sums = Sums(np.zeros(n_barcodes), np.zeros(n_features) if per_feature else None,
                    np.zeros(n_barcodes) if analysed is not None else None)
        nnz = int(indptr[-1])
        for start in range(0, nnz, CHUNK):
            end = min(start + CHUNK, nnz)
            first, last = np.searchsorted(indptr, [start, end - 1], side="right") - 1
            barcode = np.repeat(np.arange(first, last + 1), np.diff(np.clip(indptr[first:last + 2], start, end)))
            feature = group["indices"][start:end] if per_feature or analysed is not None else None
            data = group["data"][start:end].astype(np.float64)
            add_chunk(sums, barcode, feature, data, analysed)
    return sums


def mtx_sums(folder, analysed, per_feature):
    """UMI sums of a MatrixMarket matrix (features x barcodes)."""
    path = with_gz(folder, "matrix.mtx")
    with (gzip.open if path.suffix == ".gz" else open)(path, "rt") as f:
        line = f.readline()
        while line.startswith("%"):
            line = f.readline()
        n_features, n_barcodes = (int(n) for n in line.split()[:2])
        sums = Sums(np.zeros(n_barcodes), np.zeros(n_features) if per_feature else None,
                    np.zeros(n_barcodes) if analysed is not None else None)
        for chunk in pd.read_csv(f, sep=r"\s+", header=None, usecols=[0, 1, 2], chunksize=CHUNK // 2):
            feature, barcode = chunk[0].to_numpy() - 1, chunk[1].to_numpy() - 1
            add_chunk(sums, barcode, feature, chunk[2].to_numpy(np.float64), analysed)
    return sums


def add_chunk(sums, barcode, feature, data, analysed):
    sums.per_barcode += np.bincount(barcode, weights=data, minlength=len(sums.per_barcode))
    if sums.per_feature is not None:
        sums.per_feature += np.bincount(feature, weights=data, minlength=len(sums.per_feature))
    if analysed is not None:
        sums.per_barcode_analysed += np.bincount(barcode, weights=data * analysed[feature],
                                                 minlength=len(sums.per_barcode))


# ------------------------------------------------------------------------------------------------
# Input layouts


@dataclass
class Unit:
    """A set of droplets the mapper preset handles on its own: one sample, or one emulsion."""
    name: str
    called_cells: int
    suffixes: set = None  # probe barcodes (Flex) whose raw barcodes belong to this unit; None = all


@dataclass
class Layout:
    name: str
    description: str
    raw: Path                                     # .h5 file or .mtx folder CellBender reads
    filtered: list = field(default_factory=list)  # the mapper's filtered matrices (.h5 or folders)
    units: list = field(default_factory=list)     # mapper preset units; empty without mapper output


def filtered_matrix(folder, *names):
    """A filtered matrix in folder: the .h5 when there is one, else the folder."""
    for name in names:
        if (folder / f"{name}.h5").is_file():
            return folder / f"{name}.h5"
        if (folder / name).is_dir():
            return folder / name
    return None


def raw_matrix(folder, name):
    """A raw matrix in folder: the .h5 when there is one, else the .mtx folder."""
    if (folder / f"{name}.h5").is_file():
        return folder / f"{name}.h5"
    if (folder / name).is_dir():
        return folder / name
    return None


def probe_barcode(barcode):
    """The probe barcode of a Flex barcode (GEM barcode + probe barcode, then -1), or ''."""
    return barcode.split("-")[0][16:]


def flex_sample_unit(name, filtered):
    barcodes = read_index(filtered, features=False).barcodes
    return Unit(name, len(barcodes), {probe_barcode(b) for b in barcodes})


def detect_layout(path, starsolo_mapper):
    """Work out what kind of input path is, and where its raw and filtered matrices are."""
    if path.is_dir() and (path / "outs").is_dir():
        path = path / "outs"

    if path.is_file():
        if path.suffix == ".h5":
            return Layout("unknown_h5", f"{path} is an .h5 file", path)
        raise PrepareError(f"{path} is neither a folder nor an .h5 file. Check the manual for the inputs the pipeline accepts.")
    if not path.is_dir():
        raise PrepareError(f"{path} does not exist")

    # Cell Ranger multi, all samples together
    if (path / "multi").is_dir():
        return multi_layout(path)

    # One sample of a Cell Ranger multi run: its per_sample_outs/<sample> folder, or the count folder in it
    for count in (path / "count", path):
        raw = raw_matrix(count, "sample_raw_feature_bc_matrix")
        if raw is not None:
            filtered = filtered_matrix(count, "sample_filtered_feature_bc_matrix")
            sample = (count.parent if count.name == "count" else count).name
            units = [flex_sample_unit(sample, filtered)] if filtered else []
            return Layout("cellranger_multi_sample",
                          f"{path} holds one sample of a Cell Ranger multi (Flex) run", raw,
                          [filtered] if filtered else [], units)
        if filtered_matrix(count, "sample_filtered_feature_bc_matrix", "sample_feature_bc_matrix"):
            raise PrepareError(
                f"{path} holds one sample of a Cell Ranger multi run with only its called cells and no raw "
                "matrix (CellPlex demultiplexes cells, not droplets). Give the multi run's outs/ folder instead.")

    if (path / "raw_peak_bc_matrix.h5").is_file():
        return mapper_layout("cellranger-atac", f"{path} holds Cell Ranger ATAC output",
                             path / "raw_peak_bc_matrix.h5", filtered_matrix(path, "filtered_peak_bc_matrix"))
    if (path / "atac_fragments.tsv.gz").is_file() and (path / "filtered_feature_bc_matrix.h5").is_file():
        return mapper_layout("cellranger-arc", f"{path} holds Cell Ranger ARC output",
                             raw_matrix(path, "raw_feature_bc_matrix"), filtered_matrix(path, "filtered_feature_bc_matrix"))
    if (path / "filtered_feature_bc_matrix.h5").is_file() and (path / "raw_feature_bc_matrix.h5").is_file():
        return mapper_layout("cellranger_count", f"{path} holds Cell Ranger count output",
                             path / "raw_feature_bc_matrix.h5", filtered_matrix(path, "filtered_feature_bc_matrix"))
    if (path / "output").is_dir():
        solo = path / "output" / starsolo_mapper
        if not (solo / "raw").is_dir():
            found = sorted(p.name for p in (path / "output").iterdir() if (p / "raw").is_dir())
            raise PrepareError(f"{path} holds STARsolo output, but not for {starsolo_mapper} "
                               f"(found: {', '.join(found) or 'none'}). Set --starsolo_mapper.")
        return mapper_layout("starsolo", f"{path} holds STARsolo output ({starsolo_mapper})",
                             solo / "raw", solo / "filtered" if (solo / "filtered").is_dir() else None)
    if with_gz(path, "matrix.mtx") and with_gz(path, "barcodes.tsv") and with_gz(path, "features.tsv", "genes.tsv"):
        return Layout("unknown_mtx", f"{path} is an .mtx folder", path)
    raise PrepareError(f"{path} does not have a structure the pipeline recognises. Check the manual for the inputs it accepts.")


def mapper_layout(name, description, raw, filtered):
    units = []
    if filtered is not None:
        units = [Unit(name, len(read_index(filtered, features=False).barcodes))]
    return Layout(name, description, raw, [filtered] if filtered else [], units)


def multi_layout(path):
    """Cell Ranger multi with all samples in one raw matrix."""
    multi = path / "multi"
    raw = raw_matrix(multi / "count", "raw_feature_bc_matrix")
    if raw is None:
        raise PrepareError(f"{multi}/count has no raw_feature_bc_matrix[.h5]")
    samples = sorted(p for p in (multi / "per_sample_outs").glob("*") if (p / "count").is_dir())
    filtered = {s.name: filtered_matrix(s / "count", "sample_filtered_feature_bc_matrix", "sample_feature_bc_matrix")
                for s in samples}
    filtered = {name: f for name, f in filtered.items() if f is not None}
    flex = any(raw_matrix(s / "count", "sample_raw_feature_bc_matrix") for s in samples)

    if flex:
        # Each sample has its own probe barcode, so its own droplets in the raw matrix
        units = [flex_sample_unit(name, f) for name, f in filtered.items()]
        description = f"{path} holds a Cell Ranger multi (Flex) run of {len(units)} samples"
    else:
        # CellPlex and singleplex: one emulsion. Cell Ranger's cell calls include the cells
        # no sample was assigned to, which the per-sample folders leave out
        table = multi / "multiplexing_analysis" / "assignment_confidence_table.csv"
        columns = pd.read_csv(table, nrows=0).columns if table.is_file() else []
        column = next((name for name in ("Barcodes", "Barcode", "barcode") if name in columns), None)
        if column:
            called = pd.read_csv(table, usecols=[column])[column].nunique()
        else:
            called = len(set().union(*(set(read_index(f, features=False).barcodes) for f in filtered.values())))
        units = [Unit("all samples", called)] if filtered or column else []
        description = f"{path} holds a Cell Ranger multi run of {len(samples)} sample(s)"
    return Layout("cellranger_multi", description, raw, list(filtered.values()), units)


# ------------------------------------------------------------------------------------------------
# Numbers


def preset_droplets(expected):
    droplets = expected + 2000
    if expected >= 20000:
        droplets += 8000
    elif expected >= 2000:
        droplets += 3000
    return droplets


def preset_threshold(umi_desc, droplets):
    """umi_desc: UMI counts of the unit's barcodes with any UMIs, highest first."""
    rank_umi = max(int(umi_desc[PRESET_EMPTY_RANK - 1]), PRESET_MIN_UMI) if len(umi_desc) >= PRESET_EMPTY_RANK else PRESET_MIN_UMI
    above_min = int((umi_desc > PRESET_MIN_UMI).sum())
    return rank_umi if above_min < droplets + PRESET_EMPTY_RANK else PRESET_MIN_UMI


def mapper_preset(layout, per_barcode, raw_barcodes, given_cells):
    """Expected cells, total droplets and low-count threshold from the mapper's cell calls, summed over
    the layout's units. A given cell number is shared out between the units in proportion."""
    has_umis = per_barcode > 0
    flex = any(unit.suffixes is not None for unit in layout.units)
    suffixes = np.array([probe_barcode(b) for b in raw_barcodes]) if flex else None

    units = []
    for unit in layout.units:
        selected = has_umis if unit.suffixes is None else has_umis & np.isin(suffixes, list(unit.suffixes))
        umi_desc = np.sort(per_barcode[selected])[::-1]
        units.append((unit, umi_desc, min(unit.called_cells, int((umi_desc > PRESET_CELL_UMI).sum()))))

    total = sum(expected for _, _, expected in units)
    if given_cells is not None:
        shares = [given_cells] if len(units) == 1 else [
            int(round(given_cells * expected / total)) if total else given_cells // len(units) for _, _, expected in units]
    else:
        shares = [expected for _, _, expected in units]

    droplets = [preset_droplets(share) for share in shares]
    thresholds = [preset_threshold(umi_desc, d) for (_, umi_desc, _), d in zip(units, droplets)]
    detail = [f"{unit.name}: {unit.called_cells} called, {expected} expected, {d} droplets, threshold {t}"
              for (unit, _, expected), d, t in zip(units, droplets, thresholds)]
    return total, sum(droplets), min(thresholds), detail


def cellbender_estimate(umi_counts, expected_cells, total_droplets, low_count_threshold):
    """What CellBender 0.3 would use, from its own code in cellbender_priors.py."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.dont_write_bytecode = True  # no __pycache__ next to the module's scripts
    import cellbender_priors
    logging.getLogger("cellbender").setLevel(logging.WARNING)

    threshold = low_count_threshold if low_count_threshold is not None else cellbender_priors.consts.LOW_UMI_CUTOFF
    priors = cellbender_priors.get_priors(umi_counts=umi_counts, low_count_threshold=threshold)
    cellbender_priors.apply_user_values(umi_counts, priors, expected_cells, total_droplets)
    return (int(priors["expected_cells"]), int(priors["total_droplets"]),
            int(cellbender_priors.low_count_cutoff(priors, threshold)), priors)


# ------------------------------------------------------------------------------------------------


EXCLUDED_COLUMNS = ["index", "id", "name", "type", "umis", "reason", "decision"]


def write_excluded(path, raw_index, listed, outside, excluded, per_feature, source):
    """Write every feature left out of the CellBender model to path, one row each in raw matrix order.

    reason: an excluded feature type, or missing from the mapper's filtered matrix (source); the
    type wins when both apply. decision: explicit when CellBender is told to leave the feature out
    (its type is excluded, or it is outside source and has counts), implicit when it is not (outside
    source with no counts: CellBender drops all-zero features by itself).
    """
    rows = np.flatnonzero(listed)
    umis = per_feature[rows].astype(np.int64) if len(rows) else np.zeros(0, dtype=np.int64)
    explicit = excluded[rows] | (umis > 0)
    table = pd.DataFrame({
        "index": rows,
        "id": raw_index.feature_ids[rows],
        "name": raw_index.feature_names[rows],
        "type": raw_index.feature_types[rows] if raw_index.feature_types is not None else "",
        "umis": umis,
        "reason": np.where(excluded[rows], "excluded feature type", f"not in {source}"),
        "decision": np.where(explicit, "explicit", "implicit"),
    }, columns=EXCLUDED_COLUMNS)
    path.parent.mkdir(parents=True, exist_ok=True)
    table.to_csv(path, index=False)
    if len(rows):
        reasons = ", ".join(f"{count} {reason}" for reason, count in table["reason"].value_counts().items())
        print(f"INFO: left out of the model: {len(rows)} features ({reasons}), {int(explicit.sum())} explicit "
              f"and {len(rows) - int(explicit.sum())} implicit; listed in {path}")
    else:
        print(f"INFO: left out of the model: no features; {path} has only its header")


def gzip_mtx(folder, workdir):
    """CellBender reads only gzipped .mtx folders: write a gzipped copy when any file is not."""
    files = [with_gz(folder, "matrix.mtx"), with_gz(folder, "barcodes.tsv"), with_gz(folder, "features.tsv", "genes.tsv")]
    if all(f.suffix == ".gz" for f in files):
        return folder
    target = workdir / "raw_matrix"
    target.mkdir(parents=True, exist_ok=True)
    for source in files:
        name = source.name if source.suffix == ".gz" else f"{source.name}.gz"
        if source.suffix == ".gz":
            shutil.copyfile(source, target / name)
        else:
            with open(source, "rb") as fin, gzip.open(target / name, "wb", compresslevel=1) as fout:
                shutil.copyfileobj(fin, fout, 16 * 1024 * 1024)
    print(f"INFO: {folder} is not gzipped, as CellBender needs: using a gzipped copy in {target}")
    return target


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", required=True, type=Path, help="mapper output folder, .h5 file or .mtx folder")
    parser.add_argument("--cellbender-version", required=True, choices=["0.2", "0.3"])
    parser.add_argument("--starsolo-mapper", default="GeneFull", help="STARsolo output type (default: GeneFull)")
    parser.add_argument("--expected-cells", type=int, help="given for the sample")
    parser.add_argument("--total-droplets", type=int, help="given for the sample")
    parser.add_argument("--low-count-threshold", type=int, help="given for the sample")
    parser.add_argument("--exclude-features", nargs="*", default=[], help="feature types CellBender excludes")
    parser.add_argument("--preset", choices=["auto", "mapper", "off"], default="auto",
                        help="what fills the numbers not given: CellBender's estimate (auto, the default), "
                             "the mapper's cell calls (mapper) or nothing (off)")
    parser.add_argument("--keep-all-features", action="store_true",
                        help="do not ignore the features missing from the mapper's filtered matrix")
    parser.add_argument("--workdir", type=Path, default=Path("prepared"), help="folder for prepared files")
    parser.add_argument("--args-file", type=Path, default=Path("cellbender.args"))
    parser.add_argument("--excluded-file", type=Path, default=Path("excluded_features.csv"),
                        help="CSV of every feature left out of the model, with its UMIs and why")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    values = {"expected_cells": args.expected_cells, "total_droplets": args.total_droplets,
              "low_count_threshold": args.low_count_threshold}
    missing = [key.replace("_", " ") for key in ("expected_cells", "total_droplets") if values[key] is None]
    if args.preset == "off" and missing:
        raise PrepareError(f"--preset off uses only the values given, and {' and '.join(missing)} "
                           f"{'is' if len(missing) == 1 else 'are'} not given. Give {'it' if len(missing) == 1 else 'them'}, "
                           f"or use --preset auto "
                           f"(CellBender's estimate) or --preset mapper (the mapper's cell calls).")

    layout = detect_layout(args.input, args.starsolo_mapper)
    print(f"INFO: {layout.description}")
    print(f"INFO: raw matrix: {layout.raw}")

    mapper = args.preset == "mapper"
    if mapper and not layout.units:
        raise PrepareError(f"the mapper preset needs the mapper's cell calls, which {args.input} does not have "
                           f"({layout.name}). Pass the whole Cell Ranger/STARsolo folder, give cells and droplets, "
                           f"or use --preset auto.")

    # Features: keep those in the mapper's filtered matrix (or a Flex .h5's probe set)
    # Raw barcodes are only needed to tell Flex samples apart by their probe barcodes
    flex_units = mapper and any(unit.suffixes is not None for unit in layout.units)
    raw_index = read_index(layout.raw, barcodes=flex_units)
    n_features = len(raw_index.feature_ids)
    outside, source = np.zeros(n_features, dtype=bool), None
    if not args.keep_all_features:
        if layout.filtered:
            keep = set()
            for filtered in layout.filtered:
                keep.update(read_index(filtered, barcodes=False).feature_ids)
            keep_mask = np.isin(raw_index.feature_ids, list(keep))
            source = "the filtered matrix"
        elif raw_index.target_sets is not None:
            keep_mask = np.zeros(n_features, dtype=bool)
            keep_mask[raw_index.target_sets] = True
            source = "the probe set"
        else:
            keep_mask, source = None, None
        if keep_mask is not None and not keep_mask.any():
            print(f"WARN: no feature of {source} is in the raw matrix; not ignoring any feature")
        elif keep_mask is not None:
            outside = ~keep_mask

    excluded = np.zeros(n_features, dtype=bool)
    if args.exclude_features and raw_index.feature_types is not None:
        excluded = np.isin(raw_index.feature_types, args.exclude_features)
    listed = outside | excluded  # every feature left out of the model, for --excluded-file

    # CellBender 0.3 estimates what it is not given; for 0.2 the copy of its code does it here
    estimate = args.preset == "auto" and args.cellbender_version == "0.2" and None in values.values()
    sums = None
    if mapper or estimate or listed.any():
        analysed = (~outside & ~excluded).astype(np.float64) if estimate else None
        sums_of = h5_sums if layout.raw.is_file() else mtx_sums
        sums = sums_of(layout.raw, analysed, per_feature=listed.any())

    # Features outside the filtered matrix are passed only when they have counts: CellBender drops
    # all-zero features by itself
    ignored = np.flatnonzero(outside & (sums.per_feature > 0)) if outside.any() else np.array([], dtype=int)
    if outside.any():
        print(f"INFO: features: {n_features} in the raw matrix, {n_features - outside.sum()} in {source}; "
              f"ignored {len(ignored)} features outside it that have counts "
              f"({int(sums.per_feature[ignored].sum())} UMIs); {outside.sum() - len(ignored)} more have no "
              f"counts, which CellBender drops itself")
    else:
        print(f"INFO: features: {n_features} in the raw matrix, none ignored")
    write_excluded(args.excluded_file, raw_index, listed, outside, excluded,
                   sums.per_feature if listed.any() else None, source)

    # Cells, droplets, threshold: a given value always; the preset fills only the ones not given
    sources = {key: "given" for key, value in values.items() if value is not None}

    if mapper:
        cells, droplets, threshold, detail = mapper_preset(layout, sums.per_barcode, raw_index.barcodes,
                                                          values["expected_cells"])
        for line in detail:
            print(f"INFO: mapper preset, {line}")
        for key, value in zip(values, (cells, droplets, threshold)):
            if values[key] is None:
                values[key], sources[key] = value, "mapper preset"

    if estimate:
        cells, droplets, threshold, priors = cellbender_estimate(
            sums.per_barcode_analysed, values["expected_cells"], values["total_droplets"], values["low_count_threshold"])
        print(f"INFO: CellBender 0.3 estimate: prior on cell counts {int(priors['cell_counts'])}, "
              f"on empty droplet counts {int(priors['empty_counts'])}")
        for key, value in zip(values, (cells, droplets, threshold)):
            if values[key] is None:
                values[key], sources[key] = value, "CellBender 0.3 estimate"

    raw = gzip_mtx(layout.raw, args.workdir) if layout.raw.is_dir() else layout.raw
    cellbender_args = ["--input", str(raw)]
    for key, flag in (("expected_cells", "--expected-cells"), ("total_droplets", "--total-droplets-included"),
                      ("low_count_threshold", "--low-count-threshold")):
        if values[key] is not None:
            cellbender_args += [flag, str(values[key])]
            print(f"INFO: {key.replace('_', ' ')}: {values[key]} ({sources[key]})")
        elif args.preset == "off":
            print(f"INFO: {key.replace('_', ' ')}: CellBender default "
                  f"({CELLBENDER_LOW_COUNT_DEFAULT[args.cellbender_version]})")
        else:
            print(f"INFO: {key.replace('_', ' ')}: left to CellBender")
    if len(ignored):
        cellbender_args += ["--ignore-features" if args.cellbender_version == "0.3" else "--blacklist-genes"]
        cellbender_args += [str(i) for i in ignored]

    args.args_file.write_text("\n".join(cellbender_args) + "\n")


if __name__ == "__main__":
    try:
        main()
    except PrepareError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(INPUT_ERROR)
