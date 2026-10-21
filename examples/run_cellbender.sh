#!/bin/bash

set -euo pipefail

module load cellgen/nextflow/26.04.6

samples=examples/samples_exclude_features.csv

[[ -e "$samples" ]] || (echo "File $samples not found" && false)

nextflow run main.nf \
  --samples $samples \
  --on_irods \
  --exclude_features "Peaks,Multiplexing Capture,CRISPR Guide Capture" \
  --ignore_extensions "bam,bz2" \
  --outdir "my-cellbender-v3-results"
