"""Window rules validation CLI tool.

Feature 024: Dynamic Window Management System

Validates window rules JSON files against schema and checks for common issues:
- JSON schema compliance
- Duplicate rule names
- Invalid regex patterns
- Logical errors (focus=true without workspace action)
"""

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import List, Dict, Any, Optional

try:
    import jsonschema
    JSONSCHEMA_AVAILABLE = True
except ImportError:
    JSONSCHEMA_AVAILABLE = False


@dataclass
class ValidationIssue:
    """Single validation issue/error."""

    severity: str  # "error", "warning", "info"
    rule_name: Optional[str]  # Rule name if applicable
    rule_index: Optional[int]  # Rule index in array
    field: Optional[str]  # Field path (e.g., "actions[0].target")
    message: str  # Human-readable error message

    def __str__(self) -> str:
        """Format issue for display."""
        prefix = {
            "error": "✗",
            "warning": "⚠",
            "info": "ℹ",
        }[self.severity]

        location = ""
        if self.rule_name:
            location = f"[{self.rule_name}] "
        elif self.rule_index is not None:
            location = f"[Rule {self.rule_index}] "

        field_info = f" ({self.field})" if self.field else ""

        return f"{prefix} {location}{self.message}{field_info}"


@dataclass
class ValidationResult:
    """Result of validation operation."""

    valid: bool
    issues: List[ValidationIssue]
    rules_count: int

    @property
    def errors(self) -> List[ValidationIssue]:
        """Get only error-level issues."""
        return [i for i in self.issues if i.severity == "error"]

    @property
    def warnings(self) -> List[ValidationIssue]:
        """Get only warning-level issues."""
        return [i for i in self.issues if i.severity == "warning"]

    def summary(self) -> str:
        """Get summary line."""
        error_count = len(self.errors)
        warning_count = len(self.warnings)

        if self.valid:
            return f"✓ Validation passed: {self.rules_count} rules, {warning_count} warnings"
        else:
            return f"✗ Validation failed: {error_count} errors, {warning_count} warnings"


def validate_rules_file(path: Path) -> ValidationResult:
    """Validate window rules file against schema and logic.

    Args:
        path: Path to window-rules.json file

    Returns:
        ValidationResult with issues and overall validity

    Example:
        >>> result = validate_rules_file(Path("~/.config/i3/window-rules.json"))
        >>> if result.valid:
        ...     print("Valid!")
    """
    issues: List[ValidationIssue] = []

    # Check file exists
    path = path.expanduser()
    if not path.exists():
        issues.append(ValidationIssue(
            severity="error",
            rule_name=None,
            rule_index=None,
            field=None,
            message=f"File not found: {path}"
        ))
        return ValidationResult(valid=False, issues=issues, rules_count=0)

    # Load JSON
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        issues.append(ValidationIssue(
            severity="error",
            rule_name=None,
            rule_index=None,
            field=None,
            message=f"Invalid JSON: {e}"
        ))
        return ValidationResult(valid=False, issues=issues, rules_count=0)

    # Detect format (old array vs new object)
    is_old_format = isinstance(data, list)

    if is_old_format:
        issues.append(ValidationIssue(
            severity="warning",
            rule_name=None,
            rule_index=None,
            field=None,
            message="Using legacy array format. Consider migrating to new format with 'i3pm migrate-rules'"
        ))
        rules = data
    else:
        # Validate schema if jsonschema available
        if JSONSCHEMA_AVAILABLE:
            schema_path = Path(__file__).parent.parent / "schemas" / "window_rules.json"
            if schema_path.exists():
                try:
                    with open(schema_path, "r") as f:
                        schema = json.load(f)
                    jsonschema.validate(data, schema)
                except jsonschema.ValidationError as e:
                    issues.append(ValidationIssue(
                        severity="error",
                        rule_name=None,
                        rule_index=None,
                        field=e.json_path if hasattr(e, 'json_path') else None,
                        message=f"Schema validation failed: {e.message}"
                    ))
                except FileNotFoundError:
                    issues.append(ValidationIssue(
                        severity="warning",
                        rule_name=None,
                        rule_index=None,
                        field=None,
                        message="Schema file not found, skipping schema validation"
                    ))

        # Extract rules from new format
        if "rules" not in data:
            issues.append(ValidationIssue(
                severity="error",
                rule_name=None,
                rule_index=None,
                field="rules",
                message="Missing 'rules' field in configuration"
            ))
            return ValidationResult(valid=False, issues=issues, rules_count=0)

        rules = data["rules"]

    # Check for duplicate rule names (new format only)
    if not is_old_format:
        rule_names = [r.get("name") for r in rules if "name" in r]
        duplicates = set([name for name in rule_names if rule_names.count(name) > 1])
        for dup in duplicates:
            issues.append(ValidationIssue(
                severity="error",
                rule_name=dup,
                rule_index=None,
                field="name",
                message=f"Duplicate rule name: '{dup}'"
            ))

    # Validate each rule
    for i, rule in enumerate(rules):
        rule_name = rule.get("name") if not is_old_format else None

        # Check for invalid regex in match_criteria or pattern_rule
        if is_old_format:
            # Old format: pattern_rule.pattern
            pattern_rule = rule.get("pattern_rule", {})
            pattern = pattern_rule.get("pattern", "")

            # Check for regex patterns
            if pattern.startswith("regex:"):
                regex_pattern = pattern[6:]
                try:
                    re.compile(regex_pattern)
                except re.error as e:
                    issues.append(ValidationIssue(
                        severity="error",
                        rule_name=rule_name,
                        rule_index=i,
                        field="pattern_rule.pattern",
                        message=f"Invalid regex pattern '{regex_pattern}': {e}"
                    ))
        else:
            # New format: match_criteria with pattern objects
            match_criteria = rule.get("match_criteria", {})
            for field_name, pattern_obj in match_criteria.items():
                if isinstance(pattern_obj, dict) and pattern_obj.get("match_type") == "regex":
                    regex_pattern = pattern_obj.get("pattern", "")
                    try:
                        re.compile(regex_pattern)
                    except re.error as e:
                        issues.append(ValidationIssue(
                            severity="error",
                            rule_name=rule_name,
                            rule_index=i,
                            field=f"match_criteria.{field_name}.pattern",
                            message=f"Invalid regex pattern '{regex_pattern}': {e}"
                        ))

        # Check for focus=true without workspace action (new format only)
        if not is_old_format:
            focus = rule.get("focus", False)
            actions = rule.get("actions", [])

            if focus:
                has_workspace_action = any(
                    action.get("type") == "workspace" for action in actions
                )
                if not has_workspace_action:
                    issues.append(ValidationIssue(
                        severity="warning",
                        rule_name=rule_name,
                        rule_index=i,
                        field="focus",
                        message="focus=true requires at least one workspace action"
                    ))

        # Check for empty actions list (new format only)
        if not is_old_format:
            actions = rule.get("actions", [])
            if not actions:
                issues.append(ValidationIssue(
                    severity="warning",
                    rule_name=rule_name,
                    rule_index=i,
                    field="actions",
                    message="Rule has no actions (will match but do nothing)"
                ))

    # Determine overall validity (no errors)
    valid = len([i for i in issues if i.severity == "error"]) == 0

    return ValidationResult(
        valid=valid,
        issues=issues,
        rules_count=len(rules)
    )


def format_validation_result(result: ValidationResult, verbose: bool = False) -> str:
    """Format validation result for terminal display.

    Args:
        result: ValidationResult to format
        verbose: If True, show all issues; if False, show summary only

    Returns:
        Formatted string for terminal output
    """
    lines = []

    # Summary line
    lines.append(result.summary())
    lines.append("")

    # Show errors
    if result.errors:
        lines.append("Errors:")
        for issue in result.errors:
            lines.append(f"  {issue}")
        lines.append("")

    # Show warnings if verbose or if there are errors
    if result.warnings and (verbose or result.errors):
        lines.append("Warnings:")
        for issue in result.warnings:
            lines.append(f"  {issue}")
        lines.append("")

    return "\n".join(lines)


# CLI entry point (will be added to i3pm commands)
def main():
    """CLI entry point for validate-rules command.

    Usage:
        i3pm validate-rules [--file ~/.config/i3/window-rules.json] [--verbose]
    """
    import argparse

    parser = argparse.ArgumentParser(
        description="Validate window rules file (Feature 024)"
    )
    parser.add_argument(
        "--file",
        type=Path,
        default=Path("~/.config/i3/window-rules.json"),
        help="Path to window rules file (default: ~/.config/i3/window-rules.json)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show all issues including warnings",
    )

    args = parser.parse_args()

    # Validate
    result = validate_rules_file(args.file)

    # Format and print
    output = format_validation_result(result, verbose=args.verbose)
    print(output)

    # Exit code: 0 if valid, 1 if invalid
    return 0 if result.valid else 1


if __name__ == "__main__":
    exit(main())
