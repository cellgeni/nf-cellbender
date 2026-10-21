// CellBender 0.3 remove-background: removes ambient RNA and empty droplets from single-cell data
process CELLBENDER_REMOVEBACKGROUND_V03 {
    tag meta.id
    container 'quay.io/cellgeni/cellbender:0.3'

    input:
    tuple val(meta), path(input, stageAs: 'input/*')

    output:
    tuple val(meta), path("${meta.id}"),            emit: outputdir
    path "versions.yml",                            emit: versions

    script:
    template 'remove_background.sh'

    stub:
    """
    mkdir -p ${meta.id}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellbender: \$(cellbender --version)
    END_VERSIONS
    """
}
