import os
from pathlib import Path
import argparse

def parse_fasta(fasta_path):
    """Simple FASTA parser without BioPython dependency."""
    records = []
    current_header = None
    current_seq = []
    
    with open(fasta_path, 'r') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('>'):
                # Save previous record
                if current_header is not None:
                    records.append((current_header, ''.join(current_seq)))
                current_header = line[1:]  # Remove '>'
                current_seq = []
            else:
                current_seq.append(line)
        
        # Save last record
        if current_header is not None:
            records.append((current_header, ''.join(current_seq)))
    
    return records

def split_fasta_file(fasta_path: Path, output_dir: Path):
    base_name = fasta_path.stem  # filename without extension
    records = parse_fasta(fasta_path)
    
    # Skip the first sequence
    for i, (header, seq) in enumerate(records[1:], start=1):
        out_name = f"{base_name}_{i}.fa"
        out_path = output_dir / out_name
        with open(out_path, "w") as f:
            f.write(f">{header}\n{seq}\n")
        print(f"Saved: {out_path}")

def main():
    parser = argparse.ArgumentParser(description="Split ProteinMPNN multi-sequence FASTAs.")
    parser.add_argument(
        "--input-folder", 
        required=True, 
        help="Path to folder with MPNN output .fa or .fasta files"
    )
    parser.add_argument(
        "--output-folder", 
        required=True, 
        help="Path to folder to save individual FASTA files"
    )
    args = parser.parse_args()

    input_dir = Path(args.input_folder)
    output_dir = Path(args.output_folder)
    output_dir.mkdir(parents=True, exist_ok=True)

    fasta_files = list(input_dir.glob("*.fa")) + list(input_dir.glob("*.fasta"))

    if not fasta_files:
        print(f"No .fa or .fasta files found in {input_dir}")
        return

    for fasta in fasta_files:
        split_fasta_file(fasta, output_dir)

if __name__ == "__main__":
    main()
