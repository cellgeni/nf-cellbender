// Downloads an iRODS collection, keeping its folder layout and skipping unwanted file types
process IRODS_LOADCATALOG {
    tag "Loading catalog for $meta.id"

    input:
    tuple val(meta), val(catalog)

    output:
    tuple val(meta), path("${meta.id}"), emit: catalog
    path "versions.yml"                , emit: versions

    script:
    def args              = task.ext.args ?: '-f -v -K -X restartfile.txt --retries 5'
    def ignore_extensions = (task.ext.ignore_extensions ?: '').tokenize(',').collect { extension -> extension.trim() }.join('|')
    // Called through awk rather than from PATH, so it works even when the executable bit is lost
    def ils2paths         = "${moduleDir}/resources/usr/bin/ils2paths.awk"
    """
    # Remove any trailing slash from catalog, then add our own
    catalog="${catalog}"
    catalog="\${catalog%/}"

    # Get a list of files in the catalog
    ils -r \$catalog | awk -f ${ils2paths} > files.list

    # Ignore files with specified extensions
    if [[ -n "${ignore_extensions}" ]]; then
        grep -vE '\\.(${ignore_extensions})\$' files.list > filtered_files.list || true
    else
        cp files.list filtered_files.list
    fi

    # Download the filtered files
    mkdir -p "${meta.id}"
    while read file; do
        # Create output directory
        outputpath="${meta.id}/\${file#\${catalog}/}"
        outputdir=\$( dirname "\$outputpath" )
        mkdir -p "\$outputdir"
        # Load the data
        iget ${args} "\$file" "\$outputpath"
    done < filtered_files.list

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        irods: \$(ienv | grep version | awk '{ print \$3 }')
    END_VERSIONS
    """

    stub:
    """
    mkdir -p "${meta.id}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        irods: \$(ienv | grep version | awk '{ print \$3 }')
    END_VERSIONS
    """
}
