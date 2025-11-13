"""Unit tests for Feature 073 - Sub-Mode State Machine.

Tests sub-mode state transitions, digit accumulation, workspace validation,
and cancellation logic.
"""
import pytest
import sys
from pathlib import Path

# Add sway-workspace-panel to path for imports
WORKSPACE_PANEL_DIR = Path("/etc/nixos/home-modules/tools/sway-workspace-panel")
sys.path.insert(0, str(WORKSPACE_PANEL_DIR))

from sub_mode_manager import SubMode, SubModeContext


def test_initial_state_is_normal():
    """Test sub-mode context starts in NORMAL mode."""
    context = SubModeContext()

    assert context.current_mode == SubMode.NORMAL
    assert context.accumulated_input == ""
    assert context.target_workspace is None


def test_enter_move_window_sub_mode():
    """Test entering MOVE_WINDOW sub-mode."""
    context = SubModeContext()

    context.enter_sub_mode(SubMode.MOVE_WINDOW)

    assert context.current_mode == SubMode.MOVE_WINDOW
    assert context.accumulated_input == ""


def test_enter_mark_window_sub_mode():
    """Test entering MARK_WINDOW sub-mode."""
    context = SubModeContext()

    context.enter_sub_mode(SubMode.MARK_WINDOW)

    assert context.current_mode == SubMode.MARK_WINDOW
    assert context.accumulated_input == ""


def test_add_digit_in_move_mode():
    """Test digit accumulation in MOVE_WINDOW mode."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    context.add_digit("2")
    assert context.accumulated_input == "2"
    assert context.target_workspace == 2

    context.add_digit("3")
    assert context.accumulated_input == "23"
    assert context.target_workspace == 23


def test_add_char_in_mark_mode():
    """Test character accumulation in MARK_WINDOW mode."""
    context = SubModeContext(current_mode=SubMode.MARK_WINDOW)

    context.add_character("t")
    context.add_character("o")
    context.add_character("d")
    context.add_character("o")

    assert context.accumulated_input == "todo"
    assert context.mark_name == "todo"


def test_workspace_validation_min_boundary():
    """Test workspace validation: minimum is 1."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    context.add_digit("1")
    assert context.target_workspace == 1  # Valid

    context.accumulated_input = ""
    context.target_workspace = None

    context.add_digit("0")
    assert context.target_workspace is None  # Invalid


def test_workspace_validation_max_boundary():
    """Test workspace validation: maximum is 70."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    context.add_digit("7")
    context.add_digit("0")
    assert context.target_workspace == 70  # Valid

    # Reset
    context.reset_to_normal()
    context.enter_sub_mode(SubMode.MOVE_WINDOW)

    # Try 71 - first digit '7' accepted, second digit '1' rejected
    assert context.add_digit("7") is True  # Accepted
    assert context.accumulated_input == "7"
    assert context.target_workspace == 7

    assert context.add_digit("1") is False  # Rejected (71 > 70)
    assert context.accumulated_input == "7"  # Still at 7
    assert context.target_workspace == 7


def test_workspace_validation_three_digits_invalid():
    """Test workspace validation: three-digit numbers invalid."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    assert context.add_digit("1") is True  # Accepted
    assert context.add_digit("0") is True  # Accepted (10 is valid)
    assert context.target_workspace == 10

    assert context.add_digit("0") is False  # Rejected (100 > 70)
    assert context.accumulated_input == "10"  # Stays at 10
    assert context.target_workspace == 10


def test_reset_to_normal_from_move_mode():
    """Test resetting to NORMAL mode from MOVE_WINDOW."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)
    context.accumulated_input = "23"
    context.target_workspace = 23

    context.reset_to_normal()

    assert context.current_mode == SubMode.NORMAL
    assert context.accumulated_input == ""
    assert context.target_workspace is None


def test_reset_to_normal_from_mark_mode():
    """Test resetting to NORMAL mode from MARK_WINDOW."""
    context = SubModeContext(current_mode=SubMode.MARK_WINDOW)
    context.accumulated_input = "todo"
    context.mark_name = "todo"

    context.reset_to_normal()

    assert context.current_mode == SubMode.NORMAL
    assert context.accumulated_input == ""
    assert context.mark_name is None


def test_sub_mode_transitions():
    """Test complete sub-mode workflow."""
    context = SubModeContext()

    # Start in normal
    assert context.current_mode == SubMode.NORMAL

    # Enter move mode
    context.enter_sub_mode(SubMode.MOVE_WINDOW)
    assert context.current_mode == SubMode.MOVE_WINDOW

    # Add digits
    context.add_digit("2")
    context.add_digit("3")
    assert context.target_workspace == 23

    # Reset (simulate Enter key execution or Escape cancellation)
    context.reset_to_normal()
    assert context.current_mode == SubMode.NORMAL
    assert context.accumulated_input == ""


def test_cannot_add_digit_in_normal_mode():
    """Test digit accumulation rejected in NORMAL mode."""
    context = SubModeContext(current_mode=SubMode.NORMAL)

    result = context.add_digit("5")
    assert result is False  # Rejected, not an exception


def test_cannot_add_char_in_normal_mode():
    """Test character accumulation rejected in NORMAL mode."""
    context = SubModeContext(current_mode=SubMode.NORMAL)

    result = context.add_character("x")
    assert result is False  # Rejected, not an exception


def test_leading_zeros_ignored():
    """Test leading zeros are stripped from workspace numbers."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    context.add_digit("0")
    context.add_digit("5")

    # Should interpret as 5, not 05
    assert context.target_workspace == 5
