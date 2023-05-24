#!/bin/bash

# Builds a docker image with versioning extracted from yaml file

version=$(grep "ColabFold.git" colabfold_batch.yaml|cut -d@ -f3|sed 's/^v//')
echo "Building version ${version}..."

docker buildx build --platform linux/amd64 -t colabfold_batch:${version} --load .
docker save colabfold_batch:${version} > colabfold_batch.${version}.tar
