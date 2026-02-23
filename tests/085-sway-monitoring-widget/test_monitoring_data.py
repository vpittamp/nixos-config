"""
Unit tests for monitoring_data.py backend script.

Tests data transformation, JSON output format, and error handling.
"""

import asyncio
import json
import pytest
import subprocess
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
            mock_instance.get_window_tree.return_value = mock_daemon_response
            mock_instance.get_active_project.return_value = "proj"
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
            mock_instance.get_window_tree.return_value = mock_daemon_response
            mock_instance.get_active_project.return_value = None
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
    async def test_otel_session_without_window_id_maps_to_project_window(self):
        """Best-effort project mapping should restore inline OTEL badges."""
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
                                    "id": 142,
                                    "class": "Ghostty",
                                    "title": "Terminal",
                                    "project": "vpittamp/nixos-config:main",
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
        otel_payload = {
            "schema_version": "4",
            "sessions": [
                {
                    "tool": "codex",
                    "state": "working",
                    "project": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                    "project_path": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                    "identity_confidence": "native",
                    "native_session_id": "sid-123",
                    "session_id": "codex:sid-123",
                    "window_id": None,
                    "terminal_context": {},
                    "updated_at": "2026-02-23T16:00:00+00:00",
                }
            ],
            "has_working": True,
            "timestamp": 0,
            "updated_at": "",
            "sessions_by_window": {},
        }

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.load_otel_sessions", return_value=otel_payload):
            mock_instance = AsyncMock()
            mock_instance.get_window_tree.return_value = mock_daemon_response
            mock_instance.get_active_project.return_value = "vpittamp/nixos-config:main"
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

            assert result["status"] == "ok"
            windows = [
                window
                for project in result["projects"]
                for window in project.get("windows", [])
                if window.get("id") == 142
            ]
            assert windows
            assert len(windows[0]["otel_badges"]) == 1
            assert windows[0]["otel_badges"][0]["window_id"] == 142
            assert result["active_ai_sessions"][0]["window_id"] == 142

    @pytest.mark.asyncio
    async def test_otel_session_without_window_id_respects_ssh_identity(self):
        """Missing window_id mapping should prefer ssh context over local sibling windows."""
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
                                    "id": 142,
                                    "pid": 1201,
                                    "class": "Ghostty",
                                    "title": "Local Terminal",
                                    "project": "vpittamp/nixos-config:main",
                                    "workspace": 1,
                                    "floating": False,
                                    "hidden": False,
                                    "focused": False,
                                    "marks": [
                                        "scoped:terminal:vpittamp/nixos-config:main:142",
                                        "ctx:vpittamp/nixos-config:main::local::local@thinkpad",
                                    ],
                                    "execution_mode": "local",
                                    "connection_key": "local@thinkpad",
                                    "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                                },
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
                                    "remote_dir": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                                },
                            ],
                        }
                    ],
                }
            ]
        }
        otel_payload = {
            "schema_version": "4",
            "sessions": [
                {
                    "tool": "codex",
                    "state": "working",
                    "project": "vpittamp/nixos-config:main",
                    "project_path": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                    "identity_confidence": "native",
                    "native_session_id": "sid-ssh",
                    "session_id": "codex:sid-ssh",
                    "window_id": None,
                    "terminal_context": {
                        "execution_mode": "ssh",
                        "connection_key": "vpittamp@ryzen:22",
                        "context_key": "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
                        "tmux_session": "nixos",
                        "tmux_window": "1:main",
                        "tmux_pane": "%9",
                        "host_name": "ryzen",
                    },
                    "updated_at": "2026-02-23T16:10:00+00:00",
                }
            ],
            "has_working": True,
            "timestamp": 0,
            "updated_at": "",
            "sessions_by_window": {},
        }

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.load_otel_sessions", return_value=otel_payload), \
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_window_tree.return_value = mock_daemon_response
            mock_instance.get_active_project.return_value = "vpittamp/nixos-config:main"
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert result["active_ai_sessions"]
        top_session = result["active_ai_sessions"][0]
        assert top_session["window_id"] == 314
        assert top_session["execution_mode"] == "ssh"
        assert top_session["connection_key"] == "vpittamp@ryzen:22"
        assert top_session["context_key"] == "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22"

        project_variants = {
            (project.get("name"), project.get("variant")): project
            for project in result["projects"]
            if project.get("scope") == "scoped"
        }
        assert ("vpittamp/nixos-config:main", "local") in project_variants
        assert ("vpittamp/nixos-config:main", "ssh") in project_variants

        ssh_windows = project_variants[("vpittamp/nixos-config:main", "ssh")]["windows"]
        local_windows = project_variants[("vpittamp/nixos-config:main", "local")]["windows"]
        assert any(w.get("id") == 314 for w in ssh_windows)
        assert any(w.get("id") == 142 for w in local_windows)
        ssh_badges = [w for w in ssh_windows if w.get("id") == 314][0]["otel_badges"]
        assert len(ssh_badges) == 1
        assert ssh_badges[0]["execution_mode"] == "ssh"

    @pytest.mark.asyncio
    async def test_otel_session_without_project_uses_context_identity_mapping(self):
        """Context-key identity should recover SSH sessions with non-canonical project paths."""
        mock_daemon_response = {
            "outputs": [
                {
                    "name": "HEADLESS-1",
                    "active": True,
                    "workspaces": [
                        {
                            "num": 2,
                            "name": "2",
                            "visible": True,
                            "focused": True,
                            "windows": [
                                {
                                    "id": 211,
                                    "pid": 4101,
                                    "class": "Ghostty",
                                    "title": "Local Workflow Builder",
                                    "project": "vpittamp/workflow-builder:main",
                                    "workspace": 2,
                                    "floating": False,
                                    "hidden": False,
                                    "focused": False,
                                    "marks": [
                                        "ctx:vpittamp/workflow-builder:main::local::local@thinkpad",
                                    ],
                                    "execution_mode": "local",
                                    "connection_key": "local@thinkpad",
                                    "context_key": "vpittamp/workflow-builder:main::local::local@thinkpad",
                                },
                                {
                                    "id": 778,
                                    "pid": 5102,
                                    "class": "Ghostty",
                                    "title": "Remote Workflow Builder",
                                    "project": "vpittamp/workflow-builder:main",
                                    "workspace": 2,
                                    "floating": False,
                                    "hidden": False,
                                    "focused": True,
                                    "marks": [
                                        "ctx:vpittamp/workflow-builder:main::ssh::vpittamp@ryzen:22",
                                    ],
                                    "execution_mode": "ssh",
                                    "connection_key": "vpittamp@ryzen:22",
                                    "context_key": "vpittamp/workflow-builder:main::ssh::vpittamp@ryzen:22",
                                    "remote_enabled": "true",
                                    "remote_user": "vpittamp",
                                    "remote_host": "ryzen",
                                    "remote_port": "22",
                                },
                            ],
                        }
                    ],
                }
            ]
        }
        otel_payload = {
            "schema_version": "4",
            "sessions": [
                {
                    "tool": "codex",
                    "state": "working",
                    # Remote worktree path does not match ~/repos/<account>/<repo>/<branch>.
                    "project": "/srv/worktrees/workflow-builder",
                    "project_path": "/srv/worktrees/workflow-builder",
                    "identity_confidence": "native",
                    "native_session_id": "sid-workflow-ssh",
                    "session_id": "codex:sid-workflow-ssh",
                    "window_id": None,
                    "terminal_context": {
                        "execution_mode": "ssh",
                        "connection_key": "vpittamp@ryzen:22",
                        "context_key": "vpittamp/workflow-builder:main::ssh::vpittamp@ryzen:22",
                        "tmux_session": "workflow-builder",
                        "tmux_window": "1:main",
                        "tmux_pane": "%17",
                        "host_name": "ryzen",
                    },
                    "updated_at": "2026-02-23T16:22:00+00:00",
                }
            ],
            "has_working": True,
            "timestamp": 0,
            "updated_at": "",
            "sessions_by_window": {},
        }

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.load_otel_sessions", return_value=otel_payload), \
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}):
            mock_instance = AsyncMock()
            mock_instance.get_window_tree.return_value = mock_daemon_response
            mock_instance.get_active_project.return_value = "vpittamp/workflow-builder:main"
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert result["active_ai_sessions"]
        top_session = result["active_ai_sessions"][0]
        assert top_session["window_id"] == 778
        assert top_session["execution_mode"] == "ssh"
        assert top_session["connection_key"] == "vpittamp@ryzen:22"

    @pytest.mark.asyncio
    async def test_remote_otel_merge_maps_workflow_builder_session(self, monkeypatch, tmp_path):
        """Remote host OTEL sessions should surface in local SSH project cards."""
        monkeypatch.setenv("I3PM_MONITORING_REMOTE_OTEL", "1")
        monkeypatch.setattr(
            monitoring_data,
            "REMOTE_OTEL_CACHE_DIR",
            tmp_path / "remote-otel-cache",
        )
        monkeypatch.setattr(
            monitoring_data,
            "REMOTE_OTEL_CACHE_TTL_SECONDS",
            30.0,
        )
        monkeypatch.setattr(
            monitoring_data,
            "REMOTE_OTEL_FETCH_TIMEOUT_SECONDS",
            0.2,
        )

        mock_daemon_response = {
            "outputs": [
                {
                    "name": "HEADLESS-1",
                    "active": True,
                    "workspaces": [
                        {
                            "num": 3,
                            "name": "3",
                            "visible": True,
                            "focused": True,
                            "windows": [
                                {
                                    "id": 100,
                                    "pid": 9201,
                                    "class": "Ghostty",
                                    "title": "workflow-builder",
                                    "project": "PittampalliOrg/workflow-builder:main",
                                    "workspace": 3,
                                    "floating": False,
                                    "hidden": False,
                                    "focused": True,
                                    "marks": [
                                        "scoped:terminal:PittampalliOrg/workflow-builder:main:100",
                                        "ctx:PittampalliOrg/workflow-builder:main::ssh::vpittamp@ryzen:22",
                                    ],
                                    "execution_mode": "ssh",
                                    "connection_key": "vpittamp@ryzen:22",
                                    "context_key": "PittampalliOrg/workflow-builder:main::ssh::vpittamp@ryzen:22",
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

        local_otel_payload = {
            "schema_version": "4",
            "sessions": [],
            "has_working": False,
            "timestamp": 0,
            "updated_at": "",
            "sessions_by_window": {},
        }

        remote_otel_payload = {
            "schema_version": "4",
            "sessions": [
                {
                    "tool": "codex",
                    "state": "working",
                    # Stale project name from remote env; should be corrected by project_path.
                    "project": "vpittamp/nixos-config:main",
                    "project_path": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                    "identity_confidence": "native",
                    "native_session_id": "sid-remote-workflow",
                    "session_id": "codex:sid-remote-workflow",
                    "window_id": None,
                    "terminal_context": {
                        "tmux_session": "workflow-builder/main",
                        "tmux_window": "1:bash",
                        "tmux_pane": "%37",
                        "host_name": "ryzen",
                    },
                    "updated_at": "2026-02-23T18:40:00+00:00",
                }
            ],
            "has_working": True,
            "timestamp": 0,
            "updated_at": "",
            "sessions_by_window": {},
        }

        def run_side_effect(cmd, *args, **kwargs):
            if isinstance(cmd, list) and cmd and cmd[0] == "ssh":
                return subprocess.CompletedProcess(cmd, 0, json.dumps(remote_otel_payload), "")
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with patch("i3_project_manager.cli.monitoring_data.DaemonClient") as MockClient, \
             patch("i3_project_manager.cli.monitoring_data.load_otel_sessions", return_value=local_otel_payload), \
             patch("i3_project_manager.cli.monitoring_data.load_worktree_remote_profiles", return_value={}), \
             patch("i3_project_manager.cli.monitoring_data.subprocess.run", side_effect=run_side_effect):
            mock_instance = AsyncMock()
            mock_instance.get_window_tree.return_value = mock_daemon_response
            mock_instance.get_active_project.return_value = "PittampalliOrg/workflow-builder:main"
            MockClient.return_value = mock_instance

            result = await query_monitoring_data()

        assert result["status"] == "ok"
        assert result["active_ai_sessions"]
        top_session = result["active_ai_sessions"][0]
        assert top_session["window_id"] == 100
        assert top_session["execution_mode"] == "ssh"
        assert top_session["connection_key"] == "vpittamp@ryzen:22"
        assert top_session["project"] == "PittampalliOrg/workflow-builder:main"

        workflow_project = next(
            project
            for project in result["projects"]
            if str(project.get("name") or "").endswith("/workflow-builder:main")
            and project.get("variant") == "ssh"
        )
        assert workflow_project["windows"][0]["id"] == 100
        assert len(workflow_project["windows"][0]["otel_badges"]) == 1

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
            mock_instance.get_window_tree.return_value = mock_daemon_response
            mock_instance.get_active_project.return_value = "vpittamp/nixos-config:main"
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
            "updated_at": "2026-02-23T10:00:00+00:00",
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

    def test_merge_review_state_into_window_badges_adds_synthetic_badge(self):
        windows = [{
            "id": 42,
            "project": "proj",
            "otel_badges": [],
        }]
        sessions = [{
            "session_key": "tool=codex|project=proj|window=42|pane=%7",
            "tool": "codex",
            "otel_state": "completed",
            "project": "proj",
            "window_id": 42,
            "execution_mode": "local",
            "tmux_session": "proj",
            "tmux_window": "1:main",
            "tmux_pane": "%7",
            "pty": "",
            "stale": False,
            "stale_age_seconds": 0,
            "review_pending": True,
            "review_state": "finished_unseen",
            "finished_at": 1735689600,
            "synthetic": True,
        }]

        monitoring_data._merge_review_state_into_window_badges(windows, sessions)
        assert len(windows[0]["otel_badges"]) == 1
        badge = windows[0]["otel_badges"][0]
        assert badge["review_pending"] is True
        assert badge["synthetic"] is True
        assert badge["session_key"] == sessions[0]["session_key"]

    def test_active_ai_sort_rank_places_finished_unseen_between_working_and_completed(self):
        working = {"otel_state": "working", "review_pending": False}
        finished_unseen = {"otel_state": "idle", "review_pending": True}
        completed_seen = {"otel_state": "completed", "review_pending": False}
        assert monitoring_data._active_ai_session_sort_rank(working) > monitoring_data._active_ai_session_sort_rank(finished_unseen)
        assert monitoring_data._active_ai_session_sort_rank(finished_unseen) > monitoring_data._active_ai_session_sort_rank(completed_seen)

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

        entry, changed_first = monitoring_data._update_review_entry_from_session({}, session, 1000)
        assert changed_first is True
        first_updated_at = entry["updated_at"]

        entry_again, changed_second = monitoring_data._update_review_entry_from_session(dict(entry), session, 1010)
        assert changed_second is False
        assert entry_again["updated_at"] == first_updated_at


class TestAiNotificationState:
    """Test AI notification cache robustness."""

    def test_emit_notifications_recovers_from_corrupt_cache(self, tmp_path, monkeypatch):
        notify_file = tmp_path / "ai-session-notify-state.json"
        notify_file.parent.mkdir(parents=True, exist_ok=True)
        notify_file.write_text('{"sessions": {"bad": {"state":"working"}}}38944}')

        monkeypatch.setattr(monitoring_data, "AI_SESSION_NOTIFY_FILE", notify_file)

        with patch("i3_project_manager.cli.monitoring_data.subprocess.run") as mock_run:
            monitoring_data.emit_ai_state_transition_notifications([
                {
                    "session_key": "tool=codex|project=proj|window=1|pane=%1",
                    "otel_state": "idle",
                    "display_tool": "Codex CLI",
                    "display_project": "proj",
                    "display_target": "pane %1",
                    "tool": "codex",
                    "project": "proj",
                }
            ])
            mock_run.assert_not_called()

        payload = json.loads(notify_file.read_text())
        assert isinstance(payload, dict)
        assert "sessions" in payload
        assert payload["sessions"]["tool=codex|project=proj|window=1|pane=%1"]["state"] == "idle"

    def test_atomic_write_json_leaves_no_temp_files(self, tmp_path):
        state_file = tmp_path / "state.json"
        monitoring_data._atomic_write_json(state_file, {"value": 1})
        monitoring_data._atomic_write_json(state_file, {"value": 2})

        assert json.loads(state_file.read_text()) == {"value": 2}
        assert list(tmp_path.glob(".state.json.*.tmp")) == []


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
