#!/usr/bin/env nextflow

nextflow.enable.dsl=2

def helpMessage() {
    log.info"""
    =================
    cellbender pipeline
    =================
    This pipeline runs Cellbender. 
    """.stripIndent()
}

def errorMessage() {
    log.info"""
    ==============
    cellbender error
    ==============
    """.stripIndent()
    exit 1
}

process email_startup {
  
  shell:
  '''
  contents=`cat !{params.SAMPLEFILE}`
  sendmail "!{params.sangerID}@sanger.ac.uk" <<EOF
  Subject: Launched pipeline
  From: noreply-cellgeni-pipeline@sanger.ac.uk
  Hi there, you've launched Cellular Genetics Informatics' Cellbender pipeline.
  Your parameters are:
  Samplefile: !{params.SAMPLEFILE}
  
  Your sample file looks like:
  $contents
  Thanks,
  Cellular Genetics Informatics
  EOF
  '''
}

process get_data {

  input:
  val(sample) 

  output:
  env(NAME), emit: name 
  path('*'), emit: data

  shell:
  '''
  NAME=`echo !{sample} | cut -f 1 -d " "`
  data_path=`echo !{sample} | cut -f 2 -d " "`
 
  if [[ "!{params.input_matrix}" == "no" ]]; then
    if [[ "!{params.h5_on_irods}" == "no" ]]; then
      cp "${data_path}" "${NAME}.h5"
    elif [[ "!{params.h5_on_irods}" == "yes" ]]; then
      iget -f -v -K "${data_path}" "${NAME}.h5"
    else
      echo "incorrect h5 option"
      exit 1
    fi
  elif [[ "!{params.input_matrix}" == "yes" ]]; then
    cp -r "${data_path}" "${NAME}_matrix_input"
  fi
  '''
}

process run_cellbender {
  
  publishDir "/lustre/scratch126/cellgen/cellgeni/tickets/nextflow-tower-results/${params.sangerID}/${params.timestamp}/cellbender-results", mode: 'copy'

  input:
  val(NAME)
  path(data)

  output:
  path(NAME), emit: outdir
  
  shell:
  '''
  mkdir -p !{NAME} 
  if [[ "!{params.input_matrix}" == "no" ]]; then
    cellbender remove-background \
      --input !{data} \
      --output "!{NAME}/cellbender_out.h5" \
      --cuda \
      --expected-cells !{params.cells} \
      --epochs !{params.epochs} \
      --total-droplets-included !{params.droplets} \
      --fpr !{params.fpr} \
      --learning-rate !{params.learn}
  elif [[ "!{params.input_matrix}" == "yes" ]]; then
    NEXP=`zcat "!{data}/!{params.gene_tag}/filtered/barcodes.tsv.gz" | wc -l`
    TOTAL=""
    if (($NEXP > 20000)); then
      NTOT=$((NEXP+10000))
      echo "Modifying presets: expecting more than 20k cells (${NEXP}), total number of droplets is ${NTOT}.."
      TOTAL="--total-droplets-included ${NTOT}"
    else
      echo "Standard presets: expected number of cells is ${NEXP}.."
    fi
    cellbender remove-background \
      --input "!{data}/!{params.gene_tag}/raw" \
      --output "!{NAME}/cellbender_out.h5" \
      --cuda \
      --expected-cells ${NEXP} \
      --epochs !{params.epochs} \
      ${TOTAL} \
      --fpr !{params.fpr} \
      --learning-rate !{params.learn}
  fi
  '''
}

process cellbender_qc {
  
  publishDir "/lustre/scratch126/cellgen/cellgeni/tickets/nextflow-tower-results/${params.sangerID}/${params.timestamp}/cellbender-results", mode: 'copy'

  input:
  val(output_list) //this isn't used, just ensures QC is run after cellbender is finished for all samples

  output:
  path("qc_output")

  shell:
  '''
  mkdir "qc_output"
  Rscript !{baseDir}/bin/cellbender_qc.R \
    "/lustre/scratch126/cellgen/cellgeni/tickets/nextflow-tower-results/!{params.sangerID}/!{params.timestamp}/cellbender-results" \
    -m !{params.qc_mode} \
    -o "qc_output"
  '''
}

workflow {
  if (params.HELP) {
    helpMessage()
    exit 0
  }
  else {
    //Puts samplefile into a channel unless it is null, if it is null then it displays error message and exits with status 1.
    ch_sample_list = params.SAMPLEFILE != null ? Channel.fromPath(params.SAMPLEFILE) : errorMessage()
    if (params.sangerID == null) {
      errorMessage()
    }
    else {
      //email_startup()
      ch_sample_list | flatMap{ it.readLines() } | get_data
      run_cellbender(get_data.out.name, get_data.out.data) | collect | cellbender_qc
      //| collect \
      //| email_finish
    }
  }
}
