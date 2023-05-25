# Colabfold_batch Installer

This repository contains a simplified method of installing [colabfold](https://github.com/sokrypton/ColabFold) for local UoD use, which is loosely based on [localcolabfold](https://github.com/YoshitakaMo/localcolabfold). Colabfold provides a greatly accelerated structure prediction compared to the 'traditional' alphafold approach by replacing the Hmmer/HHblits homology searches with a much faster MMSeqs2 based method - see [the colabfold paper](https://doi.org/10.1038/s41592-022-01488-1). The localcolabfold installation does not work out of the box in our environment, so this is a streamlined installation which should produce a functional installation by running a single setup script.

## Requirements

### Singularity container

* Nothing inparticular - The UoD HPC cluster provides Singularity access, including on CUDA-enabled GPU nodes appropriate for running colabfold. 

This is temporarily available in `/cluster/gjb_lab/jabbott/singularity` until a better home can be found for it...

### Full Installation
*  Anaconda/Miniconda3/Mamba installation. The installation script will preferentially use mamba to carry out the installation, but will fallback to conda if this is not available. If you don't already have a conda installation, see [The Cluster Wiki](https://teams.microsoft.com/l/channel/19%3A63a2d1d10e5346c79d8b35dec6006a40%40thread.tacv2/tab%3A%3A8ac3086d-c08d-426b-9140-4890bb613c19?groupId=4153042c-375d-4caa-a654-d691f65da8bb&tenantId=ae323139-093a-4d2a-81a6-5d334bcd9019&allowXTenantAccess=false) for instructions on setting this up.
*  Approximately 14 Gb free disk space. This is mostly required for storing the alphafold weights
*  git (optional)
*  About 15 minutes of your life

## Installation

### Singularity

All necessary components are already available on the cluster. 

### Full Installation

1. Obtain a copy of this repository either using git i.e.  
`git clone git://github.com/bartongroup/JCA_colabfold_batch.git`  
or by downloading a release tarball from the link on the right under 'Releases'. Copy this tarball onto the cluster filesystem and extract with  
`tar zxvf v1.5.2-beta2.tar.gz`

2. Change into the directory which is created by step 1 - this will have the repository name if cloned from git, or the version number if obtained from a Release tarball.
a)  From a repository clone:  
`cd Colabfold_batch_installer`  
b) From a release tarball:  
`cd Colabfold_batch_installer-1.5.2-beta2`

3. Run the setup script:  
`./setup.sh`  
This will create a new conda environment named `colabfold_batch` based upon the definition within the `colabfold_batch.yaml` file. Alphafold weights are then downloaded into the `$CONDA_PREFIX/share/colabfold` directory within the conda environment. The installation will take approximately 15 minutes to complete. 

## Usage

### Singularity

Usage: run_colabfold_singularity.sh -i /path/to/fasta/file [-c 'colabfold arguments']

The `run_colabfold_singularity.sh` script can be submitted directly to GridEngine, and requires at a minimun the path to an input fasta file. Any specific colabfold arguments can be provided using the `-c` argument. Log files will be written to a 'colabfold_logs' directory in the submission directory, while outputs will be written to a `colabfold_outputs` directory within the directory containing the submitted fasta file. 

i.e. `qsub /path/to/run_colabfold.sh -i test/cadh5_arath.fa -c "--num-recycle 5 --amber --num-relax 5"`  

### Full Installation

 Activate the `colabfold_batch` environment  
`conda activate colabfold_batch`

The `colabfold_batch` program will now be available on your path. Run `colabfold_batch -h` for help information.

An example script is provided as `run_colabfold.sh` which is appropriate for submission to the UoD HPC cluster.  

`Usage: ./run_colabfold.sh -i /path/to/fasta/file [-c "colabfold_arguments"]`  

The only required argument is the path to an input fasta file containing the sequences of interest. Any additional colabfold_batch arguments can be specified with the `-c` argument, making sure to surround the colabfold arguments in quotes so the are captured as a single argument i.e.  

`run_colabfold.sh -i test/cadh5_arath.fa -c "--num-recycle 5 --amber --num-relax 5"`  

This script can be submitted directly to GridEngine directly using `qsub`, and is configured to run on one of the Nvidia A40 GPUs:  

`qsub run_colabfold.sh -i test/cadh5_arath.fa -c "--num-recycle 5 --amber --num-relax 5"`  

Resulting job logs will be written into a subdirectory of the submission directory named `colabfold_logs`, while outputs will be written to a `colabfold_results` directory.  
*Make sure you check the log files for errors!*

**N.B. There are known issues with alphafold in relaxing models using Amber on GPUs - if this fails, omit the `--use-gpu-relax` argument and run amber only on CPUs - This part of the process on CPUs doesn't seem overly slow**

## Limitations

At present we do not have an in-house MMSeq2 server, so queries are directed to the default public server, which has limited capacity. Also bear in mind that use of a public resource would expose data externally which may not be appropriate.

## Expected Warnings
Some warnings are expected within the log files, and do not necessarily mean something has gone wrong.

*  `2023-05-24 16:54:44.003090: W tensorflow/compiler/tf2tensorrt/utils/py_utils.cc:38] TF-TRT Warning: Could not find TensorRT`  
This warning relates to an optional package which does not work with the combination of library versions required for our setup which is due to be resolved in a future software release. This does not affect the results, but may increase the required runtime.

* `2023-05-24 16:54:38,928 Unable to initialize backend 'rocm': NOT_FOUND: Could not find registered platform with name: "rocm". Available platform names are: Interpreter CUDA Host`  
`2023-05-24 16:54:38,929 Unable to initialize backend 'tpu': module 'jaxlib.xla_extension' has no attribute 'get_tpu_client'`  
`2023-05-24 16:54:38,929 Unable to initialize backend 'plugin': xla_extension has no attributes named get_plugin_device_client. Compile TensorFlow with //tensorflow/compiler/xla/python:enable_plugin_device set to true (defaults to false) to enable this.`  
These warnings relate to alternative computational backends which may be used to carry out the prediction. The line `Available platform names are: Interpreter CUDA Host` indicates that the CUDA backend required for GPU acceleration has been found
