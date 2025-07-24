process AlphaFold {
    tag "alphafold_${task.index}"
    conda 'envs/helper-env.yml'
    input:
        path fasta
    output:
        path("AlphaFoldresults/${fasta.baseName}/*.pdb")
    script:
        """
        OUTPUT_DIR="AlphaFoldresults/"
        DATA_DIR="${params.alphafold_data_dir}"

        get_args=\$(python ${projectDir}/helper/yaml_to_args.py "${params.config_dir}/${params.alphafold_config_name}")

        singularity exec --nv --bind ${params.alphafold_data_dir}:${params.alphafold_data_dir} "${params.alphafold_sif_path}" /opt/run_alphafold.sh -f ${fasta} -d ${params.alphafold_data_dir} -o AlphaFoldresults/ \${get_args}
        """
}