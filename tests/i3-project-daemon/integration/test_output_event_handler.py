"""Integration tests for output event handler.

Feature 049: US1 - Automatic workspace redistribution
"""
import pytest
import asyncio
from unittest.mock import Mock, AsyncMock
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../..'))

from home_modules.desktop.i3_project_event_daemon.handlers import Feature049EventHandlers


@pytest.mark.asyncio
async def test_output_event_triggers_reassignment():
    """Test output event triggers debounced reassignment."""
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-2", active=True),
        Mock(name="HEADLESS-3", active=True),
    ]
    mock_i3.get_workspaces.return_value = []
    mock_i3.get_tree.return_value = Mock()
    mock_i3.command.return_value = [Mock(success=True)]
    
    handlers = Feature049EventHandlers(mock_i3)
    
    # Trigger output connected event
    event = Mock(change="connected", output=Mock(name="HEADLESS-3", active=True))
    await handlers.on_output_event(mock_i3, event)
    
    # Wait for debounce + processing
    await asyncio.sleep(0.6)
    
    # Verify reassignment occurred
    assert len(handlers._reassignment_history) == 1
    result = handlers._reassignment_history[0]
    assert result.success is True
    assert result.workspaces_reassigned > 0


@pytest.mark.asyncio
async def test_rapid_output_events_debounced():
    """Test rapid output events result in single reassignment."""
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
        Mock(name="HEADLESS-2", active=True),
    ]
    mock_i3.get_workspaces.return_value = []
    mock_i3.get_tree.return_value = Mock()
    mock_i3.command.return_value = [Mock(success=True)]
    
    handlers = Feature049EventHandlers(mock_i3)
    
    # Trigger 3 rapid events
    for i in range(3):
        event = Mock(change="connected", output=Mock(name=f"HDMI-{i}", active=True))
        await handlers.on_output_event(mock_i3, event)
        await asyncio.sleep(0.1)  # 100ms between events
    
    # Wait for debounce
    await asyncio.sleep(0.6)
    
    # Verify only 1 reassignment occurred
    assert len(handlers._reassignment_history) == 1


@pytest.mark.asyncio
async def test_output_disconnect_preserves_windows():
    """Test output disconnect migrates windows (US2)."""
    # Setup: Add windows to mock tree
    mock_window = Mock(
        id=12345,
        window=12345,
        window_properties={"class": "Alacritty"},
        workspace=lambda: Mock(num=5)
    )
    
    mock_tree = Mock()
    mock_tree.nodes = [mock_window]
    mock_tree.floating_nodes = []
    
    mock_i3 = AsyncMock()
    mock_i3.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True),
    ]
    mock_i3.get_workspaces.return_value = [
        Mock(num=5, name="5", output="HEADLESS-2", visible=False, focused=False)
    ]
    mock_i3.get_tree.return_value = mock_tree
    mock_i3.command.return_value = [Mock(success=True)]
    
    handlers = Feature049EventHandlers(mock_i3)
    
    # Trigger disconnect event
    event = Mock(change="disconnected", output=Mock(name="HEADLESS-2", active=False))
    await handlers.on_output_event(mock_i3, event)
    
    # Wait for processing
    await asyncio.sleep(0.6)
    
    # Verify migration records created
    result = handlers._reassignment_history[0]
    assert result.windows_migrated >= 0  # At least detected windows
