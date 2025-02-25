# nf-cellbender

Our [cellbender repo](https://github.com/cellgeni/cellbender) but implemented in Nextflow.

There are two branches:

`main` — this branch contains the script for running cellbender on the FARM using Nextflow command line

`nextflow-tower` — this branch contains the script for running cellbender on the FARM using Nextflow Tower


## Contents of Repo:
* `main.nf`  the Nextflow pipeline that executes cellbender.
* `nextflow.config` — the configuration script that allows the processes to be submitted to IBM LSF on Sanger's HPC and ensures correct environment is set via singularity container (this is an absolute path). Global default parameters are also set in this file.
* `examples/sample_table.tsv` — an example of `.tsv` file containing path to `cellranger` output directory for each specified sample
* `examples/sample_table_irods.tsv` — an example of `.tsv` file containing `IRODS` path to `starsolo` output directory for each specified sample
* `examples/run_cellranger_local_v2.sh` — an example run script that executes the pipeline with `--mapper cellranger` and `--version 0.2` options.
* `examples/run_starsolo_irods_v3.sh` — an example run script that executes the pipeline with `--mapper starsolo` and `--version 0.3` options.
* `docker/Dockerfile_v2` — a `Dockerfile` with image for `cellbender` of version `0.2.2`
* `docker/Dockerfile_v3` — a `Dockerfile` with image for `cellbender` of version `0.3.2` 

## Pipeline Parameters:
### Required parameters:
* `--sample_table` — Path to a .tsv file containing a list of sample IDs and paths to mappers result directory (see in example directory)
* `--mapper` — A mapper that was used to generate files (either `cellranger` or `starsolo`)
* `--solo_quant` — Quantification option for `starsolo` mapper (either `Gene` or `GeneFull`). only required if --mapper is `starsolo`

### Optional parameters:
* `--help` — Display this help message
* `--on_irods` — Set this flag if the data is on IRODS
* `--exclude_features` — Specify a list of features to exclude. Available options include:
  *  `"Antibody Capture"` — only available for `--version 0.3` of `cellbender`
  *  `"CRISPR Guide Capture"` — only available for `--version 0.3` of `cellbender`
  *  `"Custom"` — only available for `--version 0.3` of `cellbender`
  *  `"Peaks"` — only available for `--version 0.3` of `cellbender`
  *  `"Multiplexing Capture"` — only available for `--version 0.3` of `cellbender`
  *  `"VDJ"` — only available for `--version 0.3` of `cellbender`
  *  `"VDJ-T"` — only available for `--version 0.3` of `cellbender`
  *  `"VDJ-T-GD"` — only available for `--version 0.3` of `cellbender`
  *  `"VDJ-B"` — only available for `--version 0.3` of `cellbender`
  *  `"Antigen Capture"` — only available for `--version 0.3` of `cellbender`
  *  **`"All"` — only available for `--version 0.2` of `cellbender`**
* `--outdir` — Output directory (`default: cellbender-results`)
* `--cells` — Number of cells (`default: "cellbender-default"`)
* `--droplets` — Number of droplets (`default: "cellbender-default"`)
* `--epochs` — Number of epochs (default: "cellbender-default")
* `--fpr` — False positive rate (`default: "cellbender-default"`)
* `--lr` — Learning rate (default: "cellbender-default")
* `--min_umi` — Minimal UMI threshold (default: "cellbender-default") 
* `--version` — Cellbender version (available: `0.2`, `0.3`; `default: 0.3`)
* `--qc_mode` — Quality control mode (`default: 3`)

## Docker Image
The image is based on
```Dockerfile
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
```

and includes installations of `cellbender` and `R-4.4.2`. The up to date image can be loaded from `quay` [repository](https://quay.io/repository/cellgeni/cellbender?tab=logs)