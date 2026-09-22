#!/usr/bin/env bash
# Runs ON the GPU login node, reached through ssh_gpu_env by run.sh / status.sh / cancel.sh. Not for direct use.
#   launch [nextflow args]   start the pipeline detached (own session, output to a file) and return at once
#   child  [nextflow args]   internal: the detached wrapper. Runs nextflow, beats a heartbeat, records the exit code
#   queue                    list this project's SLURM jobs
#   cancel [--force]         SIGTERM (or SIGKILL) the run's process group, then scancel leftover jobs
# Bookkeeping in hpc/.state: start host pid cmd heartbeat exit end run.out (run.out.prev = the run before)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NF_CMD=(nextflow run "$ENTRY" -profile "$PROFILE" -resume)

launch() {
  mkdir -p "$STATE_DIR"
  [ ! -f "$STATE_DIR/run.out" ] || mv -f "$STATE_DIR/run.out" "$STATE_DIR/run.out.prev"
  rm -f "$STATE_DIR"/{pid,exit,end}
  hostname > "$STATE_DIR/host"
  printf '%q ' "${NF_CMD[@]}" "$@" > "$STATE_DIR/cmd"
  touch "$STATE_DIR/heartbeat"
  date +%s > "$STATE_DIR/start"   # last: its presence means "a run exists"
  cd "$PROJECT" || return 1
  # setsid: own session, so neither ssh going away nor cancel's group signal can reach anything else.
  setsid bash "$REMOTE_RUN" child "$@" </dev/null >"$STATE_DIR/run.out" 2>&1 &
  for _ in $(seq 20); do [ -s "$STATE_DIR/pid" ] && break; sleep 0.25; done
  if [ ! -s "$STATE_DIR/pid" ]; then
    rm -f "$STATE_DIR/start"
    echo "[!!] the detached run did not start (see $STATE_DIR/run.out)" >&2
    return 1
  fi
  echo "[ok] launched on $(hostname), pid $(<"$STATE_DIR/pid")"
}

child() {
  echo $$ > "$STATE_DIR/pid"
  export NXF_ANSI_LOG=false
  "${NF_CMD[@]}" "$@" &
  local nf=$! n=0 rc
  trap : TERM INT   # cancel signals the whole process group; only nextflow should act on it, this wrapper must outlive it
  while kill -0 "$nf" 2>/dev/null; do
    (( n++ % 15 )) || touch "$STATE_DIR/heartbeat"   # every ~30s
    sleep 2
  done
  wait "$nf"; rc=$?
  echo "$rc" > "$STATE_DIR/exit.tmp" && mv -f "$STATE_DIR/exit.tmp" "$STATE_DIR/exit"
  date +%s > "$STATE_DIR/end"
}

# This pipeline's SLURM tasks: those whose work dir is under $PROJECT/work.  id|state|reason|elapsed|name
# Fails if squeue gives no answer within $1 seconds, so "no jobs" and "no answer" stay distinguishable.
project_jobs() {
  local raw
  raw="$(timeout "$1" squeue -h -u "$(id -un)" -o '%i|%T|%r|%M|%j|%Z' 2>/dev/null)" || return 1
  awk -F'|' -v p="$PROJECT/work/" 'index($6, p) == 1 { print $1 "|" $2 "|" $3 "|" $4 "|" $5 }' <<<"$raw"
}

queue() { project_jobs 15 | awk -F'|' '{ printf "    %-10s %-10s %-16s %9s  %s\n", $1, $2, $3, $4, $5 }'; }

sweep() {
  local jobs ids
  if ! jobs="$(project_jobs 30)"; then
    echo "[!!] squeue did not answer; check for leftover jobs yourself: squeue -u \$USER" >&2
    return 1
  fi
  ids="$(cut -d'|' -f1 <<<"$jobs" | tr '\n' ' ')"
  if [ -n "${ids// /}" ]; then
    echo "[ok] scancel $ids"; scancel $ids
  else
    echo "[ok] no SLURM jobs left under $PROJECT/work"
  fi
}

cancel() {
  local sig=TERM pid host
  [ "${1:-}" != --force ] || sig=KILL
  if [ -f "$STATE_DIR/start" ] && [ ! -f "$STATE_DIR/exit" ] && [ -s "$STATE_DIR/pid" ]; then
    pid="$(<"$STATE_DIR/pid")"; host="$(<"$STATE_DIR/host")"
    if [ "$host" != "$(hostname)" ]; then
      echo "[!!] the run is on $host but this ssh master is on $(hostname). Log in to $host and run: kill -$sig -- -$pid" >&2
      return 1
    fi
    if ps -o args= -p "$pid" 2>/dev/null | grep -q 'remote-run.sh child'; then
      kill "-$sig" -- "-$pid"
      echo "[ok] sent SIG$sig to the run (process group $pid)"
      for _ in $(seq 90); do [ -f "$STATE_DIR/exit" ] && break; sleep 1; done
      if [ "$sig" = KILL ]; then   # the wrapper died with it, so record the outcome for it
        echo 137 > "$STATE_DIR/exit"; date +%s > "$STATE_DIR/end"
      elif [ ! -f "$STATE_DIR/exit" ]; then
        echo "[!!] still shutting down after 90s; if it does not stop, re-run: ./hpc/cancel.sh --force" >&2
      fi
    else
      echo "[--] no live run process (pid $pid on $host)"
    fi
  else
    echo "[--] no active run to stop"
  fi
  sweep
}

case "${1:-}" in
  launch) shift; launch "$@" ;;
  child)  shift; child "$@" ;;
  queue)  queue ;;
  cancel) shift; cancel "$@" ;;
  *) echo "usage: remote-run.sh launch|child|queue|cancel" >&2; exit 64 ;;
esac
