#!/usr/bin/env bash
# One call before using Claude Code in VSCode. Safe to re-run every session.
# Run it yourself in a terminal (not via Claude): it may prompt for password/2FA.
#   bash hpc/start.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# 1. Scripts executable
chmod +x "$HPC_DIR"/*.sh

# 2. SSH master connection to the GPU login node
if master_check; then
  echo "[ok] ssh master already running"
else
  echo "[..] opening ssh master to $SSH_TARGET (enter password/2FA if asked)"
  if ssh "${SSH_OPTS[@]}" -fN "$SSH_TARGET" && master_check; then
    echo "[ok] ssh master running (lasts 4h idle)"
  else
    echo "[!!] could not open ssh master" >&2; exit 1
  fi
fi

# 3. Cluster environment (hpc/remote-env.sh) works on the GPU login node
if OUT="$(ssh_gpu_env 'command -v singularity >/dev/null && nextflow -version 2>&1 | grep -m1 -i "version"' 2>&1)"; then
  echo "[ok] remote env loaded (singularity + nextflow): $(echo "$OUT" | tail -1 | xargs)"
else
  echo "[!!] remote env failed on $GPU_HOST; check hpc/remote-env.sh. Output:" >&2
  echo "$OUT" | tail -8 >&2
fi

echo
echo "Ready. Start Claude from the repo root:  claude"