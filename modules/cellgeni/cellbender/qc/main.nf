// Collects QC statistics and plots from a group of CellBender outputs (and, in QC mode 3, their inputs)
// into a PDF, a TSV and MultiQC custom content
process CELLBENDER_QC {
    tag "${meta.id}"
    container 'quay.io/cellgeni/cellbender:0.3'

    input:
    tuple val(meta), path(cellbender_output, stageAs: 'cellbender_output/*')

    output:
    tuple val(meta), path("qc_report"),                 emit: report
    tuple val(meta), path("qc_report/multiqc/*_mqc.*"), emit: multiqc_files
    path "versions.yml",                                emit: versions

    script:
    def args    = task.ext.args ?: ''
    def qc_mode = task.ext.qc_mode ?: 3
    """
    cellbender_qc.py \\
        cellbender_output \\
        --mode ${qc_mode} \\
        --out qc_report \\
        --verbose \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | cut -d' ' -f 2)
        h5py: \$(python -c "import h5py; print(h5py.__version__)")
        matplotlib: \$(python -c "import matplotlib; print(matplotlib.__version__)")
        numpy: \$(python -c "import numpy; print(numpy.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """

    stub:
    """
    mkdir -p qc_report/multiqc
    touch qc_report/cellbender_qc_summary.tsv qc_report/cellbender_qc_report.pdf
    touch qc_report/multiqc/cellbender_summary_mqc.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | cut -d' ' -f 2)
        h5py: \$(python -c "import h5py; print(h5py.__version__)")
        matplotlib: \$(python -c "import matplotlib; print(matplotlib.__version__)")
        numpy: \$(python -c "import numpy; print(numpy.__version__)")
        pandas: \$(python -c "import pandas; print(pandas.__version__)")
    END_VERSIONS
    """
}
