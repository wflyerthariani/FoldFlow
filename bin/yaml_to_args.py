import sys

def parse_yaml(yaml_file):
    """Custom YAML parser for simple key-value configs without external dependencies."""
    params = {}
    
    with open(yaml_file, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Skip empty lines and comments
            if not line or line.startswith('#'):
                continue
            
            # Parse key: value pairs
            if ':' in line:
                key, value = line.split(':', 1)
                key = key.strip()
                value = value.strip()
                
                # Parse value types
                if value.lower() == 'true':
                    params[key] = True
                elif value.lower() == 'false':
                    params[key] = False
                elif value == '':
                    params[key] = None
                elif value.startswith('"') and value.endswith('"'):
                    params[key] = value[1:-1]  # Remove quotes
                else:
                    # Try to parse as number, otherwise keep as string
                    try:
                        if '.' in value:
                            params[key] = float(value)
                        else:
                            params[key] = int(value)
                    except ValueError:
                        params[key] = value
    
    return params

def yaml_to_args(yaml_file):
    params = parse_yaml(yaml_file)

    args = []
    for key, value in params.items():
        if key.startswith('_'):
            continue
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
