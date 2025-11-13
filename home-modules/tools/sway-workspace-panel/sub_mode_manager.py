"""Sub-mode state machine for Feature 073: Eww Interactive Menu Stabilization.

This module manages multi-step window actions that require additional user input
after the initial key press (e.g., move window requires target workspace number).

Sub-Modes:
- NORMAL: Default mode - all standard actions available
- MOVE_WINDOW: Collecting workspace digits (1-70) for window move
- MARK_WINDOW: Collecting mark name for window marking

State Machine:
    NORMAL --M--> MOVE_WINDOW --Enter--> NORMAL (execute move)
    NORMAL --Mark--> MARK_WINDOW --Enter--> NORMAL (execute mark)
    Any Mode --Escape--> NORMAL (cancel)

User Story 4 (P3): Additional per-window actions with multi-step workflows.

Architecture:
- State machine pattern with explicit transitions
- Digit/character accumulation during sub-modes
- Validation of accumulated input (workspace 1-70, mark name 1-50 chars)
- Escape key always returns to NORMAL mode

Performance:
- <10ms state transition overhead
- <50ms visual feedback for mode changes
"""

from __future__ import annotations

from typing import Optional
from enum import Enum

from pydantic import BaseModel, Field, field_validator


class SubMode(Enum):
    """Sub-modes for multi-step window actions.

    Re-exported from keyboard_hint_manager for consistency.
    """
    NORMAL = "normal"
    MOVE_WINDOW = "move_window"
    MARK_WINDOW = "mark_window"


class SubModeContext(BaseModel):
    """Context for sub-mode state and accumulated input.

    This is the primary state container for sub-mode operations. It tracks:
    - Current sub-mode (NORMAL, MOVE_WINDOW, MARK_WINDOW)
    - Accumulated user input (digits for workspace, characters for mark name)
    - Parsed/validated values (target_workspace, mark_name)

    State transitions are managed via methods:
    - enter_sub_mode(): Transition to a new sub-mode
    - reset_to_normal(): Return to NORMAL mode (cancel or complete)
    - add_digit(): Accumulate digit input (MOVE_WINDOW mode)
    - add_character(): Accumulate character input (MARK_WINDOW mode)
    """
    current_mode: SubMode = Field(default=SubMode.NORMAL, description="Active sub-mode")
    accumulated_input: str = Field(default="", description="Raw input string")
    target_workspace: Optional[int] = Field(default=None, description="Parsed workspace (1-70)")
    mark_name: Optional[str] = Field(default=None, description="Validated mark name (1-50 chars)")

    @field_validator('accumulated_input')
    @classmethod
    def validate_input_length(cls, v: str) -> str:
        """Limit accumulated input to 50 characters."""
        if len(v) > 50:
            raise ValueError("Accumulated input exceeds 50 character limit")
        return v

    def enter_sub_mode(self, mode: SubMode) -> None:
        """Transition to a sub-mode.

        Clears any previous accumulated input and resets parsed values.

        Args:
            mode: Target sub-mode to enter

        Example:
            context = SubModeContext()
            context.enter_sub_mode(SubMode.MOVE_WINDOW)
            context.add_digit("2")
            context.add_digit("3")
            # context.accumulated_input == "23"
            # context.target_workspace == 23
        """
        self.current_mode = mode
        self.accumulated_input = ""
        self.target_workspace = None
        self.mark_name = None

    def reset_to_normal(self) -> None:
        """Exit sub-mode and return to NORMAL mode.

        Clears all accumulated state. Called when:
        - User presses Escape (cancel)
        - Action completes successfully (e.g., move window executed)
        - Error occurs during action (cleanup)

        Example:
            context.enter_sub_mode(SubMode.MOVE_WINDOW)
            context.add_digit("5")
            context.reset_to_normal()
            assert context.current_mode == SubMode.NORMAL
            assert context.accumulated_input == ""
        """
        self.current_mode = SubMode.NORMAL
        self.accumulated_input = ""
        self.target_workspace = None
        self.mark_name = None

    def add_digit(self, digit: str) -> bool:
        """Add digit to accumulated input (for MOVE_WINDOW mode).

        Validates digit character and workspace range (1-70). Only accumulates
        valid digits that keep workspace number within range.

        Args:
            digit: Single digit character ('0'-'9')

        Returns:
            True if digit accepted, False if rejected (invalid or out of range)

        Example:
            context.enter_sub_mode(SubMode.MOVE_WINDOW)
            context.add_digit("2")  # Returns True, accumulated_input = "2"
            context.add_digit("3")  # Returns True, accumulated_input = "23"
            context.add_digit("9")  # Returns False, would make 239 (>70)
        """
        if self.current_mode != SubMode.MOVE_WINDOW:
            return False

        # Validate digit character
        if not digit.isdigit():
            return False

        # Check if accumulating this digit would exceed workspace range (1-70)
        potential_input = self.accumulated_input + digit
        try:
            workspace_num = int(potential_input)
            if workspace_num < 1 or workspace_num > 70:
                return False
        except ValueError:
            return False

        # Accept digit
        self.accumulated_input = potential_input
        self.target_workspace = workspace_num
        return True

    def add_character(self, char: str) -> bool:
        """Add character to accumulated input (for MARK_WINDOW mode).

        Validates character (alphanumeric + underscore only) and length (1-50 chars).

        Args:
            char: Single character

        Returns:
            True if character accepted, False if rejected (invalid or too long)

        Example:
            context.enter_sub_mode(SubMode.MARK_WINDOW)
            context.add_character("t")  # Returns True, accumulated_input = "t"
            context.add_character("o")  # Returns True, accumulated_input = "to"
            context.add_character("d")  # Returns True, accumulated_input = "tod"
            context.add_character("o")  # Returns True, accumulated_input = "todo"
            assert context.mark_name == "todo"
        """
        if self.current_mode != SubMode.MARK_WINDOW:
            return False

        # Validate character (alphanumeric + underscore + hyphen)
        if not (char.isalnum() or char in ('_', '-')):
            return False

        # Check length limit
        if len(self.accumulated_input) >= 50:
            return False

        # Accept character
        self.accumulated_input += char

        # Mark name is valid if 1-50 characters
        if 1 <= len(self.accumulated_input) <= 50:
            self.mark_name = self.accumulated_input
        else:
            self.mark_name = None

        return True

    def can_execute(self) -> bool:
        """Check if sub-mode has valid input for execution.

        Returns:
            True if Enter key should execute action, False if incomplete/invalid

        Example:
            context.enter_sub_mode(SubMode.MOVE_WINDOW)
            assert not context.can_execute()  # No digits yet
            context.add_digit("2")
            context.add_digit("3")
            assert context.can_execute()  # Valid workspace 23
        """
        if self.current_mode == SubMode.NORMAL:
            return False  # No action to execute

        if self.current_mode == SubMode.MOVE_WINDOW:
            return self.target_workspace is not None

        if self.current_mode == SubMode.MARK_WINDOW:
            return self.mark_name is not None and len(self.mark_name) > 0

        return False

    def get_action_params(self) -> Optional[dict]:
        """Get parameters for action execution.

        Returns:
            Dict with action-specific parameters, or None if cannot execute

        Example:
            context.enter_sub_mode(SubMode.MOVE_WINDOW)
            context.add_digit("2")
            context.add_digit("3")
            params = context.get_action_params()
            # Returns: {"target_workspace": 23}
        """
        if not self.can_execute():
            return None

        if self.current_mode == SubMode.MOVE_WINDOW:
            return {"target_workspace": self.target_workspace}

        if self.current_mode == SubMode.MARK_WINDOW:
            return {"mark_name": self.mark_name}

        return None


class SubModeManager:
    """Manager for sub-mode state machine.

    This is a higher-level wrapper around SubModeContext that provides
    convenience methods and state validation. In practice, most code will
    interact directly with SubModeContext, but this manager can be useful
    for complex workflows or testing.

    Example:
        manager = SubModeManager()
        manager.enter_move_mode()
        manager.handle_digit("2")
        manager.handle_digit("3")
        if manager.can_execute():
            workspace = manager.context.target_workspace
            # Execute move window to workspace 23
            manager.reset()
    """

    def __init__(self):
        """Initialize sub-mode manager with NORMAL mode."""
        self.context = SubModeContext()

    def enter_move_mode(self) -> None:
        """Enter MOVE_WINDOW sub-mode."""
        self.context.enter_sub_mode(SubMode.MOVE_WINDOW)

    def enter_mark_mode(self) -> None:
        """Enter MARK_WINDOW sub-mode."""
        self.context.enter_sub_mode(SubMode.MARK_WINDOW)

    def reset(self) -> None:
        """Return to NORMAL mode."""
        self.context.reset_to_normal()

    def handle_digit(self, digit: str) -> bool:
        """Handle digit input in current mode.

        Args:
            digit: Single digit character

        Returns:
            True if accepted, False if rejected
        """
        return self.context.add_digit(digit)

    def handle_character(self, char: str) -> bool:
        """Handle character input in current mode.

        Args:
            char: Single character

        Returns:
            True if accepted, False if rejected
        """
        return self.context.add_character(char)

    def can_execute(self) -> bool:
        """Check if current sub-mode has valid input for execution."""
        return self.context.can_execute()

    def get_current_mode(self) -> SubMode:
        """Get current sub-mode."""
        return self.context.current_mode

    def is_normal_mode(self) -> bool:
        """Check if in NORMAL mode."""
        return self.context.current_mode == SubMode.NORMAL
