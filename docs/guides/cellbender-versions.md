---
title: CellBender 0.2 or 0.3
parent: Guides
nav_order: 1
---

# CellBender 0.2 or 0.3
{: .no_toc }

1. TOC
{:toc}

The pipeline can run CellBender 0.2 (0.2.2) or 0.3 (0.3.2). Choose with `--version`; the default
is `0.3`.

```bash
nextflow run cellgeni/nf-cellbender -r main --samples samples.csv --version 0.2
```

Each version has its own module and container, so a run uses exactly one of them:

| `--version` | Module | Container |
|---|---|---|
| `0.2` | `cellgeni/cellbender/removebackground_v02` | `quay.io/cellgeni/cellbender:0.2` |
| `0.3` | `cellgeni/cellbender/removebackground_v03` | `quay.io/cellgeni/cellbender:0.3` |

## Which one to use

Use **0.3** unless you have a reason not to. It supports more feature types in the samples
table's `exclude_features` column, writes an HTML report and a metrics file per sample, and stores the soup
fraction of each cell in its output. With the default `--preset auto`, both versions get the same
expected cells and total droplets: 0.3 estimates them itself, and for 0.2 the pipeline runs a copy
of 0.3's estimate (see [Cell and droplet counts](cell-calls.md#where-the-numbers-come-from)).

Use **0.2** to reproduce or extend an analysis that was done with 0.2.

## Options that only one version accepts

Validation rejects an option the chosen version would ignore, so a run never silently drops
something you asked for.

| Option | 0.2 | 0.3 |
|---|---|---|
| `--preset` | `auto` (default), `mapper` or `off` | `auto` (default), `mapper` or `off` |
| `exclude_features` column | Only `All` (excludes antibody capture) | A comma-separated list of feature types |
| `--estimator` | Rejected | `naive`, `map`, `mean`, `cdf` or `mckp` (CellBender's default is `mckp`) |
| `--force_empty_umi_prior` | Rejected | Accepted |
| `--epochs`, `--fpr`, `--lr` | Accepted | Accepted |

For example, `--version 0.2 --estimator mean` stops with:

```
* --estimator (mean): Expected null (`--estimator` is only available for CellBender 0.3)
```

{: .note }
`--version 0.2` and `--version "0.2"` both work. On the command line Nextflow reads `0.2` as a
number, and the pipeline accepts either form.

## What changes in the outputs

Both versions write `cellbender.h5`, `cellbender_filtered.h5`, `cellbender_cell_barcodes.csv`,
`cellbender.pdf` and `cellbender.log` into `cellbender/<id>/`, and the pipeline adds
`excluded_features.csv` for both. Only 0.3 adds
`cellbender_metrics.csv`, `cellbender_report.html` and `cellbender_posterior.h5`.

In the QC report, the soup fraction comes straight from the 0.3 output. For 0.2 it is computed from
the input matrix and can be `NA`; see [QC report](../reference/qc.md).
