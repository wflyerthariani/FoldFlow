#!/usr/bin/env bash
# Stop the run started by hpc/run.sh: SIGTERM to its process group (Nextflow then cancels its own SLURM
# jobs), wait up to 90s, then scancel any SLURM job under this project's work/ that outlived it.
# --force sends SIGKILL instead; only for a plain cancel that hangs.
# Usage: ./hpc/cancel.sh [--force]
# Exit: 0 done | 1 could not stop it, or could not check for leftover jobs
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "$#" -gt 1 ] || { [ "$#" = 1 ] && [ "$1" != --force ]; }; then echo "usage: hpc/cancel.sh [--force]" >&2; exit 64; fi
require_master

rc=0
ssh_gpu_env "'$REMOTE_RUN' cancel${1:+ $1}" || rc=$?
echo
"$HPC_DIR/status.sh" || true
exit "$rc"
