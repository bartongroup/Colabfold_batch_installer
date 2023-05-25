#!/bin/env bash

#$ -adds l_hard gpu 1
#$ -adds l_hard cuda.0.name 'NVIDIA A40'
#$ -j y
#$ -N colabfold
#$ -o colabfold_logs/$JOB_NAME.o$JOB_ID
#$ -cwd

set -e

image='/cluster/gjb_lab/jabbott/singularity/colabfold_batch.1.5.2.sif'

usage() {
	echo "$0 -i /path/to/fasta/file [-c 'colabfold arguments']"
	exit 1
}

while getopts "i:c:h" opt; do
	case $opt in
		i)
			input=$OPTARG
			;;
		c)
			colabfold_args=$OPTARG
			;;
		h)
			usage
			;;
		*)
			;;
	esac
done

read -a colabfold_args_list <<< "$colabfold_args"

for arg in "${colabfold_args_list[@]}"; do
	if [[ "$arg" == "--use-gpu-relax" ]]; then
	 	echo
		echo "WARNING: Running amber relaxation on GPUs is unreliable and may fail."
		echo "Should this occur, rerun without --use-gpu-relax"
		echo
	fi
done

if [[ -z "$input" ]]; then
	usage
fi

if [[ ! -e "$input" ]]; then
	echo "Specified input file (${input} not found..."
	exit 1
fi

# We need to bind the path to the directory containing the input fasta file into the container
# and also provide the filename...
input_dir=$(dirname $input)
fasta_file=$(basename $input)

echo "Hostname: $HOSTNAME"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo "Command line: colabfold_batch ${colabfold_args_list[@]} ${input} colabfold_outputs"

export TF_CPP_MIN_LOG_LEVEL=2
singularity exec --nv -B ${input_dir}:/mnt ${image} \
	colabfold_batch ${colabfold_args_list[@]} /mnt/${fasta_file} /mnt/colabfold_output
