nextflow.enable.dsl=2

params.rfdiff_editables_dir = '/ibex/user/thariaaa/RFdiffContainer'
params.rfdiff_sif_path = '/ibex/user/thariaaa/RFdiffContainer/RFdiffusion.sif'

params.mpnn_editables_dir = '/ibex/user/thariaaa/MPNNContainer'
params.mpnn_sif_path = '/ibex/user/thariaaa/MPNNContainer/ProteinMPNN.sif'

params.contig_str = 'contigmap.contigs=[150-150]'
params.input_pdb = '/ibex/user/thariaaa/ContainerizedProteinSynthesis/5TPN.pdb'
params.num_designs = 5
params.output_prefix = 'test'

process RFdiffusion {
    tag "rf_array_${task.index}"
    
    input:
        tuple val(contig_str), val(output_prefix), val(design_startnum), path(input_pdb)
    output:
        tuple val(design_startnum), val(output_prefix), path("RFD${output_prefix}_*.pdb"), path("RFD${output_prefix}_*.trb")
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
    conda 'envs/MPNN-env.yml'
    input:
        tuple val(index), val(output_prefix), file(pdb), file(trb)
    output:
        path "mpnn_output_${index}.txt"
    script:
        """
        output_dir="\$PWD/MPNNresults_${output_prefix}_${index}/"
        mkdir -p "\$output_dir"

        folder_with_pdbs="\$PWD/MPNNdiv_${output_prefix}_${index}/"
        mkdir -p "\$folder_with_pdbs"
        cp "$pdb" "\$folder_with_pdbs/"
        path_for_parsed_chains="\$folder_with_pdbs/parsed_pdbs.jsonl"
        path_for_fixed_positions="\$folder_with_pdbs/fixed_pdbs.jsonl"
        
        singularity exec --nv \
            --bind "${params.mpnn_editables_dir}":"${params.mpnn_editables_dir}" \
            --pwd  "${params.mpnn_editables_dir}" \
            "${params.mpnn_sif_path}" \
            python /opt/ProteinMPNN/helper_scripts/parse_multiple_chains.py \
                --input_path "\$folder_with_pdbs" \
                --output_path "\$path_for_parsed_chains"
        
        get_fixed=\$(python ${projectDir}/helper/reformat_fixed_residues.py --input-file $trb)

        chains_to_design=\$(echo "\$get_fixed" | grep -- '--chains_to_design' | cut -d'"' -f2)
        fixed_positions=\$(echo "\$get_fixed" | grep -- '--fixed_positions' | cut -d'"' -f2)

        singularity exec --nv \
            --bind "${params.mpnn_editables_dir}":"${params.mpnn_editables_dir}" \
            --pwd  "${params.mpnn_editables_dir}" \
            "${params.mpnn_sif_path}" \
            python /opt/ProteinMPNN/helper_scripts/make_fixed_positions_dict.py \
                --input_path=\$path_for_parsed_chains --output_path=\$path_for_fixed_positions --chain_list "\$chains_to_design" --position_list "\$fixed_positions"

        singularity exec --nv \
            --bind "${params.mpnn_editables_dir}":"${params.mpnn_editables_dir}" \
            --pwd  "${params.mpnn_editables_dir}" \
            "${params.mpnn_sif_path}" \
            python /opt/ProteinMPNN/protein_mpnn_run.py \
                --jsonl_path \$path_for_parsed_chains \
                --out_folder \$output_dir \
                --fixed_positions_jsonl \$path_for_fixed_positions \
                --num_seq_per_target 2 \
                --sampling_temp "0.1" \
                --seed 37 \
                --batch_size 1

        # Example command, replace with your actual ProteinMPNN invocation
        echo "Running ProteinMPNN on $pdb and $trb" > mpnn_output_${index}.txt
        """
}

workflow {
    rf_out_ch = Channel.from(0..(params.num_designs-1))
        .map { idx -> tuple(params.contig_str, params.output_prefix, idx, file(params.input_pdb)) }
        | RFdiffusion

    mpnn_out_ch = rf_out_ch | ProteinMPNN
}