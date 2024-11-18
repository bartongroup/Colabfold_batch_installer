#!/bin/env bash


# Need to select an A40 GPU node even for the non-gpu search 
# phase since currently only these have the RAM and local 
# copy of the database

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

######################################################################
#
# create_wrapper
#
# Generates a shell script for qsubbing each alphafold job once search
# phase is completed.
#
# Required parameters:
#  source_node: hostname to sync from
#  target_node: hostname to sync to
#  hold: jid to submit hold_jid for
#
# Returns:
#  path to wrapper script
#
######################################################################

create_wrapper() {

	COUNT=$1
	COLABFOLD_INPUT=$2
	COLABFOLD_ARGS_LIST=$3

	script="${TMPDIR}/colabfold_${COUNT}.sh"

	# SGE directives have ## rather than #$ to we can qsub the current script without these 
	# being interpreted, then correct them with sed before submitting the wrapper...

cat<<EOF > $script
#!/bin/env bash

## -adds l_hard gpu 1
## -adds l_hard cuda.0.name 'NVIDIA A40'
## -N colabfold
## -j y
## -o colabfold_logs/\$JOB_NAME.o\$JOB_ID
## -cwd

echo "Hostname: $HOSTNAME"
echo "GPU: $CUDA_VISIBLE_DEVICES"
echo "INPUT_FILE=${COLABFOLD_INPUT}"
echo "COLABFOLD_ARGS=${COLABFOLD_ARGS[@]}"

COMPARISON=$(echo ${COLABFOLD_INPUT}|sed 's/.a3m//')

mkdir -p colabfold_predictions/${COMPARISON}
cp -v colabfold_output/${COLABFOLD_INPUT} $TMPDIR

singularity exec --nv -B $TMPDIR:/mnt/output ${IMAGE} \
	colabfold_batch ${COLABFOLD_ARGS_LIST[@]} $TMPDIR/${COLABFOLD_INPUT} $TMPDIR

cp -v $TMPDIR/* colabfold_predictions/${COMPARISON}

EOF

	sed -i 's/##/#$/' $script
	echo $script
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
echo "SUFFIX=${SUFFIX}"
echo "DB_PATH=${DB_PATH}"
echo "VERSION=${VERSION}"
echo "MMSEQS_ARGS=${MMSEQS_ARGS[@]}"
echo "COLABFOLD_ARGS=${COLABFOLD_ARGS[@]}"

mkdir -p colabfold_output

if [[ "$SUFFIX" != 'fa' ]] && [[ "$SUFFIX" != 'fasta' ]]; then
	echo "ERROR: Input file for batch queries should be a fasta file, with a '.fa' or '.fasta' suffix"
	exit 1
else
	SEQ_COUNT=$(grep -c '>' ${INPUT})
	if [[ ${SEQ_COUNT} -gt 25 ]]; then
		echo "Input file must be a fasta file containing up to 25 sequences."
		echo "The provided file contains ${SEQ_COUNT} sequences"
		exit 1
	fi

	# Extract final '|' separated field from seq id in case of uniprot format headers
	SEQ_IDS=$(grep '>' ${INPUT}|sed 's/>//'|awk '{print $1}')

	# Create a mapping of sequence index to ID
	i=0
	declare -A ID_MAP
	for SEQ_ID in ${SEQ_IDS[@]}; do
		SEQ_ID="${SEQ_ID##*|}"
		ID_MAP[${i}]=${SEQ_ID}
		i=$(( i + 1 ))
	done

	echo "SEQUENCE_IDS:"
	for key in "${!ID_MAP[@]}"; do 
		echo "$key => ${ID_MAP[$key]}" 
	done
	echo

	singularity exec -B ${INPUT_DIR}:/mnt/input -B colabfold_output:/mnt/output -B $DB_PATH/:/mnt/db \
		${IMAGE} colabfold_search --threads ${THREADS} ${MMSEQS_ARGS_LIST[@]} \
			/mnt/input/${INPUT_FILE} /mnt/db /mnt/output/

	# a3m files are created with a 0-indexed count, which isn't particulary helpful, 
	# so rename each of these to the SEQ_ID.a3m, which is then used by the alphafold
	# output filenaming

	readarray -t A3M_LIST < <(ls colabfold_output/*a3m)
	for A3M in ${A3M_LIST[@]}; do
		index=$(basename ${A3M}|sed 's/.a3m//')
		echo "index=${index}"
		mv -v $A3M colabfold_output/${ID_MAP[${index}]}.a3m
		script=$(create_wrapper $index "${ID_MAP[${index}]}.a3m" ${COLABFOLD_ARGS_LIST[@]})
		qsub $script
	done
fi

