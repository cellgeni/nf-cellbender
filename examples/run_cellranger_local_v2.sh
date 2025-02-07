#!/bin/bash

set -euo pipefail

sample_table=examples/sample_table.tsv

[[ -e "$sample_table" ]] || (echo "File $sample_table not found" && false)

nextflow run main.nf \
  --sample_table $sample_table \
  --mapper starsolo \
  --solo_quant GeneFull \
  --version 0.3 \
  -resume
