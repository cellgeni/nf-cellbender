#!/bin/bash

set -euo pipefail

sample_table=examples/sample_table.tsv

[[ -e "$sample_table" ]] || (echo "File $sample_table not found" && false)

nextflow run main.nf \
  --sample_table $sample_table \
  --mapper cellranger \
  --exclude_features All \
  --version 0.2 \
  --fpr 0.01 \
  -resume
