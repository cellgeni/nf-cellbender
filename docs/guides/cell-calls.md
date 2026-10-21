---
title: Cell and droplet counts
parent: Guides
nav_order: 2
---

# Cell and droplet counts
{: .no_toc }

1. TOC
{:toc}

CellBender needs to know roughly how many cells there are (`--expected-cells`), how many droplets
to model (`--total-droplets-included`) and below which UMI count a droplet is surely empty
(`--low-count-threshold`). The pipeline can take these from you, estimate them from the mapper
output, or leave them to CellBender 0.3.

## Where the numbers come from

| Situation | CellBender 0.2 | CellBender 0.3 |
|---|---|---|
| Nothing given | Mapper preset | CellBender's own estimates |
| `--mapper_preset` | Rejected (the preset is already on) | Mapper preset |
| `--cells` and `--droplets` | Your values | Your values |
| Only one of `--cells` / `--droplets` | Rejected | Your value, CellBender estimates the other |
| `--min_umi` | Overrides the preset's threshold | Passed as `--low-count-threshold` |

Values you give always win over the preset.

{: .important }
With CellBender 0.2 and `.h5` or `.mtx` inputs, give both `--cells` and `--droplets`. The mapper
preset needs the whole CellRanger/STARsolo folder and fails on a bare matrix.

## The mapper preset

The preset reads the mapper's filtered barcodes and the raw matrix, so `path` in the samples
table must be the whole CellRanger or STARsolo output folder. It sets:

- **expected cells**: the smaller of the mapper's filtered barcode count and the number of barcodes
  with more than 200 UMIs;
- **total droplets**: expected cells + 2,000, plus 3,000 more if there are at least 2,000 cells,
  or 8,000 more if there are at least 20,000;
- **low-count threshold**: the UMI count at rank 20,000 in the raw matrix, or 10 if few barcodes
  have more than 10 UMIs.

The values used for each sample are printed in the task's `.command.log`.

## Inputs the pipeline recognises

| `path` points to | Detected by |
|---|---|
| CellRanger count | `outs/filtered_feature_bc_matrix.h5` and `outs/raw_feature_bc_matrix.h5` |
| CellRanger multi | `outs/multi/` |
| CellRanger ARC | `outs/atac_fragments.tsv.gz` and `outs/filtered_feature_bc_matrix.h5` |
| CellRanger ATAC | `outs/raw_peak_bc_matrix.h5` |
| STARsolo | `output/`; the matrix type is set by `--starsolo_mapper` (default `GeneFull`) |
| `.mtx` folder | `matrix.mtx[.gz]`, `barcodes.tsv[.gz]` and `features.tsv[.gz]` |
| `.h5` file | the `.h5` extension |

The `outs/` level is optional: a CellRanger folder or its `outs/` folder both work.

## Excluding feature types

`--exclude_features` keeps feature types out of the model, for example antibody or CRISPR
features in a multiome library.

```bash
# CellBender 0.3: any of the 10 types, comma-separated
--exclude_features "Peaks,Multiplexing Capture,CRISPR Guide Capture"

# CellBender 0.2: only All (excludes antibody capture)
--version 0.2 --exclude_features All
```

The 0.3 types are `Antibody Capture`, `CRISPR Guide Capture`, `Custom`, `Peaks`,
`Multiplexing Capture`, `VDJ`, `VDJ-T`, `VDJ-T-GD`, `VDJ-B` and `Antigen Capture`. A name that
is not in the list is rejected before the run starts.

## Training options

`--epochs`, `--fpr` (target false positive rate, 0 to 1), `--lr` (learning rate) and, for 0.3,
`--estimator` and `--force_empty_umi_prior` go straight to CellBender. Leave them unset to use
CellBender's defaults. If training curves in the [QC report](../reference/qc.md) look wrong,
`--epochs` and `--lr` are the first to change.
