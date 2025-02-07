#!/usr/bin/env nextflow

nextflow.enable.dsl=2

def helpMessage() {
    log.info"""
    ===================
    Cellbender pipeline
    ===================
    This pipeline runs Cellbender to eliminate technical artifacts from high-throughput single-cell omics data 
    Usage: nextflow run main.nf [parameters]
        Required parameters:
            --sample_table <string>  Path to a .tsv file containing a list of sample IDs and paths to mappers result directory (see in example directory)
            --mapper       <string>  Either "cellranger" or "starsolo"
            --solo_quant   <string>  Either "Gene" or "GeneFull"(only required if --mapper is "starsolo")
        
        Optional parameters:
            --help         Display this help message
            --on_irods     Set this flag if the data is on IRODS
            --outdir       Output directory (default: cellbender-results)
            --cells        Number of cells (default: "cellbender-default")
            --droplets     Number of droplets (default: "cellbender-default")
            --epochs       Number of epochs (default: "cellbender-default")
            --fpr          False positive rate (default: "cellbender-default")
            --lr           Learning rate (default: "cellbender-default")
            --min_umi      Minimal UMI threshold (default: "cellbender-default") 
            --version      Cellbender version (available: 0.2, 0.3; default: 0.3)
            --qc_mode      Quality control mode (default: 3)
    """.stripIndent()
}

def missingParametersError() {
    log.error "Missing input parameters"
    helpMessage()
    error "Please provide all required parameters: --sample_table, --mapper and --solo_quant (only required if --mapper is \"starsolo\")"
}

process LoadFromIrods {
  tag "Getting the data for sample ${sample} from IRODS"
  input:
  tuple val(sample), val(catalog_path)


  output:
  tuple val(sample), path('*')

  script:
  """
  iget -f -v -K -r "${catalog_path}" "input_data"
  """
}

process RemoveBackground {
  tag "Running cellbender for sample ${sample}"

  input:
  tuple val(sample), path(mapper_output, stageAs: 'mapper_output')
  val mapper
  val solo_quant
  val cells
  val droplets
  val epochs
  val fpr
  val lr
  val min_umi
  val version

  output:
  path("${sample}")
  
  script:
    """
    cellbender.sh \
      --sample ${sample} \
      --mapper_output ${mapper_output} \
      --mapper ${mapper} \
      --solo_quant ${solo_quant} \
      --cells ${cells} \
      --droplets ${droplets} \
      --min_umi ${min_umi} \
      --epochs ${epochs} \
      --fpr ${fpr} \
      --learning_rate ${lr} \
      --version ${version}
    """
}

process QualityControl {
  tag "Running quality control"
  input:
  path(cellbender_output, stageAs: 'cellbender_output/*')
  val(qc_mode)

  output:
  path('qc_report')

  script:
  """
  mkdir "qc_report"
  cellbender_qc.R \
    "cellbender_output" \
    -m ${qc_mode} \
    -o "qc_report"
  """
}

workflow {
  if (params.help) {
    helpMessage()
  }
  else {
    // Check that all required parameters are provided
    if (params.sample_table == null || params.mapper == null || (params.mapper == "starsolo" && params.solo_quant == "")) {
      missingParametersError()
    }
    // Puts samplefile into a channel unless it is null, if it is null then it displays error message and exits with status 1.
    sample_table = params.sample_table != null ? Channel.fromPath(params.sample_table) : missingParametersError()
    sample_list = sample_table.splitCsv(sep: '\t', strip: true)
    sample_list.view()

    // Get the data from IRODS
    if (params.on_irods) {
      sample_list = LoadFromIrods(sample_list)
    }
    sample_list.view()

    // Run cellbender
    RemoveBackground(
      sample_list,
      params.mapper,
      params.solo_quant,
      params.cells,
      params.droplets,
      params.epochs,
      params.fpr,
      params.lr,
      params.min_umi,
      params.version,
    )
    cellbender_output = RemoveBackground.out.collect()
    cellbender_output.view()
    
    // Run QC
    QualityControl(cellbender_output, params.qc_mode)
  }
}
