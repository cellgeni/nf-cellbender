// CellBender 0.3 remove-background: removes ambient RNA and empty droplets from single-cell data
process CELLBENDER_REMOVEBACKGROUND_V03 {
    tag meta.id
    container 'quay.io/cellgeni/cellbender:0.3'

    input:
    // expected_cells, total_droplets, low_count_threshold: integers, or null/[] to leave them to the
    // preset (task.ext.preset: auto, mapper or off); exclude_features: list of feature types, or []
    tuple val(meta), path(input, stageAs: 'input/*'), val(expected_cells), val(total_droplets), val(low_count_threshold), val(exclude_features)

    output:
    tuple val(meta), path("${meta.id}"),        emit: outputdir  // the whole folder, for the QC
    tuple val(meta), path("${meta.id}/*.h5"),   emit: h5         // cellbender, _filtered and _posterior
    tuple val(meta), path("${meta.id}/*.csv"),  emit: csv        // cell barcodes, metrics and excluded features
    tuple val(meta), path("${meta.id}/*.pdf"),  emit: pdf
    tuple val(meta), path("${meta.id}/*.html"), emit: html
    tuple val(meta), path("${meta.id}/*.log"),  emit: log
    tuple val("${task.process}"), val('cellbender'), eval('cellbender --version'), emit: versions_cellbender, topic: versions

    script:
    def args    = task.ext.args ?: ''
    def exclude = (exclude_features ?: []) as List
    // Values given for the sample; null, [] and '' mean not given
    def given   = [
        '--expected-cells'     : expected_cells,
        '--total-droplets'     : total_droplets,
        '--low-count-threshold': low_count_threshold,
    ].findAll { _flag, value -> value != null && value != [] && value != '' }
    def prepare = [
        "--cellbender-version 0.3",
        "--starsolo-mapper ${task.ext.starsolo_mapper ?: 'GeneFull'}",
        exclude                            ? "--exclude-features " + exclude.collect { feature -> "\"${feature}\"" }.join(' ') : '',
        "--preset ${task.ext.preset ?: 'auto'}",
        task.ext.filter_features == false  ? '--keep-all-features'                          : '',
    ].findAll { flag -> flag }.plus(given.collect { flag, value -> "${flag} ${value}" }).join(' ')
    def exclude_args = exclude ? "--exclude-feature-types " + exclude.collect { feature -> "\"${feature}\"" }.join(' ') : ''
    """
    # Find the raw matrix, the features to ignore and the cell and droplet numbers (see the module
    # README). Every feature left out of the model is listed in excluded_features.csv
    mkdir -p "${meta.id}"
    prepare_cellbender.py --input ${input} ${prepare} --excluded-file "${meta.id}/excluded_features.csv"

    # One argument per line, so file names and feature types with spaces stay whole
    mapfile -t prepared_args < cellbender.args

    cellbender remove-background \\
        ${args} \\
        ${exclude_args} \\
        "\${prepared_args[@]}" \\
        --output "${meta.id}/cellbender.h5" \\
        --cuda
    """

    stub:
    """
    mkdir -p "${meta.id}"
    touch "${meta.id}/cellbender.h5" "${meta.id}/cellbender_filtered.h5" "${meta.id}/cellbender_posterior.h5" \\
        "${meta.id}/cellbender_cell_barcodes.csv" "${meta.id}/cellbender_metrics.csv" "${meta.id}/excluded_features.csv" \\
        "${meta.id}/cellbender.pdf" "${meta.id}/cellbender_report.html" "${meta.id}/cellbender.log"
    """
}
