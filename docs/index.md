---
title: Home
nav_order: 1
permalink: /
---

# nf-cellbender

nf-cellbender runs [CellBender](https://cellbender.readthedocs.io/en/latest/) `remove-background`
on Sanger's farm22 for a whole table of samples, and then builds one QC report across all of
them. It takes CellRanger or STARsolo output folders, `.h5` files or `.mtx` folders, from Lustre or
from iRODS. CellBender jobs run on the GPU queues.

```
samples.csv ──► (download from iRODS) ──► CellBender 0.2 or 0.3 ──► QC summary + PDF ──► MultiQC report
```

## Quick start

```bash
module load cellgen/nextflow/26.04.6

nextflow run cellgeni/nf-cellbender -r main --samples samples.csv
```

`samples.csv` has an `id` and a `path` column:

```
id,path
sample1,/lustre/scratch124/.../sample1/cellranger
sample2,/lustre/scratch124/.../sample2/outs/raw_feature_bc_matrix.h5
```

Results go to `results/`: one CellBender folder per sample in `results/cellbender/`, and the QC
report in `results/qc_report/`.

## Where next

| Page | Read it when |
|---|---|
| [Getting started](getting-started.md) | You are running the pipeline for the first time |
| [CellBender 0.2 or 0.3](guides/cellbender-versions.md) | You need to choose a CellBender version, or an option is rejected for your version |
| [Cell and droplet counts](guides/cell-calls.md) | CellBender called too many or too few cells, or you have `.h5`/`.mtx` input |
| [Data on iRODS](guides/irods.md) | Your sample folders are on iRODS, or a download fails |
| [GPU queues and costcodes](guides/gpu-queues.md) | You want to run on `cub22` or `tiger22`, or jobs pend on `gpu` |
| [Reruns and failures](guides/reruns.md) | A run stopped part-way and you want to continue it |
| [Parameters](reference/parameters.md) | You need the full list of parameters and what each accepts |
| [Outputs](reference/outputs.md) | You want to know what each output file is |
| [QC report](reference/qc.md) | You are reading the QC report and want to know which samples to worry about |
| [Troubleshooting](troubleshooting.md) | Something failed with an error message |
| [Developers](developers.md) | You are changing the pipeline or its modules |
| [Changelog](changelog.md) | You want to know what changed between releases |
