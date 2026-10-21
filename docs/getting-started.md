---
title: Getting started
nav_order: 2
---

# Getting started
{: .no_toc }

1. TOC
{:toc}

## Requirements

- **Nextflow 26.04 or later.** On farm22: `module load cellgen/nextflow/26.04.6`.
- **farm22 access** with LSF and Singularity. CellBender runs in the `quay.io/cellgeni/cellbender`
  images; they are already in the shared cache `/nfs/cellgeni/singularity/images/`.
- **Read access to your data**, on Lustre or on iRODS (see [Data on iRODS](guides/irods.md)).

The [nf-schema](https://registry.nextflow.io/plugins/nf-schema@3.0.0) plugin, which checks the
parameters, is downloaded by Nextflow on the first run.

## 1. Write a samples table

A `.csv` file with one row per sample, passed with `--samples`:

| Column | Description |
|---|---|
| `id` | Sample name, used for the output folder. Unique, no spaces. |
| `path` | CellRanger or STARsolo output folder, a `.h5` file or a `.mtx` folder. With `--on_irods`, an iRODS collection. |

```
id,path
cellranger-count,/lustre/scratch124/.../cellranger-count
starsolo,/lustre/scratch124/.../starsolo
```

Give the whole mapper output folder where you can: the pipeline then finds the right raw matrix
itself and can estimate cell numbers from it. See [Samples table](reference/samples.md) for the
input layouts it recognises.

## 2. Run it

From the folder where you want `nf-work/` and `results/` to appear:

```bash
module load cellgen/nextflow/26.04.6

nextflow run cellgeni/nf-cellbender -r main --samples samples.csv
```

This runs CellBender 0.3 on the `gpu` queue. Common variations:

```bash
# CellBender 0.2
nextflow run cellgeni/nf-cellbender -r main --samples samples.csv --version 0.2

# Sample folders on iRODS
nextflow run cellgeni/nf-cellbender -r main --samples samples_irods.csv --on_irods

# Results somewhere else
nextflow run cellgeni/nf-cellbender -r main --samples samples.csv --outdir my-results
```

Run it inside `screen`/`tmux` or submit the `nextflow run` itself as an LSF job: the head job has
to stay alive until every sample has finished.

## 3. Check the results

```
results/
├── cellbender/<id>/          CellBender output for each sample
├── index/cellbender.csv      id,path of every CellBender output
├── qc_report/                QC summary, PDF and MultiQC report
└── versions.yml              software versions
```

Start with `results/qc_report/multiqc_report.html`: samples that need a closer look are listed
first. [QC report](reference/qc.md) explains each column, and [Outputs](reference/outputs.md)
each file.

## Getting help on the command line

```bash
nextflow run cellgeni/nf-cellbender -r main --help                   # main parameters and examples
nextflow run cellgeni/nf-cellbender -r main --help exclude_features  # one parameter in detail
nextflow run cellgeni/nf-cellbender -r main --helpFull               # every parameter
```

Running without `--samples` prints a short usage message.

## When a parameter is rejected

Parameters are checked before anything is downloaded or submitted. A wrong value or a combination
that would be silently ignored stops the run at once:

```
The following invalid input values have been detected:

* --gpuqueue (gpu-normal): Expected any of [gpu, cub22-inference, tiger22-inference]
* --estimator (mean): Expected null (`--estimator` is only available for CellBender 0.3)
* Value matches against schema from 'if' but does not match against schema from 'then'
```

The text in brackets says what to change. The last line is printed by the validation plugin under
every rule that fails and adds nothing. [Parameters](reference/parameters.md) lists all the rules.
