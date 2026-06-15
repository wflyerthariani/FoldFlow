/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { RFDIFFUSION  } from '../modules/local/rfdiffusion/main'
include { PROTEINMPNN  } from '../modules/local/proteinmpnn/main'
include { ALPHAFOLD    } from '../modules/local/alphafold/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow FOLDFLOW {
    take:
    design_indices // channel: [ val(meta), val(design_idx), path(input_pdb) ]

    main:
    def ch_versions = channel.empty()

    //
    // MODULE: RFdiffusion - Generate protein backbone structures
    //
    RFDIFFUSION(
        design_indices
    )
    ch_versions = ch_versions.mix(RFDIFFUSION.out.versions)

    //
    // MODULE: ProteinMPNN - Design sequences for the generated backbones
    //
    // Combine PDB and TRB files by meta
    def mpnn_input = RFDIFFUSION.out.structures
        .join(RFDIFFUSION.out.trajectories, by: 0, remainder: true)
    
    PROTEINMPNN(
        mpnn_input
    )
    ch_versions = ch_versions.mix(PROTEINMPNN.out.versions.first())

    //
    // MODULE: AlphaFold - Validate designed sequences by folding
    //
    // Flatten sequences and add meta for each sequence
    def alphafold_input = PROTEINMPNN.out.sequences
        .transpose()
        .map { meta, fasta ->
            def seq_meta = meta.clone()
            seq_meta.seq_id = fasta.baseName
            def matcher = (fasta.baseName =~ /^(.*_mpnn_\d+)_([^_]+)$/)
            if (matcher.find()) {
                seq_meta.lineage = matcher.group(1)
            }
            tuple(seq_meta, fasta)
        }
    
    ALPHAFOLD(
        alphafold_input
    )
    ch_versions = ch_versions.mix(ALPHAFOLD.out.versions.first())

    emit:
    rfdiffusion_structures = RFDIFFUSION.out.structures
    rfdiffusion_trajectories = RFDIFFUSION.out.trajectories
    mpnn_sequences = PROTEINMPNN.out.sequences
    alphafold_structures = ALPHAFOLD.out.structures
    alphafold_scores = ALPHAFOLD.out.scores
    versions = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
