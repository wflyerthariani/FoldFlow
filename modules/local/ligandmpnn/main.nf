process LIGANDMPNN {
    tag "${meta.id}"
    label 'process_gpu'

    def config_path = params.ligandmpnn_config_path ?: "${projectDir}/configs"
    def config_name = params.ligandmpnn_config_name ?: 'LigandMPNN.yaml'
    def config_file = new File("${config_path}/${config_name}")
    def config_text = config_file.exists() ? config_file.text : ''
    def yaml_value = { String key, String defaultValue ->
        def matcher = (config_text =~ /(?m)^${java.util.regex.Pattern.quote(key)}\s*:\s*(.+?)\s*$/)
        if (matcher.find()) {
            return matcher.group(1).replaceAll(/^[\'"]|[\'"]$/, '')
        }
        return defaultValue
    }
    def model_weights_path = yaml_value('_model_weights_path', '')

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'docker://rosettacommons/ligandmpnn'
        : 'rosettacommons/ligandmpnn'}"
    containerOptions {
        if (workflow.containerEngine != 'singularity') {
            return ''
        }
        def binds = []
        if (model_weights_path) {
            binds << "--bind ${model_weights_path}:${model_weights_path}"
        }
        binds.join(' ')
    }

    input:
    tuple val(meta), path(pdb), path(fixed_regions)

    output:
    tuple val(meta), path("*.fa"), emit: sequences
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def num_sequences = params.ligandmpnn_num_sequences ?: 2
    def helper_dir = "${projectDir}/bin"
    def tool_tag = task.ext.tool_name ?: 'ligandmpnn'
    def lineage = meta.lineage ?: "design_${(meta.design_idx as Integer) + 1}"

    """
    output_dir="\${PWD}/LigandMPNNresults_${pdb.baseName}/"
    mkdir -p "\${output_dir}"

    # Build argument array — keeps multi-word values (e.g. fixed residues) as single args
    ligandmpnn_args=(
        --pdb_path "${pdb}"
        --out_folder "\${output_dir}"
        --number_of_batches ${num_sequences}
    )

    # Parse fixed regions from the tool-agnostic fixed_regions file
    if [ -f "${fixed_regions}" ] && [ -s "${fixed_regions}" ]; then
        chains_to_design=\$(grep -- '--chains_to_design' "${fixed_regions}" | cut -d'"' -f2)
        fixed_positions=\$(grep -- '--fixed_positions' "${fixed_regions}" | cut -d'"' -f2)

        if [ -n "\$chains_to_design" ]; then
            ligandmpnn_args+=(--chains_to_design "\${chains_to_design}")
        fi
        if [ -n "\$fixed_positions" ]; then
            # Pass as a single quoted argument — unquoted expansion would split on spaces
            ligandmpnn_args+=(--fixed_residues "\${fixed_positions}")
        fi
    fi

    # Convert YAML config to CLI args (reuses the shared helper)
    get_args=""
    if [ -f "${config_path}/${config_name}" ]; then
        get_args=\$(python ${helper_dir}/yaml_to_args.py "${config_path}/${config_name}" || echo "")
    fi

    python /app/ligandmpnn/run.py "\${ligandmpnn_args[@]}" \${get_args} ${args}

    python ${helper_dir}/split_mpnn_fastas.py \\
        --input-folder "\${output_dir}/seqs" \\
        --output-folder "\${output_dir}/split"

    mv "\${output_dir}/split/"*.fa . || mv "\${output_dir}/seqs/"*.fasta . 2>/dev/null || true

    for f in *.fasta; do
        [ -f "\$f" ] && mv "\$f" "\${f%.fasta}.fa"
    done

    mpnn_counter=1
    for f in *.fa; do
        [ -f "\$f" ] || continue
        mv "\$f" "${lineage}_mpnn_\${mpnn_counter}_${tool_tag}.fa"
        mpnn_counter=\$((mpnn_counter + 1))
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ligandmpnn: \$(python -c "import sys; print(sys.version.split()[0])" 2>/dev/null || echo "unknown")
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def num_sequences = params.ligandmpnn_num_sequences ?: 2
    def tool_tag = task.ext.tool_name ?: 'ligandmpnn'
    def lineage = meta.lineage ?: "design_${(meta.design_idx as Integer) + 1}"
    """
    for i in \$(seq 1 ${num_sequences}); do
        echo ">${meta.id}_seq\${i}" > ${lineage}_mpnn_\${i}_${tool_tag}.fa
        echo "ACDEFGHIKLMNPQRSTVWY" >> ${lineage}_mpnn_\${i}_${tool_tag}.fa
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ligandmpnn: 1.0.0
        python: 3.9.0
    END_VERSIONS
    """
}
