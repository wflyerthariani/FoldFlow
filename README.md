# FoldFlow
## Purpose
This repo contains the design for a basic RFdiffusion -> ProteinMPNN -> AlphaFold pipeline in Nextflow.
## Pipeline Design
![Alt text](./FoldFlow0_0%20_%20Mermaid%20Chart-2025-07-14-090750.png)
## Setup
Once cloned, you will need to make some adjustments to the config files, specifically in `nextflow.config`
```
params.rfdiff_editables_dir = '/ibex/user/thariaaa/RFdiffContainer'
params.rfdiff_sif_path = '/ibex/user/thariaaa/RFdiffContainer/RFdiffusion.sif'
...
params.mpnn_editables_dir = '/ibex/user/thariaaa/MPNNContainer'
params.mpnn_sif_path = '/ibex/user/thariaaa/MPNNContainer/ProteinMPNN.sif'
...
params.alphafold_sif_path = '/ibex/user/thariaaa/AlphaFoldContainer/AlphaFold.sif'
params.alphafold_data_dir = '/ibex/reference/KSL/alphafold/2.3.1/'
```
Each `editables_dir`, `sif_path` and `data_dir` needs to be set according to how you have set up the singularity images as per the setup instructions in:
- [RFdiffusion container](https://github.com/wflyerthariani/RFdiffusionContainer.git)
- [MPNN container](https://github.com/wflyerthariani/MPNNContainer.git)
- [AlphaFold container](https://github.com/wflyerthariani/AlphaFoldContainer.git)

The number of outputs for each stage of the pipeline can also be edited in `nextflow.config` alongside any naming conventions and the SLURM setup

To change the configuration of any specific model you will need to edit this information in `module_configs`
