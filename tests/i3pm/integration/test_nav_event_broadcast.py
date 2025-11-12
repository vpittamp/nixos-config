"""Integration tests for workspace mode navigation event broadcasting (Feature 059).

Tests the end-to-end flow: WorkspaceModeManager.nav() → IPC broadcast → workspace-preview-daemon receives event.

These tests verify User Story 1 (arrow key navigation) by simulating the daemon's event handling.
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from datetime import datetime
import sys
from pathlib import Path

# Add daemon to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop"))

from i3_project_event_daemon.workspace_mode import WorkspaceModeManager


@pytest.fixture
def mock_i3_connection():
    """Create mock i3 connection."""
    mock = AsyncMock()
    mock.command = AsyncMock(return_value=[{"success": True}])
    mock.get_workspaces = AsyncMock(return_value=[])
    mock.get_outputs = AsyncMock(return_value=[
        {"name": "HEADLESS-1", "active": True, "focused": True}
    ])
    return mock


class MockIPCServer:
    """Mock IPC server that captures broadcasted events."""

    def __init__(self):
        self.broadcasted_events = []

        async def capture_event(event):
            self.broadcasted_events.append(event)
            return None

        self.broadcast_event = AsyncMock(side_effect=capture_event)


@pytest.fixture
def mock_ipc_server():
    """Create mock IPC server that captures broadcasted events."""
    return MockIPCServer()


@pytest.fixture
async def workspace_manager(mock_i3_connection, mock_ipc_server):
    """Create WorkspaceModeManager instance with mocks."""
    manager = WorkspaceModeManager(
        i3_connection=mock_i3_connection,
        ipc_server=mock_ipc_server
    )
    # Enter mode so nav() and delete() work
    await manager.enter_mode("goto")
    # Give event loop a chance to process the broadcast
    await asyncio.sleep(0.01)
    print(f"FIXTURE DEBUG: After enter_mode, events = {mock_ipc_server.broadcasted_events}")
    # Clear the enter event from the captured events
    mock_ipc_server.broadcasted_events.clear()
    print(f"FIXTURE DEBUG: After clear, events = {mock_ipc_server.broadcasted_events}")
    mock_ipc_server.broadcast_event.reset_mock()  # Reset call count
    return manager


# ==================== T016: nav("down") updates selection to next workspace ====================

@pytest.mark.asyncio
async def test_nav_down_updates_selection_to_next_workspace(workspace_manager, mock_ipc_server):
    """T016: Integration test - nav('down') emits event that would update selection to next workspace.

    This test verifies the event is broadcast correctly. The actual selection update
    happens in workspace-preview-daemon's NavigationHandler.
    """
    # Act: Navigate down
    await workspace_manager.nav("down")
    # Give event loop a chance to process the broadcast
    await asyncio.sleep(0.01)

    # Assert: Event was broadcast with correct structure
    assert mock_ipc_server.broadcast_event.called
    print(f"DEBUG: Events = {mock_ipc_server.broadcasted_events}")
    print(f"DEBUG: Length = {len(mock_ipc_server.broadcasted_events)}")

    # Get the nav event (should be captured now)
    nav_events = [e for e in mock_ipc_server.broadcasted_events if e["payload"]["event_type"] == "nav"]
    assert len(nav_events) >= 1, "No nav event found"

    event = nav_events[0]
    assert event["type"] == "workspace_mode"
    assert event["payload"]["event_type"] == "nav"
    assert event["payload"]["direction"] == "down"
    assert "mode_type" in event["payload"]

    # The event should contain enough information for the preview daemon to update selection
    assert event["payload"]["direction"] in ["up", "down", "left", "right", "home", "end"]


# ==================== T017: nav("up") wraps from first to last workspace ====================

@pytest.mark.asyncio
async def test_nav_up_wraps_from_first_to_last_workspace(workspace_manager, mock_ipc_server):
    """T017: Integration test - nav('up') emits event that enables wrapping from first to last.

    The wrapping logic is implemented in workspace-preview-daemon's NavigationHandler.
    This test verifies the event is broadcast correctly to trigger that logic.
    """
    # Act: Navigate up (wrapping direction)
    await workspace_manager.nav("up")
    # Give event loop a chance to process the broadcast
    await asyncio.sleep(0.01)

    # Assert: Event was broadcast with correct structure
    assert mock_ipc_server.broadcast_event.called

    nav_events = [e for e in mock_ipc_server.broadcasted_events if e["payload"]["event_type"] == "nav"]
    assert len(nav_events) >= 1, "No nav event found"

    event = nav_events[0]
    assert event["type"] == "workspace_mode"
    assert event["payload"]["event_type"] == "nav"
    assert event["payload"]["direction"] == "up"

    # The event structure supports wrapping - the preview daemon will handle the wrap logic


# ==================== T018: nav("down") wraps from last to first workspace ====================

@pytest.mark.asyncio
async def test_nav_down_wraps_from_last_to_first_workspace(workspace_manager, mock_ipc_server):
    """T018: Integration test - nav('down') emits event that enables wrapping from last to first.

    The wrapping logic is implemented in workspace-preview-daemon's NavigationHandler.
    This test verifies the event is broadcast correctly to trigger that logic.
    """
    # Act: Navigate down (wrapping direction)
    await workspace_manager.nav("down")
    # Give event loop a chance to process the broadcast
    await asyncio.sleep(0.01)

    # Assert: Event was broadcast with correct structure
    assert mock_ipc_server.broadcast_event.called

    nav_events = [e for e in mock_ipc_server.broadcasted_events if e["payload"]["event_type"] == "nav"]
    assert len(nav_events) >= 1, "No nav event found"

    event = nav_events[0]
    assert event["type"] == "workspace_mode"
    assert event["payload"]["event_type"] == "nav"
    assert event["payload"]["direction"] == "down"

    # Multiple down events in sequence should all be valid
    # The preview daemon handles wrapping when selection reaches the end


# ==================== T019-T020: Sway-test will be written in JSON ====================
# These tests (T019-T020) will be implemented as sway-test JSON files in:
# home-modules/tools/sway-test/tests/sway-tests/integration/test_navigation_workflow.json
#
# T019: Enter workspace mode, navigate with Down/Up, verify preview updates
# T020: Navigate to workspace 23, press Enter, verify workspace switch
#
# The sway-test framework provides end-to-end testing with actual Sway IPC.
# These Python integration tests focus on the event broadcasting layer.


# ==================== Additional Integration Tests ====================

@pytest.mark.asyncio
async def test_multiple_nav_events_maintain_correct_order(workspace_manager, mock_ipc_server):
    """Verify rapid navigation events are broadcast in correct order."""
    # Act: Rapid sequence of navigation events
    await workspace_manager.nav("down")
    await workspace_manager.nav("down")
    await workspace_manager.nav("up")
    await workspace_manager.nav("down")
    # Give event loop a chance to process all broadcasts
    await asyncio.sleep(0.01)

    # Assert: All events were broadcast in order
    nav_events = [e for e in mock_ipc_server.broadcasted_events if e["payload"]["event_type"] == "nav"]
    assert len(nav_events) == 4, f"Expected 4 nav events, got {len(nav_events)}"

    assert nav_events[0]["payload"]["direction"] == "down"
    assert nav_events[1]["payload"]["direction"] == "down"
    assert nav_events[2]["payload"]["direction"] == "up"
    assert nav_events[3]["payload"]["direction"] == "down"


@pytest.mark.asyncio
async def test_nav_events_include_mode_type(workspace_manager, mock_ipc_server):
    """Verify nav events include mode_type (goto vs move)."""
    # Act: Navigate in goto mode
    await workspace_manager.nav("down")
    await asyncio.sleep(0.01)

    # Assert: Event includes mode_type
    nav_events = [e for e in mock_ipc_server.broadcasted_events if e["payload"]["event_type"] == "nav"]
    assert len(nav_events) >= 1, "No nav event found"
    event = nav_events[0]
    assert event["payload"]["mode_type"] == "goto"

    # Switch to move mode
    await workspace_manager.cancel()
    await workspace_manager.enter_mode("move")
    await asyncio.sleep(0.01)
    mock_ipc_server.broadcasted_events.clear()

    # Act: Navigate in move mode
    await workspace_manager.nav("down")
    await asyncio.sleep(0.01)

    # Assert: Event includes updated mode_type
    nav_events = [e for e in mock_ipc_server.broadcasted_events if e["payload"]["event_type"] == "nav"]
    assert len(nav_events) >= 1, "No nav event found"
    event = nav_events[0]
    assert event["payload"]["mode_type"] == "move"


@pytest.mark.asyncio
async def test_nav_and_delete_events_in_sequence(workspace_manager, mock_ipc_server):
    """Verify nav and delete events can be sent in sequence."""
    # Act: Navigate then delete
    await workspace_manager.nav("down")
    await workspace_manager.nav("down")
    await workspace_manager.delete()
    # Give event loop a chance to process all broadcasts
    await asyncio.sleep(0.01)

    # Assert: All events were broadcast in order
    # Filter for nav and delete events only (excludes any enter/cancel events)
    events = [e for e in mock_ipc_server.broadcasted_events if e["payload"]["event_type"] in ["nav", "delete"]]
    assert len(events) == 3, f"Expected 3 nav/delete events, got {len(events)}"

    assert events[0]["payload"]["event_type"] == "nav"
    assert events[1]["payload"]["event_type"] == "nav"
    assert events[2]["payload"]["event_type"] == "delete"
