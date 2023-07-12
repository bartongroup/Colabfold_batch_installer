#!/bin/env bash

#$ -adds l_hard gpu 1
#$ -adds l_hard cuda.0.name 'NVIDIA A40'
#$ -j y
#$ -N colabfold
#$ -o colabfold_logs/$JOB_NAME.o$JOB_ID
#$ -cwd

set -e

script_path=$(dirname ${BASH_SOURCE[0]})
image=$(ls ${script_path}/*sif)

usage() {
	echo "Usage: $0 -i /path/to/fasta/file [-c 'colabfold arguments'] [-h] [-u]"
	echo
	echo "Note that colabfold arguments passed via '-c' must be surrounded with quotes to ensure they are all passed to colabfold"
	echo
	echo "run $0 -u for colabfold_batch help"
	echo
	exit 1
}

colabfold_usage() {
	export TINI_SUBREAPER=1
	singularity run ${image} colabfold_batch -h
	exit 1
}

while getopts "i:c:uh" opt; do
	case $opt in
		i)
			input=$OPTARG
			;;
		c)
			colabfold_args=$OPTARG
			;;
		u)
			colabfold_usage
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
# This is a bit of a lie, but is the effective command run taking bind mounts into account...
echo "Command line: colabfold_batch ${colabfold_args_list[@]} ${input} ${input_dir}/colabfold_outputs"

export TF_CPP_MIN_LOG_LEVEL=2
export TINI_SUBREAPER=1
singularity exec --nv -B ${input_dir}:/mnt ${image} \
	colabfold_batch ${colabfold_args_list[@]} /mnt/${fasta_file} /mnt/colabfold_output