"""Integration tests for Feature 073 - User Story 4: Sub-Mode Workflows.

Tests move window workflow end-to-end with sub-mode entry, digit accumulation,
and execution.

NOTE: These tests verify the core data structures and logic. The actual daemon
integration is tested via sway-test framework (test_window_move.json).
"""
import pytest
import sys
from pathlib import Path

# Add sway-workspace-panel to path for imports
WORKSPACE_PANEL_DIR = Path("/etc/nixos/home-modules/tools/sway-workspace-panel")
sys.path.insert(0, str(WORKSPACE_PANEL_DIR))

from sub_mode_manager import SubMode, SubModeContext
from keyboard_hint_manager import KeyboardHints


def test_move_window_workflow_complete():
    """Test complete move window workflow: enter mode → add digits → confirm.

    Simulates:
    1. User presses M (enter move mode)
    2. User types 2, 3 (accumulate workspace number)
    3. User presses Enter (confirm move)
    """
    context = SubModeContext()

    # Step 1: Enter move mode (triggered by M key)
    context.enter_sub_mode(SubMode.MOVE_WINDOW)
    assert context.current_mode == SubMode.MOVE_WINDOW
    assert context.accumulated_input == ""

    # Step 2: Type digits (triggered by digit keys)
    context.add_digit("2")
    assert context.accumulated_input == "2"
    assert context.target_workspace == 2

    context.add_digit("3")
    assert context.accumulated_input == "23"
    assert context.target_workspace == 23

    # Step 3: Confirm (triggered by Enter key)
    # In actual daemon, this would call handle_window_move(window_id, 23)
    target_workspace = context.target_workspace
    assert target_workspace == 23

    # Step 4: Reset to normal after execution
    context.reset_to_normal()
    assert context.current_mode == SubMode.NORMAL
    assert context.target_workspace is None


def test_move_window_workflow_cancelled():
    """Test move window workflow cancellation via Escape.

    Simulates:
    1. User presses M (enter move mode)
    2. User types 2, 3 (accumulate workspace number)
    3. User presses Escape (cancel)
    """
    context = SubModeContext()

    # Step 1: Enter move mode
    context.enter_sub_mode(SubMode.MOVE_WINDOW)

    # Step 2: Type digits
    context.add_digit("2")
    context.add_digit("3")
    assert context.target_workspace == 23

    # Step 3: Cancel (triggered by Escape key)
    context.reset_to_normal()

    # Should be back to normal with no side effects
    assert context.current_mode == SubMode.NORMAL
    assert context.target_workspace is None


def test_keyboard_hints_update_during_move_workflow():
    """Test keyboard hints update as user types in move mode.

    NOTE: This test verifies sub-mode hints exist in keyboard_hint_manager.py
    from Phase 2. The actual implementation was done in T006/T032.

    Verifies:
    - Hints show "Type workspace:" prompt
    - Hints show accumulated digits with cursor
    - Hints show Confirm and Cancel options
    """
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    # No input yet
    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )
    assert "Type workspace:" in hints
    assert "_" in hints  # Empty cursor
    assert "Confirm" in hints
    assert "Cancel" in hints

    # After typing "2"
    context.add_digit("2")
    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )
    assert "2_" in hints  # Shows accumulated input

    # After typing "23"
    context.add_digit("3")
    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )
    assert "23_" in hints


def test_mark_window_workflow_complete():
    """Test complete mark window workflow: enter mode → type chars → confirm.

    Simulates:
    1. User presses Shift+M (enter mark mode)
    2. User types "todo" (accumulate mark name)
    3. User presses Enter (confirm mark)
    """
    context = SubModeContext()

    # Step 1: Enter mark mode
    context.enter_sub_mode(SubMode.MARK_WINDOW)
    assert context.current_mode == SubMode.MARK_WINDOW

    # Step 2: Type characters
    for char in "todo":
        context.add_character(char)

    assert context.accumulated_input == "todo"
    assert context.mark_name == "todo"

    # Step 3: Confirm
    target_mark = context.mark_name
    assert target_mark == "todo"

    # Step 4: Reset
    context.reset_to_normal()
    assert context.current_mode == SubMode.NORMAL


def test_invalid_workspace_number_prevents_execution():
    """Test that invalid workspace numbers are rejected.

    Verifies:
    - Workspace 0 rejected
    - Workspace 71 rejected (stops at 7)
    - Workspace 100 rejected (stops at 10)
    """
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    # Try workspace 0
    result = context.add_digit("0")
    assert result is False  # Rejected
    assert context.target_workspace is None  # Invalid

    # Reset
    context.reset_to_normal()
    context.enter_sub_mode(SubMode.MOVE_WINDOW)

    # Try workspace 71 - stops at 7
    assert context.add_digit("7") is True
    assert context.target_workspace == 7
    assert context.add_digit("1") is False  # Rejected (71 > 70)
    assert context.target_workspace == 7  # Still 7

    # Reset
    context.reset_to_normal()
    context.enter_sub_mode(SubMode.MOVE_WINDOW)

    # Try workspace 100 - stops at 10
    assert context.add_digit("1") is True
    assert context.add_digit("0") is True
    assert context.target_workspace == 10
    assert context.add_digit("0") is False  # Rejected (100 > 70)
    assert context.target_workspace == 10  # Still 10


def test_sub_mode_state_preserved_during_navigation():
    """Test that sub-mode state is preserved when user navigates selection.

    Simulates:
    1. User enters move mode
    2. User types "2"
    3. User navigates with arrow keys (selection changes)
    4. User types "3" (should continue from "2" → "23")
    """
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    # Type first digit
    context.add_digit("2")
    assert context.accumulated_input == "2"

    # Selection changes (navigation) - sub-mode state should persist
    # (In actual daemon, selection_index would change but sub_mode_context stays)

    # Type second digit
    context.add_digit("3")
    assert context.accumulated_input == "23"
    assert context.target_workspace == 23
