"""Keyboard shortcut hint generation for Feature 073: Eww Interactive Menu Stabilization.

This module generates context-aware keyboard shortcut help text displayed at the
bottom of the workspace preview card. The hints change based on:
- Current selection (workspace heading vs window)
- Sub-mode state (normal, move window, mark window)
- Available actions for the selected item

User Story 3 (P2): Visual feedback for available actions with <50ms update latency.

Architecture:
- Pure function design (no state)
- Hint generation based on SelectionState and SubModeContext
- Compact hint format for space-constrained UI
- UTF-8 symbols for visual clarity (→, ⇒, |)

Performance:
- <5ms hint generation time
- <50ms total latency from selection change to UI update
"""

from __future__ import annotations

from typing import Optional, List
from enum import Enum

from pydantic import BaseModel, Field


class SubMode(Enum):
    """Sub-modes for multi-step window actions.

    Sub-modes temporarily change keyboard input behavior to collect additional
    parameters (e.g., target workspace number for move action).
    """
    NORMAL = "normal"  # Default mode - all standard actions available
    MOVE_WINDOW = "move_window"  # Collecting workspace digits for move
    MARK_WINDOW = "mark_window"  # Collecting mark name for window marking


class SubModeContext(BaseModel):
    """Context for sub-mode state and accumulated input.

    Used by keyboard hint manager to generate appropriate help text for
    the current sub-mode.
    """
    current_mode: SubMode = Field(default=SubMode.NORMAL, description="Active sub-mode")
    accumulated_input: str = Field(default="", description="Digits/text entered so far")
    target_workspace: Optional[int] = Field(default=None, description="Parsed workspace number (move mode)")

    def enter_sub_mode(self, mode: SubMode) -> None:
        """Transition to a sub-mode.

        Args:
            mode: Target sub-mode to enter
        """
        self.current_mode = mode
        self.accumulated_input = ""
        self.target_workspace = None

    def reset_to_normal(self) -> None:
        """Exit sub-mode and return to normal mode."""
        self.current_mode = SubMode.NORMAL
        self.accumulated_input = ""
        self.target_workspace = None

    def add_digit(self, digit: str) -> None:
        """Add digit to accumulated input (for move window mode).

        Args:
            digit: Single digit character ('0'-'9')
        """
        self.accumulated_input += digit

        # Try to parse workspace number (1-70 range)
        try:
            workspace_num = int(self.accumulated_input)
            if 1 <= workspace_num <= 70:
                self.target_workspace = workspace_num
            else:
                self.target_workspace = None
        except ValueError:
            self.target_workspace = None


class KeyboardHintSet(BaseModel):
    """Set of keyboard hints for display.

    Formatted for Eww label widget with compact hint notation.
    """
    hints: List[str] = Field(..., description="List of hint strings")

    def format(self) -> str:
        """Format hints as compact string with pipe separators.

        Returns:
            Formatted string like "↑/↓ Navigate | Enter Select | Delete Close | Esc Cancel"
        """
        return " | ".join(self.hints)


class KeyboardHints:
    """Generate context-aware keyboard shortcut hints.

    This is a stateless utility class that generates hint text based on current
    selection and mode context.

    Hint Notation:
    - Key names: Delete, Enter, Esc, M, F, : (concise uppercase/symbols)
    - Actions: Navigate, Select, Close, Move, Float, Project, Cancel (verbs)
    - Separators: | (pipe) for distinct actions, / (slash) for alternatives (↑/↓)
    - Mode prefixes: "Type workspace: 23_" for input collection modes

    Examples:
        # Window selected, normal mode:
        "↑/↓ Navigate | Enter Select | Delete Close | M Move | F Float | : Project | Esc Cancel"

        # Workspace heading selected:
        "↑/↓ Navigate | Enter Select | : Project | Esc Cancel"

        # Move window sub-mode (collecting workspace):
        "Type workspace: 23_ | Enter Confirm | Esc Cancel"
    """

    @staticmethod
    def generate_hints(
        selection_type: str,  # "workspace_heading" or "window"
        sub_mode_context: SubModeContext
    ) -> str:
        """Generate context-aware keyboard hints.

        Args:
            selection_type: Type of currently selected item
            sub_mode_context: Current sub-mode and accumulated input

        Returns:
            Formatted hint string for display

        Example:
            from selection_models.selection_state import SelectionState
            state = SelectionState(item_type="window", ...)
            context = SubModeContext(current_mode=SubMode.NORMAL)
            hints = KeyboardHints.generate_hints(state.item_type, context)
            # Returns: "↑/↓ Navigate | Enter Select | Delete Close | ..."
        """
        # Sub-mode overrides normal hints
        if sub_mode_context.current_mode == SubMode.MOVE_WINDOW:
            return KeyboardHints._generate_move_window_hints(sub_mode_context)
        elif sub_mode_context.current_mode == SubMode.MARK_WINDOW:
            return KeyboardHints._generate_mark_window_hints(sub_mode_context)

        # Normal mode hints depend on selection type
        if selection_type == "window":
            return KeyboardHints._generate_window_hints()
        else:  # workspace_heading
            return KeyboardHints._generate_heading_hints()

    @staticmethod
    def _generate_window_hints() -> str:
        """Generate hints when a window is selected.

        Windows support all actions: navigate, select, close, move, float, project, cancel.
        """
        hint_set = KeyboardHintSet(hints=[
            "↑/↓ Navigate",
            "Enter Select",
            "Delete Close",
            "M Move",
            "F Float",
            ": Project",
            "Esc Cancel"
        ])
        return hint_set.format()

    @staticmethod
    def _generate_heading_hints() -> str:
        """Generate hints when a workspace heading is selected.

        Headings only support: navigate, select (focus workspace), project, cancel.
        No window-specific actions (Close, Move, Float).
        """
        hint_set = KeyboardHintSet(hints=[
            "↑/↓ Navigate",
            "Enter Select",
            ": Project",
            "Esc Cancel"
        ])
        return hint_set.format()

    @staticmethod
    def _generate_move_window_hints(context: SubModeContext) -> str:
        """Generate hints for move window sub-mode.

        Shows accumulated workspace digits and confirmation options.

        Args:
            context: Sub-mode context with accumulated input

        Returns:
            Hint like "Type workspace: 23_ | Enter Confirm | Esc Cancel"
        """
        workspace_display = context.accumulated_input + "_"
        hint_set = KeyboardHintSet(hints=[
            f"Type workspace: {workspace_display}",
            "Enter Confirm",
            "Esc Cancel"
        ])
        return hint_set.format()

    @staticmethod
    def _generate_mark_window_hints(context: SubModeContext) -> str:
        """Generate hints for mark window sub-mode.

        Shows accumulated mark name and confirmation options.

        Args:
            context: Sub-mode context with accumulated input

        Returns:
            Hint like "Type mark: todo_ | Enter Confirm | Esc Cancel"
        """
        mark_display = context.accumulated_input + "_"
        hint_set = KeyboardHintSet(hints=[
            f"Type mark: {mark_display}",
            "Enter Confirm",
            "Esc Cancel"
        ])
        return hint_set.format()
