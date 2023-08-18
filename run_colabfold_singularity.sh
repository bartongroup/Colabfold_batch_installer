#!/bin/env bash

#$ -adds l_hard gpu 1
#$ -adds l_hard cuda.0.name 'NVIDIA A40'
#$ -mods l_hard h_vmem 350G
#$ -mods l_hard mem_free 350G
#$ -pe smp 32
#$ -j y
#$ -N colabfold
#$ -o colabfold_logs/$JOB_NAME.o$JOB_ID
#$ -cwd

set -e

# if modifying threads, also update '-pe smp' request above to match...
THREADS=32
INSTALL_DIR="/cluster/sw/colabfold/current"
DB_PATH="/opt/colabfold/current"

export TF_CPP_MIN_LOG_LEVEL=2
export TINI_SUBREAPER=1

SCRIPT_PATH=$(dirname ${BASH_SOURCE[0]})
IMAGE=$(ls ${INSTALL_DIR}/*sif)

# based on the image being named 'colabfold_batch.?.?.?.sif'...
VERSION=$(echo $IMAGE|sed -r 's/.*colabfold_batch.([0-9\.]+).sif/\1/')

usage() {
	echo "Usage: $0 -i /path/to/fasta/file [-c 'colabfold arguments'] [-m 'mmseq arguments'] [-h] [-u] [-s]"
	echo
	echo "-i: path to input fasta or a3m file"
	echo "-m: Arguments to pass to mmseqs search phase (must be surrounded with quotes)"
	echo "-c: Arguments to pass to colabfold phase (must be surrounded with quotes)"
	echo "-h: Show Help"
	echo "-s: Show MMseqs search options"
	echo "-u: Show colabfold usage options"
	echo
	exit 1
}

colabfold_usage() {
	singularity run ${IMAGE} colabfold_batch -h
	exit 1
}

mmseqs_search_usage() {
	singularity run ${IMAGE} colabfold_search -h
	exit 1
}

while getopts "i:c:m:ush" opt; do
	case $opt in
		i)
			INPUT=$OPTARG
			;;
		c)
			COLABFOLD_ARGS=$OPTARG
			;;
		m)
			MMSEQS_ARGS=$OPTARG
			;;
		u)
			colabfold_usage
			;;
		s)
			mmseqs_search_usage
			;;
		h)
			usage
			;;
		*)
			;;
	esac
done

if [[ -z "$INPUT" ]]; then
	usage
fi

if [[ ! -e "$INPUT" ]]; then
	echo "Specified input file (${INPUT} not found..."
	exit 1
fi

if [[ -z "${JOB_ID}" || "${REQUEST}" == "QRLOGIN" ]]; then
	echo "This script must be submitted as a batch job to the scheduler"
	echo "i.e. qsub $0 $@"

	exit 1
fi

read -a COLABFOLD_ARGS_LIST <<< "$COLABFOLD_ARGS"
read -a MMSEQS_ARGS_LIST <<< "$MMSEQS_ARGS"

for arg in "${COLABFOLD_ARGS_LIST[@]}"; do
	if [[ "$arg" == "--use-gpu-relax" ]]; then
		echo
		echo "WARNING: Running amber relaxation on GPUs is unreliable and may fail."
		echo "Should this occur, rerun without --use-gpu-relax"
		echo
	fi
done

INPUT_DIR=$(dirname $INPUT)
INPUT_FILE=$(basename $INPUT)
SUFFIX="${INPUT_FILE##*.}"

echo "Hostname: $HOSTNAME"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo "INPUT_DIR=${INPUT_DIR}"
echo "INPUT_FILE=${INPUT_FILE}"
echo "DB_PATH=${DB_PATH}"
echo "VERSION=${VERSION}"
echo "MMSEQS_ARGS=${MMSEQS_ARGS[@]}"
echo "COLABFOLD_ARGS=${COLABFOLD_ARGS[@]}"

mkdir -p colabfold_output

if [[ "$SUFFIX" != 'a3m' ]]; then
	SEQ_COUNT=$(grep -c '>' ${INPUT})
	if [[ ${SEQ_COUNT} != "1" ]]; then
		echo "Input file must be a fasta file containing 1 sequence, or an a3m formatted alignment"
		exit 1
	fi

	# Extract final '|' separated field from seq id in case of uniprot format headers
	SEQ_ID=$(grep '>' ${INPUT}|sed 's/>//'|awk '{print $1}')
	SEQ_ID="${SEQ_ID##*|}"

	singularity exec -B ${INPUT_DIR}:/mnt/input -B colabfold_output:/mnt/output -B $DB_PATH/:/mnt/db \
		${IMAGE} colabfold_search --threads ${THREADS} ${MMSEQS_ARGS_LIST[@]} \
		/mnt/input/${INPUT_FILE} /mnt/db /mnt/output/

	mv colabfold_output/0.a3m colabfold_output/${SEQ_ID}.a3m
	COLABFOLD_INPUT="/mnt/output/${SEQ_ID}.a3m"
else
	COLABFOLD_INPUT="/mnt/input/${INPUT_FILE}"
fi
echo "COLABFOLD_INPUT=$COLABFOLD_INPUT"

singularity exec --nv -B ${INPUT_DIR}:/mnt/input -B colabfold_output:/mnt/output  ${IMAGE} \
	colabfold_batch ${COLABFOLD_ARGS_LIST[@]} ${COLABFOLD_INPUT} /mnt/output
