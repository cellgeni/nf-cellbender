#!/usr/bin/env python3
"""Collect QC statistics and plots from CellBender remove-background outputs.

Reads every per-sample folder in DIR (CellBender 0.2 or 0.3 output), and writes:
  cellbender_qc_summary.tsv    one row per sample, most problematic samples first
  cellbender_qc_report.pdf     summary table, training curves, cell probabilities, soup fractions
  multiqc/                     the same data as MultiQC custom content
"""
import argparse
import glob
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
from matplotlib.backends.backend_pdf import PdfPages  # noqa: E402

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
    "cellbender_cells", "top10umi_min_cell_prob", "mean_soup_fraction", "median_soup_fraction",
    *LOG_PATTERNS, "input",
]
GRID_ROWS, GRID_COLS = 4, 6
MULTIQC_LINE_POINTS = 1000


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


def column_sums(group):
    """Total UMI per barcode from a CSC matrix stored as indices/indptr/data/shape."""
    indptr = group["indptr"][:]
    data = group["data"][:].astype(float)
    ncols = len(indptr) - 1
    col = np.repeat(np.arange(ncols), np.diff(indptr))
    return np.bincount(col, weights=data, minlength=ncols)


def decode(values):
    return np.array([v.decode() if isinstance(v, bytes) else v for v in values])


def parse_h5(path, mode):
    """Cell probabilities, learning curve, total UMI and (v0.3) soup fraction from the output h5."""
    r = {}
    with h5py.File(path, "r") as h5:
        if "droplet_latents" in h5:  # CellBender 0.3
            r["version"] = "0.3"
            latents, matrix, meta = h5["droplet_latents"], h5["matrix"], h5["metadata"]
            r["cell_probability"] = latents["cell_probability"][:]
            idx = latents["barcode_indices_for_latents"][:]
            r["train"] = dict(zip(meta["learning_curve_train_epoch"][:].astype(int), meta["learning_curve_train_elbo"][:]))
            r["test"] = dict(zip(meta["learning_curve_test_epoch"][:].astype(int), meta["learning_curve_test_elbo"][:]))
            filtered_umi = column_sums(matrix)[idx]
            if mode > 2:
                soup = latents["background_fraction"][:]
                with np.errstate(divide="ignore", invalid="ignore"):
                    r["raw_umi"] = np.round(filtered_umi / (1 - soup))
                r["soup_fraction"] = soup
        else:  # CellBender 0.2: a single top-level group
            r["version"] = "0.2"
            g = h5[list(h5.keys())[0]]
            r["cell_probability"] = g["latent_cell_probability"][:]
            idx = g["barcode_indices_for_latents"][:]
            elbo = g["training_elbo_per_epoch"][:]
            r["train"] = dict(zip(range(1, len(elbo) + 1), elbo))
            r["test"] = dict(zip(g["test_epoch"][:].astype(int), g["test_elbo"][:]))
            filtered_umi = column_sums(g)[idx]
            r["barcodes"] = decode(g["barcodes"][:])[idx]
        r["filtered_umi"] = filtered_umi
    return r


def raw_umi_from_input(path, barcodes):
    """Total UMI per barcode from the CellBender input, needed for the v0.2 soup fraction."""
    if path and os.path.isdir(path):
        mtx = glob.glob(os.path.join(path, "matrix.mtx*"))
        bcs = glob.glob(os.path.join(path, "barcodes.tsv*"))
        if not mtx or not bcs:
            return None
        import gzip
        import scipy.io

        opener = gzip.open if bcs[0].endswith(".gz") else open
        with opener(bcs[0], "rt") as f:
            input_barcodes = np.array(f.read().split())
        sums = np.asarray(scipy.io.mmread(mtx[0]).sum(axis=0)).ravel()
    elif path and os.path.isfile(path) and path.endswith(".h5"):
        with h5py.File(path, "r") as h5:
            g = h5["matrix"]
            input_barcodes = decode(g["barcodes"][:])
            sums = column_sums(g)
    else:
        return None
    lookup = dict(zip(input_barcodes, sums))
    return np.array([lookup.get(bc, np.nan) for bc in barcodes])


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
        h5 = parse_h5(h5_file, mode)
        info["cellbender_version"] = h5["version"]
        s["train"], s["test"] = h5["train"], h5["test"]
        s["cell_probability"] = h5["cell_probability"]
        info["top10umi_min_cell_prob"] = float(np.min(h5["cell_probability"][:10]))
        if mode > 2:
            if "soup_fraction" not in h5:
                raw = raw_umi_from_input(info["input"], h5["barcodes"])
                if raw is None:
                    log(f"WARN: input {info['input']} of {sample_dir} is not readable, soup fraction skipped", verbose)
                else:
                    h5["raw_umi"] = raw
                    with np.errstate(divide="ignore", invalid="ignore"):
                        h5["soup_fraction"] = (raw - h5["filtered_umi"]) / raw
            if "soup_fraction" in h5:
                cells = h5["cell_probability"] > 0.5
                s["raw_umi"], s["soup_fraction"] = h5["raw_umi"][cells], h5["soup_fraction"][cells]
                info["mean_soup_fraction"] = float(np.nanmean(s["soup_fraction"]))
                info["median_soup_fraction"] = float(np.nanmedian(s["soup_fraction"]))
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


def plot_training(ax, s):
    epochs = sorted(s["train"])
    ax.plot(epochs, [s["train"][e] for e in epochs], color="tab:blue", lw=2, label="Train")
    test = sorted(s["test"])
    ax.plot(test, [s["test"][e] for e in test], color="tab:orange", lw=2, label="Test")
    ax.set_xlabel("Epoch")
    ax.set_ylabel("ELBO")
    ax.legend(loc="lower right", frameon=False, fontsize=8)


def plot_cell_probability(ax, s):
    ax.plot(s["cell_probability"], color="black", lw=1)
    ax.set_ylim(0, 1)
    ax.set_xlabel("Barcode index, sorted by UMI count")
    ax.set_ylabel("Cell probability")


def plot_soup_fraction(ax, s):
    if "soup_fraction" not in s:
        ax.text(0.5, 0.5, "not available", ha="center", va="center", transform=ax.transAxes)
        return
    x = np.log10(s["raw_umi"] + 1)
    y = s["soup_fraction"] * 100
    ok = np.isfinite(x) & np.isfinite(y)
    _, _, _, image = ax.hist2d(x[ok], y[ok], bins=100, range=[[x[ok].min(), x[ok].max()], [0, 100]],
                               cmap="viridis", norm=matplotlib.colors.LogNorm(), cmin=1)
    plt.colorbar(image, ax=ax, label="# cells")
    ax.set_xlabel("log10(UMI + 1)")
    ax.set_ylabel("soup %")


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


def downsample(values, n=MULTIQC_LINE_POINTS):
    idx = np.unique(np.linspace(0, len(values) - 1, min(n, len(values))).astype(int))
    return {int(i) + 1: round(float(values[i]), 4) for i in idx}


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
    if mode > 1:
        content["cellbender_cell_probability_mqc.json"] = {
            "id": "cellbender_cell_probability", "section_name": "CellBender cell probability", "plot_type": "linegraph",
            "description": "Cell probability per barcode, barcodes sorted by UMI count. Expect a sharp drop from 1 to 0.",
            "pconfig": {"id": "cellbender_cell_probability_plot", "title": "CellBender: cell probability",
                        "xlab": "Barcode index, sorted by UMI count", "ylab": "Cell probability", "ymin": 0, "ymax": 1},
            "data": {sid: downsample(s["cell_probability"]) for sid, s in samples if "cell_probability" in s},
        }
    for name, data in content.items():
        with open(os.path.join(outdir, name), "w") as f:
            json.dump(data, f, indent=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dir", help="folder with one CellBender output folder per sample")
    parser.add_argument("-m", "--mode", type=int, default=1, choices=[1, 2, 3],
                        help="1: log only (fast); 2: also cell probabilities from the output h5; 3: also soup fraction")
    parser.add_argument("-o", "--out", default=".", help="output folder (default: current folder)")
    parser.add_argument("-v", "--verbose", action="store_true", help="print progress to stderr")
    args = parser.parse_args()

    if not os.path.isdir(args.dir):
        sys.exit(f'Folder "{args.dir}" does not exist.')
    os.makedirs(args.out, exist_ok=True)

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
            for fig in grid_pages(samples, plot_cell_probability, pdf, "Cell probability"):
                plt.close(fig)
        if args.mode > 2:
            figures = grid_pages(samples, plot_soup_fraction, pdf, "Soup fraction of cells (cell probability > 0.5)")
            os.makedirs(os.path.join(args.out, "multiqc"), exist_ok=True)
            # Density plots have no MultiQC plot type, so each page goes into the report as an image
            for page, fig in enumerate(figures, start=1):
                fig.savefig(os.path.join(args.out, "multiqc", f"cellbender_soup_fraction_{page}_mqc.png"), dpi=80)
                plt.close(fig)

    write_multiqc(samples, args.mode, os.path.join(args.out, "multiqc"))


if __name__ == "__main__":
    main()
