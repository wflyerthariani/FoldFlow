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
    def ch_structures
    def ch_fixed_regions

    //
    // MODULE: Backbone design — RFdiffusion or BoltzGen, selected via params.design_tool
    //
    if (params.design_tool == 'boltzgen') {
        BOLTZGEN(design_indices)
        ch_versions     = ch_versions.mix(BOLTZGEN.out.versions)
        ch_structures   = BOLTZGEN.out.structures
        ch_fixed_regions = BOLTZGEN.out.fixed_regions
    } else {
        RFDIFFUSION(design_indices)
        ch_versions     = ch_versions.mix(RFDIFFUSION.out.versions)
        ch_structures   = RFDIFFUSION.out.structures
        ch_fixed_regions = RFDIFFUSION.out.fixed_regions
    }

    //
    // MODULE: ProteinMPNN - Design sequences for the generated backbones
    //
    def mpnn_input = ch_structures
        .join(ch_fixed_regions, by: 0)
    
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
    design_structures    = ch_structures
    design_fixed_regions = ch_fixed_regions
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
