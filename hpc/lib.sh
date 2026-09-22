# Sourced by the other scripts. SSH options live here, so ~/.ssh/config is never touched.
HPC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HPC_DIR/.." && pwd)"
# shellcheck source=config.env
source "$HPC_DIR/config.env"

SSH_TARGET="$GPU_USER@$GPU_HOST"
SSH_OPTS=(
  -o ControlMaster=auto
  -o "ControlPath=/tmp/cm-%C"
  -o ControlPersist=4h
  -o ServerAliveInterval=60
  -o ForwardX11=no
)

STATE_DIR="$HPC_DIR/.state"   # bookkeeping for the detached run; shared filesystem, so any node can read it
CHECK_DIR="$HPC_DIR/.check"   # throwaway launch dir for check.sh: keeps stub-runs out of the real run's history/cache/log
REMOTE_RUN="$HPC_DIR/remote-run.sh"
HEARTBEAT_STALE=180           # seconds of silence after which a run with no exit code counts as lost

ssh_gpu()      { ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$SSH_TARGET" "$@"; }
master_check() { ssh "${SSH_OPTS[@]}" -O check "$SSH_TARGET" 2>/dev/null; }

# Fail fast instead of hanging on a password/2FA prompt.
require_master() {
  master_check && return 0
  echo "No open SSH master to $SSH_TARGET. Run bash hpc/start.sh in your own terminal first." >&2
  exit 1
}

# Run a command on the GPU login node in a login shell with hpc/remote-env.sh applied.
ssh_gpu_env() {
  local cmd="source '$HPC_DIR/remote-env.sh' && $*"
  ssh_gpu "bash -lc $(printf '%q' "$cmd")"
}

# State of the detached run, from the files in $STATE_DIR only (no SSH). Sets:
#   RUN_STATE  none | running | ok | failed | lost   (lost = no exit code and no recent heartbeat)
#   RUN_RC     exit code of the finished run
run_state() {
  RUN_STATE=none RUN_RC=""
  [ -f "$STATE_DIR/start" ] || return 0
  if [ -f "$STATE_DIR/exit" ]; then
    RUN_RC="$(<"$STATE_DIR/exit")"
    if [ "$RUN_RC" = 0 ]; then RUN_STATE=ok; else RUN_STATE=failed; fi
  elif [ $(( $(date +%s) - $(stat -c %Y "$STATE_DIR/heartbeat" 2>/dev/null || echo 0) )) -lt "$HEARTBEAT_STALE" ]; then
    RUN_STATE=running
  else
    RUN_STATE=lost
  fi
}

# The nf-schema plugin colours its summary regardless of NXF_ANSI_LOG; strip that from what Claude reads.
strip_ansi() { sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'; }

fmt_dur() {
  local s=$1
  if   [ "$s" -ge 3600 ]; then printf '%dh %02dm %02ds' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
  elif [ "$s" -ge 60 ];   then printf '%dm %02ds' $((s / 60)) $((s % 60))
  else printf '%ds' "$s"; fi
}
