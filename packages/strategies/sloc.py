import os, re, argparse

# HOW TO USE:
# python sloc.py --dir <root_directory> --include <include_patterns> --exclude <exclude_patterns>
# By default, excludes node_modules, lib, test, .git, coverage, docs, out, broadcast, utils
# Using flag override these defaults

def is_interface_file(file_path):
    with open(file_path, "r", encoding="utf-8") as file:
        content = file.read()
        if "interface" in content and "contract" not in content:
            return True

    return False


def count_valid_lines(file_path):
    valid_lines = 0
    inside_multiline_comment = False

    with open(file_path, "r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()

            if not line:
                continue

            if "/*" in line:
                inside_multiline_comment = True
            if "*/" in line:
                inside_multiline_comment = False
                continue
            if inside_multiline_comment:
                continue

            if line.startswith("//"):
                continue

            if line.startswith("import"):
                continue

            if line.startswith("pragma"):
                continue

            valid_lines += 1

    return valid_lines


def should_include_path(path, include_patterns, exclude_patterns):
    # Check if the path matches any exclude pattern
    if any(re.search(pattern, path) for pattern in exclude_patterns):
        return False

    # Check if the path matches any include pattern
    return any(re.search(pattern, path) for pattern in include_patterns)


def find_solidity_files(root_dir, include_patterns, exclude_patterns):
    solidity_files = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        relative_path = os.path.relpath(dirpath, root_dir)

        if should_include_path(relative_path, include_patterns, exclude_patterns):
            for filename in filenames:
                if filename.endswith(".sol"):
                    file_path = os.path.join(dirpath, filename)
                    if not is_interface_file(file_path):
                        solidity_files.append(file_path)

    return solidity_files


def main(root_directory, include_patterns, exclude_patterns):
    if not os.path.isdir(root_directory):
        print(f"The specified directory does not exist: {root_directory}")
        return

    solidity_files = find_solidity_files(
        root_directory, include_patterns, exclude_patterns
    )

    if not solidity_files:
        print(
            f"No non-interface Solidity files found in the specified included directories."
        )
        return

    total_lines = 0
    for file_path in solidity_files:
        lines = count_valid_lines(file_path)
        total_lines += lines
        print(f"{file_path}: {lines} valid lines")

    print(f"\nTotal valid lines across all non-interface Solidity files: {total_lines}")
    print(f"Included patterns: {', '.join(include_patterns)}")
    print(f"Excluded patterns: {', '.join(exclude_patterns)}")
    print("Note: Interface files were excluded from the count.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Count lines of code in Solidity files, excluding interfaces."
    )
    parser.add_argument(
        "--dir",
        default=os.getcwd(),
        help="Root directory to search for Solidity files (default: current working directory)",
    )
    parser.add_argument(
        "--include",
        nargs="+",
        default=["src", "contracts", r"packages/.*/src", r"packages/.*/contracts"],
        help="Regex patterns for directories to include in the search",
    )
    parser.add_argument(
        "--exclude",
        nargs="+",
        default=[
            "node_modules",
            "lib",
            "test",
            ".git",
            "coverage",
            "docs",
            "out",
            "broadcast",
            "utils"
        ],
        help="Regex patterns for directories to exclude from the search",
    )
    args = parser.parse_args()

    main(args.dir, args.include, args.exclude)