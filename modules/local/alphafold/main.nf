process ALPHAFOLD {
    tag "${meta.id}"
    label 'process_gpu'
    label 'process_high_memory'

    def config_path = params.alphafold_config_path ?: "${projectDir}/configs"
    def config_name = params.alphafold_config_name ?: 'AlphaFold.yaml'
    def config_file = new File("${config_path}/${config_name}")
    def config_text = config_file.exists() ? config_file.text : ''
    def yaml_value = { String key, String defaultValue ->
        def matcher = (config_text =~ /(?m)^${java.util.regex.Pattern.quote(key)}\s*:\s*(.+?)\s*$/)
        if (matcher.find()) {
            return matcher.group(1).replaceAll(/^['"]|['"]$/, '')
        }
        return defaultValue
    }
    def data_dir = yaml_value('_data_dir', '/data')
    def cuda_lib_dir = yaml_value('_cuda_lib_dir', '')
    def db_preset = yaml_value('db_preset', 'full_dbs')
    def model_preset = yaml_value('model_preset', 'monomer')
    def max_template_date = yaml_value('max_template_date', '2023-10-01')
    def use_gpu_relax = yaml_value('use_gpu_relax', 'true')
    def jax_platform = yaml_value('_jax_platform', 'cuda').toLowerCase()

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'docker://catgumag/alphafold:2.3.0'
        : 'docker.io/catgumag/alphafold:2.3.0'}"
    containerOptions {
        if (workflow.containerEngine != 'singularity') {
            return ''
        }
        def binds = []
        if (data_dir) {
            binds << "--bind ${data_dir}:${data_dir}"
        }
        if (cuda_lib_dir) {
            binds << "--bind ${cuda_lib_dir}:${cuda_lib_dir}:ro"
        }
        binds.join(' ')
    }

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.pdb"), emit: structures
    tuple val(meta), path("*.json"), emit: scores, optional: true
    tuple val(meta), path("timings.json"), emit: timings, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def output_dir = "AlphaFoldresults"

    """
    # Create output directory
    mkdir -p ${output_dir}

    # Validate that AlphaFold data directory is visible from inside the container.
    if [ ! -d "${data_dir}" ]; then
        echo "ERROR: AlphaFold data directory not accessible in container: ${data_dir}" >&2
        echo "Set _data_dir in ${config_path}/${config_name} to a valid host path; this module bind-mounts it automatically for Singularity." >&2
        exit 1
    fi

    # Build database flags following AlphaFold container layout conventions.
    uniref90_database_path="${data_dir}/uniref90/uniref90.fasta"
    mgnify_database_path="${data_dir}/mgnify/mgy_clusters_2022_05.fa"
    template_mmcif_dir="${data_dir}/pdb_mmcif/mmcif_files"
    obsolete_pdbs_path="${data_dir}/pdb_mmcif/obsolete.dat"
    bfd_database_path="${data_dir}/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt"
    small_bfd_database_path="${data_dir}/small_bfd/bfd-first_non_consensus_sequences.fasta"
    uniref30_database_path="${data_dir}/uniref30/UniRef30_2021_03"
    pdb70_database_path="${data_dir}/pdb70/pdb70"
    uniprot_database_path="${data_dir}/uniprot/uniprot.fasta"
    pdb_seqres_database_path="${data_dir}/pdb_seqres/pdb_seqres.txt"

    required_paths=(
        "\${uniref90_database_path}"
        "\${mgnify_database_path}"
        "\${template_mmcif_dir}"
        "\${obsolete_pdbs_path}"
    )

    if [[ "${db_preset}" == "reduced_dbs" ]]; then
        required_paths+=("\${small_bfd_database_path}")
        db_flags="--small_bfd_database_path=\${small_bfd_database_path}"
    else
        required_paths+=("\${uniref30_database_path}" "\${bfd_database_path}")
        db_flags="--uniref30_database_path=\${uniref30_database_path} --bfd_database_path=\${bfd_database_path}"
    fi

    if [[ "${model_preset}" == "multimer" ]]; then
        required_paths+=("\${uniprot_database_path}" "\${pdb_seqres_database_path}")
        model_flags="--uniprot_database_path=\${uniprot_database_path} --pdb_seqres_database_path=\${pdb_seqres_database_path}"
    else
        required_paths+=("\${pdb70_database_path}")
        model_flags="--pdb70_database_path=\${pdb70_database_path}"
    fi

    path_or_prefix_exists() {
        local candidate="\$1"
        if [[ -e "\${candidate}" ]]; then
            return 0
        fi

        compgen -G "\${candidate}*" > /dev/null
    }

    for p in "\${required_paths[@]}"; do
        if ! path_or_prefix_exists "\${p}"; then
            echo "ERROR: Required AlphaFold database path not found: \${p}" >&2
            exit 1
        fi
    done

    # Runtime settings recommended for AlphaFold on Singularity + SLURM GPU nodes.
    export TF_FORCE_UNIFIED_MEMORY=1
    export XLA_PYTHON_CLIENT_MEM_FRACTION=4.0
    export XLA_PYTHON_CLIENT_PREALLOCATE=false
    export OPENMM_CPU_THREADS=${task.cpus}
    export MAX_CPUS=${task.cpus}
    export NVIDIA_VISIBLE_DEVICES=\${CUDA_VISIBLE_DEVICES:-all}
    if [[ -n "${cuda_lib_dir}" ]]; then
        export LD_LIBRARY_PATH="${cuda_lib_dir}:\${LD_LIBRARY_PATH:-}"
    fi

    # Optional backend override from YAML for CUDA/library compatibility issues.
    if [[ "${jax_platform}" == "cpu" ]]; then
        export JAX_PLATFORM_NAME=cpu
        export CUDA_VISIBLE_DEVICES=""
        export NVIDIA_VISIBLE_DEVICES=""
    fi
    
    # Run AlphaFold
    /app/run_alphafold.sh \\
        --fasta_paths=${fasta} \\
        --data_dir=${data_dir} \\
        --output_dir=${output_dir}/ \\
        --db_preset=${db_preset} \\
        --model_preset=${model_preset} \\
        --max_template_date=${max_template_date} \\
        --uniref90_database_path=\${uniref90_database_path} \\
        --mgnify_database_path=\${mgnify_database_path} \\
        --template_mmcif_dir=\${template_mmcif_dir} \\
        --obsolete_pdbs_path=\${obsolete_pdbs_path} \\
        --use_gpu_relax=${use_gpu_relax} \\
        \${db_flags} \\
        \${model_flags} \\
        ${args}
    
    # Move results to main directory
    find ${output_dir} -name "*.pdb" -exec mv {} . \\;
    find ${output_dir} -name "*scores*.json" -exec mv {} . \\; 2>/dev/null || true
    find ${output_dir} -name "timings.json" -exec mv {} . \\; 2>/dev/null || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold: \$(python -c "import sys; print(sys.version.split()[0])" 2>/dev/null || echo "unknown")
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_model_1.pdb
    touch ${prefix}_scores.json
    touch timings.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold: 2.3.2
        python: 3.9.0
    END_VERSIONS
    """
}
