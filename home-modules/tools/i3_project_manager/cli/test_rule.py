"""Window rules testing CLI tool.

Feature 024: Dynamic Window Management System

Test window rules against simulated window properties to see which rule would match
and what actions would be executed. Useful for debugging and rule development.
"""

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import List, Dict, Any, Optional
from fnmatch import fnmatch


@dataclass
class MatchResult:
    """Result of rule matching test."""

    matched: bool
    rule_name: Optional[str]
    rule_index: Optional[int]
    priority: Optional[str]
    actions: List[Dict[str, Any]]
    workspace: Optional[int]  # For legacy format
    command: Optional[str]  # For legacy format

    def format_for_display(self) -> str:
        """Format result for terminal display."""
        lines = []

        if not self.matched:
            lines.append("✗ No matching rule found")
            return "\n".join(lines)

        # Match found
        if self.rule_name:
            lines.append(f"✓ Matched rule: {self.rule_name}")
        else:
            lines.append(f"✓ Matched rule at index {self.rule_index}")

        if self.priority:
            lines.append(f"  Priority: {self.priority}")

        # Show actions (new format)
        if self.actions:
            lines.append(f"  Actions ({len(self.actions)}):")
            for i, action in enumerate(self.actions, 1):
                action_type = action.get("type", "unknown")
                if action_type == "workspace":
                    lines.append(f"    {i}. Move to workspace {action.get('target')}")
                elif action_type == "mark":
                    lines.append(f"    {i}. Add mark '{action.get('value')}'")
                elif action_type == "float":
                    state = "enable" if action.get("enable") else "disable"
                    lines.append(f"    {i}. Set floating {state}")
                elif action_type == "layout":
                    lines.append(f"    {i}. Set layout {action.get('mode')}")
                else:
                    lines.append(f"    {i}. {action}")

        # Show legacy format fields
        if self.workspace is not None:
            lines.append(f"  Workspace: {self.workspace} (legacy format)")
        if self.command:
            lines.append(f"  Command: {self.command} (legacy format)")

        return "\n".join(lines)


def _match_pattern(pattern: str, value: str, match_type: str, case_sensitive: bool = True) -> bool:
    """Match a pattern against a value.

    Args:
        pattern: Pattern to match
        value: Value to test
        match_type: One of "exact", "regex", "wildcard"
        case_sensitive: Whether to match case-sensitively

    Returns:
        True if pattern matches value
    """
    if not case_sensitive:
        pattern = pattern.lower()
        value = value.lower()

    if match_type == "exact":
        return pattern == value
    elif match_type == "regex":
        try:
            return bool(re.search(pattern, value))
        except re.error:
            return False
    elif match_type == "wildcard":
        return fnmatch(value, pattern)
    else:
        return False


def _rule_matches(rule: Dict[str, Any], window_class: str, window_title: str) -> bool:
    """Check if a rule matches window properties.

    Args:
        rule: Rule dictionary from JSON
        window_class: Window class to test
        window_title: Window title to test

    Returns:
        True if rule matches all criteria
    """
    criteria = rule.get("match_criteria", {})

    # Check class match
    if "class" in criteria:
        class_pattern = criteria["class"]
        pattern = class_pattern.get("pattern", "")
        match_type = class_pattern.get("match_type", "exact")
        case_sensitive = class_pattern.get("case_sensitive", True)

        if not _match_pattern(pattern, window_class, match_type, case_sensitive):
            return False

    # Check title match
    if "title" in criteria:
        title_pattern = criteria["title"]
        pattern = title_pattern.get("pattern", "")
        match_type = title_pattern.get("match_type", "exact")
        case_sensitive = title_pattern.get("case_sensitive", True)

        if not _match_pattern(pattern, window_title, match_type, case_sensitive):
            return False

    # All criteria matched (or no criteria specified)
    return True


def test_rule_match(
    window_class: str,
    window_title: str,
    rules: List[Any],
) -> MatchResult:
    """Test which rule matches given window properties.

    Args:
        window_class: Window class to test (e.g., "Code", "firefox")
        window_title: Window title to test (e.g., "main.py - VS Code")
        rules: List of rule dictionaries to test against

    Returns:
        MatchResult with matched rule and actions

    Example:
        >>> rules = load_rules_for_testing(Path("~/.config/i3/window-rules.json"))
        >>> result = test_rule_match("Code", "", rules)
        >>> print(result.format_for_display())
    """
    # Test each rule in order (priority already sorted)
    for i, rule in enumerate(rules):
        if not rule.get("enabled", True):
            continue

        if _rule_matches(rule, window_class, window_title):
            # Get priority string
            priority_str = rule.get("priority", "default")

            # Extract actions (new format) or workspace/command (old format)
            actions = rule.get("actions", [])
            workspace = rule.get("workspace")
            command = rule.get("command")

            # Get rule name
            rule_name = rule.get("name")

            return MatchResult(
                matched=True,
                rule_name=rule_name,
                rule_index=i,
                priority=priority_str,
                actions=actions,
                workspace=workspace,
                command=command,
            )

    # No match found
    return MatchResult(
        matched=False,
        rule_name=None,
        rule_index=None,
        priority=None,
        actions=[],
        workspace=None,
        command=None,
    )


def load_rules_for_testing(path: Path) -> List[Any]:
    """Load window rules from file for testing.

    Args:
        path: Path to window rules file

    Returns:
        List of rule dictionaries sorted by priority

    Raises:
        FileNotFoundError: If file doesn't exist
        ValueError: If file is invalid
    """
    path = path.expanduser()
    if not path.exists():
        raise FileNotFoundError(f"Rules file not found: {path}")

    # Load JSON file
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON: {e}")
    except Exception as e:
        raise ValueError(f"Error reading file: {e}")

    # Handle both new format (dict with "rules" key) and legacy format (array)
    if isinstance(data, dict):
        rules = data.get("rules", [])
    elif isinstance(data, list):
        rules = data
    else:
        raise ValueError("Invalid rules format: expected dict or list")

    # Sort by priority (project > global > default)
    priority_order = {"project": 0, "global": 1, "default": 2}

    def get_priority_rank(rule: Dict[str, Any]) -> int:
        priority = rule.get("priority", "default")
        return priority_order.get(priority, 2)

    rules = sorted(rules, key=get_priority_rank)

    return rules


# CLI entry point (will be added to i3pm commands)
def main():
    """CLI entry point for test-rule command.

    Usage:
        i3pm test-rule --class=Code [--title="main.py"]
    """
    import argparse

    parser = argparse.ArgumentParser(
        description="Test window rule matching (Feature 024)"
    )
    parser.add_argument(
        "--class",
        dest="window_class",
        required=True,
        help="Window class to test (e.g., 'Code', 'firefox')",
    )
    parser.add_argument(
        "--title",
        dest="window_title",
        default="",
        help="Window title to test (optional)",
    )
    parser.add_argument(
        "--file",
        type=Path,
        default=Path("~/.config/i3/window-rules.json"),
        help="Path to window rules file (default: ~/.config/i3/window-rules.json)",
    )
    parser.add_argument(
        "--instance",
        dest="window_instance",
        default="",
        help="Window instance to test (optional, not yet implemented)",
    )

    args = parser.parse_args()

    # Load rules
    try:
        rules = load_rules_for_testing(args.file)
    except FileNotFoundError as e:
        print(f"Error: {e}")
        return 1
    except ValueError as e:
        print(f"Error: {e}")
        return 1

    if not rules:
        print(f"No rules found in {args.file}")
        return 0

    print(f"Testing window properties against {len(rules)} rules from {args.file}")
    print(f"  Class: {args.window_class}")
    if args.window_title:
        print(f"  Title: {args.window_title}")
    print()

    # Test matching
    result = test_rule_match(args.window_class, args.window_title, rules)

    # Display result
    print(result.format_for_display())

    return 0


if __name__ == "__main__":
    exit(main())
