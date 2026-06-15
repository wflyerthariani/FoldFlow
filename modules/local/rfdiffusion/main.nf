process RFDIFFUSION {
    tag "${meta.id}_${meta.design_idx}"
    label 'process_gpu'

    def config_path = params.rfdiff_config_path ?: "${projectDir}/configs"
    def config_name = params.rfdiff_config_name ?: 'RFdiffusion.yaml'
    def config_file = new File("${config_path}/${config_name}")
    def config_text = config_file.exists() ? config_file.text : ''
    def yaml_value = { String key, String defaultValue ->
        def matcher = (config_text =~ /(?m)^${java.util.regex.Pattern.quote(key)}\s*:\s*(.+?)\s*$/)
        if (matcher.find()) {
            return matcher.group(1).replaceAll(/^[\'"]|[\'"]$/, '')
        }
        return defaultValue
    }
    def editables_dir = yaml_value('_editables_dir', projectDir.toString())
    def schedule_dir = yaml_value('_schedule_dir', "${editables_dir}/schedules")
    def model_dir = yaml_value('_model_dir', "${editables_dir}/models")

    // Container support: singularity pulls from docker://, docker uses Docker Hub image
    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'docker://rosettacommons/rfdiffusion'
        : 'rosettacommons/rfdiffusion'}"
    containerOptions {
        if (workflow.containerEngine != 'singularity') {
            return ''
        }
        def binds = []
        if (schedule_dir) {
            binds << "--bind ${schedule_dir}:${schedule_dir}"
        }
        if (model_dir) {
            binds << "--bind ${model_dir}:${model_dir}"
        }
        binds.join(' ')
    }

    input:
    tuple val(meta), val(design_idx), path(input_pdb)

    output:
    tuple val(meta), path("*_rfdiffusion.pdb"), emit: structures
    tuple val(meta), path("*_rfdiffusion.fixed_regions"), emit: fixed_regions
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def tool_tag = task.ext.tool_name ?: 'rfdiffusion'
    def lineage = meta.lineage ?: "rfdiffusion_${(design_idx as Integer) + 1}"
    def helper_dir = params.helper_dir ?: "${projectDir}/bin"

    """
    # Set up environment variables
    export SCHEDULE_DIR="${schedule_dir}"
    export MODEL_DIR="${model_dir}"
    
    # Run RFdiffusion
    run_inference.py \\
        --config-path ${config_path} \\
        --config-name ${config_name} \\
        +inference.input_pdb="\${PWD}/${input_pdb.name}" \\
        +inference.output_prefix="\${PWD}/${prefix}_RFD" \\
        +inference.design_startnum=${design_idx} \\
        +inference.schedule_directory_path="\${SCHEDULE_DIR}" \\
        +inference.model_directory_path="\${MODEL_DIR}" \\
        ${args}

    # Remove staged input PDB symlink/copy so it cannot be emitted as a process output.
    rm -f "${input_pdb.name}" || true

    # Append module name so outputs are traceable to the generating tool.
    for f in *.pdb; do
        [ -f "\$f" ] || continue
        [[ "\$f" == *"_${lineage}_${tool_tag}.pdb" ]] && continue
        mv "\$f" "\${f%.pdb}_${lineage}_${tool_tag}.pdb"
    done

    # Extract fixed regions from TRB into a tool-agnostic file, then discard the TRB.
    # Any upstream tool only needs to produce a PDB + a .fixed_regions file in this format.
    fixed_regions_file=""
    for f in *.trb; do
        [ -f "\$f" ] || continue
        base="\${f%.trb}_${lineage}_${tool_tag}"
        python ${helper_dir}/reformat_fixed_residues.py --input-file "\$f" > "\${base}.fixed_regions" 2>/dev/null \
            || touch "\${base}.fixed_regions"
        fixed_regions_file="\${base}.fixed_regions"
        rm -f "\$f"
    done
    # If no TRB was produced, create an empty fixed_regions alongside the PDB.
    if [ -z "\$fixed_regions_file" ]; then
        for f in *_${lineage}_${tool_tag}.pdb; do
            [ -f "\$f" ] || continue
            touch "\${f%.pdb}.fixed_regions"
            break
        done
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rfdiffusion: \$(python -c "import sys; print(sys.version.split()[0])" 2>/dev/null || echo "unknown")
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def tool_tag = task.ext.tool_name ?: 'rfdiffusion'
    def lineage = meta.lineage ?: "rfdiffusion_${(design_idx as Integer) + 1}"
    """
    touch ${prefix}_RFD_${design_idx}_${lineage}_${tool_tag}.pdb
    touch ${prefix}_RFD_${design_idx}_${lineage}_${tool_tag}.fixed_regions

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rfdiffusion: 1.0.0
        python: 3.9.0
    END_VERSIONS
    """
}
