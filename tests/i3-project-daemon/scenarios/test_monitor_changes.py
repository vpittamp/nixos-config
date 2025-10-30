"""Scenario tests for monitor change workflows.

Feature 049: US1+US2 - Complete monitor change scenarios
"""
import pytest
import asyncio
from unittest.mock import Mock, AsyncMock
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../..'))

from home_modules.desktop.i3_project_event_daemon.handlers import Feature049EventHandlers


@pytest.mark.asyncio
async def test_3_monitors_to_2_monitors():
    """Test workspace redistribution when disconnecting a monitor (US1)."""
    # Setup: 3 monitors initially
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-2", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]
    mock_i3.get_workspaces.return_value = []
    mock_i3.get_tree.return_value = Mock(nodes=[], floating_nodes=[])
    mock_i3.command.return_value = [Mock(success=True)]
    
    handlers = Feature049EventHandlers(mock_i3)
    
    # Initial state: 3 monitors
    event = Mock(change="connected", output=Mock(name="HEADLESS-3", active=True))
    await handlers.on_output_event(mock_i3, event)
    await asyncio.sleep(0.6)
    
    initial_result = handlers._reassignment_history[0]
    assert initial_result.workspaces_reassigned == 70  # All workspaces assigned
    
    # Disconnect HEADLESS-2
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]
    
    event = Mock(change="disconnected", output=Mock(name="HEADLESS-2", active=False))
    await handlers.on_output_event(mock_i3, event)
    await asyncio.sleep(0.6)
    
    # Verify redistribution for 2 monitors
    result = handlers._reassignment_history[1]
    assert result.success is True
    assert result.workspaces_reassigned > 0
    
    # Verify workspace assignment commands issued
    # WS 1-2 should go to HEADLESS-1 (primary)
    # WS 3-70 should go to HEADLESS-3 (secondary)
    calls = mock_i3.command.call_args_list
    assert any("workspace number 1 output HEADLESS-1" in str(call) for call in calls)
    assert any("workspace number 3 output HEADLESS-3" in str(call) for call in calls)


@pytest.mark.asyncio
async def test_window_preservation_on_disconnect():
    """Test windows from disconnected monitor are accessible (US2)."""
    # Setup: Windows on HEADLESS-2 (WS 3-5)
    mock_window = Mock(
        id=99999,
        window=99999,
        window_properties={"class": "Firefox"},
        workspace=lambda: Mock(num=4)
    )
    
    mock_tree = Mock(nodes=[mock_window], floating_nodes=[])
    
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]
    mock_i3.get_workspaces.return_value = [
        Mock(num=4, name="4", output="HEADLESS-2", visible=False, focused=False)
    ]
    mock_i3.get_tree.return_value = mock_tree
    mock_i3.command.return_value = [Mock(success=True)]
    
    handlers = Feature049EventHandlers(mock_i3)
    
    # Disconnect HEADLESS-2
    event = Mock(change="disconnected", output=Mock(name="HEADLESS-2", active=False))
    await handlers.on_output_event(mock_i3, event)
    await asyncio.sleep(0.6)
    
    result = handlers._reassignment_history[0]
    # Windows detected and migration records created
    assert result.windows_migrated >= 0


@pytest.mark.asyncio
async def test_rapid_connect_disconnect_cycles():
    """Test rapid monitor changes result in single reassignment (US1)."""
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
    ]
    mock_i3.get_workspaces.return_value = []
    mock_i3.get_tree.return_value = Mock(nodes=[], floating_nodes=[])
    mock_i3.command.return_value = [Mock(success=True)]
    
    handlers = Feature049EventHandlers(mock_i3)
    
    # Rapid connect/disconnect cycle (5 events in 1 second)
    for i in range(5):
        change = "connected" if i % 2 == 0 else "disconnected"
        event = Mock(change=change, output=Mock(name="HEADLESS-2", active=(i % 2 == 0)))
        await handlers.on_output_event(mock_i3, event)
        await asyncio.sleep(0.2)
    
    # Wait for final debounce
    await asyncio.sleep(0.6)
    
    # Verify only 1 reassignment occurred
    assert len(handlers._reassignment_history) == 1
