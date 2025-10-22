"""Migration utilities for window rules: old format → new format.

Feature 024: Dynamic Window Management System

This module provides tools to migrate from the legacy window rules format
(array of rules with workspace + command fields) to the new structured
format (version + rules + defaults with typed actions).

Legacy Format (Array):
    [
      {
        "pattern_rule": {"pattern": "Code", "scope": "scoped", "priority": 250},
        "workspace": 2,
        "command": "layout tabbed"
      }
    ]

New Format (Structured):
    {
      "version": "1.0",
      "rules": [
        {
          "name": "vscode-workspace-2",
          "match_criteria": {"class": {"pattern": "Code", "match_type": "exact"}},
          "actions": [
            {"type": "workspace", "target": 2},
            {"type": "layout", "mode": "tabbed"}
          ],
          "priority": "project"
        }
      ],
      "defaults": {"workspace": "current", "focus": true}
    }
"""

import json
import re
from pathlib import Path
from typing import Dict, List, Any, Optional


# Priority mapping: old numeric priority → new priority level
def map_priority(numeric_priority: int) -> str:
    """Map numeric priority to priority level string.

    Mapping:
        1000+ → "project" (project-scoped rules)
        200-999 → "global" (global rules)
        <200 → "default" (default rules)
    """
    if numeric_priority >= 1000:
        return "project"
    elif numeric_priority >= 200:
        return "global"
    else:
        return "default"


# Scope mapping: old scope → new priority level
def map_scope_to_priority(scope: str) -> str:
    """Map old scope values to new priority levels.

    Mapping:
        "scoped" → "project"
        "global" → "global"
        "unscoped" → "default"
    """
    scope_map = {
        "scoped": "project",
        "global": "global",
        "unscoped": "default",
    }
    return scope_map.get(scope, "default")


def parse_i3_command(command: str) -> List[Dict[str, Any]]:
    """Parse i3 command string into structured actions.

    Supports:
        - "layout tabbed" → LayoutAction(mode="tabbed")
        - "layout stacked" → LayoutAction(mode="stacked")
        - "floating enable" → FloatAction(enable=True)
        - "floating disable" → FloatAction(enable=False)
        - "mark foo" → MarkAction(value="foo")

    Args:
        command: i3 command string (e.g., "layout tabbed")

    Returns:
        List of action dictionaries

    Examples:
        >>> parse_i3_command("layout tabbed")
        [{'type': 'layout', 'mode': 'tabbed'}]
        >>> parse_i3_command("floating enable")
        [{'type': 'float', 'enable': True}]
    """
    actions = []
    command = command.strip()

    # Layout command
    if command.startswith("layout "):
        mode = command[7:].strip()
        if mode in ["tabbed", "stacked", "splitv", "splith"]:
            actions.append({"type": "layout", "mode": mode})

    # Floating command
    elif command.startswith("floating "):
        state = command[9:].strip()
        if state == "enable":
            actions.append({"type": "float", "enable": True})
        elif state == "disable":
            actions.append({"type": "float", "enable": False})

    # Mark command
    elif command.startswith("mark "):
        mark_value = command[5:].strip()
        # Validate mark format
        if re.match(r"^[a-zA-Z0-9_-]+$", mark_value):
            actions.append({"type": "mark", "value": mark_value})

    # Unknown command - skip with warning
    else:
        # Return empty list for unknown commands
        pass

    return actions


def migrate_pattern_to_match_criteria(pattern_rule: Dict[str, Any]) -> Dict[str, Any]:
    """Convert old PatternRule format to new MatchCriteria format.

    Old format:
        {
          "pattern": "Code",  # or "glob:FFPWA-*", "regex:^Code.*", "pwa:YouTube", "title:YouTube"
          "scope": "scoped",
          "priority": 250
        }

    New format:
        {
          "class": {"pattern": "Code", "match_type": "exact", "case_sensitive": true}
        }

    Args:
        pattern_rule: Old PatternRule dictionary

    Returns:
        New MatchCriteria dictionary
    """
    pattern = pattern_rule["pattern"]

    # Detect pattern type from prefix
    if pattern.startswith("glob:"):
        # Glob pattern: "glob:FFPWA-*" → {"pattern": "FFPWA-*", "match_type": "wildcard"}
        return {
            "class": {
                "pattern": pattern[5:],
                "match_type": "wildcard",
                "case_sensitive": True,
            }
        }
    elif pattern.startswith("regex:"):
        # Regex pattern: "regex:^Code.*" → {"pattern": "^Code.*", "match_type": "regex"}
        return {
            "class": {
                "pattern": pattern[6:],
                "match_type": "regex",
                "case_sensitive": True,
            }
        }
    elif pattern.startswith("pwa:"):
        # PWA pattern: "pwa:YouTube" → class=FFPWA-*, title=YouTube
        title = pattern[4:]
        return {
            "class": {"pattern": "FFPWA-*", "match_type": "wildcard"},
            "title": {"pattern": title, "match_type": "exact"},
        }
    elif pattern.startswith("title:"):
        # Title-only pattern: "title:YouTube" → title=YouTube (any class)
        return {
            "title": {
                "pattern": pattern[6:],
                "match_type": "exact",
                "case_sensitive": True,
            }
        }
    else:
        # Exact match (default): "Code" → {"pattern": "Code", "match_type": "exact"}
        return {
            "class": {
                "pattern": pattern,
                "match_type": "exact",
                "case_sensitive": True,
            }
        }


def generate_rule_name(pattern: str, workspace: Optional[int] = None) -> str:
    """Generate a rule name from pattern and workspace.

    Examples:
        >>> generate_rule_name("Code", 2)
        'code-workspace-2'
        >>> generate_rule_name("glob:FFPWA-*", 4)
        'ffpwa-workspace-4'
        >>> generate_rule_name("Firefox")
        'firefox-rule'
    """
    # Extract base pattern (remove prefix)
    base = pattern
    for prefix in ["glob:", "regex:", "pwa:", "title:"]:
        if base.startswith(prefix):
            base = base[len(prefix) :]

    # Sanitize: lowercase, remove special chars, replace spaces with dash
    sanitized = re.sub(r"[^a-zA-Z0-9_-]", "-", base.lower())
    sanitized = re.sub(r"-+", "-", sanitized)  # Collapse multiple dashes
    sanitized = sanitized.strip("-")  # Remove leading/trailing dashes

    # Add workspace suffix if present
    if workspace:
        return f"{sanitized}-workspace-{workspace}"
    else:
        return f"{sanitized}-rule"


def migrate_rule_v1_to_v2(old_rule: Dict[str, Any]) -> Dict[str, Any]:
    """Convert a single old-format rule to new-format rule.

    Args:
        old_rule: Legacy format rule dictionary

    Returns:
        New format rule dictionary

    Example:
        >>> old_rule = {
        ...     "pattern_rule": {"pattern": "Code", "scope": "scoped", "priority": 250},
        ...     "workspace": 2,
        ...     "command": "layout tabbed"
        ... }
        >>> new_rule = migrate_rule_v1_to_v2(old_rule)
        >>> new_rule["name"]
        'code-workspace-2'
        >>> new_rule["priority"]
        'project'
    """
    pattern_rule = old_rule["pattern_rule"]
    workspace = old_rule.get("workspace")
    command = old_rule.get("command")

    # Generate rule name
    name = generate_rule_name(pattern_rule["pattern"], workspace)

    # Convert match criteria
    match_criteria = migrate_pattern_to_match_criteria(pattern_rule)

    # Build actions list
    actions = []

    # Add workspace action if present
    if workspace is not None:
        actions.append({"type": "workspace", "target": workspace})

    # Parse command into actions
    if command:
        command_actions = parse_i3_command(command)
        actions.extend(command_actions)

    # If no actions generated, add a default workspace action (current)
    if not actions:
        # No actions = no-op rule (could be modifier-only)
        # For now, keep empty actions list
        pass

    # Determine priority
    numeric_priority = pattern_rule.get("priority", 0)
    scope = pattern_rule.get("scope", "unscoped")

    # Use scope mapping if priority not set, otherwise use numeric mapping
    if numeric_priority == 0:
        priority = map_scope_to_priority(scope)
    else:
        priority = map_priority(numeric_priority)

    # Build new format rule
    new_rule = {
        "name": name,
        "match_criteria": match_criteria,
        "actions": actions,
        "priority": priority,
        "focus": False,  # Default: don't focus
        "enabled": True,  # Default: enabled
    }

    # Preserve modifier if present
    if "modifier" in old_rule:
        new_rule["modifier"] = old_rule["modifier"]

    # Preserve blacklist if present
    if "blacklist" in old_rule and old_rule["blacklist"]:
        new_rule["blacklist"] = old_rule["blacklist"]

    return new_rule


def migrate_rules_file(
    input_path: Path, output_path: Optional[Path] = None, dry_run: bool = False
) -> Dict[str, Any]:
    """Convert entire window rules file from old format to new format.

    Args:
        input_path: Path to old format rules file (JSON array)
        output_path: Path to write new format rules file (defaults to input_path with -v2 suffix)
        dry_run: If True, don't write output file, just return converted data

    Returns:
        New format rules dictionary

    Raises:
        FileNotFoundError: If input file doesn't exist
        ValueError: If input file is invalid JSON or wrong format

    Example:
        >>> migrate_rules_file(Path("~/.config/i3/window-rules.json"))
        {'version': '1.0', 'rules': [...], 'defaults': {...}}
    """
    input_path = input_path.expanduser()

    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    # Load old format file
    with open(input_path, "r") as f:
        old_data = json.load(f)

    # Validate old format (should be array)
    if not isinstance(old_data, list):
        raise ValueError(f"Old format should be JSON array, got {type(old_data)}")

    # Convert each rule
    new_rules = []
    for i, old_rule in enumerate(old_data):
        try:
            new_rule = migrate_rule_v1_to_v2(old_rule)
            new_rules.append(new_rule)
        except Exception as e:
            raise ValueError(f"Error migrating rule {i}: {e}")

    # Build new format structure
    new_data = {
        "version": "1.0",
        "rules": new_rules,
        "defaults": {"workspace": "current", "focus": True},
    }

    # Write output file
    if not dry_run:
        if output_path is None:
            # Default: add -v2 suffix before extension
            output_path = input_path.with_stem(f"{input_path.stem}-v2")

        output_path = output_path.expanduser()
        with open(output_path, "w") as f:
            json.dump(new_data, f, indent=2)

        print(f"Migrated {len(new_rules)} rules from {input_path} to {output_path}")

    return new_data


# CLI entry point (will be added to i3pm commands)
def main():
    """CLI entry point for migration command.

    Usage:
        i3pm migrate-rules --input ~/.config/i3/window-rules.json --output ~/.config/i3/window-rules-v2.json
    """
    import argparse

    parser = argparse.ArgumentParser(
        description="Migrate window rules from old format to new format (Feature 024)"
    )
    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Input file path (old format)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output file path (new format). Defaults to input with -v2 suffix.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show migration result without writing output file",
    )

    args = parser.parse_args()

    try:
        result = migrate_rules_file(args.input, args.output, args.dry_run)

        if args.dry_run:
            print("Dry run - would generate:")
            print(json.dumps(result, indent=2))

    except Exception as e:
        print(f"Error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
