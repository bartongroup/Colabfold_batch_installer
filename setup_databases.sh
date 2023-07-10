#!/bin/bash -ex

# Modified verrsion of colabfold database setup script for UoD cluster

# This is intended to be qsubbed to an A40 node so the mmseqs2 indexes
# are built on the same nodes as used for execution, then distributed 
# to the remaining nodes

#$ -cwd
#$ -j y
#$ -o download_logs/$JOB_NAME.$JOB_ID
#$ -jc long
#$ -adds l_hard gpu 1
#$ -adds l_hard cuda.0.name 'NVIDIA A40'

ARIA_NUM_CONN=8
WORKDIR="${1:-$(pwd)}"

cd "${WORKDIR}"

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
  rm uniref30_2022.tar.gz
  rm -r tmp1
  touch UNIREF30_READY
fi

if [ ! -f COLABDB_READY ]; then
  downloadFile "https://wwwuser.gwdg.de/~compbiol/colabfold/colabfold_envdb_202108.tar.gz" "colabfold_envdb_202108.tar.gz"
  tar xzvf "colabfold_envdb_202108.tar.gz"
  mmseqs tsv2exprofiledb "colabfold_envdb_202108" "colabfold_envdb_202108_db"
  mmseqs createindex "colabfold_envdb_202108_db" tmp2 --remove-tmp-files 1
  rm colabfold_envdb_202108.tar.gz
  rm -r tmp2
  touch COLABDB_READY
fi

if [ ! -f PDB_READY ]; then
  downloadFile "https://wwwuser.gwdg.de/~compbiol/colabfold/pdb70_220313.fasta.gz" "pdb70_220313.fasta.gz"
  mmseqs createdb pdb70_220313.fasta.gz pdb70_220313
  mmseqs createindex pdb70_220313 tmp3 --remove-tmp-files 1
  rm pdb70_220313.fasta.gz
  rm -r tmp3
  touch PDB_READY
fi

if [ ! -f PDB70_READY ]; then
  downloadFile "https://wwwuser.gwdg.de/~compbiol/data/hhsuite/databases/hhsuite_dbs/pdb70_from_mmcif_220313.tar.gz" "pdb70_from_mmcif_220313.tar.gz"
  tar xzvf pdb70_from_mmcif_220313.tar.gz pdb70_a3m.ffdata pdb70_a3m.ffindex
  rm pdb70_from_mmcif_220313.tar.gz
  touch PDB70_READY
fi
if [ ! -f PDB_MMCIF_READY ]; then
  mkdir -p pdb/divided
  mkdir -p pdb/obsolete
  rsync -av --delete /cluster/gjb_lab/db/NOBACK/mirrors/pdb/data/structures/divided/mmCIF pdb/divided
  rsync -av --delete /cluster/gjb_lab/db/NOBACK/mirrors/pdb/data/structures/obsolete/mmCIF pdb/obsolete
  touch PDB_MMCIF_READY
fi
