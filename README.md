# FoldFlow - Protein Design Pipeline

A Nextflow DSL2 pipeline for de novo protein design using RFdiffusion, ProteinMPNN, and AlphaFold validation.

## Pipeline Overview

FoldFlow implements a three-stage protein design workflow:

1. **RFdiffusion**: Generates protein backbone structures using diffusion models
2. **ProteinMPNN**: Designs amino acid sequences for the generated backbones
3. **AlphaFold**: Validates designed sequences by structure prediction

## Quick Start

### Prerequisites

- Nextflow >= 24.04.0
- Singularity or Docker (for containerized execution)
- GPU support for deep learning models

### Installation

```bash
# Clone the repository
git clone https://github.com/user/FoldFlow.git
cd FoldFlow-refactored

# Test the pipeline
nextflow run main.nf -profile test,singularity
```

### Basic Usage

```bash
nextflow run main.nf \
  --num_designs 5 \
  --output_prefix "my_design" \
  --outdir results \
  -profile singularity
```

## Configuration

### Required Parameters

The pipeline requires paths to Singularity containers and data directories. These can be set in a custom config file or via command line:

```bash
# Example custom config (my_config.config)
params {
    // RFdiffusion settings
    rfdiff_sif_path = '/path/to/RFdiffusion.sif'
    rfdiff_editables_dir = '/path/to/RFdiffContainer'
    
    // ProteinMPNN settings
    mpnn_sif_path = '/path/to/ProteinMPNN.sif'
    mpnn_editables_dir = '/path/to/MPNNContainer'
    
    // AlphaFold settings
    alphafold_sif_path = '/path/to/AlphaFold.sif'
    alphafold_data_dir = '/path/to/alphafold/data'
}

# Run with custom config
nextflow run main.nf -c my_config.config -profile singularity
```

### Pipeline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `num_designs` | 3 | Number of protein designs to generate |
| `output_prefix` | 'design' | Prefix for output files |
| `outdir` | './results' | Output directory |
| `mpnn_num_sequences` | 2 | Number of sequences per backbone |

### Module-Specific Configurations

Place YAML configuration files in the `configs/` directory:

- `RFdiffusion.yaml`: RFdiffusion-specific parameters
- `MPNN.yaml`: ProteinMPNN-specific parameters
- `AlphaFold.yaml`: AlphaFold-specific parameters

## Execution Profiles

### Singularity (Recommended for HPC)

```bash
nextflow run main.nf -profile singularity
```

### Docker

```bash
nextflow run main.nf -profile docker
```

### SLURM Cluster

```bash
nextflow run main.nf -profile singularity,slurm -c conf/slurm.config
```

Edit `conf/slurm.config` to customize:
- GPU queue names
- Resource allocations
- Cluster-specific options

## Output Structure

```
results/
├── rfdiffusion/
│   ├── design_RFD_0.pdb
│   ├── design_RFD_0.trb
│   └── ...
├── proteinmpnn/
│   ├── design_seq1.fa
│   ├── design_seq2.fa
│   └── ...
├── alphafold/
│   ├── structures/
│   │   ├── design_seq1_model_1.pdb
│   │   └── ...
│   └── scores/
│       ├── design_seq1_scores.json
│       └── ...
└── pipeline_info/
    ├── execution_report.html
    ├── execution_timeline.html
    └── execution_trace.txt
```

## Pipeline Architecture

### DSL2 Module Structure

```
FoldFlow-refactored/
├── main.nf                    # Entry point
├── workflows/
│   └── foldflow.nf           # Main workflow logic
├── modules/
│   └── local/
│       ├── rfdiffusion/
│       │   ├── main.nf
│       │   └── environment.yml
│       ├── proteinmpnn/
│       │   ├── main.nf
│       │   └── environment.yml
│       └── alphafold/
│           ├── main.nf
│           └── environment.yml
├── conf/
│   ├── base.config           # Base resources
│   ├── modules.config        # Module-specific settings
│   ├── slurm.config          # SLURM executor config
│   └── test.config           # Test profile
├── bin/                       # Helper scripts
│   ├── reformat_fixed_residues.py
│   ├── split_mpnn_fastas.py
│   └── yaml_to_args.py
└── configs/                   # Module YAML configs
    ├── RFdiffusion.yaml
    ├── MPNN.yaml
    └── AlphaFold.yaml
```

## Customization

### Adding Custom Arguments

Module-specific arguments can be added via `ext.args` in `conf/modules.config`:

```groovy
withName: 'RFDIFFUSION' {
    ext.args = '+inference.ckpt_override_path=/custom/checkpoint.pt'
}
```

### Resource Requirements

Adjust resources in `conf/base.config`:

```groovy
withLabel: 'process_gpu' {
    cpus   = 16
    memory = '128.GB'
    time   = '12.h'
}
```

## Troubleshooting

### Common Issues

**GPU not detected:**
- Ensure `--nv` flag is used for Singularity
- Check GPU availability: `nvidia-smi`

**Container path errors:**
- Verify `singularity.autoMounts = true` in config
- Use `--bind` to explicitly mount directories

**Memory issues:**
- Increase memory in `conf/base.config`
- Use `process_high_memory` label for specific processes

### Debugging

Enable debug mode:

```bash
nextflow run main.nf -profile debug,singularity
```

Check execution logs:
```bash
ls -la .nextflow.log
ls -la work/
```

## Development

### Linting

Run Nextflow linting:

```bash
nextflow lint main.nf
nextflow lint workflows/
nextflow lint modules/
```

### Testing

```bash
# Quick test with stub runs
nextflow run main.nf -profile test -stub

# Full test run
nextflow run main.nf -profile test,singularity
```

## Citation

If you use FoldFlow, please cite:

- RFdiffusion: [Watson et al., Nature 2023]
- ProteinMPNN: [Dauparas et al., Science 2022]
- AlphaFold: [Jumper et al., Nature 2021]

## License

MIT License

## Contact

For questions and support, please open an issue on GitHub.
