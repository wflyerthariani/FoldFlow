"""Checks that each tool's containers, weights and databases are actually reachable.

This is the quick "is my installation wired up" test. It runs no tool and needs no GPU:
it resolves the same YAML keys each Nextflow module resolves, using the same lookup rule,
and reports whether every path the module will bind-mount exists and is readable.

Run:   python3 tests/test_config.py            # every tool
       python3 tests/test_config.py alphafold3 # one tool
Exit:  0 all required checks passed, 1 otherwise.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIGS = ROOT / "configs"

OK, FAIL, SKIP, WARN = "PASS", "FAIL", "SKIP", "WARN"


def yaml_value(text, key, default=None):
    """Mirror of the `yaml_value` closure used in every module's main.nf.

    The modules read their YAML with a line-oriented regex rather than a YAML parser,
    so this test must resolve values the same way or it would validate the wrong thing.
    """
    m = re.search(rf"(?m)^{re.escape(key)}\s*:\s*(.+?)\s*$", text)
    if not m:
        return default
    return m.group(1).strip("'\"")


def module_container(module):
    """The container image a module declares, read out of its main.nf."""
    nf = ROOT / "modules" / "local" / module / "main.nf"
    if not nf.exists():
        return None
    m = re.search(r"'((?:docker|library)://[^']+)'", nf.read_text())
    return m.group(1) if m else None


class Report:
    def __init__(self):
        self.rows = []

    def add(self, tool, status, what, detail=""):
        self.rows.append((tool, status, what, detail))

    def failed(self):
        return any(s == FAIL for _, s, _, _ in self.rows)

    def print(self):
        width = max((len(w) for _, _, w, _ in self.rows), default=10)
        current = None
        for tool, status, what, detail in self.rows:
            if tool != current:
                print(f"\n{tool}")
                current = tool
            mark = {OK: "  ok  ", FAIL: " FAIL ", SKIP: " skip ", WARN: " warn "}[status]
            print(f"  [{mark}] {what.ljust(width)}  {detail}")
        counts = {s: sum(1 for _, st, _, _ in self.rows if st == s) for s in (OK, FAIL, SKIP, WARN)}
        print(
            f"\n{counts[OK]} passed, {counts[FAIL]} failed, "
            f"{counts[WARN]} warnings, {counts[SKIP]} skipped"
        )


def check_path(rep, tool, label, value, kind="dir", required=True, contains=None):
    """Verify one configured host path exists, is the right kind, and is readable."""
    if not value:
        rep.add(tool, FAIL if required else SKIP, label,
                "not set" if required else "not set (optional)")
        return
    p = Path(value)
    if not p.exists():
        rep.add(tool, FAIL if required else WARN, label, f"missing: {value}")
        return
    if kind == "dir" and not p.is_dir():
        rep.add(tool, FAIL, label, f"not a directory: {value}")
        return
    if kind == "file" and not p.is_file():
        rep.add(tool, FAIL, label, f"not a file: {value}")
        return
    if not os.access(p, os.R_OK):
        rep.add(tool, FAIL, label, f"not readable: {value}")
        return
    if contains:
        missing = [c for c in contains if not (p / c).exists()]
        if missing:
            rep.add(tool, FAIL, label, f"{value} is missing {', '.join(missing)}")
            return
    size = ""
    if kind == "file":
        size = f"({p.stat().st_size / 1e9:.1f} GB)" if p.stat().st_size > 1e8 else ""
    rep.add(tool, OK, label, f"{value} {size}".strip())


def load(rep, tool, filename):
    """Load a module YAML, reporting a hard failure if it is absent."""
    path = CONFIGS / filename
    if not path.exists():
        rep.add(tool, FAIL, "config file", f"missing: configs/{filename}")
        return None
    rep.add(rep_tool := tool, OK, "config file", f"configs/{filename}")
    return path.read_text()


def check_container(rep, tool, module):
    """Report the image a module will use. Public images are pulled on first run."""
    image = module_container(module)
    if image:
        rep.add(tool, OK, "container", image)
    else:
        rep.add(tool, WARN, "container", "no image literal found in main.nf")


def check_rfdiffusion(rep):
    tool = "RFDIFFUSION"
    text = load(rep, tool, "RFdiffusion.yaml")
    if text is None:
        return
    check_container(rep, tool, "rfdiffusion")
    editables = yaml_value(text, "_editables_dir", str(ROOT))
    check_path(rep, tool, "_schedule_dir",
               yaml_value(text, "_schedule_dir", f"{editables}/schedules"))
    check_path(rep, tool, "_model_dir",
               yaml_value(text, "_model_dir", f"{editables}/models"))


def check_boltzgen(rep):
    tool = "BOLTZGEN"
    text = load(rep, tool, "Boltzgen.yaml")
    if text is None:
        return
    check_container(rep, tool, "boltzgen")
    editables = yaml_value(text, "_editables_dir", str(ROOT))
    check_path(rep, tool, "_model_dir",
               yaml_value(text, "_model_dir", f"{editables}/weights/boltzgen/models"))


def check_proteinmpnn(rep):
    tool = "PROTEINMPNN"
    text = load(rep, tool, "MPNN.yaml")
    if text is None:
        return
    check_container(rep, tool, "proteinmpnn")
    weights = yaml_value(text, "path_to_model_weights", "")
    if weights:
        check_path(rep, tool, "path_to_model_weights", weights)
    else:
        rep.add(tool, SKIP, "path_to_model_weights", "empty - using container weights")


def check_ligandmpnn(rep):
    tool = "LIGANDMPNN"
    text = load(rep, tool, "LigandMPNN.yaml")
    if text is None:
        return
    check_container(rep, tool, "ligandmpnn")
    weights = yaml_value(text, "_model_weights_path", "")
    if weights:
        check_path(rep, tool, "_model_weights_path", weights)
    else:
        rep.add(tool, SKIP, "_model_weights_path", "unset - using container weights")
    ckpt = yaml_value(text, "checkpoint_ligand_mpnn", "")
    if ckpt.startswith("/app/"):
        rep.add(tool, SKIP, "checkpoint_ligand_mpnn", f"{ckpt} (inside container)")
    elif ckpt:
        check_path(rep, tool, "checkpoint_ligand_mpnn", ckpt, kind="file")


def check_alphafold(rep):
    tool = "ALPHAFOLD"
    text = load(rep, tool, "AlphaFold.yaml")
    if text is None:
        return
    check_container(rep, tool, "alphafold")
    check_path(rep, tool, "_data_dir", yaml_value(text, "_data_dir"),
               contains=["uniref90", "mgnify", "pdb_mmcif"])
    cuda = yaml_value(text, "_cuda_lib_dir", "")
    if cuda:
        check_path(rep, tool, "_cuda_lib_dir", cuda, required=False)
    else:
        rep.add(tool, SKIP, "_cuda_lib_dir", "unset")
    platform = yaml_value(text, "_jax_platform", "cuda")
    rep.add(tool, OK if platform in ("cuda", "cpu") else FAIL, "_jax_platform", platform)


def check_alphafold3(rep):
    tool = "ALPHAFOLD3"
    text = load(rep, tool, "AlphaFold3.yaml")
    if text is None:
        return
    # AlphaFold 3 has no public image, so its container is a path that must already exist.
    check_path(rep, tool, "_container", yaml_value(text, "_container"), kind="file")
    check_path(rep, tool, "_db_dir", yaml_value(text, "_db_dir"),
               contains=["mmcif_files"])
    check_path(rep, tool, "_model_path", yaml_value(text, "_model_path"), kind="file")
    chains = yaml_value(text, "_chains", "first")
    rep.add(tool, OK if chains in ("first", "all") else FAIL, "_chains", chains)


CHECKS = {
    "rfdiffusion": check_rfdiffusion,
    "boltzgen": check_boltzgen,
    "proteinmpnn": check_proteinmpnn,
    "ligandmpnn": check_ligandmpnn,
    "alphafold": check_alphafold,
    "alphafold3": check_alphafold3,
}


def main(argv):
    wanted = [a.lower() for a in argv[1:]] or list(CHECKS)
    unknown = [w for w in wanted if w not in CHECKS]
    if unknown:
        print(f"unknown tool(s): {', '.join(unknown)}", file=sys.stderr)
        print(f"choose from: {', '.join(CHECKS)}", file=sys.stderr)
        return 2

    rep = Report()
    for name in wanted:
        CHECKS[name](rep)
    rep.print()
    if rep.failed():
        print("\nA FAIL means that tool cannot run until the path is fixed in its YAML.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
