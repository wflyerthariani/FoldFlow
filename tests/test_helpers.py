"""Unit tests for the helper scripts in bin/.

These are the glue between tools: they reshape one tool's output into the next tool's
input, so a silent change here corrupts a run without failing it. Each script is invoked
as a subprocess, the same way the Nextflow modules call it.

Run:  python3 -m unittest discover -s tests -v
"""

import json
import pickle
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

BIN = Path(__file__).resolve().parent.parent / "bin"


def run_script(name, *args, expect_ok=True):
    """Invoke a helper script and return its CompletedProcess."""
    proc = subprocess.run(
        [sys.executable, str(BIN / name), *map(str, args)],
        capture_output=True, text=True,
    )
    if expect_ok and proc.returncode != 0:
        raise AssertionError(f"{name} failed ({proc.returncode}):\n{proc.stderr}")
    return proc


class TempDirTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, name, text):
        p = self.tmp / name
        p.write_text(text)
        return p


class TestFastaToAf3Json(TempDirTest):
    """bin/fasta_to_af3_json.py — FASTA from either MPNN into AlphaFold 3 input JSON."""

    def convert(self, fasta_text, **kwargs):
        fasta = self.write("in.fa", fasta_text)
        out = self.tmp / "out.json"
        args = ["--fasta", fasta, "--name", kwargs.pop("name", "job1"), "--output", out]
        for k, v in kwargs.items():
            args += [f"--{k.replace('_', '-')}", v]
        run_script("fasta_to_af3_json.py", *args)
        return json.loads(out.read_text())

    def test_single_chain(self):
        job = self.convert(">header\nACDEFGHIKL\n")
        self.assertEqual(job["name"], "job1")
        self.assertEqual(job["dialect"], "alphafold3")
        self.assertEqual(job["version"], 1)
        self.assertEqual(len(job["sequences"]), 1)
        self.assertEqual(job["sequences"][0]["protein"]["id"], "A")
        self.assertEqual(job["sequences"][0]["protein"]["sequence"], "ACDEFGHIKL")

    def test_proteinmpnn_slash_separator_first_chain_only(self):
        # ProteinMPNN separates chains with '/'; the default folds chain 1 only.
        job = self.convert(">h\nAAAA/CCCC\n")
        self.assertEqual(len(job["sequences"]), 1)
        self.assertEqual(job["sequences"][0]["protein"]["sequence"], "AAAA")

    def test_ligandmpnn_colon_separator_first_chain_only(self):
        # LigandMPNN uses ':' instead — both must be understood.
        job = self.convert(">h\nAAAA:CCCC\n")
        self.assertEqual(len(job["sequences"]), 1)
        self.assertEqual(job["sequences"][0]["protein"]["sequence"], "AAAA")

    def test_chains_all_builds_a_complex(self):
        job = self.convert(">h\nAAAA/CCCC/DDDD\n", chains="all")
        self.assertEqual([s["protein"]["id"] for s in job["sequences"]], ["A", "B", "C"])
        self.assertEqual(
            [s["protein"]["sequence"] for s in job["sequences"]],
            ["AAAA", "CCCC", "DDDD"],
        )

    def test_multiline_sequence_is_joined(self):
        job = self.convert(">h\nACDE\nFGHI\n")
        self.assertEqual(job["sequences"][0]["protein"]["sequence"], "ACDEFGHI")

    def test_seeds_accept_commas_and_spaces(self):
        self.assertEqual(self.convert(">h\nAAAA\n", seeds="1,2,3")["modelSeeds"], [1, 2, 3])
        self.assertEqual(self.convert(">h\nAAAA\n", seeds="4 5")["modelSeeds"], [4, 5])

    def test_job_name_is_preserved_for_output_naming(self):
        # The module keys its output filenames on this name, so it must survive verbatim.
        job = self.convert(">h\nAAAA\n", name="boltzgen_3_mpnn_1_ligandmpnn")
        self.assertEqual(job["name"], "boltzgen_3_mpnn_1_ligandmpnn")

    def test_empty_sequence_is_an_error_not_an_empty_job(self):
        fasta = self.write("empty.fa", ">header only\n")
        out = self.tmp / "out.json"
        proc = run_script(
            "fasta_to_af3_json.py", "--fasta", fasta, "--name", "j",
            "--output", out, expect_ok=False,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(out.exists())


class TestSplitMpnnFastas(TempDirTest):
    """bin/split_mpnn_fastas.py — one sequence per file, dropping MPNN's echoed input."""

    def split(self, files):
        src = self.tmp / "seqs"
        dst = self.tmp / "split"
        src.mkdir()
        for name, text in files.items():
            (src / name).write_text(text)
        run_script("split_mpnn_fastas.py", "--input-folder", src, "--output-folder", dst)
        return sorted(p.name for p in dst.glob("*.fa")), dst

    def test_first_record_is_dropped(self):
        # MPNN writes the input sequence as record 1; only the designs should survive.
        names, dst = self.split({"bb.fa": ">input\nAAAA\n>design1\nCCCC\n>design2\nDDDD\n"})
        self.assertEqual(names, ["bb_1.fa", "bb_2.fa"])
        self.assertIn("CCCC", (dst / "bb_1.fa").read_text())
        self.assertIn("DDDD", (dst / "bb_2.fa").read_text())

    def test_header_is_kept_on_each_split_record(self):
        _, dst = self.split({"bb.fa": ">in\nAAAA\n>T=0.1, sample=1\nCCCC\n"})
        self.assertTrue((dst / "bb_1.fa").read_text().startswith(">T=0.1, sample=1"))

    def test_fasta_extension_is_also_picked_up(self):
        names, _ = self.split({"bb.fasta": ">in\nAAAA\n>d1\nCCCC\n"})
        self.assertEqual(names, ["bb_1.fa"])

    def test_single_record_file_yields_nothing(self):
        # Only the echoed input and no designs: no output rather than a bogus sequence.
        names, _ = self.split({"bb.fa": ">input\nAAAA\n"})
        self.assertEqual(names, [])

    def test_each_source_file_is_split_independently(self):
        names, _ = self.split({
            "one.fa": ">in\nAAAA\n>d\nCCCC\n",
            "two.fa": ">in\nAAAA\n>d\nDDDD\n",
        })
        self.assertEqual(names, ["one_1.fa", "two_1.fa"])


class TestReformatFixedResidues(TempDirTest):
    """bin/reformat_fixed_residues.py — RFdiffusion TRB into the tool-agnostic sidecar."""

    def reformat(self, con_hal_pdb_idx):
        trb = self.tmp / "d.trb"
        with open(trb, "wb") as f:
            pickle.dump({"con_hal_pdb_idx": con_hal_pdb_idx}, f)
        return run_script("reformat_fixed_residues.py", "--input-file", trb).stdout

    def test_single_chain(self):
        out = self.reformat([("A", 5), ("A", 6), ("A", 7)])
        self.assertIn('--chains_to_design="A"', out)
        self.assertIn('--fixed_positions="5 6 7"', out)

    def test_multiple_chains_are_comma_separated(self):
        # Both MPNN modules parse this with `cut -d'"' -f2`, so the quoting matters.
        out = self.reformat([("A", 1), ("B", 10), ("A", 2), ("B", 11)])
        self.assertIn('--chains_to_design="A B"', out)
        self.assertIn('--fixed_positions="1 2, 10 11"', out)

    def test_residues_are_sorted_within_a_chain(self):
        out = self.reformat([("A", 9), ("A", 2), ("A", 5)])
        self.assertIn('--fixed_positions="2 5 9"', out)

    def test_output_is_parsed_the_way_the_modules_parse_it(self):
        # Mirrors: grep -- '--chains_to_design' file | cut -d'"' -f2
        out = self.reformat([("A", 3), ("B", 4)])
        for line in out.splitlines():
            if "--chains_to_design" in line:
                self.assertEqual(line.split('"')[1], "A B")
            if "--fixed_positions" in line:
                self.assertEqual(line.split('"')[1], "3, 4")


class TestYamlToArgs(TempDirTest):
    """bin/yaml_to_args.py — module YAML into CLI flags for the MPNN tools."""

    def to_args(self, text):
        return run_script("yaml_to_args.py", self.write("c.yaml", text)).stdout.strip()

    def test_underscore_keys_are_not_passed_to_the_tool(self):
        # The `_` prefix marks module-only settings (host paths, containers).
        args = self.to_args('_model_weights_path: /host/path\nmodel_type: "ligand_mpnn"\n')
        self.assertNotIn("_model_weights_path", args)
        self.assertNotIn("/host/path", args)
        self.assertIn("--model_type ligand_mpnn", args)

    def test_quotes_are_stripped_from_values(self):
        self.assertIn("--sampling_temp 0.1", self.to_args('sampling_temp: "0.1"\n'))

    def test_true_becomes_a_bare_flag_and_false_is_omitted(self):
        args = self.to_args("ca_only: true\nuse_soluble_model: false\n")
        self.assertIn("--ca_only", args)
        self.assertNotIn("use_soluble_model", args)

    def test_empty_values_are_omitted(self):
        # An empty path must not become `--path_to_model_weights ''`.
        args = self.to_args('path_to_model_weights: ""\nmodel_name: "v_48_020"\n')
        self.assertNotIn("path_to_model_weights", args)
        self.assertIn("--model_name v_48_020", args)

    def test_comments_and_blank_lines_are_ignored(self):
        self.assertEqual(self.to_args("# a comment\n\nseed: 0\n"), "--seed 0")

    def test_shipped_mpnn_configs_produce_usable_flags(self):
        configs = Path(__file__).resolve().parent.parent / "configs"
        for name in ("MPNN.yaml", "LigandMPNN.yaml"):
            path = configs / name
            if not path.exists():
                continue
            with self.subTest(config=name):
                args = run_script("yaml_to_args.py", path).stdout.split()
                self.assertTrue(args, f"{name} produced no flags")
                # Flags and values must alternate sensibly: no stray bare values.
                for tok in args:
                    if tok.startswith("--"):
                        self.assertNotIn(" ", tok)
                self.assertFalse(
                    any(tok.startswith("--_") for tok in args),
                    f"{name} leaked an underscore-prefixed module key",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
