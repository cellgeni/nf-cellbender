#!/bin/bash

# enable extglob so ?(…) works
shopt -s extglob

# Variables
cellbender_input=""

### Figure out the input structure. See a diagram explaining the steps here: FUTURE LINK
# Check if exists cellranger's input/outs directory
input="$input"
if [[ -d "\$input/outs" ]]; then
    input="\$input/outs"
fi

# Check if input is a directory
if [[ -d "\$input" ]]; then
    # Check if it's output from cellranger multi
    if [[ -d "\$input/multi" ]]; then
        echo "INFO: \$input directory contains cellranger multi output structure"
        mapper="cellranger_multi"
        cellbender_input="\$input/multi/count/raw_feature_bc_matrix"
        filt_bc_old=\$input/multi/per_sample_outs/*/count/sample_feature_bc_matrix/barcodes.tsv.gz
        filt_bc=\$input/multi/per_sample_outs/*/count/sample_filtered_feature_bc_matrix/barcodes.tsv.gz
        filt_bc_count=\$(zcat \$filt_bc \$filt_bc_old | wc -l)
    # Check if it's output from cellranger-atac
    elif [[ -f "\$input/filtered_peak_bc_matrix.h5" ]]; then
        echo "INFO: \$input directory contains cellranger-atac output structure"
        mapper="cellranger-atac"
        cellbender_input="\$input/raw_peak_bc_matrix"
        filt_bc_count=\$(zcat \$input/filtered_peak_bc_matrix/barcodes.tsv | wc -l)
    # Check if it's output from cellranger-arc
    elif [[ -f "\$input/atac_fragments.tsv.gz" && -f "\$input/filtered_feature_bc_matrix.h5" ]]; then
        echo "INFO: \$input directory contains cellranger-arc output structure"
        mapper="cellranger-arc"
        cellbender_input="\$input/raw_feature_bc_matrix"
        filt_bc_count=\$(zcat \$input/filtered_feature_bc_matrix/barcodes.tsv | wc -l)
    # Check if it's output from cellranger count
    elif [[ -f "\$input/filtered_feature_bc_matrix.h5" && -f "\$input/raw_feature_bc_matrix.h5" ]]; then
        echo "INFO: \$input directory contains cellranger count output structure"
        mapper="cellranger_count"
        cellbender_input="\$input/raw_feature_bc_matrix"
        filt_bc_count=\$(zcat \$input/filtered_feature_bc_matrix/barcodes.tsv | wc -l)
    # Check if it's output from STARsolo
    elif [[ -d "$input/output" ]]; then
        echo "INFO: ${input} directory contains STARsolo output structure"
        mapper="starsolo"
        cellbender_input="$input/output/${task.ext.starsolo_mapper}/raw"
        filt_bc_count=\$(zcat "${input}/output/${task.ext.starsolo_mapper}/filtered/barcodes.tsv.gz" | wc -l)
    # Check if it's output from 10x Genomics
    elif [ -f "$input"/matrix.mtx?(.gz) ] && [ -f "$input"/barcodes.tsv?(.gz) ] && [ -f "$input"/features.tsv?(.gz) ]; then
        echo "INFO: ${input} directory contains 10x Genomics output structure"
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

# Initialize variables
expected_cells=""
total_droplets=""
umi_threshold=""

# Check of cellranger of version 2 is requested or if user requested to use mapper's preset for the params
if [[ "${task.ext.version}" == "0.2" || "${task.ext.mapper_preset}" == "true" ]]; then
    echo "INFO: Using mapper's preset for parameters"
    # Check if full mapper directory was passed as an input to use mapper's preset
    if [[ "\$mapper" == unknown* ]]; then
        echo "Error: Mapper preset is not available for unknown mapper type. Please specify expected cells, droplets and UMI threshold manually." >&2
        exit 1
    fi

    # Import preset functions
    source preset.sh

    # Calculate presets
    expected_cells=\$(preset_cells "\$cellbender_input" \$filt_bc_count)
    expected_cells_arg="--expected-cells \$expected_cells"
    total_droplets=\$(preset_droplets \$expected_cells)
    total_droplets_arg="--total-droplets-included \$total_droplets"
    umi_threshold_arg="--low-count-threshold \$(preset_umi_threshold "\$cellbender_input" \$total_droplets)"
    echo "INFO: Using preset values: expected_cells=\$expected_cells_arg, total_droplets=\$total_droplets_arg, umi_threshold=\$umi_threshold_arg"
fi

# Use user-specified parameters if provided
if [[ ${task.ext.expected_cells} != "null" ]]; then
    expected_cells="--expected-cells ${task.ext.expected_cells}"
fi
if [[ ${task.ext.total_droplets} != "null" ]]; then
    total_droplets="--total-droplets-included ${task.ext.total_droplets}"
fi
if [[ ${task.ext.umi_threshold} != "null" ]]; then
    umi_threshold="--low-count-threshold ${task.ext.umi_threshold}"
fi


### Create output directory
mkdir -p "${meta.id}"

### Save file version information
if [[ $task.ext.version == "0.2" ]]; then
    version=\$(grep "version" /opt/cellbender/setup.py | cut -d"'" -f 2)
elif [[ $task.ext.version == "0.3" ]]; then
    version=\$(cellbender --version)
else
    echo "Error: Unsupported CellBender version specified: ${task.ext.version}" >&2
fi
cat <<-END_VERSIONS > versions.yml
"${task.process}":
    cellbender: \$version
END_VERSIONS

### Run CellBender

echo "INFO: Running CellBender remove-background with input: \$cellbender_input"
echo "INFO: Using the following arguments: \$expected_cells \$total_droplets \$umi_threshold ${task.ext.args ?: ''}"

cellbender remove-background \
    ${task.ext.args ?: ''} \
    \$expected_cells_arg \
    \$total_droplets_arg \
    \$umi_threshold_arg \
    --input \$cellbender_input \
    --output "${meta.id}/cellbender.h5" \
    --cuda
