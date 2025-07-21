process RFdiffusion {
    tag "rf_array_${task.index}"
    
    input:
        tuple val(contig_str), val(output_prefix), val(design_startnum), path(input_pdb)
    output:
        tuple val(design_startnum), val(output_prefix), path("RFDresults_${output_prefix}_*.pdb"), path("RFDresults_${output_prefix}_*.trb")
    script:
        """
        singularity exec --nv \
            --bind "${params.rfdiff_editables_dir}":"${params.rfdiff_editables_dir}" \
            --env SCHEDULE_DIR="${params.rfdiff_editables_dir}/schedules" \
            --env MODEL_DIR="${params.rfdiff_editables_dir}/models" \
            "${params.rfdiff_sif_path}" \
            /opt/miniconda/envs/SE3nv/bin/python /opt/RFdiffusion/scripts/run_inference.py \
                "$contig_str" \
                inference.output_prefix="\${PWD}/RFDresults_$output_prefix" \
                inference.num_designs=1 \
                inference.design_startnum="$design_startnum" 
        """
}