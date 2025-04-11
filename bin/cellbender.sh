#!/usr/bin/env bash

## Function to display usage
usage() {
  echo "Usage: $0 --sample sample_id --mapper mapper --mapper_output mapper_output --version version [--cells cells] [--droplets droplets] [--epochs epochs] [--fpr fpr] [--learning_rate learning_rate]"
  exit 1
}

## Function to parse arguments
parse_args() {
  ## Initialize optional inputs with default values
  solo_quant=""
  exclude_features=""
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
      if [[ "${2:-}" =~ ^- ]] || [[ -z "${2:-}" ]]; then
        echo "Error: --sample requires a non-empty argument" >&2
        usage
      fi
      sample="$2"
      shift 2
      ;;
    --mapper_output)
      if [[ "${2:-}" =~ ^- ]] || [[ -z "${2:-}" ]]; then
        echo "Error: --mapper_output requires a non-empty argument" >&2
        usage
      fi
      mapper_output="$2"
      shift 2
      ;;
    --mapper)
      if [[ "${2:-}" =~ ^- ]] || [[ -z "${2:-}" ]]; then
        echo "Error: --mapper requires a non-empty argument" >&2
        usage
      fi
      mapper="$2"
      shift 2
      ;;
    --solo_quant)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: solo_quant is empty" >&2
        solo_quant=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: solo_quant is empty, next one is a new option $2" >&2
        solo_quant=""
        shift 1
      else
        echo "Debug: solo_quant is not empty: $2" >&2
        solo_quant="$2"
        shift 2
      fi
      ;;
    --exclude_features)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: exclude_features is empty" >&2
        exclude_features=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: exclude_features is empty, next one is a new option $2" >&2
        exclude_features=""
        shift 1
      else
        echo "Debug: exclude_features is not empty: $2" >&2
        exclude_features="$2"
        shift 2
      fi
      ;;
    --cells)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: cells is empty" >&2
        cells=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: cells is empty, next one is a new option $2" >&2
        cells=""
        shift 1
      else
        echo "Debug: cells is not empty: $2" >&2
        cells="$2"
        shift 2
      fi
      ;;
    --droplets)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: droplets is empty" >&2
        droplets=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: droplets is empty, next one is a new option $2" >&2
        droplets=""
        shift 1
      else
        echo "Debug: droplets is not empty: $2" >&2
        droplets="$2"
        shift 2
      fi
      ;;
    --min_umi)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: min_umi is empty" >&2
        min_umi=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: min_umi is empty, next one is a new option $2" >&2
        min_umi=""
        shift 1
      else
        echo "Debug: min_umi is not empty: $2" >&2
        min_umi="$2"
        shift 2
      fi
      ;;
    --epochs)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: epochs is empty" >&2
        epochs=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: epochs is empty, next one is a new option $2" >&2
        epochs=""
        shift 1
      else
        echo "Debug: epochs is not empty: $2" >&2
        epochs="$2"
        shift 2
      fi
      ;;
    --fpr)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: fpr is empty" >&2
        fpr=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: fpr is empty, next one is a new option $2" >&2
        fpr=""
        shift 1
      else
        echo "Debug: fpr is not empty: $2" >&2
        fpr="$2"
        shift 2
      fi
      ;;
    --learning_rate)
      if [[ -z "${2:-}" ]]; then
        echo "Debug: learning_rate is empty" >&2
        learning_rate=""
        shift 2
      elif [[ "${2:-}" =~ ^- ]]; then
        echo "Debug: learning_rate is empty, next one is a new option $2" >&2
        learning_rate=""
        shift 1
      else
        echo "Debug: learning_rate is not empty: $2" >&2
        learning_rate="$2"
        shift 2
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

function find_mtx_directory() {
  local mapper_output=$1
  local solo_quant=${2:-}
  local prefix=$3

  ## Find the matrix directory
  matrix_dir=$(find "$mapper_output/" -type d -regextype posix-extended -regex ".*${solo_quant}/(sample_)?${prefix}.*" -print -quit)

  ## Ensure directory exists
  if [[ -z "$matrix_dir" ]]; then
    echo "Error: Could not locate \"${prefix}\" matrix directory" >&2
    exit 1
  fi

  echo "$matrix_dir"
}

function preset_cells() {
  local raw_matrix_dir=$1
  local filtered_matrix_dir=$2
  local mapper_prediction
  local cells_umi200

  ## Ensure input files exist
  if [[ ! -f "$filtered_matrix_dir/barcodes.tsv.gz" ]]; then
    echo "Error: barcodes.tsv.gz file is missing in $filtered_matrix_dir" >&2
    exit 1
  fi

  if [[ ! -f "$raw_matrix_dir/matrix.mtx.gz" ]]; then
    echo "Error: matrix.mtx.gz is missing in $raw_matrix_dir" >&2
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
  raw_matrix_dir=$(find_mtx_directory "$mapper_output" "$solo_quant" "raw")
  filtered_matrix_dir=$(find_mtx_directory "$mapper_output" "$solo_quant" "filtered")

  ## Ensure directories exist
  if [[ -z "$raw_matrix_dir" || -z "$filtered_matrix_dir" ]]; then
    echo "Error: Could not locate required matrix directories" >&2
    exit 1
  fi

  ## Create argument inpul string for the script
  args=() # using array ensures proper handling of arguments

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

    ## Set exclude_features_option
    [ -n "$exclude_features" ] && args+=(--exclude-antibody-capture)
    if [[ -n $exclude_features && ! $exclude_features == "All" ]]; then
      echo "Error: Only All is supported for exclude_features in version 0.3" >&2
      exit 1
    fi
  elif [[ $version == "0.3" ]]; then
    echo "Running cellbender version 0.3"
    ## Set exclude_features_option
    [ -n "$exclude_features" ] && args+=(--exclude-feature-types "$exclude_features")
  else
    echo "Version not supported"
    exit 1
  fi

  ## Add arguments to the array
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Enable strict error handling
  set -euo pipefail

  # Run the script
  main "$@"
fi
