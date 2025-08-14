process RFdiffusion {
    tag "rfdiffusion_${task.index}"
    
    input:
        tuple val(output_prefix), val(design_startnum)
    output:
        tuple path("RFDresults_*.pdb"), path("RFDresults_*.trb")
    script:
        """
        singularity exec --nv \
            --bind "${params.rfdiff_editables_dir}":"${params.rfdiff_editables_dir}" \
            --env SCHEDULE_DIR="${params.rfdiff_editables_dir}/schedules" \
            --env MODEL_DIR="${params.rfdiff_editables_dir}/models" \
            "${params.rfdiff_sif_path}" \
            /opt/miniconda/envs/SE3nv/bin/python /opt/RFdiffusion/scripts/run_inference.py \
                --config-path ${params.config_dir} --config-name ${params.rfdiff_config_name} \
                +inference.output_prefix="\${PWD}/RFDresults" \
                +inference.num_designs=1 \
                +inference.design_startnum="$design_startnum" 
        """
}