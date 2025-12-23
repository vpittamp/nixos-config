#!/usr/bin/env python3
"""Initialize a new NixOS integration test from templates.

Usage:
    init_test.py <test-name> [--type TYPE] [--output DIR]

Arguments:
    test-name   Name for the new test (e.g., "my-feature")

Options:
    --type TYPE     Template type: minimal, multi_machine, graphical, otel_traced
                    (default: minimal)
    --output DIR    Output directory (default: ./tests/<test-name>)

Examples:
    init_test.py my-service
    init_test.py sway-windows --type graphical
    init_test.py network-test --type multi_machine
    init_test.py traced-test --type otel_traced --output ./my-tests
"""

import argparse
import os
import sys
from pathlib import Path


def get_skill_dir() -> Path:
    """Get the skill directory (parent of scripts/)."""
    return Path(__file__).parent.parent


def get_template(template_type: str) -> str:
    """Read template file content."""
    skill_dir = get_skill_dir()
    template_path = skill_dir / "templates" / f"{template_type}.nix"

    if not template_path.exists():
        available = [f.stem for f in (skill_dir / "templates").glob("*.nix")]
        print(f"Error: Template '{template_type}' not found.", file=sys.stderr)
        print(f"Available templates: {', '.join(available)}", file=sys.stderr)
        sys.exit(1)

    return template_path.read_text()


def substitute_test_name(content: str, test_name: str) -> str:
    """Replace TODO_TEST_NAME placeholder with actual test name."""
    return content.replace("TODO_TEST_NAME", test_name)


def main():
    parser = argparse.ArgumentParser(
        description="Initialize a new NixOS integration test",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Examples:")[1] if "Examples:" in __doc__ else "",
    )
    parser.add_argument("test_name", help="Name for the new test")
    parser.add_argument(
        "--type",
        choices=["minimal", "multi_machine", "graphical", "otel_traced"],
        default="minimal",
        help="Template type (default: minimal)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output directory (default: ./tests/<test-name>)",
    )

    args = parser.parse_args()

    # Determine output directory
    if args.output:
        output_dir = args.output
    else:
        output_dir = Path("tests") / args.test_name

    output_file = output_dir / "default.nix"

    # Check if already exists
    if output_file.exists():
        print(f"Error: {output_file} already exists.", file=sys.stderr)
        print("Remove it first or choose a different name.", file=sys.stderr)
        sys.exit(1)

    # Get and customize template
    template = get_template(args.type)
    content = substitute_test_name(template, args.test_name)

    # Create directory and write file
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file.write_text(content)

    print(f"Created {output_file}")
    print()
    print("Next steps:")
    print(f"  1. Edit {output_file} to add your test logic")
    print(f"  2. Build: nix-build {output_dir} -A default")
    print(f"  3. Debug: $(nix-build {output_dir} -A default.driverInteractive)/bin/nixos-test-driver")


if __name__ == "__main__":
    main()
