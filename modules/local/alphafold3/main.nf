process ALPHAFOLD3 {
    tag "${meta.id}"
    label 'process_gpu'
    label 'process_high_memory'

    def config_path = params.alphafold3_config_path ?: "${projectDir}/configs"
    def config_name = params.alphafold3_config_name ?: 'AlphaFold3.yaml'
    def config_file = new File("${config_path}/${config_name}")
    def config_text = config_file.exists() ? config_file.text : ''
    def yaml_value = { String key, String defaultValue ->
        def matcher = (config_text =~ /(?m)^${java.util.regex.Pattern.quote(key)}\s*:\s*(.+?)\s*$/)
        if (matcher.find()) {
            return matcher.group(1).replaceAll(/^['"]|['"]$/, '')
        }
        return defaultValue
    }
    def container_image = yaml_value('_container', '')
    def db_dir = yaml_value('_db_dir', '/ibex/reference/KSL/alphafold/3.0.0')
    def model_path = yaml_value('_model_path', '')
    def chains = yaml_value('_chains', 'first')
    def xla_flags = yaml_value('_xla_flags', '--xla_gpu_enable_triton_gemm=false')
    def model_seeds = yaml_value('model_seeds', '1')
    def num_diffusion_samples = yaml_value('num_diffusion_samples', '5')
    def flash_attention_implementation = yaml_value('flash_attention_implementation', 'triton')

    // DeepMind publishes no AF3 image, so this points at a locally built SIF
    // (see build_container.sh) instead of a registry URI like the other modules.
    container "${container_image}"
    containerOptions {
        if (workflow.containerEngine != 'singularity') {
            return ''
        }
        def binds = []
        if (db_dir) {
            binds << "--bind ${db_dir}:${db_dir}:ro"
        }
        if (model_path) {
            def model_dir = new File(model_path).parent
            binds << "--bind ${model_dir}:${model_dir}:ro"
        }
        binds.join(' ')
    }

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*_alphafold3.pdb"), emit: structures
    tuple val(meta), path("*_alphafold3.cif"), emit: cifs
    tuple val(meta), path("*_alphafold3.json"), emit: scores
    tuple val(meta), path("*_alphafold3.csv"), emit: ranking, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def output_dir = "AlphaFold3results"
    def helper_dir = "${projectDir}/bin"
    def tool_tag = task.ext.tool_name ?: 'alphafold3'
    // Keyed on the full FASTA name (which includes the MPNN tool), so outputs from
    // ProteinMPNN and LigandMPNN sequences with the same lineage do not collide.
    def job_name = fasta.baseName
    def suffix = "${job_name}_alphafold_1_${tool_tag}"

    """
    if [ ! -f /app/alphafold/run_alphafold.py ]; then
        echo "ERROR: AlphaFold 3 container not in use. Set _container in ${config_path}/${config_name} to the SIF built by modules/local/alphafold3/build_container.sh." >&2
        exit 1
    fi
    if [ ! -d "${db_dir}/mmcif_files" ]; then
        echo "ERROR: AlphaFold 3 database directory not accessible in container: ${db_dir}" >&2
        exit 1
    fi
    if [ ! -f "${model_path}" ]; then
        echo "ERROR: AlphaFold 3 weights not found: '${model_path}'. Set _model_path in ${config_path}/${config_name}." >&2
        exit 1
    fi

    # AF3 loads whichever weights file it recognises in --model_dir (preferring .bin.zst over .bin),
    # so stage only the configured file.
    mkdir -p af3_models
    ln -sf "${model_path}" af3_models/

    # _chains: first folds only the first chain (as the AlphaFold 2 module does); all folds the complex.
    python3 ${helper_dir}/fasta_to_af3_json.py \\
        --fasta "${fasta}" \\
        --name "${job_name}" \\
        --chains ${chains} \\
        --seeds "${model_seeds}" \\
        --output af3_input.json

    export XLA_FLAGS="${xla_flags}"
    export XLA_PYTHON_CLIENT_PREALLOCATE=true
    export XLA_CLIENT_MEM_FRACTION=0.95

    python /app/alphafold/run_alphafold.py \\
        --json_path=af3_input.json \\
        --model_dir=\${PWD}/af3_models \\
        --db_dir=${db_dir} \\
        --output_dir=${output_dir} \\
        --force_output_dir \\
        --num_diffusion_samples=${num_diffusion_samples} \\
        --flash_attention_implementation=${flash_attention_implementation} \\
        --jackhmmer_n_cpu=${task.cpus} \\
        --nhmmer_n_cpu=${task.cpus} \\
        ${args}

    # Collect the top-ranked prediction and apply the pipeline naming convention.
    result_dir="${output_dir}/${job_name}"
    cp "\${result_dir}/${job_name}_model.cif" "model_${suffix}.cif"
    cp "\${result_dir}/${job_name}_summary_confidences.json" "summary_confidences_${suffix}.json"
    cp "\${result_dir}/${job_name}_confidences.json" "confidences_${suffix}.json"
    cp "\${result_dir}/${job_name}_ranking_scores.csv" "ranking_scores_${suffix}.csv"
    python3 -c "import gemmi; gemmi.read_structure('model_${suffix}.cif').write_pdb('model_${suffix}.pdb')"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold3: \$(python -c "import importlib.metadata as m; print(m.version('alphafold3'))" 2>/dev/null || echo "unknown")
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def tool_tag = task.ext.tool_name ?: 'alphafold3'
    def suffix = "${fasta.baseName}_alphafold_1_${tool_tag}"
    """
    touch model_${suffix}.pdb
    touch model_${suffix}.cif
    touch summary_confidences_${suffix}.json
    touch confidences_${suffix}.json
    touch ranking_scores_${suffix}.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold3: 3.0.4
        python: 3.12.0
    END_VERSIONS
    """
}
