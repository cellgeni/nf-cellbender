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
    tuple val("${task.process}"), val('python'),     eval("python --version | cut -d' ' -f 2"),                        emit: versions_python,     topic: versions
    tuple val("${task.process}"), val('h5py'),       eval('python -c "import h5py; print(h5py.__version__)"'),             emit: versions_h5py,       topic: versions
    tuple val("${task.process}"), val('matplotlib'), eval('python -c "import matplotlib; print(matplotlib.__version__)"'), emit: versions_matplotlib, topic: versions
    tuple val("${task.process}"), val('numpy'),      eval('python -c "import numpy; print(numpy.__version__)"'),           emit: versions_numpy,      topic: versions
    tuple val("${task.process}"), val('pandas'),     eval('python -c "import pandas; print(pandas.__version__)"'),         emit: versions_pandas,     topic: versions

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
    """

    stub:
    """
    mkdir -p qc_report/multiqc
    touch qc_report/cellbender_qc_summary.tsv qc_report/cellbender_qc_report.pdf
    touch qc_report/multiqc/cellbender_summary_mqc.json
    """
}
