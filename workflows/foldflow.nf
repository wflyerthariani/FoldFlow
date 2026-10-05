/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { RFDIFFUSION  } from '../modules/local/rfdiffusion/main'
include { BOLTZGEN     } from '../modules/local/boltzgen/main'
include { PROTEINMPNN  } from '../modules/local/proteinmpnn/main'
include { LIGANDMPNN   } from '../modules/local/ligandmpnn/main'
include { ALPHAFOLD    } from '../modules/local/alphafold/main'
include { ALPHAFOLD3   } from '../modules/local/alphafold3/main'

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
    // Shared backbone channel — all sequence design tools receive this.
    def ch_backbone_input = RFDIFFUSION.out.structures
        .mix(BOLTZGEN.out.structures)
        .join(
            RFDIFFUSION.out.fixed_regions.mix(BOLTZGEN.out.fixed_regions),
            by: 0
        )

    // ── SEQUENCE DESIGN STAGE ─────────────────────────────────────────────
    // Every tool receives ch_backbone_input and runs in parallel.
    // To add another sequence design tool:
    //   1. Add an include { NEWTOOL } line at the top of this file
    //   2. Call NEWTOOL(ch_backbone_input) below
    //   3. Mix its .out.sequences into ch_sequences
    //   4. Add a withName: 'NEWTOOL' block in conf/modules.config
    PROTEINMPNN(ch_backbone_input)
    ch_versions = ch_versions.mix(PROTEINMPNN.out.versions.first())

    LIGANDMPNN(ch_backbone_input)
    ch_versions = ch_versions.mix(LIGANDMPNN.out.versions.first())

    def ch_sequences = PROTEINMPNN.out.sequences
        .mix(LIGANDMPNN.out.sequences)
    // ──────────────────────────────────────────────────────────────────────

    // ── VALIDATION STAGE ──────────────────────────────────────────────────
    // Every structure predictor receives alphafold_input and runs in parallel.
    // To add another validation tool:
    //   1. Add an include { NEWTOOL } line at the top of this file
    //   2. Call NEWTOOL(alphafold_input) below
    //   3. Mix its .out.structures / .out.scores into ch_val_structures / ch_val_scores
    //   4. Add a withName: 'NEWTOOL' block in conf/modules.config
    def alphafold_input = ch_sequences
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
    
    ALPHAFOLD(alphafold_input)
    ch_versions = ch_versions.mix(ALPHAFOLD.out.versions.first())

    ALPHAFOLD3(alphafold_input)
    ch_versions = ch_versions.mix(ALPHAFOLD3.out.versions.first())

    def ch_val_structures = ALPHAFOLD.out.structures
        .mix(ALPHAFOLD3.out.structures)
    def ch_val_scores = ALPHAFOLD.out.scores
        .mix(ALPHAFOLD3.out.scores)
    // ──────────────────────────────────────────────────────────────────────

    emit:
    design_structures    = RFDIFFUSION.out.structures.mix(BOLTZGEN.out.structures)
    design_fixed_regions = RFDIFFUSION.out.fixed_regions.mix(BOLTZGEN.out.fixed_regions)
    mpnn_sequences       = ch_sequences
    alphafold_structures = ch_val_structures
    alphafold_scores     = ch_val_scores
    versions             = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
