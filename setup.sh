#!/bin/bash

set -e

# Based on the setup from https://github.com/YoshitakaMo/localcolabfold
# but modified to be more readily maintainable and to work with an existing
# conda/mamba installation. Some dependencies were also missing in the 
# localcolabfold setup, and the tensorflow setup incomplete, so it didn't 
# find our GPUs. Hopefully all that is sorted here

# pick a snake, any snake...
[[ "$(which conda 2>/dev/null)" ]] && CONDA='conda'
[[ "$(which mamba 2>/dev/null)" ]] && CONDA='mamba'

if [[ -z "${CONDA}" ]]; then
	echo "Please install Miniconda3 or mamba prior to running this script..."
	exit 1
else
	echo "Using existing ${CONDA} installation..."
	source $CONDA_PREFIX/etc/profile.d/conda.sh

	$CONDA env create -f colabfold_batch.yaml

	source $(dirname $CONDA_EXE)/activate colabfold_batch

	pip install --no-warn-conflicts "colabfold[alphafold-minus-jax] @ git+https://github.com/sokrypton/ColabFold" 

	echo 'CUDNN_PATH=$(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)"))' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
	echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CONDA_PREFIX/lib/:$CUDNN_PATH/lib' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh

	py_ver=$(python --version|cut -f2 -d' '|sed 's/\.[0-9]*$//')

	cd $CONDA_PREFIX/lib/python${py_ver}/site-packages/colabfold

	# Use matplotlib Agg backend...
	sed -i -e "s#from matplotlib import pyplot as plt#import matplotlib\nmatplotlib.use('Agg')\nimport matplotlib.pyplot as plt#g" plot.py
	# Store alphafold weightings in $CONDA_PREFIX/share/colabfold rather than default user directory
	sed -i -e "s#appdirs.user_cache_dir(__package__ or \"colabfold\")#\"${CONDA_PREFIX}/share/colabfold\"#g" download.py
	rm -rf __pycache__
	
	cd ${CONDA_PREFIX}/share
	mkdir -p colabfold
	python -m colabfold.download
fi
