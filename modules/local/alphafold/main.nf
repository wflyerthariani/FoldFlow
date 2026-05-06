process ALPHAFOLD {
    tag "${meta.id}"
    label 'process_gpu'
    label 'process_high_memory'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? params.alphafold_sif_path ?: 'docker://alphafold/alphafold:latest'
        : 'docker.io/alphafold/alphafold:latest'}"

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
    def data_dir = params.alphafold_data_dir ?: '/data'
    def config_path = params.alphafold_config_path ?: params.config_dir ?: '.'
    def config_name = params.alphafold_config_name ?: 'AlphaFold.yaml'
    def helper_dir = params.helper_dir ?: './bin'

    """
    # Create output directory
    mkdir -p ${output_dir}
    
    # Get additional args from config if available
    if [ -f "${config_path}/${config_name}" ]; then
        get_args=\$(python ${helper_dir}/yaml_to_args.py "${config_path}/${config_name}" || echo "")
    else
        get_args=""
    fi
    
    # Run AlphaFold
    /opt/run_alphafold.sh \\
        -f ${fasta} \\
        -d ${data_dir} \\
        -o ${output_dir}/ \\
        \${get_args} \\
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
