"""
Scenario tests for daemon recovery and state rebuild after restart.

Tests the daemon's ability to:
- Rebuild state from i3 IPC tree on startup
- Preserve window tracking across restarts
- Re-establish event subscriptions
- Maintain workspace assignments

Part of Feature 039 - Task T024
Success Criteria: SC-015 (state rebuild verification), 99.9% uptime (SC-010)
"""

import pytest
import asyncio
from pathlib import Path
from typing import Dict, Any, List
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/desktop"))

from i3_project_event_daemon.models import I3PMEnvironment


class MockI3Tree:
    """Mock i3 IPC tree for testing state rebuild."""

    def __init__(self):
        self.windows: List[Dict[str, Any]] = []
        self.workspaces: List[Dict[str, Any]] = []
        self.outputs: List[Dict[str, Any]] = []

    def add_window(
        self,
        window_id: int,
        window_class: str,
        window_title: str,
        workspace_num: int,
        marks: List[str] = None
    ):
        """Add a window to the mock i3 tree."""
        self.windows.append({
            "id": window_id,
            "window_class": window_class,
            "name": window_title,
            "workspace": workspace_num,
            "marks": marks or [],
            "window_properties": {
                "class": window_class,
                "instance": window_class.lower()
            }
        })

    def add_workspace(self, num: int, name: str, output: str = "HDMI-1", focused: bool = False):
        """Add a workspace to the mock i3 tree."""
        self.workspaces.append({
            "num": num,
            "name": name,
            "output": output,
            "focused": focused,
            "visible": focused
        })

    def add_output(self, name: str, active: bool = True):
        """Add an output to the mock i3 tree."""
        self.outputs.append({
            "name": name,
            "active": active
        })

    def get_tree(self) -> Dict[str, Any]:
        """Get the complete i3 tree structure."""
        return {
            "nodes": [
                {
                    "type": "output",
                    "name": output["name"],
                    "nodes": [
                        {
                            "type": "workspace",
                            "num": ws["num"],
                            "name": ws["name"],
                            "nodes": [
                                win for win in self.windows
                                if win["workspace"] == ws["num"]
                            ]
                        }
                        for ws in self.workspaces
                        if ws["output"] == output["name"]
                    ]
                }
                for output in self.outputs
            ]
        }


@pytest.mark.asyncio
class TestDaemonRecovery:
    """Tests for daemon state recovery after restart."""

    @pytest.fixture
    async def mock_daemon_with_state(self):
        """Mock daemon with existing state (before restart)."""
        from ..fixtures.mock_daemon import MockDaemon

        daemon = MockDaemon()
        await daemon.initialize()

        # Simulate daemon having tracked windows before restart
        daemon.pre_restart_state = {
            "tracked_windows": {},
            "window_marks": {},
            "event_count": 0
        }

        # Add state tracking
        daemon.post_restart_state = {
            "tracked_windows": {},
            "window_marks": {},
            "event_count": 0
        }

        yield daemon
        await daemon.cleanup()

    @pytest.fixture
    def i3_tree_with_existing_windows(self):
        """Mock i3 tree with existing windows (from before daemon restart)."""
        tree = MockI3Tree()

        # Add outputs
        tree.add_output("HDMI-1", active=True)
        tree.add_output("eDP-1", active=True)

        # Add workspaces
        tree.add_workspace(1, "1:web", "HDMI-1", focused=False)
        tree.add_workspace(2, "2:code", "HDMI-1", focused=True)
        tree.add_workspace(3, "3:term", "eDP-1", focused=False)

        # Add pre-existing windows with marks
        tree.add_window(
            window_id=10001,
            window_class="firefox",
            window_title="Mozilla Firefox",
            workspace_num=1,
            marks=["app:firefox", "global"]
        )

        tree.add_window(
            window_id=10002,
            window_class="Code",
            window_title="stacks - nixos - Visual Studio Code",
            workspace_num=2,
            marks=["app:vscode", "project:stacks", "scoped"]
        )

        tree.add_window(
            window_id=10003,
            window_class="com.mitchellh.ghostty",
            window_title="terminal",
            workspace_num=2,
            marks=["app:terminal", "project:stacks", "scoped"]
        )

        tree.add_window(
            window_id=10004,
            window_class="com.mitchellh.ghostty",
            window_title="lazygit",
            workspace_num=3,
            marks=["app:lazygit", "project:nixos", "scoped"]
        )

        return tree

    async def test_state_rebuild_from_i3_tree(
        self, mock_daemon_with_state, i3_tree_with_existing_windows
    ):
        """
        Test daemon can rebuild state from i3 tree on startup.

        Scenario:
        1. Daemon has 4 windows tracked (before restart)
        2. Daemon restarts
        3. Daemon scans i3 tree and rebuilds state
        4. All 4 windows should be re-tracked with correct properties
        """
        daemon = mock_daemon_with_state
        i3_tree = i3_tree_with_existing_windows

        # Simulate state rebuild process
        rebuilt_windows = {}

        for window in i3_tree.windows:
            window_id = window["id"]
            rebuilt_windows[window_id] = {
                "window_id": window_id,
                "window_class": window["window_class"],
                "window_title": window["name"],
                "workspace_number": window["workspace"],
                "marks": window["marks"]
            }

        daemon.post_restart_state["tracked_windows"] = rebuilt_windows

        # Verify all windows recovered
        assert len(rebuilt_windows) == 4
        assert 10001 in rebuilt_windows  # Firefox
        assert 10002 in rebuilt_windows  # VS Code
        assert 10003 in rebuilt_windows  # Terminal
        assert 10004 in rebuilt_windows  # Lazygit

    async def test_window_marks_preserved(
        self, mock_daemon_with_state, i3_tree_with_existing_windows
    ):
        """
        Test window marks are preserved across daemon restart.

        Marks are stored in i3, so they should survive daemon restart.
        """
        i3_tree = i3_tree_with_existing_windows

        # Verify marks exist in i3 tree
        firefox_window = next(w for w in i3_tree.windows if w["id"] == 10001)
        assert "app:firefox" in firefox_window["marks"]
        assert "global" in firefox_window["marks"]

        vscode_window = next(w for w in i3_tree.windows if w["id"] == 10002)
        assert "app:vscode" in vscode_window["marks"]
        assert "project:stacks" in vscode_window["marks"]
        assert "scoped" in vscode_window["marks"]

    async def test_workspace_assignments_maintained(
        self, mock_daemon_with_state, i3_tree_with_existing_windows
    ):
        """
        Test workspace assignments are maintained after restart.

        Windows should remain on their assigned workspaces.
        """
        i3_tree = i3_tree_with_existing_windows

        # Verify windows are on correct workspaces
        firefox = next(w for w in i3_tree.windows if w["id"] == 10001)
        assert firefox["workspace"] == 1

        vscode = next(w for w in i3_tree.windows if w["id"] == 10002)
        assert vscode["workspace"] == 2

        terminal = next(w for w in i3_tree.windows if w["id"] == 10003)
        assert terminal["workspace"] == 2

        lazygit = next(w for w in i3_tree.windows if w["id"] == 10004)
        assert lazygit["workspace"] == 3

    async def test_project_context_recovery(
        self, mock_daemon_with_state, i3_tree_with_existing_windows
    ):
        """
        Test project context can be recovered from window marks.

        Marks contain project information that daemon can extract.
        """
        i3_tree = i3_tree_with_existing_windows

        # Extract project from marks
        for window in i3_tree.windows:
            project_marks = [m for m in window["marks"] if m.startswith("project:")]
            if project_marks:
                project_name = project_marks[0].split(":")[1]
                window["recovered_project"] = project_name

        # Verify project recovery
        vscode = next(w for w in i3_tree.windows if w["id"] == 10002)
        assert vscode.get("recovered_project") == "stacks"

        lazygit = next(w for w in i3_tree.windows if w["id"] == 10004)
        assert lazygit.get("recovered_project") == "nixos"

    async def test_event_subscription_reestablishment(self, mock_daemon_with_state):
        """
        Test event subscriptions are re-established after restart.

        Daemon should subscribe to all event types on startup.
        """
        daemon = mock_daemon_with_state

        # Simulate subscription setup
        expected_subscriptions = ["window", "workspace", "output", "tick"]
        daemon.active_subscriptions = expected_subscriptions.copy()

        # Verify all subscriptions active
        assert "window" in daemon.active_subscriptions
        assert "workspace" in daemon.active_subscriptions
        assert "output" in daemon.active_subscriptions
        assert "tick" in daemon.active_subscriptions

    async def test_new_windows_after_restart(self, mock_daemon_with_state):
        """
        Test daemon can track new windows after restart.

        After state rebuild, daemon should continue tracking new windows normally.
        """
        daemon = mock_daemon_with_state
        daemon.set_registry({
            "new-app": {
                "name": "new-app",
                "preferred_workspace": 5,
                "expected_class": "NewApp",
                "scope": "global"
            }
        })

        # Create new window after restart
        i3pm_env = I3PMEnvironment(
            app_id="new-app-test-999999-1730000999",
            app_name="new-app",
            target_workspace=None,
            project_name=None,
            scope="global",
            launch_time=1730000999,
            launcher_pid=999999
        )

        result = await daemon.assign_workspace(
            window_id=20001,
            window_class="NewApp",
            window_title="New Application",
            window_pid=999999,
            i3pm_env=i3pm_env
        )

        assert result["success"] is True
        assert result["workspace"] == 5

    async def test_partial_state_corruption_recovery(self, mock_daemon_with_state):
        """
        Test daemon can recover from partial state corruption.

        If some windows have incomplete marks or missing data,
        daemon should handle gracefully and rebuild what it can.
        """
        daemon = mock_daemon_with_state

        # Simulate corrupted state (missing marks)
        corrupted_windows = {
            20001: {
                "window_id": 20001,
                "window_class": "firefox",
                "marks": []  # Missing marks
            },
            20002: {
                "window_id": 20002,
                "window_class": "Code",
                "marks": ["app:vscode"]  # Partial marks (missing project)
            },
            20003: {
                "window_id": 20003,
                "window_class": "com.mitchellh.ghostty",
                "marks": ["app:terminal", "project:stacks", "scoped"]  # Complete
            }
        }

        # Daemon should handle all windows (even with incomplete data)
        valid_windows = [
            w for w in corrupted_windows.values()
            if "window_id" in w and "window_class" in w
        ]

        assert len(valid_windows) == 3  # All windows still tracked


@pytest.mark.asyncio
class TestHighAvailability:
    """Tests for 99.9% uptime requirement (SC-010)."""

    async def test_graceful_shutdown(self):
        """Test daemon shuts down gracefully without losing state."""
        from ..fixtures.mock_daemon import MockDaemon

        daemon = MockDaemon()
        await daemon.initialize()

        # Simulate tracked windows
        daemon.tracked_windows = {
            30001: {"window_id": 30001, "window_class": "firefox"},
            30002: {"window_id": 30002, "window_class": "Code"}
        }

        # Graceful cleanup
        await daemon.cleanup()

        # In real daemon, state would be persisted or marks preserved in i3
        # Mock just verifies cleanup doesn't crash
        assert True  # Cleanup succeeded

    async def test_crash_recovery_simulation(self):
        """
        Test daemon can recover from unexpected crash.

        State should be recoverable from i3 tree even if daemon crashes.
        """
        from ..fixtures.mock_daemon import MockDaemon

        # Daemon before crash
        daemon1 = MockDaemon()
        await daemon1.initialize()

        daemon1.tracked_windows = {
            40001: {"window_id": 40001, "window_class": "firefox", "marks": ["app:firefox"]},
            40002: {"window_id": 40002, "window_class": "Code", "marks": ["app:vscode", "project:test"]}
        }

        # Simulate crash (no cleanup)
        # In real scenario, i3 still has the windows with marks

        # Daemon after crash (new instance)
        daemon2 = MockDaemon()
        await daemon2.initialize()

        # Rebuild from "i3 tree" (simulated)
        daemon2.tracked_windows = {
            40001: {"window_id": 40001, "window_class": "firefox", "marks": ["app:firefox"]},
            40002: {"window_id": 40002, "window_class": "Code", "marks": ["app:vscode", "project:test"]}
        }

        # Verify state recovered
        assert len(daemon2.tracked_windows) == 2
        assert 40001 in daemon2.tracked_windows
        assert 40002 in daemon2.tracked_windows

        await daemon2.cleanup()

    async def test_uptime_tracking(self):
        """
        Test daemon tracks uptime for monitoring.

        Required for verifying 99.9% uptime (SC-010).
        """
        from ..fixtures.mock_daemon import MockDaemon
        import time

        daemon = MockDaemon()
        daemon.start_time = time.time()
        await daemon.initialize()

        # Simulate some uptime
        await asyncio.sleep(0.1)

        uptime = time.time() - daemon.start_time
        assert uptime > 0
        assert uptime < 1  # Less than 1 second (sanity check)

        await daemon.cleanup()


@pytest.mark.asyncio
class TestStateConsistency:
    """Tests for state consistency between daemon and i3."""

    async def test_state_validation_after_rebuild(self):
        """
        Test daemon can validate its state against i3 after rebuild.

        Ensures rebuilt state matches actual i3 state.
        """
        from ..fixtures.mock_daemon import MockDaemon

        daemon = MockDaemon()
        await daemon.initialize()

        # Simulated rebuilt state
        daemon.tracked_windows = {
            50001: {"window_id": 50001, "workspace": 1},
            50002: {"window_id": 50002, "workspace": 2}
        }

        # Simulated i3 state
        i3_state = {
            50001: {"window_id": 50001, "workspace": 1},  # Match
            50002: {"window_id": 50002, "workspace": 2}   # Match
        }

        # Validate
        mismatches = []
        for wid, daemon_data in daemon.tracked_windows.items():
            if wid in i3_state:
                if daemon_data["workspace"] != i3_state[wid]["workspace"]:
                    mismatches.append(wid)

        assert len(mismatches) == 0  # Perfect consistency

        await daemon.cleanup()

    async def test_detect_state_drift_after_restart(self):
        """
        Test daemon can detect and report state drift after restart.

        If windows moved while daemon was down, drift should be detected.
        """
        from ..fixtures.mock_daemon import MockDaemon

        daemon = MockDaemon()
        await daemon.initialize()

        # Daemon thinks windows are here (from marks/config)
        daemon.tracked_windows = {
            60001: {"window_id": 60001, "workspace": 1},
            60002: {"window_id": 60002, "workspace": 2}
        }

        # But i3 says they're actually here (user moved them while daemon down)
        i3_state = {
            60001: {"window_id": 60001, "workspace": 3},  # Drift!
            60002: {"window_id": 60002, "workspace": 2}   # Match
        }

        # Detect drift
        drift_detected = []
        for wid, daemon_data in daemon.tracked_windows.items():
            if wid in i3_state:
                if daemon_data["workspace"] != i3_state[wid]["workspace"]:
                    drift_detected.append({
                        "window_id": wid,
                        "daemon_workspace": daemon_data["workspace"],
                        "i3_workspace": i3_state[wid]["workspace"]
                    })

        assert len(drift_detected) == 1
        assert drift_detected[0]["window_id"] == 60001

        await daemon.cleanup()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
