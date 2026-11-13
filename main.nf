// IMPORT SUBWORKFLOW
include { CELLBENDER } from './workflow/main.nf'
include { CELLBENDER_QC } from './modules/cellgeni/cellbender/qc'
include { MULTIQC } from './modules/cellgeni/multiqc'
include { validateParameters; paramsHelp; paramsSummaryLog; samplesheetToList } from 'plugin/nf-schema'

// HELP MESSAGE: the parameter list itself is generated from nextflow_schema.json by nf-schema
def helpBefore() {
    """
    ======================
    nf-cellbender pipeline
    ======================
    This pipeline runs CellBender remove-background to eliminate technical artifacts
    from high-throughput single-cell omics data, then builds a QC report across samples.

    == sample table (comma-separated) ==
    id,path
    sample1,/path/to/cellranger/output
    sample2,/path/to/raw_feature_bc_matrix.h5

    path is a CellRanger/STARsolo output directory (or one sample of a CellRanger multi
    Flex run), a .h5 file or a .mtx directory; with --on_irods it is an iRODS collection instead.

    An optional group column (id,group,path) splits the samples into datasets: each group
    gets its own QC report, and its outputs go to <outdir>/<group>/.

    Optional cells, droplets, min_umi and exclude_features columns set those values per sample;
    an empty cell leaves the number to --preset, and excludes no features.
    """.stripIndent()
}

def helpShort() {
    """
    Usage:
      nextflow run main.nf --samples <samples.csv> [--version 0.2|0.3] [--on_irods] [--outdir results]

    Run with --help for the main parameters and examples, --help <param> for one parameter,
    or --helpFull for all of them.

    Documentation: https://cellgeni.github.io/nf-cellbender/
    """.stripIndent()
}

def helpAfter() {
    """
    == Examples ==
    # CellBender 0.3 on local CellRanger/STARsolo folders, .h5 files or .mtx folders
    nextflow run main.nf --samples examples/samples.csv

    # Sample folders on iRODS
    nextflow run main.nf --samples examples/samples_irods.csv --on_irods

    # Samples in groups (id,group,path): one QC report and one output folder per group
    nextflow run main.nf --samples examples/samples_groups.csv --on_irods

    # The samples of a Flex run one by one, with cells and droplets from CellRanger's cell calls
    nextflow run main.nf --samples examples/samples_flex_per_sample.csv --on_irods --preset mapper

    # Cells, droplets and excluded feature types set per sample; the empty cells are estimated.
    # With --preset off nothing is estimated, and every sample needs cells and droplets
    nextflow run main.nf --samples examples/samples_per_sample_params.csv --on_irods

    # The cub22 GPU queue, billed to a costcode
    nextflow run main.nf --samples examples/samples.csv --gpuqueue cub22-inference --costcode s1234

    Documentation, more examples and the output layout: https://cellgeni.github.io/nf-cellbender/
    """.stripIndent()
}

// A cell of the samples table, or null when it is empty (nf-schema gives [])
def sampleValue(value) {
    return value == null || value == [] || value == '' ? null : value
}

// Feature types to exclude, from the exclude_features column: comma-separated.
// All (the CellBender 0.2 value) means Antibody Capture
def excludeList(value) {
    if (!value) {
        return []
    }
    return value.toString().tokenize(',').collect { feature -> feature.trim() == 'All' ? 'Antibody Capture' : feature.trim() }.unique()
}

workflow {
    main:
    if (params.help || params.helpFull) {
        // --help prints the top-level parameters, --help <param> details one parameter, --helpFull prints all of them
        log.info paramsHelp(
            parameter : params.help.toString() in ['true', 'false'] ? null : params.help,
            beforeText: helpBefore(),
            afterText : helpAfter(),
            command   : "nextflow run main.nf --samples examples/samples.csv"
        )
        System.exit(0)
    }

    // Without a sample table there is nothing to run: show how to start instead of a validation error
    if (!params.samples) {
        log.info helpBefore() + helpShort()
        System.exit(1)
    }

    // nf-schema only warns about an unknown parameter, so a removed one would be dropped quietly
    // and the run would estimate instead
    def removed = [
        mapper_preset   : "use --preset mapper (or --preset auto, the default, or --preset off)",
        cells           : "set it per sample in the samples table's cells column",
        droplets        : "set it per sample in the samples table's droplets column",
        min_umi         : "set it per sample in the samples table's min_umi column",
        exclude_features: "set it per sample in the samples table's exclude_features column",
    ].findAll { name, _hint -> params.containsKey(name) }
    if (removed) {
        error(removed.collect { name, hint -> "--${name} was removed: ${hint}." }.join(' '))
    }

    // Types, enums and cross-parameter rules (costcode only for cub/tiger queues, version-specific
    // options, --ignore_extensions only with --on_irods) are checked against nextflow_schema.json
    // before anything is downloaded or submitted
    validateParameters()
    log.info paramsSummaryLog()

    // Define variables
    def on_irods = params.on_irods as boolean
    def version  = params.version.toString()  // --version 0.2 on the command line arrives as a number

    // Load files: sample table rows become [meta, path, cells, droplets, min_umi, exclude_features],
    // checked against assets/schema_samples.json
    def rows = samplesheetToList(params.samples, "${projectDir}/assets/schema_samples.json")

    // The schema accepts the exclude_features of either version; which ones apply depends on --version
    def bad_exclude = rows.findAll { row ->
        def types = row[5] ? row[5].toString().tokenize(',').collect { feature -> feature.trim() } : []
        version == '0.2' ? types.any { feature -> feature != 'All' } : types.contains('All')
    }.collect { row -> row[0].id }
    if (bad_exclude) {
        error("--samples (${params.samples}): exclude_features of ${bad_exclude.join(', ')} " + (version == '0.2'
            ? "must be All: CellBender 0.2 can only exclude antibody capture features."
            : "uses All, which is for CellBender 0.2; with CellBender 0.3 name the feature types, e.g. Antibody Capture."))
    }

    // An empty cell (or a missing column) is null: --preset fills it. nf-schema sets meta.group
    // to [] when the table has no group column or the cell is empty; dropping it keeps the meta of an
    // ungrouped run [id: ...], as before, so index files and -resume are unchanged
    def sample_list = rows.collect { meta, path, cells, droplets, min_umi, exclude_features ->
        [
            meta.group ? meta : meta.findAll { key, _value -> key != 'group' },
            path,
            sampleValue(cells),
            sampleValue(droplets),
            sampleValue(min_umi),
            excludeList(sampleValue(exclude_features)),
        ]
    }

    // --preset off passes only the values given, so every sample needs cells and droplets
    if (params.preset == 'off') {
        def missing = [cells: 2, droplets: 3].collect { name, index ->
            def ids = sample_list.findAll { row -> row[index] == null }.collect { row -> row[0].id }
            ids ? "${name} missing for ${ids.join(', ')}" : null
        }.findAll { message -> message }
        if (missing) {
            error("--preset off uses only the values given: ${missing.join('; ')}. Give them in the samples table's cells and droplets columns, or use --preset auto (CellBender's estimate) or --preset mapper (the mapper's cell calls).")
        }
    }

    // With a group column, every sample needs a group: no silent fallback to the top-level folders.
    // A missing column and an empty cell both come out as [], so the header decides whether the column is
    // there (the index files quote their column names)
    def header           = file(params.samples).readLines().find { line -> line.trim() } ?: ''
    def has_group_column = header.split(',').collect { column -> column.trim().replaceAll(/^"|"$/, '') }.contains('group')
    def ungrouped        = sample_list.findAll { row -> !row[0].group }.collect { row -> row[0].id }
    if (has_group_column && ungrouped) {
        error("--samples (${params.samples}): no group for ${ungrouped.join(', ')}. Give every sample a group, or leave the group column out.")
    }

    samples        = channel.fromList(sample_list)
    multiqc_config = channel.value(file("${projectDir}/assets/multiqc_config.yaml", checkIfExists: true))

    // Run main workflow
    CELLBENDER(
        samples,
        on_irods,
        version
    )

    // QC per sample group: PDF + TSV, and an HTML report through MultiQC. Without a group column
    // all samples are one group, 'all'. Sorted, so the QC task is cached on -resume
    qc_input = CELLBENDER.out.outputdir
        .map { meta, outputdir -> [meta.group ? [id: meta.group, group: meta.group] : [id: 'all'], outputdir] }
        .groupTuple(sort: true)

    CELLBENDER_QC(
        qc_input
    )
    MULTIQC(
        CELLBENDER_QC.out.multiqc_files,
        multiqc_config
    )

    // One versions.yml for the run, from the [process, tool, version] tuples every module sends to the
    // 'versions' topic: one entry per process, its tools sorted
    versions = channel.topic('versions')
        .unique()
        .map { process, tool, version_number -> [process, "    ${tool}: ${version_number}"] }
        .groupTuple(sort: true)
        .map { process, tools -> "\"${process}\":\n" + tools.unique().sort().join('\n') }
        .collectFile(name: 'versions.yml', sort: true, newLine: true)

    publish:
    // Records with a path field (and group, when set), so outputs can be routed to their group's
    // folder and each sample output also gets an index CSV (id,path or id,group,path)
    raw        = CELLBENDER.out.raw.map { meta, dir -> meta + [path: dir] }
    cellbender = CELLBENDER.out.outputdir.map { meta, dir -> meta + [path: dir] }
    qc_report  = CELLBENDER_QC.out.report.map { meta, report -> meta + [path: report] }
    multiqc    = MULTIQC.out.report.mix(MULTIQC.out.data).map { meta, report -> meta + [path: report] }
    versions   = versions
}

// Outputs of a sample group go to <outdir>/<group>/, those of an ungrouped run to <outdir>/
output {
    raw {
        // index/raw.csv can be passed back as --samples without --on_irods
        path { sample -> sample.group ? "${sample.group}/raw" : "raw" }
        index {
            path "index/raw.csv"
            header true
            sep ','
        }
    }
    cellbender {
        path { sample -> sample.group ? "${sample.group}/cellbender" : "cellbender" }
        index {
            path "index/cellbender.csv"
            header true
            sep ','
        }
    }
    qc_report {
        // the qc_report/ folder itself: summary TSV, PDF and MultiQC input files
        path { report -> report.group ?: "." }
    }
    multiqc {
        path { report -> report.group ? "${report.group}/qc_report" : "qc_report" }
    }
    versions {
        path "."
    }
}
