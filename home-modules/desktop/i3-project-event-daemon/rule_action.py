"""Structured action types for window rules.

This module defines typed action objects for window management rules,
replacing string-based commands with structured, validated action types.

Feature 024: Dynamic Window Management System
"""

from dataclasses import dataclass
from typing import Literal, Union


@dataclass
class WorkspaceAction:
    """Move window to a specific workspace.

    Corresponds to i3 command: `move container to workspace number <target>`
    """

    type: Literal["workspace"] = "workspace"
    target: int = 1  # Workspace number (1-9)

    def __post_init__(self) -> None:
        """Validate workspace target."""
        if not isinstance(self.target, int):
            raise TypeError(f"Workspace target must be int, got {type(self.target)}")
        if not (1 <= self.target <= 9):
            raise ValueError(f"Workspace target must be 1-9, got {self.target}")


@dataclass
class MarkAction:
    """Add an i3 mark to the window for tracking.

    Corresponds to i3 command: `mark <value>`
    Marks are used for project association and window identification.
    """

    type: Literal["mark"] = "mark"
    value: str = ""  # Mark identifier (alphanumeric, underscore, hyphen only)

    def __post_init__(self) -> None:
        """Validate mark value."""
        if not self.value:
            raise ValueError("Mark value cannot be empty")
        if not isinstance(self.value, str):
            raise TypeError(f"Mark value must be str, got {type(self.value)}")

        # Validate mark format: alphanumeric, underscore, hyphen
        import re
        if not re.match(r"^[a-zA-Z0-9_-]+$", self.value):
            raise ValueError(
                f"Mark value must contain only alphanumeric, underscore, and hyphen characters: '{self.value}'"
            )


@dataclass
class FloatAction:
    """Set window floating state.

    Corresponds to i3 commands:
    - `floating enable` (enable=True)
    - `floating disable` (enable=False)
    """

    type: Literal["float"] = "float"
    enable: bool = True  # True = floating, False = tiled

    def __post_init__(self) -> None:
        """Validate enable flag."""
        if not isinstance(self.enable, bool):
            raise TypeError(f"Float enable must be bool, got {type(self.enable)}")


@dataclass
class LayoutAction:
    """Set container layout mode.

    Corresponds to i3 command: `layout <mode>`
    Affects the container that holds this window.
    """

    type: Literal["layout"] = "layout"
    mode: str = "tabbed"  # Layout mode: tabbed, stacked, splitv, splith

    VALID_MODES = {"tabbed", "stacked", "splitv", "splith"}

    def __post_init__(self) -> None:
        """Validate layout mode."""
        if not isinstance(self.mode, str):
            raise TypeError(f"Layout mode must be str, got {type(self.mode)}")
        if self.mode not in self.VALID_MODES:
            raise ValueError(
                f"Layout mode must be one of {self.VALID_MODES}, got '{self.mode}'"
            )


# Union type for all action types (discriminated union on 'type' field)
RuleAction = Union[WorkspaceAction, MarkAction, FloatAction, LayoutAction]


def action_from_dict(data: dict) -> RuleAction:
    """Parse action from dictionary (JSON deserialization).

    Args:
        data: Dictionary with 'type' field and action-specific fields

    Returns:
        Parsed action object

    Raises:
        ValueError: If action type is unknown or data is invalid

    Example:
        >>> action_from_dict({"type": "workspace", "target": 2})
        WorkspaceAction(type='workspace', target=2)
    """
    action_type = data.get("type")

    if action_type == "workspace":
        return WorkspaceAction(target=data["target"])
    elif action_type == "mark":
        return MarkAction(value=data["value"])
    elif action_type == "float":
        return FloatAction(enable=data["enable"])
    elif action_type == "layout":
        return LayoutAction(mode=data["mode"])
    else:
        raise ValueError(f"Unknown action type: {action_type}")


def action_to_dict(action: RuleAction) -> dict:
    """Serialize action to dictionary (JSON serialization).

    Args:
        action: Action object to serialize

    Returns:
        Dictionary representation

    Example:
        >>> action_to_dict(WorkspaceAction(target=2))
        {'type': 'workspace', 'target': 2}
    """
    if isinstance(action, WorkspaceAction):
        return {"type": "workspace", "target": action.target}
    elif isinstance(action, MarkAction):
        return {"type": "mark", "value": action.value}
    elif isinstance(action, FloatAction):
        return {"type": "float", "enable": action.enable}
    elif isinstance(action, LayoutAction):
        return {"type": "layout", "mode": action.mode}
    else:
        raise ValueError(f"Unknown action type: {type(action)}")
