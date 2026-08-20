# nf-cellbender

Our [cellbender repo](https://github.com/cellgeni/cellbender) but implemented in Nextflow.

There are two branches:

`main` — this branch contains the script for running cellbender on the FARM using Nextflow command line

`nextflow-tower` — this branch contains the script for running cellbender on the FARM using Nextflow Tower


## Contents of Repo:
* `main.nf`  the Nextflow pipeline that executes cellbender.
* `nextflow.config` — the configuration script that allows the processes to be submitted to IBM LSF on Sanger's HPC and ensures correct environment is set via singularity container (this is an absolute path). Global default parameters are also set in this file.
* `examples/sample_table.csv` — example CSV file with sample IDs and local filesystem paths to CellRanger output directories for each sample
* `examples/sample_table_irods.csv` — example CSV file with sample IDs and iRODS catalog paths to STARsolo output directories for each sample (excluded `.h5` files)
* `examples/sample_table_preset.csv` — example CSV file designed for use with `--mapper_preset` option to automatically estimate cell/droplet parameters from CellRanger/STARsolo output (excluded `.mtx` and `.h5` files)
* `examples/sample_table_exclude_features.csv` — example CSV file for demonstrating feature exclusion workflows with different CellBender versions
* `examples/run_cellbender.sh` — example of bash script to run this pipeline
* `docker/Dockerfile_v2` — a `Dockerfile` with image for `cellbender` of version `0.2.2`
* `docker/Dockerfile_v3` — a `Dockerfile` with image for `cellbender` of version `0.3.2` 

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
Running `Cellbender` version `0.2`. The parameter `--mapper_preset` is applied for version `0.2` by default
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
### Required parameters:
* `--sample_table` — Path to a .csv file containing a list of sample IDs and paths to one of the following: `CellRanger`/`STARsolo` output directory (works for all flavors of `CellRanger`), `.h5` file, `.mtx` directory. For more details see `examples/sample_table.csv` file.
* `--cells` — Number of cells. **Required** for version `0.2` when `.h5` file or `.mtx` file is provided in `--sample_table`. Otherwise `--mapper_preset` is used for version `0.2` or `CellBender`'s parameter estimation is used for version `0.3`.
* `--droplets` — Number of droplets. **Required** for version `0.2` when `.h5` file or `.mtx` file is provided in `--sample_table`. Otherwise `--mapper_preset` is used for version `0.2` or `CellBender`'s parameter estimation is used for version `0.3`.

### Optional parameters:
* `--help` — Display this help message
* `--on_irods` — Set this flag if the path in `--sample_table` file points to IRODS catalog
* `--ignore_extensions` - Specify file extensions to drop those files during catalog loading from `iRODS` (default: "bam,cram,fastq,fq,fastq.gz,fq.gz,fastq.bz2,fq.bz2,fastq.xz,fq.xz,fastq.lz4,fq.lz4,mate1.bz2,mate2.bz2")
* `--mapper_preset` - Use `CellRanger`'s or `STARsolo`'s output to estimate `--cells`, `--droplets` and `--min_umi` parameters. Works only if the whole output directory is specified as path in `--sample_table`
* `--starsolo_mapper` - Specify `STARsolo`'s output type to use for `CellBender` (`default: "GeneFull"`)
* `--exclude_features` — Specify a list of features to exclude. Available options include:
  *  `"Antibody Capture"` — only available for version `0.3` of `cellbender`
  *  `"CRISPR Guide Capture"` — only available for version `0.3` of `cellbender`
  *  `"Custom"` — only available for version `0.3` of `cellbender`
  *  `"Peaks"` — only available for version `0.3` of `cellbender`
  *  `"Multiplexing Capture"` — only available for version `0.3` of `cellbender`
  *  `"VDJ"` — only available for version `0.3` of `cellbender`
  *  `"VDJ-T"` — only available for version `0.3` of `cellbender`
  *  `"VDJ-T-GD"` — only available for version `0.3` of `cellbender`
  *  `"VDJ-B"` — only available for version `0.3` of `cellbender`
  *  `"Antigen Capture"` — only available for version `0.3` of `cellbender`
  *  **`"All"` — only available for version `0.2` of `cellbender`**
* `--epochs` — Number of epochs (`default: ""`)
* `--fpr` — False positive rate (`default: ""`)
* `--lr` — Learning rate (`default: ""`)
* `--min_umi` — Lower bound for empty-droplet UMI count (`default: ""`)
* `--force_empty_umi_prior` - Higher bound for empty-droplet UMI count (`default: ""`)
* `--estimator` - An estimator that is used for posterior generation (default: "mckp")
* `--version` — Cellbender version (available: `0.2`, `0.3`; `default: 0.3`)
* `--qc_mode` — Quality control mode (`default: 3`)
* `--output_dir` — Output directory (`default: results`)
* `--gpuqueue` — GPU queue to submit `CellBender` jobs to (e.g. `gpu-normal`, `cub22-inference`; `default: "gpu-normal"`). `tiger` queues are not supported; `cub` queues require `--costcode`
* `--costcode` — Costcode to bill the job to. Only required if `--gpuqueue` is a `cub` queue
* `--ignore_failed` — Ignore failed `CellBender` jobs on the final retry instead of stopping the pipeline (`default: false`)

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