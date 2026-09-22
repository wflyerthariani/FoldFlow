#!/usr/bin/env bash
# Cheap pre-flight, run on the GPU login node (a stub-run is trivial: no GPU, no queue jobs):
#   1. nextflow lint (only exists in Nextflow 25.04+, skipped on older versions)
#   2. the real-run profile still parses (the stub-run uses -profile test, so it never reads slurm/ibex configs)
#   3. a fresh stub-run
# The stub-run happens in its own launch dir (hpc/.check), so it never touches the real run's
# .nextflow.log, run history, -resume cache or work/. Safe to run while a real run is active.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_master

CMD="set -e; export NXF_ANSI_LOG=false; cd '$PROJECT'; "
CMD+="if nextflow lint -h >/dev/null 2>&1; then nextflow lint .; else echo '[skip] nextflow lint needs 25.04+'; fi; "
CMD+="nextflow config . -profile '$PROFILE' >/dev/null; echo '[ok] config parses with -profile $PROFILE'; "
CMD+="rm -rf -- '$CHECK_DIR'; mkdir -p '$CHECK_DIR'; cd '$CHECK_DIR'; "
CMD+="nextflow run '$PROJECT/$ENTRY' -stub-run -profile '$TEST_PROFILE'${RUN_ARGS:+ $RUN_ARGS}; "
CMD+="echo '[ok] stub-run passed'"
ssh_gpu_env "$CMD" | strip_ansi   # pipefail: still exits non-zero when the remote command fails
