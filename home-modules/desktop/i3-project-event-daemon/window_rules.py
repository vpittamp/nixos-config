"""Window rule management for dynamic window classification."""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, List, Literal

# Import PatternRule from local pattern module (copied from i3pm)
from .pattern import PatternRule

# Import structured action types (Feature 024)
from .rule_action import RuleAction, action_from_dict, action_to_dict


@dataclass
class WindowRule:
    """Window classification rule with pattern matching and actions.

    Feature 024 Enhancement: Now supports structured actions (actions field) in addition
    to legacy format (workspace + command fields). Both formats are supported for
    backwards compatibility.

    Attributes:
        pattern_rule: PatternRule instance for window class matching
        workspace: Optional target workspace (1-9) - LEGACY FORMAT
        command: Optional i3 command to execute when rule matches - LEGACY FORMAT
        actions: Optional list of structured actions - NEW FORMAT (Feature 024)
        modifier: Optional rule modifier (GLOBAL, DEFAULT, ON_CLOSE, TITLE)
        blacklist: List of window classes to exclude (only for GLOBAL modifier)

    Format Detection:
        - If `actions` is provided: Use structured actions (new format)
        - If `workspace` or `command` is provided: Use legacy format
        - Both formats supported during transition period

    Examples:
        Legacy format (still works):
        >>> from i3_project_manager.models.pattern import PatternRule
        >>> pattern = PatternRule("Code", "scoped", priority=250)
        >>> rule = WindowRule(pattern, workspace=2, command="floating disable")
        >>> rule.matches("Code")
        True

        New format (Feature 024):
        >>> from .rule_action import WorkspaceAction, LayoutAction
        >>> pattern = PatternRule("Code", "scoped", priority=250)
        >>> actions = [WorkspaceAction(target=2), LayoutAction(mode="tabbed")]
        >>> rule = WindowRule(pattern, actions=actions)
        >>> rule.actions
        [WorkspaceAction(type='workspace', target=2), LayoutAction(type='layout', mode='tabbed')]
    """

    pattern_rule: PatternRule
    workspace: Optional[int] = None  # Legacy format
    command: Optional[str] = None  # Legacy format
    actions: Optional[List[RuleAction]] = None  # New format (Feature 024)
    modifier: Optional[Literal["GLOBAL", "DEFAULT", "ON_CLOSE", "TITLE"]] = None
    blacklist: List[str] = field(default_factory=list)

    def __post_init__(self):
        """Validate window rule configuration."""
        if self.workspace is not None and not (1 <= self.workspace <= 99):
            raise ValueError(
                f"Workspace must be 1-99, got {self.workspace}"
            )

        valid_modifiers = ["GLOBAL", "DEFAULT", "ON_CLOSE", "TITLE"]
        if self.modifier and self.modifier not in valid_modifiers:
            raise ValueError(
                f"Invalid modifier: {self.modifier}. "
                f"Must be one of: {', '.join(valid_modifiers)}"
            )

        if self.blacklist and self.modifier != "GLOBAL":
            raise ValueError(
                "Blacklist only valid with GLOBAL modifier"
            )

    def matches(self, window_class: str, window_title: str = "") -> bool:
        """Check if this rule matches the window.

        Args:
            window_class: Window WM_CLASS to match against
            window_title: Optional window title for title-based patterns

        Returns:
            True if rule matches window, False otherwise
        """
        # Check pattern match (pass both class and title)
        if not self.pattern_rule.matches(window_class, window_title):
            return False

        # Check blacklist (for GLOBAL rules)
        if self.modifier == "GLOBAL" and window_class in self.blacklist:
            return False

        return True

    @property
    def priority(self) -> int:
        """Get priority from pattern rule for sorting."""
        return self.pattern_rule.priority

    @property
    def scope(self) -> str:
        """Get scope from pattern rule."""
        return self.pattern_rule.scope

    def to_json(self) -> dict:
        """Serialize to JSON-compatible dict.

        Supports both legacy format (workspace + command) and new format (actions).
        """
        result = {
            "pattern_rule": {
                "pattern": self.pattern_rule.pattern,
                "scope": self.pattern_rule.scope,
                "priority": self.pattern_rule.priority,
                "description": self.pattern_rule.description,
            }
        }

        # Legacy format fields
        if self.workspace is not None:
            result["workspace"] = self.workspace
        if self.command:
            result["command"] = self.command

        # New format field (Feature 024)
        if self.actions is not None:
            result["actions"] = [action_to_dict(action) for action in self.actions]

        # Common fields
        if self.modifier:
            result["modifier"] = self.modifier
        if self.blacklist:
            result["blacklist"] = self.blacklist

        return result

    @classmethod
    def from_json(cls, data: dict) -> "WindowRule":
        """Deserialize from JSON-compatible dict.

        Supports both legacy format (workspace + command) and new format (actions).
        Format is auto-detected based on presence of 'actions' field.

        Args:
            data: Dictionary with window rule fields

        Returns:
            WindowRule instance

        Raises:
            ValueError: If data is invalid or missing required fields
        """
        if "pattern_rule" not in data:
            raise ValueError("Missing required 'pattern_rule' field")

        pattern_data = data["pattern_rule"]
        pattern_rule = PatternRule(
            pattern=pattern_data["pattern"],
            scope=pattern_data["scope"],
            priority=pattern_data.get("priority", 0),
            description=pattern_data.get("description", ""),
        )

        # Parse actions if present (new format)
        actions = None
        if "actions" in data:
            actions = [action_from_dict(action_data) for action_data in data["actions"]]

        return cls(
            pattern_rule=pattern_rule,
            workspace=data.get("workspace"),  # Legacy format
            command=data.get("command"),  # Legacy format
            actions=actions,  # New format (Feature 024)
            modifier=data.get("modifier"),
            blacklist=data.get("blacklist", []),
        )


def load_window_rules(config_path: str) -> List[WindowRule]:
    """Load window rules from JSON file.

    Args:
        config_path: Path to window-rules.json file

    Returns:
        List of WindowRule objects sorted by priority (highest first).
        Returns empty list if file doesn't exist.

    Examples:
        >>> rules = load_window_rules("~/.config/i3/window-rules.json")
        >>> len(rules)
        5
        >>> rules[0].priority  # Highest priority first
        300
    """
    path = Path(config_path).expanduser()

    # Return empty list if file doesn't exist
    if not path.exists():
        return []

    try:
        with open(path, "r") as f:
            data = json.load(f)

        if not isinstance(data, list):
            raise ValueError("window-rules.json must be a JSON array")

        rules = [WindowRule.from_json(item) for item in data]

        # Sort by priority (highest first) for efficient matching
        rules.sort(key=lambda r: r.priority, reverse=True)

        return rules

    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in {config_path}: {e}")
    except KeyError as e:
        raise ValueError(f"Missing required field in window rule: {e}")
    except ValueError as e:
        # Re-raise with context
        raise ValueError(f"Error loading window rules from {config_path}: {e}")
