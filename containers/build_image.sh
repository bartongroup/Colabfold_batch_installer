#!/bin/bash

# Builds a docker image with versioning extracted from yaml file
# This uses 'buildx' for a cross-platform build allowing it be be built on MacOS 
# where we have Docker available, then the image can be transferred to the cluster
# and singuliarity used to create a .sif image. 

# Doing a direct singularity build requires sudo access, or can be run on MacOS 
# in a VM....

version=$(grep "ColabFold.git" ../colabfold_batch.yaml|cut -d@ -f3|sed 's/^v//')
echo "Building version ${version}..."

docker buildx build --platform linux/amd64 -t colabfold_batch:${version} --load .
docker save colabfold_batch:${version} > colabfold_batch.${version}.tar
