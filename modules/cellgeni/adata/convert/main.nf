// Converts a single-cell matrix (10x .h5, CellBender output, .mtx folder, loom, ...) to another
// format with adata-cli: an AnnData .h5ad store unless ext.extension says otherwise
process ADATA_CONVERT {
    tag "${meta.id}"
    container 'quay.io/cellgeni/adata-cli:0.17.5'

    input:
    tuple val(meta), path(input, stageAs: 'input/*')

    output:
    tuple val(meta), path("${task.ext.prefix ?: meta.id}.${task.ext.extension ?: 'h5ad'}"), emit: converted
    tuple val("${task.process}"), val('adata'), eval('adata --version'), emit: versions_adata, topic: versions

    script:
    def args   = task.ext.args ?: ''
    def output = "${task.ext.prefix ?: meta.id}.${task.ext.extension ?: 'h5ad'}"
    """
    adata convert ${input} -o ${output} ${args}
    """

    stub:
    def output = "${task.ext.prefix ?: meta.id}.${task.ext.extension ?: 'h5ad'}"
    """
    touch ${output}
    """
}
