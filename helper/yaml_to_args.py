import argparse
import yaml
import sys

def yaml_to_args(yaml_file):
    with open(yaml_file) as f:
        params = yaml.safe_load(f)

    args = []
    for key, value in params.items():
        flag = f"--{key}"
        if isinstance(value, bool):
            if value:
                args.append(flag)
        elif isinstance(value, list):
            args.append(flag)
            args.append(" ".join(map(str, value)))
        elif value == '' or value is None:
            continue
        else:
            args.append(flag)
            args.append(str(value))
    return args

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: yaml_to_args.py <yaml_file>")
        sys.exit(1)

    args = yaml_to_args(sys.argv[1])
    print(" ".join(args))
