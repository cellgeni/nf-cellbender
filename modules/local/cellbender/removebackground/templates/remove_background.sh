#!/bin/bash

# enable extglob so ?(…) works
shopt -s extglob

# Variables
cellbender_input=""
starsolo_default_mapper="GeneFull"
args="${task.ext.args ? $args : ''}"

### Figure out the input structure. See a diagram explaining the steps here: FUTURE LINK
# Check if input is a directory
if [[ -d "$input" ]]; then
    # Check if it's cellranger output directory
    if [[ -d "$input/outs" ]]; then
        # Check if it's output from cellranger multi
        if [[ -d "$input/outs/multi" ]]; then
            echo "INFO: $input directory contains cellranger multi output structure"
            mapper="cellranger_multi"
            cellbender_input="$input/outs/multi/count/raw_feature_bc_matrix.h5"
        # Check if it's output from cellranger-atac
        elif [[ -f "$input/outs/filtered_peak_bc_matrix.h5" ]]; then
            echo "INFO: $input directory contains cellranger-atac output structure"
            mapper="cellranger-atac"
            cellbender_input="$input/outs/filtered_peak_bc_matrix.h5"
        # Check if it's output from cellranger-arc
        elif [[ -f "$input/outs/atac_fragments.tsv.gz" && -f "$input/outs/filtered_feature_bc_matrix.h5" ]]; then
            echo "INFO: $input directory contains cellranger-arc output structure"
            mapper="cellranger-arc"
            cellbender_input="$input/outs/filtered_feature_bc_matrix.h5"
        # Check if it's output from cellranger count
        elif [[ -f "$input/outs/filtered_feature_bc_matrix.h5" && -f "$input/outs/raw_feature_bc_matrix.h5" ]]; then
            echo "INFO: $input directory contains cellranger count output structure"
            mapper="cellranger_count"
            cellbender_input="$input/outs/filtered_feature_bc_matrix.h5"
        else
            echo "Error: Input directory does not contain expected cellranger output structure. Check manual for more information" >&2
            exit 1
        fi
    # Check if it's output from STARsolo
    elif [[ -d "$input/output" ]]; then
        echo "INFO: $input directory contains STARsolo output structure"
        mapper="starsolo"
        cellbender_input="$input/output/\$starsolo_default_mapper/raw"
    # Check if it's output from 10x Genomics
    elif [ -f "$input"/matrix.mtx?(.gz) ] && [ -f "$input"/barcodes.tsv?(.gz) ] && [ -f "$input"/features.tsv?(.gz) ]; then
        echo "INFO: $input directory contains 10x Genomics output structure"
        mapper="unknown_mtx"
        cellbender_input="$input"
    else
        echo "Error: Input directory does not contain expected structure. Check mannual for more information" >&2
        exit 1
    fi
# Check if input is .h5 file
elif [[ -f "$input" && "$input" == *.h5 ]]; then
    echo "INFO: Input $input is an .h5 file"
    mapper="unknown_h5"
    cellbender_input="$input"
else
    echo "Error: Input is neither a directory nor a .h5 file. Check manual for more information" >&2
    exit 1
fi

### Create output directory
mkdir -p "$meta.id"

### Save file version information
cat <<-END_VERSIONS > versions.yml
"${task.process}":
    cellbender: \$(cellbender --version)
END_VERSIONS

### Run CellBender

echo "INFO: Running CellBender remove-background with input: \$cellbender_input"
echo "INFO: Using the following arguments: \${args:-None}"

cellbender remove-background \
    \$args \
    --input \$cellbender_input \
    --output "$meta.id"
