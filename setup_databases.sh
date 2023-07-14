#!/bin/bash -e

# Modified verrsion of colabfold database setup script for UoD cluster

# This is intended to be qsubbed to an A40 node so the mmseqs2 indexes
# are built on the same nodes as used for execution, then distributed 
# to the remaining nodes

#$ -j y
#$ -o colabfold_db_logs/$JOB_NAME.$JOB_ID
#$ -jc long
#$ -adds l_hard gpu 1
#$ -adds l_hard cuda.0.name 'NVIDIA A40'

VERSION="1.5.2"

# Current A40 nodes are gpu-34-gpu52
NODES=$(seq 34 52)

if [[ "$USER" != "dbadmin" ]]; then
	echo "Please submit this script as the dbadmin user"
	exit 1
fi

source ~/miniconda3/etc/profile.d/conda.sh
conda activate mmseqs2

echo "CONDA_PREFIX=$CONDA_PREFIX"
echo "HOSTNAME=$HOSTNAME"

ARIA_NUM_CONN=8

db_dir="/opt/colabfold/${VERSION}"
discoba_dir="/opt/colabfold/discoba"

######################################################################
#
# downloadFile
#
# Downloads specified file to cwd
#
# Required params:
#   URL: URL to download
#   OUTPUT: Output filename
#
# Returns: None
#
######################################################################

downloadFile() {
    URL="$1"
    OUTPUT="$2"
    set +e
    FILENAME=$(basename "${OUTPUT}")
    DIR=$(dirname "${OUTPUT}")
    aria2c --max-connection-per-server="$ARIA_NUM_CONN" --allow-overwrite=true -o "$FILENAME" -d "$DIR" "$URL" && set -e && return 0
    
    set -e
    fail "Could not download $URL to $OUTPUT"
}

######################################################################
#
# download_colabfold_dbs
#
# Carries out parallel download of required databases
#
# Required args: None
# Returns: None
#
######################################################################

download_colabfold_db() {

  mkdir -p $db_dir
  cd $db_dir

  {
    if [ ! -f UNIREF30_READY ]; then
      downloadFile "https://wwwuser.gwdg.de/~compbiol/colabfold/uniref30_2202.tar.gz" "uniref30_2202.tar.gz"
      tar xzvf "uniref30_2202.tar.gz"
      mmseqs tsv2exprofiledb "uniref30_2202" "uniref30_2202_db"
      mmseqs createindex "uniref30_2202_db" tmp1 --remove-tmp-files 1
      if [ -e uniref30_2202_db_mapping ]; then
        ln -sf uniref30_2202_db_mapping uniref30_2202_db.idx_mapping
      fi
      if [ -e uniref30_2202_db_taxonomy ]; then
        ln -sf uniref30_2202_db_taxonomy uniref30_2202_db.idx_taxonomy
      fi
      rm -r tmp1
      rm -f uniref30_2202.tar.gz
      touch UNIREF30_READY
    fi
  }&

  {
    if [ ! -f COLABDB_READY ]; then
      downloadFile "https://wwwuser.gwdg.de/~compbiol/colabfold/colabfold_envdb_202108.tar.gz" "colabfold_envdb_202108.tar.gz"
      tar xzvf "colabfold_envdb_202108.tar.gz"
      mmseqs tsv2exprofiledb "colabfold_envdb_202108" "colabfold_envdb_202108_db"
      mmseqs createindex "colabfold_envdb_202108_db" tmp2 --remove-tmp-files 1
      rm -r tmp2
      rm -f colabfold_envdb_202108.tar.gz
      touch COLABDB_READY
    fi
  }&

  {
    if [ ! -f PDB_READY ]; then
      downloadFile "https://wwwuser.gwdg.de/~compbiol/colabfold/pdb70_220313.fasta.gz" "pdb70_220313.fasta.gz"
      mmseqs createdb pdb70_220313.fasta.gz pdb70_220313
      mmseqs createindex pdb70_220313 tmp3 --remove-tmp-files 1
      rm -r tmp3
      rm -f pdb70_220313.fasta.gz
      touch PDB_READY
    fi
  }&

  {
    if [ ! -f PDB70_READY ]; then
      downloadFile "https://wwwuser.gwdg.de/~compbiol/data/hhsuite/databases/hhsuite_dbs/pdb70_from_mmcif_220313.tar.gz" "pdb70_from_mmcif_220313.tar.gz"
      tar xzvf pdb70_from_mmcif_220313.tar.gz pdb70_a3m.ffdata pdb70_a3m.ffindex
      rm -f pdb70_from_mmcif_220313.tar.gz
      touch PDB70_READY
    fi
  }&

  {
    if [ ! -f PDB_MMCIF_READY ]; then
      mkdir -p pdb/divided
      mkdir -p pdb/obsolete
      rsync -av --delete /cluster/gjb_lab/db/NOBACK/mirrors/pdb/data/structures/divided/mmCIF pdb/divided
      rsync -av --delete /cluster/gjb_lab/db/NOBACK/mirrors/pdb/data/structures/obsolete/mmCIF pdb/obsolete
      touch PDB_MMCIF_READY
    fi
  }&

  wait
}

######################################################################
#
# download_discoba_db
#
# Downloads Discoba-specific database (https://doi.org/10.5281/zenodo.5563073)
# from Wheeler (https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0259871)
# 
# Required argumnents: None
#
# Returns: None
#
######################################################################

download_discoba_db() {

  mkdir -p $discoba_dir
  cd $discoba_dir

  if [ ! -f DISCOBA_READY ]; then
    downloadFile "https://zenodo.org/record/5682928/files/discoba.fasta.gz?download=1" "discoba.fasta.gz"
    mmseqs createdb discoba.fasta.gz discoba
    mmseqs createindex discoba tmp4 --remove-tmp-files 1
    rm -r tmp4
    rm -f discoba.fasta.gz
    touch DISCOBA_READY
  fi
}

######################################################################
#
# create_wrapper
#
# Generates a shell script for qsubbing each rsync job. 
# Requirement to activate conda environment makes this 
# to complex for qsub -b...
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

  source_node=$1
  target_node=$2
  hold=$3

  extra_args=""
  if [[ ! -z "$hold" ]]; then
    extra_args="## -hold_jid $hold"
  fi

  script="${TMPDIR}/sync_$target_node.sh"

# SGE directives have ## rather than #$ to we can qsub this script, then
# sed them afterwards...

cat<<EOF > $script
#!/bin/env bash

## -mods l_hard hostname ${target_node}
## -N colabfold_mirror
## -j y
## -o $HOME/colabfold_db_logs/\$JOB_NAME.\$JOB_ID
$extra_args

source ~/miniconda3/etc/profile.d/conda.sh
conda activate mmseqs2
rsync -e 'ssh -oStrictHostKeyChecking=no' --rsync-path=$CONDA_PREFIX/bin/rsync --delete -av $source_node:/opt/colabfold/ /opt/colabfold
EOF

  sed -i 's/##/#$/' $script
  echo $script
}

######################################################################
#
# distribute_db
#
# Shares database across appropriate GPU nodes via qsubbed rsync jobs
# The database is pulled onto two nodes for each source node, so
# the initial transfer is submitted to run immediately, but subsequent
# dependent jobs which require a previous transfer to complete are 
# submitted with '-hold_jid' so they will not run until the database has 
# mirrored to their source node
# 
# Required args: None
# Returns: None
#
######################################################################

distribute_db() {

  # We need to exlude the current host since we already have the database
  # and are going to use this as a starting point...
  source_node=$(hostname -s)
  cur_node=$(echo $source_node|sed -r 's/gpu-([0-9]+)/\1/')
  nodes=( "${NODES[@]/$cur_node}" )

  # Now we need to reorder the node list so that any nodes which are down
  # appear last on the list, then the jobs assigned to them will hold until
  # the nodes return, rather than having live nodes waiting on a job to complete
  # on a node which is down

  declare -a bad_nodes

  for node in ${nodes[@]}; do
    nodename=$(printf "gpu-%s.compute.dundee.ac.uk" "$node")
    # qhost will return '-' in NLOAD field if a node is offline or uncommunicative...
    status=$( qhost -h $nodename |tail -n +4|awk '{print $7}')
    if [[ "$status" == '-' ]]; then
      echo "Warning: $nodename is down..."
      bad_nodes+=($node)
    fi
  done

  # remove 'bad nodes' from the list and append them again
  # at the end to ensure they are not dependancies for other jobs
  for bad_node in ${bad_nodes[@]}; do
    nodes=( "${nodes[@]/$bad_node}" )
    nodes+=($bad_node)
  done

  declare -a submitted_nodes # list of nodes for which jobs have been prepared
  declare -A node_jobs # associative array mapping node name to job id, for determining jid to hold

  # 'submission' tracks the number of jobs submitted from each node
  submission=-1
  # sub_level tracks index of submitted nodes to identify correct source node 
  sub_level=1 

  for node in ${nodes[@]};do
    submission=$((submission+1))

    target_node=$(printf "gpu-%s.compute.dundee.ac.uk" "$node")
    submitted_nodes+=($target_node)

    # change the source node when we have prepared jobs for two nodes...
    if [[ "$submission" == 2 ]]; then
      submission=0
      source_node=${submitted_nodes[0]}
      submitted_nodes=$(echo ${submitted_nodes[$sub_level]:-1})
      sub_level=$(($sub_level+1))
    fi

    echo "$source_node -> $target_node"

    hold=${node_jobs[$source_node]}
    script=$(create_wrapper $source_node $target_node $hold)

    return=$(qsub $script)
    job_id=$(echo $return|cut -f3 -d' ')
    echo "job_id=$job_id"
    node_jobs[$target_node]=$job_id

  done
}


download_colabfold_db
download_discoba_db
distribute_db