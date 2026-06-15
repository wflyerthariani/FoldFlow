process PROTEINMPNN {
    tag "${meta.id}"
    label 'process_gpu'

    def config_path = params.mpnn_config_path ?: "${projectDir}/configs"
    def config_name = params.mpnn_config_name ?: 'MPNN.yaml'
    def config_file = new File("${config_path}/${config_name}")
    def config_text = config_file.exists() ? config_file.text : ''
    def yaml_value = { String key, String defaultValue ->
        def matcher = (config_text =~ /(?m)^${java.util.regex.Pattern.quote(key)}\s*:\s*(.+?)\s*$/)
        if (matcher.find()) {
            return matcher.group(1).replaceAll(/^[\'"]|[\'"]$/, '')
        }
        return defaultValue
    }
    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'docker://rosettacommons/proteinmpnn:latest'
        : 'docker.io/rosettacommons/proteinmpnn:latest'}"

    input:
    tuple val(meta), path(pdb), path(trb)

    output:
    tuple val(meta), path("*.fa"), emit: sequences
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def num_sequences = params.mpnn_num_sequences ?: 2
    def helper_dir = "${projectDir}/bin"
    def tool_tag = task.ext.tool_name ?: 'proteinmpnn'
    def lineage = meta.lineage ?: "rfdiffusion_${(meta.design_idx as Integer) + 1}"

    """
    # Create working directories
    output_dir="\${PWD}/MPNNresults_${pdb.baseName}/"
    mkdir -p "\${output_dir}"
    
    folder_with_pdbs="\${PWD}/MPNNdiv_${pdb.baseName}/"
    mkdir -p "\${folder_with_pdbs}"
    cp "${pdb}" "\${folder_with_pdbs}/"
    
    path_for_parsed_chains="\${folder_with_pdbs}/parsed_pdbs.jsonl"
    path_for_fixed_positions="\${folder_with_pdbs}/fixed_pdbs.jsonl"
    
    # Parse PDB chains
    python /app/proteinmpnn/helper_scripts/parse_multiple_chains.py \\
        --input_path "\${folder_with_pdbs}" \\
        --output_path "\${path_for_parsed_chains}"
    
    # Extract fixed residues from trajectory file
    if [ -f "${trb}" ]; then
        get_fixed=\$(python ${helper_dir}/reformat_fixed_residues.py --input-file ${trb})
        chains_to_design=\$(echo "\${get_fixed}" | grep -- '--chains_to_design' | cut -d'"' -f2)
        fixed_positions=\$(echo "\${get_fixed}" | grep -- '--fixed_positions' | cut -d'"' -f2)
        
        # Create fixed positions dictionary
        python /app/proteinmpnn/helper_scripts/make_fixed_positions_dict.py \\
            --input_path="\${path_for_parsed_chains}" \\
            --output_path="\${path_for_fixed_positions}" \\
            --chain_list "\${chains_to_design}" \\
            --position_list "\${fixed_positions}"
        
        fixed_pos_arg="--fixed_positions_jsonl \${path_for_fixed_positions}"
    else
        fixed_pos_arg=""
    fi
    
    # Get additional args from config if available
    if [ -f "${config_path}/${config_name}" ]; then
        get_args=\$(python ${helper_dir}/yaml_to_args.py "${config_path}/${config_name}" || echo "")
    else
        get_args=""
    fi
    
    # Run ProteinMPNN - Nextflow handles container execution
    python /app/proteinmpnn/protein_mpnn_run.py \\
        --jsonl_path "\${path_for_parsed_chains}" \\
        --out_folder "\${output_dir}" \\
        \${fixed_pos_arg} \\
        --num_seq_per_target ${num_sequences} \\
        --batch_size 1 \\
        \${get_args} \\
        ${args}
    
    # Split FASTA files
    python ${helper_dir}/split_mpnn_fastas.py \\
        --input-folder "\${output_dir}/seqs" \\
        --output-folder "\${output_dir}/split"
    
    # Move output FASTA files to main directory
    mv "\${output_dir}/split/"*.fa . || mv "\${output_dir}/seqs/"*.fasta . 2>/dev/null || true
    
    # Rename to standard format if needed
    for f in *.fasta; do
        [ -f "\$f" ] && mv "\$f" "\${f%.fasta}.fa"
    done

    # Append module name so outputs are traceable to the generating tool.
    mpnn_counter=1
    for f in *.fa; do
        [ -f "\$f" ] || continue
        mv "\$f" "${lineage}_mpnn_\${mpnn_counter}_${tool_tag}.fa"
        mpnn_counter=\$((mpnn_counter + 1))
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        proteinmpnn: \$(python -c "import sys; print(sys.version.split()[0])" 2>/dev/null || echo "unknown")
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def num_sequences = params.mpnn_num_sequences ?: 2
    def tool_tag = task.ext.tool_name ?: 'proteinmpnn'
    def lineage = meta.lineage ?: "rfdiffusion_${(meta.design_idx as Integer) + 1}"
    """
    for i in \$(seq 1 ${num_sequences}); do
        echo ">${prefix}_seq\${i}" > ${lineage}_mpnn_\${i}_${tool_tag}.fa
        echo "ACDEFGHIKLMNPQRSTVWY" >> ${lineage}_mpnn_\${i}_${tool_tag}.fa
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        proteinmpnn: 1.0.0
        python: 3.9.0
    END_VERSIONS
    """
}
