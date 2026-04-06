process RFDIFFUSION {
    tag "${meta.id}_${meta.design_idx}"
    label 'process_gpu'

    // Container support: singularity pulls from docker://, docker uses Docker Hub image
    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? params.rfdiff_sif_path ?: 'docker://rosettacommons/rfdiffusion'
        : 'rosettacommons/rfdiffusion'}"

    input:
    tuple val(meta), val(design_idx)

    output:
    tuple val(meta), path("*.pdb"), emit: structures
    tuple val(meta), path("*.trb"), emit: trajectories, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def config_path = params.rfdiff_config_path ?: params.config_dir ?: '.'
    def config_name = params.rfdiff_config_name ?: 'RFdiffusion.yaml'
    def editables_dir = params.rfdiff_editables_dir ?: '/ibex/user/x_thariaa/RFdiffusionContainer'

    // Construct environment variables
    def schedule_dir = params.rfdiff_editables_dir ? "${params.rfdiff_editables_dir}/schedules" : "${editables_dir}/schedules"
    def model_dir = params.rfdiff_editables_dir ? "${params.rfdiff_editables_dir}/models" : "${editables_dir}/models"

    """
    # Set up environment variables
    export SCHEDULE_DIR="${schedule_dir}"
    export MODEL_DIR="${model_dir}"
    
    # Run RFdiffusion
    run_inference.py \\
        --config-path ${config_path} \\
        --config-name ${config_name} \\
        +inference.output_prefix="\${PWD}/${prefix}_RFD" \\
        +inference.design_startnum=${design_idx} \\
        +inference.schedule_directory_path="\${SCHEDULE_DIR}" \\
        +inference.model_directory_path="\${MODEL_DIR}" \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rfdiffusion: \$(python -c "import sys; print(sys.version.split()[0])" 2>/dev/null || echo "unknown")
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_RFD_${design_idx}.pdb
    touch ${prefix}_RFD_${design_idx}.trb

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rfdiffusion: 1.0.0
        python: 3.9.0
    END_VERSIONS
    """
}
