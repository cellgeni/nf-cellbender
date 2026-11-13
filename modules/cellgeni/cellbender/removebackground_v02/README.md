# cellgeni/cellbender/removebackground_v02

## Summary

Removes ambient RNA and empty droplet artifacts from single-cell RNA-seq data
using **CellBender 0.2** (`quay.io/cellgeni/cellbender:0.2`, CellBender 0.2.2),
producing a per-sample output directory with filtered count matrices.

The CellBender version is fixed by the module. For CellBender 0.3 use
`cellgeni/cellbender/removebackground_v03`, which has the same inputs, outputs and `ext` variables.

The module:

1. Stages the input (Cell Ranger/STARsolo output directory, `.h5` file, or `.mtx` directory) under `input/`.
2. Runs `prepare_cellbender.py` (a module binary, so the pipeline needs
   `nextflow.enable.moduleBinaries = true`). The script:
   - finds the raw matrix for the input structure;
   - lists the features to leave out of the model;
   - works out the cell and droplet numbers not given, by default with CellBender 0.3's own estimate.
3. Runs `cellbender remove-background` on a GPU and writes outputs to `${meta.id}/`.

## Inputs

A tuple of:

| Name | Type | Description |
|---|---|---|
| `meta` | map | Sample metadata. Must contain `id`, the output directory name, e.g. `[id: 'sample1']`. |
| `input` | file/directory | Raw count data: Cell Ranger or STARsolo output directory, `.h5` file, or `.mtx` directory. |
| `expected_cells` | integer | `--expected-cells` for this sample, or `null`/`[]` to leave it to `ext.preset`. |
| `total_droplets` | integer | `--total-droplets-included` for this sample, or `null`/`[]`. |
| `low_count_threshold` | integer | `--low-count-threshold` for this sample, or `null`/`[]`. |
| `exclude_features` | list | `['Antibody Capture']` to exclude antibody capture features (`--exclude-antibody-capture`), or `[]`. CellBender 0.2 cannot exclude other feature types; the task fails if any is given. |

### Supported input structures

The `outs/` level of a Cell Ranger directory is optional.

| Input type | Detection criterion | Raw matrix used |
|---|---|---|
| Cell Ranger multi | `outs/multi/` | `multi/count/raw_feature_bc_matrix.h5` |
| One sample of a Cell Ranger multi (Flex) run | `per_sample_outs/<sample>/` (or its `count/`) with `sample_raw_feature_bc_matrix.h5` | `sample_raw_feature_bc_matrix.h5` |
| Cell Ranger ARC | `outs/atac_fragments.tsv.gz` + `outs/filtered_feature_bc_matrix.h5` | `raw_feature_bc_matrix.h5` |
| Cell Ranger ATAC | `outs/raw_peak_bc_matrix.h5` | `raw_peak_bc_matrix.h5` |
| Cell Ranger count | `outs/filtered_feature_bc_matrix.h5` + `outs/raw_feature_bc_matrix.h5` | `raw_feature_bc_matrix.h5` |
| STARsolo | `output/` (output type set by `ext.starsolo_mapper`) | `output/<type>/raw/` |
| Raw `.mtx` directory | `matrix.mtx[.gz]` + `barcodes.tsv[.gz]` + `features.tsv[.gz]` | the directory |
| `.h5` file | `.h5` extension | the file |

One sample of a CellPlex run (`per_sample_outs/<sample>/` without a raw matrix) is rejected: CellPlex
assigns cells, not droplets, to samples, so it has no per-sample raw matrix. Use the multi run's `outs/`.
An `.mtx` directory that is not gzipped is gzipped into the work directory first, as CellBender needs.

## Outputs

All outputs except the version are tuples of `meta` and the file(s).

| Name | File(s) | Description |
|---|---|---|
| `outputdir` | `${meta.id}/` | The whole output directory, for tools that read it as one (the QC module). |
| `h5` | `${meta.id}/*.h5` | `cellbender.h5` (all analysed droplets) and `cellbender_filtered.h5` (cells). |
| `csv` | `${meta.id}/*.csv` | `cellbender_cell_barcodes.csv`. |
| `pdf` | `${meta.id}/*.pdf` | `cellbender.pdf`, CellBender's summary plots. |
| `log` | `${meta.id}/*.log` | `cellbender.log`. |
| `versions_cellbender` | | Tuple of the process name, `cellbender` and its version, also sent to the `versions` topic. |

The per-extension outputs let a pipeline publish file by file, so other files (such as an `.h5ad`)
can be published into the same folder.

## Feature filtering

For a Flex run, the raw matrix lists every gene of the reference (37,143 for GRCh38), while the
filtered matrix keeps only the genes the probe set measures (18,082). Reads still land on probes the
probe set excludes, and the raw matrix counts them. On the Flex test sample these 743 genes carry 2.7% of the UMIs.

With `ext.filter_features` (default `true`), the features missing from the mapper's filtered matrix
(for a bare `.h5`: outside the probe set in `features/target_sets`) are passed to CellBender as
`--blacklist-genes`. CellBender 0.2 leaves them out of the model and sets their counts to zero in
the output. Only the features with counts are listed. For Cell Ranger count, ARC, ATAC and STARsolo the
filtered matrix has the same features as the raw one, and nothing is ignored.

## Cells, droplets and the low-count threshold

`--expected-cells`, `--total-droplets-included` and `--low-count-threshold` come from the
`expected_cells`, `total_droplets` and `low_count_threshold` inputs. `ext.preset` decides what fills
the ones not given:

| `ext.preset` | Value given | Expected cells, total droplets not given | Low-count threshold not given |
|---|---|---|---|
| `auto` (default) | passed as given | CellBender 0.3's estimate, made by the module | the cut-off CellBender 0.3 would apply |
| `mapper` | passed as given | the [mapper preset](#mapper-preset) | the mapper preset |
| `off` | passed as given | the task fails (exit status 3) | CellBender's default (15) |

A value given for the sample is never changed, whatever the preset.

CellBender 0.2 cannot make 0.3's estimate, so with `auto` the module runs a copy of CellBender
0.3.2's code for it (`cellbender_priors.py`, from `cellbender/remove_background/data/priors.py`,
BSD-3 licence). It counts UMIs over the features 0.3 would analyse, and uses the given values the
way 0.3 does:

- A given cell number with no droplet number raises the droplets to cells + 20,000 if they were fewer.
- A threshold not given becomes the cut-off 0.3 applies itself: the greater of 5 and half the
  empty-droplet prior. A given threshold is passed as it is.

So with nothing given, a CellBender 0.2 run analyses the droplets a 0.3 run would. With `off` and no
threshold, CellBender 0.2 uses its own default of 15.

### Mapper preset

The preset uses the mapper's cell calls, so it needs a Cell Ranger or STARsolo output directory as
input, not an `.h5` file or `.mtx` directory. For each counting unit:

- **expected cells**: the smaller of the cells the mapper called and the barcodes with more than 200 UMIs;
- **total droplets**: expected cells + 2,000, plus 3,000 more with at least 2,000 cells, or 8,000
  more with at least 20,000;
- **low-count threshold**: 10. The exception is when more than 20,000 barcodes have over 10 UMIs but
  fewer than total droplets + 20,000 do: then it is the UMI count at rank 20,000.

A counting unit is one set of droplets:

- A single-sample input is one unit.
- A combined Cell Ranger multi run with CellPlex is one unit, since its samples share droplets. Its
  cells are all the barcodes Cell Ranger called (`multiplexing_analysis/assignment_confidence_table.csv`),
  including those with no sample tag or with several.
- A combined Flex run has one unit per sample. The raw barcodes carry the sample's probe barcode, so
  each sample has its own droplets. Cells and droplets are added up over the samples, and the
  lowest threshold is used.

A given cell number replaces the preset's, and the droplets follow from it (shared out between the
units in proportion).

## Configuration via `ext` variables

```groovy
withName: ".*CELLBENDER_REMOVEBACKGROUND_V02" {
    ext.preset          = "mapper"
    ext.filter_features = true
    ext.starsolo_mapper = "GeneFull"
    ext.args            = "--epochs 150"
    clusterOptions      = '-gpu "mode=shared:j_exclusive=no:gmem=6000:num=1"'
    containerOptions    = '--nv'
    cpus                = 2
    memory              = { 30.GB * task.attempt }
    queue               = 'gpu'
}
```

All `ext` variables are optional.

| Variable | Type | Default | Description |
|---|---|---|---|
| `ext.preset` | string | `"auto"` | What fills the cell, droplet and threshold numbers not given for the sample: `auto` (CellBender 0.3's estimate), `mapper` (the [mapper preset](#mapper-preset)) or `off` (nothing; cells and droplets must be given). See [Cells, droplets and the low-count threshold](#cells-droplets-and-the-low-count-threshold). |
| `ext.filter_features` | boolean | `true` | Leave the features missing from the mapper's filtered matrix out of the model (see [Feature filtering](#feature-filtering)). |
| `ext.starsolo_mapper` | string | `"GeneFull"` | STARsolo output type to use as CellBender input. Only applies to STARsolo output directories. |
| `ext.args` | string | `""` | Additional arguments passed to `cellbender remove-background`, see below. |

### `ext.args` — additional CellBender 0.2 arguments

| Argument | Description |
|---|---|
| `--epochs <int>` | Number of training epochs. |
| `--fpr <float>` | False positive rate for the output filtered matrix. |
| `--learning-rate <float>` | Learning rate for the optimizer. |

## Usage

```nextflow
include { CELLBENDER_REMOVEBACKGROUND_V02 } from 'cellgeni/cellbender/removebackground_v02'

CELLBENDER_REMOVEBACKGROUND_V02(
    channel.of(
        [[id: 'sample1'], file('cellranger_output/'), null, null, null, []],
        [[id: 'sample2'], file('citeseq_output/'), 5000, 15000, null, ['Antibody Capture']],
    )
)
```

## License

BSD-3-clause
