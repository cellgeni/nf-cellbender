// Process to load a catalog from iRODS
process IRODS_LOADCATALOG {
    tag "Loading catalog for $meta.id"

    input:
    tuple val(meta), val(catalog)

    output:
    tuple val(meta), path("${meta.id}"), emit: catalog
    path "versions.yml"                , emit: versions

    script:
    def args = task.ext.args ?: '-f -v -K -X restartfile.txt --retries 5'
    def ignore_extensions = task.ext.ignore_extensions.replace(",", "|")
    """
    # Remove any trailing slash from catalog, then add our own
    catalog="${catalog}"
    catalog="\${catalog%/}"

    # Get a list of files in the catalog
    ils -r \$catalog | ils2paths.awk > files.list

    # Ignore files with specified extensions
    grep -vE '.($ignore_extensions)\$' files.list > filtered_files.list

    # Download the filtered files
    while read file; do
        # Create output directory
        outputpath="${meta.id}/\${file#\${catalog}/}"
        outputdir=\$( dirname "\$outputpath" )
        mkdir -p "\$outputdir"
        # Load the data
        iget $args "\$file" "\$outputpath"
    done < filtered_files.list

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        irods: \$(ienv | grep version | awk '{ print \$3 }')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: '-f -v -K -X restartfile.txt --retries 5'
    def ignore_extensions = task.ext.ignore_extensions.replace(",", "|")
    """
    echo $args
    mkdir catalog

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        irods: \$(ienv | grep version | awk '{ print \$3 }')
    END_VERSIONS
    """
}
