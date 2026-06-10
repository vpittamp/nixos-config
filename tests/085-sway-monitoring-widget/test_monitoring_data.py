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


def test_ai_session_state_files_use_i3pm_runtime_path():
    paths = [
        monitoring_data.AI_SESSION_MRU_FILE,
        monitoring_data.AI_SESSION_PIN_FILE,
        monitoring_data.AI_MONITOR_METRICS_FILE,
        monitoring_data.AI_SESSION_REVIEW_FILE,
        monitoring_data.AI_SESSION_SEEN_EVENTS_FILE,
    ]

    assert monitoring_data.AI_SESSION_STATE_DIR.parent.name == "i3pm"
    assert monitoring_data.AI_SESSION_STATE_DIR.name == "ai-sessions"
    for path in paths:
        assert path.parent == monitoring_data.AI_SESSION_STATE_DIR
        assert "eww-monitoring-panel" not in str(path)


def make_daemon_runtime_session(raw_session: dict, *, session_key: str | None = None, **overrides) -> dict:
    session = copy.deepcopy(raw_session)
    terminal_context = dict(session.get("terminal_context") or {})
    session["terminal_context"] = terminal_context
    tool = str(session.get("tool") or "unknown")
    session_id = str(session.get("session_id") or "").strip()
    surface_key = str(session.get("surface_key") or "").strip()
    if not surface_key:
        tmux_server_key = str(terminal_context.get("tmux_server_key") or "unknown-tmux-server")
        tmux_session = str(terminal_context.get("tmux_session") or "")
        tmux_window = str(terminal_context.get("tmux_window") or "")
        tmux_pane = str(terminal_context.get("tmux_pane") or "")
        context_key = str(session.get("context_key") or terminal_context.get("context_key") or "unknown-context")
        surface_key = f"{context_key}::{tmux_server_key}::{tmux_session}::{tmux_window}::{tmux_pane}"
    connection_key = str(
        overrides.get("connection_key")
        or session.get("connection_key")
        or terminal_context.get("connection_key")
        or ""
    ).strip()
    execution_mode = str(
        overrides.get("execution_mode")
        or session.get("execution_mode")
        or terminal_context.get("execution_mode")
        or "local"
    ).strip()
    context_key = str(
        overrides.get("context_key")
        or session.get("context_key")
        or terminal_context.get("context_key")
        or ""
    ).strip()
    window_id = int(
        overrides.get("window_id")
        or session.get("window_id")
        or terminal_context.get("window_id")
        or 0
    )
    project_name = str(
        overrides.get("project_name")
        or session.get("project_name")
        or session.get("project")
        or ""
    ).strip()
    resolved_session_key = session_key or f"tool={tool}|surface={surface_key}|session={session_id or 'unknown'}"
    session.update({
        "session_key": resolved_session_key,
        "render_session_key": resolved_session_key,
        "surface_key": surface_key,
        "project_name": project_name,
        "display_project": str(session.get("display_project") or project_name),
        "window_project": str(session.get("window_project") or project_name),
        "focus_project": str(session.get("focus_project") or session.get("window_project") or project_name),
        "execution_mode": execution_mode,
        "connection_key": connection_key,
        "context_key": context_key,
        "focus_execution_mode": str(overrides.get("focus_execution_mode") or execution_mode),
        "focus_connection_key": str(overrides.get("focus_connection_key") or connection_key),
        "window_id": window_id,
        "host_name": str(overrides.get("host_name") or session.get("host_name") or terminal_context.get("host_name") or ""),
        "focusable": True,
        "availability_state": str(overrides.get("availability_state") or "remote_bridge_bound"),
        "focusability_reason": str(overrides.get("focusability_reason") or "exact_remote_bridge_bound"),
        "focus_mode": str(overrides.get("focus_mode") or "remote_bridge_bound"),
        "is_current_host": bool(overrides.get("is_current_host", True)),
        "is_current_window": bool(overrides.get("is_current_window", False)),
        "window_active": bool(overrides.get("window_active", False)),
        "pane_active": bool(overrides.get("pane_active", False)),
        "focus_target": {
            "method": "session.focus",
            "params": {"session_key": resolved_session_key},
        },
        "tmux_session": str(session.get("tmux_session") or terminal_context.get("tmux_session") or ""),
        "tmux_window": str(session.get("tmux_window") or terminal_context.get("tmux_window") or ""),
        "tmux_pane": str(session.get("tmux_pane") or terminal_context.get("tmux_pane") or ""),
    })
    session.update(overrides)
    return session


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
            assert "active_ai_sessions" in result
            assert "active_ai_sessions_mru" in result
            assert "ai_monitor_metrics" in result

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
            assert result["active_ai_sessions"] == []
            assert result["active_ai_sessions_mru"] == []
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
            assert "active_ai_sessions" in result
            assert "active_ai_sessions_mru" in result
            assert "ai_monitor_metrics" in result
            assert "otel_sessions" in result
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


class TestAiReviewLifecycle:
    """Test finished-unseen session retention and acknowledgement lifecycle."""

    def test_retains_finished_session_until_seen(self, tmp_path, monkeypatch):
        review_file = tmp_path / "ai-session-review.json"
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        monkeypatch.setattr(monitoring_data, "AI_SESSION_REVIEW_FILE", review_file)
        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)

        active_sessions = [{
            "session_key": "tool=codex|project=proj|window=10|pane=%1",
            "otel_state": "completed",
            "project": "proj",
            "display_project": "proj",
            "window_id": 10,
            "execution_mode": "local",
            "tmux_session": "proj",
            "tmux_window": "1:main",
            "tmux_pane": "%1",
            "pty": "/dev/pts/1",
            "tool": "codex",
            "display_tool": "Codex CLI",
            "display_target": "pane %1",
            "state_seq": 11,
            "status_reason": "quiet_period_expired",
            # Keep fixture relative to wall clock so review TTL assertions
            # remain stable over time.
            "updated_at": monitoring_data.datetime.now().isoformat(),
            "stale": False,
            "stale_age_seconds": 0,
            "synthetic": False,
        }]
        window_lookup = {10: {"id": 10, "project": "proj"}}

        first_out, first_review = monitoring_data._apply_review_lifecycle(active_sessions, window_lookup, None)
        assert len(first_out) == 1
        assert first_out[0]["review_pending"] is True
        assert first_out[0]["review_state"] == "finished_unseen"
        marker = str(first_out[0]["finish_marker"])
        assert marker != ""
        assert str(first_review[first_out[0]["session_key"]]["finish_marker"]) == marker

        second_out, _ = monitoring_data._apply_review_lifecycle([], window_lookup, None)
        assert len(second_out) == 1
        assert second_out[0]["synthetic"] is True
        assert second_out[0]["review_pending"] is True

        seen_events_file.parent.mkdir(parents=True, exist_ok=True)
        seen_events_file.write_text(json.dumps({
            "session_key": first_out[0]["session_key"],
            "finish_marker": marker,
            "timestamp": 123456,
        }) + "\n")
        third_out, third_review = monitoring_data._apply_review_lifecycle([], window_lookup, None)
        assert third_out == []
        assert str(third_review[first_out[0]["session_key"]]["seen_marker"]) == marker

    def test_passive_focus_marks_seen_without_pane(self, tmp_path, monkeypatch):
        review_file = tmp_path / "ai-session-review.json"
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        monkeypatch.setattr(monitoring_data, "AI_SESSION_REVIEW_FILE", review_file)
        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)

        payload = {
            "schema_version": "1",
            "sessions": {
                "tool=claude-code|project=proj|window=22": {
                    "finish_marker": "marker-1",
                    "seen_marker": "",
                    "finished_at": 1735689600,
                    "expires_at": 4135689600,
                    "window_id": 22,
                    "project": "proj",
                    "tool": "claude-code",
                    "display_tool": "Claude Code",
                    "last_state": "completed",
                    "tmux_pane": "",
                    "tmux_session": "",
                    "tmux_window": "",
                    "pty": "",
                }
            },
            "updated_at": 0,
        }
        review_file.parent.mkdir(parents=True, exist_ok=True)
        review_file.write_text(json.dumps(payload))

        out, state = monitoring_data._apply_review_lifecycle([], {22: {"id": 22, "project": "proj"}}, 22)
        assert out == []
        assert state["tool=claude-code|project=proj|window=22"]["seen_marker"] == "marker-1"

    def test_disappeared_working_session_transitions_to_finished_unseen(self, tmp_path, monkeypatch):
        review_file = tmp_path / "ai-session-review.json"
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        monkeypatch.setattr(monitoring_data, "AI_SESSION_REVIEW_FILE", review_file)
        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)

        now_epoch = 2_000_000
        monkeypatch.setattr(monitoring_data.time, "time", lambda: float(now_epoch))

        session_key = "tool=codex|project=proj|window=42|pane=%7"
        payload = {
            "schema_version": "1",
            "sessions": {
                session_key: {
                    "project": "proj",
                    "display_project": "proj",
                    "window_id": 42,
                    "execution_mode": "ssh",
                    "connection_key": "vpittamp@ryzen:22",
                    "identity_key": "ssh:vpittamp@ryzen:22",
                    "context_key": "proj::ssh::vpittamp@ryzen:22",
                    "host_alias": "vpittamp@ryzen:22",
                    "tmux_session": "proj/main",
                    "tmux_window": "1:main",
                    "tmux_pane": "%7",
                    "pty": "/dev/pts/7",
                    "tool": "codex",
                    "display_tool": "Codex CLI",
                    "display_target": "pane %7",
                    "last_state": "working",
                    "updated_at": now_epoch - 120,
                    "finish_marker": "",
                    "seen_marker": "",
                    "finished_at": None,
                    "seen_at": None,
                    "expires_at": None,
                }
            },
            "updated_at": now_epoch - 120,
        }
        review_file.parent.mkdir(parents=True, exist_ok=True)
        review_file.write_text(json.dumps(payload))

        sessions, state = monitoring_data._apply_review_lifecycle([], {42: {"id": 42, "project": "proj"}}, None)

        assert len(sessions) == 1
        session = sessions[0]
        assert session["synthetic"] is True
        assert session["review_pending"] is True
        assert session["review_state"] == "finished_unseen"
        assert session["otel_state"] == "idle"
        assert session["window_id"] == 42

        entry = state[session_key]
        assert str(entry.get("finish_marker") or "") != ""
        assert int(entry.get("finished_at") or 0) == now_epoch - 120
        assert int(entry.get("expires_at") or 0) == (now_epoch - 120) + monitoring_data._AI_SESSION_REVIEW_TTL_SECONDS

    def test_live_session_suppresses_matching_synthetic_review_entry(self, tmp_path, monkeypatch):
        review_file = tmp_path / "ai-session-review.json"
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        monkeypatch.setattr(monitoring_data, "AI_SESSION_REVIEW_FILE", review_file)
        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)

        now_epoch = 2_000_000
        monkeypatch.setattr(monitoring_data.time, "time", lambda: float(now_epoch))

        live_session = {
            "session_key": "tool=codex|project=PittampalliOrg/workflow-builder:main|window=42|pane=%7",
            "otel_state": "working",
            "project": "PittampalliOrg/workflow-builder:main",
            "session_project": "PittampalliOrg/workflow-builder:main",
            "display_project": "PittampalliOrg/workflow-builder:main",
            "window_project": "vpittamp/nixos-config:main",
            "focus_project": "vpittamp/nixos-config:main",
            "window_id": 42,
            "execution_mode": "ssh",
            "connection_key": "vpittamp@ryzen:22",
            "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
            "tmux_session": "workflow-builder/main",
            "tmux_window": "1:main",
            "tmux_pane": "%7",
            "pty": "/dev/pts/7",
            "tool": "codex",
            "display_tool": "Codex CLI",
            "display_target": "pane %7",
            "updated_at": "2026-03-06T18:49:29+00:00",
            "synthetic": False,
        }
        payload = {
            "schema_version": "1",
            "sessions": {
                "tool=codex|project=vpittamp/nixos-config:main|window=42|pane=%7": {
                    "project": "vpittamp/nixos-config:main",
                    "session_project": "vpittamp/nixos-config:main",
                    "display_project": "vpittamp/nixos-config:main",
                    "window_project": "vpittamp/nixos-config:main",
                    "focus_project": "vpittamp/nixos-config:main",
                    "window_id": 42,
                    "execution_mode": "ssh",
                    "connection_key": "vpittamp@ryzen:22",
                    "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
                    "tmux_session": "workflow-builder/main",
                    "tmux_window": "1:main",
                    "tmux_pane": "%7",
                    "pty": "/dev/pts/7",
                    "tool": "codex",
                    "display_tool": "Codex CLI",
                    "display_target": "pane %7",
                    "last_state": "completed",
                    "finish_marker": "marker-1",
                    "seen_marker": "",
                    "finished_at": now_epoch - 30,
                    "expires_at": now_epoch + 300,
                    "updated_at": now_epoch - 30,
                }
            },
            "updated_at": now_epoch - 30,
        }
        review_file.parent.mkdir(parents=True, exist_ok=True)
        review_file.write_text(json.dumps(payload))

        sessions, state = monitoring_data._apply_review_lifecycle(
            [live_session],
            {42: {"id": 42, "project": "vpittamp/nixos-config:main", "class": "Ghostty"}},
            None,
        )

        assert len(sessions) == 1
        assert sessions[0]["synthetic"] is False
        assert sessions[0]["review_pending"] is False
        assert "tool=codex|project=vpittamp/nixos-config:main|window=42|pane=%7" in state

    def test_drops_pending_review_entry_when_window_matches_non_terminal_app(self, tmp_path, monkeypatch):
        review_file = tmp_path / "ai-session-review.json"
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        monkeypatch.setattr(monitoring_data, "AI_SESSION_REVIEW_FILE", review_file)
        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)

        session_key = "tool=claude-code|project=global|window=170|pane=%37"
        payload = {
            "schema_version": "1",
            "sessions": {
                session_key: {
                    "project": "global",
                    "display_project": "global",
                    "window_id": 170,
                    "execution_mode": "ssh",
                    "connection_key": "vpittamp@ryzen:22",
                    "identity_key": "ssh:vpittamp@ryzen:22",
                    "context_key": "global::ssh::vpittamp@ryzen:22",
                    "tmux_session": "workflow-builder-main",
                    "tmux_window": "1:main",
                    "tmux_pane": "%37",
                    "tool": "claude-code",
                    "display_tool": "Claude Code",
                    "display_target": "pane %37",
                    "last_state": "completed",
                    "finish_marker": "marker-1",
                    "seen_marker": "",
                    "finished_at": 1735689600,
                    "expires_at": 4135689600,
                    "updated_at": 1735689600,
                }
            },
            "updated_at": 1735689600,
        }
        review_file.parent.mkdir(parents=True, exist_ok=True)
        review_file.write_text(json.dumps(payload))

        # Simulate local non-terminal window ID collision (e.g. Firefox shares same con_id).
        window_lookup = {
            170: {
                "id": 170,
                "project": "global",
                "class": "firefox",
                "execution_mode": "local",
                "connection_key": "local@thinkpad",
                "context_key": "",
            }
        }

        out, state = monitoring_data._apply_review_lifecycle([], window_lookup, None)
        assert out == []
        assert session_key not in state

    def test_apply_current_window_marker_falls_back_to_single_session_when_tmux_has_no_match(self):
        sessions = [
            {
                "session_key": "first",
                "window_id": 171,
                "tmux_session": "nixos-main",
                "tmux_pane": "%1",
                "is_current_window": False,
            },
            {
                "session_key": "second",
                "window_id": 171,
                "tmux_session": "nixos-main",
                "tmux_pane": "%2",
                "is_current_window": False,
            },
        ]

        with patch.object(monitoring_data, "_list_tmux_active_panes_by_session", return_value={}):
            current_key = monitoring_data._apply_current_window_marker(sessions, 171)

        assert current_key == "first"
        assert sessions[0]["is_current_window"] is True
        assert sessions[1]["is_current_window"] is False

    def test_apply_current_window_marker_retains_previous_session_when_focus_leaves_ai_windows(self):
        sessions = [
            {
                "session_key": "first",
                "window_id": 171,
                "tmux_session": "nixos-main",
                "tmux_pane": "%1",
                "is_current_window": True,
            },
            {
                "session_key": "second",
                "window_id": 172,
                "tmux_session": "workflow-builder-main",
                "tmux_pane": "%2",
                "is_current_window": False,
            },
        ]

        current_key = monitoring_data._apply_current_window_marker(
            sessions,
            999,
            previous_session_key="first",
        )

        assert current_key == "first"
        assert sessions[0]["is_current_window"] is True
        assert sessions[1]["is_current_window"] is False

    def test_apply_current_window_marker_normalizes_missing_flags_to_explicit_booleans(self):
        sessions = [
            {
                "session_key": "first",
                "window_id": 171,
            },
            {
                "session_key": "second",
                "window_id": 172,
                "is_current_window": None,
            },
        ]

        current_key = monitoring_data._apply_current_window_marker(
            sessions,
            999,
            previous_session_key="first",
        )

        assert current_key == "first"
        assert sessions[0]["is_current_window"] is True
        assert sessions[1]["is_current_window"] is False

    def test_set_current_window_marker_clears_multiple_existing_true_flags(self):
        sessions = [
            {
                "session_key": "first",
                "window_id": 171,
                "is_current_window": True,
            },
            {
                "session_key": "second",
                "window_id": 171,
                "is_current_window": True,
            },
            {
                "session_key": "third",
                "window_id": 172,
                "is_current_window": True,
            },
        ]

        changed = monitoring_data._set_current_window_marker(sessions, "second")

        assert changed is True
        assert sessions[0]["is_current_window"] is False
        assert sessions[1]["is_current_window"] is True
        assert sessions[2]["is_current_window"] is False

    def test_sort_active_ai_sessions_for_display_uses_stable_identity_not_current_or_recency(self):
        sessions = [
            {
                "session_key": "later-pane",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "display_project": "PittampalliOrg/workflow-builder:main",
                "project": "PittampalliOrg/workflow-builder:main",
                "tmux_session": "i3pm-workflow",
                "tmux_window": "2:main",
                "tmux_pane": "%9",
                "pane_label": "2:main %9",
                "tool": "codex",
                "is_current_window": True,
                "updated_at": "2026-03-13T18:00:09+00:00",
            },
            {
                "session_key": "earlier-pane",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "display_project": "PittampalliOrg/workflow-builder:main",
                "project": "PittampalliOrg/workflow-builder:main",
                "tmux_session": "i3pm-workflow",
                "tmux_window": "2:main",
                "tmux_pane": "%2",
                "pane_label": "2:main %2",
                "tool": "codex",
                "is_current_window": False,
                "updated_at": "2026-03-13T18:00:01+00:00",
            },
        ]

        monitoring_data._sort_active_ai_sessions_for_display(
            sessions,
            focused_window_id=35,
            active_project_name="PittampalliOrg/workflow-builder:main",
        )

        assert [session["session_key"] for session in sessions] == [
            "earlier-pane",
            "later-pane",
        ]

    def test_payload_requires_fast_tmux_focus_tracking_only_for_ambiguous_focused_tmux_sessions(self):
        payload = {
            "focused_window_id": 171,
            "active_ai_sessions": [
                {"session_key": "a", "window_id": 171, "tmux_session": "nixos-main", "tmux_pane": "%1"},
                {"session_key": "b", "window_id": 171, "tmux_session": "nixos-main", "tmux_pane": "%2"},
                {"session_key": "c", "window_id": 172, "tmux_session": "nixos-main", "tmux_pane": "%3"},
            ],
        }

        assert monitoring_data._payload_requires_fast_tmux_focus_tracking(payload) is True
        assert monitoring_data._payload_requires_fast_tmux_focus_tracking(
            {"focused_window_id": 171, "active_ai_sessions": payload["active_ai_sessions"][:1]}
        ) is False
        assert monitoring_data._payload_requires_fast_tmux_focus_tracking(
            {"focused_window_id": 171, "active_ai_sessions": [{"session_key": "x", "window_id": 171}]}
        ) is False

    def test_refresh_current_window_marker_in_payload_updates_cached_payload_without_daemon_refresh(self, monkeypatch):
        payload = {
            "focused_window_id": 171,
            "active_project": "vpittamp/nixos-config:main",
            "current_ai_session_key": "first",
            "active_ai_sessions": [
                {
                    "session_key": "first",
                    "window_id": 171,
                    "tmux_session": "nixos-main",
                    "tmux_pane": "%1",
                    "display_project": "vpittamp/nixos-config:main",
                    "project": "vpittamp/nixos-config:main",
                    "stage_rank": 20,
                    "updated_at": "2026-02-23T10:00:01+00:00",
                    "is_current_window": True,
                },
                {
                    "session_key": "second",
                    "window_id": 171,
                    "tmux_session": "nixos-main",
                    "tmux_pane": "%2",
                    "display_project": "vpittamp/nixos-config:main",
                    "project": "vpittamp/nixos-config:main",
                    "stage_rank": 20,
                    "updated_at": "2026-02-23T10:00:02+00:00",
                    "is_current_window": False,
                },
            ],
            "active_ai_sessions_mru": [
                {
                    "session_key": "second",
                    "window_id": 171,
                    "tmux_session": "nixos-main",
                    "tmux_pane": "%2",
                    "is_current_window": False,
                },
                {
                    "session_key": "first",
                    "window_id": 171,
                    "tmux_session": "nixos-main",
                    "tmux_pane": "%1",
                    "is_current_window": True,
                },
            ],
        }
        monkeypatch.setattr(
            monitoring_data,
            "_list_tmux_active_panes_by_session",
            lambda connection_key="": {"nixos-main": "%2"},
        )

        changed = monitoring_data._refresh_current_window_marker_in_payload(payload)

        assert changed is True
        assert payload["current_ai_session_key"] == "second"
        assert payload["active_ai_sessions"][0]["session_key"] == "first"
        assert payload["active_ai_sessions"][0]["is_current_window"] is False
        assert payload["active_ai_sessions"][1]["session_key"] == "second"
        assert payload["active_ai_sessions"][1]["is_current_window"] is True
        assert payload["active_ai_sessions_mru"][0]["is_current_window"] is True
        assert payload["active_ai_sessions_mru"][1]["is_current_window"] is False

    def test_refresh_current_window_marker_in_payload_retains_previous_session_when_focus_is_non_ai(self):
        payload = {
            "focused_window_id": 999,
            "active_project": "vpittamp/nixos-config:main",
            "current_ai_session_key": "first",
            "active_ai_sessions": [
                {
                    "session_key": "first",
                    "window_id": 171,
                    "tmux_session": "nixos-main",
                    "tmux_pane": "%1",
                    "display_project": "vpittamp/nixos-config:main",
                    "project": "vpittamp/nixos-config:main",
                    "stage_rank": 20,
                    "updated_at": "2026-02-23T10:00:01+00:00",
                    "is_current_window": True,
                },
                {
                    "session_key": "second",
                    "window_id": 172,
                    "tmux_session": "workflow-builder-main",
                    "tmux_pane": "%2",
                    "display_project": "PittampalliOrg/workflow-builder:main",
                    "project": "PittampalliOrg/workflow-builder:main",
                    "stage_rank": 20,
                    "updated_at": "2026-02-23T10:00:02+00:00",
                    "is_current_window": False,
                },
            ],
            "active_ai_sessions_mru": [
                {
                    "session_key": "second",
                    "window_id": 172,
                    "tmux_session": "workflow-builder-main",
                    "tmux_pane": "%2",
                    "is_current_window": False,
                },
                {
                    "session_key": "first",
                    "window_id": 171,
                    "tmux_session": "nixos-main",
                    "tmux_pane": "%1",
                    "is_current_window": True,
                },
            ],
        }

        changed = monitoring_data._refresh_current_window_marker_in_payload(payload)

        assert changed is False
        assert payload["current_ai_session_key"] == "first"
        assert payload["active_ai_sessions"][0]["is_current_window"] is True
        assert payload["active_ai_sessions"][1]["is_current_window"] is False
        assert payload["active_ai_sessions_mru"][0]["is_current_window"] is False
        assert payload["active_ai_sessions_mru"][1]["is_current_window"] is True

    def test_apply_review_lifecycle_marks_remote_focused_tmux_review_seen(self, tmp_path, monkeypatch):
        review_file = tmp_path / "ai-session-review.json"
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        monkeypatch.setattr(monitoring_data, "AI_SESSION_REVIEW_FILE", review_file)
        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)

        now_epoch = 2_000_000
        monkeypatch.setattr(monitoring_data.time, "time", lambda: float(now_epoch))
        monkeypatch.setattr(
            monitoring_data,
            "_list_tmux_active_panes_by_session",
            lambda connection_key="": {"stacks/main": "%12"} if connection_key == "vpittamp@ryzen:22" else {},
        )

        payload = {
            "schema_version": "1",
            "sessions": {
                "remote-review": {
                    "project": "PittampalliOrg/stacks:main",
                    "display_project": "PittampalliOrg/stacks:main",
                    "window_project": "PittampalliOrg/stacks:main",
                    "focus_project": "PittampalliOrg/stacks:main",
                    "window_id": 171,
                    "execution_mode": "ssh",
                    "connection_key": "vpittamp@ryzen:22",
                    "focus_connection_key": "vpittamp@ryzen:22",
                    "tmux_session": "stacks/main",
                    "tmux_window": "2:agent",
                    "tmux_pane": "%12",
                    "tool": "codex",
                    "display_tool": "Codex CLI",
                    "display_target": "pane %12",
                    "last_state": "completed",
                    "finish_marker": "marker-remote",
                    "seen_marker": "",
                    "finished_at": now_epoch - 30,
                    "expires_at": now_epoch + 300,
                    "updated_at": now_epoch - 30,
                }
            },
            "updated_at": now_epoch - 30,
        }
        review_file.parent.mkdir(parents=True, exist_ok=True)
        review_file.write_text(json.dumps(payload))

        sessions, state = monitoring_data._apply_review_lifecycle(
            [],
            {
                171: {
                    "id": 171,
                    "project": "PittampalliOrg/stacks:main",
                    "class": "Ghostty",
                    "execution_mode": "ssh",
                    "connection_key": "vpittamp@ryzen:22",
                }
            },
            171,
        )

        assert state["remote-review"]["seen_marker"] == "marker-remote"
        assert state["remote-review"]["seen_at"] == now_epoch

    @pytest.mark.asyncio
    async def test_query_monitoring_data_preserves_explicit_window_id_when_project_matches_and_context_is_stale(self):
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
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}), \
             patch("i3_project_manager.cli.monitoring_data.load_badge_state_from_files", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = mock_daemon_response
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert result["active_ai_sessions"]
        session = result["active_ai_sessions"][0]
        assert session["window_id"] == 14
        assert session["window_project"] == "PittampalliOrg/workflow-builder:main"
        assert session["focus_project"] == "PittampalliOrg/workflow-builder:main"
        assert result["otel_sessions"]["disabled_reason"] == "daemon_herdr_sessions_present"

    @pytest.mark.asyncio
    async def test_query_monitoring_data_prefers_daemon_runtime_sessions_for_active_ai_panel(self):
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
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}), \
             patch("i3_project_manager.cli.monitoring_data.load_badge_state_from_files", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = runtime_snapshot
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert [session["session_key"] for session in result["active_ai_sessions"]] == ["daemon-session-key"]
        assert result["current_ai_session_key"] == "daemon-session-key"
        assert result["active_ai_sessions"][0]["render_session_key"] == "daemon-session-key"
        assert result["otel_sessions"]["disabled_reason"] == "daemon_herdr_sessions_present"

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
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}), \
             patch("i3_project_manager.cli.monitoring_data.load_badge_state_from_files", return_value={}), \
             patch("i3_project_manager.cli.monitoring_data.load_ai_session_pins", return_value=[]), \
             patch("i3_project_manager.cli.monitoring_data.load_ai_session_mru", return_value=[]), \
             patch("i3_project_manager.cli.monitoring_data.load_ai_monitor_metrics", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_runtime_snapshot.return_value = runtime_snapshot
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert [project["is_active"] for project in result["projects"]] == [True, False, False]

    def test_active_ai_sort_rank_places_finished_unseen_between_working_and_completed(self):
        working = {"stage_rank": 3}
        finished_unseen = {"stage_rank": 1}
        completed_seen = {"stage_rank": 0}
        assert monitoring_data._active_ai_session_sort_rank(working) > monitoring_data._active_ai_session_sort_rank(finished_unseen)
        assert monitoring_data._active_ai_session_sort_rank(finished_unseen) > monitoring_data._active_ai_session_sort_rank(completed_seen)

    def test_should_render_ai_session_hides_seen_idle_and_completed(self):
        assert monitoring_data._should_render_ai_session({"stage": "thinking", "review_pending": False}) is True
        assert monitoring_data._should_render_ai_session({"stage": "attention", "review_pending": False}) is True
        assert monitoring_data._should_render_ai_session({"stage": "output_ready", "output_unseen": True}) is True
        assert monitoring_data._should_render_ai_session({"stage": "idle", "review_pending": False}) is False
        assert monitoring_data._should_render_ai_session({"stage": "output_ready", "output_unseen": False}) is False
        assert monitoring_data._should_render_ai_session({"stage": "idle", "review_pending": False, "pinned": True}) is True

    def test_normalize_stage_fields_only_pulses_on_real_work_signals(self):
        process_keepalive = monitoring_data._normalize_stage_fields(
            {
                "otel_state": "working",
                "status_reason": "process_keepalive",
                "pending_tools": 0,
                "is_streaming": False,
                "identity_confidence": "native",
                "updated_at": "2026-03-07T20:33:51+00:00",
            },
            now_epoch=1741380000.0,
        )
        assert process_keepalive["stage"] == "thinking"
        assert process_keepalive["pulse_working"] is False

        tool_running = monitoring_data._normalize_stage_fields(
            {
                "otel_state": "working",
                "status_reason": "event:claude_code.tool_start",
                "pending_tools": 1,
                "is_streaming": False,
                "identity_confidence": "native",
                "updated_at": "2026-03-07T20:33:51+00:00",
            },
            now_epoch=1741380000.0,
        )
        assert tool_running["stage"] == "tool_running"
        assert tool_running["pulse_working"] is True

        streaming = monitoring_data._normalize_stage_fields(
            {
                "otel_state": "working",
                "status_reason": "event:codex.stream_token",
                "pending_tools": 0,
                "is_streaming": True,
                "identity_confidence": "native",
                "updated_at": "2026-03-07T20:33:51+00:00",
            },
            now_epoch=1741380000.0,
        )
        assert streaming["stage"] == "streaming"
        assert streaming["pulse_working"] is True

    def test_normalize_stage_fields_derives_semantic_stage_from_raw_session(self):
        stage = monitoring_data._normalize_stage_fields(
            {
                "otel_state": "working",
                "status_reason": "process_detected",
                "pending_tools": 0,
                "is_streaming": False,
                "identity_confidence": "pid",
                "updated_at": "2026-03-07T20:33:51+00:00",
            },
            now_epoch=1741380000.0,
        )
        assert stage["stage"] == "starting"
        assert stage["stage_label"] == "Starting"
        assert stage["stage_detail"] == "Process detected"
        assert stage["stage_visual_state"] == "working"
        assert stage["stage_glyph"] == "◔"

    @pytest.mark.parametrize(
        ("session", "expected_turn_owner", "expected_substate"),
        [
            (
                {
                    "otel_state": "working",
                    "pending_tools": 1,
                    "status_reason": "event:codex.tool_decision",
                    "updated_at": "2026-03-07T20:33:51+00:00",
                },
                "llm",
                "tool_running",
            ),
            (
                {
                    "otel_state": "working",
                    "status_reason": "event:claude_code.permission_request",
                    "updated_at": "2026-03-07T20:33:51+00:00",
                },
                "blocked",
                "waiting_input",
            ),
            (
                {
                    "otel_state": "working",
                    "status_reason": "event:codex.sse_event:response.completed",
                    "updated_at": "2026-03-07T20:33:51+00:00",
                },
                "user",
                "output_ready",
            ),
        ],
    )
    def test_normalize_stage_fields_derives_turn_owner(self, session, expected_turn_owner, expected_substate):
        stage = monitoring_data._normalize_stage_fields(session, now_epoch=1741380000.0)

        assert stage["turn_owner"] == expected_turn_owner
        assert stage["activity_substate"] == expected_substate

    @pytest.mark.parametrize(
        ("session", "expected_stage", "expected_label", "expected_detail", "expected_glyph"),
        [
            (
                {
                    "otel_state": "working",
                    "pending_tools": 2,
                    "status_reason": "event:claude_code.tool_start",
                    "updated_at": "2026-03-07T20:33:51+00:00",
                },
                "tool_running",
                "Tool",
                "Tool started",
                "⛭",
            ),
            (
                {
                    "otel_state": "working",
                    "is_streaming": True,
                    "status_reason": "event:claude_code.stream_token",
                    "updated_at": "2026-03-07T20:33:51+00:00",
                },
                "streaming",
                "Streaming",
                "Streaming response",
                "⇢",
            ),
            (
                {
                    "otel_state": "working",
                    "status_reason": "event:claude_code.permission_request",
                    "updated_at": "2026-03-07T20:33:51+00:00",
                },
                "waiting_input",
                "Waiting",
                "Waiting on permission",
                "✋",
            ),
            (
                {
                    "otel_state": "attention",
                    "user_action_reason": "rate_limit",
                    "status_reason": "rate_limit",
                    "updated_at": "2026-03-07T20:33:51+00:00",
                },
                "attention",
                "Attention",
                "Rate limit",
                "!",
            ),
        ],
    )
    def test_normalize_stage_fields_maps_semantic_stage_variants(self, session, expected_stage, expected_label, expected_detail, expected_glyph):
        stage = monitoring_data._normalize_stage_fields(session, now_epoch=1741380000.0)

        assert stage["stage"] == expected_stage
        assert stage["stage_label"] == expected_label
        assert stage["stage_detail"] == expected_detail
        assert stage["stage_glyph"] == expected_glyph

    def test_normalize_stage_fields_marks_unseen_output_as_ready(self):
        stage = monitoring_data._normalize_stage_fields(
            {
                "otel_state": "idle",
                "review_pending": True,
                "status_reason": "finished_unseen_retained",
                "updated_at": "2026-03-07T20:33:51+00:00",
            },
            now_epoch=1741380000.0,
        )
        assert stage["stage"] == "output_ready"
        assert stage["output_unseen"] is True
        assert stage["stage_detail"] == "Unread output retained"
        assert stage["stage_glyph"] == "✓"

    def test_normalize_stage_fields_marks_remote_stale_without_faking_completion(self):
        stage = monitoring_data._normalize_stage_fields(
            {
                "otel_state": "working",
                "status_reason": "process_keepalive",
                "identity_confidence": "native",
                "remote_source_stale": True,
                "remote_source_age_seconds": 240,
                "updated_at": "2026-03-07T20:33:51+00:00",
            },
            now_epoch=1741380000.0,
        )
        assert stage["stage"] == "thinking"
        assert stage["activity_freshness"] == "stale"
        assert stage["activity_age_seconds"] >= 240
        assert stage["stage_detail"] == "Still active · Source stale"

    def test_format_activity_age_prefers_compact_relative_copy(self):
        assert monitoring_data._format_activity_age(12) == "12s ago"
        assert monitoring_data._format_activity_age(120) == "2m ago"
        assert monitoring_data._format_activity_age(7200) == "2h ago"

    def test_consume_seen_events_empty_file_does_not_rewrite(self, tmp_path, monkeypatch):
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        seen_events_file.parent.mkdir(parents=True, exist_ok=True)
        seen_events_file.write_text("")
        before = seen_events_file.stat().st_mtime_ns

        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)
        events = monitoring_data.consume_ai_session_seen_events()

        assert events == []
        assert seen_events_file.exists()
        assert seen_events_file.stat().st_mtime_ns == before

    def test_consume_seen_events_with_entries_clears_file(self, tmp_path, monkeypatch):
        seen_events_file = tmp_path / "ai-session-seen-events.jsonl"
        seen_events_file.parent.mkdir(parents=True, exist_ok=True)
        seen_events_file.write_text(
            json.dumps({
                "session_key": "tool=codex|project=proj|window=10",
                "finish_marker": "m1",
                "timestamp": 123,
            }) + "\n"
        )

        monkeypatch.setattr(monitoring_data, "AI_SESSION_SEEN_EVENTS_FILE", seen_events_file)
        events = monitoring_data.consume_ai_session_seen_events()

        assert len(events) == 1
        assert events[0]["session_key"] == "tool=codex|project=proj|window=10"
        assert events[0]["finish_marker"] == "m1"
        assert not seen_events_file.exists()

    def test_review_entry_update_is_idempotent_without_state_changes(self):
        session = {
            "session_key": "tool=codex|project=proj|window=10|pane=%1",
            "otel_state": "idle",
            "project": "proj",
            "display_project": "proj",
            "window_id": 10,
            "execution_mode": "local",
            "tmux_session": "proj",
            "tmux_window": "1:main",
            "tmux_pane": "%1",
            "pty": "/dev/pts/1",
            "tool": "codex",
            "display_tool": "Codex CLI",
            "display_target": "pane %1",
            "updated_at": "2026-02-23T16:30:00+00:00",
            "state_seq": 4,
            "status_reason": "completed_timeout",
        }

        entry, changed_first = monitoring_data._update_review_entry_from_session({}, session, 1000, None)
        assert changed_first is True
        first_updated_at = entry["updated_at"]

        entry_again, changed_second = monitoring_data._update_review_entry_from_session(dict(entry), session, 1010, None)
        assert changed_second is False
        assert entry_again["updated_at"] == first_updated_at

    def test_idle_session_without_prior_activity_does_not_create_review_marker(self):
        session_idle = {
            "session_key": "tool=codex|project=proj|window=10|pane=%1",
            "otel_state": "idle",
            "project": "proj",
            "display_project": "proj",
            "window_id": 10,
            "execution_mode": "local",
            "tmux_session": "proj",
            "tmux_window": "1:main",
            "tmux_pane": "%1",
            "pty": "/dev/pts/1",
            "tool": "codex",
            "display_tool": "Codex CLI",
            "display_target": "pane %1",
            "updated_at": "2026-02-23T16:30:00+00:00",
            "state_seq": 1,
            "status_reason": "window_correlated_process_candidate",
        }

        entry, _ = monitoring_data._update_review_entry_from_session({}, session_idle, 1000, None)
        assert str(entry.get("finish_marker") or "") == ""
        assert int(entry.get("finished_at") or 0) == 0

    def test_idle_after_completed_does_not_rotate_finish_marker(self):
        base = {
            "session_key": "tool=codex|project=proj|window=10|pane=%1",
            "project": "proj",
            "display_project": "proj",
            "window_id": 10,
            "execution_mode": "local",
            "tmux_session": "proj",
            "tmux_window": "1:main",
            "tmux_pane": "%1",
            "pty": "/dev/pts/1",
            "tool": "codex",
            "display_tool": "Codex CLI",
            "display_target": "pane %1",
        }
        completed = {
            **base,
            "otel_state": "completed",
            "updated_at": "2026-02-23T16:31:00+00:00",
            "state_seq": 5,
            "status_reason": "quiet_period_expired",
        }
        idle = {
            **base,
            "otel_state": "idle",
            "updated_at": "2026-02-23T16:31:31+00:00",
            "state_seq": 6,
            "status_reason": "completed_timeout",
        }

        entry, _ = monitoring_data._update_review_entry_from_session({}, completed, 1000, None)
        marker = str(entry.get("finish_marker") or "")
        assert marker

        entry["seen_marker"] = marker
        entry["seen_at"] = 1001
        entry_after_idle, _ = monitoring_data._update_review_entry_from_session(dict(entry), idle, 1031, None)

        assert str(entry_after_idle.get("finish_marker") or "") == marker
        assert str(entry_after_idle.get("seen_marker") or "") == marker

    def test_completed_session_in_focused_window_stays_unseen_until_explicit_ack(self):
        session = {
            "session_key": "tool=codex|project=proj|window=10|pane=%1",
            "otel_state": "completed",
            "project": "proj",
            "display_project": "proj",
            "window_id": 10,
            "execution_mode": "local",
            "tmux_session": "proj",
            "tmux_window": "1:main",
            "tmux_pane": "%1",
            "pty": "/dev/pts/1",
            "tool": "codex",
            "display_tool": "Codex CLI",
            "display_target": "pane %1",
            "updated_at": "2026-02-23T16:31:00+00:00",
            "state_seq": 5,
            "status_reason": "quiet_period_expired",
            "is_current_window": True,
        }

        entry, changed = monitoring_data._update_review_entry_from_session({}, session, 1000, 10)

        assert changed is True
        assert str(entry.get("finish_marker") or "")
        assert str(entry.get("seen_marker") or "") == ""
        assert entry.get("seen_at") in (None, 0)

    def test_output_ready_idle_session_still_creates_review_marker(self):
        session = {
            "session_key": "tool=codex|project=proj|window=10|pane=%1",
            "otel_state": "idle",
            "project": "proj",
            "display_project": "proj",
            "window_id": 10,
            "execution_mode": "local",
            "tmux_session": "proj",
            "tmux_window": "1:main",
            "tmux_pane": "%1",
            "pty": "/dev/pts/1",
            "tool": "codex",
            "display_tool": "Codex CLI",
            "display_target": "pane %1",
            "updated_at": "2026-02-23T16:31:31+00:00",
            "state_seq": 6,
            "status_reason": "quiet_period_expired",
            "stage": "output_ready",
            "output_ready": True,
            "output_unseen": False,
            "review_pending": False,
        }

        entry, changed = monitoring_data._update_review_entry_from_session({}, session, 1031, None)

        assert changed is True
        assert str(entry.get("finish_marker") or "")
        assert int(entry.get("finished_at") or 0) > 0


class TestRuntimeFileWrites:
    """Test retained runtime file helpers."""

    def test_atomic_write_json_leaves_no_temp_files(self, tmp_path):
        state_file = tmp_path / "state.json"
        monitoring_data._atomic_write_json(state_file, {"value": 1})
        monitoring_data._atomic_write_json(state_file, {"value": 2})

        assert json.loads(state_file.read_text()) == {"value": 2}
        assert list(tmp_path.glob(".state.json.*.tmp")) == []


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
