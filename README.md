# nf-cellbender

Our [cellbender repo](https://github.com/cellgeni/cellbender) but implemented in Nextflow: runs [CellBender](https://cellbender.readthedocs.io/en/latest/) `remove-background` on Sanger's farm22 (LSF + Singularity) for a table of samples, then builds a QC report across all of them.

There are two branches:

`main` — this branch contains the script for running cellbender on the FARM using Nextflow command line

`nextflow-tower` — this branch contains the script for running cellbender on the FARM using Nextflow Tower

## Requirements
* Nextflow `>=26.04.0` (e.g. `/software/cellgen/cellgeni/nextflow/26.04.6/nextflow`)
* The [nf-schema](https://registry.nextflow.io/plugins/nf-schema@3.0.0) plugin (`3.0.0`) checks the parameters and the sample table. Nextflow downloads it on the first run.

## Contents of Repo:
* `main.nf` — the Nextflow pipeline that executes cellbender. Its `output {}` block defines what is published where.
* `nextflow.config` — global settings: default parameters, LSF executor, Singularity, nf-schema plugin and help text. Each process has its own config in `configs/`.
* `configs/` — per-process settings (queue, resources, `ext` arguments): `irods_loadcatalog.config`, `cellbender_removebackground.config`, `cellbender_qc.config`, `multiqc.config`.
* `nextflow_schema.json` — parameter definitions (types, allowed values, cross-parameter rules) used for validation and `--help`.
* `assets/schema_sample_table.json` — the format of `--sample_table`.
* `assets/multiqc_config.yaml` — MultiQC report layout.
* `modules/cellgeni/cellbender/removebackground_v02/`, `modules/cellgeni/cellbender/removebackground_v03/` — CellBender `0.2` and `0.3` modules, each pinned to its own container (see [Modules](#modules)).
* `modules/cellgeni/cellbender/qc/` — QC module (`cellbender_qc.py`): summary table, PDF report and MultiQC content.
* `modules/local/irods/loadcatalog/` — downloads sample folders from iRODS.
* `modules/local/multiqc/` — renders the HTML QC report.
* `examples/sample_table.csv` — example CSV file with sample IDs and local filesystem paths to CellRanger output directories for each sample
* `examples/sample_table_irods.csv` — example CSV file with sample IDs and iRODS catalog paths to STARsolo output directories for each sample (excluded `.h5` files)
* `examples/sample_table_preset.csv` — example CSV file designed for use with `--mapper_preset` option to automatically estimate cell/droplet parameters from CellRanger/STARsolo output (excluded `.mtx` and `.h5` files)
* `examples/sample_table_exclude_features.csv` — example CSV file for demonstrating feature exclusion workflows with different CellBender versions
* `examples/run_cellbender.sh` — example of bash script to run this pipeline
* `docker/Dockerfile_v2` — a `Dockerfile` with image for `cellbender` of version `0.2.2`
* `docker/Dockerfile_v3` — a `Dockerfile` with image for `cellbender` of version `0.3.2`

## Sample table
A `.csv` file with two columns:

| Column | Description |
|---|---|
| `id` | Sample name, used for the output folder. Must be unique and contain no spaces. |
| `path` | `CellRanger`/`STARsolo` output directory (any `CellRanger` flavour), `.h5` file or `.mtx` directory. With `--on_irods`, an iRODS collection. |

```
id,path
cellranger-count,/path/to/cellranger-count
starsolo,/path/to/starsolo
```

## Getting help
The parameter list printed by `--help` is generated from `nextflow_schema.json`:
```
nextflow run main.nf --help                   # top-level parameters and examples
nextflow run main.nf --help exclude_features  # details of one parameter
nextflow run main.nf --helpFull               # all parameters
nextflow run main.nf --help --showHidden      # include hidden parameters
```

Parameters are validated before any job is submitted, including combinations that would otherwise be silently ignored (a version 0.3 option with `--version 0.2`, `--costcode` with the `gpu` queue, `--ignore_extensions` without `--on_irods`). A wrong value fails at once with a message like:
```
* --gpuqueue (gpu-normal): Expected any of [gpu, cub22-inference, tiger22-inference]
* Missing required parameter(s): costcode (`--costcode` is required for `cub` and `tiger` queues)
```

## Examples
### Default parameters
Running `Cellbender` version `0.2` using local data
```
nextflow run main.nf --version "0.2" --sample_table examples/sample_table.csv --cells <val> --droplets <val>
```

Running `Cellbender` version `0.3` (used by default) using data on `iRODS`
```
nextflow run main.nf --sample_table examples/sample_table_irods.csv --on_irods
```

### CellRanger/STARsolo preset
Running `Cellbender` version `0.2`. The mapper preset is applied for version `0.2` by default, unless both `--cells` and `--droplets` are given
```
nextflow run main.nf --sample_table examples/sample_table_preset.csv --version "0.2" --on_irods
```

Running `Cellbender` version `0.3` with `--mapper_preset`
```
nextflow run main.nf --sample_table examples/sample_table_preset.csv --on_irods --mapper_preset --version "0.3"
```

### Exclude features
Only `"All"` is available for version `0.2`
```
nextflow run main.nf --version "0.2" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "All"
```

Specify a list of comma-separated features you want to exclude for version `0.3`
```
nextflow run main.nf --version "0.3" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "Peaks,Multiplexing Capture,CRISPR Guide Capture" --mapper_preset
```

### GPU queues
`CellBender` jobs go to the `gpu` queue by default. The `cub22-inference` and `tiger22-inference` queues need a costcode, which is passed to LSF as `-G` and converted to lowercase
```
nextflow run main.nf --sample_table examples/sample_table_irods.csv --on_irods --gpuqueue cub22-inference --costcode s1234
```

### Combine all together
Use mapper preset with feature exclusion for version `0.2`. Load the data from iRODS (do not load `.bam` and `.bz2` files) and change the name of output directory to `my-cellbender-v2-results`
```
nextflow run main.nf --version "0.2" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "All" --ignore_extensions "bam,bz2" --output_dir "my-cellbender-v2-results"
```

Use mapper preset with feature exclusion for version `0.3`. Load the data from iRODS (do not load `.bam` and `.bz2` files) and change the name of output directory to `my-cellbender-v3-results`
```
nextflow run main.nf --version "0.3" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "Peaks,Multiplexing Capture,CRISPR Guide Capture" --ignore_extensions "bam,bz2" --output_dir "my-cellbender-v3-results"
```

## Pipeline Parameters:
### Input/output options
* `--sample_table` — **Required.** Path to a `.csv` file with sample IDs and paths, see [Sample table](#sample-table).
* `--on_irods` — Set this flag if the paths in `--sample_table` point to iRODS collections (`default: false`)
* `--ignore_extensions` — Comma-separated file extensions to skip when downloading from `iRODS`. Only with `--on_irods` (`default: "bam,cram,fastq,fq,fastq.gz,fq.gz,fastq.bz2,fq.bz2,fastq.xz,fq.xz,fastq.lz4,fq.lz4,mate1.bz2,mate2.bz2"`)
* `--output_dir` — Output directory (`default: results`)

### CellBender options
* `--version` — CellBender version (available: `0.2`, `0.3`; `default: 0.3`)
* `--cells` — Number of cells. **Required** together with `--droplets` for version `0.2` when `.h5` files or `.mtx` directories are given in `--sample_table`. Otherwise the mapper preset is used for version `0.2`, and `CellBender`'s own estimation for version `0.3`.
* `--droplets` — Number of droplets. **Required** together with `--cells` for version `0.2` when `.h5` files or `.mtx` directories are given in `--sample_table`.
* `--mapper_preset` — Use `CellRanger`'s or `STARsolo`'s output to estimate `--cells`, `--droplets` and `--min_umi`. Works only if the whole output directory is given as `path` in `--sample_table`. Version `0.3` only: version `0.2` always uses the preset unless both `--cells` and `--droplets` are given (`default: false`)
* `--starsolo_mapper` — `STARsolo` output type to use for `CellBender` (`default: "GeneFull"`)
* `--exclude_features` — Feature types to exclude:
  * version `0.3`: a comma-separated list of `"Antibody Capture"`, `"CRISPR Guide Capture"`, `"Custom"`, `"Peaks"`, `"Multiplexing Capture"`, `"VDJ"`, `"VDJ-T"`, `"VDJ-T-GD"`, `"VDJ-B"`, `"Antigen Capture"`
  * version `0.2`: only `"All"` (excludes antibody capture)
* `--epochs` — Number of epochs
* `--fpr` — False positive rate (between `0` and `1`)
* `--lr` — Learning rate
* `--min_umi` — Lower bound for empty-droplet UMI count
* `--force_empty_umi_prior` — Higher bound for empty-droplet UMI count (version `0.3` only)
* `--estimator` — Estimator for posterior generation: `naive`, `map`, `mean`, `cdf` or `mckp` (version `0.3` only; CellBender's default is `mckp`)
* `--qc_mode` — QC detail level (`default: 3`): `1` reads logs only; `2` also reads cell probabilities from the output `.h5`; `3` also computes soup fractions

### Cluster options
* `--gpuqueue` — GPU queue to submit `CellBender` jobs to (available: `gpu`, `cub22-inference`, `tiger22-inference`; `default: "gpu"`). `cub` and `tiger` queues require `--costcode`
* `--costcode` — Costcode to bill the job to (converted to lowercase). Required for `cub` and `tiger` queues, and not allowed with `gpu`
* `--ignore_failed` — Ignore `CellBender` jobs that still fail after the last retry instead of stopping the pipeline (`default: false`)

### Generic options
* `--help`, `--helpFull`, `--showHidden` — see [Getting help](#getting-help)

## Outputs
```
results/
├── raw/<id>/                       data downloaded from iRODS (with --on_irods)
├── cellbender/<id>/                CellBender output: cellbender.h5, cellbender_filtered.h5, cellbender.pdf, cellbender.log, ...
├── index/
│   ├── cellbender.csv              id,path of every CellBender output folder
│   └── raw.csv                     id,path of every iRODS download (empty without --on_irods)
└── qc_report/
    ├── cellbender_qc_summary.tsv   one row per sample, most problematic samples first
    ├── cellbender_qc_report.pdf    summary table, training curves, cell probabilities, soup fractions
    ├── multiqc_report.html         the same QC as an interactive HTML report
    ├── multiqc_data/
    └── multiqc/                    MultiQC input files
```

Outputs are published with Nextflow [workflow outputs](https://docs.seqera.io/nextflow/workflow#workflow-outputs) into `--output_dir`, copied by default (`--publish_mode`, hidden). The index files use the sample table format, so `index/raw.csv` can be passed back as `--sample_table` (without `--on_irods`) to rerun CellBender on data already downloaded.

## Modules
The CellBender modules are written in this repository in the [Nextflow module registry](https://registry.nextflow.io/) layout, one per CellBender version:

| Module | Process | Container |
|---|---|---|
| `cellgeni/cellbender/removebackground_v02` | `CELLBENDER_REMOVEBACKGROUND_V02` | `quay.io/cellgeni/cellbender:0.2` |
| `cellgeni/cellbender/removebackground_v03` | `CELLBENDER_REMOVEBACKGROUND_V03` | `quay.io/cellgeni/cellbender:0.3` |
| `cellgeni/cellbender/qc` | `CELLBENDER_QC` | `quay.io/cellgeni/cellbender:0.3` |

`main.nf` runs one of the two CellBender modules depending on `--version`. To publish a new module version, bump `version` in its `meta.yml` and run:
```
nextflow module validate modules/cellgeni/cellbender/removebackground_v03
nextflow module publish modules/cellgeni/cellbender/removebackground_v03 -dry-run
nextflow module publish modules/cellgeni/cellbender/removebackground_v03
```

## Docker Image
The image is based on
```Dockerfile
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
```

and includes installations of `cellbender` and `R-4.4.2`. The up to date image can be loaded from `quay` [repository](https://quay.io/repository/cellgeni/cellbender?tab=logs)

## Run tests (for developers)

Run tests
```
mkdir -p logs
N=26
bsub -J "test-cellbender[1-$N]" -env "all, N=$N" < tests/scripts/run_tests.bsub
```

Count successful runs
```
echo "PASSED: $(grep -l "PASSED" logs/*Output*.log | wc -l), FAILED: $(grep -l "FAILURE" logs/*Output*.log | wc -l), RUNNING $(grep -L "Your job looked like:" logs/*Output*.log | wc -l)"
echo "FAILED TEST LIST:"; grep -l "FAILURE" logs/*Output*.log
```
