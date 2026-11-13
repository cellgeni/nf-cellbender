// CellBender 0.2 remove-background: removes ambient RNA and empty droplets from single-cell data
process CELLBENDER_REMOVEBACKGROUND_V02 {
    tag meta.id
    container 'quay.io/cellgeni/cellbender:0.2'

    input:
    tuple val(meta), path(input, stageAs: 'input/*')

    output:
    tuple val(meta), path("${meta.id}"),            emit: outputdir
    tuple val("${task.process}"), val('cellbender'), eval('pip show cellbender 2>/dev/null | sed -n "s/^Version: //p"'), emit: versions_cellbender, topic: versions

    script:
    template 'remove_background.sh'

    stub:
    """
    mkdir -p ${meta.id}
    """
}
