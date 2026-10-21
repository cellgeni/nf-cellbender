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

Use **0.3** unless you have a reason not to. It estimates the expected cells and total droplets
itself, supports more feature types for `--exclude_features`, writes an HTML report and a metrics
file per sample, and stores the soup fraction of each cell in its output.

Use **0.2** to reproduce or extend an analysis that was done with 0.2.

## Options that only one version accepts

Validation rejects an option the chosen version would ignore, so a run never silently drops
something you asked for.

| Option | 0.2 | 0.3 |
|---|---|---|
| `--cells` / `--droplets` | Both or neither (neither means the mapper preset) | Either, both or neither |
| `--mapper_preset` | Rejected: 0.2 always uses the preset unless both `--cells` and `--droplets` are given | Off by default; turn it on to estimate from the mapper output |
| `--exclude_features` | Only `All` (excludes antibody capture) | A comma-separated list of feature types |
| `--estimator` | Rejected | `naive`, `map`, `mean`, `cdf` or `mckp` (CellBender's default is `mckp`) |
| `--force_empty_umi_prior` | Rejected | Accepted |
| `--epochs`, `--fpr`, `--lr`, `--min_umi` | Accepted | Accepted |

For example, `--version 0.2 --estimator mean` stops with:

```
* --estimator (mean): Expected null (`--estimator` is only available for CellBender 0.3)
```

{: .note }
`--version 0.2` and `--version "0.2"` both work. On the command line Nextflow reads `0.2` as a
number, and the pipeline accepts either form.

## What changes in the outputs

Both versions write `cellbender.h5`, `cellbender_filtered.h5`, `cellbender_cell_barcodes.csv`,
`cellbender.pdf` and `cellbender.log` into `cellbender/<id>/`. Only 0.3 adds
`cellbender_metrics.csv`, `cellbender_report.html` and `cellbender_posterior.h5`.

In the QC report, the soup fraction comes straight from the 0.3 output. For 0.2 it is computed from
the input matrix and can be `NA`; see [QC report](../reference/qc.md).
