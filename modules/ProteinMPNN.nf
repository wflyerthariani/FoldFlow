process ProteinMPNN {
    tag "mpnn_${task.index}"
    conda 'envs/helper-env.yml'
    input:
        tuple file(pdb), file(trb)
    output:
        path "MPNNresults_${pdb.baseName}/split/*.fasta", emit: fasta_files
    script:
        """
        output_dir="\$PWD/MPNNresults_${pdb.baseName}/"
        mkdir -p "\$output_dir"

        folder_with_pdbs="\$PWD/MPNNdiv_${pdb.baseName}/"
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

        get_args=\$(python ${projectDir}/helper/yaml_to_args.py "${params.config_dir}/${params.mpnn_config_name}")

        singularity exec --nv \
            --bind "${params.mpnn_editables_dir}":"${params.mpnn_editables_dir}" \
            --pwd  "${params.mpnn_editables_dir}" \
            "${params.mpnn_sif_path}" \
            python /opt/ProteinMPNN/protein_mpnn_run.py \
                --jsonl_path \$path_for_parsed_chains \
                --out_folder \$output_dir \
                --fixed_positions_jsonl \$path_for_fixed_positions \
                --num_seq_per_target ${params.mpnn_num_sequences} \
                --batch_size 1 \${get_args}
        
        python ${projectDir}/helper/split_mpnn_fastas.py \
            --input-folder "\$output_dir/seqs" \
            --output-folder "\$output_dir/split"
        """
}