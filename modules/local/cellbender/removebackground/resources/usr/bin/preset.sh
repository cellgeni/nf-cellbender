#!/usr/bin/env bash

function preset_cells() {
  local raw_matrix_dir=$1
  local filt_bc_count=$2
  local cells_umi200

  if [[ ! -f "$raw_matrix_dir/matrix.mtx.gz" ]]; then
    echo "Error: matrix.mtx.gz is missing in $raw_matrix_dir" >&2
    exit 1
  fi

  ## Calculate expected number of cell
  cells_umi200=$(zcat "$raw_matrix_dir/matrix.mtx.gz" | count_cells.awk -v threshold=200)

  ## Return the minimum of the two values
  echo $((filt_bc_count < cells_umi200 ? filt_bc_count : cells_umi200))
}

function preset_droplets() {
  local expected_cells=$1
  local total_droplets
  total_droplets=$((expected_cells + 2000))

  ## Adjust based on expected cell count
  if ((expected_cells >= 20000)); then
    total_droplets=$((total_droplets + 8000))
  elif ((expected_cells >= 2000)); then
    total_droplets=$((total_droplets + 3000))
  fi

  echo "$total_droplets"

}

function preset_umi_threshold() {
  local raw_matrix_dir=$1
  local expected_total_barcodes=$2
  local umi_rank20000
  local cells_umi10

  ## Ensure required file exists
  if [[ ! -f "$raw_matrix_dir/matrix.mtx.gz" ]]; then
    echo "Error: Raw matrix file missing" >&2
    exit 1
  fi

  ## Calculate UMI number for the 20000th cell and count cells with UMI > 10
  umi_rank20000=$(zcat "$raw_matrix_dir/matrix.mtx.gz" | sort_cells.awk -v target_cell=20000 -v preset_value=10)
  cells_umi10=$(zcat "$raw_matrix_dir/matrix.mtx.gz" | count_cells.awk -v threshold=10)

  ## Use the maximum of `umi_rank20000` or `10`
  if ((cells_umi10 < expected_total_barcodes + 20000)); then
    echo "$umi_rank20000"
  else
    echo "10"
  fi
}
