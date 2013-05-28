#!/bin/bash
ssh izquiefo@stampede.tacc.utexas.edu "cd /scratch/01844/izquiefo/remote/wooster/experiments/pipeline_1368806488/output/batch_0/ml_trees && sbatch raxmllight_pipeline_1368806488_000_000.slurm"
ssh izquiefo@stampede.tacc.utexas.edu "cd /scratch/01844/izquiefo/remote/wooster/experiments/pipeline_1368806488/output/batch_0/ml_trees && sbatch raxmllight_pipeline_1368806488_000_001.slurm"
ssh izquiefo@stampede.tacc.utexas.edu "cd /scratch/01844/izquiefo/remote/wooster/experiments/pipeline_1368806488/output/batch_0/ml_trees && sbatch raxmllight_pipeline_1368806488_000_002.slurm"
