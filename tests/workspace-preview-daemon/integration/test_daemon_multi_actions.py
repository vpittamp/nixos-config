"""Integration tests for Feature 073 - User Story 2: Multi-Action Workflow Support.

Tests that the workspace-preview-daemon can handle multiple consecutive
window management actions without state corruption or crashes.

NOTE: These tests verify the core data structures and logic. The actual daemon
integration is tested via sway-test framework (test_multi_action_workflow.json).
"""
import pytest
import sys
from pathlib import Path

# Add sway-workspace-panel to path for imports
WORKSPACE_PANEL_DIR = Path("/etc/nixos/home-modules/tools/sway-workspace-panel")
sys.path.insert(0, str(WORKSPACE_PANEL_DIR))

from selection_models.selection_state import NavigableItem, PreviewListModel


@pytest.fixture
def sample_preview_list():
    """Create a PreviewListModel with test data."""
    return PreviewListModel(
        items=[
            NavigableItem.from_workspace_heading(
                workspace_num=1,
                window_count=3,
                monitor_output="HEADLESS-1",
                position_index=0
            ),
            NavigableItem.from_window(
                window_name="Alacritty",
                workspace_num=1,
                window_id=1001,
                icon_path=None,
                position_index=1
            ),
            NavigableItem.from_window(
                window_name="Firefox",
                workspace_num=1,
                window_id=1002,
                icon_path=None,
                position_index=2
            ),
            NavigableItem.from_window(
                window_name="VS Code",
                workspace_num=1,
                window_id=1003,
                icon_path=None,
                position_index=3
            ),
        ],
        current_selection_index=1  # Start on first window
    )


def test_consecutive_item_removal_preserves_state(sample_preview_list):
    """Test T024 & T028: Multiple item removals maintain consistent state.

    Verifies:
    - Multiple remove_item() calls work correctly
    - Selection is clamped after each removal
    - Item count decreases as expected
    - No duplicate items remain
    - Position indices stay valid
    """
    initial_count = len(sample_preview_list.items)

    # First removal: Alacritty
    first_item = sample_preview_list.get_selected_item()
    assert first_item.window_id == 1001  # Alacritty

    success = sample_preview_list.remove_item(first_item)
    assert success, "First item removal should succeed"

    sample_preview_list.clamp_selection()

    assert len(sample_preview_list.items) == initial_count - 1
    assert not sample_preview_list.is_empty

    # Second removal: Firefox (now at same index after first removal)
    second_item = sample_preview_list.get_selected_item()
    assert second_item.window_id == 1002  # Firefox

    success = sample_preview_list.remove_item(second_item)
    assert success, "Second item removal should succeed"

    sample_preview_list.clamp_selection()

    assert len(sample_preview_list.items) == initial_count - 2
    assert not sample_preview_list.is_empty

    # Third removal: VS Code
    third_item = sample_preview_list.get_selected_item()
    assert third_item.window_id == 1003  # VS Code

    success = sample_preview_list.remove_item(third_item)
    assert success, "Third item removal should succeed"

    sample_preview_list.clamp_selection()

    # Only workspace heading should remain
    assert len(sample_preview_list.items) == 1
    assert not sample_preview_list.is_empty  # Heading still present
    assert sample_preview_list.items[0].is_workspace_heading()

    # Verify no duplicates
    item_ids = [item.position_index for item in sample_preview_list.items]
    assert len(item_ids) == len(set(item_ids)), "No duplicate position indices"


def test_workspace_heading_protection(sample_preview_list):
    """Test T025: Workspace headings cannot be removed like windows.

    Verifies:
    - is_workspace_heading() check works correctly
    - Workspace heading can be identified before attempting removal
    - Window items can be distinguished from headings
    """
    # Select workspace heading
    sample_preview_list.current_selection_index = 0
    selected = sample_preview_list.get_selected_item()

    # Verify it's a heading
    assert selected.is_workspace_heading()
    assert not selected.is_window()
    assert selected.window_id is None

    # In actual daemon, this check prevents removal:
    # if selected_item.is_workspace_heading():
    #     return  # Silent no-op

    # Verify windows can be distinguished
    sample_preview_list.current_selection_index = 1
    window_selected = sample_preview_list.get_selected_item()

    assert window_selected.is_window()
    assert not window_selected.is_workspace_heading()
    assert window_selected.window_id is not None


def test_empty_detection_after_all_windows_removed(sample_preview_list):
    """Test auto-exit condition: is_empty detection.

    Verifies:
    - is_empty returns True only when no items remain
    - After removing all windows, heading still present
    - If heading is also removed, is_empty returns True
    """
    # Remove all windows (keep heading)
    windows = [item for item in sample_preview_list.items if item.is_window()]

    for window in windows:
        sample_preview_list.remove_item(window)
        sample_preview_list.clamp_selection()

    # Heading still present
    assert len(sample_preview_list.items) == 1
    assert not sample_preview_list.is_empty

    # Remove heading too
    heading = sample_preview_list.items[0]
    sample_preview_list.remove_item(heading)

    # Now empty
    assert len(sample_preview_list.items) == 0
    assert sample_preview_list.is_empty


def test_selection_clamping_after_removal(sample_preview_list):
    """Test selection stays valid after item removal.

    Verifies:
    - Selection index stays within bounds
    - Selecting last item, then removing it moves selection
    - Selection never becomes invalid (out of range)
    """
    # Move to last window
    sample_preview_list.current_selection_index = 3  # VS Code

    last_item = sample_preview_list.get_selected_item()
    assert last_item.window_id == 1003

    # Remove last item
    sample_preview_list.remove_item(last_item)
    sample_preview_list.clamp_selection()

    # Selection should clamp to new last item (Firefox)
    assert sample_preview_list.current_selection_index == 2
    assert sample_preview_list.get_selected_item().window_id == 1002


def test_multi_action_workflow_state_preservation(sample_preview_list):
    """Test T028: State remains consistent across multiple operations.

    Simulates a multi-action workflow:
    1. Remove first window
    2. Navigate down
    3. Remove second window
    4. Navigate up
    5. Verify state is consistent
    """
    # Operation 1: Remove Alacritty
    sample_preview_list.current_selection_index = 1
    item1 = sample_preview_list.get_selected_item()
    sample_preview_list.remove_item(item1)
    sample_preview_list.clamp_selection()

    # Operation 2: Navigate down (selection advances after removal, so we're now on Firefox at index 1)
    # But we're already on Firefox at index 1 after removal, so navigate_down goes to VS Code
    sample_preview_list.navigate_down()
    assert sample_preview_list.get_selected_item().window_id == 1003  # VS Code

    # Operation 3: Remove VS Code
    item2 = sample_preview_list.get_selected_item()
    sample_preview_list.remove_item(item2)
    sample_preview_list.clamp_selection()

    # Operation 4: Navigate up (should wrap to last item)
    sample_preview_list.navigate_up()

    # Verify state consistency
    assert len(sample_preview_list.items) == 2  # Heading + Firefox
    assert sample_preview_list.has_selection
    assert sample_preview_list.current_selection_index is not None
    assert sample_preview_list.current_selection_index < len(sample_preview_list.items)

    # Verify no orphaned references
    selected = sample_preview_list.get_selected_item()
    assert selected is not None
    assert selected in sample_preview_list.items
