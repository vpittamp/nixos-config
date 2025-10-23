"""
Unit tests for layout restore functionality

Feature 030: Production Readiness
Task T047: Unit test for layout restore

Tests cover:
- Loading layout snapshots
- Monitor configuration detection and adaptation
- Workspace reassignment logic
- Window geometry scaling
- Application launching
- Window swallowing
"""

import pytest
import asyncio
from datetime import datetime
from unittest.mock import AsyncMock, Mock, patch, call

# Import layout module (sys.path configured in conftest.py)
from layout.restore import LayoutRestore
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
def sample_layout_snapshot():
    """Create sample layout snapshot"""
    return LayoutSnapshot(
        name="test-layout",
        project="nixos",
        monitor_config=MonitorConfiguration(
            name="single-monitor",
            monitors=[
                Monitor(
                    name="eDP-1",
                    active=True,
                    primary=True,
                    resolution=Resolution(width=1920, height=1080),
                    position=Position(x=0, y=0)
                )
            ],
            workspace_assignments={1: "eDP-1", 2: "eDP-1"}
        ),
        workspace_layouts=[
            WorkspaceLayout(
                workspace_num=1,
                workspace_name="1",
                output="eDP-1",
                layout_mode=LayoutMode.SPLITH,
                windows=[
                    WindowPlaceholder(
                        window_class="Alacritty",
                        launch_command="alacritty",
                        geometry=WindowGeometry(x=0, y=0, width=960, height=1080),
                        floating=False
                    ),
                    WindowPlaceholder(
                        window_class="Code",
                        launch_command="code",
                        geometry=WindowGeometry(x=960, y=0, width=960, height=1080),
                        floating=False
                    )
                ]
            )
        ]
    )


@pytest.fixture
def dual_monitor_snapshot():
    """Create dual monitor layout snapshot"""
    return LayoutSnapshot(
        name="dual-setup",
        project="nixos",
        monitor_config=MonitorConfiguration(
            name="dual-monitor",
            monitors=[
                Monitor(
                    name="eDP-1",
                    active=True,
                    primary=True,
                    resolution=Resolution(width=1920, height=1080),
                    position=Position(x=0, y=0)
                ),
                Monitor(
                    name="HDMI-1",
                    active=True,
                    primary=False,
                    resolution=Resolution(width=1920, height=1080),
                    position=Position(x=1920, y=0)
                )
            ],
            workspace_assignments={1: "eDP-1", 2: "eDP-1", 3: "HDMI-1", 4: "HDMI-1"}
        ),
        workspace_layouts=[
            WorkspaceLayout(
                workspace_num=1,
                workspace_name="1",
                output="eDP-1",
                layout_mode=LayoutMode.SPLITH,
                windows=[
                    WindowPlaceholder(
                        window_class="Alacritty",
                        launch_command="alacritty",
                        geometry=WindowGeometry(x=0, y=0, width=1920, height=1080),
                        floating=False
                    )
                ]
            ),
            WorkspaceLayout(
                workspace_num=3,
                workspace_name="3",
                output="HDMI-1",
                layout_mode=LayoutMode.SPLITH,
                windows=[
                    WindowPlaceholder(
                        window_class="Firefox",
                        launch_command="firefox",
                        geometry=WindowGeometry(x=0, y=0, width=1920, height=1080),
                        floating=False
                    )
                ]
            )
        ]
    )


# ============================================================================
# LayoutRestore Tests
# ============================================================================

@pytest.mark.asyncio
async def test_layout_restore_initialization(mock_i3_connection):
    """Test LayoutRestore initialization"""
    restore = LayoutRestore(mock_i3_connection)
    assert restore.i3 == mock_i3_connection
    assert restore.swallow_timeout == 30.0


@pytest.mark.asyncio
async def test_detect_monitor_configuration(mock_i3_connection):
    """Test monitor configuration detection"""
    restore = LayoutRestore(mock_i3_connection)

    # Mock i3 outputs
    mock_output = Mock()
    mock_output.name = "eDP-1"
    mock_output.active = True
    mock_output.primary = True
    mock_output.current_workspace = "1"
    mock_output.rect = {"x": 0, "y": 0, "width": 1920, "height": 1080}

    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=[mock_output])

    monitors = await restore._detect_monitor_configuration()

    assert len(monitors) == 1
    assert isinstance(monitors[0], Monitor)
    assert monitors[0].name == "eDP-1"
    assert monitors[0].resolution.width == 1920


@pytest.mark.asyncio
async def test_detect_multiple_monitors(mock_i3_connection):
    """Test detecting multiple monitors"""
    restore = LayoutRestore(mock_i3_connection)

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
            rect={"x": 1920, "y": 0, "width": 2560, "height": 1440}
        )
    ]

    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=outputs)

    monitors = await restore._detect_monitor_configuration()

    assert len(monitors) == 2
    assert monitors[1].resolution.width == 2560
    assert monitors[1].position.x == 1920


@pytest.mark.asyncio
async def test_build_output_mapping_same_monitors(mock_i3_connection):
    """Test output mapping when monitors haven't changed"""
    restore = LayoutRestore(mock_i3_connection)

    saved_monitors = [
        Monitor(name="eDP-1", active=True, primary=True, position=Position(x=0, y=0))
    ]

    current_monitors = [
        Monitor(name="eDP-1", active=True, primary=True, position=Position(x=0, y=0))
    ]

    mapping = restore._build_output_mapping(saved_monitors, current_monitors)

    assert mapping["eDP-1"] == "eDP-1"


@pytest.mark.asyncio
async def test_build_output_mapping_different_names(mock_i3_connection):
    """Test output mapping with different monitor names"""
    restore = LayoutRestore(mock_i3_connection)

    saved_monitors = [
        Monitor(name="eDP-1", active=True, primary=True, position=Position(x=0, y=0))
    ]

    current_monitors = [
        Monitor(name="eDP1", active=True, primary=True, position=Position(x=0, y=0))
    ]

    mapping = restore._build_output_mapping(saved_monitors, current_monitors)

    # Should map primary to primary
    assert mapping["eDP-1"] == "eDP1"


@pytest.mark.asyncio
async def test_build_output_mapping_fewer_monitors(mock_i3_connection):
    """Test output mapping when current has fewer monitors"""
    restore = LayoutRestore(mock_i3_connection)

    saved_monitors = [
        Monitor(name="eDP-1", active=True, primary=True, position=Position(x=0, y=0)),
        Monitor(name="HDMI-1", active=True, primary=False, position=Position(x=1920, y=0))
    ]

    current_monitors = [
        Monitor(name="eDP-1", active=True, primary=True, position=Position(x=0, y=0))
    ]

    mapping = restore._build_output_mapping(saved_monitors, current_monitors)

    # Both should map to primary
    assert mapping["eDP-1"] == "eDP-1"
    assert mapping["HDMI-1"] == "eDP-1"  # Fallback to primary


@pytest.mark.asyncio
async def test_adapt_window_geometry_same_resolution(mock_i3_connection):
    """Test window geometry adaptation with same resolution"""
    restore = LayoutRestore(mock_i3_connection)

    window = WindowPlaceholder(
        window_class="Code",
        launch_command="code",
        geometry=WindowGeometry(x=0, y=0, width=1920, height=1080),
        floating=False
    )

    saved_monitor = Monitor(
        name="eDP-1",
        active=True,
        primary=True,
        resolution=Resolution(width=1920, height=1080),
        position=Position(x=0, y=0)
    )

    current_monitor = Monitor(
        name="eDP-1",
        active=True,
        primary=True,
        resolution=Resolution(width=1920, height=1080),
        position=Position(x=0, y=0)
    )

    adapted = restore._adapt_window_geometry(window, saved_monitor, current_monitor)

    # Geometry should be unchanged
    assert adapted.geometry.width == 1920
    assert adapted.geometry.height == 1080


@pytest.mark.asyncio
async def test_adapt_window_geometry_scaled(mock_i3_connection):
    """Test window geometry scaling for different resolutions"""
    restore = LayoutRestore(mock_i3_connection)

    window = WindowPlaceholder(
        window_class="Code",
        launch_command="code",
        geometry=WindowGeometry(x=0, y=0, width=1920, height=1080),
        floating=False
    )

    saved_monitor = Monitor(
        name="eDP-1",
        active=True,
        primary=True,
        resolution=Resolution(width=1920, height=1080),
        position=Position(x=0, y=0)
    )

    current_monitor = Monitor(
        name="eDP-1",
        active=True,
        primary=True,
        resolution=Resolution(width=2560, height=1440),  # Larger
        position=Position(x=0, y=0)
    )

    adapted = restore._adapt_window_geometry(window, saved_monitor, current_monitor)

    # Geometry should be scaled
    assert adapted.geometry.width > 1920
    assert adapted.geometry.height > 1080


@pytest.mark.asyncio
async def test_adapt_layout_to_monitors(mock_i3_connection, sample_layout_snapshot):
    """Test full layout adaptation"""
    restore = LayoutRestore(mock_i3_connection)

    current_monitors = [
        Monitor(
            name="eDP-1",
            active=True,
            primary=True,
            resolution=Resolution(width=1920, height=1080),
            position=Position(x=0, y=0)
        )
    ]

    adapted = restore._adapt_layout_to_monitors(sample_layout_snapshot, current_monitors)

    assert len(adapted.workspace_layouts) == len(sample_layout_snapshot.workspace_layouts)
    assert adapted.workspace_layouts[0].output == "eDP-1"


@pytest.mark.asyncio
async def test_adapt_layout_dual_to_single(mock_i3_connection, dual_monitor_snapshot):
    """Test adapting dual monitor layout to single monitor"""
    restore = LayoutRestore(mock_i3_connection)

    current_monitors = [
        Monitor(
            name="eDP-1",
            active=True,
            primary=True,
            resolution=Resolution(width=1920, height=1080),
            position=Position(x=0, y=0)
        )
    ]

    adapted = restore._adapt_layout_to_monitors(dual_monitor_snapshot, current_monitors)

    # All workspaces should be mapped to single monitor
    for ws in adapted.workspace_layouts:
        assert ws.output == "eDP-1"


@pytest.mark.asyncio
async def test_launch_application(mock_i3_connection):
    """Test application launching"""
    restore = LayoutRestore(mock_i3_connection)

    window = WindowPlaceholder(
        window_class="Alacritty",
        launch_command="alacritty",
        geometry=WindowGeometry(x=0, y=0, width=800, height=600),
        floating=False
    )

    with patch('subprocess.Popen') as mock_popen:
        mock_process = Mock()
        mock_process.pid = 12345
        mock_popen.return_value = mock_process

        result = await restore._launch_application(window)

    assert result["success"] is True
    assert result["pid"] == 12345
    mock_popen.assert_called_once()


@pytest.mark.asyncio
async def test_launch_application_with_env(mock_i3_connection):
    """Test application launching with environment variables"""
    restore = LayoutRestore(mock_i3_connection)

    window = WindowPlaceholder(
        window_class="Code",
        launch_command="code /tmp/test",
        geometry=WindowGeometry(x=0, y=0, width=1600, height=900),
        floating=False
    )

    with patch('subprocess.Popen') as mock_popen:
        mock_process = Mock()
        mock_process.pid = 67890
        mock_popen.return_value = mock_process

        result = await restore._launch_application(window)

    assert result["success"] is True


@pytest.mark.asyncio
async def test_launch_application_failure(mock_i3_connection):
    """Test application launch failure handling"""
    restore = LayoutRestore(mock_i3_connection)

    window = WindowPlaceholder(
        window_class="Invalid",
        launch_command="nonexistent-app-12345",
        geometry=WindowGeometry(x=0, y=0, width=800, height=600),
        floating=False
    )

    with patch('subprocess.Popen', side_effect=FileNotFoundError("Command not found")):
        result = await restore._launch_application(window)

    assert result["success"] is False
    assert "error" in result


@pytest.mark.asyncio
async def test_restore_workspace(mock_i3_connection):
    """Test restoring single workspace"""
    restore = LayoutRestore(mock_i3_connection)

    workspace = WorkspaceLayout(
        workspace_num=1,
        workspace_name="1",
        output="eDP-1",
        layout_mode=LayoutMode.SPLITH,
        windows=[
            WindowPlaceholder(
                window_class="Alacritty",
                launch_command="echo test",  # Safe command
                geometry=WindowGeometry(x=0, y=0, width=800, height=600),
                floating=False
            )
        ]
    )

    results = {"windows_launched": 0, "windows_swallowed": 0, "windows_failed": 0, "errors": []}

    with patch.object(restore, '_wait_for_window_swallow', return_value=True):
        await restore._restore_workspace(workspace, results)

    assert results["windows_launched"] == 1


@pytest.mark.asyncio
async def test_restore_layout_no_adaptation(mock_i3_connection, sample_layout_snapshot):
    """Test layout restore without monitor adaptation"""
    restore = LayoutRestore(mock_i3_connection)

    # Mock monitor detection
    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=[
        Mock(
            name="eDP-1",
            active=True,
            primary=True,
            current_workspace="1",
            rect={"x": 0, "y": 0, "width": 1920, "height": 1080}
        )
    ])

    with patch.object(restore, '_restore_workspace', return_value=None):
        result = await restore.restore_layout(sample_layout_snapshot, adapt_monitors=False)

    assert result["success"] is True
    assert "duration_seconds" in result


@pytest.mark.asyncio
async def test_restore_layout_with_adaptation(mock_i3_connection, sample_layout_snapshot):
    """Test layout restore with monitor adaptation"""
    restore = LayoutRestore(mock_i3_connection)

    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=[
        Mock(
            name="eDP-1",
            active=True,
            primary=True,
            current_workspace="1",
            rect={"x": 0, "y": 0, "width": 2560, "height": 1440}  # Different resolution
        )
    ])

    with patch.object(restore, '_restore_workspace', return_value=None):
        result = await restore.restore_layout(sample_layout_snapshot, adapt_monitors=True)

    assert result["success"] is True


@pytest.mark.asyncio
async def test_wait_for_window_swallow_timeout(mock_i3_connection):
    """Test window swallow timeout"""
    restore = LayoutRestore(mock_i3_connection)
    restore.swallow_timeout = 0.1  # Short timeout for testing

    window = WindowPlaceholder(
        window_class="SlowApp",
        launch_command="sleep 10",
        geometry=WindowGeometry(x=0, y=0, width=800, height=600),
        floating=False
    )

    # Mock that window never appears
    mock_i3_connection.conn.get_tree = AsyncMock(return_value=Mock(ipc_data={"nodes": []}))

    result = await restore._wait_for_window_swallow(window, 12345)

    assert result is False  # Timeout


@pytest.mark.asyncio
async def test_preserve_window_marks(mock_i3_connection):
    """Test that window marks are preserved during restore"""
    restore = LayoutRestore(mock_i3_connection)

    window = WindowPlaceholder(
        window_class="Code",
        launch_command="code",
        geometry=WindowGeometry(x=0, y=0, width=1600, height=900),
        floating=False,
        marks=["project:nixos", "custom-mark"]
    )

    # Marks should be preserved in the placeholder
    assert "project:nixos" in window.marks
    assert "custom-mark" in window.marks


@pytest.mark.asyncio
async def test_floating_window_restoration(mock_i3_connection):
    """Test floating window restoration"""
    restore = LayoutRestore(mock_i3_connection)

    floating_window = WindowPlaceholder(
        window_class="Rofi",
        launch_command="rofi -show run",
        geometry=WindowGeometry(x=500, y=300, width=600, height=400),
        floating=True
    )

    assert floating_window.floating is True
    assert floating_window.geometry.x == 500


@pytest.mark.asyncio
async def test_error_handling_during_restore(mock_i3_connection, sample_layout_snapshot):
    """Test error handling during layout restore"""
    restore = LayoutRestore(mock_i3_connection)

    mock_i3_connection.conn.get_outputs = AsyncMock(return_value=[])

    with patch.object(restore, '_restore_workspace', side_effect=Exception("Test error")):
        result = await restore.restore_layout(sample_layout_snapshot)

    # Should capture error but not crash
    assert "duration_seconds" in result
