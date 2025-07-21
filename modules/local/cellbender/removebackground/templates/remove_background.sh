#!/bin/bash

# enable extglob so ?(…) works
shopt -s extglob

# Variables
cellbender_input=""
filt_bc_files=()

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
        cellbender_input="\$input/multi/count/raw_feature_bc_matrix.h5"
        filt_bc_files=(\$input/multi/per_sample_outs/*/count/sample_?(filtered_)feature_bc_matrix/barcodes.tsv?(.gz))
    # Check if it's output from cellranger-atac
    elif [[ -f "\$input/raw_peak_bc_matrix.h5" ]]; then
        echo "INFO: \$input directory contains cellranger-atac output structure"
        mapper="cellranger-atac"
        cellbender_input="\$input/raw_peak_bc_matrix.h5"
        filt_bc_files=(\$input/filtered_peak_bc_matrix/barcodes.tsv?(.gz))
    # Check if it's output from cellranger-arc
    elif [[ -f "\$input/atac_fragments.tsv.gz" && -f "\$input/filtered_feature_bc_matrix.h5" ]]; then
        echo "INFO: \$input directory contains cellranger-arc output structure"
        mapper="cellranger-arc"
        cellbender_input="\$input/raw_feature_bc_matrix.h5"
        filt_bc_files=(\$input/filtered_feature_bc_matrix/barcodes.tsv?(.gz))
    # Check if it's output from cellranger count
    elif [[ -f "\$input/filtered_feature_bc_matrix.h5" && -f "\$input/raw_feature_bc_matrix.h5" ]]; then
        echo "INFO: \$input directory contains cellranger count output structure"
        mapper="cellranger_count"
        cellbender_input="\$input/raw_feature_bc_matrix.h5"
        filt_bc_files=(\$input/filtered_feature_bc_matrix/barcodes.tsv?(.gz))
    # Check if it's output from STARsolo
    elif [[ -d "$input/output" ]]; then
        echo "INFO: ${input} directory contains STARsolo output structure"
        mapper="starsolo"
        cellbender_input="$input/output/${task.ext.starsolo_mapper}/raw"
        filt_bc_files=($input/output/${task.ext.starsolo_mapper}/filtered/barcodes.tsv?(.gz))
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

# For starsolo and raw mtx inputs check if matrix.mtx is in uncompressed format becasause CellBender expects gzipped matrix.mtx
# See https://github.com/broadinstitute/CellBender/blob/04c2f5b460721fd55cf62a4cd23617b2555d69b8/cellbender/remove_background/data/io.py#L617
if [[ -f "\$cellbender_input/matrix.mtx" ]]; then
    echo "INFO: matrix.mtx found in ugzipped format, proceding to gzip it"
    cp -r \$cellbender_input gzipped_raw_input
    gzip gzipped_raw_input/*
    cellbender_input="gzipped_raw_input"
fi

# Initialize variables
expected_cells=""
total_droplets=""
umi_threshold=""

# Check of cellranger of version 2 is requested or if user requested to use mapper's preset for the params
if [[ "${task.ext.version}" == "0.2" || "${task.ext.mapper_preset}" == "true" ]]; then
    echo "INFO: Using mapper's preset for parameters"
    # Check if full mapper directory was passed as an input to use mapper's preset
    if [[ "\$mapper" == unknown* && "${task.ext.version}" == "0.3" ]]; then
        echo "INFO: Mapper preset is not available for \"\$mapper\" input type. Skipping preset calculation." >&2
    elif [[ "\$mapper" == unknown* && "${task.ext.version}" == "0.2" ]]; then
        echo "ERROR: CellBender version 0.2 does not support mapper presets. Please specify expected_cells, total_droplets, and umi_threshold manually." >&2
    else
        # Check that filtered barcodes file exists
        if [[ -z "\$filt_bc_files" || ! -f "\${filt_bc_files[0]}" ]]; then
            echo "Error: Filtered barcodes file not found: \$filt_bc_files" >&2
            exit 1
        fi

        # Import preset functions
        source preset.sh

        # Calculate presets
        echo "DEBUG: Calculating presets for CellBender remove-background" >&2
        echo "DEBUG: Using filtered barcodes file: \${filt_bc_files[0]}" >&2
        cat_command=\$(get_cat_command "\${filt_bc_files[0]}")
        echo "DEBUG: Using command: \$cat_command" >&2
        filt_bc_count=\$(\$cat_command "\${filt_bc_files[0]}" | wc -l)
        echo "DEBUG: Filtered barcodes count: \$filt_bc_count" >&2
        expected_cells=\$(preset_cells "\${cellbender_input%.h5}" \$filt_bc_count)
        expected_cells_arg="--expected-cells \$expected_cells"
        total_droplets=\$(preset_droplets \$expected_cells)
        total_droplets_arg="--total-droplets-included \$total_droplets"
        umi_threshold_arg="--low-count-threshold \$(preset_umi_threshold "\${cellbender_input%.h5}" \$total_droplets)"
        echo "INFO: Using preset values: expected_cells=\$expected_cells_arg, total_droplets=\$total_droplets_arg, umi_threshold=\$umi_threshold_arg"
    fi
fi

# Use user-specified parameters if provided
if [[ -n "${task.ext.expected_cells}" ]]; then
    expected_cells_arg="--expected-cells ${task.ext.expected_cells}"
fi
if [[ -n "${task.ext.total_droplets}" ]]; then
    total_droplets_arg="--total-droplets-included ${task.ext.total_droplets}"
fi
if [[ -n "${task.ext.umi_threshold}" ]]; then
    umi_threshold_arg="--low-count-threshold ${task.ext.umi_threshold}"
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
echo "INFO: Using the following arguments: \$expected_cells_arg \$total_droplets_arg \$umi_threshold_arg ${task.ext.args ?: ''}"

cellbender remove-background \
    ${task.ext.args ?: ''} \
    \$expected_cells_arg \
    \$total_droplets_arg \
    \$umi_threshold_arg \
    --input \$cellbender_input \
    --output "${meta.id}/cellbender.h5" \
    --cuda
