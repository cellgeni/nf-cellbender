#!/bin/bash

set -euo pipefail

sample_table=examples/sample_table_exclude_features.csv

[[ -e "$sample_table" ]] || (echo "File $sample_table not found" && false)

nextflow run main.nf \
  --sample_table $sample_table \
  --on_irods \
  --exclude_features "Peaks,Multiplexing Capture,CRISPR Guide Capture" \
  --ignore_extensions "bam,bz2" \
  --output_dir "my-cellbender-v3-results"
