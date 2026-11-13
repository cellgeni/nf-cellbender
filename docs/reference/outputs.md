---
title: Outputs
parent: Reference
nav_order: 3
---

# Outputs
{: .no_toc }

1. TOC
{:toc}

## Layout

Everything is written to `--outdir` (default `results/`):

```
results/
├── raw/<id>/                       data downloaded from iRODS (with --on_irods)
├── cellbender/<id>/                CellBender output for each sample, and its cells as .h5ad
├── index/
│   ├── cellbender.csv              id,path of every CellBender output folder
│   ├── h5ad.csv                    id,path of every cellbender_filtered.h5ad (empty with --h5ad false)
│   └── raw.csv                     id,path of every iRODS download (empty without --on_irods)
├── qc_report/
│   ├── cellbender_qc_summary.tsv   one row per sample, most problematic samples first
│   ├── cellbender_qc_report.pdf    summary table, training curves, cell calling, latent PCA, soup, gene removal
│   ├── multiqc_report.html         the same QC as an interactive HTML report
│   ├── multiqc_data/               data behind the MultiQC report
│   └── multiqc/                    MultiQC input files
└── versions.yml                    software versions
```

With a `group` column in the samples table (see [Groups](samples.md#groups)), each group gets
its own folder with the same layout; the index files and `versions.yml` stay at the top:

```
results/
├── <group>/
│   ├── raw/<id>/                   data downloaded from iRODS (with --on_irods)
│   ├── cellbender/<id>/            CellBender output for each sample of the group
│   └── qc_report/                  QC of the group's samples, as above
├── index/
│   ├── cellbender.csv              id,group,path of every CellBender output folder
│   ├── h5ad.csv                    id,group,path of every cellbender_filtered.h5ad
│   └── raw.csv                     id,group,path of every iRODS download
└── versions.yml
```

Run reports from Nextflow (timeline, resource report, trace) go to `execution-reports/` in the
launch folder, not to `--outdir`.

## CellBender output

Each `cellbender/<id>/` (or `<group>/cellbender/<id>/`) folder holds what
`cellbender remove-background` wrote for that sample:

| File | 0.2 | 0.3 | Contents |
|---|---|---|---|
| `cellbender.h5` | ✓ | ✓ | Corrected counts for all analysed droplets, plus latent variables |
| `cellbender_filtered.h5` | ✓ | ✓ | Corrected counts for droplets with cell probability > 0.5 |
| `cellbender_cell_barcodes.csv` | ✓ | ✓ | Barcodes with cell probability > 0.5 |
| `cellbender.pdf` | ✓ | ✓ | CellBender's own summary plots |
| `cellbender.log` | ✓ | ✓ | CellBender's log, read by the QC step |
| `cellbender_metrics.csv` | | ✓ | Run metrics |
| `cellbender_report.html` | | ✓ | CellBender's own HTML report, with warnings |
| `cellbender_posterior.h5` | | ✓ | Posterior of noise counts |
| `cellbender_filtered.h5ad` | ✓ | ✓ | `cellbender_filtered.h5` as AnnData (not with `--h5ad false`) |

For downstream analysis use `cellbender_filtered.h5ad`, or `cellbender_filtered.h5`. The
[CellBender documentation](https://cellbender.readthedocs.io/en/latest/) describes each file in
detail.

### The .h5ad file

`cellbender_filtered.h5ad` is written by [adata-cli](https://cellgeni.github.io/adata-cli/)
(`adata convert`) from `cellbender_filtered.h5`:

- `X`: CellBender's corrected counts, as integers.
- `obs`: CellBender's latent variables per cell, such as `cell_probability` and `background_fraction`.
- `obsm["gene_expression_encoding"]`: the latent gene expression embedding.
- `var["ambient_expression"]`: the ambient profile.
- `uns["cellbender"]`: the run's settings and learning curve.

Features are named by gene id, with the symbols in `var["gene_symbols"]`. In scanpy, use
`adata.var_names = adata.var["gene_symbols"]` and `adata.var_names_make_unique()` for symbols.

The features [left out of the model](../guides/cell-calls.md#feature-filtering) are still in the
file: CellBender 0.3 keeps their raw counts, and 0.2 sets them to zero. For an analysis of the
probe set alone, keep the features of CellRanger's filtered matrix, for example
`adata = adata[:, adata.var_names.isin(filtered.var_names)]`. `var["cellbender_analyzed"]` is not
the same: it is also `False` for the features CellBender 0.3 found too sparse to model, which keep
their counts.

The files are published one by one into `cellbender/<id>/`, so the `.h5ad` sits in the same
folder without being removed when the CellBender files are published again (with `-resume`, for
example).

## QC report

`qc_report/` (one per group with a `group` column) is described column by column in
[QC report](qc.md).

## Versions

`versions.yml` records the version of every tool used in the run:

```yaml
"CELLBENDER:CELLBENDER_REMOVEBACKGROUND_V03":
    cellbender: 0.3.2
"CELLBENDER_QC":
    python: 3.10.12
    h5py: 3.14.0
    matplotlib: 3.10.3
"MULTIQC":
    multiqc: 1.35
"CELLBENDER:ADATA_CONVERT":
    adata: 0.17.5
```

Each module sends the version of every tool it uses to the `versions` topic, and the pipeline
collects them into this one file.

## How files are published

Outputs are copied out of `nf-work/` by default. `--publish_mode` (hidden, see `--help --showHidden`)
also accepts `symlink`, `link`, `rellink`, `copyNoFollow` and `move`.

{: .warning }
With `symlink` or `rellink`, the results point into `nf-work/`: deleting it then deletes the
results too.
