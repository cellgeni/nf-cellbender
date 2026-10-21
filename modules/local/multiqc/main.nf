// Renders MultiQC custom content into an HTML report
process MULTIQC {
    tag "Building MultiQC report"

    container 'quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2'

    input:
    path multiqc_files, stageAs: 'multiqc_input/*'
    path multiqc_config

    output:
    path "multiqc_report.html", emit: report
    path "multiqc_data",        emit: data
    path "versions.yml",        emit: versions

    script:
    def args = task.ext.args ?: ''
    """
    multiqc \\
        --force \\
        --config ${multiqc_config} \\
        ${args} \\
        multiqc_input

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
