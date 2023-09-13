#!/usr/bin/env nextflow

nextflow.enable.dsl=2

def helpMessage() {
    log.info"""
    ===================
    cellbender pipeline
    ===================
    This pipeline runs Cellbender.
    The only parameter you need to input is:
      --SAMPLEFILE /full/path/to/sample/file
    This file should contain a single sampleID per line. 
    An example can be seen here: https://github.com/cellgeni/nf-cellbender/blob/main/examples/example.txt  
    """.stripIndent()
}

def errorMessage() {
    log.info"""
    ================
    cellbender error
    ================
    You failed to provide the SAMPLEFILE input parameter
    Please provide these parameters as follows:
      --SAMPLEFILE /full/path/to/sample/file
    The pipeline has exited with error status 1.
    """.stripIndent()
    exit 1
}

process get_data {

  input:
  tuple val(id), val(data_path)


  output:
  val(id), emit: id 
  path('*'), emit: data

  shell:
  '''
  if [[ "!{params.input_matrix}" == "no" ]]; then
    if [[ "!{params.h5_on_irods}" == "no" ]]; then
      cp -r "!{data_path}" "!{id}.h5"
    elif [[ "!{params.h5_on_irods}" == "yes" ]]; then
      iget -f -v -K "!{data_path}" "!{id}.h5"
    else
      echo "incorrect h5 option"
      exit 1
    fi
  elif [[ "!{params.input_matrix}" == "yes" ]]; then
    cp -r "!{data_path}" "!{id}_matrix_input"
  fi
  '''
}

process run_cellbender {
  
  publishDir "${params.outdir}", mode: 'copy'

  input:
  val(NAME)
  path(data)

  output:
  path(NAME), emit: outdir
  
  shell:
  '''
  mkdir -p !{NAME} 
  if [[ "!{params.input_matrix}" == "no" ]]; then
    echo "cellbender remove-background --input !{data} --output !{NAME}/cellbender_out.h5 --cuda --expected-cells !{params.cells} --epochs !{params.epochs} --total-droplets-included !{params.droplets} --fpr !{params.fpr} --learning-rate !{params.learn}" > "!{NAME}/cmd.txt"
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
    echo "cellbender remove-background --input !{data}/!{params.gene_tag}/raw --output !{NAME}/cellbender_out.h5 --cuda --expected-cells ${NEXP} --epochs !{params.epochs} ${TOTAL} --fpr !{params.fpr} --learning-rate !{params.learn}" > "!{NAME}/cmd.txt"
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
  
  publishDir "${params.outdir}", mode: 'copy'

  input:
  val(output_list) //this isn't used, just ensures QC is run after cellbender is finished for all samples

  output:
  path("qc_output")

  shell:
  '''
  mkdir "qc_output"
  Rscript !{projectDir}/bin/cellbender_qc.R \
    "!{launchDir}/!{params.outdir}" \
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
    ch_sample_list | flatMap{ it.readLines() } | map { it -> [ it.split()[0], it.split()[1] ] } | get_data
    run_cellbender(get_data.out.id, get_data.out.data) | collect | cellbender_qc 
  }
}
