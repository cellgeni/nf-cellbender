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
├── cellbender/<id>/                CellBender output for each sample
├── index/
│   ├── cellbender.csv              id,path of every CellBender output folder
│   └── raw.csv                     id,path of every iRODS download (empty without --on_irods)
├── qc_report/
│   ├── cellbender_qc_summary.tsv   one row per sample, most problematic samples first
│   ├── cellbender_qc_report.pdf    summary table, training curves, cell probabilities, soup fractions
│   ├── multiqc_report.html         the same QC as an interactive HTML report
│   ├── multiqc_data/               data behind the MultiQC report
│   └── multiqc/                    MultiQC input files
└── versions.yml                    software versions
```

Run reports from Nextflow (timeline, resource report, trace) go to `execution-reports/` in the
launch folder, not to `--outdir`.

## CellBender output

Each `cellbender/<id>/` folder holds what `cellbender remove-background` wrote for that sample:

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

For downstream analysis use `cellbender_filtered.h5`. The
[CellBender documentation](https://cellbender.readthedocs.io/en/latest/) describes each file in
detail.

## QC report

`qc_report/` is described column by column in [QC report](qc.md).

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
```

## How files are published

Outputs are copied out of `nf-work/` by default. `--publish_mode` (hidden, see `--help --showHidden`)
also accepts `symlink`, `link`, `rellink`, `copyNoFollow` and `move`.

{: .warning }
Do not use `symlink` or `rellink` without also turning off cleanup: the pipeline deletes `nf-work/`
after a successful run, and the links would point at deleted files.
