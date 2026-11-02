#!/usr/bin/env bash
# FoldFlow test runner.
#
#   tests/run_tests.sh              # quick: helpers + config  (a few seconds, no GPU)
#   tests/run_tests.sh helpers      # unit tests for bin/ scripts only
#   tests/run_tests.sh config       # are containers, weights and databases reachable
#   tests/run_tests.sh config alphafold3     # one tool only
#   tests/run_tests.sh stub         # + whole-workflow stub run (~1 min, no GPU)
#   tests/run_tests.sh nftest       # nf-test module suites, stub tags only (~1 min)
#   tests/run_tests.sh nftest --tag alphafold3   # one module's suite
#   tests/run_tests.sh all          # everything above
#
# Nothing here needs a GPU, a model or a container image. The stub tier runs Nextflow,
# so run it where `nextflow` is available.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Stub-run parameters. These must match conf/test.config, since the output counts are
# derived from them.
DESIGNS=2
MPNN_SEQS=1
LIGANDMPNN_SEQS=2
INPUT_PDB="${INPUT_PDB:-$ROOT/6px6.pdb}"

rc=0
skipped=0
section() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
record()  { [ "$1" -eq 0 ] || rc=1; }

run_helpers() {
    section "helper scripts (bin/)"
    python3 -m unittest discover -s tests -p 'test_helpers.py' 2>&1 | tail -5
    record "${PIPESTATUS[0]}"
}

run_config() {
    section "tool setup (containers, weights, databases)"
    python3 tests/test_config.py "$@"
    record $?
}

run_stub() {
    section "whole-workflow stub run"
    if ! command -v nextflow >/dev/null 2>&1; then
        echo "  skipped: nextflow is not on PATH"
        skipped=1
        return
    fi
    if [ ! -f "$INPUT_PDB" ]; then
        echo "  skipped: no input structure at $INPUT_PDB (set INPUT_PDB=...)"
        skipped=1
        return
    fi

    # Run in a scratch launch dir so a real run's -resume cache, history and work/ are
    # never touched. Safe to run while a real run is in progress.
    local dir
    dir="$(mktemp -d "${TMPDIR:-/tmp}/foldflow-stub.XXXXXX")"
    trap 'rm -rf "$dir"' RETURN

    ( cd "$dir" && NXF_ANSI_LOG=false nextflow run "$ROOT/main.nf" \
        -profile test -stub-run --input_pdb "$INPUT_PDB" ) > "$dir/run.log" 2>&1
    local nf_rc=$?
    if [ $nf_rc -ne 0 ]; then
        echo "  stub run failed:"
        tail -25 "$dir/run.log" | sed 's/^/    /'
        rc=1
        return
    fi
    echo "  stub run completed"

    local results
    results="$(find "$dir" -maxdepth 3 -type d -name 'test_design' -print -quit)"
    if [ -z "$results" ]; then
        echo "  could not find published results under $dir"
        rc=1
        return
    fi
    python3 tests/test_stub.py "$results" \
        --designs "$DESIGNS" --mpnn-seqs "$MPNN_SEQS" --ligandmpnn-seqs "$LIGANDMPNN_SEQS"
    record $?
}

# nf-test may be on PATH, or inside a conda env that is not currently active.
find_nftest() {
    if command -v nf-test >/dev/null 2>&1; then
        command -v nf-test
        return 0
    fi
    for c in "$HOME"/.local/bin/nf-test "$HOME"/miniconda3/envs/*/bin/nf-test \
             "$HOME"/miniforge3/envs/*/bin/nf-test "$HOME"/anaconda3/envs/*/bin/nf-test; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

run_nftest() {
    section "nf-test module suites (stub tags)"
    local nft
    if ! nft="$(find_nftest)"; then
        cat <<'EOS'
  skipped: nf-test not found.

  Install it (user-space, no root):
      curl -fsSL https://code.askimed.com/install/nf-test | bash
      mkdir -p ~/.local/bin && mv nf-test nf-test.jar ~/.local/bin/
EOS
        skipped=1
        return
    fi
    echo "  using $nft"
    # nf-test needs nextflow and Java 17+ on PATH.
    if ! command -v nextflow >/dev/null 2>&1; then
        echo "  skipped: nextflow is not on PATH"
        skipped=1
        return
    fi
    # Default to the stub tag so this stays fast; callers can pass their own filters.
    if [ "$#" -eq 0 ]; then
        set -- --tag stub
    fi
    "$nft" test "$@"
    record $?
}

tier="${1:-quick}"
case "$tier" in
    quick)   run_helpers; run_config ;;
    helpers) run_helpers ;;
    config)  shift; run_config "$@" ;;
    stub)    run_stub ;;
    nftest)  shift; run_nftest "$@" ;;
    all)     run_helpers; run_config; run_stub; run_nftest ;;
    -h|--help)
        sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
        exit 0 ;;
    *)
        echo "unknown tier: $tier (choose quick, helpers, config, stub, nftest, all)" >&2
        exit 2 ;;
esac

printf '\n'
if [ "$rc" -eq 0 ]; then
    if [ "$skipped" -ne 0 ]; then
        printf '\033[33mall checks passed (some tiers skipped)\033[0m\n'
    else
        printf '\033[32mall checks passed\033[0m\n'
    fi
else
    printf '\033[31msome checks failed\033[0m\n'
fi
exit "$rc"
