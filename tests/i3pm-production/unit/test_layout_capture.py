"""
Unit tests for layout capture functionality

Feature 030: Production Readiness
Task T046: Unit test for layout capture

Tests cover:
- Capturing workspace layouts from i3 tree
- Extracting window properties and geometry
- Monitor configuration detection
- Launch command discovery
- Snapshot serialization
"""

import pytest
import asyncio
from datetime import datetime
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

# Import layout module (sys.path configured in conftest.py)
from layout.capture import LayoutCapture
from layout.models import (
    LayoutSnapshot, WorkspaceLayout, WindowPlaceholder, Monitor,
    MonitorConfiguration, WindowGeometry, Resolution, Position, LayoutMode
)


# ============================================================================
# Test Fixtures
# ============================================================================

@pytest.fixture
def mock_i3_connection():
    """Create mock i3 connection"""
    mock_conn = Mock()
    mock_conn.conn = AsyncMock()
    return mock_conn


@pytest.fixture
def sample_i3_tree():
    """Sample i3 tree structure"""
    return {
        "nodes": [
            {
                "type": "output",
                "name": "eDP-1",
                "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                "nodes": [
                    {
                        "type": "con",
                        "nodes": [
                            {
                                "type": "workspace",
                                "num": 1,
                                "name": "1",
                                "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                                "nodes": [
                                    {
                                        "type": "con",
                                        "window": 12345,
                                        "window_properties": {
                                            "class": "Alacritty",
                                            "instance": "Alacritty",
                                            "title": "Terminal"
                                        },
                                        "rect": {"x": 0, "y": 0, "width": 960, "height": 1080},
                                        "geometry": {"x": 0, "y": 0, "width": 960, "height": 1080},
                                        "floating": "auto_off",
                                        "marks": ["project:nixos"],
                                    },
                                    {
                                        "type": "con",
                                        "window": 67890,
                                        "window_properties": {
                                            "class": "Code",
                                            "instance": "code",
                                            "title": "test.py - VSCode"
                                        },
                                        "rect": {"x": 960, "y": 0, "width": 960, "height": 1080},
                                        "geometry": {"x": 960, "y": 0, "width": 960, "height": 1080},
                                        "floating": "auto_off",
                                        "marks": ["project:nixos"],
                                    }
                                ]
                            }
                        ]
                    }
                ]
            }
        ]
    }


@pytest.fixture
def sample_i3_outputs():
    """Sample i3 outputs"""
    output = Mock()
    output.name = "eDP-1"
    output.active = True
    output.primary = True
    output.current_workspace = "1"
    output.rect = {"x": 0, "y": 0, "width": 1920, "height": 1080}
    return [output]


# ============================================================================
# LayoutCapture Tests
# ============================================================================

@pytest.mark.asyncio
async def test_layout_capture_initialization(mock_i3_connection):
    """Test LayoutCapture initialization"""
    capture = LayoutCapture(mock_i3_connection)
    assert capture.i3 == mock_i3_connection
    assert capture.command_discovery is not None


@pytest.mark.asyncio
async def test_capture_layout_basic(mock_i3_connection, sample_i3_tree, sample_i3_outputs):
    """Test basic layout capture"""
    capture = LayoutCapture(mock_i3_connection)

    # Mock i3 methods
    mock_i3_connection.conn.get_tree = AsyncMock(return_value=Mock(ipc_data=sample_i3_tree))
    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=sample_i3_outputs)

    # Mock command discovery
    with patch.object(capture, '_discover_launch_command', return_value="alacritty"):
        snapshot = await capture.capture_layout(name="test-layout", project="nixos")

    assert isinstance(snapshot, LayoutSnapshot)
    assert snapshot.name == "test-layout"
    assert snapshot.project == "nixos"
    assert isinstance(snapshot.created_at, datetime)


@pytest.mark.asyncio
async def test_capture_monitor_configuration(mock_i3_connection, sample_i3_outputs):
    """Test monitor configuration capture"""
    capture = LayoutCapture(mock_i3_connection)
    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=sample_i3_outputs)

    monitors = await capture._capture_monitors()

    assert len(monitors) == 1
    assert isinstance(monitors[0], Monitor)
    assert monitors[0].name == "eDP-1"
    assert monitors[0].active is True
    assert monitors[0].primary is True
    assert monitors[0].resolution.width == 1920
    assert monitors[0].resolution.height == 1080


@pytest.mark.asyncio
async def test_capture_workspace_layout(mock_i3_connection, sample_i3_tree):
    """Test workspace layout extraction"""
    capture = LayoutCapture(mock_i3_connection)

    # Extract workspace from tree
    workspace_node = sample_i3_tree["nodes"][0]["nodes"][0]["nodes"][0]

    with patch.object(capture, '_discover_launch_command', return_value="test-command"):
        workspace_layout = await capture._capture_workspace(workspace_node, "eDP-1")

    assert isinstance(workspace_layout, WorkspaceLayout)
    assert workspace_layout.workspace_num == 1
    assert workspace_layout.workspace_name == "1"
    assert workspace_layout.output == "eDP-1"
    assert len(workspace_layout.windows) == 2


@pytest.mark.asyncio
async def test_capture_window_placeholder(mock_i3_connection):
    """Test window placeholder creation"""
    capture = LayoutCapture(mock_i3_connection)

    window_node = {
        "window": 12345,
        "window_properties": {
            "class": "Alacritty",
            "instance": "Alacritty",
            "title": "Terminal"
        },
        "rect": {"x": 0, "y": 0, "width": 800, "height": 600},
        "geometry": {"x": 0, "y": 0, "width": 800, "height": 600},
        "floating": "auto_off",
        "marks": ["project:nixos"],
    }

    with patch.object(capture, '_discover_launch_command', return_value="alacritty"):
        placeholder = await capture._create_window_placeholder(window_node)

    assert isinstance(placeholder, WindowPlaceholder)
    assert placeholder.window_class == "Alacritty"
    assert placeholder.launch_command == "alacritty"
    assert placeholder.geometry.width == 800
    assert placeholder.geometry.height == 600
    assert placeholder.floating is False
    assert "project:nixos" in placeholder.marks


@pytest.mark.asyncio
async def test_capture_floating_window(mock_i3_connection):
    """Test floating window capture"""
    capture = LayoutCapture(mock_i3_connection)

    floating_node = {
        "window": 99999,
        "window_properties": {
            "class": "Rofi",
            "instance": "rofi",
            "title": "rofi"
        },
        "rect": {"x": 500, "y": 300, "width": 600, "height": 400},
        "geometry": {"x": 500, "y": 300, "width": 600, "height": 400},
        "floating": "user_on",
        "marks": [],
    }

    with patch.object(capture, '_discover_launch_command', return_value="rofi"):
        placeholder = await capture._create_window_placeholder(floating_node)

    assert placeholder.floating is True


@pytest.mark.asyncio
async def test_capture_multiple_monitors(mock_i3_connection):
    """Test multi-monitor configuration capture"""
    capture = LayoutCapture(mock_i3_connection)

    outputs = [
        Mock(
            name="eDP-1",
            active=True,
            primary=True,
            current_workspace="1",
            rect={"x": 0, "y": 0, "width": 1920, "height": 1080}
        ),
        Mock(
            name="HDMI-1",
            active=True,
            primary=False,
            current_workspace="3",
            rect={"x": 1920, "y": 0, "width": 1920, "height": 1080}
        ),
    ]

    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=outputs)
    monitors = await capture._capture_monitors()

    assert len(monitors) == 2
    assert monitors[0].name == "eDP-1"
    assert monitors[0].primary is True
    assert monitors[1].name == "HDMI-1"
    assert monitors[1].position.x == 1920


@pytest.mark.asyncio
async def test_capture_ignores_inactive_monitors(mock_i3_connection):
    """Test inactive monitors are ignored"""
    capture = LayoutCapture(mock_i3_connection)

    outputs = [
        Mock(
            name="eDP-1",
            active=True,
            primary=True,
            current_workspace="1",
            rect={"x": 0, "y": 0, "width": 1920, "height": 1080}
        ),
        Mock(
            name="DP-1",
            active=False,
            primary=False,
            current_workspace=None,
            rect={"x": 0, "y": 0, "width": 0, "height": 0}
        ),
    ]

    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=outputs)
    monitors = await capture._capture_monitors()

    assert len(monitors) == 1
    assert monitors[0].name == "eDP-1"


@pytest.mark.asyncio
async def test_capture_window_without_class(mock_i3_connection):
    """Test capturing window without WM_CLASS"""
    capture = LayoutCapture(mock_i3_connection)

    window_node = {
        "window": 12345,
        "window_properties": {
            "title": "Unknown Window"
        },
        "rect": {"x": 0, "y": 0, "width": 800, "height": 600},
        "geometry": {"x": 0, "y": 0, "width": 800, "height": 600},
        "floating": "auto_off",
        "marks": [],
    }

    with patch.object(capture, '_discover_launch_command', return_value="unknown"):
        placeholder = await capture._create_window_placeholder(window_node)

    assert placeholder.window_class is None
    assert placeholder.title_pattern is not None


@pytest.mark.asyncio
async def test_capture_preserves_marks(mock_i3_connection):
    """Test window marks are preserved"""
    capture = LayoutCapture(mock_i3_connection)

    window_node = {
        "window": 12345,
        "window_properties": {
            "class": "Code",
            "instance": "code",
            "title": "test.py"
        },
        "rect": {"x": 0, "y": 0, "width": 800, "height": 600},
        "geometry": {"x": 0, "y": 0, "width": 800, "height": 600},
        "floating": "auto_off",
        "marks": ["project:nixos", "custom-mark", "_i3_resize"],
    }

    with patch.object(capture, '_discover_launch_command', return_value="code"):
        placeholder = await capture._create_window_placeholder(window_node)

    assert len(placeholder.marks) == 3
    assert "project:nixos" in placeholder.marks
    assert "custom-mark" in placeholder.marks


@pytest.mark.asyncio
async def test_capture_layout_empty_workspace(mock_i3_connection):
    """Test capturing workspace with no windows"""
    capture = LayoutCapture(mock_i3_connection)

    empty_workspace = {
        "type": "workspace",
        "num": 5,
        "name": "5:empty",
        "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
        "nodes": []
    }

    workspace_layout = await capture._capture_workspace(empty_workspace, "eDP-1")

    assert workspace_layout.workspace_num == 5
    assert workspace_layout.workspace_name == "5:empty"
    assert len(workspace_layout.windows) == 0


@pytest.mark.asyncio
async def test_monitor_configuration_validation(mock_i3_connection, sample_i3_outputs):
    """Test MonitorConfiguration validation"""
    capture = LayoutCapture(mock_i3_connection)
    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=sample_i3_outputs)

    monitors = await capture._capture_monitors()

    # Should create valid MonitorConfiguration
    config = MonitorConfiguration(
        name="test-config",
        monitors=monitors,
        workspace_assignments={1: "eDP-1", 2: "eDP-1"}
    )

    assert config.name == "test-config"
    assert len(config.monitors) == 1
    assert config.workspace_assignments[1] == "eDP-1"


@pytest.mark.asyncio
async def test_capture_layout_metadata(mock_i3_connection, sample_i3_tree, sample_i3_outputs):
    """Test snapshot includes metadata"""
    capture = LayoutCapture(mock_i3_connection)

    mock_i3_connection.conn.get_tree = AsyncMock(return_value=Mock(ipc_data=sample_i3_tree))
    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=sample_i3_outputs)

    with patch.object(capture, '_discover_launch_command', return_value="test"):
        snapshot = await capture.capture_layout(
            name="test",
            project="nixos",
            metadata={"description": "Test layout", "tags": ["dev", "work"]}
        )

    assert snapshot.metadata.get("description") == "Test layout"
    assert "dev" in snapshot.metadata.get("tags", [])


# ============================================================================
# Command Discovery Tests (subset - full tests in test_command_discovery.py)
# ============================================================================

@pytest.mark.asyncio
async def test_discover_launch_command_from_desktop_file(mock_i3_connection):
    """Test discovering launch command from .desktop file"""
    capture = LayoutCapture(mock_i3_connection)

    with patch('layout.capture.Path.glob') as mock_glob:
        # Mock finding desktop file
        mock_desktop = Mock()
        mock_desktop.read_text.return_value = """[Desktop Entry]
Name=Alacritty
Exec=alacritty
"""
        mock_glob.return_value = [mock_desktop]

        command = capture._discover_launch_command("Alacritty", None, "Terminal")

    assert command == "alacritty"


@pytest.mark.asyncio
async def test_discover_launch_command_fallback(mock_i3_connection):
    """Test command discovery fallback to class name"""
    capture = LayoutCapture(mock_i3_connection)

    with patch('layout.capture.Path.glob', return_value=[]):
        with patch('shutil.which', return_value="/usr/bin/firefox"):
            command = capture._discover_launch_command("Firefox", None, "Browser")

    assert command == "firefox"


# ============================================================================
# Serialization Tests
# ============================================================================

@pytest.mark.asyncio
async def test_snapshot_serialization(mock_i3_connection, sample_i3_tree, sample_i3_outputs):
    """Test layout snapshot can be serialized"""
    capture = LayoutCapture(mock_i3_connection)

    mock_i3_connection.conn.get_tree = AsyncMock(return_value=Mock(ipc_data=sample_i3_tree))
    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=sample_i3_outputs)

    with patch.object(capture, '_discover_launch_command', return_value="test"):
        snapshot = await capture.capture_layout(name="test", project="nixos")

    # Should serialize without errors
    data = snapshot.model_dump(mode='python')

    assert data["name"] == "test"
    assert data["project"] == "nixos"
    assert "monitor_config" in data
    assert "workspace_layouts" in data


@pytest.mark.asyncio
async def test_snapshot_deserialization(mock_i3_connection, sample_i3_tree, sample_i3_outputs):
    """Test layout snapshot can be deserialized"""
    capture = LayoutCapture(mock_i3_connection)

    mock_i3_connection.conn.get_tree = AsyncMock(return_value=Mock(ipc_data=sample_i3_tree))
    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=sample_i3_outputs)

    with patch.object(capture, '_discover_launch_command', return_value="test"):
        original = await capture.capture_layout(name="test", project="nixos")

    # Serialize and deserialize
    data = original.model_dump(mode='python')
    restored = LayoutSnapshot(**data)

    assert restored.name == original.name
    assert restored.project == original.project
    assert len(restored.workspace_layouts) == len(original.workspace_layouts)
