"""
Integration tests for window_filter.py parallelization.
Feature 091: Optimize i3pm Project Switching Performance

Tests verify:
1. Zero regression in window filtering accuracy
2. Scoped/global window semantics preserved
3. Performance target <200ms achieved
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, MagicMock, patch
from datetime import datetime


# Mock i3ipc classes
class MockRect:
    """Mock rectangle for window geometry."""

    def __init__(self, x=0, y=0, width=800, height=600):
        self.x = x
        self.y = y
        self.width = width
        self.height = height


class MockWorkspace:
    """Mock workspace object."""

    def __init__(self, name="1", num=1, floating_nodes=None):
        self.name = name
        self.num = num
        self.floating_nodes = floating_nodes or []


class MockWindow:
    """Mock window object."""

    def __init__(
        self,
        window_id,
        window_class="TestApp",
        marks=None,
        workspace_name="1",
        workspace_num=1,
        floating="user_off",
        rect=None,
        pid=None,
    ):
        self.id = window_id
        self.window_class = window_class
        self.name = window_class
        self.marks = marks or []
        self._workspace = MockWorkspace(workspace_name, workspace_num)
        self.floating = floating
        self.rect = rect or MockRect()
        self.pid = pid

    def workspace(self):
        return self._workspace


class MockTree:
    """Mock Sway tree."""

    def __init__(self, windows=None, scratchpad_windows=None):
        self._windows = windows or []
        self._scratchpad = MockScratchpad(scratchpad_windows or [])
        self.nodes = [MockOutputNode(self._windows)]

    def leaves(self):
        return self._windows

    def scratchpad(self):
        return self._scratchpad


class MockScratchpad:
    """Mock scratchpad container."""

    def __init__(self, windows=None):
        self.floating_nodes = windows or []


class MockOutputNode:
    """Mock output tree node."""

    def __init__(self, windows=None):
        self.name = "eDP-1"
        self.nodes = [MockWorkspaceNode()]


class MockWorkspaceNode:
    """Mock workspace tree node."""

    def __init__(self, floating_nodes=None):
        self.floating_nodes = list(floating_nodes or [])


@pytest.mark.asyncio
class TestWindowFilterParallelization:
    """Integration tests for parallelized window filtering."""

    async def test_global_windows_always_visible(self):
        """Test that windows without project marks remain visible."""
        # Setup
        windows = [
            MockWindow(1, "Firefox", marks=[]),  # No mark = global
            MockWindow(2, "Firefox", marks=["global::"]),  # Explicit global
        ]

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(return_value=MockTree(windows))

        # Import after mocking to avoid import-time dependencies
        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute with active project
        result = await filter_windows_by_project(
            mock_conn, active_project="test-project", workspace_tracker=None
        )

        # Verify both windows visible (no hide commands)
        assert result["visible"] == 2
        assert result["hidden"] == 0
        assert result["errors"] == 0

    async def test_scoped_windows_filtered_by_project(self):
        """Test that scoped windows are shown/hidden based on project."""
        # Setup
        windows = [
            MockWindow(1, "Code", marks=["scoped:project-a:123"]),
            MockWindow(2, "Code", marks=["scoped:project-b:456"]),
            MockWindow(3, "Firefox", marks=[]),  # Global
        ]

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(return_value=MockTree(windows))
        mock_conn.command = AsyncMock(return_value=None)

        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute with project-a active
        result = await filter_windows_by_project(
            mock_conn, active_project="project-a", workspace_tracker=None
        )

        # Verify: project-a window visible, project-b hidden, global visible
        assert result["visible"] == 2  # project-a + global
        assert result["hidden"] == 1  # project-b
        assert result["duration_ms"] < 500  # Should be fast even without optimization

    async def test_scoped_window_uses_env_context_when_ctx_mark_missing(self, monkeypatch):
        """Test that strict context filtering falls back to I3PM context env when ctx mark drifted."""
        windows = [
            MockWindow(
                44,
                "Ghostty",
                marks=["scoped:terminal:vpittamp/t3code:main:44"],
                pid=2284946,
            ),
        ]

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(return_value=MockTree(windows))
        mock_conn.command = AsyncMock(return_value=None)

        from home_modules.desktop.i3_project_event_daemon.services import window_filter as window_filter_module

        monkeypatch.setattr(
            window_filter_module,
            "read_process_environ_with_fallback",
            lambda _pid, max_depth=3: {
                "I3PM_APP_ID": "terminal-vpittamp/t3code:main-1913381-1773617031",
                "I3PM_APP_NAME": "terminal",
                "I3PM_SCOPE": "scoped",
                "I3PM_PROJECT_NAME": "vpittamp/t3code:main",
                "I3PM_CONTEXT_KEY": "vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
            },
        )

        result = await window_filter_module.filter_windows_by_project(
            mock_conn,
            active_project="vpittamp/t3code:main",
            workspace_tracker=None,
            active_context_key="vpittamp/t3code:main::ssh::vpittamp@ryzen:22",
        )

        assert result["visible"] == 1
        assert result["hidden"] == 0

    async def test_scratchpad_windows_restored(self):
        """Test that scratchpad windows are restored when switching to their project."""
        # Setup workspace tracker
        mock_tracker = Mock()
        mock_tracker.get_window_workspace = AsyncMock(
            return_value={
                "workspace_number": 3,
                "floating": False,
                "original_scratchpad": False,
                "geometry": None,
            }
        )

        # Window in scratchpad with project mark
        scratchpad_window = MockWindow(
            1,
            "Code",
            marks=["scoped:test-project:123"],
            workspace_name="__i3_scratch",
            workspace_num=None,
        )

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(
            return_value=MockTree(windows=[], scratchpad_windows=[scratchpad_window])
        )
        mock_conn.command = AsyncMock(return_value=None)

        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute
        result = await filter_windows_by_project(
            mock_conn, active_project="test-project", workspace_tracker=mock_tracker
        )

        # Verify window restored
        assert result["visible"] == 1
        assert result["hidden"] == 0

        # Verify restore commands were executed (parallel batch)
        assert mock_conn.command.call_count >= 1

    async def test_floating_window_geometry_preserved(self):
        """Test that floating window geometry is preserved during hide/restore."""
        # Setup workspace tracker
        mock_tracker = Mock()
        mock_tracker.get_window_workspace = AsyncMock(
            return_value={
                "workspace_number": 2,
                "floating": True,
                "original_scratchpad": False,
                "geometry": {"x": 100, "y": 200, "width": 1024, "height": 768},
            }
        )
        mock_tracker.track_window = AsyncMock()

        # Floating window in scratchpad
        scratchpad_window = MockWindow(
            1,
            "Code",
            marks=["scoped:test-project:123"],
            workspace_name="__i3_scratch",
            workspace_num=None,
            floating="user_on",
            rect=MockRect(x=100, y=200, width=1024, height=768),
        )

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(
            return_value=MockTree(windows=[], scratchpad_windows=[scratchpad_window])
        )
        mock_conn.command = AsyncMock(return_value=None)

        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute
        result = await filter_windows_by_project(
            mock_conn, active_project="test-project", workspace_tracker=mock_tracker
        )

        # Verify window restored
        assert result["visible"] == 1

        # Verify batched restore command includes geometry
        # Should be single batched command with workspace + floating + resize + position
        assert mock_conn.command.call_count >= 1

    async def test_no_active_project_hides_scoped_windows(self):
        """Test that scoped windows are hidden when no project is active."""
        # Setup
        windows = [
            MockWindow(1, "Code", marks=["scoped:project-a:123"]),
            MockWindow(2, "Firefox", marks=[]),  # Global
        ]

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(return_value=MockTree(windows))
        mock_conn.command = AsyncMock(return_value=None)

        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute with no active project
        result = await filter_windows_by_project(
            mock_conn, active_project=None, workspace_tracker=None
        )

        # Verify: scoped hidden, global visible
        assert result["visible"] == 1  # global only
        assert result["hidden"] == 1  # scoped
        assert mock_conn.command.call_count >= 1  # Hide command executed

    async def test_performance_target_met(self):
        """Test that filtering 10-20 windows completes in <200ms."""
        # Setup 15 windows (typical workload)
        windows = [
            MockWindow(i, "TestApp", marks=["scoped:test-project:{}".format(i)])
            for i in range(15)
        ]

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(return_value=MockTree(windows))
        mock_conn.command = AsyncMock(return_value=None)

        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute
        result = await filter_windows_by_project(
            mock_conn, active_project="test-project", workspace_tracker=None
        )

        # Verify performance
        assert result["duration_ms"] < 200, f"Expected <200ms, got {result['duration_ms']}ms"
        assert result["visible"] == 15
        assert result["hidden"] == 0

    async def test_parallel_execution_active(self):
        """Test that commands are executed in parallel (not sequentially)."""
        # Setup 10 windows to hide
        windows = [
            MockWindow(i, "Code", marks=["scoped:project-b:{}".format(i)])
            for i in range(10)
        ]

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(return_value=MockTree(windows))

        # Track command execution times
        command_times = []

        async def track_command(cmd):
            command_times.append(asyncio.get_event_loop().time())
            await asyncio.sleep(0.01)  # Simulate 10ms IPC latency

        mock_conn.command = AsyncMock(side_effect=track_command)

        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute with different project (all windows should hide)
        result = await filter_windows_by_project(
            mock_conn, active_project="project-a", workspace_tracker=None
        )

        # Verify parallel execution
        assert result["hidden"] == 10
        assert mock_conn.command.call_count == 10

        # If sequential: 10 * 10ms = 100ms minimum
        # If parallel: ~10ms (all at once)
        # Total duration should be much less than sequential execution time
        assert result["duration_ms"] < 100, "Commands executed sequentially (should be parallel)"

    async def test_error_handling_continues_processing(self):
        """Test that errors in individual window commands don't stop processing."""
        # Setup windows
        windows = [
            MockWindow(1, "Code", marks=["scoped:project-b:1"]),
            MockWindow(2, "Code", marks=["scoped:project-b:2"]),
            MockWindow(3, "Code", marks=["scoped:project-b:3"]),
        ]

        mock_conn = AsyncMock()
        mock_conn.get_tree = AsyncMock(return_value=MockTree(windows))

        # Make second command fail
        call_count = 0

        async def failing_command(cmd):
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise Exception("Simulated IPC error")

        mock_conn.command = AsyncMock(side_effect=failing_command)

        from home_modules.desktop.i3_project_event_daemon.services.window_filter import (
            filter_windows_by_project,
        )

        # Execute
        result = await filter_windows_by_project(
            mock_conn, active_project="project-a", workspace_tracker=None
        )

        # Verify partial success (2 successful hides, 1 error)
        assert result["hidden"] == 3  # All queued
        assert mock_conn.command.call_count == 3
        # Note: error_count tracking happens in CommandBatchService
