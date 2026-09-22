#!/usr/bin/env bash
# Close the SSH master to the GPU login node. Re-open with: bash hpc/start.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if master_check; then
  ssh "${SSH_OPTS[@]}" -O exit "$SSH_TARGET" && echo "[ok] ssh master closed"
else
  echo "[--] no ssh master running"
fi