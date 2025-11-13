"""Integration tests for Feature 073 - User Story 5: Project Navigation.

Tests project navigation integration with new window actions from User Story 4.
Verifies colon prefix doesn't conflict with sub-mode workflows.
"""
import pytest
import sys
from pathlib import Path

# Add sway-workspace-panel to path for imports
WORKSPACE_PANEL_DIR = Path("/etc/nixos/home-modules/tools/sway-workspace-panel")
sys.path.insert(0, str(WORKSPACE_PANEL_DIR))

from sub_mode_manager import SubMode, SubModeContext
from keyboard_hint_manager import KeyboardHints


def test_project_hints_visible_in_normal_mode():
    """Test ': Project' hint is visible in normal mode.

    Verifies keyboard hints show project navigation option when not in sub-mode.
    Both window and workspace heading selections should show ': Project'.
    """
    context = SubModeContext(current_mode=SubMode.NORMAL)

    # Window selected - should show ': Project' among other hints
    hints_window = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )
    assert ": Project" in hints_window
    assert "↑/↓ Navigate" in hints_window
    assert "Delete Close" in hints_window
    assert "M Move" in hints_window
    assert "F Float" in hints_window

    # Workspace heading selected - should also show ': Project'
    hints_heading = KeyboardHints.generate_hints(
        selection_type="workspace_heading",
        sub_mode_context=context
    )
    assert ": Project" in hints_heading
    assert "↑/↓ Navigate" in hints_heading
    # No window-specific actions
    assert "Delete Close" not in hints_heading
    assert "M Move" not in hints_heading


def test_project_hints_hidden_in_move_window_sub_mode():
    """Test ': Project' hint is hidden during move window sub-mode.

    When in MOVE_WINDOW sub-mode, hints should show workspace digit entry,
    NOT project navigation option.
    """
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)
    context.add_digit("2")
    context.add_digit("3")

    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )

    # Sub-mode hints take precedence
    assert "Type workspace:" in hints
    assert "23_" in hints  # Accumulated digits with cursor
    assert "Confirm" in hints
    assert "Cancel" in hints

    # Project navigation NOT shown during sub-mode
    assert ": Project" not in hints


def test_project_hints_hidden_in_mark_window_sub_mode():
    """Test ': Project' hint is hidden during mark window sub-mode.

    When in MARK_WINDOW sub-mode, hints should show mark name entry,
    NOT project navigation option.
    """
    context = SubModeContext(current_mode=SubMode.MARK_WINDOW)
    for char in "todo":
        context.add_character(char)

    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )

    # Sub-mode hints take precedence
    assert "Type mark:" in hints
    assert "todo_" in hints  # Accumulated chars with cursor
    assert "Confirm" in hints
    assert "Cancel" in hints

    # Project navigation NOT shown during sub-mode
    assert ": Project" not in hints


def test_colon_character_not_captured_by_sub_modes():
    """Test colon character is not captured by sub-mode state machines.

    Verifies colon (':') is not valid input for MOVE_WINDOW or MARK_WINDOW,
    ensuring it can be handled by i3pm daemon for project mode transition.
    """
    # MOVE_WINDOW mode only accepts digits 0-9
    move_context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)
    result = move_context.add_digit(":")  # Colon is not a digit
    assert result is False
    assert move_context.accumulated_input == ""
    assert move_context.target_workspace is None

    # MARK_WINDOW mode accepts alphanumeric + underscore + hyphen only
    mark_context = SubModeContext(current_mode=SubMode.MARK_WINDOW)
    result = mark_context.add_character(":")  # Colon is not alphanumeric/underscore/hyphen
    assert result is False
    assert mark_context.accumulated_input == ""
    assert mark_context.mark_name is None


def test_escape_from_sub_mode_returns_to_normal_with_project_hints():
    """Test Escape from sub-mode returns to NORMAL with full hints restored.

    After cancelling a sub-mode workflow, user should see normal mode hints
    including ': Project' option.
    """
    context = SubModeContext()

    # Enter move mode
    context.enter_sub_mode(SubMode.MOVE_WINDOW)
    context.add_digit("5")

    # Verify sub-mode hints (no project option)
    hints_sub_mode = KeyboardHints.generate_hints("window", context)
    assert ": Project" not in hints_sub_mode

    # Cancel sub-mode (Escape key)
    context.reset_to_normal()

    # Verify normal hints restored (project option visible)
    hints_normal = KeyboardHints.generate_hints("window", context)
    assert ": Project" in hints_normal
    assert "M Move" in hints_normal
    assert "F Float" in hints_normal
    assert context.current_mode == SubMode.NORMAL


def test_project_navigation_available_after_window_action():
    """Test project navigation is available after completing window action.

    After executing window actions (move/float/mark), user should be able to
    use ': Project' to switch to project mode without conflict.
    """
    context = SubModeContext()

    # Execute move window action
    context.enter_sub_mode(SubMode.MOVE_WINDOW)
    context.add_digit("2")
    context.add_digit("3")
    assert context.can_execute()

    # Simulate action completion (daemon would call reset_to_normal)
    context.reset_to_normal()

    # Verify normal mode with project option
    assert context.current_mode == SubMode.NORMAL
    hints = KeyboardHints.generate_hints("window", context)
    assert ": Project" in hints

    # Colon is not captured by sub-mode logic
    result = context.add_digit(":")  # Should return False (not a valid digit)
    assert result is False
    result = context.add_character(":")  # Should return False (not valid char)
    assert result is False
