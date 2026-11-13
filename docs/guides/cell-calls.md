---
title: Cell and droplet counts
parent: Guides
nav_order: 2
---

# Cell and droplet counts
{: .no_toc }

1. TOC
{:toc}

CellBender needs to know three things about each sample:

- roughly how many cells there are (`--expected-cells`);
- how many droplets to model (`--total-droplets-included`);
- below which UMI count a droplet is surely empty (`--low-count-threshold`).

You can give them per sample in the samples table, and `--preset` decides what fills the ones you
leave out: CellBender's own estimate, the mapper's cell calls, or nothing.

## Where the numbers come from

A value given for a sample is always used as it is. It comes from the `cells`, `droplets` and
`min_umi` columns of the [samples table](../reference/samples.md#per-sample-values). An empty cell,
or a missing column, leaves the number to `--preset`:

| `--preset` | Cells and droplets not given | Min UMI not given |
|---|---|---|
| `auto` (default) | CellBender's own estimate | CellBender 0.3: its default (5). CellBender 0.2: the cut-off 0.3 would apply |
| `mapper` | the [mapper preset](#the-mapper-preset), from the cell calls of CellRanger or STARsolo | the mapper preset |
| `off` | not allowed: the run stops before it starts | CellBender's default (5 for 0.3, 15 for 0.2) |

- **`auto`**: CellBender 0.3 estimates the numbers from the UMI curve itself. CellBender 0.2
  cannot, so for 0.2 the pipeline runs a copy of CellBender 0.3.2's estimate on the same counts
  and passes the numbers on. With nothing given, a 0.2 run then analyses the droplets a 0.3 run
  would.
- **`mapper`**: needs the whole mapper output folder as `path` (see [below](#the-mapper-preset)).
- **`off`**: nothing is estimated. Every sample needs `cells` and `droplets` in the table;
  `min_umi` can stay empty:

  ```
  id,path,cells,droplets,min_umi
  pbmc,/lustre/scratch124/.../pbmc,5000,15000,
  multiome,/lustre/scratch124/.../multiome,3000,10000,10
  ```

  ```bash
  nextflow run main.nf --samples samples.csv --preset off
  ```

So you can give one number and leave the others to the preset. The numbers used for each sample,
and where each came from, are printed in the task's `.command.log`:

```
INFO: expected cells: 3000 (given)
INFO: total droplets: 8000 (mapper preset)
INFO: low count threshold: left to CellBender
```

{: .note }
Whatever low-count threshold it is given, CellBender 0.3 applies a cut-off of at least half its
prior on the UMI count of empty droplets.

## The mapper preset

With `--preset mapper`, the preset reads the mapper's cell calls and the raw matrix, so `path` in the samples table must be
the whole CellRanger or STARsolo output folder. On a bare `.h5` file or `.mtx` folder the task stops
with an error. For each set of droplets it sets:

- **expected cells**: the smaller of the cells the mapper called and the number of barcodes with
  more than 200 UMIs;
- **total droplets**: expected cells + 2,000, plus 3,000 more if there are at least 2,000 cells,
  or 8,000 more if there are at least 20,000;
- **low-count threshold**: 10. The exception is when more than 20,000 barcodes have over 10 UMIs
  but fewer than total droplets + 20,000 do: then it is the UMI count at rank 20,000 in the raw
  matrix.

A given `cells` value replaces the preset's expected cells, and the droplets are worked out from it.

### Multiplexed runs

A CellRanger multi folder with several samples is handled by how they were multiplexed:

- **CellPlex** (and other cell multiplexing): the samples share one set of droplets, so the preset
  runs once. Its cells are all the barcodes CellRanger called, including those assigned to no
  sample or to several (`multiplexing_analysis/assignment_confidence_table.csv`). The per-sample
  folders leave those out.
- **Flex with probe barcodes**: each sample's barcodes carry its probe barcode, so the raw matrix
  holds one set of droplets per sample. The preset runs per sample, the cells and droplets are
  added up, and the lowest threshold is used.

On the Flex test data (4 samples) that gives 40,804 droplets. One buffer for all the cells would
give 30,804.

## Flex samples one by one

The samples of a Flex run can also go through CellBender one by one. Give each sample's
`per_sample_outs/<sample>` folder as `path`:

```
id,path
Liver_BC1,/path/to/multi_run/outs/multi/per_sample_outs/Liver_BC1
Ovarian_BC2,/path/to/multi_run/outs/multi/per_sample_outs/Ovarian_BC2
```

CellBender then reads that sample's own raw matrix (`count/sample_raw_feature_bc_matrix.h5`), and
the mapper preset uses that sample's cell calls.

{: .important }
This works for Flex only. A CellPlex sample's folder has only the cells assigned to it, not the
droplets, so CellBender has nothing to learn the background from. The task stops with
`holds one sample of a Cell Ranger multi run with only its called cells`. Give the multi run's
`outs/` folder instead.

## Feature filtering

The raw matrix of a Flex run lists every gene of the reference (37,143 for GRCh38). The filtered
matrix keeps only the genes the probe set measures (18,082). Reads on probes the probe set excludes
are still counted in the raw matrix: on the test sample, 743 such genes carry 2.7% of the UMIs.

By default the pipeline leaves the features missing from the mapper's filtered matrix out of the
CellBender model. For a bare Flex `.h5` file, it leaves out the features outside its probe set
(`features/target_sets`). They are passed as `--ignore-features` to CellBender 0.3, which copies
their counts unchanged to its output. CellBender 0.2 takes them as `--blacklist-genes` and sets
their counts to zero. For CellRanger count, ARC, ATAC and STARsolo the filtered matrix has the same
features as the raw one, and nothing changes.

`--filter_features false` keeps every feature in the model.

## Inputs the pipeline recognises

| `path` points to | Detected by |
|---|---|
| CellRanger multi | `outs/multi/` |
| One sample of a CellRanger multi Flex run | `per_sample_outs/<sample>/` (or its `count/`), with `sample_raw_feature_bc_matrix.h5` |
| CellRanger ARC | `outs/atac_fragments.tsv.gz` and `outs/filtered_feature_bc_matrix.h5` |
| CellRanger ATAC | `outs/raw_peak_bc_matrix.h5` |
| CellRanger count | `outs/filtered_feature_bc_matrix.h5` and `outs/raw_feature_bc_matrix.h5` |
| STARsolo | `output/`; the matrix type is set by `--starsolo_mapper` (default `GeneFull`) |
| `.mtx` folder | `matrix.mtx[.gz]`, `barcodes.tsv[.gz]` and `features.tsv[.gz]` |
| `.h5` file | the `.h5` extension |

The `outs/` level is optional: a CellRanger folder or its `outs/` folder both work.

## Excluding feature types

The `exclude_features` column of the samples table keeps feature types out of the model for one
sample, for example the peaks of a multiome library or the CRISPR guides of a CRISPR screen. Each
sample gets its own list, so one table can mix library types. Quote a cell with several types:

```
id,path,exclude_features
pbmc,/lustre/scratch124/.../pbmc,
multiome,/lustre/scratch124/.../multiome,Peaks
crispr,/lustre/scratch124/.../crispr,"CRISPR Guide Capture,Antibody Capture"
```

CellBender 0.3 takes any of `Antibody Capture`, `CRISPR Guide Capture`, `Custom`, `Peaks`,
`Multiplexing Capture`, `VDJ`, `VDJ-T`, `VDJ-T-GD`, `VDJ-B` and `Antigen Capture`. CellBender 0.2
takes only `All`, which excludes antibody capture. A name that is not in the list, or `All` with
0.3, is rejected before the run starts.

## Training options

`--epochs`, `--fpr` (target false positive rate, 0 to 1), `--lr` (learning rate) and, for 0.3,
`--estimator` and `--force_empty_umi_prior` go straight to CellBender. Leave them unset to use
CellBender's defaults. If training curves in the [QC report](../reference/qc.md) look wrong,
`--epochs` and `--lr` are the first to change.
