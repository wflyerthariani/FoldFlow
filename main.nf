#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FoldFlow - Protein Design Pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    A Nextflow pipeline for de novo protein design using RFdiffusion, ProteinMPNN,
    and AlphaFold validation.
    
    Github: https://github.com/user/FoldFlow
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FOLDFLOW } from './workflows/foldflow'
include { paramsSummaryLog; samplesheetToList } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline
//
workflow FOLDFLOW_PIPELINE {
    main:
    
    // Print parameter summary
    log.info paramsSummaryLog(workflow)
    
    // Create design index channel
    def ch_input_pdb = channel.fromPath(params.input_pdb, checkIfExists: true)

    // Each backbone tool decides how many backbones it contributes via _num_outputs in
    // its own YAML. We emit as many design indices as the greediest tool needs; each
    // module then ignores the indices beyond its own count, so a tool set to 0 simply
    // never runs.
    def rfdiff_designs = ToolConfig.numOutputs(
        params.rfdiff_config_path, params.rfdiff_config_name, params.rfdiff_num_designs, 3)
    def boltzgen_designs = ToolConfig.numOutputs(
        params.boltzgen_config_path, params.boltzgen_config_name, params.boltzgen_num_designs, 3)
    def num_designs = Math.max(rfdiff_designs, boltzgen_designs)

    if (num_designs < 1) {
        log.warn "Both backbone tools have _num_outputs 0 - no designs will be generated."
    }

    def design_indices = num_designs > 0
        ? channel.of(0..(num_designs - 1))
            .combine(ch_input_pdb)
            .map { idx, pdb ->
                def meta = [
                    id: params.output_prefix ?: "design",
                    design_idx: idx
                ]
                tuple(meta, idx, pdb)
            }
        : channel.empty()

    // Run main workflow
    FOLDFLOW(
        design_indices
    )
    
    emit:
    design_structures    = FOLDFLOW.out.design_structures
    design_fixed_regions = FOLDFLOW.out.design_fixed_regions
    mpnn_sequences       = FOLDFLOW.out.mpnn_sequences
    alphafold_structures = FOLDFLOW.out.alphafold_structures
    alphafold_scores     = FOLDFLOW.out.alphafold_scores
    versions             = FOLDFLOW.out.versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {
    FOLDFLOW_PIPELINE()
    
    workflow.onComplete {
        log.info "Pipeline completed at: ${complete ?: 'unknown'}"
        log.info "Execution status: ${success ? 'OK' : 'failed'}"
        log.info "Execution duration: ${duration ?: 'unknown'}"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
