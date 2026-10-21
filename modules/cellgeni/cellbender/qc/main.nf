// Collects QC statistics and plots from CellBender outputs into a PDF, a TSV and MultiQC custom content
process CELLBENDER_QC {
    tag "Running quality control"

    container 'quay.io/cellgeni/cellbender:0.3'

    input:
    path cellbender_output, stageAs: 'cellbender_output/*'

    output:
    path "qc_report",                 emit: report
    path "qc_report/multiqc/*_mqc.*", emit: multiqc_files
    path "versions.yml",              emit: versions

    script:
    """
    cellbender_qc.py \\
        cellbender_output \\
        --mode ${task.ext.qc_mode ?: 3} \\
        --out qc_report \\
        --verbose

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | cut -d' ' -f 2)
        h5py: \$(python -c "import h5py; print(h5py.__version__)")
        matplotlib: \$(python -c "import matplotlib; print(matplotlib.__version__)")
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
    END_VERSIONS
    """
}
