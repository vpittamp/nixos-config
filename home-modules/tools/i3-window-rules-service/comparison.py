"""
Pattern comparison and analysis.

Compare discovered patterns with existing window-rules.json to identify:
- Correctly configured rules
- Broken patterns that don't match
- Missing rules for discovered applications
- Workspace assignment issues
"""

import json
from pathlib import Path
from typing import Optional, List, Dict, Tuple
from dataclasses import dataclass
from enum import Enum

try:
    from .models import Window, Pattern, WindowRule, PatternType, Scope
    from .discovery import discover_from_open_windows, generate_pattern
    from .config_manager import ConfigManager
except ImportError:
    from models import Window, Pattern, WindowRule, PatternType, Scope
    from discovery import discover_from_open_windows, generate_pattern
    from config_manager import ConfigManager


def load_existing_rules_from_daemon_format() -> List[Dict]:
    """
    Load existing rules from daemon's window-rules.json format.

    The daemon uses a simpler format:
    [
      {
        "pattern_rule": {"pattern": "Alacritty", "scope": "scoped", ...},
        "workspace": 1
      },
      ...
    ]

    Returns simplified rule dictionaries for comparison.
    """
    config_path = Path.home() / ".config/i3/window-rules.json"
    if not config_path.exists():
        return []

    try:
        with open(config_path, 'r') as f:
            data = json.load(f)

        rules = []
        for item in data:
            pattern_rule = item.get("pattern_rule", {})
            rules.append({
                "pattern": pattern_rule.get("pattern", ""),
                "scope": pattern_rule.get("scope", "global"),
                "priority": pattern_rule.get("priority", 200),
                "workspace": item.get("workspace"),
                "description": pattern_rule.get("description", ""),
            })

        return rules
    except Exception as e:
        print(f"Warning: Failed to load window-rules.json: {e}")
        return []


class RuleStatus(str, Enum):
    """Status of a rule after comparison."""
    CORRECT = "correct"           # Rule matches and workspace is correct
    PATTERN_BROKEN = "pattern_broken"  # Pattern doesn't match window
    WORKSPACE_WRONG = "workspace_wrong"  # Pattern matches but workspace assignment is wrong
    MISSING = "missing"           # Window has no corresponding rule


@dataclass
class ComparisonResult:
    """Result of comparing a window with existing rules."""
    window: Window
    discovered_pattern: Pattern
    matched_rule: Optional[Dict]  # Changed from WindowRule to Dict
    status: RuleStatus
    issues: List[str]
    suggestions: List[str]


async def compare_with_existing_rules() -> Dict[str, any]:
    """
    Compare discovered patterns from open windows with existing window-rules.json.

    Returns:
        Dictionary with comparison statistics and detailed results
    """
    # Get discovered patterns from open windows
    discovery_results = await discover_from_open_windows()

    if not discovery_results:
        return {
            "success": False,
            "error": "No windows found to analyze",
            "statistics": {},
            "results": []
        }

    # Load existing rules (use direct parsing to adapt to daemon's format)
    existing_rules = load_existing_rules_from_daemon_format()

    # Analyze each discovered window
    results: List[ComparisonResult] = []

    for discovery in discovery_results:
        if not discovery.window or not discovery.generated_pattern:
            continue

        window = discovery.window
        discovered_pattern = discovery.generated_pattern

        # Find matching rule in existing configuration
        matched_rule = find_matching_rule(window, existing_rules)

        # Determine status and issues
        status, issues, suggestions = analyze_rule_match(
            window, discovered_pattern, matched_rule
        )

        result = ComparisonResult(
            window=window,
            discovered_pattern=discovered_pattern,
            matched_rule=matched_rule,
            status=status,
            issues=issues,
            suggestions=suggestions,
        )
        results.append(result)

    # Calculate statistics
    statistics = calculate_statistics(results, len(existing_rules))

    return {
        "success": True,
        "statistics": statistics,
        "results": results,
        "total_rules": len(existing_rules),
        "total_windows": len(results),
    }


def find_matching_rule(window: Window, rules: List[Dict]) -> Optional[Dict]:
    """
    Find the rule that matches this window in the existing configuration.

    Args:
        window: Window to match
        rules: List of existing window rules (as dicts)

    Returns:
        Matching rule dict or None if no match
    """
    # Sort by priority (lower = higher priority)
    sorted_rules = sorted(rules, key=lambda r: r.get("priority", 200))

    for rule in sorted_rules:
        # Check if rule matches window
        if matches_rule(window, rule):
            return rule

    return None


def matches_rule(window: Window, rule: Dict) -> bool:
    """
    Check if a window matches a rule's pattern.

    Args:
        window: Window to check
        rule: Rule dict to test against

    Returns:
        True if rule matches window
    """
    pattern = rule.get("pattern", "")

    if not pattern:
        return False

    # Handle title: prefix patterns (daemon format)
    if pattern.startswith("title:"):
        title_pattern = pattern[6:]  # Remove "title:" prefix

        # Check if it's a regex pattern (starts with ^)
        if title_pattern.startswith("^"):
            import re
            try:
                return bool(re.match(title_pattern, window.title))
            except:
                return False

        # Substring match
        return title_pattern.lower() in window.title.lower()

    # The daemon uses class-based matching primarily
    # Check exact match
    if pattern == window.window_class:
        return True

    # Check case-insensitive
    if pattern.lower() == window.window_class.lower():
        return True

    # Check title substring match (for terminals)
    if pattern.lower() in window.title.lower():
        return True

    return False


def analyze_rule_match(
    window: Window,
    discovered_pattern: Pattern,
    matched_rule: Optional[Dict]
) -> Tuple[RuleStatus, List[str], List[str]]:
    """
    Analyze the match between window, discovered pattern, and existing rule.

    Returns:
        Tuple of (status, issues, suggestions)
    """
    issues = []
    suggestions = []

    # No rule exists for this window
    if not matched_rule:
        return (
            RuleStatus.MISSING,
            ["No rule configured for this application"],
            [f"Add rule with pattern: {discovered_pattern.type.value}={discovered_pattern.value}"]
        )

    # Check if pattern matches correctly
    pattern_correct = check_pattern_correctness(window, discovered_pattern, matched_rule)

    # Check if workspace assignment is correct
    workspace_correct = True
    rule_workspace = matched_rule.get("workspace")
    if rule_workspace is not None:
        if window.workspace_num != rule_workspace:
            workspace_correct = False
            issues.append(
                f"Window on workspace {window.workspace_num}, rule expects workspace {rule_workspace}"
            )
            suggestions.append(
                f"Verify workspace assignment or update rule to workspace {window.workspace_num}"
            )

    # Determine overall status
    if not pattern_correct:
        issues.append(
            f"Rule pattern '{matched_rule.get('pattern')}' "
            f"doesn't match optimally. Discovered better pattern: "
            f"{discovered_pattern.type.value}={discovered_pattern.value}"
        )
        suggestions.append(
            f"Update rule pattern to: {discovered_pattern.type.value}={discovered_pattern.value}"
        )
        return RuleStatus.PATTERN_BROKEN, issues, suggestions

    if not workspace_correct:
        return RuleStatus.WORKSPACE_WRONG, issues, suggestions

    return RuleStatus.CORRECT, [], []


def check_pattern_correctness(
    window: Window,
    discovered_pattern: Pattern,
    matched_rule: Dict
) -> bool:
    """
    Check if the existing rule's pattern is optimal.

    Returns:
        True if rule pattern is correct/optimal
    """
    rule_pattern = matched_rule.get("pattern", "")

    # Handle title: prefix patterns from daemon
    if rule_pattern.startswith("title:"):
        rule_title_pattern = rule_pattern[6:]  # Remove "title:" prefix

        # If discovered pattern is also title-based, compare values
        if discovered_pattern.type == PatternType.TITLE:
            # Handle regex patterns (^)
            if rule_title_pattern.startswith("^"):
                # Regex pattern - if it matches the window, it's correct
                import re
                try:
                    if re.match(rule_title_pattern, window.title):
                        return True
                except:
                    pass

            # Substring pattern - check if they match
            if rule_title_pattern.lower() in discovered_pattern.value.lower() or \
               discovered_pattern.value.lower() in rule_title_pattern.lower():
                return True

        return False

    # Compare discovered pattern with rule pattern
    if discovered_pattern.type == PatternType.CLASS:
        # Class-based pattern is optimal
        if rule_pattern == discovered_pattern.value:
            return True
        return False

    if discovered_pattern.type == PatternType.TITLE:
        # Title-based pattern (for terminals)
        if rule_pattern.lower() in discovered_pattern.value.lower():
            return True
        return False

    # Default: rule is acceptable
    return True


def calculate_statistics(results: List[ComparisonResult], total_rules: int) -> Dict[str, any]:
    """
    Calculate statistics from comparison results.

    Returns:
        Dictionary with counts and percentages
    """
    correct = sum(1 for r in results if r.status == RuleStatus.CORRECT)
    pattern_broken = sum(1 for r in results if r.status == RuleStatus.PATTERN_BROKEN)
    workspace_wrong = sum(1 for r in results if r.status == RuleStatus.WORKSPACE_WRONG)
    missing = sum(1 for r in results if r.status == RuleStatus.MISSING)

    total_analyzed = len(results)
    total_issues = pattern_broken + workspace_wrong + missing

    return {
        "correct": correct,
        "pattern_broken": pattern_broken,
        "workspace_wrong": workspace_wrong,
        "missing": missing,
        "total_analyzed": total_analyzed,
        "total_issues": total_issues,
        "total_rules": total_rules,
        "accuracy_percentage": round((correct / total_analyzed * 100) if total_analyzed > 0 else 0, 1),
    }


def format_comparison_report(comparison_data: Dict[str, any], verbose: bool = False) -> str:
    """
    Format comparison results as human-readable report.

    Args:
        comparison_data: Output from compare_with_existing_rules()
        verbose: Include detailed per-window analysis

    Returns:
        Formatted report string
    """
    if not comparison_data.get("success"):
        return f"Error: {comparison_data.get('error', 'Unknown error')}"

    stats = comparison_data["statistics"]
    results = comparison_data["results"]

    lines = []
    lines.append("\nWindow Rules Comparison Report")
    lines.append("=" * 80)
    lines.append("")

    # Statistics summary
    lines.append("Summary:")
    lines.append(f"  Total window rules:      {stats['total_rules']}")
    lines.append(f"  Windows analyzed:        {stats['total_analyzed']}")
    lines.append(f"  Accuracy:                {stats['accuracy_percentage']}%")
    lines.append("")

    lines.append("Status Breakdown:")
    lines.append(f"  ✓ Correct:               {stats['correct']}")
    lines.append(f"  ✗ Pattern broken:        {stats['pattern_broken']}")
    lines.append(f"  ⚠ Workspace wrong:       {stats['workspace_wrong']}")
    lines.append(f"  ○ Missing rule:          {stats['missing']}")
    lines.append("")

    # Issues section
    if stats['total_issues'] > 0:
        lines.append(f"Issues Found ({stats['total_issues']}):")
        lines.append("-" * 80)

        issue_num = 1
        for result in results:
            if result.status == RuleStatus.CORRECT:
                continue

            status_icon = {
                RuleStatus.PATTERN_BROKEN: "✗",
                RuleStatus.WORKSPACE_WRONG: "⚠",
                RuleStatus.MISSING: "○",
            }.get(result.status, "?")

            lines.append(f"\n{issue_num}. {status_icon} {result.window.window_class}")
            lines.append(f"   Title: {result.window.title[:60]}")
            lines.append(f"   Current workspace: {result.window.workspace_num}")

            if result.matched_rule:
                rule_desc = result.matched_rule.get('description', result.matched_rule.get('pattern', 'Unknown'))
                lines.append(f"   Existing rule: {rule_desc}")
                rule_ws = result.matched_rule.get('workspace')
                if rule_ws:
                    lines.append(f"   Expected workspace: {rule_ws}")

            lines.append(f"   Discovered pattern: {result.discovered_pattern.type.value}={result.discovered_pattern.value}")

            if result.issues:
                for issue in result.issues:
                    lines.append(f"   Issue: {issue}")

            if result.suggestions:
                for suggestion in result.suggestions:
                    lines.append(f"   → {suggestion}")

            issue_num += 1

        lines.append("-" * 80)
    else:
        lines.append("✓ All rules are correctly configured!")

    # Verbose details
    if verbose and stats['correct'] > 0:
        lines.append("\nCorrectly Configured Rules:")
        lines.append("-" * 80)
        for result in results:
            if result.status == RuleStatus.CORRECT:
                lines.append(f"  ✓ {result.window.window_class} → WS{result.window.workspace_num}")
        lines.append("-" * 80)

    lines.append("")
    return "\n".join(lines)
