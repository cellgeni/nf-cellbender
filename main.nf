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
  if "!{params.on_irods}"; then
    iget -f -v -K -r "!{data_path}" "input_data"
  else
    cp -r "!{data_path}" "input_data"
  fi
  if "!{params.is_h5}"; then
    mv input_data input_data.h5
  fi
  '''
}

process run_cellbender {
  
  publishDir "${params.outdir}", mode: 'copy'

  input:
  val(id)
  path(data)

  output:
  path(id)
  
  shell:
  '''
  mkdir -p !{id} 
  !{projectDir}/bin/cellbender.sh !{id} !{data} !{params.cells} !{params.droplets} !{params.epochs} !{params.fpr} !{params.learn}
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
