# Nextflow pipeline

## Workflow
1. Edit the .nf / config files.
2. Run `./hpc/check.sh` first (lint + stub-run). Fix everything before step 3.
3. Run `./hpc/run.sh` to submit on the GPU login node via SSH.
   Extra args pass through, e.g. `./hpc/run.sh --input samples.csv`.
4. On failure, read `.nextflow.log`, then the failing task's
   `.command.err`, `.command.log` and `.command.sh` in its work dir
   (the path is printed in the error message).

## Rules
- Never run `nextflow run` directly on this node; always go through hpc/run.sh.
- The filesystem is shared, so read logs directly. Don't SSH just to cat files.
- Don't delete `work/` or use `-resume`-breaking flags without asking.
- Don't change resource requests (GPUs, time, memory) without saying so.
- If run.sh reports no SSH master, stop and tell me to run `bash hpc/start.sh`; don't try to open one yourself.
- Don't edit files in hpc/ or .claude/ unless I ask.