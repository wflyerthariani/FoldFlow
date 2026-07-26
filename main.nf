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
    def num_designs = (params.rfdiff_num_designs ?: params.num_designs ?: 3) as Integer
    def design_indices = channel.of(0..(num_designs - 1))
        .combine(ch_input_pdb)
        .map { idx, pdb ->
            def meta = [
                id: params.output_prefix ?: "design",
                design_idx: idx
            ]
            tuple(meta, idx, pdb)
        }
    
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
