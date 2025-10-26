#!/usr/bin/env python3
"""
Code Cleanup Verification Script

Checks for:
1. Debug logging statements (logger.debug calls that should be removed)
2. Missing docstrings on public functions/classes
3. Code formatting issues (can be fixed with black)

Feature 039 - Task T109

Usage:
    python3 scripts/code-cleanup-check.py
    python3 scripts/code-cleanup-check.py --fix  # Auto-fix formatting with black
"""

import os
import re
import sys
import subprocess
from pathlib import Path
from typing import List, Tuple


# Paths to check
DAEMON_DIR = Path("/etc/nixos/home-modules/desktop/i3-project-event-daemon")
DIAGNOSTIC_CLI_DIR = Path("/etc/nixos/home-modules/tools/i3pm-diagnostic")
SERVICES_DIR = DAEMON_DIR / "services"


def find_python_files(directory: Path) -> List[Path]:
    """Find all Python files in directory."""
    if not directory.exists():
        return []
    return list(directory.rglob("*.py"))


def check_debug_logging(file_path: Path) -> List[Tuple[int, str]]:
    """
    Find debug logging statements that should be removed.

    Returns list of (line_number, line_content) tuples.
    """
    issues = []

    try:
        with open(file_path, 'r') as f:
            for line_num, line in enumerate(f, 1):
                # Skip if it's Feature 039 diagnostic logging (these are intentional)
                if "Feature 039" in line or "# T0" in line:
                    continue

                # Check for logger.debug calls
                if re.search(r'logger\.debug\(', line) and not line.strip().startswith('#'):
                    issues.append((line_num, line.strip()))

    except Exception as e:
        print(f"Error reading {file_path}: {e}")

    return issues


def check_missing_docstrings(file_path: Path) -> List[Tuple[int, str]]:
    """
    Find public functions/classes missing docstrings.

    Returns list of (line_number, function/class_name) tuples.
    """
    issues = []

    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()

        i = 0
        while i < len(lines):
            line = lines[i].strip()

            # Check for function/class definition
            func_match = re.match(r'^(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', line)
            class_match = re.match(r'^class\s+([a-zA-Z_][a-zA-Z0-9_]*)', line)

            if func_match or class_match:
                name = func_match.group(2) if func_match else class_match.group(1)

                # Skip private methods (start with _)
                if name.startswith('_') and not name.startswith('__'):
                    i += 1
                    continue

                # Skip dunder methods
                if name.startswith('__') and name.endswith('__'):
                    i += 1
                    continue

                # Check if next non-empty line is a docstring
                j = i + 1
                while j < len(lines) and not lines[j].strip():
                    j += 1

                if j < len(lines):
                    next_line = lines[j].strip()
                    if not (next_line.startswith('"""') or next_line.startswith("'''")):
                        issues.append((i + 1, name))

            i += 1

    except Exception as e:
        print(f"Error reading {file_path}: {e}")

    return issues


def check_formatting(file_path: Path) -> bool:
    """
    Check if file is formatted correctly using black.

    Returns True if formatting is correct, False otherwise.
    """
    try:
        result = subprocess.run(
            ["black", "--check", str(file_path)],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except FileNotFoundError:
        print("Warning: black not installed, skipping formatting check")
        return True


def fix_formatting(file_path: Path) -> bool:
    """
    Fix formatting using black.

    Returns True if successful, False otherwise.
    """
    try:
        result = subprocess.run(
            ["black", str(file_path)],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except FileNotFoundError:
        print("Error: black not installed")
        return False


def main():
    """Main cleanup check execution."""
    fix_mode = "--fix" in sys.argv

    print("=" * 80)
    print("Code Cleanup Verification - Feature 039")
    print("=" * 80)
    print()

    # Collect all Python files
    daemon_files = find_python_files(DAEMON_DIR)
    cli_files = find_python_files(DIAGNOSTIC_CLI_DIR)
    all_files = daemon_files + cli_files

    if not all_files:
        print("No Python files found to check")
        return

    print(f"Checking {len(all_files)} Python files...")
    print()

    # Track issues
    debug_logging_issues = {}
    missing_docstring_issues = {}
    formatting_issues = []

    # Check each file
    for file_path in all_files:
        relative_path = file_path.relative_to(Path("/etc/nixos"))

        # Check debug logging
        debug_issues = check_debug_logging(file_path)
        if debug_issues:
            debug_logging_issues[relative_path] = debug_issues

        # Check docstrings
        docstring_issues = check_missing_docstrings(file_path)
        if docstring_issues:
            missing_docstring_issues[relative_path] = docstring_issues

        # Check/fix formatting
        if fix_mode:
            if not fix_formatting(file_path):
                formatting_issues.append(relative_path)
        else:
            if not check_formatting(file_path):
                formatting_issues.append(relative_path)

    # Report results
    total_issues = len(debug_logging_issues) + len(missing_docstring_issues) + len(formatting_issues)

    if total_issues == 0:
        print("✅ No cleanup issues found!")
        print()
        print("Code is clean:")
        print("  - No debug logging statements")
        print("  - All public functions have docstrings")
        print("  - Code is properly formatted")
        sys.exit(0)

    # Debug logging issues
    if debug_logging_issues:
        print("🔍 Debug Logging Issues:")
        print("-" * 80)
        for file_path, issues in debug_logging_issues.items():
            print(f"\n{file_path}:")
            for line_num, line in issues[:5]:  # Show first 5
                print(f"  Line {line_num}: {line}")
            if len(issues) > 5:
                print(f"  ... and {len(issues) - 5} more")
        print()

    # Missing docstrings
    if missing_docstring_issues:
        print("📝 Missing Docstrings:")
        print("-" * 80)
        for file_path, issues in missing_docstring_issues.items():
            print(f"\n{file_path}:")
            for line_num, name in issues[:5]:  # Show first 5
                print(f"  Line {line_num}: {name}()")
            if len(issues) > 5:
                print(f"  ... and {len(issues) - 5} more")
        print()

    # Formatting issues
    if formatting_issues:
        print("🎨 Formatting Issues:")
        print("-" * 80)
        for file_path in formatting_issues:
            status = "✓ Fixed" if fix_mode else "✗ Needs formatting"
            print(f"  {status}: {file_path}")
        print()

        if not fix_mode:
            print("Run with --fix to auto-format: python3 scripts/code-cleanup-check.py --fix")
            print()

    # Summary
    print("=" * 80)
    print(f"Summary: {total_issues} issue(s) found")
    print("-" * 80)
    print(f"  Debug logging:     {len(debug_logging_issues)} files")
    print(f"  Missing docstrings: {len(missing_docstring_issues)} files")
    print(f"  Formatting issues:  {len(formatting_issues)} files")
    print("=" * 80)

    if total_issues > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
