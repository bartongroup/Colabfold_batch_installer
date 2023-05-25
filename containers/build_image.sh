#!/bin/bash

set -e

# Builds a docker image with versioning extracted from yaml file
# This uses 'buildx' for a cross-platform build allowing it be be built on MacOS 
# where we have Docker available, then the image can be transferred to the cluster
# and singuliarity used to create a .sif image. 

# Doing a direct singularity build requires sudo access, or can be run on MacOS 
# in a VM....

if [[ ! -e "colabfold_batch.yaml" ]]; then
	echo "Please run this script from the root of the repository" 
	echo "i.e. ./containers/$0"
	exit 1
fi

version=$(grep "ColabFold.git" colabfold_batch.yaml|cut -d@ -f3|sed 's/^v//')
echo "Building version ${version}..."

docker buildx build --platform linux/amd64 -f containers/Dockerfile -t colabfold_batch:${version} --load .
docker save colabfold_batch:${version} > containers/colabfold_batch.${version}.tar

echo
echo "The singularity container can now be built on a linux host using: "
echo "singularity build colabfold_batch.${version}.sif docker-archive://colabfold_batch.${version}.tar"
