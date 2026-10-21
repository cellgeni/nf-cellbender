// Aggregates MultiQC input files (tool outputs or *_mqc custom content) into an HTML report
process MULTIQC {
    tag "Building MultiQC report"
    container 'quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2'

    input:
    path multiqc_files, stageAs: 'multiqc_input/*'
    path multiqc_config  // optional: pass [] to use MultiQC's defaults

    output:
    path "multiqc_report.html", emit: report
    path "multiqc_data",        emit: data
    path "versions.yml",        emit: versions

    script:
    def args   = task.ext.args ?: ''
    def config = multiqc_config ? "--config ${multiqc_config}" : ''
    """
    # MultiQC builds the report in a temporary folder and then moves it here. Keep that folder
    # inside the work directory, so the move stays on one filesystem and the outputs inherit
    # the work directory's group (a copy from /tmp gets the user's primary group instead)
    export TMPDIR=\$PWD/.multiqc_tmp
    mkdir -p \$TMPDIR

    multiqc \\
        --force \\
        --filename multiqc_report.html \\
        ${config} \\
        ${args} \\
        multiqc_input

    # The data folder is named after the report file; keep a fixed name for the output
    if [[ -d multiqc_report_data ]]; then mv multiqc_report_data multiqc_data; fi
    rm -rf \$TMPDIR

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        multiqc: \$(multiqc --version | sed 's/.*version //')
    END_VERSIONS
    """

    stub:
    """
    mkdir multiqc_data
    touch multiqc_report.html

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        multiqc: \$(multiqc --version | sed 's/.*version //')
    END_VERSIONS
    """
}
