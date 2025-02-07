#!/usr/bin/env bash

set -euo pipefail

## Function to display usage
usage() {
  echo "Usage: $0 --sample sample_id --mapper mapper --mapper_output mapper_output --version version [--cells cells] [--droplets droplets] [--epochs epochs] [--fpr fpr] [--learning_rate learning_rate]"
  exit 1
}

## Function to parse arguments
parse_args() {
  ## Initialize optional inputs with default values
  solo_quant=""
  cells=""
  droplets=""
  min_umi=""
  epochs=""
  fpr=""
  learning_rate=""

  ## Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --sample)
      sample="$2"
      shift 2
      ;;
    --mapper_output)
      mapper_output="$2"
      shift 2
      ;;
    --mapper)
      mapper="$2"
      shift 2
      ;;
    --solo_quant)
      # optional
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        solo_quant="$2"
        shift 2
      else
        solo_quant=""
        shift 1
      fi
      ;;
    --cells)
      # optional
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        cells="$2"
        shift 2
      else
        cells=""
        shift 1
      fi
      ;;
    --droplets)
      # optional
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        droplets="$2"
        shift 2
      else
        droplets=""
        shift 1
      fi
      ;;
    --min_umi)
      # optional
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        min_umi="$2"
        shift 2
      else
        min_umi=""
        shift 1
      fi
      ;;
    --epochs)
      # optional
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        epochs="$2"
        shift 2
      else
        epochs=""
        shift 1
      fi
      ;;
    --fpr)
      # optional
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        fpr="$2"
        shift 2
      else
        fpr=""
        shift 1
      fi
      ;;
    --learning_rate)
      # optional
      if [[ -n "${2:-}" && "$2" != --* ]]; then
        learning_rate="$2"
        shift 2
      else
        learning_rate=""
        shift 1
      fi
      ;;
    --version)
      version="$2"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Error: Invalid option $1" >&2
      usage
      ;;
    esac
  done

  ## Check mandatory arguments
  if [ -z "${sample:-}" ] || [ -z "${mapper_output:-}" ] || [ -z "${version:-}" ] || [ -z "${mapper:-}" ]; then
    usage
  fi

  ## Check if solo_quant is provided if mapper is starsolo
  if [[ $mapper == "starsolo" && -z "$solo_quant" ]]; then
    echo "Error: solo_quant is required for starsolo" >&2
    exit 1
  fi
}

function preset_cells() {
  local raw_matrix_dir=$1
  local filtered_matrix_dir=$2
  local mapper_prediction
  local cells_umi200

  ## Ensure input files exist
  if [[ ! -f "$filtered_matrix_dir/barcodes.tsv.gz" || ! -f "$raw_matrix_dir/matrix.mtx.gz" ]]; then
    echo "Error: Required matrix files are missing" >&2
    exit 1
  fi

  ## Calculate expected number of cells
  mapper_prediction=$(zcat "$filtered_matrix_dir/barcodes.tsv.gz" | wc -l)
  cells_umi200=$(zcat "$raw_matrix_dir/matrix.mtx.gz" | count_cells.awk -v threshold=200)

  ## Return the minimum of the two values
  echo $((mapper_prediction < cells_umi200 ? mapper_prediction : cells_umi200))
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

function main() {

  parse_args "$@"

  ## Get a path to the directory containing raw and filltered .mtx file
  raw_matrix_dir=$(find "$mapper_output/" -type d -wholename "*${solo_quant}/raw*" -print -quit)
  filtered_matrix_dir=$(find "$mapper_output/" -type d -wholename "*${solo_quant}/filtered*" -print -quit)

  ## Ensure directories exist
  if [[ -z "$raw_matrix_dir" || -z "$filtered_matrix_dir" ]]; then
    echo "Error: Could not locate required matrix directories" >&2
    exit 1
  fi

  ## Check if the version is supported
  if [[ $version == "0.2" ]]; then
    echo "Running cellbender version 0.2"
    ## Calculate expected number of cells
    expected_cells=$(preset_cells "$raw_matrix_dir" "$filtered_matrix_dir")
    expected_total_barcodes=$(preset_droplets "$expected_cells")

    ## Set expected number of cells, total number of droplets and UMI threshold value if not specified
    [ -z "$cells" ] && cells="$expected_cells"
    [ -z "$droplets" ] && droplets="$expected_total_barcodes"
    [ -z "$min_umi" ] && min_umi=$(preset_umi_threshold "$raw_matrix_dir" "$expected_total_barcodes")
  elif [[ $version == "0.3" ]]; then
    echo "Running cellbender version 0.3"
  else
    echo "Version not supported"
    exit 1
  fi

  ## Create argument inpul string for the script
  args=() # using array ensures proper handling of arguments
  [ -n "$cells" ] && args+=(--expected-cells "$cells")
  [ -n "$droplets" ] && args+=(--total-droplets-included "$droplets")
  [ -n "$min_umi" ] && args+=(--low-count-threshold "$min_umi")
  [ -n "$epochs" ] && args+=(--epochs "$epochs")
  [ -n "$fpr" ] && args+=(--fpr "$fpr")
  [ -n "$learning_rate" ] && args+=(--learning-rate "$learning_rate")

  ## Create a directory for each sample
  mkdir -p "${sample}"

  ## Write the command to a file
  echo "cellbender remove-background --input ${raw_matrix_dir} --output ${sample}/cellbender_out.h5 --cuda" "${args[@]}" >"${sample}/cmd.txt"

  ## Run the command
  cellbender remove-background \
    --input "${raw_matrix_dir}" \
    --output "${sample}/cellbender_out.h5" \
    --cuda \
    "${args[@]}"
}

main "$@"
