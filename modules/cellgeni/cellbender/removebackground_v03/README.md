# cellgeni/cellbender/removebackground_v03

## Summary

Removes ambient RNA and empty droplet artifacts from single-cell RNA-seq data
using **CellBender 0.3** (`quay.io/cellgeni/cellbender:0.3`, CellBender 0.3.2),
producing a per-sample output directory with filtered count matrices.

The CellBender version is fixed by the module. For CellBender 0.2 use
`cellgeni/cellbender/removebackground_v02`, which has the same inputs, outputs and `ext` variables.

The module:

1. Stages the input (Cell Ranger/STARsolo output directory, `.h5` file, or `.mtx` directory) under `input/`.
2. Auto-detects the input structure and locates the correct raw count matrix for CellBender.
3. Optionally estimates `--expected-cells`, `--total-droplets-included`, and `--low-count-threshold`
   from the mapper's filtered barcodes (the mapper preset; requires the full mapper output directory).
4. Runs `cellbender remove-background` on a GPU and writes outputs to `${meta.id}/`.

## Inputs

| Name | Type | Description |
|---|---|---|
| `meta.id` | string | Sample name used as the output directory name (e.g. `sample1`). |
| `input` | file/directory | Raw count data: Cell Ranger or STARsolo output directory, `.h5` file, or `.mtx` directory. |

### Supported input structures

| Input type | Detection criterion |
|---|---|
| Cell Ranger count | `outs/filtered_feature_bc_matrix.h5` + `outs/raw_feature_bc_matrix.h5` present |
| Cell Ranger multi | `outs/multi/` directory present |
| Cell Ranger ARC | `outs/atac_fragments.tsv.gz` + `outs/filtered_feature_bc_matrix.h5` present |
| Cell Ranger ATAC | `outs/raw_peak_bc_matrix.h5` present |
| STARsolo | `output/` directory present (mapper type set by `ext.starsolo_mapper`) |
| Raw `.mtx` directory | `matrix.mtx[.gz]` + `barcodes.tsv[.gz]` + `features.tsv[.gz]` present |
| `.h5` file | File with `.h5` extension |

## Outputs

| Name | File(s) | Description |
|---|---|---|
| `outputdir` | `${meta.id}/` | CellBender output directory containing `cellbender.h5` and summary files. |
| `versions` | `versions.yml` | CellBender version record. |

## Configuration via `ext` variables

```groovy
withName: ".*CELLBENDER_REMOVEBACKGROUND_V03" {
    ext.mapper_preset   = true
    ext.starsolo_mapper = "GeneFull"
    ext.expected_cells  = null
    ext.total_droplets  = null
    ext.umi_threshold   = null
    ext.args            = '--epochs 150 --exclude-feature-type "Peaks" "Antibody Capture"'
    clusterOptions      = '-gpu "mode=shared:j_exclusive=no:gmem=6000:num=1"'
    containerOptions    = '--nv'
    cpus                = 2
    memory              = { 30.GB * task.attempt }
    queue               = 'gpu'
}
```

All `ext` variables are optional; unset (`null`) values are ignored.

| Variable | Type | Default | Description |
|---|---|---|---|
| `ext.mapper_preset` | boolean | `false` | When `true`, estimates `--expected-cells`, `--total-droplets-included` and `--low-count-threshold` from the mapper's filtered barcodes. Requires the full mapper output directory as input (not `.h5` or raw `.mtx`). When `false`, CellBender 0.3 estimates these itself. |
| `ext.starsolo_mapper` | string | `"GeneFull"` | STARsolo output type to use as CellBender input. Only applies to STARsolo output directories. |
| `ext.expected_cells` | integer | `null` | Passed as `--expected-cells`. Overrides the mapper preset. |
| `ext.total_droplets` | integer | `null` | Passed as `--total-droplets-included`. Overrides the mapper preset. |
| `ext.umi_threshold` | integer | `null` | Passed as `--low-count-threshold`. Overrides the mapper preset. |
| `ext.args` | string | `""` | Additional arguments passed to `cellbender remove-background`, see below. |

### `ext.args` — additional CellBender 0.3 arguments

| Argument | Description |
|---|---|
| `--epochs <int>` | Number of training epochs. |
| `--fpr <float>` | False positive rate for the output filtered matrix. |
| `--learning-rate <float>` | Learning rate for the optimizer. |
| `--estimator <str>` | Posterior estimator: `naive`, `map`, `mean`, `cdf` or `mckp` (CellBender default). |
| `--force-empty-umi-prior <int>` | Force the empty-droplet UMI count prior. |
| `--exclude-feature-type <str> [...]` | Feature types to exclude, space-separated and quoted: `"Antibody Capture"`, `"CRISPR Guide Capture"`, `"Custom"`, `"Peaks"`, `"Multiplexing Capture"`, `"VDJ"`, `"VDJ-T"`, `"VDJ-T-GD"`, `"VDJ-B"`, `"Antigen Capture"`. |

### Mapper preset logic

When the mapper preset is on, the module runs `preset.sh` (bundled as a module binary, so the pipeline needs
`nextflow.enable.moduleBinaries = true`) to estimate parameters:

- **`--expected-cells`** — minimum of: (a) filtered barcode count from the mapper and (b) number of barcodes with UMI > 200 in the raw matrix.
- **`--total-droplets-included`** — `expected_cells + 2000`, with an additional `+3000` if cells ≥ 2000, or `+8000` if cells ≥ 20000.
- **`--low-count-threshold`** — UMI count at rank 20000 in the raw matrix, or `10` if the total number of barcodes with UMI > 10 is small relative to the expected total.

## Usage

```nextflow
include { CELLBENDER_REMOVEBACKGROUND_V03 } from 'cellgeni/cellbender/removebackground_v03'

CELLBENDER_REMOVEBACKGROUND_V03(
    channel.of([[id: 'sample1'], file('cellranger_output/')])
)
```

## License

BSD-3-clause
