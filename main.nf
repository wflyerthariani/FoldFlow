nextflow.enable.dsl=2

params.rfdiff_editables_dir = '/ibex/user/thariaaa/RFdiffContainer'
params.rfdiff_sif_path = '/ibex/user/thariaaa/RFdiffContainer/RFdiffusion.sif'
params.contig_str = 'contigmap.contigs=[150-150]'
params.input_pdb = '/ibex/user/thariaaa/ContainerizedProteinSynthesis/5TPN.pdb'
params.num_designs = 5
params.output_prefix = 'test'

process RFdiffusion {
    tag "rf_array_${task.index}"
    
    input:
        tuple val(contig_str), val(output_prefix), val(design_startnum), path(input_pdb)
    output:
        tuple val(design_startnum), path("RFD${output_prefix}_*.pdb"), path("RFD${output_prefix}_*.trb")
    script:
        """
        singularity exec --nv \
            --bind "${params.rfdiff_editables_dir}":"${params.rfdiff_editables_dir}" \
            --env SCHEDULE_DIR="${params.rfdiff_editables_dir}/schedules" \
            --env MODEL_DIR="${params.rfdiff_editables_dir}/models" \
            "${params.rfdiff_sif_path}" \
            /opt/miniconda/envs/SE3nv/bin/python /opt/RFdiffusion/scripts/run_inference.py \
                "$contig_str" \
                inference.output_prefix="\${PWD}/RFD$output_prefix" \
                inference.num_designs=1 \
                inference.design_startnum="$design_startnum" 
        """
}

process ProteinMPNN {
    tag "mpnn_${task.index}"
    input:
        tuple val(index), file(pdb), file(trb)
    output:
        path "mpnn_output_${index}.txt"
    script:
        """
        # Example command, replace with your actual ProteinMPNN invocation
        echo "Running ProteinMPNN on ${pdb} and ${trb}" > mpnn_output_${index}.txt
        """
}

workflow {
    rf_out_ch = Channel.from(0..(params.num_designs-1))
        .map { idx -> tuple(params.contig_str, params.output_prefix, idx, file(params.input_pdb)) }
        | RFdiffusion

    mpnn_out_ch = rf_out_ch | ProteinMPNN
}