---
title: QC report
parent: Reference
nav_order: 4
---

# QC report
{: .no_toc }

1. TOC
{:toc}

After CellBender has run on every sample, the QC step reads all the outputs together and writes
`results/qc_report/`:

| File | Contents |
|---|---|
| `cellbender_qc_summary.tsv` | One row per sample, most problematic samples first |
| `cellbender_qc_report.pdf` | A summary table, then one panel per sample for each plot, 24 samples per page |
| `multiqc_report.html` | The same table and plots in an interactive report |

## What to look at first

Open `multiqc_report.html`. The samples worth a closer look come first in the summary table:

1. **A low `Top-10 min cell prob`** (below 0.5): one of the ten barcodes with the most UMIs was not
   called a cell. This usually means training failed for that sample.
2. **A strongly negative `Final - max test ELBO`**: the test ELBO peaked and then fell, so the
   final model is worse than an earlier one. Training became unstable.

Then check the plots for those samples:

- **Training curves.** Train and test ELBO should rise and level off together. A test curve that
  drops away at the end, or ends far below the training curve, is a bad sign. Try fewer epochs or
  a lower `--lr`.
- **Cell probability.** Barcodes are sorted by UMI count. Expect a plateau at 1 for the cells and a
  sharp drop to 0. A slow decline, or a dip near the start, means CellBender could not separate
  cells from empty droplets.
- **Soup fraction.** For each called cell, the share of its UMIs CellBender removed as background,
  against its total UMIs. Most cells should sit at a low soup percentage; a large share of cells
  near 100% points at empty droplets called as cells.

## QC modes

`--qc_mode` sets how much is computed:

| Mode | Reads | Adds |
|---|---|---|
| `1` | CellBender logs | Summary from the log and training curves (fast) |
| `2` | Also each `cellbender.h5` | Cell probabilities and `Top-10 min cell prob` (a few seconds per sample) |
| `3` (default) | Also the soup fraction | Soup fraction plots and statistics (10–60 seconds per sample) |

## Summary columns

| Column | Description |
|---|---|
| `sample_id` | Sample `id` from the samples table |
| `cellbender_version` | `0.2` or `0.3`, from the output files |
| `epochs` | Training epochs |
| `final_test_elbo_minus_max` | Final test ELBO minus its maximum. 0 is ideal; strongly negative suggests training went wrong |
| `test_minus_train_elbo` | Final test ELBO minus the training ELBO at the same epoch |
| `cellbender_cells` | Barcodes with cell probability > 0.5 |
| `top10umi_min_cell_prob` | Lowest cell probability among the 10 barcodes with the most UMIs (mode 2 and 3) |
| `mean_soup_fraction`, `median_soup_fraction` | Soup fraction of the called cells (mode 3) |
| `prior_empty_count` | CellBender's prior on UMI counts in empty droplets |
| `prior_cell_count` | CellBender's prior on UMI counts in cells |
| `barcode_low_thr` | Barcodes with fewer UMIs were excluded |
| `posterior_reg_factor` | Posterior regularisation factor (CellBender 0.2 only) |
| `largest_empty_count` | UMI count of the largest droplet CellBender considered surely empty |
| `genes_used` | Features included in the analysis |
| `probable_cells`, `additional_cells`, `probable_empty` | Barcodes CellBender used as probable cells, additional barcodes and empty droplets |
| `input` | The input CellBender read |

Samples are sorted by `top10umi_min_cell_prob > 0.5` (failures first), then by
`final_test_elbo_minus_max` (most negative first).

{: .note }
CellBender 0.3 stores each cell's soup fraction in its output. CellBender 0.2 does not, so the QC
step recomputes it from the input matrix recorded in the log. If that input is no longer readable,
for example after the work folder was cleaned up, the soup fraction is `NA`.

## Running the QC on its own

The QC step is the module `cellgeni/cellbender/qc`, and its script runs on any folder of CellBender
outputs, one subfolder per sample:

```bash
singularity exec -B /lustre /nfs/cellgeni/singularity/images/quay.io-cellgeni-cellbender-0.3.img \
    cellbender_qc.py results/cellbender --mode 3 --out qc_report --verbose
```

`cellbender_qc.py` is in
[`modules/cellgeni/cellbender/qc/resources/usr/bin/`](https://github.com/cellgeni/nf-cellbender/tree/main/modules/cellgeni/cellbender/qc/resources/usr/bin);
use its full path if it is not on your `PATH`.
