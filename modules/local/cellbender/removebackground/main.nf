// cellbender module to remove empty droplets from single-cell data
process CELLBENDER_REMOVEBACKGROUND {
    tag "Running cellbender for sample ${meta.id}"

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://quay.io/cellgeni/cellbender:0.3':
        'quay.io/cellgeni/cellbender:0.3' }"

    input:
    tuple val(meta), path(input)

    output:
    tuple val(meta), path("${meta.id}"),      emit: outputdir
    tuple val(meta), path("${meta.id}/*.h5"), emit: h5
    path "versions.yml",                      emit: versions

    script:
    template 'remove_background.sh'

    stub:
    """
    touch ${meta.id}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cellbender: \$(cellbender --version)
    END_VERSIONS
    """
}
