// Imports
include { CELLBENDER_REMOVEBACKGROUND_V02 } from './modules/cellgeni/cellbender/removebackground_v02'
include { CELLBENDER_REMOVEBACKGROUND_V03 } from './modules/cellgeni/cellbender/removebackground_v03'
include { IRODS_LOADCATALOG } from './modules/local/irods/loadcatalog'
include { validateParameters; paramsHelp; paramsSummaryLog; samplesheetToList } from 'plugin/nf-schema'

process QualityControl {
  tag "Running quality control"

  input:
  tuple val(meta), path(cellbender_output, stageAs: 'cellbender_output/*')

  output:
  path 'qc_report', emit: report
  path "versions.yml", emit: versions

  script:
  """
  mkdir "qc_report"
  cellbender_qc.R \
    cellbender_output \
    -m ${task.ext.qc_mode} \
    -o "qc_report"
  
  cat <<-END_VERSIONS > versions.yml
  "${task.process}":
      R: \$(Rscript --version | head -n 1)
      Matrix: \$(Rscript -e "packageVersion('Matrix')")
  END_VERSIONS
  """
}

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
    def cellbender_output = cellbender_outputdir.collect(flat: false).transpose().toList()

    // Run QC
    QualityControl(cellbender_output)
  }
}
