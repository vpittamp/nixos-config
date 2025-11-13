"""Unit tests for Feature 073 - User Story 3: Keyboard Hints Manager.

Tests context-aware keyboard hint generation based on selection type
and sub-mode state.
"""
import pytest
import sys
from pathlib import Path

# Add sway-workspace-panel to path for imports
WORKSPACE_PANEL_DIR = Path("/etc/nixos/home-modules/tools/sway-workspace-panel")
sys.path.insert(0, str(WORKSPACE_PANEL_DIR))

from keyboard_hint_manager import KeyboardHints, SubModeContext, SubMode


def test_window_selected_normal_mode():
    """Test T031: Hints when window selected in normal mode.

    Should show all available actions: Navigate, Select, Close, Move, Float, Project, Cancel.
    """
    context = SubModeContext(current_mode=SubMode.NORMAL)
    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )

    # Verify all expected hints are present
    assert "Navigate" in hints
    assert "Select" in hints
    assert "Close" in hints
    assert "Move" in hints
    assert "Float" in hints
    assert "Project" in hints
    assert "Cancel" in hints

    # Verify specific keys
    assert "↑/↓" in hints
    assert "Enter" in hints
    assert "Delete" in hints
    assert "M" in hints
    assert "F" in hints
    assert ":" in hints
    assert "Esc" in hints


def test_workspace_heading_selected_normal_mode():
    """Test T031: Hints when workspace heading selected.

    Should NOT show window-specific actions (Close, Move, Float).
    Only: Navigate, Select, Project, Cancel.
    """
    context = SubModeContext(current_mode=SubMode.NORMAL)
    hints = KeyboardHints.generate_hints(
        selection_type="workspace_heading",
        sub_mode_context=context
    )

    # Verify expected hints are present
    assert "Navigate" in hints
    assert "Select" in hints
    assert "Project" in hints
    assert "Cancel" in hints

    # Verify window-specific actions are NOT present
    assert "Close" not in hints
    assert "Move" not in hints
    assert "Float" not in hints

    # Verify no window-specific keys
    assert "Delete" not in hints
    assert "M" not in hints
    assert "F" not in hints


def test_move_window_sub_mode():
    """Test T031: Hints when in move window sub-mode.

    Should show workspace input prompt with accumulated digits.
    """
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)
    context.accumulated_input = "23"

    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )

    # Verify sub-mode prompt
    assert "Type workspace:" in hints
    assert "23_" in hints  # Shows accumulated input with cursor
    assert "Confirm" in hints
    assert "Cancel" in hints

    # Verify sub-mode overrides normal hints
    assert "Navigate" not in hints
    assert "Delete" not in hints


def test_move_window_sub_mode_empty_input():
    """Test T031: Move window sub-mode with no input yet."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )

    # Should show empty cursor
    assert "_" in hints
    assert "Type workspace:" in hints


def test_mark_window_sub_mode():
    """Test T031: Hints when in mark window sub-mode.

    Should show mark input prompt with accumulated text.
    """
    context = SubModeContext(current_mode=SubMode.MARK_WINDOW)
    context.accumulated_input = "todo"

    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )

    # Verify sub-mode prompt
    assert "Type mark:" in hints
    assert "todo_" in hints  # Shows accumulated input with cursor
    assert "Confirm" in hints
    assert "Cancel" in hints


def test_hint_format_consistency():
    """Test T031: Verify hint format follows documented notation.

    - Pipe separators (|) between distinct actions
    - Slash (/) for alternatives (↑/↓)
    - Key names uppercase or symbols
    - Action verbs (Navigate, Select, Close, etc.)
    """
    context = SubModeContext(current_mode=SubMode.NORMAL)
    hints = KeyboardHints.generate_hints(
        selection_type="window",
        sub_mode_context=context
    )

    # Verify pipe separators
    assert "|" in hints

    # Verify format: "Key Action | Key Action"
    parts = [part.strip() for part in hints.split("|")]
    assert len(parts) >= 5  # At least 5 distinct actions

    # Each part should have a key and an action
    for part in parts:
        assert len(part.split()) >= 2, f"Part '{part}' should have key and action"


def test_sub_mode_context_transitions():
    """Test SubModeContext state management."""
    context = SubModeContext()

    # Start in normal mode
    assert context.current_mode == SubMode.NORMAL
    assert context.accumulated_input == ""

    # Enter move window sub-mode
    context.enter_sub_mode(SubMode.MOVE_WINDOW)
    assert context.current_mode == SubMode.MOVE_WINDOW
    assert context.accumulated_input == ""  # Reset on entry

    # Add digits
    context.add_digit("2")
    context.add_digit("3")
    assert context.accumulated_input == "23"
    assert context.target_workspace == 23

    # Reset to normal
    context.reset_to_normal()
    assert context.current_mode == SubMode.NORMAL
    assert context.accumulated_input == ""
    assert context.target_workspace is None


def test_workspace_number_validation():
    """Test SubModeContext validates workspace numbers (1-70 range)."""
    context = SubModeContext(current_mode=SubMode.MOVE_WINDOW)

    # Valid workspace
    context.add_digit("2")
    context.add_digit("3")
    assert context.target_workspace == 23

    # Reset
    context.accumulated_input = ""
    context.target_workspace = None

    # Invalid workspace (>70)
    context.add_digit("9")
    context.add_digit("9")
    assert context.target_workspace is None  # Out of range

    # Reset
    context.accumulated_input = ""
    context.target_workspace = None

    # Valid edge case (70)
    context.add_digit("7")
    context.add_digit("0")
    assert context.target_workspace == 70

    # Reset
    context.accumulated_input = ""
    context.target_workspace = None

    # Valid edge case (1)
    context.add_digit("1")
    assert context.target_workspace == 1


def test_hint_generation_performance():
    """Test T035: Verify hint generation is fast (<5ms target).

    Note: This is a basic timing test. Actual performance validation
    should be done via Phase 8 comprehensive testing.
    """
    import time

    context = SubModeContext(current_mode=SubMode.NORMAL)

    # Run 100 iterations to get average time
    start = time.perf_counter()
    for _ in range(100):
        KeyboardHints.generate_hints(
            selection_type="window",
            sub_mode_context=context
        )
    end = time.perf_counter()

    avg_time_ms = ((end - start) / 100) * 1000

    # Should be well under 5ms (targeting <1ms)
    assert avg_time_ms < 5.0, f"Hint generation took {avg_time_ms:.2f}ms, target <5ms"

    print(f"INFO: Average hint generation time: {avg_time_ms:.2f}ms (target <5ms)")
