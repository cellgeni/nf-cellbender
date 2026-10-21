# cellgeni/cellbender/qc

## Summary

Collects QC statistics from CellBender `remove-background` outputs (version 0.2 or 0.3) for many samples
at once, and writes a summary table, a PDF report and MultiQC custom content.
It replaces the R script of `cellgeni/cellbender/qc@0.0.1` with `cellbender_qc.py`, which runs in the
CellBender 0.3 image (`quay.io/cellgeni/cellbender:0.3`, which has h5py and matplotlib).

For every sample folder the script reads:

- `cellbender.log`: train/test ELBO per epoch, priors, thresholds and barcode counts;
- `cellbender_cell_barcodes.csv`: the number of cells called;
- `cellbender.h5` (QC mode ≥ 2): cell probability per barcode and the learning curve;
  in mode 3 also the soup (background) fraction per cell.

Samples are ordered with the most problematic first: those whose 10 highest-UMI barcodes include one with
cell probability ≤ 0.5, then by how far the final test ELBO fell below its maximum.

## Inputs

| Name | Type | Description |
|---|---|---|
| `cellbender_output` | directories | CellBender output directories, one per sample and named after it, staged under `cellbender_output/`. |

## Outputs

| Name | File(s) | Description |
|---|---|---|
| `report` | `qc_report/` | All outputs below. |
| | `qc_report/cellbender_qc_summary.tsv` | One row per sample. |
| | `qc_report/cellbender_qc_report.pdf` | Summary table, then grids of training curves, cell probabilities (mode ≥ 2) and soup fraction density plots (mode 3), 24 samples per page. |
| `multiqc_files` | `qc_report/multiqc/*_mqc.*` | MultiQC custom content: summary table, general statistics, ELBO and cell probability line graphs, soup fraction images. |
| `versions` | `versions.yml` | python, h5py and matplotlib versions. |

### Summary columns

| Column | Description |
|---|---|
| `cellbender_version` | `0.2` or `0.3`, from the output files. |
| `epochs` | Number of training epochs. |
| `final_test_elbo_minus_max` | Final test ELBO minus its maximum; strongly negative values suggest training went wrong. |
| `test_minus_train_elbo` | Final test ELBO minus training ELBO at the same epoch. |
| `cellbender_cells` | Barcodes with cell probability > 0.5. |
| `top10umi_min_cell_prob` | Lowest cell probability among the 10 barcodes with the most UMIs (mode ≥ 2). |
| `mean_soup_fraction`, `median_soup_fraction` | Soup fraction of cells (mode 3). CellBender 0.2 does not store it, so it is computed from the input matrix at the `--input` path recorded in the log (resolved against the folder CellBender ran in, following symlinks; inside a pipeline that is the CellBender task's work directory). `NA` when that input is not readable. |
| `prior_empty_count`, `prior_cell_count`, `barcode_low_thr`, `posterior_reg_factor`, `largest_empty_count`, `genes_used`, `probable_cells`, `additional_cells`, `probable_empty` | Numbers reported in the CellBender log. |
| `input` | `--input` of the CellBender run. |

## Configuration via `ext` variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `ext.qc_mode` | integer | `3` | `1`: log only (fast); `2`: also reads cell probabilities from the output h5 (a few seconds per sample); `3`: also soup fraction (10–60 s per sample). |

The script is bundled as a module binary, so the pipeline needs `nextflow.enable.moduleBinaries = true`.

## Usage

```nextflow
include { CELLBENDER_QC } from 'cellgeni/cellbender/qc'

CELLBENDER_QC(CELLBENDER_REMOVEBACKGROUND_V03.out.outputdir.map { meta, dir -> dir }.collect())
MULTIQC(CELLBENDER_QC.out.multiqc_files, file('multiqc_config.yaml'))
```

The script can also be run on its own:

```bash
cellbender_qc.py results/cellbender --mode 3 --out qc_report --verbose
```

## License

MIT
