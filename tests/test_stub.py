"""Validates the published output of a stub run: the whole workflow, no GPU, no containers.

A stub run executes every process with placeholder commands, so it exercises the parts that
break most quietly — channel wiring, the fan-out arithmetic, the lineage carried in `meta`,
output filenames and publish paths — without touching a model.

Run:   nextflow run main.nf -profile test -stub-run --input_pdb 6px6.pdb
       python3 tests/test_stub.py results_test/test_design

Counts default to the `test` profile; override if you ran with different parameters.
Exit:  0 all checks passed, 1 otherwise.
"""

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

BACKBONE_TOOLS = ["rfdiffusion", "boltzgen"]
SEQUENCE_TOOLS = ["proteinmpnn", "ligandmpnn"]
PREDICTORS = ["alphafold", "alphafold3"]

OK, FAIL, WARN = "PASS", "FAIL", "WARN"


class Report:
    def __init__(self):
        self.rows = []

    def add(self, status, what, detail=""):
        self.rows.append((status, what, detail))

    def failed(self):
        return any(s == FAIL for s, _, _ in self.rows)

    def print(self):
        width = max((len(w) for _, w, _ in self.rows), default=10)
        for status, what, detail in self.rows:
            mark = {OK: "  ok  ", FAIL: " FAIL ", WARN: " warn "}[status]
            print(f"[{mark}] {what.ljust(width)}  {detail}")
        counts = Counter(s for s, _, _ in self.rows)
        print(f"\n{counts[OK]} passed, {counts[FAIL]} failed, {counts[WARN]} warnings")


def check_count(rep, label, actual, expected):
    rep.add(OK if actual == expected else FAIL, label,
            f"{actual}" if actual == expected else f"{actual}, expected {expected}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("results", type=Path,
                    help="published results dir, e.g. results_test/test_design")
    ap.add_argument("--designs", type=int, default=2, help="rfdiff_num_designs (default 2)")
    ap.add_argument("--mpnn-seqs", type=int, default=1, help="mpnn_num_sequences (default 1)")
    ap.add_argument("--ligandmpnn-seqs", type=int, default=2,
                    help="ligandmpnn_num_sequences (default 2)")
    args = ap.parse_args(argv)

    rep = Report()
    root = args.results
    if not root.is_dir():
        print(f"no such results directory: {root}", file=sys.stderr)
        print("run the stub first:  nextflow run main.nf -profile test -stub-run "
              "--input_pdb 6px6.pdb", file=sys.stderr)
        return 2

    # The fan-out the workflow is supposed to produce, derived from the run parameters.
    backbones = args.designs * len(BACKBONE_TOOLS)
    sequences = backbones * (args.mpnn_seqs + args.ligandmpnn_seqs)
    predictions = sequences * len(PREDICTORS)

    # --- every stage published something -----------------------------------------
    for stage in BACKBONE_TOOLS + SEQUENCE_TOOLS + PREDICTORS:
        rep.add(OK if (root / stage).is_dir() else FAIL, f"{stage}/ published",
                "" if (root / stage).is_dir() else "directory missing")
    if rep.failed():
        rep.print()
        print("\nA stage directory is missing: the workflow did not reach that process.")
        return 1

    # --- stage 1: one backbone per design index, per tool -------------------------
    for tool in BACKBONE_TOOLS:
        pdbs = list((root / tool).glob(f"*_{tool}.pdb"))
        check_count(rep, f"{tool} backbones", len(pdbs), args.designs)
        # The .fixed_regions sidecar is deliberately not checked here: it travels to the
        # sequence stage through the channel but is not published, so it never appears in
        # results/. The sequence-stage counts below fail if a sidecar went missing.

    # --- stage 2: sequences per backbone, per tool --------------------------------
    per_tool = {"proteinmpnn": args.mpnn_seqs, "ligandmpnn": args.ligandmpnn_seqs}
    for tool in SEQUENCE_TOOLS:
        fas = list((root / tool).glob(f"*_{tool}.fa"))
        check_count(rep, f"{tool} sequences", len(fas), backbones * per_tool[tool])
        # Filenames must encode the backbone lineage, or downstream outputs lose their trail.
        malformed = [f.name for f in fas
                     if not re.match(rf"^({'|'.join(BACKBONE_TOOLS)})_\d+_mpnn_\d+_{tool}\.fa$",
                                     f.name)]
        rep.add(OK if not malformed else FAIL, f"{tool} filename lineage",
                "well formed" if not malformed else f"malformed: {malformed[:3]}")

    # --- stage 3: one prediction per sequence, per predictor ----------------------
    af3_models = list((root / "alphafold3").glob("model_*_alphafold3.pdb"))
    check_count(rep, "alphafold3 models", len(af3_models), sequences)

    # Each AlphaFold 3 model must come with its scores; a missing one means the
    # collection step in the module silently dropped a file.
    for suffix, label in ((".cif", "mmCIF"), (".csv", "ranking CSV")):
        found = list((root / "alphafold3").glob(f"*_alphafold3{suffix}"))
        check_count(rep, f"alphafold3 {label}", len(found), sequences)
    confidences = list((root / "alphafold3").glob("confidences_*_alphafold3.json"))
    summaries = list((root / "alphafold3").glob("summary_confidences_*_alphafold3.json"))
    check_count(rep, "alphafold3 confidences", len(confidences), sequences)
    check_count(rep, "alphafold3 summaries", len(summaries), sequences)

    # AlphaFold 3 filenames carry the sequence-design tool, so one model per sequence
    # survives publishing. This guards the naming that keeps the two MPNN tools apart.
    af3_names = {f.name for f in af3_models}
    rep.add(OK if len(af3_names) == sequences else FAIL, "alphafold3 no collisions",
            f"{len(af3_names)} unique names for {sequences} sequences")
    for tool in SEQUENCE_TOOLS:
        got = sum(1 for n in af3_names if f"_{tool}_" in n)
        check_count(rep, f"alphafold3 from {tool}", got, backbones * per_tool[tool])

    # AlphaFold 2 names omit the sequence-design tool, so sequences that differ only by
    # which MPNN produced them overwrite each other. Reported, not failed - see README.
    af2_models = list((root / "alphafold").glob("*_alphafold.pdb"))
    if len(af2_models) < sequences:
        rep.add(WARN, "alphafold collisions",
                f"{len(af2_models)} files for {sequences} sequences "
                f"({sequences - len(af2_models)} overwritten - known issue)")
    else:
        rep.add(OK, "alphafold models", f"{len(af2_models)}")

    # --- totals -------------------------------------------------------------------
    rep.add(OK, "expected fan-out",
            f"{args.designs} designs -> {backbones} backbones -> {sequences} sequences "
            f"-> {predictions} predictions")

    rep.print()
    return 1 if rep.failed() else 0


if __name__ == "__main__":
    sys.exit(main())
