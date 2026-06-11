"""
Unit tests for monitoring_data.py backend script.

Tests data transformation, JSON output format, and error handling.
"""

import asyncio
import copy
import json
import pytest
import subprocess
import time
from unittest.mock import AsyncMock, MagicMock, patch
from pathlib import Path
import sys

# Add the i3_project_manager module to the path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "home-modules" / "tools"))
import i3_project_manager.cli.monitoring_data as monitoring_data

from i3_project_manager.cli.monitoring_data import (
    get_window_state_classes,
    transform_window,
    transform_workspace,
    transform_monitor,
    validate_and_count,
    query_monitoring_data,
    query_tailscale_data,
    main,
)

class TestGetWindowStateClasses:
    """Test State Model Pattern - CSS class generation in Python."""

    def test_no_states_returns_empty_string(self):
        """Window with no special states returns empty string."""
        window = {"floating": False, "hidden": False, "focused": False}
        result = get_window_state_classes(window)
        assert result == ""

    def test_single_state_floating(self):
        """Window with only floating state."""
        window = {"floating": True, "hidden": False, "focused": False}
        result = get_window_state_classes(window)
        assert result == "window-floating"

    def test_single_state_hidden(self):
        """Window with only hidden state."""
        window = {"floating": False, "hidden": True, "focused": False}
        result = get_window_state_classes(window)
        assert result == "window-hidden"

    def test_single_state_focused(self):
        """Window with only focused state."""
        window = {"floating": False, "hidden": False, "focused": True}
        result = get_window_state_classes(window)
        assert result == "window-focused"

    def test_multiple_states_floating_hidden(self):
        """Window with both floating and hidden states."""
        window = {"floating": True, "hidden": True, "focused": False}
        result = get_window_state_classes(window)
        assert result == "window-floating window-hidden"

    def test_all_states_combined(self):
        """Window with all three states active."""
        window = {"floating": True, "hidden": True, "focused": True}
        result = get_window_state_classes(window)
        assert result == "window-floating window-hidden window-focused"

    def test_missing_fields_defaults_to_false(self):
        """Window data missing state fields defaults to False."""
        window = {}  # No state fields
        result = get_window_state_classes(window)
        assert result == ""


class TestTransformWindow:
    """Test window data transformation from daemon to Eww schema."""

    def test_basic_window_transformation(self):
        """Transform basic window data with minimal fields."""
        daemon_window = {
            "id": 123,
            "class": "Ghostty",
            "title": "Terminal Window",
            "workspace": 1,
            "floating": False,
            "hidden": False,
            "focused": False,
            "marks": [],
        }
        result = transform_window(daemon_window)

        assert result["id"] == 123
        assert result["app_name"] == "Ghostty"
        assert result["title"] == "Terminal Window"
        assert result["workspace"] == 1
        assert result["floating"] is False
        assert result["hidden"] is False
        assert result["focused"] is False
        assert result["is_pwa"] is False
        assert result["scope"] == "global"
        assert result["state_classes"] == ""

    def test_app_name_fallback_to_app_id(self):
        """Use app_id when class is missing."""
        daemon_window = {
            "id": 456,
            "app_id": "firefox",
            "title": "Browser",
            "workspace": 2,
        }
        result = transform_window(daemon_window)
        assert result["app_name"] == "firefox"

    def test_app_name_defaults_to_unknown(self):
        """Default to 'unknown' when both class and app_id are missing."""
        daemon_window = {
            "id": 789,
            "title": "Mystery Window",
            "workspace": 3,
        }
        result = transform_window(daemon_window)
        assert result["app_name"] == "unknown"

    def test_scoped_window_detection(self):
        """Detect scoped windows from marks."""
        daemon_window = {
            "id": 101,
            "class": "Code",
            "title": "VSCode",
            "workspace": 2,
            "marks": ["scoped:nixos:101", "other_mark"],
        }
        result = transform_window(daemon_window)
        assert result["scope"] == "scoped"

    def test_pwa_detection_workspace_50(self):
        """Detect PWA on workspace 50 (boundary)."""
        daemon_window = {
            "id": 202,
            "class": "FFPWA",
            "title": "Gmail",
            "workspace": 50,
        }
        result = transform_window(daemon_window)
        assert result["is_pwa"] is True

    def test_pwa_detection_workspace_62(self):
        """Detect PWA on workspace 62."""
        daemon_window = {
            "id": 303,
            "class": "FFPWA",
            "title": "Claude",
            "workspace": 62,
        }
        result = transform_window(daemon_window)
        assert result["is_pwa"] is True

    def test_non_pwa_workspace_49(self):
        """Regular window on workspace 49 is not a PWA."""
        daemon_window = {
            "id": 404,
            "class": "Terminal",
            "title": "Shell",
            "workspace": 49,
        }
        result = transform_window(daemon_window)
        assert result["is_pwa"] is False

    def test_scratchpad_workspace_handling(self):
        """Handle scratchpad workspace string value."""
        daemon_window = {
            "id": 505,
            "class": "Ghostty",
            "title": "Scratchpad Terminal",
            "workspace": "scratchpad",
            "floating": True,
            "hidden": True,
        }
        result = transform_window(daemon_window)
        assert result["workspace"] == "scratchpad"
        assert result["is_pwa"] is False  # scratchpad is not >= 50

    def test_title_preserved_for_runtime_truncation(self):
        """Preserve full titles; UI handles truncation at render time."""
        long_title = "A" * 100
        daemon_window = {
            "id": 606,
            "class": "Browser",
            "title": long_title,
            "workspace": 1,
        }
        result = transform_window(daemon_window)
        assert len(result["title"]) == 100
        assert result["title"] == long_title
        assert result["full_title"] == long_title

    def test_state_classes_generation(self):
        """Generate state classes for window states."""
        daemon_window = {
            "id": 707,
            "class": "Floating",
            "title": "Dialog",
            "workspace": 1,
            "floating": True,
            "hidden": False,
            "focused": True,
        }
        result = transform_window(daemon_window)
        assert result["state_classes"] == "window-floating window-focused"


class TestTransformWorkspace:
    """Test workspace data transformation."""

    def test_basic_workspace_transformation(self):
        """Transform basic workspace data."""
        daemon_workspace = {
            "num": 1,
            "name": "1",
            "visible": True,
            "focused": True,
            "windows": [],
        }
        result = transform_workspace(daemon_workspace, "HEADLESS-1")

        assert result["number"] == 1
        assert result["name"] == "1"
        assert result["visible"] is True
        assert result["focused"] is True
        assert result["monitor"] == "HEADLESS-1"
        assert result["window_count"] == 0
        assert result["windows"] == []

    def test_workspace_with_windows(self):
        """Transform workspace with multiple windows."""
        daemon_workspace = {
            "num": 2,
            "name": "code",
            "visible": False,
            "focused": False,
            "windows": [
                {"id": 1, "class": "Code", "title": "VSCode", "workspace": 2},
                {"id": 2, "class": "Browser", "title": "Firefox", "workspace": 2},
            ],
        }
        result = transform_workspace(daemon_workspace, "HEADLESS-2")

        assert result["window_count"] == 2
        assert len(result["windows"]) == 2
        assert result["windows"][0]["app_name"] == "Code"
        assert result["windows"][1]["app_name"] == "Browser"

    def test_workspace_number_fallback(self):
        """Use 'number' field when 'num' is missing."""
        daemon_workspace = {
            "number": 3,
            "name": "3",
            "visible": True,
            "focused": False,
            "windows": [],
        }
        result = transform_workspace(daemon_workspace, "HEADLESS-1")
        assert result["number"] == 3


class TestTransformMonitor:
    """Test monitor/output data transformation."""

    def test_basic_monitor_transformation(self):
        """Transform basic monitor data."""
        daemon_output = {
            "name": "HEADLESS-1",
            "active": True,
            "workspaces": [],
        }
        result = transform_monitor(daemon_output)

        assert result["name"] == "HEADLESS-1"
        assert result["active"] is True
        assert result["focused"] is False  # No focused workspaces
        assert result["workspaces"] == []

    def test_monitor_with_focused_workspace(self):
        """Monitor with focused workspace sets focused flag."""
        daemon_output = {
            "name": "HEADLESS-2",
            "active": True,
            "workspaces": [
                {"num": 1, "name": "1", "focused": False, "visible": True, "windows": []},
                {"num": 2, "name": "2", "focused": True, "visible": True, "windows": []},
            ],
        }
        result = transform_monitor(daemon_output)
        assert result["focused"] is True

    def test_monitor_name_defaults_to_unknown(self):
        """Default to 'unknown' when name is missing."""
        daemon_output = {
            "active": True,
            "workspaces": [],
        }
        result = transform_monitor(daemon_output)
        assert result["name"] == "unknown"


class TestValidateAndCount:
    """Test summary count validation."""

    def test_empty_monitors_list(self):
        """Empty monitors list returns zero counts."""
        monitors = []
        result = validate_and_count(monitors)

        assert result["monitor_count"] == 0
        assert result["workspace_count"] == 0
        assert result["window_count"] == 0

    def test_single_monitor_with_data(self):
        """Count single monitor with workspaces and windows."""
        monitors = [
            {
                "name": "HEADLESS-1",
                "workspaces": [
                    {"window_count": 3, "windows": [{}, {}, {}]},
                    {"window_count": 2, "windows": [{}, {}]},
                ],
            }
        ]
        result = validate_and_count(monitors)

        assert result["monitor_count"] == 1
        assert result["workspace_count"] == 2
        assert result["window_count"] == 5

    def test_multiple_monitors(self):
        """Count across multiple monitors."""
        monitors = [
            {
                "name": "HEADLESS-1",
                "workspaces": [
                    {"window_count": 2, "windows": [{}, {}]},
                ],
            },
            {
                "name": "HEADLESS-2",
                "workspaces": [
                    {"window_count": 3, "windows": [{}, {}, {}]},
                    {"window_count": 1, "windows": [{}]},
                ],
            },
        ]
        result = validate_and_count(monitors)

        assert result["monitor_count"] == 2
        assert result["workspace_count"] == 3
        assert result["window_count"] == 6


class TestQueryMonitoringData:
    """Test async daemon query and error handling."""

    @pytest.mark.asyncio
    async def test_successful_query(self):
        """Successful daemon query returns current panel payload shape."""
        mock_daemon_response = {
            "active_context": {
                "qualified_name": "vpittamp/nixos-config:main",
                "project_name": "vpittamp/nixos-config:main",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
            },
            "outputs": [
                {
                    "name": "HEADLESS-1",
                    "active": True,
                    "workspaces": [
                        {
                            "num": 1,
                            "name": "1",
                            "visible": True,
                            "focused": True,
                            "windows": [
                                {
                                    "id": 1,
                                    "class": "Ghostty",
                                    "title": "Terminal",
                                    "workspace": 1,
                                    "floating": False,
                                    "hidden": False,
                                    "focused": True,
                                    "marks": [],
                                }
                            ],
                        }
                    ],
                }
            ]
        }

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient:
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = mock_daemon_response
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

            assert result["status"] == "ok"
            assert "projects" in result
            assert isinstance(result["projects"], list)
            assert result["error"] is None
            assert "timestamp" in result
            assert "active_ai_sessions" not in result
            assert "active_ai_sessions_mru" not in result
            assert "ai_monitor_metrics" not in result

    @pytest.mark.asyncio
    async def test_daemon_error_handling(self):
        """Daemon connection error returns error state."""
        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient:
            from i3_project_manager.core.daemon_client import DaemonError

            mock_instance = AsyncMock()
            mock_instance.connect.side_effect = DaemonError("Socket not found")
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

            assert result["status"] == "error"
            assert result["projects"] == []
            assert "active_ai_sessions" not in result
            assert "active_ai_sessions_mru" not in result
            assert "Socket not found" in result["error"]
            assert "timestamp" in result

    @pytest.mark.asyncio
    async def test_unexpected_error_handling(self):
        """Unexpected errors return error state with exception info."""
        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient:
            mock_instance = AsyncMock()
            mock_instance.connect.side_effect = RuntimeError("Unexpected failure")
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

            assert result["status"] == "error"
            assert "Unexpected error" in result["error"]
            assert "RuntimeError" in result["error"]

    @pytest.mark.asyncio
    async def test_json_output_format(self):
        """Verify output matches the current monitoring panel payload contract."""
        mock_daemon_response = {"outputs": []}

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient:
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = mock_daemon_response
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

            # Verify required fields exist
            assert "status" in result
            assert "projects" in result
            assert "active_project" in result
            assert "spinner_frame" in result
            assert "has_working_badge" in result
            assert "active_ai_sessions" not in result
            assert "active_ai_sessions_mru" not in result
            assert "ai_monitor_metrics" not in result
            assert "otel_sessions" not in result
            assert "timestamp" in result
            assert "error" in result

            # Verify JSON serializable
            json_str = json.dumps(result)
            assert json_str is not None

    @pytest.mark.asyncio
    async def test_query_uses_daemon_execution_metadata_without_proc_fallback(self):
        """Daemon-provided identity metadata should avoid /proc fallback reads."""
        mock_daemon_response = {
            "outputs": [
                {
                    "name": "HEADLESS-1",
                    "active": True,
                    "workspaces": [
                        {
                            "num": 1,
                            "name": "1",
                            "visible": True,
                            "focused": True,
                            "windows": [
                                {
                                    "id": 314,
                                    "pid": 2202,
                                    "class": "Ghostty",
                                    "title": "Remote Terminal",
                                    "project": "vpittamp/nixos-config:main",
                                    "workspace": 1,
                                    "floating": False,
                                    "hidden": False,
                                    "focused": True,
                                    "marks": [
                                        "scoped:terminal:vpittamp/nixos-config:main:314",
                                        "ctx:vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
                                    ],
                                    "execution_mode": "ssh",
                                    "connection_key": "vpittamp@ryzen:22",
                                    "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
                                    "remote_enabled": "true",
                                    "remote_user": "vpittamp",
                                    "remote_host": "ryzen",
                                    "remote_port": "22",
                                }
                            ],
                        }
                    ],
                }
            ]
        }

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}), \
             patch("i3_project_manager.cli.monitoring_data._read_window_remote_env", side_effect=AssertionError("fallback should not run")):
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = mock_daemon_response
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        scoped_projects = [p for p in result["projects"] if p.get("scope") == "scoped"]
        assert scoped_projects
        assert scoped_projects[0]["execution_mode"] == "ssh"

@pytest.mark.asyncio
class TestQueryTailscaleData:
    """Test Tailscale tab backend mode."""

    async def test_tailscale_successful_query(self):
        tailscale_payload = {
            "BackendState": "Running",
            "Health": [],
            "CurrentTailnet": {"Name": "example.tailnet"},
            "Self": {
                "HostName": "ryzen",
                "DNSName": "ryzen.example.ts.net.",
                "Online": True,
                "ExitNode": False,
                "TailscaleIPs": ["100.64.0.1"],
            },
            "Peer": {
                "peer-a": {"HostName": "peer-a", "DNSName": "peer-a.example.ts.net.", "Online": True, "TailscaleIPs": ["100.64.0.2"]},
                "peer-b": {"HostName": "peer-b", "DNSName": "peer-b.example.ts.net.", "Online": False, "TailscaleIPs": ["100.64.0.3"]},
            },
        }

        def which_side_effect(binary):
            if binary in {"tailscale", "kubectl", "systemctl"}:
                return f"/usr/bin/{binary}"
            return None

        def run_side_effect(cmd, capture_output=True, text=True, timeout=0, check=False):
            if cmd[:3] == ["tailscale", "status", "--json"]:
                return subprocess.CompletedProcess(cmd, 0, json.dumps(tailscale_payload), "")
            if cmd[:3] == ["systemctl", "is-active", "tailscaled"]:
                return subprocess.CompletedProcess(cmd, 0, "active\n", "")
            if cmd[:4] == ["kubectl", "config", "current-context"]:
                return subprocess.CompletedProcess(cmd, 0, "kind-test\n", "")
            if "ingress" in cmd:
                return subprocess.CompletedProcess(cmd, 0, "ns-a ingress-a\n", "")
            if "services" in cmd:
                return subprocess.CompletedProcess(cmd, 0, "ns-a svc-a\n", "")
            if "deployments" in cmd:
                return subprocess.CompletedProcess(cmd, 0, "ns-a deploy-a\n", "")
            if "daemonsets" in cmd:
                return subprocess.CompletedProcess(cmd, 0, "ns-a ds-a\n", "")
            if "pods" in cmd:
                return subprocess.CompletedProcess(cmd, 0, "ns-a pod-a\n", "")
            raise AssertionError(f"Unexpected command: {cmd}")

        with patch("i3_project_manager.cli.monitoring_data.shutil.which", side_effect=which_side_effect), \
             patch("i3_project_manager.cli.monitoring_data.subprocess.run", side_effect=run_side_effect):
            result = await query_tailscale_data()

        assert result["status"] == "ok"
        assert result["self"]["hostname"] == "ryzen"
        assert result["service"]["tailscaled_active"] is True
        assert result["peers"]["total"] == 2
        assert result["peers"]["online"] == 1
        assert result["kubernetes"]["available"] is True
        assert result["actions"]["reconnect"] is True
        assert result["actions"]["k8s_rollout_restart"] is True
        assert result["error"] is None

    async def test_tailscale_partial_when_kubectl_missing(self):
        tailscale_payload = {
            "BackendState": "Running",
            "Health": [],
            "CurrentTailnet": {"Name": "example.tailnet"},
            "Self": {"HostName": "thinkpad", "DNSName": "thinkpad.example.ts.net.", "Online": True, "ExitNode": False, "TailscaleIPs": ["100.64.0.10"]},
            "Peer": {},
        }

        def which_side_effect(binary):
            if binary in {"tailscale", "systemctl"}:
                return f"/usr/bin/{binary}"
            return None

        def run_side_effect(cmd, capture_output=True, text=True, timeout=0, check=False):
            if cmd[:3] == ["tailscale", "status", "--json"]:
                return subprocess.CompletedProcess(cmd, 0, json.dumps(tailscale_payload), "")
            if cmd[:3] == ["systemctl", "is-active", "tailscaled"]:
                return subprocess.CompletedProcess(cmd, 0, "active\n", "")
            raise AssertionError(f"Unexpected command: {cmd}")

        with patch("i3_project_manager.cli.monitoring_data.shutil.which", side_effect=which_side_effect), \
             patch("i3_project_manager.cli.monitoring_data.subprocess.run", side_effect=run_side_effect):
            result = await query_tailscale_data()

        assert result["status"] == "partial"
        assert result["kubernetes"]["available"] is False
        assert result["actions"]["k8s_rollout_restart"] is False
        assert "kubectl not found" in (result["error"] or "")

    async def test_tailscale_error_when_core_commands_missing(self):
        with patch("i3_project_manager.cli.monitoring_data.shutil.which", return_value=None):
            result = await query_tailscale_data()

        assert result["status"] == "error"
        assert "tailscale command not found" in (result["error"] or "")
        assert result["service"]["tailscaled_active"] is False
        assert result["actions"]["reconnect"] is False

    async def test_main_dispatches_tailscale_mode(self):
        mock_response = {"status": "ok"}

        with patch.object(sys, "argv", ["monitoring_data.py", "--mode", "tailscale"]), \
             patch("i3_project_manager.cli.monitoring_data.query_tailscale_data", new=AsyncMock(return_value=mock_response)) as mock_query, \
             patch("builtins.print"), \
             patch("sys.exit", side_effect=SystemExit) as mock_exit:
            with pytest.raises(SystemExit):
                await main()

        mock_query.assert_awaited_once()
        mock_exit.assert_called_with(0)


class TestLegacyAiCompatibility:
    """Legacy monitoring-data JSON no longer exports AI-session fields."""

    @pytest.mark.asyncio
    async def test_query_monitoring_data_suppresses_daemon_sessions_in_legacy_payload(self):
        mock_daemon_response = {
            "outputs": [
                {
                    "name": "HEADLESS-1",
                    "active": True,
                    "workspaces": [
                        {
                            "num": 1,
                            "name": "1",
                            "visible": True,
                            "focused": True,
                            "windows": [
                                {
                                    "id": 14,
                                    "class": "Ghostty",
                                    "title": "Ghostty",
                                    "project": "PittampalliOrg/workflow-builder:main",
                                    "connection_key": "local@ryzen",
                                    "context_key": "PittampalliOrg/workflow-builder:main::local::local@ryzen",
                                    "marks": ["scoped:terminal:PittampalliOrg/workflow-builder:main:14"],
                                    "floating": True,
                                    "hidden": True,
                                },
                                {
                                    "id": 168,
                                    "class": "Ghostty",
                                    "title": "Ghostty",
                                    "project": "vpittamp/nixos-config:main",
                                    "connection_key": "local@ryzen",
                                    "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
                                    "marks": ["scoped:terminal:vpittamp/nixos-config:main:168"],
                                    "floating": True,
                                    "hidden": True,
                                },
                            ],
                        }
                    ],
                }
            ],
            "total_windows": 2,
            "sessions": [
                {
                    "session_key": "daemon-workflow-session",
                    "render_session_key": "daemon-workflow-session",
                    "tool": "codex",
                    "display_tool": "Codex",
                    "project": "PittampalliOrg/workflow-builder:main",
                    "project_name": "PittampalliOrg/workflow-builder:main",
                    "display_project": "PittampalliOrg/workflow-builder:main",
                    "window_project": "PittampalliOrg/workflow-builder:main",
                    "focus_project": "PittampalliOrg/workflow-builder:main",
                    "window_id": 14,
                    "execution_mode": "local",
                    "connection_key": "local@ryzen",
                    "context_key": "PittampalliOrg/workflow-builder:main::local::local@ryzen",
                    "terminal_anchor_id": "anchor-workflow-builder-14",
                    "surface_key": "PittampalliOrg/workflow-builder:main::local::local@ryzen::pane-%5",
                    "tmux_session": "workflow-builder/main",
                    "tmux_window": "0:codex-raw",
                    "tmux_pane": "%5",
                    "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime()),
                    "stage": "streaming",
                    "stage_label": "Streaming",
                    "stage_class": "stage-streaming",
                    "stage_visual_state": "working",
                    "stage_detail": "",
                    "review_pending": False,
                    "session_phase": "working",
                    "session_phase_label": "Working",
                    "turn_owner": "assistant",
                    "turn_owner_label": "Assistant",
                    "activity_substate": "streaming",
                    "activity_substate_label": "Streaming",
                    "is_streaming": True,
                    "pending_tools": 0,
                    "focusable": True,
                    "host_name": "ryzen",
                    "is_current_host": True,
                    "source_is_current_host": True,
                    "focus_mode": "local_window",
                    "focus_target_host": "",
                    "availability_state": "available",
                    "focusability_reason": "",
                    "identity_source": "native",
                    "native_session_id": "native-codex-1",
                    "session_id": "codex:session-1",
                    "trace_id": "trace-1",
                    "process_running": True,
                    "last_activity_at": "",
                    "activity_age_seconds": 0,
                    "activity_age_label": "now",
                    "activity_freshness": "fresh",
                    "status_reason": "",
                    "remote_source_stale": False,
                    "remote_source_age_seconds": 0,
                    "source_connection_key": "local@ryzen",
                    "focus_execution_mode": "local",
                    "focus_connection_key": "local@ryzen",
                    "bridge_window_id": 0,
                    "bridge_state": "",
                    "shared_surface": False,
                    "surface_member_count": 1,
                }
            ],
            "current_ai_session_key": "daemon-workflow-session",
        }
        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = mock_daemon_response
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert "active_ai_sessions" not in result
        assert "active_ai_sessions_mru" not in result
        assert "current_ai_session_key" not in result
        assert "ai_monitor_metrics" not in result
        assert "otel_sessions" not in result
        assert any(
            window["id"] == 14
            for project in result["projects"]
            for window in project.get("windows", [])
        )

    @pytest.mark.asyncio
    async def test_query_monitoring_data_does_not_export_daemon_runtime_sessions_for_active_ai_panel(self):
        runtime_snapshot = {
            "active_context": {
                "qualified_name": "vpittamp/nixos-config:main",
                "project_name": "vpittamp/nixos-config:main",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
            },
            "outputs": [],
            "total_windows": 0,
            "sessions": [
                {
                    "session_key": "daemon-session-key",
                    "render_session_key": "daemon-session-key",
                    "focus_target": {
                        "method": "session.focus",
                        "params": {"session_key": "daemon-session-key"},
                    },
                    "tool": "codex",
                    "display_tool": "Codex",
                    "project": "vpittamp/nixos-config:main",
                    "project_name": "vpittamp/nixos-config:main",
                    "display_project": "vpittamp/nixos-config:main",
                    "window_project": "",
                    "focus_project": "vpittamp/nixos-config:main",
                    "window_id": 0,
                    "execution_mode": "local",
                    "connection_key": "local@ryzen",
                    "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
                    "terminal_anchor_id": "anchor-codex",
                    "surface_key": "vpittamp/nixos-config:main::local::local@ryzen::pane-%10",
                    "tmux_session": "nixos-config",
                    "tmux_window": "0:main",
                    "tmux_pane": "%10",
                    "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime()),
                    "stage": "streaming",
                    "stage_label": "Streaming",
                    "stage_class": "stage-streaming",
                    "stage_visual_state": "working",
                    "stage_detail": "",
                    "review_pending": False,
                    "session_phase": "working",
                    "session_phase_label": "Working",
                    "turn_owner": "assistant",
                    "turn_owner_label": "Assistant",
                    "activity_substate": "streaming",
                    "activity_substate_label": "Streaming",
                    "is_streaming": True,
                    "pending_tools": 0,
                    "focusable": True,
                    "host_name": "ryzen",
                    "is_current_host": True,
                    "source_is_current_host": True,
                    "focus_mode": "local_window",
                    "focus_target_host": "",
                    "availability_state": "available",
                    "focusability_reason": "",
                    "identity_source": "native",
                    "native_session_id": "native-codex-1",
                    "session_id": "codex:session-1",
                    "trace_id": "trace-1",
                    "process_running": True,
                    "last_activity_at": "",
                    "activity_age_seconds": 0,
                    "activity_age_label": "now",
                    "activity_freshness": "fresh",
                    "status_reason": "",
                    "remote_source_stale": False,
                    "remote_source_age_seconds": 0,
                    "source_connection_key": "local@ryzen",
                    "focus_execution_mode": "local",
                    "focus_connection_key": "local@ryzen",
                    "bridge_window_id": 0,
                    "bridge_state": "",
                    "shared_surface": False,
                    "surface_member_count": 1,
                }
            ],
            "current_ai_session_key": "daemon-session-key",
        }

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = runtime_snapshot
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert "active_ai_sessions" not in result
        assert "active_ai_sessions_mru" not in result
        assert "current_ai_session_key" not in result
        assert "ai_monitor_metrics" not in result
        assert "otel_sessions" not in result

    def test_active_worktree_identity_from_context_uses_runtime_snapshot_context(self):
        identity = monitoring_data._active_worktree_identity_from_context({
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@ryzen",
            "context_key": "vpittamp/nixos-config:main::host::ryzen",
        })

        assert identity["qualified_name"] == "vpittamp/nixos-config:main"
        assert identity["execution_mode"] == "local"
        assert identity["connection_key"] == "local@ryzen"
        assert identity["identity_key"] == "local:local@ryzen"
        assert identity["context_key"] == "vpittamp/nixos-config:main::host::ryzen"

    @pytest.mark.asyncio
    async def test_query_monitoring_data_requires_active_identity_match_for_project_card_activation(self):
        runtime_snapshot = {
            "status": "ok",
            "outputs": [],
            "active_project": "vpittamp/nixos-config:main",
            "active_context": {
                "qualified_name": "vpittamp/nixos-config:main",
                "execution_mode": "local",
                "connection_key": "local@thinkpad",
                "identity_key": "local:local@thinkpad",
                "context_key": "vpittamp/nixos-config:main::host::thinkpad",
            },
            "sessions": [],
        }
        project_cards = [
            {
                "name": "vpittamp/nixos-config:main",
                "variant": "local",
                "identity_key": "local:local@thinkpad",
                "windows": [],
            },
            {
                "name": "vpittamp/nixos-config:main",
                "variant": "ssh",
                "identity_key": "ssh:vpittamp@ryzen:22",
                "windows": [],
            },
            {
                "name": "Global Windows",
                "variant": "global",
                "identity_key": "global:global",
                "windows": [],
            },
        ]

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.transform_to_project_view", return_value=copy.deepcopy(project_cards)), \
             patch("i3_project_manager.cli.monitoring_data.validate_and_count", return_value={}), \
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = runtime_snapshot
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert [project["is_active"] for project in result["projects"]] == [True, False, False]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
