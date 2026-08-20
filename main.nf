// Imports
include { CELLBENDER_REMOVEBACKGROUND } from './modules/local/cellbender/removebackground'
include { IRODS_LOADCATALOG } from './modules/local/irods/loadcatalog'

def helpMessage() {
  log.info(
    """
    ===================
    nf-cellbender pipeline
    ===================
    This pipeline runs Cellbender to eliminate technical artifacts from high-throughput single-cell omics data using Nextflow.

    Usage: nextflow run main.nf [parameters]

    Required parameters:
      --sample_table <string>   Path to a .csv file with sample IDs and paths to CellRanger/STARsolo output, .h5, or .mtx directory
      --cells <int>             Number of cells (required for version 0.2 with .h5 or .mtx input)
      --droplets <int>          Number of droplets (required for version 0.2 with .h5 or .mtx input)

    Optional parameters:
      --help                    Display this help message
      --on_irods                Set this flag if the sample table points to IRODS catalog
      --ignore_extensions       File extensions to ignore during IRODS catalog loading (default: "bam,cram,fastq,fq,fastq.gz,fq.gz,fastq.bz2,fq.bz2,fastq.xz,fq.xz,fastq.lz4,fq.lz4,mate1.bz2,mate2.bz2")
      --mapper_preset           Use CellRanger/STARsolo output to estimate --cells, --droplets, --min_umi (whole output dir required)
      --starsolo_mapper         STARsolo output type for CellBender (default: "GeneFull")
      --exclude_features        Comma-separated features to exclude (see README for options)
      --epochs                  Number of epochs
      --fpr                     False positive rate
      --lr                      Learning rate
      --min_umi                 Lower bound for empty-droplet UMI count
      --force_empty_umi_prior   Higher bound for empty-droplet UMI count
      --estimator               Estimator for posterior generation (default: "mckp")
      --version                 Cellbender version (available: 0.2, 0.3; default: 0.3)
      --qc_mode                 Quality control mode (default: 3)
      --output_dir              Output directory (default: results)
      --gpuqueue                GPU queue to submit cellbender jobs to (e.g. "gpu-normal", "cub22-inference"; default: "gpu-normal"). "tiger" queues are not supported; "cub" queues require --costcode
      --costcode                Costcode to bill the job to (only required if --gpuqueue is a "cub" queue)

    Examples:
      # Basic usage - CellBender v0.2 with local data (manual cell/droplet counts required)
      nextflow run main.nf --version "0.2" --sample_table examples/sample_table.csv --cells <val> --droplets <val>
      
      # Basic usage - CellBender v0.3 with iRODS data (automatic parameter estimation)
      nextflow run main.nf --sample_table examples/sample_table_irods.csv --on_irods
      
      # Use mapper preset - CellBender v0.2 (preset applied by default for v0.2)
      nextflow run main.nf --sample_table examples/sample_table_preset.csv --version "0.2" --on_irods
      
      # Use mapper preset - CellBender v0.3 (explicitly enable preset for v0.3)
      nextflow run main.nf --sample_table examples/sample_table_preset.csv --on_irods --mapper_preset --version "0.3"
      
      # Exclude features - CellBender v0.2 (only "All" option available)
      nextflow run main.nf --version "0.2" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "All"
      
      # Exclude features - CellBender v0.3 (specify comma-separated feature types)
      nextflow run main.nf --version "0.3" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "Peaks,Multiplexing Capture,CRISPR Guide Capture" --mapper_preset
      
      # Advanced usage - CellBender v0.2 with feature exclusion, custom extensions, and output directory
      nextflow run main.nf --version "0.2" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "All" --ignore_extensions "bam,bz2" --output_dir "my-cellbender-v2-results"
      
      # Advanced usage - CellBender v0.3 with multiple feature exclusions, custom extensions, and output directory
      nextflow run main.nf --version "0.3" --sample_table examples/sample_table_exclude_features.csv --on_irods --exclude_features "Peaks,Multiplexing Capture,CRISPR Guide Capture" --ignore_extensions "bam,bz2" --output_dir "my-cellbender-v3-results"

    For more details, see the README.md file in this repository.
    """.stripIndent()
  )
}

def missingParametersError() {
  log.error("Missing input parameters")
  helpMessage()
  error("Please provide all required parameters: --sample_table, --mapper and --solo_quant (only required if --mapper is \"starsolo\")")
}


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
  if (params.help) {
    helpMessage()
  }
  else {
    // Check that all required parameters are provided
    if (params.sample_table == null) {
      missingParametersError()
    }

    // Check that costcode is provided for cub and tiger clusters
    if (params.gpuqueue.contains("tiger")) {
      log.error "Tiger cluster is not suited for running this pipeline. Please use cub cluster instead."
      error "Use --gpuqueue cub22-inference --costcode <costcode> to run the pipeline on cub cluster"
    }
    else if (params.gpuqueue.contains("cub") && params.costcode == "") {
      log.error "Missing costcode parameter"
      error "Please provide a costcode using the --costcode parameter"
    }

    // Puts samplefile into a channel unless it is null, if it is null then it displays error message and exits with status 1.
    sample_table = params.sample_table != null ? Channel.fromPath(params.sample_table) : missingParametersError()
    files = sample_table.splitCsv(sep: ',', header: true).map { row -> [row, row["path"]] }

    // Get the data from IRODS
    if (params.on_irods) {
      IRODS_LOADCATALOG(files)
      files = IRODS_LOADCATALOG.out.catalog
    }

    // Run cellbender
    CELLBENDER_REMOVEBACKGROUND(files)
    cellbender_output = CELLBENDER_REMOVEBACKGROUND.out.outputdir.collect(flat: false).transpose().toList()

    // Run QC
    QualityControl(cellbender_output)
  }
}
