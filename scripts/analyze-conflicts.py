#!/usr/bin/env python3
"""
Semantic Similarity Analyzer - Conflicting API Detection

Identifies conflicting APIs with overlapping functionality using semantic analysis.
Part of Feature 039 - i3 Window Management System Diagnostic & Optimization

Usage:
    python scripts/analyze-conflicts.py [target_directory]

Output:
    - Console report with conflicting API findings
    - JSON report for automated processing
"""

import ast
import json
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Set


@dataclass
class APIFunction:
    """Information about a public API function."""
    name: str
    file_path: str
    line_number: int
    module_name: str
    parameters: List[str]
    return_annotation: str
    docstring: str
    calls: Set[str]  # Functions this function calls
    is_async: bool


@dataclass
class ConflictGroup:
    """Group of conflicting API functions."""
    functions: List[APIFunction]
    conflict_type: str  # "name_overlap", "functionality_overlap", "deprecated_duplicate"
    similarity_score: float
    recommendation: str


class APIAnalyzer:
    """Analyze codebase for conflicting API functions."""

    def __init__(self, target_dir: Path):
        self.target_dir = target_dir
        self.functions: List[APIFunction] = []
        self.conflicts: List[ConflictGroup] = []

        # Suspicious patterns that indicate potential conflicts
        self.SUSPICIOUS_PATTERNS = [
            ("assign_workspace", "move_to_workspace", "Workspace assignment"),
            ("filter_windows", "hide_windows", "Window filtering"),
            ("read_env", "get_environment", "Environment reading"),
            ("handle_event", "process_event", "Event handling"),
            ("subscribe_events", "setup_subscriptions", "Event subscription"),
        ]

    def scan_directory(self):
        """Scan directory for Python files and extract public functions."""
        print(f"Scanning {self.target_dir} for API functions...")

        for py_file in self.target_dir.rglob("*.py"):
            # Skip __pycache__ and test files
            if "__pycache__" in str(py_file) or "test_" in py_file.name:
                continue

            try:
                self._parse_file(py_file)
            except Exception as e:
                print(f"Error parsing {py_file}: {e}", file=sys.stderr)

        print(f"Found {len(self.functions)} public API functions")

    def _parse_file(self, file_path: Path):
        """Parse a single Python file and extract public functions."""
        with open(file_path, 'r', encoding='utf-8') as f:
            source_code = f.read()

        try:
            tree = ast.parse(source_code, filename=str(file_path))
        except SyntaxError as e:
            print(f"Syntax error in {file_path}: {e}", file=sys.stderr)
            return

        module_name = self._get_module_name(file_path)

        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                # Only analyze public functions (not starting with _)
                if not node.name.startswith('_'):
                    func_info = self._extract_api_info(node, file_path, module_name)
                    if func_info:
                        self.functions.append(func_info)

    def _get_module_name(self, file_path: Path) -> str:
        """Get module name from file path."""
        try:
            rel_path = file_path.relative_to(self.target_dir)
            parts = list(rel_path.parts[:-1]) + [rel_path.stem]
            return ".".join(parts)
        except ValueError:
            return file_path.stem

    def _extract_api_info(
        self, node: ast.FunctionDef, file_path: Path, module_name: str
    ) -> APIFunction:
        """Extract information about an API function."""
        # Get parameters
        params = [arg.arg for arg in node.args.args]

        # Get return annotation
        return_annotation = ""
        if node.returns:
            return_annotation = ast.unparse(node.returns) if hasattr(ast, 'unparse') else str(node.returns)

        # Get docstring
        docstring = ast.get_docstring(node) or ""

        # Get function calls (for dependency analysis)
        calls = set()
        for child in ast.walk(node):
            if isinstance(child, ast.Call):
                if isinstance(child.func, ast.Name):
                    calls.add(child.func.id)
                elif isinstance(child.func, ast.Attribute):
                    calls.add(child.func.attr)

        # Check if async
        is_async = isinstance(node, ast.AsyncFunctionDef)

        return APIFunction(
            name=node.name,
            file_path=str(file_path.relative_to(self.target_dir.parent)),
            line_number=node.lineno,
            module_name=module_name,
            parameters=params,
            return_annotation=return_annotation,
            docstring=docstring,
            calls=calls,
            is_async=is_async
        )

    def detect_conflicts(self):
        """Detect conflicting API functions."""
        print("\nAnalyzing for API conflicts...")

        # 1. Detect name-based conflicts (similar names, different implementations)
        self._detect_name_conflicts()

        # 2. Detect functionality overlap (different names, similar purpose)
        self._detect_functionality_conflicts()

        # 3. Detect deprecated duplicates (old + new implementations)
        self._detect_deprecated_duplicates()

        print(f"Found {len(self.conflicts)} potential conflicts")

    def _detect_name_conflicts(self):
        """Detect functions with similar names in different modules."""
        # Group by normalized name (lowercase, underscores)
        name_groups: Dict[str, List[APIFunction]] = defaultdict(list)

        for func in self.functions:
            normalized = func.name.lower().replace('_', '')
            name_groups[normalized].append(func)

        # Find conflicts
        for normalized_name, funcs in name_groups.items():
            if len(funcs) > 1:
                # Check if they're in different modules (not just overridden methods)
                modules = set(f.module_name for f in funcs)
                if len(modules) > 1:
                    self.conflicts.append(ConflictGroup(
                        functions=funcs,
                        conflict_type="name_overlap",
                        similarity_score=0.8,
                        recommendation="Review for consolidation - same name in multiple modules"
                    ))

    def _detect_functionality_conflicts(self):
        """Detect functions with different names but similar purpose."""
        # Check suspicious patterns
        for pattern1, pattern2, description in self.SUSPICIOUS_PATTERNS:
            funcs1 = [f for f in self.functions if pattern1 in f.name.lower()]
            funcs2 = [f for f in self.functions if pattern2 in f.name.lower()]

            if funcs1 and funcs2:
                # Check if they're genuinely different
                modules1 = set(f.module_name for f in funcs1)
                modules2 = set(f.module_name for f in funcs2)

                if modules1 != modules2 or len(funcs1) + len(funcs2) > 2:
                    self.conflicts.append(ConflictGroup(
                        functions=funcs1 + funcs2,
                        conflict_type="functionality_overlap",
                        similarity_score=0.7,
                        recommendation=f"Review {description} implementations - possible functional overlap"
                    ))

    def _detect_deprecated_duplicates(self):
        """Detect old/legacy implementations alongside new ones."""
        # Look for functions with 'old', 'legacy', 'deprecated' in name or docstring
        deprecated_funcs = []
        current_funcs = []

        for func in self.functions:
            is_deprecated = any(
                marker in func.name.lower() or marker in func.docstring.lower()
                for marker in ['old', 'legacy', 'deprecated', 'obsolete', 'temp']
            )

            if is_deprecated:
                deprecated_funcs.append(func)
            else:
                current_funcs.append(func)

        # For each deprecated function, find similar current function
        for dep_func in deprecated_funcs:
            # Look for current function with similar name
            base_name = dep_func.name.lower().replace('old', '').replace('legacy', '').replace('deprecated', '').replace('_', '')

            similar_current = [
                f for f in current_funcs
                if base_name in f.name.lower().replace('_', '')
            ]

            if similar_current:
                self.conflicts.append(ConflictGroup(
                    functions=[dep_func] + similar_current,
                    conflict_type="deprecated_duplicate",
                    similarity_score=0.9,
                    recommendation=f"Remove deprecated function '{dep_func.name}' after migration complete"
                ))

    def generate_report(self) -> Dict:
        """Generate conflict analysis report."""
        report = {
            "summary": {
                "total_api_functions": len(self.functions),
                "conflict_groups": len(self.conflicts),
                "name_conflicts": sum(1 for c in self.conflicts if c.conflict_type == "name_overlap"),
                "functionality_conflicts": sum(1 for c in self.conflicts if c.conflict_type == "functionality_overlap"),
                "deprecated_conflicts": sum(1 for c in self.conflicts if c.conflict_type == "deprecated_duplicate"),
            },
            "conflicts": []
        }

        for conflict in self.conflicts:
            report["conflicts"].append({
                "conflict_type": conflict.conflict_type,
                "similarity_score": conflict.similarity_score,
                "recommendation": conflict.recommendation,
                "functions": [
                    {
                        "name": f.name,
                        "module": f.module_name,
                        "file": f.file_path,
                        "line": f.line_number,
                        "params": f.parameters,
                        "async": f.is_async
                    }
                    for f in conflict.functions
                ]
            })

        return report

    def print_report(self):
        """Print human-readable report to console."""
        if not self.conflicts:
            print("\n✓ No conflicting API functions detected!")
            return

        print("\n" + "=" * 80)
        print("API CONFLICT ANALYSIS REPORT")
        print("=" * 80)

        print(f"\nSummary:")
        print(f"  Total API functions analyzed: {len(self.functions)}")
        print(f"  Conflict groups found: {len(self.conflicts)}")

        conflict_counts = defaultdict(int)
        for c in self.conflicts:
            conflict_counts[c.conflict_type] += 1

        for conflict_type, count in conflict_counts.items():
            print(f"    - {conflict_type}: {count}")

        print("\n" + "-" * 80)
        print("DETAILED FINDINGS")
        print("-" * 80)

        for i, conflict in enumerate(self.conflicts, 1):
            print(f"\n{i}. {conflict.conflict_type.upper().replace('_', ' ')}")
            print(f"   Similarity: {conflict.similarity_score * 100:.0f}%")
            print(f"   Recommendation: {conflict.recommendation}")
            print(f"\n   Involved functions ({len(conflict.functions)}):")

            for func in conflict.functions:
                params_str = ', '.join(func.parameters) if func.parameters else '()'
                async_marker = "async " if func.is_async else ""
                print(f"     - {async_marker}{func.name}({params_str})")
                print(f"       Location: {func.file_path}:{func.line_number}")
                if func.docstring:
                    first_line = func.docstring.split('\n')[0][:60]
                    print(f"       Doc: {first_line}...")

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

    analyzer = APIAnalyzer(target_dir)
    analyzer.scan_directory()
    analyzer.detect_conflicts()

    # Print console report
    analyzer.print_report()

    # Save JSON report
    report = analyzer.generate_report()
    output_file = Path("/etc/nixos/specs/039-create-a-new/audit-conflicts.json")
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n✓ JSON report saved to: {output_file}")

    # Exit with error code if conflicts found
    sys.exit(1 if analyzer.conflicts else 0)


if __name__ == "__main__":
    main()
