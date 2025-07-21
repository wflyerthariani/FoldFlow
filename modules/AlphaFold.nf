process AlphaFold {
    tag "alphafold_${task.index}"

    input:
        path fasta
    output:
        path("AlphaFoldresults/${fasta.baseName}/*.pdb")
    script:
        """
        OUTPUT_DIR="AlphaFoldresults/"
        DATA_DIR="${params.alphafold_data_dir}"

        singularity exec --nv --bind ${params.alphafold_data_dir}:${params.alphafold_data_dir} "${params.alphafold_sif_path}" /opt/run_alphafold.sh -f ${fasta} -d ${params.alphafold_data_dir} -o \$OUTPUT_DIR -t 2020-05-14
        """
}