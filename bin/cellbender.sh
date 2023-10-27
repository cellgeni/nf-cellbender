#!/bin/bash

set -euo pipefail

##Mandatory inputs
sample_id=$1 #sample id (just for naming output folder)
data=$2 #raw h5 or raw 10x matrix folder

##Optional inputs
cells=${3:-""} 
droplets=${4:-""}
epochs=${5:-""}
fpr=${6:-""}
learning_rate=${7:-""}

##If optional arg is set then add the flag to the string to be interpreted by cellbender

ARGS_STRING=""

if [ ! -z "${cells}" ]; then
  ARGS_STRING+="--expected-cells ${cells}"
fi

if [ ! -z "${droplets}" ]; then
  ARGS_STRING+=" --total-droplets-included ${droplets}"
fi

if [ ! -z "${epochs}" ]; then
  ARGS_STRING+=" --epochs ${epochs}"
fi

if [ ! -z "${fpr}" ]; then
  ARGS_STRING+=" --fpr ${fpr}"
fi

if [ ! -z "${learning_rate}" ]; then
  ARGS_STRING+=" --learning-rate ${learning_rate}"
fi

#To ensure cellbender doesn't interpret blank spaces when no optional inputs have to add space to above variables, making command below ugly

echo "cellbender remove-background --input ${data} --output ${sample_id}/cellbender_out.h5 --cuda ${ARGS_STRING}" > "${sample_id}/cmd.txt"

cellbender remove-background --input "${data}" --output "${sample_id}/cellbender_out.h5" --cuda ${ARGS_STRING}
