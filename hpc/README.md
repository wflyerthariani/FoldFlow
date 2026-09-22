# Claude Code + Nextflow on a two-login-node HPC

Self-contained: no changes to ~/.ssh/config. SSH options live in hpc/lib.sh.

    .claude/CLAUDE.md       instructions Claude Code reads
    .claude/settings.json   command allowlist (see "Allowlist" below)
    hpc/config.env          host, user, profiles, entry script (the only file to edit)
    hpc/lib.sh              shared SSH options, paths, run-state helpers
    hpc/start.sh            the one call: setup + ssh master + sanity checks (you run this)
    hpc/stop.sh             close the ssh master (a detached run keeps going)
    hpc/check.sh            lint + config parse + stub-run on the GPU login node
    hpc/run.sh              submit the pipeline on the GPU login node, detached
    hpc/status.sh           report on the run; --wait SECS blocks while it is going
    hpc/cancel.sh           stop the run and its SLURM jobs
    hpc/remote-run.sh       the part of run/status/cancel that executes on the login node

## Use
1. Check hpc/config.env once — GPU_USER auto-detects, but confirm INPUT_PDB points at your structure.
2. `bash hpc/start.sh`   # every session; handles 2FA, chmod, checks
3. `claude`              # from the repo root; /memory confirms .claude/CLAUDE.md loaded

## The iteration loop
    ./hpc/check.sh                  # fix everything it reports, then:
    ./hpc/run.sh [nextflow args]    # detaches, always -resume; reports a run that dies within RUN_SETTLE seconds
    ./hpc/status.sh --wait 90       # repeat while it exits 2
    #   on failure: status prints the error and the failing task dirs (.command.err/.log/.sh); fix; loop
    ./hpc/cancel.sh                 # a run that is going wrong; then fix and run.sh again (resumes)

`status.sh` exit codes: 0 finished OK, 1 failed, 2 still running, 3 no run recorded or run lost.
`run.sh` exits 0 if the run was submitted (or already finished OK), 1 if it was refused or failed straight away.
Keep `--wait` under the caller's own timeout (Claude's shell tool: 2 min by default, 10 min max).

## How it works
- **Detached.** `run.sh` starts nextflow in its own session on the login node (setsid), output to
  `hpc/.state/run.out`. It survives a dropped ssh connection, `stop.sh`, or the tool call timing out.
- **State is files** in `hpc/.state/` on the shared filesystem: `status.sh` needs no SSH. The wrapper
  touches `heartbeat` every ~30s and writes `exit` when nextflow ends. No exit file and no heartbeat for
  3 min = "lost" (launcher killed / node down). This is by design not PID-based: `glogin` round-robins
  between login nodes (login510-22, login510-27, ...), so the next ssh may land on a different one.
- **One run at a time.** `run.sh` refuses while one is active. `run.out.prev` keeps the run before.
- **check.sh is isolated.** The stub-run uses its own launch dir `hpc/.check` (wiped each time), so it never
  touches the real run's `.nextflow.log`, history, `-resume` cache or `work/`, and it may run while a real
  run is active. (`-resume` with no session id resumes the *last run in history*, so a stub-run sharing the
  launch dir would make the next real run resume the stub's empty cache.)
- **cancel.sh** sends SIGTERM to the run's process group (Nextflow cancels its SLURM jobs), waits up to 90s,
  then scancels any job of yours whose work dir is under `work/`. `--force` = SIGKILL. If the run is on a
  different login node than the current ssh master it says so instead of guessing.

## Caveats
- Editing `bin/*` or `configs/*` while a run is going: tasks that have not started yet read the edited
  files. `.nf` and `conf/` edits are safe (Nextflow has already parsed them).
- The ssh master lasts 4h idle. If it lapses, run `bash hpc/start.sh` again; a detached run is unaffected.

## Allowlist
`.claude/settings.json` lets Claude run these without prompting. `status.sh` is read-only; `cancel.sh`
kills jobs, so you may prefer to keep prompting for it.

    "Bash(./hpc/check.sh:*)", "Bash(./hpc/run.sh:*)", "Bash(./hpc/status.sh:*)"

## Porting to another user or repo
Nothing in `.claude/` or `hpc/` names a person. Copy both dirs in; `hpc/config.env` is the one file
that might need a look:
- `GPU_USER` auto-detects (`$(id -un)`) — only hardcode it if your local account differs from your
  IBEX one.
- `INPUT_PDB` defaults to `$PROJECT/6px6.pdb` (`PROJECT` = this repo's checkout path, set by
  `hpc/lib.sh`) — point it at your own structure, or leave it if you keep the same filename.
- `GPU_HOST`, `ENTRY`, `PROFILE`, `TEST_PROFILE` are shared defaults; change only if your setup differs.

Then `bash hpc/start.sh`.
