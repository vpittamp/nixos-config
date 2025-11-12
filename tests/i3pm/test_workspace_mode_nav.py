"""Unit tests for workspace mode navigation methods (Feature 059).

Tests the nav() and delete() methods in WorkspaceModeManager for event broadcasting.
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch, MagicMock
from datetime import datetime

# Import the class under test
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "home-modules" / "desktop"))

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


@pytest.fixture
def mock_ipc_server():
    """Create mock IPC server."""
    mock = AsyncMock()
    mock.broadcast_event = AsyncMock()
    return mock


@pytest.fixture
async def workspace_manager(mock_i3_connection, mock_ipc_server):
    """Create WorkspaceModeManager instance with mocks."""
    manager = WorkspaceModeManager(
        i3_connection=mock_i3_connection,
        ipc_server=mock_ipc_server
    )
    return manager


# ==================== Tests for nav() method ====================

@pytest.mark.asyncio
async def test_nav_with_valid_direction_down_emits_event(workspace_manager, mock_ipc_server):
    """Test nav('down') in active mode emits correct event payload."""
    # Arrange: Enter workspace mode
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()  # Clear enter event

    # Act: Navigate down
    await workspace_manager.nav("down")

    # Assert: Event was broadcast
    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["type"] == "workspace_mode"
    assert call_args["payload"]["event_type"] == "nav"
    assert call_args["payload"]["direction"] == "down"


@pytest.mark.asyncio
async def test_nav_with_valid_direction_up_emits_event(workspace_manager, mock_ipc_server):
    """Test nav('up') in active mode emits correct event payload."""
    # Arrange
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    # Act
    await workspace_manager.nav("up")

    # Assert
    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["event_type"] == "nav"
    assert call_args["payload"]["direction"] == "up"


@pytest.mark.asyncio
async def test_nav_with_valid_direction_left_emits_event(workspace_manager, mock_ipc_server):
    """Test nav('left') in active mode emits correct event payload."""
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    await workspace_manager.nav("left")

    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["direction"] == "left"


@pytest.mark.asyncio
async def test_nav_with_valid_direction_right_emits_event(workspace_manager, mock_ipc_server):
    """Test nav('right') in active mode emits correct event payload."""
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    await workspace_manager.nav("right")

    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["direction"] == "right"


@pytest.mark.asyncio
async def test_nav_with_valid_direction_home_emits_event(workspace_manager, mock_ipc_server):
    """Test nav('home') in active mode emits correct event payload."""
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    await workspace_manager.nav("home")

    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["direction"] == "home"


@pytest.mark.asyncio
async def test_nav_with_valid_direction_end_emits_event(workspace_manager, mock_ipc_server):
    """Test nav('end') in active mode emits correct event payload."""
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    await workspace_manager.nav("end")

    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["direction"] == "end"


@pytest.mark.asyncio
async def test_nav_with_invalid_direction_raises_value_error(workspace_manager):
    """Test nav() with invalid direction raises ValueError."""
    await workspace_manager.enter_mode("goto")

    with pytest.raises(ValueError, match="Invalid direction"):
        await workspace_manager.nav("invalid")


@pytest.mark.asyncio
async def test_nav_when_mode_inactive_raises_runtime_error(workspace_manager):
    """Test nav() when mode not active raises RuntimeError."""
    # Mode is not active (don't call enter_mode)

    with pytest.raises(RuntimeError, match="Cannot navigate: workspace mode not active"):
        await workspace_manager.nav("down")


@pytest.mark.asyncio
async def test_nav_includes_mode_type_in_payload(workspace_manager, mock_ipc_server):
    """Test nav() includes mode_type in event payload."""
    await workspace_manager.enter_mode("move")  # Use move mode
    mock_ipc_server.broadcast_event.reset_mock()

    await workspace_manager.nav("down")

    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["mode_type"] == "move"


# ==================== Tests for delete() method ====================

@pytest.mark.asyncio
async def test_delete_in_active_mode_emits_event(workspace_manager, mock_ipc_server):
    """Test delete() in active mode emits correct event payload."""
    # Arrange
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    # Act
    await workspace_manager.delete()

    # Assert
    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["type"] == "workspace_mode"
    assert call_args["payload"]["event_type"] == "delete"


@pytest.mark.asyncio
async def test_delete_when_mode_inactive_raises_runtime_error(workspace_manager):
    """Test delete() when mode not active raises RuntimeError."""
    # Mode is not active

    with pytest.raises(RuntimeError, match="Cannot delete: workspace mode not active"):
        await workspace_manager.delete()


@pytest.mark.asyncio
async def test_delete_includes_mode_type_in_payload(workspace_manager, mock_ipc_server):
    """Test delete() includes mode_type in event payload."""
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    await workspace_manager.delete()

    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["mode_type"] == "goto"


# ==================== Tests for _emit_workspace_mode_event() with **kwargs ====================

@pytest.mark.asyncio
async def test_emit_workspace_mode_event_accepts_kwargs(workspace_manager, mock_ipc_server):
    """Test _emit_workspace_mode_event() accepts direction via **kwargs."""
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    # Call the private method directly with direction kwarg
    await workspace_manager._emit_workspace_mode_event("nav", direction="down")

    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["direction"] == "down"


@pytest.mark.asyncio
async def test_emit_workspace_mode_event_without_kwargs(workspace_manager, mock_ipc_server):
    """Test _emit_workspace_mode_event() works without kwargs (backward compatibility)."""
    await workspace_manager.enter_mode("goto")
    mock_ipc_server.broadcast_event.reset_mock()

    # Call without kwargs (existing behavior)
    await workspace_manager._emit_workspace_mode_event("enter")

    assert mock_ipc_server.broadcast_event.called
    call_args = mock_ipc_server.broadcast_event.call_args[0][0]
    assert call_args["payload"]["event_type"] == "enter"
    # direction should not be present
    assert "direction" not in call_args["payload"]
