#!/usr/bin/env bash
# Submit the pipeline on the GPU login node, detached: it keeps running if this command, the ssh
# connection or Claude's shell goes away. Returns after RUN_SETTLE seconds (sooner if the run ends),
# so a run that fails immediately is reported right here; otherwise follow it with hpc/status.sh.
# Usage: ./hpc/run.sh [extra nextflow args]   e.g. ./hpc/run.sh --input samples.csv
# Always passes -resume. One run at a time; stop the current one with hpc/cancel.sh.
# Exit: 0 submitted (running, or already finished OK) | 1 refused, or failed straight away
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_master

run_state
case "$RUN_STATE" in
  running)
    echo "A run is already active. Follow it with ./hpc/status.sh, or stop it with ./hpc/cancel.sh." >&2
    exit 1 ;;
  lost)
    echo "[warn] the previous run left no exit code and no heartbeat; assuming it died. ./hpc/cancel.sh sweeps leftover SLURM jobs." >&2 ;;
esac

ARGS=""
if [ "$#" -gt 0 ]; then printf -v ARGS ' %q' "$@"; fi
ssh_gpu_env "'$REMOTE_RUN' launch${RUN_ARGS:+ $RUN_ARGS}$ARGS"

rc=0
"$HPC_DIR/status.sh" --wait "${RUN_SETTLE:-20}" || rc=$?
if [ "$rc" = 2 ]; then
  echo
  echo "[ok] submitted and running. Follow with: ./hpc/status.sh --wait 90   (exit 0 done, 1 failed, 2 still running)"
  rc=0
fi
[ "$rc" = 0 ] || rc=1
exit "$rc"
