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
| `excluded_features.csv` | ✓ | ✓ | Every feature left out of the CellBender model, with its UMIs (see [below](#excluded-features)) |
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
probe set alone, drop the features listed in [`excluded_features.csv`](#excluded-features):

```python
import pandas as pd
excluded = pd.read_csv("cellbender/<id>/excluded_features.csv")
adata = adata[:, ~adata.var_names.isin(excluded["id"])]
```
 `var["cellbender_analyzed"]` is not
the same: it is also `False` for the features CellBender 0.3 found too sparse to model, which keep
their counts.

The files are published one by one into `cellbender/<id>/`, so the `.h5ad` sits in the same
folder without being removed when the CellBender files are published again (with `-resume`, for
example).

### Excluded features

`excluded_features.csv` lists every feature the pipeline leaves out of the CellBender model, one
row per feature in the order of the raw matrix:

- features missing from the mapper's filtered matrix, or for a bare Flex `.h5` from its probe set
  (see [Feature filtering](../guides/cell-calls.md#feature-filtering));
- features of a type in the sample's `exclude_features` column.

| Column | Contents |
|---|---|
| `index` | Position of the feature in the raw matrix, from 0, as passed to CellBender |
| `id`, `name`, `type` | The feature's ID, name and type. A peak's name is its ID. |
| `umis` | Total UMIs of the feature in the raw matrix |
| `reason` | `not in the filtered matrix`, `not in the probe set` or `excluded feature type` |
| `decision` | `explicit`: CellBender is told to leave it out (`--ignore-features` in 0.3, `--blacklist-genes` in 0.2, or by its feature type). `implicit`: it has no counts, so it is not passed; CellBender drops features without counts by itself. |

On the combined Flex test run, the 19,061 genes outside the probe set are listed. 933 are
`explicit`, with 3.5% of the UMIs; the other 18,128 have no counts. A sample with nothing left out
gets a file with only the header. With `Peaks` excluded, every peak is listed, so the file of a
multiome sample runs to several MB.

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
