import argparse
import json
import re
import string


def main():
    parser = argparse.ArgumentParser(
        description="Convert an MPNN FASTA into an AlphaFold 3 input JSON."
    )
    parser.add_argument("--fasta", required=True, help="Single-record FASTA; chains separated by '/' or ':'")
    parser.add_argument("--name", required=True, help="AlphaFold 3 job name (also names its output files)")
    parser.add_argument("--chains", choices=["first", "all"], default="first",
                        help="Fold only the first chain, or all chains as a complex")
    parser.add_argument("--seeds", default="1", help="Comma- or space-separated model seeds")
    parser.add_argument("--output", required=True, help="Path of the JSON to write")
    args = parser.parse_args()

    with open(args.fasta) as f:
        seq = "".join(line.strip() for line in f if not line.startswith(">"))

    # ProteinMPNN separates chains with '/', LigandMPNN with ':'.
    chains = [c for c in re.split("[/:]", seq) if c]
    if not chains:
        raise SystemExit(f"No sequence found in {args.fasta}")
    if args.chains == "first":
        chains = chains[:1]

    job = {
        "name": args.name,
        "modelSeeds": [int(s) for s in args.seeds.replace(",", " ").split()],
        "sequences": [
            {"protein": {"id": string.ascii_uppercase[i], "sequence": s}}
            for i, s in enumerate(chains)
        ],
        "dialect": "alphafold3",
        "version": 1,
    }
    with open(args.output, "w") as f:
        json.dump(job, f, indent=2)


if __name__ == "__main__":
    main()
