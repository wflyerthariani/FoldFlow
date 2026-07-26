/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { RFDIFFUSION  } from '../modules/local/rfdiffusion/main'
include { BOLTZGEN     } from '../modules/local/boltzgen/main'
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

    // Stamp each copy of design_indices with the tool-specific lineage before branching.
    // DSL2 channels can be consumed by multiple operators independently.
    def rfd_indices = design_indices.map { meta, idx, pdb ->
        tuple(meta + [lineage: "rfdiffusion_${(idx as Integer) + 1}"], idx, pdb)
    }
    def bg_indices = design_indices.map { meta, idx, pdb ->
        tuple(meta + [lineage: "boltzgen_${(idx as Integer) + 1}"], idx, pdb)
    }

    //
    // MODULE: RFdiffusion — backbone structure generation
    //
    RFDIFFUSION(rfd_indices)
    ch_versions = ch_versions.mix(RFDIFFUSION.out.versions)

    //
    // MODULE: BoltzGen — backbone structure generation (runs in parallel with RFdiffusion)
    //
    BOLTZGEN(bg_indices)
    ch_versions = ch_versions.mix(BOLTZGEN.out.versions)

    //
    // MODULE: ProteinMPNN - Design sequences for all generated backbones
    //
    def mpnn_input = RFDIFFUSION.out.structures
        .mix(BOLTZGEN.out.structures)
        .join(
            RFDIFFUSION.out.fixed_regions.mix(BOLTZGEN.out.fixed_regions),
            by: 0
        )
    
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
    design_structures    = RFDIFFUSION.out.structures.mix(BOLTZGEN.out.structures)
    design_fixed_regions = RFDIFFUSION.out.fixed_regions.mix(BOLTZGEN.out.fixed_regions)
    mpnn_sequences       = PROTEINMPNN.out.sequences
    alphafold_structures = ALPHAFOLD.out.structures
    alphafold_scores     = ALPHAFOLD.out.scores
    versions             = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
