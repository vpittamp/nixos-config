"""Mock fixtures for i3 IPC connection testing.

Feature 049: Intelligent Automatic Workspace-to-Monitor Assignment
"""
import pytest
from unittest.mock import AsyncMock, Mock
from i3ipc.aio import Connection


@pytest.fixture
async def mock_i3_connection():
    """Mock i3 IPC connection for testing."""
    conn = AsyncMock(spec=Connection)
    conn.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True, primary=True, current_workspace="1",
             rect=Mock(x=0, y=0, width=1920, height=1080),
             make="Virtual", model="Headless-1", serial="001"),
        Mock(name="HEADLESS-2", active=True, primary=False, current_workspace="3",
             rect=Mock(x=1920, y=0, width=1920, height=1080),
             make="Virtual", model="Headless-2", serial="002"),
        Mock(name="HEADLESS-3", active=True, primary=False, current_workspace="6",
             rect=Mock(x=3840, y=0, width=1920, height=1080),
             make="Virtual", model="Headless-3", serial="003"),
    ]
    conn.get_workspaces.return_value = [
        Mock(num=1, name="1", output="HEADLESS-1", visible=True, focused=True),
        Mock(num=2, name="2", output="HEADLESS-1", visible=False, focused=False),
        Mock(num=3, name="3", output="HEADLESS-2", visible=True, focused=False),
        Mock(num=4, name="4", output="HEADLESS-2", visible=False, focused=False),
        Mock(num=5, name="5", output="HEADLESS-2", visible=False, focused=False),
        Mock(num=6, name="6", output="HEADLESS-3", visible=True, focused=False),
        Mock(num=7, name="7", output="HEADLESS-3", visible=False, focused=False),
    ]
    conn.get_tree.return_value = Mock()  # Tree structure mock
    conn.command.return_value = [Mock(success=True)]
    return conn


@pytest.fixture
def mock_output_event_connected():
    """Mock output connected event."""
    return Mock(
        change="connected",
        output=Mock(name="HEADLESS-3", active=True,
                    rect=Mock(x=3840, y=0, width=1920, height=1080))
    )


@pytest.fixture
def mock_output_event_disconnected():
    """Mock output disconnected event."""
    return Mock(
        change="disconnected",
        output=Mock(name="HEADLESS-2", active=False)
    )


@pytest.fixture
def mock_i3_connection_single_monitor():
    """Mock i3 connection with single monitor."""
    conn = AsyncMock(spec=Connection)
    conn.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True, primary=True, current_workspace="1",
             rect=Mock(x=0, y=0, width=1920, height=1080),
             make="Virtual", model="Headless-1", serial="001"),
    ]
    conn.get_workspaces.return_value = [
        Mock(num=1, name="1", output="HEADLESS-1", visible=True, focused=True),
    ]
    conn.get_tree.return_value = Mock()
    conn.command.return_value = [Mock(success=True)]
    return conn


@pytest.fixture
def mock_i3_connection_two_monitors():
    """Mock i3 connection with two monitors."""
    conn = AsyncMock(spec=Connection)
    conn.get_outputs.return_value = [
        Mock(name="HEADLESS-1", active=True, primary=True, current_workspace="1",
             rect=Mock(x=0, y=0, width=1920, height=1080),
             make="Virtual", model="Headless-1", serial="001"),
        Mock(name="HEADLESS-2", active=True, primary=False, current_workspace="3",
             rect=Mock(x=1920, y=0, width=1920, height=1080),
             make="Virtual", model="Headless-2", serial="002"),
    ]
    conn.get_workspaces.return_value = [
        Mock(num=1, name="1", output="HEADLESS-1", visible=True, focused=True),
        Mock(num=2, name="2", output="HEADLESS-1", visible=False, focused=False),
        Mock(num=3, name="3", output="HEADLESS-2", visible=True, focused=False),
    ]
    conn.get_tree.return_value = Mock()
    conn.command.return_value = [Mock(success=True)]
    return conn
