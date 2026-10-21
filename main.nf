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

    path is a CellRanger/STARsolo output directory, a .h5 file or a .mtx directory;
    with --on_irods it is an iRODS collection instead.
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

    # The cub22 GPU queue, billed to a costcode
    nextflow run main.nf --samples examples/samples.csv --gpuqueue cub22-inference --costcode s1234

    Documentation, more examples and the output layout: https://cellgeni.github.io/nf-cellbender/
    """.stripIndent()
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

    // Types, enums and cross-parameter rules (costcode only for cub/tiger queues, version-specific
    // options, --ignore_extensions only with --on_irods) are checked against nextflow_schema.json
    // before anything is downloaded or submitted
    validateParameters()
    log.info paramsSummaryLog()

    // Load files: sample table rows become [meta, path], checked against assets/schema_samples.json
    samples        = channel.fromList(samplesheetToList(params.samples, "${projectDir}/assets/schema_samples.json"))
    multiqc_config = channel.value(file("${projectDir}/assets/multiqc_config.yaml", checkIfExists: true))

    // Define variables
    def on_irods = params.on_irods as boolean
    def version  = params.version.toString()  // --version 0.2 on the command line arrives as a number

    // Run main workflow
    CELLBENDER(
        samples,
        on_irods,
        version
    )

    // QC across all samples: PDF + TSV, and an HTML report through MultiQC
    CELLBENDER_QC(
        CELLBENDER.out.outputdir.map { _meta, outputdir -> outputdir }.collect()
    )
    MULTIQC(
        CELLBENDER_QC.out.multiqc_files,
        multiqc_config
    )

    // One versions.yml for the run: the first task of each process is enough
    versions = CELLBENDER.out.versions
        .mix(CELLBENDER_QC.out.versions, MULTIQC.out.versions)
        .collectFile(name: 'versions.yml', sort: { versions_file -> versions_file.text })

    publish:
    // Records with a path field, so each output also gets an index CSV (id,path)
    raw        = CELLBENDER.out.raw.map { meta, dir -> meta + [path: dir] }
    cellbender = CELLBENDER.out.outputdir.map { meta, dir -> meta + [path: dir] }
    qc_report  = CELLBENDER_QC.out.report
    multiqc    = MULTIQC.out.report.mix(MULTIQC.out.data)
    versions   = versions
}

output {
    raw {
        // index/raw.csv can be passed back as --samples without --on_irods
        path "raw"
        index {
            path "index/raw.csv"
            header true
            sep ','
        }
    }
    cellbender {
        path "cellbender"
        index {
            path "index/cellbender.csv"
            header true
            sep ','
        }
    }
    qc_report {
        // the qc_report/ folder itself: summary TSV, PDF and MultiQC input files
        path "."
    }
    multiqc {
        path "qc_report"
    }
    versions {
        path "."
    }
}
