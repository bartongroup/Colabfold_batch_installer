#!/bin/bash

set -e

# Inspired by https://github.com/YoshitakaMo/localcolabfold, with the 
# hopefully added bonus of producing a functioning installation on 
# our infrastructure...
#
# Hopefully provides tighter controls of installed versions and dependancies as well

# pick a snake, any snake...
[[ "$(which conda 2>/dev/null)" ]] && CONDA='conda'
[[ "$(which mamba 2>/dev/null)" ]] && CONDA='mamba'

inDockerBuild=`uname -a|(grep -c buildkit || true)`

if [[ -z "${CONDA}" ]]; then
	echo "Please install Miniconda3 or mamba prior to running this script..."
	exit 1
else
	source $CONDA_PREFIX/etc/profile.d/conda.sh

	# If installation is run on a non-gpu host, some cpu-centric packages will be installed instead
	# of cuda packages. This can be fixed with the 'CONDA_OVERRIDE_CUDA' variabe...
	CONDA_OVERRIDE_CUDA="11.4" $CONDA env create -f colabfold_batch.yaml

	source $(dirname $CONDA_EXE)/activate colabfold_batch

	echo 'CUDNN_PATH=$(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)"))' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
	echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CONDA_PREFIX/lib/:$CUDNN_PATH/lib' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh

	py_ver=$(python --version|cut -f2 -d' '|sed 's/\.[0-9]*$//')
	cd $CONDA_PREFIX/lib/python${py_ver}/site-packages/colabfold

	# Use matplotlib Agg backend for headless operation
	sed -i -e "s#from matplotlib import pyplot as plt#import matplotlib\nmatplotlib.use('Agg')\nimport matplotlib.pyplot as plt#g" plot.py
	# Store alphafold weightings in $CONDA_PREFIX/share/colabfold rather than default user directory
	sed -i -e "s#appdirs.user_cache_dir(__package__ or \"colabfold\")#\"${CONDA_PREFIX}/share/colabfold\"#g" download.py
	rm -rf __pycache__
	
	cd ${CONDA_PREFIX}/share
	mkdir -m 0777 -p colabfold
	python -m colabfold.download

	if [[ "$inDockerBuild" == '1' ]]; then
		mamba clean -a -y
		pip cache purge
	fi
fi
