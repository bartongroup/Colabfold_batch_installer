#!/bin/env bash

#$ -adds l_hard gpu 1
#$ -adds l_hard cuda.0.name 'NVIDIA A40'
#$ -j y
#$ -N colabfold
#$ -o colabfold_logs/$JOB_NAME.o$JOB_ID
#$ -cwd



singularity exec --nv -B .:/mnt /cluster/gjb_lab/jabbott/singularity/colabfold_batch.1.5.2.sif \
	colabfold_batch /mnt/cadh5_arath.fa /mnt/colabfold_output
