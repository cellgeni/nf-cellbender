# nf-cellbender

Our [cellbender repo](https://github.com/cellgeni/cellbender) but implemented in Nextflow.

There are two branches:

`main` - this branch contains the script for running cellbender on the FARM using Nextflow command line

`nextflow-tower` - this branch conrains the script for running cellbender on the FARM using Nextflow Tower


## Contents of Repo:
* `main.nf` - the Nextflow pipeline that executes cellbender.
* `nextflow.config` - the configuration script that allows the processes to be submitted to IBM LSF on Sanger's HPC and ensures correct environment is set via singularity container (this is an absolute path). Global default parameters are also set in this file.
* `examples/samples_h5.txt` - samplefile tsv containing 2 fields: sampleID, path to h5 file (The order of these files is important!). These paths can be IRODs paths or local paths.
* `examples/samples_matrix.txt` - samplefile tsv containing 2 fields: sampleID, path to aligner output directory (The order of these files is important!). These paths can be IRODs paths or local paths.
* `examples/RESUME-cellbender` - an example run script that executes the pipeline it has  hardcoded argument: `/path/to/sample/file` that needs to be changed based on your local set up.
* `bin/cellbender_qc.R` - a qc script that enables sanity checks that cellbender worked correctly.

## Pipeline Arguments:
* `--SAMPLEFILE` - The path to the sample file provided to the pipeline. This is a tab-separated file with one sample per line. Each line should contain a sample id, path to h5 file or matrix folder, path to barcodes file (in that order!).
* `--outdir` - The path to where the results will be saved.
* `--on_irods` - Tells pipeline whether to look for the input data on IRODS or the FARM (default true means look on IRODS).
* `--qc_mode` - Tells pipeline which level of QC to complete, 1 is the quickets but least depth, 3 is the slowest but most depth. 
* `--cells` - The number of cells expected a priori from the experimental design (for v0.3.0 cellbender calculates this).
* `--droplets` - Number of total droplets (for v0.3.0 cellbender calculates this). Select a number that goes a few thousand barcodes into the “empty droplet plateau”. Include some droplets that you think are surely empty. But be aware that the larger this number, the longer the algorithm takes to run (linear).
* `--epochs` - Number of epochs to train, going above 300 will lead to overfitting.
* `--fpr` - Target false positive rate in (0, 1). A false positive is a true signal count that is erroneously removed. More background removal is accompanied by more signal removal at high values of FPR.
* `--learn` - Training detail: lower learning rate for inference. A OneCycle learning rate schedule is used, where the upper learning rate is ten times this value. (For this value, probably do not exceed 1e-3).
