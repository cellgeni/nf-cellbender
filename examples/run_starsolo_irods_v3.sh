#!/bin/bash

set -euo pipefail

sample_table=examples/sample_table_irods.tsv

[[ -e "$sample_table" ]] || (echo "File $sample_table not found" && false)

nextflow run main.nf \
  --sample_table $sample_table \
  --mapper cellranger \
  --version 0.3 \
  --on_irods \
  -resume
