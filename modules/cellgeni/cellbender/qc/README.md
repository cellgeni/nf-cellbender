# cellgeni/cellbender/qc

## Summary

Collects QC statistics from CellBender `remove-background` outputs (version 0.2 or 0.3) for many samples
at once, and writes a summary table, a PDF report and MultiQC custom content.
It replaces the R script of `cellgeni/cellbender/qc@0.0.1` with `cellbender_qc.py`, which runs in the
CellBender 0.3 image (`quay.io/cellgeni/cellbender:0.3`, which has h5py, matplotlib, numpy and pandas).

For every sample folder the script reads:

- `cellbender.log`: train/test ELBO per epoch, priors, thresholds and barcode counts;
- `cellbender_cell_barcodes.csv`: the number of cells called;
- `cellbender.h5` (QC mode ≥ 2): cell probability per barcode, the learning curve, the latent gene
  expression embedding, the ambient profile and the corrected counts; in mode 3 also the soup
  (background) fraction per cell;
- the CellBender input (QC mode 3), at the `--input` path recorded in the log (resolved against the folder
  CellBender ran in, following symlinks; inside a pipeline that is the CellBender task's work directory):
  raw UMI per barcode and raw UMI per feature over the called cells. A 10x `.h5` or an `.mtx` folder is
  read once, in chunks.

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
| | `qc_report/cellbender_qc_report.pdf` | Summary table, then one grid per plot, 24 samples per page (see [Plots](#plots)). |
| `multiqc_files` | `qc_report/multiqc/*_mqc.*` | MultiQC custom content: summary table, general statistics, ELBO and soup fraction histogram line graphs, and the other plots as images (one per PDF page). |
| `versions` | `versions.yml` | python, h5py, matplotlib, numpy and pandas versions. |

### Plots

| Plot | Mode | Shows |
|---|---|---|
| Training history | ≥ 1 | Train and test ELBO per epoch. |
| Cell calling | ≥ 2 | As in CellBender's own `cellbender.pdf`: UMI count of each analysed barcode by rank (black, log scale) with its cell probability (red, second axis), and a dashed line at the number of cells. Mode 2, or an unreadable input, shows only the probabilities in CellBender's barcode order. |
| Latent PCA | ≥ 2 | PCA of CellBender's latent gene expression of cells (cell probability > 0.5), coloured by soup fraction when it is known. |
| Soup fraction | 3 | Density of the soup fraction of cells against their UMI count. |
| Soup fraction histogram | 3 | Number of cells per soup fraction bin, log scale, with the median dashed. |
| Gene removal | 3 | UMI per feature summed over cells, raw against after CellBender, with the features that lost the most UMI listed. Needs a readable input. |

### Summary columns

| Column | Description |
|---|---|
| `cellbender_version` | `0.2` or `0.3`, from the output files. |
| `epochs` | Number of training epochs. |
| `final_test_elbo_minus_max` | Final test ELBO minus its maximum; strongly negative values suggest training went wrong. |
| `test_minus_train_elbo` | Final test ELBO minus training ELBO at the same epoch. |
| `cellbender_cells` | Barcodes with cell probability > 0.5. |
| `top10umi_min_cell_prob` | Lowest cell probability among the 10 barcodes with the most UMIs (mode ≥ 2; ranked by raw UMI in mode 3, by CellBender's barcode order otherwise). |
| `mean_soup_fraction`, `median_soup_fraction` | Soup fraction of cells (mode 3). CellBender 0.2 does not store it, so it is computed from the input; `NA` when that input is not readable. |
| `top_ambient_genes` | The 5 features with the largest share of CellBender's ambient profile (mode ≥ 2). |
| `prior_empty_count`, `prior_cell_count`, `barcode_low_thr`, `posterior_reg_factor`, `largest_empty_count`, `genes_used`, `probable_cells`, `additional_cells`, `probable_empty` | Numbers reported in the CellBender log. |
| `input` | `--input` of the CellBender run. |

## Configuration via `ext` variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `ext.qc_mode` | integer | `3` | `1`: log only (fast); `2`: also reads the output h5 (a few seconds per sample); `3`: also reads the CellBender input (10–60 s per sample, depending on its size). |

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
