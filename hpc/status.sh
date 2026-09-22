#!/usr/bin/env bash
# Report on the run started by hpc/run.sh. Reads hpc/.state on the shared filesystem, so it works without
# SSH (the SLURM queue view is added only when the ssh master is up).
# Usage: ./hpc/status.sh [--wait SECS]   with --wait, block up to SECS while the run is still going
#        (keep SECS under the caller's own timeout, minus ~10s of ssh overhead: 90 for a 2 min shell limit)
# Exit:  0 finished OK | 1 failed | 2 still running | 3 no run recorded, or run lost
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WAIT=0
case "${1:-}" in
  "") ;;
  --wait) WAIT="${2:-}" ;;
  *) WAIT=x ;;
esac
[[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "usage: hpc/status.sh [--wait SECS]" >&2; exit 64; }

run_state
until_ts=$(( $(date +%s) + WAIT ))
while [ "$RUN_STATE" = running ] && [ "$(date +%s)" -lt "$until_ts" ]; do sleep 3; run_state; done

OUT="$STATE_DIR/run.out"
now=$(date +%s)
read_state() { cat "$STATE_DIR/$1" 2>/dev/null || echo "$2"; }
started=$(read_state start "$now"); finished=$(read_state end "$now"); host=$(read_state host '?')
tail_out() { echo "--- last $1 lines of hpc/.state/run.out"; tail -n "$1" "$OUT" 2>/dev/null | strip_ansi; }

case "$RUN_STATE" in
  none)
    echo "[--] no run recorded; start one with ./hpc/run.sh"
    exit 3 ;;
  running)
    age=$(( now - $(stat -c %Y "$STATE_DIR/heartbeat") ))
    echo "[..] RUNNING on $host, $(fmt_dur $((now - started))) elapsed (heartbeat ${age}s ago)"
    echo "     cmd: $(read_state cmd '?')"
    tail_out 8
    if [ $((now - started)) -ge 60 ] && master_check; then
      jobs="$(ssh_gpu_env "'$REMOTE_RUN' queue" 2>/dev/null)" || jobs=""
      if [ -n "$jobs" ]; then echo "--- SLURM jobs under work/ (id state reason elapsed name)"; echo "$jobs"; fi
    fi
    exit 2 ;;
  ok)
    echo "[ok] FINISHED OK on $host after $(fmt_dur $((finished - started)))"
    tail_out 8
    exit 0 ;;
  failed)
    echo "[!!] FAILED (exit $RUN_RC) on $host after $(fmt_dur $((finished - started)))"
    tail_out 60
    dirs="$(awk '/^Work dir:/ { getline; sub(/^[ \t]+/, ""); print }' "$OUT" 2>/dev/null | awk '!seen[$0]++' | head -5)"
    if [ -n "$dirs" ]; then
      echo "--- failed task dirs (read .command.err, .command.log and .command.sh there)"
      echo "$dirs"
    fi
    echo "--- Nextflow's own log: .nextflow.log"
    exit 1 ;;
  lost)
    echo "[!!] LOST: no exit code and no heartbeat for $(fmt_dur $((now - $(stat -c %Y "$STATE_DIR/heartbeat" 2>/dev/null || echo "$started")))) (started on $host)"
    echo "     The launcher died (node reboot? kill -9?). See .nextflow.log and hpc/.state/run.out; ./hpc/cancel.sh sweeps leftover SLURM jobs."
    tail_out 15
    exit 3 ;;
esac
