nextflow.enable.dsl=2

include { RFdiffusion } from './modules/RFdiffusion.nf'
include { ProteinMPNN } from './modules/ProteinMPNN.nf'
include { AlphaFold } from './modules/AlphaFold.nf'

workflow {
    rf_in_ch = Channel.from(0..(params.num_designs-1))
        .map { idx -> tuple(params.contig_str, params.output_prefix, idx, file(params.input_pdb)) }
    
    rf_out_ch = rf_in_ch | RFdiffusion

    mpnn_out_ch = rf_out_ch | ProteinMPNN

    alphafold_out_ch = mpnn_out_ch.fasta_files.flatten() | AlphaFold
}