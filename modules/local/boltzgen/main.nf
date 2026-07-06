process BOLTZGEN {
    tag "${meta.id}_${meta.design_idx}"
    label 'process_gpu'

    def config_path = params.boltzgen_config_path ?: "${projectDir}/configs"
    def config_name = params.boltzgen_config_name ?: 'Boltzgen.yaml'
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
    def model_dir = yaml_value('_model_dir', "${editables_dir}/weights/boltzgen/models")
    def num_designs = yaml_value('_num_designs', '1')

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'library://boltzgen/default/boltzgen_x86:latest'
        : 'boltzgen/boltzgen_x86:latest'}"
    containerOptions {
        if (workflow.containerEngine != 'singularity') {
            return ''
        }
        def binds = []
        if (model_dir) {
            binds << "--bind ${model_dir}:/models"
        }
        binds.join(' ')
    }

    input:
    tuple val(meta), val(design_idx), path(input_pdb)

    output:
    tuple val(meta), path("*_boltzgen.pdb"), emit: structures
    tuple val(meta), path("*_boltzgen.fixed_regions"), emit: fixed_regions
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def tool_tag = task.ext.tool_name ?: 'boltzgen'
    def lineage = meta.lineage ?: "boltzgen_${(design_idx as Integer) + 1}"

    """
    # Set cache directories to writable locations inside the container
    export HF_HOME=/models
    export XDG_CACHE_HOME=/tmp/.cache
    export TRITON_CACHE_DIR=/tmp/.triton
    export NUMBA_CACHE_DIR=/tmp/numba_cache
    export MPLCONFIGDIR=/tmp/matplotlib

    # Build runtime config: strip internal _-prefixed keys and inject staged input PDB path
    python3 - <<'PYEOF'
import yaml

with open('${config_path}/${config_name}') as f:
    cfg = yaml.safe_load(f)

for k in list(cfg.keys()):
    if k.startswith('_'):
        del cfg[k]

# Replace the sentinel path with the actual staged input PDB filename
for entity in cfg.get('entities', []):
    if 'file' in entity and entity['file'].get('path') == 'STAGED_INPUT_PDB':
        entity['file']['path'] = '${input_pdb.name}'

with open('boltzgen_run.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True)
PYEOF

    mkdir -p output

    boltzgen run boltzgen_run.yaml \\
        --output output \\
        --num_designs ${num_designs} \\
        ${args}

    # Remove staged input PDB symlink so it cannot be emitted as a process output
    rm -f "${input_pdb.name}" || true

    # Convert final ranked CIF outputs to PDB and apply pipeline naming convention.
    # Boltzgen writes final designs to output/final_ranked_designs/final_*/rank*.cif.
    # The glob excludes the before_refolding subdirectory by matching only one level deep.
    python3 - <<'PYEOF'
import gemmi, glob, os, sys

cif_files = sorted(glob.glob('output/final_ranked_designs/final_*/rank*.cif'))
prefix    = '${prefix}'
design_idx = '${design_idx}'
lineage   = '${lineage}'
tool_tag  = '${tool_tag}'

for idx, cif_path in enumerate(cif_files):
    out_name = f'{prefix}_BG{design_idx}_{idx}_{lineage}_{tool_tag}.pdb'
    st = gemmi.read_structure(cif_path)
    st.write_pdb(out_name)

if not cif_files:
    sys.exit('No CIF outputs found in output/final_ranked_designs/')
PYEOF

    # Create matching .fixed_regions files (boltzgen does not produce TRB files)
    for f in *_${tool_tag}.pdb; do
        [ -f "\$f" ] || continue
        touch "\${f%.pdb}.fixed_regions"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        boltzgen: \$(boltzgen --version 2>&1 | head -1 || echo "unknown")
        python: \$(python --version 2>&1 | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def tool_tag = task.ext.tool_name ?: 'boltzgen'
    def lineage = meta.lineage ?: "boltzgen_${(design_idx as Integer) + 1}"
    """
    touch ${prefix}_BG${design_idx}_0_${lineage}_${tool_tag}.pdb
    touch ${prefix}_BG${design_idx}_0_${lineage}_${tool_tag}.fixed_regions

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        boltzgen: 1.0.0
        python: 3.12.0
    END_VERSIONS
    """
}
