import pickle
from collections import defaultdict
from pathlib import Path
import argparse

def generate_fixed_positions(con_hal_pdb_idx):
    """
    Reformat trb fixed residues for use in MPNN

    Args:
        con_hal_pdb_idx: List of (chain_id, residue_number) tuples

    Returns:
        chains_to_design: str, e.g. "A B"
        fixed_positions: str, e.g. "101 102 103, 210 211"
    """

    chain_to_residues = defaultdict(list)
    for chain_id, res_num in con_hal_pdb_idx:
        chain_to_residues[chain_id].append(res_num)

    # Sort residues per chain
    for chain_id in chain_to_residues:
        chain_to_residues[chain_id].sort()

    chains_to_design = []
    fixed_positions_parts = []

    for chain_id in sorted(chain_to_residues.keys()):
        residues = chain_to_residues[chain_id]
        chains_to_design.append(chain_id)

        # Use original residue numbers, space-separated
        fixed_positions_parts.append(" ".join(str(r) for r in residues))

    chains_to_design_str = " ".join(chains_to_design)
    fixed_positions_str = ", ".join(fixed_positions_parts)

    return chains_to_design_str, fixed_positions_str

def main():
    parser = argparse.ArgumentParser(description="Reformat trb file to inputs for MPNN")
    parser.add_argument(
        "--input-file", 
        required=True, 
        help="Path to trb file to check"
    )
    args = parser.parse_args()

    input_dir = Path(args.input_file)

    with open(input_dir, "rb") as f:
        data = pickle.load(f)

    con_hal_pdb_idx = data['con_hal_pdb_idx']
    return generate_fixed_positions(con_hal_pdb_idx)

if __name__ == "__main__":
    chains, positions = main()
    print(f'--chains_to_design="{chains}"')
    print(f'--fixed_positions="{positions}"')