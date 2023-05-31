#!/bin/env bash

#$ -adds l_hard gpu 1
#$ -adds l_hard cuda.0.name 'NVIDIA A40'
#$ -j y
#$ -N colabfold
#$ -o colabfold_logs/$JOB_NAME.o$JOB_ID
#$ -cwd

set -e

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
	colabfold_batch -h
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

echo "Hostname: $HOSTNAME"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo "Command line: colabfold_batch  ${colabfold_args_list[@]} ${input} ${input_dir}/colabfold_outputs"

input_dir=$(dirname $input)

TF_CPP_MIN_LOG_LEVEL=2
colabfold_batch ${colabfold_args_list[@]} ${input} ${input_dir}/colabfold_outputs

