// Imports
include { CELLBENDER_REMOVEBACKGROUND_V02 } from './modules/cellgeni/cellbender/removebackground_v02'
include { CELLBENDER_REMOVEBACKGROUND_V03 } from './modules/cellgeni/cellbender/removebackground_v03'
include { CELLBENDER_QC } from './modules/cellgeni/cellbender/qc'
include { IRODS_LOADCATALOG } from './modules/local/irods/loadcatalog'
include { MULTIQC } from './modules/local/multiqc'
include { validateParameters; paramsHelp; paramsSummaryLog; samplesheetToList } from 'plugin/nf-schema'

workflow {
  if (params.help || params.helpFull) {
    // --help prints the top-level parameters, --help <param> details one parameter, --helpFull prints all of them
    log.info paramsHelp(parameter: params.help.toString() in ['true', 'false'] ? null : params.help)
  }
  else {
    // Types, enums and cross-parameter rules (costcode for cub/tiger queues, version-specific options) are in nextflow_schema.json
    validateParameters()
    log.info paramsSummaryLog()

    // Sample table rows become [meta, path], checked against assets/schema_sample_table.json
    def files = channel.fromList(samplesheetToList(params.sample_table, "${projectDir}/assets/schema_sample_table.json"))

    // Get the data from IRODS
    if (params.on_irods) {
      IRODS_LOADCATALOG(files)
      files = IRODS_LOADCATALOG.out.catalog
    }

    // Run cellbender with the module pinned to the requested version (--version 0.2 arrives as a number)
    def cellbender_outputdir
    if (params.version.toString() == '0.2') {
      CELLBENDER_REMOVEBACKGROUND_V02(files)
      cellbender_outputdir = CELLBENDER_REMOVEBACKGROUND_V02.out.outputdir
    }
    else {
      CELLBENDER_REMOVEBACKGROUND_V03(files)
      cellbender_outputdir = CELLBENDER_REMOVEBACKGROUND_V03.out.outputdir
    }

    // QC across all samples: PDF + TSV, and an HTML report through MultiQC
    CELLBENDER_QC(cellbender_outputdir.map { _meta, outputdir -> outputdir }.collect())
    MULTIQC(CELLBENDER_QC.out.multiqc_files, file("${projectDir}/assets/multiqc_config.yaml"))
  }
}
