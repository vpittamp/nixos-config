#!/usr/bin/env python3
"""
Code Audit Script - Duplicate Function Detection

Detects duplicate function implementations using Python AST parsing.
Part of Feature 039 - i3 Window Management System Diagnostic & Optimization

Usage:
    python scripts/audit-duplicates.py [target_directory]

Output:
    - Console report with duplicate function findings
    - JSON report for automated processing
"""

import ast
import hashlib
import json
import sys
from collections import defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Set


@dataclass
class FunctionInfo:
    """Information about a function definition."""
    name: str
    file_path: str
    line_number: int
    end_line: int
    code_hash: str
    ast_hash: str
    source_code: str


@dataclass
class DuplicateGroup:
    """Group of duplicate function implementations."""
    function_name: str
    functions: List[FunctionInfo]
    duplicate_type: str  # "exact" or "semantic"
    similarity_score: float


class ASTHasher(ast.NodeVisitor):
    """Generate hash of AST structure (ignoring variable names)."""

    def __init__(self):
        self.hash_parts = []

    def visit(self, node):
        """Visit AST node and record its type."""
        # Record node type (structure) but ignore names/values
        if isinstance(node, (ast.Name, ast.arg)):
            # Normalize variable names to generic placeholder
            self.hash_parts.append(f"{node.__class__.__name__}:VAR")
        elif isinstance(node, (ast.Constant, ast.Num, ast.Str)):
            # Ignore constant values, just record type
            self.hash_parts.append(f"{node.__class__.__name__}:CONST")
        else:
            self.hash_parts.append(node.__class__.__name__)

        self.generic_visit(node)

    def get_hash(self) -> str:
        """Get hash of AST structure."""
        hash_str = "|".join(self.hash_parts)
        return hashlib.md5(hash_str.encode()).hexdigest()


class DuplicateDetector:
    """Detect duplicate function implementations in Python codebase."""

    def __init__(self, target_dir: Path):
        self.target_dir = target_dir
        self.functions: List[FunctionInfo] = []
        self.duplicates: List[DuplicateGroup] = []

    def scan_directory(self):
        """Scan directory for Python files and extract functions."""
        print(f"Scanning {self.target_dir} for Python files...")

        for py_file in self.target_dir.rglob("*.py"):
            # Skip __pycache__ and test files for now
            if "__pycache__" in str(py_file):
                continue

            try:
                self._parse_file(py_file)
            except Exception as e:
                print(f"Error parsing {py_file}: {e}", file=sys.stderr)

        print(f"Found {len(self.functions)} function definitions")

    def _parse_file(self, file_path: Path):
        """Parse a single Python file and extract function definitions."""
        with open(file_path, 'r', encoding='utf-8') as f:
            source_code = f.read()

        try:
            tree = ast.parse(source_code, filename=str(file_path))
        except SyntaxError as e:
            print(f"Syntax error in {file_path}: {e}", file=sys.stderr)
            return

        # Extract source lines for getting function source
        source_lines = source_code.splitlines()

        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                func_info = self._extract_function_info(
                    node, file_path, source_lines
                )
                if func_info:
                    self.functions.append(func_info)

    def _extract_function_info(
        self, node: ast.FunctionDef, file_path: Path, source_lines: List[str]
    ) -> FunctionInfo:
        """Extract information about a function definition."""
        # Get function source code
        start_line = node.lineno - 1  # 0-indexed
        end_line = node.end_lineno if hasattr(node, 'end_lineno') else start_line + 1

        func_source = "\n".join(source_lines[start_line:end_line])

        # Generate code hash (exact match)
        code_hash = hashlib.md5(func_source.encode()).hexdigest()

        # Generate AST hash (semantic match)
        ast_hasher = ASTHasher()
        ast_hasher.visit(node)
        ast_hash = ast_hasher.get_hash()

        return FunctionInfo(
            name=node.name,
            file_path=str(file_path.relative_to(self.target_dir.parent)),
            line_number=node.lineno,
            end_line=end_line + 1,  # Convert back to 1-indexed
            code_hash=code_hash,
            ast_hash=ast_hash,
            source_code=func_source
        )

    def detect_duplicates(self):
        """Detect duplicate function implementations."""
        print("\nAnalyzing for duplicates...")

        # Group by function name first (only check functions with same name)
        by_name: Dict[str, List[FunctionInfo]] = defaultdict(list)
        for func in self.functions:
            by_name[func.name].append(func)

        # For each function name, check for duplicates
        for func_name, func_list in by_name.items():
            if len(func_list) < 2:
                continue  # Need at least 2 to have duplicates

            # Group by code hash (exact duplicates)
            exact_duplicates: Dict[str, List[FunctionInfo]] = defaultdict(list)
            for func in func_list:
                exact_duplicates[func.code_hash].append(func)

            for hash_val, duplicate_funcs in exact_duplicates.items():
                if len(duplicate_funcs) > 1:
                    self.duplicates.append(DuplicateGroup(
                        function_name=func_name,
                        functions=duplicate_funcs,
                        duplicate_type="exact",
                        similarity_score=1.0
                    ))

            # Group by AST hash (semantic duplicates)
            semantic_duplicates: Dict[str, List[FunctionInfo]] = defaultdict(list)
            for func in func_list:
                semantic_duplicates[func.ast_hash].append(func)

            for hash_val, duplicate_funcs in semantic_duplicates.items():
                if len(duplicate_funcs) > 1:
                    # Check if already found as exact duplicate
                    exact_hashes = {f.code_hash for group in self.duplicates
                                   if group.function_name == func_name
                                   for f in group.functions}
                    if duplicate_funcs[0].code_hash not in exact_hashes:
                        self.duplicates.append(DuplicateGroup(
                            function_name=func_name,
                            functions=duplicate_funcs,
                            duplicate_type="semantic",
                            similarity_score=0.9  # Approximate
                        ))

        print(f"Found {len(self.duplicates)} duplicate groups")

    def generate_report(self) -> Dict:
        """Generate duplicate detection report."""
        report = {
            "summary": {
                "total_functions": len(self.functions),
                "duplicate_groups": len(self.duplicates),
                "exact_duplicates": sum(1 for g in self.duplicates if g.duplicate_type == "exact"),
                "semantic_duplicates": sum(1 for g in self.duplicates if g.duplicate_type == "semantic"),
            },
            "duplicates": []
        }

        for group in self.duplicates:
            report["duplicates"].append({
                "function_name": group.function_name,
                "duplicate_type": group.duplicate_type,
                "similarity_score": group.similarity_score,
                "count": len(group.functions),
                "locations": [
                    {
                        "file": f.file_path,
                        "line": f.line_number,
                        "end_line": f.end_line
                    }
                    for f in group.functions
                ]
            })

        return report

    def print_report(self):
        """Print human-readable report to console."""
        if not self.duplicates:
            print("\n✓ No duplicate function implementations found!")
            return

        print("\n" + "=" * 80)
        print("DUPLICATE FUNCTION REPORT")
        print("=" * 80)

        exact_count = sum(1 for g in self.duplicates if g.duplicate_type == "exact")
        semantic_count = sum(1 for g in self.duplicates if g.duplicate_type == "semantic")

        print(f"\nSummary:")
        print(f"  Total functions analyzed: {len(self.functions)}")
        print(f"  Duplicate groups found: {len(self.duplicates)}")
        print(f"    - Exact duplicates: {exact_count}")
        print(f"    - Semantic duplicates: {semantic_count}")

        print("\n" + "-" * 80)
        print("DETAILED FINDINGS")
        print("-" * 80)

        for i, group in enumerate(self.duplicates, 1):
            print(f"\n{i}. Function '{group.function_name}' ({group.duplicate_type} duplicate)")
            print(f"   Similarity: {group.similarity_score * 100:.0f}%")
            print(f"   Found in {len(group.functions)} locations:")

            for func in group.functions:
                print(f"     - {func.file_path}:{func.line_number}-{func.end_line}")

            # Show first occurrence source (truncated)
            source_preview = group.functions[0].source_code.split('\n')[:5]
            print(f"\n   Source preview:")
            for line in source_preview:
                print(f"     {line}")
            if len(group.functions[0].source_code.split('\n')) > 5:
                print(f"     ... ({len(group.functions[0].source_code.split('\n')) - 5} more lines)")

        print("\n" + "=" * 80)


def main():
    """Main entry point."""
    if len(sys.argv) > 1:
        target_dir = Path(sys.argv[1])
    else:
        # Default to i3-project-event-daemon directory
        target_dir = Path("/etc/nixos/home-modules/desktop/i3-project-event-daemon")

    if not target_dir.exists():
        print(f"Error: Directory {target_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    detector = DuplicateDetector(target_dir)
    detector.scan_directory()
    detector.detect_duplicates()

    # Print console report
    detector.print_report()

    # Save JSON report
    report = detector.generate_report()
    output_file = Path("/etc/nixos/specs/039-create-a-new/audit-duplicates.json")
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n✓ JSON report saved to: {output_file}")

    # Exit with error code if duplicates found
    sys.exit(1 if detector.duplicates else 0)


if __name__ == "__main__":
    main()
