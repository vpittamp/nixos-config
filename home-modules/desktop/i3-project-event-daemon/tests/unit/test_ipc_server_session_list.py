"""Unit tests for daemon-owned AI session list field propagation."""

from __future__ import annotations

import copy
import importlib
import importlib.util
import json
import sys
import time
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


PACKAGE_ROOT = Path(__file__).parent.parent.parent
I3PM_TOOL_ROOT = PACKAGE_ROOT.parent.parent / "tools"

if str(I3PM_TOOL_ROOT) not in sys.path:
    sys.path.insert(0, str(I3PM_TOOL_ROOT))


if "i3_project_daemon" not in sys.modules:
    package_spec = importlib.util.spec_from_file_location(
        "i3_project_daemon",
        PACKAGE_ROOT / "__init__.py",
        submodule_search_locations=[str(PACKAGE_ROOT)],
    )
    package_module = importlib.util.module_from_spec(package_spec)
    sys.modules["i3_project_daemon"] = package_module
    assert package_spec.loader is not None
    package_spec.loader.exec_module(package_module)


ipc_server_module = importlib.import_module("i3_project_daemon.ipc_server")
models_module = importlib.import_module("i3_project_daemon.models")

IPCServer = ipc_server_module.IPCServer
WindowInfo = models_module.WindowInfo


class DummyLaunchRegistry:
    def get_stats(self):
        return SimpleNamespace(total_pending=0)


class DummyStateManager:
    def __init__(self):
        self.state = SimpleNamespace(
            active_project="global",
            window_map={},
            launch_registry=DummyLaunchRegistry(),
            scoped_classes=set(),
        )
        self.launch_registry = self.state.launch_registry
        self.removed_windows = []

    async def get_active_project(self):
        return self.state.active_project

    async def remove_window(self, _window_id: int):
        self.removed_windows.append(_window_id)
        return None


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


def make_runtime_snapshot():
    return {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "tracked_windows": [
            {
                "id": 101,
                "window_id": 101,
                "project": "vpittamp/nixos-config:main",
                "execution_mode": "local",
                "connection_key": "local@thinkpad",
                "context_key": "vpittamp/nixos-config:main::host::thinkpad",
                "terminal_anchor_id": "terminal-anchor",
                "focused": True,
                "hidden": False,
            }
        ],
        "sessions": [],
        "current_session_key": "",
        "focused_window_id": 101,
    }


def test_project_outputs_merge_configured_workspace_slots_by_output(server, tmp_path, monkeypatch):
    config_path = tmp_path / "workspace-assignments.json"
    config_path.write_text(json.dumps({
        "version": "1.0",
        "output_preferences": {
            "primary": ["DP-1"],
            "secondary": ["HDMI-A-1"],
            "tertiary": ["DP-2"],
        },
        "assignments": [
            {
                "workspace_number": 1,
                "app_name": "terminal",
                "monitor_role": "primary",
                "primary_output": "DP-1",
                "fallback_outputs": ["HDMI-A-1", "DP-2"],
                "source": "nix",
            },
            {
                "workspace_number": 33,
                "app_name": "herdr",
                "monitor_role": "primary",
                "primary_output": "DP-1",
                "fallback_outputs": ["HDMI-A-1", "DP-2"],
                "source": "nix",
            },
            {
                "workspace_number": 131,
                "app_name": "workflow-builder-dev-pwa",
                "monitor_role": "secondary",
                "primary_output": "HDMI-A-1",
                "fallback_outputs": ["DP-1", "DP-2"],
                "source": "nix",
            },
            {
                "workspace_number": 158,
                "app_name": "mediaite-pwa",
                "monitor_role": "tertiary",
                "primary_output": "DP-2",
                "fallback_outputs": ["DP-1", "HDMI-A-1"],
                "source": "nix",
            },
            {
                "workspace_number": 158,
                "app_name": "duplicate-slot",
                "monitor_role": "tertiary",
                "primary_output": "DP-2",
                "fallback_outputs": ["DP-1", "HDMI-A-1"],
                "source": "nix",
            },
        ],
    }))
    monkeypatch.setattr(ipc_server_module, "WORKSPACE_ASSIGNMENTS_PATH", config_path)

    outputs = [
        {
            "name": "DP-1",
            "active": True,
            "primary": True,
            "geometry": {},
            "current_workspace": "33",
            "workspaces": [
                {
                    "number": 33,
                    "name": "33",
                    "focused": False,
                    "visible": True,
                    "output": "DP-1",
                    "windows": [{"id": 3301}],
                }
            ],
        },
        {
            "name": "HDMI-A-1",
            "active": True,
            "primary": False,
            "geometry": {},
            "current_workspace": "131",
            "workspaces": [],
        },
        {
            "name": "DP-2",
            "active": True,
            "primary": False,
            "geometry": {},
            "current_workspace": "158",
            "workspaces": [],
        },
    ]

    result = server._project_outputs_from_tracked_windows(outputs, [])
    workspaces_by_output = {
        output["name"]: output["workspaces"]
        for output in result
    }

    assert [workspace["name"] for workspace in workspaces_by_output["DP-1"]] == ["1", "33"]
    live_workspace = workspaces_by_output["DP-1"][1]
    assert live_workspace["visible"] is True
    assert live_workspace["configured"] is True
    assert live_workspace["app_name"] == "herdr"

    assert [workspace["name"] for workspace in workspaces_by_output["HDMI-A-1"]] == ["131"]
    assert workspaces_by_output["HDMI-A-1"][0]["configured"] is True
    assert workspaces_by_output["HDMI-A-1"][0]["monitor_role"] == "secondary"

    assert [workspace["name"] for workspace in workspaces_by_output["DP-2"]] == ["158"]
    assert workspaces_by_output["DP-2"][0]["app_names"] == ["mediaite-pwa", "duplicate-slot"]


@pytest.mark.asyncio
async def test_monitors_config_accepts_generated_workspace_number_key(server, tmp_path, monkeypatch):
    config_path = tmp_path / "workspace-assignments.json"
    config_path.write_text(json.dumps({
        "version": "1.0",
        "output_preferences": {"primary": ["DP-1"]},
        "assignments": [
            {
                "workspace_number": 33,
                "app_name": "herdr",
                "monitor_role": "primary",
                "source": "nix",
            }
        ],
    }))
    monkeypatch.setattr(ipc_server_module, "WORKSPACE_ASSIGNMENTS_PATH", config_path)

    result = await server._monitors_config({})

    assert result["workspace_assignments"] == [
        {
            "preferred_workspace": 33,
            "app_name": "herdr",
            "preferred_monitor_role": "primary",
            "source": "nix",
        }
    ]


def make_runtime_session(overrides: dict | None = None) -> dict:
    session = {
        "session_key": "session-1",
        "render_session_key": "session-1",
        "surface_key": "surface-local-1",
        "tool": "codex",
        "project_name": "vpittamp/nixos-config:main",
        "project": "vpittamp/nixos-config:main",
        "display_project": "vpittamp/nixos-config:main",
        "window_project": "vpittamp/nixos-config:main",
        "focus_project": "vpittamp/nixos-config:main",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "context_key": "vpittamp/nixos-config:main::host::thinkpad",
        "focus_execution_mode": "local",
        "focus_connection_key": "local@thinkpad",
        "host_name": "thinkpad",
        "window_id": 101,
        "terminal_anchor_id": "terminal-anchor",
        "pane_label": "main",
        "session_phase": "working",
        "session_phase_label": "Working",
        "turn_owner": "llm",
        "turn_owner_label": "LLM",
        "activity_substate": "thinking",
        "activity_substate_label": "Thinking",
        "status_reason": "event:codex.websocket_event",
        "availability_state": "local_window",
        "focusability_reason": "",
        "focus_mode": "herdr_pane",
        "is_current_host": True,
        "is_current_window": True,
        "window_active": True,
        "pane_active": True,
        "focusable": True,
        "identity_phase": "canonical",
        "native_session_id": "native-1",
        "session_id": "session-1",
        "process_running": True,
        "activity_age_seconds": 1,
        "activity_freshness": "fresh",
        "focus_target": {},
        "terminal_context": {
            "window_id": 101,
            "terminal_anchor_id": "terminal-anchor",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::host::thinkpad",
            "host_name": "thinkpad",
            "pane_title": "main",
            "pane_active": True,
            "window_active": True,
            "tmux_session": "i3pm-vpittamp-nixos-config-main",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
        "tmux_session": "i3pm-vpittamp-nixos-config-main",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
    }
    if not overrides:
        return session
    merged = copy.deepcopy(session)
    overrides = copy.deepcopy(overrides)
    terminal_context_overrides = overrides.pop("terminal_context", None)
    merged.update(overrides)
    if isinstance(terminal_context_overrides, dict):
        merged_terminal_context = dict(merged.get("terminal_context") or {})
        merged_terminal_context.update(terminal_context_overrides)
        merged["terminal_context"] = merged_terminal_context
    return merged


@pytest.mark.asyncio
async def test_runtime_snapshot_keeps_transient_unbound_window_visible(server, monkeypatch):
    tracked_window = WindowInfo(
        window_id=101,
        con_id=101,
        window_class="com.mitchellh.ghostty",
        window_title="Ghostty",
        window_instance="ghostty",
        app_identifier="terminal",
        project="vpittamp/nixos-config:main",
        marks=["scoped:terminal:vpittamp/nixos-config:main:101"],
        scope="scoped",
        workspace="1",
        output="eDP-1",
        binding_state="transient_unbound",
        last_workspace="1",
        last_output="eDP-1",
    )

    async def fake_context_get_active(_params):
        return {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::host::thinkpad",
        }

    async def fake_window_map_snapshot():
        return {101: tracked_window}

    server._get_window_tree = AsyncMock(return_value={
        "outputs": [
            {
                "name": "eDP-1",
                "active": True,
                "primary": True,
                "geometry": {},
                "current_workspace": "1",
                "workspaces": [
                    {
                        "number": 1,
                        "name": "1",
                        "focused": True,
                        "visible": True,
                        "output": "eDP-1",
                        "windows": [],
                    }
                ],
            }
        ],
        "total_windows": 0,
        "cached": False,
    })
    monkeypatch.setattr(server, "_context_get_active", fake_context_get_active)
    monkeypatch.setattr(server.state_manager, "get_window_map_snapshot", fake_window_map_snapshot, raising=False)
    monkeypatch.setattr(server.launch_service, "get_reusable_context_terminal_window", AsyncMock(return_value=None))
    monkeypatch.setattr(server.launch_service, "launch_stats", lambda: {})

    snapshot = await server._runtime_snapshot({})

    assert snapshot["active_project"] == "vpittamp/nixos-config:main"
    assert snapshot["total_windows"] == 1
    assert snapshot["tracked_windows"][0]["binding_state"] == "transient_unbound"
    assert snapshot["tracked_windows"][0]["visible"] is True
    assert snapshot["tracked_windows"][0]["hidden"] is False
    assert snapshot["tracked_windows"][0]["workspace"] == "1"
    assert snapshot["outputs"][0]["workspaces"][0]["windows"][0]["id"] == 101
    assert snapshot["outputs"][0]["workspaces"][0]["windows"][0]["binding_state"] == "transient_unbound"


@pytest.mark.asyncio
async def test_runtime_snapshot_prunes_stale_bound_window_missing_from_tree(server, monkeypatch):
    tracked_window = WindowInfo(
        window_id=202,
        con_id=202,
        window_class="google-chrome",
        window_title="Closed app",
        window_instance="chrome",
        app_identifier="browser",
        project="global",
        marks=["global:browser:global:202"],
        scope="global",
        workspace="4",
        output="eDP-1",
        binding_state="bound_workspace",
        last_workspace="4",
        last_output="eDP-1",
    )

    async def fake_context_get_active(_params):
        return {
            "qualified_name": "global",
            "project_name": "global",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "global::host::thinkpad",
        }

    async def fake_window_map_snapshot():
        return {202: tracked_window}

    server._get_window_tree = AsyncMock(return_value={
        "outputs": [
            {
                "name": "eDP-1",
                "active": True,
                "primary": True,
                "geometry": {},
                "current_workspace": "4",
                "workspaces": [
                    {
                        "number": 4,
                        "name": "4",
                        "focused": True,
                        "visible": True,
                        "output": "eDP-1",
                        "windows": [],
                    }
                ],
            }
        ],
        "total_windows": 0,
        "cached": False,
    })
    monkeypatch.setattr(server, "_context_get_active", fake_context_get_active)
    monkeypatch.setattr(server.state_manager, "get_window_map_snapshot", fake_window_map_snapshot, raising=False)
    monkeypatch.setattr(server.launch_service, "get_reusable_context_terminal_window", AsyncMock(return_value=None))
    monkeypatch.setattr(server.launch_service, "launch_stats", lambda: {})

    snapshot = await server._runtime_snapshot({})

    assert snapshot["total_windows"] == 0
    assert snapshot["tracked_windows"] == []
    assert snapshot["outputs"][0]["workspaces"][0]["windows"] == []
    assert server.state_manager.removed_windows == [202]


def test_extract_windows_prefers_mark_app_identity_over_dynamic_chrome_class(server):
    tracked_window = WindowInfo(
        window_id=1405,
        con_id=1405,
        window_class="chrome-github.com__-Default",
        window_title="GitHub",
        window_instance="",
        app_identifier="chrome-github.com__-Default",
        project="global",
        marks=["global:github-pwa:global:1405"],
        scope="global",
        workspace="54",
        output="HDMI-A-1",
        binding_state="bound_workspace",
    )
    rect = SimpleNamespace(x=0, y=0, width=100, height=100)
    node = SimpleNamespace(
        id=1405,
        window=None,
        app_id="chrome-github.com__-Default",
        window_class="",
        window_instance="",
        name="GitHub",
        marks=["global:github-pwa:global:1405"],
        pid=0,
        floating="auto_off",
        focused=False,
        fullscreen_mode=0,
        rect=rect,
        nodes=[],
        floating_nodes=[],
    )
    workspace = SimpleNamespace(
        window=None,
        app_id="",
        type="workspace",
        name="54",
        nodes=[node],
        floating_nodes=[],
    )

    windows = server._extract_windows_from_container(
        workspace,
        54,
        "HDMI-A-1",
        tracked_windows={1405: tracked_window},
        tracked_windows_by_con_id={1405: tracked_window},
    )

    assert len(windows) == 1
    assert windows[0]["app_key"] == "github-pwa"
    assert windows[0]["app_name"] == "github-pwa"
    assert windows[0]["project"] == "global"


def make_local_payload():
    return {
        "schema_version": "11",
        "sessions": [
            {
                "tool": "codex",
                "project_name": "vpittamp/nixos-config:main",
                "project": "vpittamp/nixos-config:main",
                "display_project": "vpittamp/nixos-config:main",
                "surface_kind": "terminal-window",
                "pane_label": "main",
                "updated_at": "2026-03-14T15:00:00Z",
                "stage": "thinking",
                "stage_rank": 50,
                "stage_label": "Thinking",
                "stage_class": "working",
                "stage_visual_state": "working",
                "needs_user_action": False,
                "output_ready": False,
                "output_unseen": False,
                "llm_stopped": False,
                "terminal_state": "",
                "terminal_state_at": "",
                "terminal_state_label": "",
                "terminal_state_source": "",
                "review_pending": False,
                "session_phase": "working",
                "session_phase_label": "Working",
                "turn_owner": "llm",
                "turn_owner_label": "LLM",
                "activity_substate": "thinking",
                "activity_substate_label": "Thinking",
                "is_streaming": False,
                "pending_tools": 0,
                "identity_source": "pane",
                "identity_phase": "canonical",
                "native_session_id": "native-1",
                "session_id": "session-1",
                "context_fingerprint": "abc123def456",
                "trace_id": "trace-1",
                "pid": 12345,
                "process_running": True,
                "pulse_working": True,
                "last_activity_at": "2026-03-14T15:00:00Z",
                "activity_age_seconds": 1,
                "activity_age_label": "now",
                "activity_freshness": "fresh",
                "status_reason": "event:codex.websocket_event",
                "terminal_context": {
                    "window_id": 101,
                    "terminal_anchor_id": "terminal-anchor",
                    "execution_mode": "local",
                    "connection_key": "local@thinkpad",
                    "context_key": "vpittamp/nixos-config:main::host::thinkpad",
                    "host_name": "thinkpad",
                    "pane_title": "main",
                    "pane_active": True,
                    "window_active": True,
                    "tmux_session": "i3pm-vpittamp-nixos-config-main",
                    "tmux_window": "0:main",
                    "tmux_pane": "%0",
                },
            }
        ]
    }


def _herdr_local_and_remote_both_active():
    """Both herdr instances mark their own active pane focused — the ambiguous
    case the deterministic selector must resolve purely from sway focus."""
    return [
        {
            "session_key": "herdr:thinkpad:pane:w0-1",
            "source": "herdr",
            "focused": True,
            "pane_active": True,
            "is_current_host": True,
            "host_name": "thinkpad",
        },
        {
            "session_key": "herdr:ryzen:pane:w1-1",
            "source": "herdr",
            "focused": True,
            "pane_active": True,
            "is_current_host": False,
            "host_name": "ryzen",
        },
    ]


def test_current_session_follows_focused_local_herdr_instance(server):
    """The reported bug: sway focus is on the LOCAL herdr window, but the remote
    instance also reports its pane focused. Deterministically the local instance
    wins — selection is a pure function of which herdr window holds sway focus."""
    result = server.focus_service.select_current_session_key(
        _herdr_local_and_remote_both_active(),
        focused_herdr_host="__local__",
    )
    assert result == "herdr:thinkpad:pane:w0-1"


def test_current_session_follows_focused_remote_herdr_instance(server):
    """Sway focus on the remote herdr-<host> window selects that host's pane."""
    result = server.focus_service.select_current_session_key(
        _herdr_local_and_remote_both_active(),
        focused_herdr_host="ryzen",
    )
    assert result == "herdr:ryzen:pane:w1-1"


def test_current_session_empty_when_focus_not_on_herdr_window(server):
    """No fallback: focus on a non-herdr window (or nothing) => nothing focused."""
    result = server.focus_service.select_current_session_key(
        _herdr_local_and_remote_both_active(),
        focused_herdr_host=None,
    )
    assert result == ""


def test_current_session_empty_when_focused_instance_has_no_active_pane(server):
    """No fallback/guess: if the focused instance reports no active pane, the
    current session is empty rather than an arbitrarily chosen row."""
    sessions = [
        {
            "session_key": "herdr:thinkpad:pane:w0-1",
            "source": "herdr",
            "focused": False,
            "pane_active": False,
            "is_current_host": True,
            "host_name": "thinkpad",
        },
    ]
    result = server.focus_service.select_current_session_key(
        sessions,
        focused_herdr_host="__local__",
    )
    assert result == ""


@pytest.mark.asyncio
async def test_session_list_strips_retired_ui_state_fields(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    session = make_runtime_session()
    runtime_snapshot["sessions"] = [session]
    runtime_snapshot["current_session_key"] = session["session_key"]

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    for retired_field in (
        "session_phase",
        "session_phase_label",
        "turn_owner",
        "turn_owner_label",
        "activity_substate",
        "activity_substate_label",
        "status_reason",
        "terminal_anchor_id",
        "terminal_context",
        "tmux_session",
        "tmux_window",
        "tmux_pane",
        "native_session_id",
        "session_id",
        "process_running",
        "activity_age_seconds",
        "activity_freshness",
    ):
        assert retired_field not in session
    assert session["is_current_window"] is True
    assert session["focus_target"] == {}
    assert result["current_session_key"] == session["session_key"]
    assert session["availability_state"] == "local_window"
    assert session["focusability_reason"] == ""


@pytest.mark.asyncio
async def test_remote_herdr_session_uses_focus_only_attach_mode(server, monkeypatch):
    runtime_snapshot = make_runtime_snapshot()
    runtime_snapshot["active_context"].update({
        "execution_mode": "local",
        "connection_key": "local@ryzen",
    })
    runtime_snapshot["tracked_windows"][0].update({
        "execution_mode": "local",
        "connection_key": "local@ryzen",
        "context_key": "vpittamp/nixos-config:main::host::ryzen",
    })
    session = make_runtime_session({
        "session_key": "herdr:thinkpad:pane:w0-1",
        "render_session_key": "herdr:thinkpad:pane:w0-1",
        "source": "herdr",
        "pane_id": "w0-1",
        "surface_key": "herdr:thinkpad:pane:w0-1",
        "is_remote_herdr": True,
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "context_key": "vpittamp/nixos-config:main::host::thinkpad",
        "focus_execution_mode": "ssh",
        "focus_connection_key": "vpittamp@thinkpad:22",
        "host_name": "thinkpad",
        "window_id": 0,
        "availability_state": "remote_herdr_attachable",
        "focusability_reason": "",
        "focus_mode": "remote_herdr_attach",
        "is_current_host": False,
        "is_current_window": False,
        "window_active": False,
        "pane_active": False,
        "focus_target": {
            "method": "herdr.remote.pane.focus",
            "params": {"host": "thinkpad", "pane_id": "w0-1"},
        },
        "session_phase": "idle",
        "session_phase_label": "Idle",
        "turn_owner": "user",
        "turn_owner_label": "User",
        "activity_substate": "idle",
        "activity_substate_label": "Idle",
        "status_reason": "remote",
        "terminal_context": {
            "window_id": 30,
            "terminal_anchor_id": "remote-anchor",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::host::thinkpad",
            "host_name": "thinkpad",
            "pane_title": "main",
            "pane_active": False,
            "window_active": False,
            "tmux_session": "i3pm-vpittamp-nixos-config-main",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
    })
    runtime_snapshot["sessions"] = [session]
    runtime_snapshot["current_session_key"] = ""

    async def fake_runtime_snapshot(_params):
        return runtime_snapshot

    monkeypatch.setattr(server, "_runtime_snapshot", fake_runtime_snapshot)
    monkeypatch.setattr(server, "_flatten_runtime_windows", lambda snapshot: list(snapshot.get("tracked_windows", [])))
    monkeypatch.setattr(server, "_local_host_alias", lambda: "ryzen")

    result = await server._session_list({})

    assert result["total"] == 1
    session = result["sessions"][0]
    assert session["connection_key"] == "local@thinkpad"
    assert session["focus_connection_key"] == "vpittamp@thinkpad:22"
    assert session["focus_mode"] == "remote_herdr_attach"
    assert session["availability_state"] == "remote_herdr_attachable"
    assert session["focusability_reason"] == ""
    assert session["focus_target"]["method"] == "herdr.remote.pane.focus"


@pytest.mark.asyncio
async def test_dashboard_snapshot_marks_remote_window_focused_from_current_session(server, monkeypatch):
    sessions = [
        {
            "session_key": "session-remote-current",
            "render_session_key": "session-remote-current",
            "window_id": 175,
            "window_active": True,
            "pane_active": True,
            "is_current_window": True,
            "source": "herdr",
            "pane_id": "remote-pane-1",
            "project_name": "PittampalliOrg/stacks:main",
            "execution_mode": "ssh",
            "connection_key": "vpittamp@ryzen:22",
            "focus_connection_key": "vpittamp@ryzen:22",
            "host_name": "ryzen",
            "tool": "codex",
            "pane_label": "main",
            "session_phase": "working",
            "turn_owner": "llm",
            "turn_owner_label": "LLM",
            "activity_substate": "thinking",
            "activity_substate_label": "Thinking",
        },
    ]
    runtime_snapshot = {
        "active_project": "vpittamp/nixos-config:main",
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "outputs": [],
        "tracked_windows": [
            {
                "id": 175,
                "window_id": 175,
                "project": "PittampalliOrg/stacks:main",
                "execution_mode": "ssh",
                "connection_key": "vpittamp@ryzen:22",
                "context_key": "PittampalliOrg/stacks:main::host::ryzen",
                "focused": False,
                "visible": False,
                "hidden": True,
                "title": "Ghostty",
                "app_key": "ghostty",
                "app_name": "Ghostty",
                "scope": "scoped",
                "workspace": "11:stacks",
                "output": "DP-1",
            },
        ],
        "total_windows": 1,
        "state_health": {},
        "launch_stats": {},
        "scratchpad": {},
        "active_terminal": {},
        "sessions": sessions,
        "current_session_key": "session-remote-current",
        "focused_window_id": 175,
    }

    server.display_service.snapshot = AsyncMock(return_value={"outputs": []})
    server._build_dashboard_worktrees = AsyncMock(return_value=[])
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, sessions, {}))

    result = await server._dashboard_snapshot({})

    assert result["active_project"] == "vpittamp/nixos-config:main"
    assert "current_ai_session_key" not in result
    assert result["focus_state"]["current_session_key"] == "session-remote-current"
    window = result["projects"][0]["windows"][0]
    assert window["focused"] is True
    assert window["visible"] is True
    assert window["hidden"] is False


@pytest.mark.asyncio
async def test_dashboard_snapshot_preserves_runtime_active_project(server):
    runtime_snapshot = {
        "active_project": "vpittamp/nixos-config:main",
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "active_project": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
        },
        "outputs": [],
        "tracked_windows": [],
        "total_windows": 0,
        "state_health": {},
        "launch_stats": {},
        "scratchpad": {},
        "active_terminal": {},
        "sessions": [],
        "current_session_key": "",
        "focused_window_id": 0,
    }

    server.display_service.snapshot = AsyncMock(return_value={"outputs": []})
    server._build_dashboard_worktrees = AsyncMock(return_value=[])
    server._load_reconciled_session_runtime = AsyncMock(return_value=(runtime_snapshot, [], {}))

    result = await server._dashboard_snapshot({})

    assert result["active_project"] == "vpittamp/nixos-config:main"
    assert result["active_context"]["active_project"] == "vpittamp/nixos-config:main"


@pytest.mark.asyncio
async def test_hydrate_runtime_git_state_uses_canonical_project_identity(server):
    runtime_snapshot = {
        "active_context": {},
        "tracked_windows": [],
    }
    sessions = [{
        "project_name": "PittampalliOrg/workflow-builder:main",
        "canonical_project_name": "PittampalliOrg/workflow-builder:codex-shared-workspace-capabilities-20260323",
    }]
    server._build_dashboard_worktrees = AsyncMock(return_value=[{
        "qualified_name": "PittampalliOrg/workflow-builder:codex-shared-workspace-capabilities-20260323",
        "path": "/tmp/workflow-builder",
        "branch": "codex-shared-workspace-capabilities-20260323",
        "visible_window_count": 0,
        "scoped_window_count": 0,
    }])
    server._get_or_schedule_git_snapshot = AsyncMock(return_value={
        "state": "dirty",
        "status_compact": "● 1",
        "status_tooltip": "dirty",
        "freshness": "fresh",
        "attribution": "exact_worktree",
        "has_conflicts": False,
        "ahead": 0,
        "behind": 0,
        "staged_count": 0,
        "modified_count": 1,
        "untracked_count": 0,
        "dirty_count": 1,
    })

    await server._hydrate_runtime_git_state(runtime_snapshot, sessions)

    assert sessions[0]["git_state"] == "dirty"
    assert runtime_snapshot["dashboard_worktrees"][0]["git_state"] == "dirty"


@pytest.mark.asyncio
async def test_build_dashboard_worktrees_rebuilds_when_cached_active_context_is_stale(server, monkeypatch):
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "project_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
        },
        "tracked_windows": [],
    }
    server.dashboard_worktree_service._cache = [{
        "qualified_name": "PittampalliOrg/stacks:main",
        "is_active": True,
    }]
    server.dashboard_worktree_service._cache_time = time.time()
    server.dashboard_worktree_service._cache_fingerprint_value = {
        "active_qualified": "PittampalliOrg/stacks:main",
        "active_target_host": "local",
        "repos": (0, 0),
        "usage": (0, 0),
    }
    monkeypatch.setattr(server, "_stat_fingerprint", lambda _path: (0, 0))
    server._repo_list = AsyncMock(return_value={
        "repositories": [{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [{
                "branch": "main",
                "path": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                "is_clean": True,
                "is_main": True,
            }],
        }],
    })
    monkeypatch.setattr(server, "_get_project_remote_profile", lambda _qualified_name: None)

    worktrees = await server._build_dashboard_worktrees(runtime_snapshot)

    assert len(worktrees) == 1
    assert worktrees[0]["qualified_name"] == "vpittamp/nixos-config:main"
    assert worktrees[0]["is_active"] is True
