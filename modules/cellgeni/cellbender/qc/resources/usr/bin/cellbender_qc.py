#!/usr/bin/env python3
"""Collect QC statistics and plots from CellBender remove-background outputs.

Reads every per-sample folder in DIR (CellBender 0.2 or 0.3 output), and writes:
  cellbender_qc_summary.tsv    one row per sample, most problematic samples first
  cellbender_qc_report.pdf     summary table, training curves, cell calling, latent PCA, soup fractions, gene removal
  multiqc/                     the same data as MultiQC custom content
"""
import argparse
import glob
import gzip
import json
import math
import os
import re
import sys

import h5py
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib.backends.backend_pdf import PdfPages  # noqa: E402

plt.rcParams.update({"axes.spines.top": False, "axes.spines.right": False, "font.size": 8})

# Numbers that follow these phrases in the CellBender log (both 0.2 and 0.3 wordings)
LOG_PATTERNS = {
    "prior_empty_count": r"Prior on counts (?:in|for) empty droplets is ",
    "prior_cell_count": r"Prior on counts for cells is ",
    "barcode_low_thr": r"Excluding barcodes with counts below ",
    "posterior_reg_factor": r"Optimal posterior regularization factor = ",
    "largest_empty_count": r"Largest surely-empty droplet has ",
    "genes_used": r"Including ",
    "probable_cells": r"Using ",
    "additional_cells": r"probable cell barcodes, plus an additional ",
    "probable_empty": r" barcodes, and ",
}
NUMBER = r"(\d+\.?\d*)"
COLUMNS = [
    "sample_id", "cellbender_version", "epochs", "final_test_elbo_minus_max", "test_minus_train_elbo",
    "cellbender_cells", "top10umi_min_cell_prob", "mean_soup_fraction", "median_soup_fraction", "top_ambient_genes",
    *LOG_PATTERNS, "input",
]
GRID_ROWS, GRID_COLS = 4, 6
CELL_PROB = 0.5
TOP_GENES = 5
SOUP_BINS = 50
CHUNK = 20_000_000  # matrix entries read at once


def log(msg, verbose=True):
    if verbose:
        print(msg, file=sys.stderr)


def parse_log(path):
    """Training curves and summary numbers from a CellBender log."""
    with open(path) as f:
        lines = f.read().splitlines()

    train, test = {}, {}
    other = []
    for line in lines:
        m = re.search(r"\[epoch (\d+)\].*average (training|test) loss: (-?\d+\.?\d*)", line)
        if m:
            # Loss is the negative ELBO
            (train if m.group(2) == "training" else test)[int(m.group(1))] = -float(m.group(3))
        else:
            other.append(line)

    info = {}
    for key, pattern in LOG_PATTERNS.items():
        values = [float(m.group(1)) for line in other for m in [re.search(pattern + NUMBER, line)] if m]
        info[key] = values[0] if values else None

    command = next((line for line in lines if "cellbender remove-background" in line), "")
    tokens = command.split()
    info["input"] = tokens[tokens.index("--input") + 1] if "--input" in tokens else None
    output = tokens[tokens.index("--output") + 1] if "--output" in tokens else ""
    if info["input"] and not os.path.isabs(info["input"]):
        # A relative input is relative to where CellBender ran: the log folder minus the folder part of --output
        log_dir, out_dir = os.path.dirname(os.path.realpath(path)), os.path.dirname(output).strip("/")
        run_dir = log_dir[: -len(out_dir)] if out_dir and log_dir.endswith(out_dir) else log_dir
        info["input"] = os.path.normpath(os.path.join(run_dir, info["input"]))
    return {"train": train, "test": test, "info": info}


def sparse_sums(group, cells=None):
    """Total UMI per barcode, and UMI per feature over the barcodes in the mask `cells`, from a features x
    barcodes CSC matrix stored as indices/indptr/data/shape. Reads CHUNK entries at a time."""
    indptr = group["indptr"][:]
    nrows, ncols = int(group["shape"][0]), len(indptr) - 1
    per_barcode = np.zeros(ncols)
    per_feature = np.zeros(nrows) if cells is not None else None
    for start in range(0, int(indptr[-1]), CHUNK):
        end = min(start + CHUNK, int(indptr[-1]))
        first, last = np.searchsorted(indptr, [start, end - 1], side="right") - 1
        col = np.repeat(np.arange(first, last + 1), np.diff(np.clip(indptr[first:last + 2], start, end)))
        data = group["data"][start:end].astype(float)
        per_barcode += np.bincount(col, weights=data, minlength=ncols)
        if cells is not None:
            keep = cells[col]
            per_feature += np.bincount(group["indices"][start:end][keep], weights=data[keep], minlength=nrows)
    return per_barcode, per_feature


def mtx_sums(path, cells):
    """Same as sparse_sums for a features x barcodes MatrixMarket file."""
    with (gzip.open if path.endswith(".gz") else open)(path, "rt") as f:
        line = f.readline()
        while line.startswith("%"):
            line = f.readline()
        nrows, ncols = (int(n) for n in line.split()[:2])
        per_barcode, per_feature = np.zeros(ncols), np.zeros(nrows)
        for chunk in pd.read_csv(f, sep=" ", header=None, usecols=[0, 1, 2], chunksize=CHUNK // 2):
            row, col = chunk[0].to_numpy() - 1, chunk[1].to_numpy() - 1
            value = chunk[2].to_numpy(float)
            per_barcode += np.bincount(col, weights=value, minlength=ncols)
            keep = cells[col]
            per_feature += np.bincount(row[keep], weights=value[keep], minlength=nrows)
    return per_barcode, per_feature


def decode(values):
    values = np.asarray(values)
    if values.dtype.kind == "S":
        return values.astype(str)
    return np.array([v.decode() if isinstance(v, bytes) else v for v in values])


def optional(group, name):
    return group[name][:] if name in group else None


def barcode_positions(barcodes, wanted, idx):
    """Position of each wanted barcode in barcodes, -1 if absent. CellBender keeps the input barcode order,
    so its own indices idx are usually the answer."""
    if len(idx) and len(barcodes) > idx.max() and np.array_equal(barcodes[idx], wanted):
        return idx
    order = np.argsort(barcodes)
    pos = order[np.clip(np.searchsorted(barcodes, wanted, sorter=order), 0, len(barcodes) - 1)]
    return np.where(barcodes[pos] == wanted, pos, -1)


def read_input(path, idx, barcodes, cells):
    """Raw UMI per analysed barcode, and raw UMI per feature over cells, from the CellBender input."""
    if path and os.path.isfile(path) and path.endswith(".h5"):
        with h5py.File(path, "r") as h5:
            g = h5["matrix"] if "matrix" in h5 else h5[list(h5.keys())[0]]
            input_barcodes = decode(g["barcodes"][:])
            pos = barcode_positions(input_barcodes, barcodes, idx)
            in_cells = np.zeros(len(input_barcodes), dtype=bool)
            in_cells[pos[cells & (pos >= 0)]] = True
            per_barcode, per_feature = sparse_sums(g, in_cells)
    elif path and os.path.isdir(path):
        mtx = glob.glob(os.path.join(path, "matrix.mtx*"))
        bcs = glob.glob(os.path.join(path, "barcodes.tsv*"))
        if not mtx or not bcs:
            return None
        input_barcodes = pd.read_csv(bcs[0], sep="\t", header=None, usecols=[0], dtype=str)[0].to_numpy(str)
        pos = barcode_positions(input_barcodes, barcodes, idx)
        in_cells = np.zeros(len(input_barcodes), dtype=bool)
        in_cells[pos[cells & (pos >= 0)]] = True
        per_barcode, per_feature = mtx_sums(mtx[0], in_cells)
    else:
        return None
    return np.where(pos >= 0, per_barcode[pos], np.nan), per_feature


def parse_h5(path):
    """Cell probabilities, learning curve, latent encoding, ambient profile and UMI after CellBender, per
    analysed barcode and per feature over cells, from the output h5."""
    r = {}
    with h5py.File(path, "r") as h5:
        if "droplet_latents" in h5:  # CellBender 0.3
            r["version"] = "0.3"
            latents, g, meta = h5["droplet_latents"], h5["matrix"], h5["metadata"]
            r["cell_probability"] = latents["cell_probability"][:]
            r["z"] = optional(latents, "gene_expression_encoding")
            r["soup_fraction"] = optional(latents, "background_fraction")
            r["ambient"] = optional(h5["global_latents"], "ambient_expression") if "global_latents" in h5 else None
            idx = latents["barcode_indices_for_latents"][:]
            r["train"] = dict(zip(meta["learning_curve_train_epoch"][:].astype(int), meta["learning_curve_train_elbo"][:]))
            r["test"] = dict(zip(meta["learning_curve_test_epoch"][:].astype(int), meta["learning_curve_test_elbo"][:]))
            r["barcodes"] = decode(meta["barcodes_analyzed"][:] if "barcodes_analyzed" in meta else g["barcodes"][:][idx])
        else:  # CellBender 0.2: a single top-level group
            r["version"] = "0.2"
            g = h5[list(h5.keys())[0]]
            r["cell_probability"] = g["latent_cell_probability"][:]
            r["z"] = optional(g, "latent_gene_encoding")
            r["ambient"] = optional(g, "ambient_expression")
            idx = g["barcode_indices_for_latents"][:]
            elbo = g["training_elbo_per_epoch"][:]
            r["train"] = dict(zip(range(1, len(elbo) + 1), elbo))
            r["test"] = dict(zip(g["test_epoch"][:].astype(int), g["test_elbo"][:]))
            r["barcodes"] = decode(g["barcodes"][:][idx])
        r["idx"] = idx
        r["feature_names"] = decode(g["features"]["name"][:] if "features" in g else g["gene_names"][:])
        cells = np.zeros(len(g["indptr"]) - 1, dtype=bool)
        cells[idx[r["cell_probability"] > CELL_PROB]] = True
        per_barcode, r["gene_corrected"] = sparse_sums(g, cells)
        r["corrected_umi"] = per_barcode[idx]
    return r


def process_sample(sample_dir, mode, verbose):
    logs = glob.glob(os.path.join(sample_dir, "**", "*.log"), recursive=True)
    if len(logs) != 1:
        log(f"WARN: {len(logs)} log files in {sample_dir}, expected one; skipped", verbose)
        return None
    log_file = logs[0]
    h5_file = log_file[: -len(".log")] + ".h5"
    if not os.path.exists(h5_file):
        log(f"ERROR: {h5_file} does not exist; skipped", True)
        return None

    s = parse_log(log_file)
    info = s["info"]
    test_epochs = sorted(s["test"])
    if test_epochs:
        last = test_epochs[-1]
        info["final_test_elbo_minus_max"] = s["test"][last] - max(s["test"].values())
        info["test_minus_train_elbo"] = s["test"][last] - s["train"].get(last, np.nan)
    info["epochs"] = max(s["train"]) if s["train"] else None

    # Only CellBender 0.3 writes a metrics file; the h5 layout confirms this in modes 2 and 3
    info["cellbender_version"] = "0.3" if os.path.exists(log_file[: -len(".log")] + "_metrics.csv") else "0.2"

    barcodes_csv = log_file[: -len(".log")] + "_cell_barcodes.csv"
    if os.path.exists(barcodes_csv):
        with open(barcodes_csv) as f:
            info["cellbender_cells"] = sum(1 for line in f if line.strip())

    if mode > 1:
        h5 = parse_h5(h5_file)
        info["cellbender_version"] = h5["version"]
        s["train"], s["test"] = h5["train"], h5["test"]
        p = s["cell_probability"] = h5["cell_probability"]
        cells = p > CELL_PROB
        s["z"] = h5["z"]
        if h5["ambient"] is not None:
            top = np.argsort(h5["ambient"])[::-1][:TOP_GENES]
            info["top_ambient_genes"] = ",".join(h5["feature_names"][top])
        if mode > 2:
            raw = read_input(info["input"], h5["idx"], h5["barcodes"], cells)
            if raw is None:
                log(f"WARN: input {info['input']} of {sample_dir} is not readable, UMI curve and gene removal skipped", verbose)
            else:
                s["umi"], gene_raw = raw
                if len(gene_raw) == len(h5["gene_corrected"]):
                    s["gene_raw"], s["gene_corrected"], s["gene_names"] = gene_raw, h5["gene_corrected"], h5["feature_names"]
                else:
                    log(f"WARN: input and output of {sample_dir} have different features, gene removal skipped", verbose)
            soup, umi = h5.get("soup_fraction"), s.get("umi")
            with np.errstate(divide="ignore", invalid="ignore"):
                if soup is None and umi is not None:  # CellBender 0.2 does not store the soup fraction
                    soup = (umi - h5["corrected_umi"]) / umi
                if soup is not None and umi is None:  # invert background_fraction = (raw - out) / (raw + 0.001)
                    umi = (h5["corrected_umi"] + 0.001 * soup) / (1 - soup)
            if soup is not None:
                s["raw_umi"], s["soup_fraction"] = umi[cells], soup[cells]
                info["mean_soup_fraction"] = float(np.nanmean(s["soup_fraction"]))
                info["median_soup_fraction"] = float(np.nanmedian(s["soup_fraction"]))
        order = np.argsort(-s["umi"], kind="stable") if "umi" in s else np.arange(len(p))
        info["top10umi_min_cell_prob"] = float(np.min(p[order][:10]))
    return s


def sort_key(item):
    """Most problematic samples first: low cell probability among top barcodes, then the largest ELBO drop."""
    info = item[1]["info"]
    top10 = info.get("top10umi_min_cell_prob")
    elbo = info.get("final_test_elbo_minus_max")
    return (top10 is not None and top10 > 0.5, elbo if elbo is not None else math.inf)


def fmt(value):
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return "NA"
    if isinstance(value, float):
        return f"{value:.4g}"
    return str(value)


def write_summary(samples, path):
    with open(path, "w") as f:
        f.write("\t".join(COLUMNS) + "\n")
        for sid, s in samples:
            f.write("\t".join(fmt(sid if c == "sample_id" else s["info"].get(c)) for c in COLUMNS) + "\n")


def grid_pages(samples, plot, pdf, title):
    """Plot one panel per sample, up to GRID_ROWS x GRID_COLS panels per page."""
    per_page = GRID_ROWS * GRID_COLS
    figures = []
    for start in range(0, len(samples), per_page):
        page = samples[start:start + per_page]
        ncols = min(GRID_COLS, len(page))
        nrows = math.ceil(len(page) / ncols)
        fig, axes = plt.subplots(nrows, ncols, figsize=(3.5 * ncols, 3 * nrows + 0.5), squeeze=False)
        for ax, (sid, s) in zip(axes.flat, page):
            plot(ax, s)
            ax.set_title(sid, fontsize=9)
        for ax in axes.flat[len(page):]:
            ax.axis("off")
        fig.suptitle(title)
        fig.tight_layout()
        if pdf is not None:
            pdf.savefig(fig)
        figures.append(fig)
    return figures


def save_pages(figures, outdir, name):
    """Save each page as a MultiQC image, for plots MultiQC cannot draw itself, and close it."""
    for page, fig in enumerate(figures, start=1):
        fig.savefig(os.path.join(outdir, f"cellbender_{name}_{page}_mqc.png"), dpi=80)
        plt.close(fig)


def not_available(ax, text="not available"):
    ax.axis("off")
    ax.text(0.5, 0.5, text, ha="center", va="center", transform=ax.transAxes)


def plot_training(ax, s):
    epochs = sorted(s["train"])
    ax.plot(epochs, [s["train"][e] for e in epochs], color="tab:blue", lw=2, label="Train")
    test = sorted(s["test"])
    ax.plot(test, [s["test"][e] for e in test], color="tab:orange", lw=2, label="Test")
    ax.set_xlabel("Epoch")
    ax.set_ylabel("ELBO")
    ax.legend(loc="lower right", frameon=False, fontsize=8)


def plot_cell_calling(ax, s):
    """CellBender's own plot: UMI count by barcode rank, with the cell probability on a second axis."""
    p = s["cell_probability"]
    if "umi" in s:
        order = np.argsort(-s["umi"], kind="stable")
        ax.semilogy(s["umi"][order], color="black", lw=1)
        ax.axvline(np.sum(p > CELL_PROB), color="grey", ls="--", lw=0.8)
        ax.set_xlabel("Barcode rank by UMI count")
        ax.set_ylabel("UMI counts")
        prob_ax = ax.twinx()
        prob_ax.spines["right"].set_visible(True)
    else:  # without the input only CellBender's own barcode order, close to the UMI order, is known
        order = np.arange(len(p))
        ax.set_xlabel("Barcode index (CellBender order)")
        prob_ax = ax
    prob_ax.plot(p[order], ".", ms=2, color="red", alpha=0.3, rasterized=True)
    prob_ax.set_ylim(-0.05, 1.05)
    prob_ax.set_ylabel("Cell probability", color="red")
    prob_ax.tick_params(axis="y", colors="red")


def plot_latent_pca(ax, s):
    cells = s["cell_probability"] > CELL_PROB
    if s.get("z") is None or cells.sum() < 3:
        not_available(ax)
        return
    z = s["z"][cells] - s["z"][cells].mean(axis=0)
    # Top eigenvectors of the small covariance matrix: much faster than an SVD of z with the same result
    pcs = z @ np.linalg.eigh(z.T @ z)[1][:, ::-1][:, :2]
    if "soup_fraction" in s:
        soup = s["soup_fraction"] * 100
        order = np.argsort(soup)  # most soup on top
        points = ax.scatter(pcs[order, 0], pcs[order, 1], c=soup[order], s=2, cmap="viridis", vmin=0,
                            vmax=max(np.nanpercentile(soup, 99), 1), edgecolors="none", rasterized=True)
        plt.colorbar(points, ax=ax, label="soup %", extend="max")
    else:
        ax.scatter(pcs[:, 0], pcs[:, 1], s=2, color="black", alpha=0.3, edgecolors="none", rasterized=True)
    ax.set_xlabel("PC 1")
    ax.set_ylabel("PC 2")


def plot_soup_fraction(ax, s):
    if "soup_fraction" not in s:
        not_available(ax)
        return
    x = np.log10(s["raw_umi"] + 1)
    y = s["soup_fraction"] * 100
    ok = np.isfinite(x) & np.isfinite(y)
    _, _, _, image = ax.hist2d(x[ok], y[ok], bins=100, range=[[x[ok].min(), x[ok].max()], [0, 100]],
                               cmap="viridis", norm=matplotlib.colors.LogNorm(), cmin=1)
    plt.colorbar(image, ax=ax, label="# cells")
    ax.set_xlabel("log10(UMI + 1)")
    ax.set_ylabel("soup %")


def plot_soup_histogram(ax, s):
    if "soup_fraction" not in s:
        not_available(ax)
        return
    soup = s["soup_fraction"] * 100
    soup = soup[np.isfinite(soup)]
    ax.hist(np.clip(soup, 0, 100), bins=SOUP_BINS, range=(0, 100), color="tab:blue", alpha=0.7)
    ax.axvline(np.median(soup), color="black", ls="--", lw=0.8)
    ax.set_yscale("log")
    ax.set_xlabel("soup %")
    ax.set_ylabel("# cells")


def plot_gene_removal(ax, s):
    if "gene_raw" not in s:
        not_available(ax)
        return
    raw, corrected = s["gene_raw"], s["gene_corrected"]
    x, y = np.maximum(raw, 0.5), np.maximum(corrected, 0.5)  # show zeros at 0.5 on log axes
    keep = raw > 0
    ax.scatter(x[keep], y[keep], s=2, color="black", alpha=0.3, edgecolors="none", rasterized=True)
    high = x.max() * 2
    ax.plot([0.5, high], [0.5, high], color="grey", ls="--", lw=0.8)
    # The features with the most UMI removed, listed in a corner: their labels would overlap at the top right
    top = np.argsort(raw - corrected)[::-1][:TOP_GENES]
    ax.scatter(x[top], y[top], s=6, color="red")
    ax.text(0.98, 0.02, "most UMI removed\n" + "\n".join(
        f"{s['gene_names'][g]}  -{100 * (raw[g] - corrected[g]) / raw[g]:.2g}%" for g in top),
        transform=ax.transAxes, ha="right", va="bottom", fontsize=6, color="red")
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(0.4, high)
    ax.set_ylim(0.4, high)
    ax.set_xlabel("UMI in cells, raw")
    ax.set_ylabel("UMI in cells, after CellBender")


def summary_page(samples, pdf):
    shown = ["sample_id", "epochs", "final_test_elbo_minus_max", "test_minus_train_elbo", "cellbender_cells",
             "top10umi_min_cell_prob", "median_soup_fraction", "prior_cell_count", "prior_empty_count"]
    rows_per_page = 35
    for start in range(0, len(samples), rows_per_page):
        cells = [[fmt(sid if c == "sample_id" else s["info"].get(c)) for c in shown]
                 for sid, s in samples[start:start + rows_per_page]]
        fig, ax = plt.subplots(figsize=(18, 1.5 + 0.3 * len(cells)))
        ax.axis("off")
        table = ax.table(cellText=cells, colLabels=shown, loc="upper center", cellLoc="center")
        table.auto_set_font_size(False)
        table.set_fontsize(8)
        table.scale(1, 1.4)
        fig.suptitle("CellBender QC summary (most problematic samples first)")
        pdf.savefig(fig)
        plt.close(fig)


def write_multiqc(samples, mode, outdir):
    os.makedirs(outdir, exist_ok=True)
    headers = {
        "cellbender_version": {"title": "Version"},
        "epochs": {"title": "Epochs", "format": "{:,.0f}"},
        "final_test_elbo_minus_max": {"title": "Final - max test ELBO", "description": "Final test ELBO minus its maximum; strongly negative values suggest training went wrong"},
        "test_minus_train_elbo": {"title": "Test - train ELBO"},
        "cellbender_cells": {"title": "Cells", "description": "Barcodes with cell probability > 0.5", "format": "{:,.0f}"},
        "top10umi_min_cell_prob": {"title": "Top-10 min cell prob", "description": "Lowest cell probability among the 10 barcodes with most UMIs; below 0.5 is a red flag", "min": 0, "max": 1},
        "mean_soup_fraction": {"title": "Mean soup", "min": 0, "max": 1, "format": "{:,.3f}"},
        "median_soup_fraction": {"title": "Median soup", "min": 0, "max": 1, "format": "{:,.3f}"},
        "top_ambient_genes": {"title": "Top ambient genes", "description": f"The {TOP_GENES} features with the highest share of CellBender's ambient profile"},
        "prior_cell_count": {"title": "Cell prior", "hidden": True},
        "prior_empty_count": {"title": "Empty prior", "hidden": True},
        "barcode_low_thr": {"title": "Low-count threshold", "hidden": True},
        "posterior_reg_factor": {"title": "Posterior reg. factor", "hidden": True},
        "largest_empty_count": {"title": "Largest empty", "hidden": True},
        "genes_used": {"title": "Genes", "hidden": True},
        "probable_cells": {"title": "Probable cells", "hidden": True},
        "additional_cells": {"title": "Additional barcodes", "hidden": True},
        "probable_empty": {"title": "Empty droplets", "hidden": True},
    }

    def clean(value):
        return None if value is None or (isinstance(value, float) and math.isnan(value)) else value

    table = {sid: {k: clean(s["info"].get(k)) for k in headers if clean(s["info"].get(k)) is not None} for sid, s in samples}
    content = {
        "cellbender_summary_mqc.json": {
            "id": "cellbender_summary", "section_name": "CellBender summary", "plot_type": "table",
            "description": "One row per sample, from the CellBender log and output h5.",
            "pconfig": {"id": "cellbender_summary_table", "title": "CellBender summary"},
            "headers": headers, "data": table,
        },
        "cellbender_generalstats_mqc.json": {
            "id": "cellbender_generalstats", "plot_type": "generalstats",
            "headers": {k: dict(headers[k], namespace="CellBender") for k in
                        ["cellbender_cells", "top10umi_min_cell_prob", "final_test_elbo_minus_max", "median_soup_fraction"]},
            "data": {sid: {k: v for k, v in row.items() if k in
                           ["cellbender_cells", "top10umi_min_cell_prob", "final_test_elbo_minus_max", "median_soup_fraction"]}
                     for sid, row in table.items()},
        },
        "cellbender_training_mqc.json": {
            "id": "cellbender_training", "section_name": "CellBender training", "plot_type": "linegraph",
            "description": "ELBO per epoch. The test curve should rise and level off with the training curve.",
            "pconfig": {"id": "cellbender_training_plot", "title": "CellBender: ELBO per epoch", "xlab": "Epoch", "ylab": "ELBO",
                        "data_labels": [{"name": "Train", "ylab": "Train ELBO"}, {"name": "Test", "ylab": "Test ELBO"}]},
            "data": [
                {sid: {int(e): float(v) for e, v in sorted(s["train"].items())} for sid, s in samples},
                {sid: {int(e): float(v) for e, v in sorted(s["test"].items())} for sid, s in samples},
            ],
        },
    }
    if mode > 2:
        edges = np.linspace(0, 100, SOUP_BINS + 1)
        centres = (edges[:-1] + edges[1:]) / 2
        histograms = {}
        for sid, s in samples:
            if "soup_fraction" in s:
                soup = s["soup_fraction"] * 100
                counts = np.histogram(np.clip(soup[np.isfinite(soup)], 0, 100), bins=edges)[0]
                histograms[sid] = {round(float(c), 1): round(100 * float(n) / max(counts.sum(), 1), 3) for c, n in zip(centres, counts)}
        content["cellbender_soup_histogram_mqc.json"] = {
            "id": "cellbender_soup_histogram", "section_name": "CellBender soup fraction histogram", "plot_type": "linegraph",
            "description": "Share of cells (cell probability > 0.5) in each soup fraction bin. Most cells should sit at "
                           "a low soup fraction; a second peak at high soup points at empty droplets called as cells.",
            "pconfig": {"id": "cellbender_soup_histogram_plot", "title": "CellBender: soup fraction of cells",
                        "xlab": "soup %", "ylab": "% of cells", "xmin": 0, "xmax": 100, "ymin": 0},
            "data": histograms,
        }
    for name, data in content.items():
        with open(os.path.join(outdir, name), "w") as f:
            json.dump(data, f, indent=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dir", help="folder with one CellBender output folder per sample")
    parser.add_argument("-m", "--mode", type=int, default=1, choices=[1, 2, 3],
                        help="1: log only (fast); 2: also cell probabilities and latent PCA from the output h5; "
                             "3: also the CellBender input: UMI curve, soup fraction and gene removal")
    parser.add_argument("-o", "--out", default=".", help="output folder (default: current folder)")
    parser.add_argument("-v", "--verbose", action="store_true", help="print progress to stderr")
    args = parser.parse_args()

    if not os.path.isdir(args.dir):
        sys.exit(f'Folder "{args.dir}" does not exist.')
    multiqc_dir = os.path.join(args.out, "multiqc")
    os.makedirs(multiqc_dir, exist_ok=True)

    samples = []
    for sid in sorted(os.listdir(args.dir)):
        path = os.path.join(args.dir, sid)
        if not os.path.isdir(path):
            continue
        log(f"INFO: processing {sid}", args.verbose)
        s = process_sample(path, args.mode, args.verbose)
        if s is not None:
            samples.append((sid, s))
    if not samples:
        sys.exit("No CellBender output was found.")
    samples.sort(key=sort_key)

    write_summary(samples, os.path.join(args.out, "cellbender_qc_summary.tsv"))

    with PdfPages(os.path.join(args.out, "cellbender_qc_report.pdf")) as pdf:
        summary_page(samples, pdf)
        for fig in grid_pages(samples, plot_training, pdf, "Training history"):
            plt.close(fig)
        if args.mode > 1:
            save_pages(grid_pages(samples, plot_cell_calling, pdf, "Cell calling: UMI counts and cell probability"),
                       multiqc_dir, "cell_calling")
            save_pages(grid_pages(samples, plot_latent_pca, pdf, "PCA of CellBender's latent gene expression of cells"),
                       multiqc_dir, "latent_pca")
        if args.mode > 2:
            save_pages(grid_pages(samples, plot_soup_fraction, pdf, "Soup fraction of cells (cell probability > 0.5)"),
                       multiqc_dir, "soup_fraction")
            # MultiQC gets the histogram as a line graph instead
            for fig in grid_pages(samples, plot_soup_histogram, pdf, "Soup fraction histogram of cells"):
                plt.close(fig)
            save_pages(grid_pages(samples, plot_gene_removal, pdf, "UMI per feature in cells, before and after CellBender"),
                       multiqc_dir, "gene_removal")

    write_multiqc(samples, args.mode, multiqc_dir)


if __name__ == "__main__":
    main()
