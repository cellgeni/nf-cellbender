// CellBender 0.2 remove-background: removes ambient RNA and empty droplets from single-cell data
process CELLBENDER_REMOVEBACKGROUND_V02 {
    tag "Running cellbender 0.2 for sample ${meta.id}"

    container 'quay.io/cellgeni/cellbender:0.2'

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
        cellbender: \$(grep "version" /opt/cellbender/setup.py | cut -d"'" -f 2)
    END_VERSIONS
    """
}
