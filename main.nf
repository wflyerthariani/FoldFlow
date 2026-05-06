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
    def design_indices = channel.of(0..(params.num_designs - 1))
        .map { idx ->
            def meta = [
                id: params.output_prefix ?: "design",
                design_idx: idx
            ]
            tuple(meta, idx)
        }
    
    // Run main workflow
    FOLDFLOW(
        design_indices
    )
    
    emit:
    rfdiffusion_structures = FOLDFLOW.out.rfdiffusion_structures
    rfdiffusion_trajectories = FOLDFLOW.out.rfdiffusion_trajectories
    mpnn_sequences = FOLDFLOW.out.mpnn_sequences
    alphafold_structures = FOLDFLOW.out.alphafold_structures
    alphafold_scores = FOLDFLOW.out.alphafold_scores
    versions = FOLDFLOW.out.versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {
    FOLDFLOW_PIPELINE()
    
    workflow.onComplete {
        log.info "Pipeline completed at: ${workflow.complete}"
        log.info "Execution status: ${workflow.success ? 'OK' : 'failed'}"
        log.info "Execution duration: ${workflow.duration}"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
