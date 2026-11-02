/*
 * Reads the per-module output counts out of configs/<Tool>.yaml.
 *
 * Each module YAML carries a `_num_outputs` key saying how much that tool contributes:
 * backbones for RFdiffusion and BoltzGen, sequences per backbone for the MPNN tools,
 * predictions per sequence for the AlphaFold tools. 0 switches the tool off.
 *
 * The count is resolved here rather than inside the process body because a `when:`
 * block cannot see variables declared at process scope - it silently evaluates them
 * as null, which disables every task without raising an error. Gating therefore
 * happens in the workflow, where ordinary Groovy scoping applies.
 */
class ToolConfig {

    /**
     * Resolve one tool's output count.
     *
     * @param dir       directory holding the module YAML (its *_config_path param)
     * @param name      YAML filename (its *_config_name param)
     * @param override  matching params.* value, or null to use the YAML
     * @param fallback  used when the YAML is absent or has no _num_outputs key
     */
    static int numOutputs(Object dir, Object name, Object override, int fallback) {
        if (override != null) {
            return (override as Integer)
        }
        if (dir == null || name == null) {
            return fallback
        }
        def file = new File("${dir}/${name}")
        if (!file.exists()) {
            return fallback
        }
        def matcher = (file.text =~ /(?m)^_num_outputs\s*:\s*(\d+)\s*$/)
        return matcher.find() ? (matcher.group(1) as Integer) : fallback
    }
}
