"""Regression tests for the i3pm desktop MCP bridge."""

from __future__ import annotations

import importlib.util
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MCP_SCRIPT = REPO_ROOT / "scripts" / "i3pm-desktop-mcp.py"


spec = importlib.util.spec_from_file_location("i3pm_desktop_mcp", MCP_SCRIPT)
i3pm_desktop_mcp = importlib.util.module_from_spec(spec)
assert spec is not None
assert spec.loader is not None
spec.loader.exec_module(i3pm_desktop_mcp)


class FakeClient:
    def __init__(self):
        self.calls = []

    def request(self, method, params=None):
        self.calls.append((method, params or {}))
        if method == "dashboard.snapshot":
            return {
                "active_context": {
                    "qualified_name": "vpittamp/nixos-config:main",
                    "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
                    "connection_key": "local@ryzen",
                },
                "focus_state": {
                    "current_session_key": "herdr:pane:1",
                    "current_window_id": 11,
                    "current_workspace_name": "2",
                    "current_herdr_pane_id": "1",
                    "current_herdr_host": "ryzen",
                },
                "tracked_windows": [
                    {
                        "window_id": 11,
                        "title": "Editor",
                        "app_name": "code",
                        "window_class": "code",
                        "project": "vpittamp/nixos-config:main",
                        "workspace": "2",
                        "output": "DP-1",
                        "visible": True,
                        "focused": True,
                        "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
                        "connection_key": "local@ryzen",
                    },
                    {
                        "window_id": 22,
                        "title": "Other",
                        "app_name": "browser",
                        "visible": True,
                        "focused": False,
                        "context_key": "other::local::local@ryzen",
                    },
                ],
                "outputs": [
                    {
                        "name": "DP-1",
                        "workspaces": [{"name": "2", "focused": True, "windows": []}],
                    }
                ],
                "active_outputs": ["DP-1"],
                "active_ai_sessions": [{"session_key": "herdr:pane:1", "pane_id": "1", "source": "herdr"}],
                "scratchpad": {"available": True},
                "active_terminal": {},
                "launch_stats": {},
            }
        if method == "window.focus_fast":
            return {"success": True, "message": "focused"}
        if method == "workspace.focus_fast":
            return {"success": True, "message": "workspace focused"}
        if method == "daemon.apps":
            return {
                "applications": [
                    {"name": "herdr", "display_name": "Herdr", "description": "AI sessions"},
                    {"name": "firefox", "display_name": "Firefox", "description": "Browser"},
                ]
            }
        if method == "launch.open":
            return {"success": True, "message": "launched"}
        if method == "window.action":
            return {"success": True, "message": "closed"}
        raise AssertionError(f"unexpected method {method}")


def test_desktop_context_uses_dashboard_snapshot_focus_state_and_herdr_rows():
    client = FakeClient()

    result = i3pm_desktop_mcp.dispatch_tool(client, "get_desktop_context", {})

    assert client.calls == [("dashboard.snapshot", {})]
    assert result["isError"] is False
    structured = result["structuredContent"]
    assert structured["focused_window"]["window_id"] == 11
    assert structured["workspace"]["current_workspace"] == "2"
    assert structured["current_session_key"] == "herdr:pane:1"
    assert "current_ai_session_key" not in structured
    assert structured["runtime"]["herdr_session_count"] == 1
    assert structured["sessions"][0]["source"] == "herdr"


def test_focus_window_uses_current_daemon_focus_endpoint():
    client = FakeClient()

    result = i3pm_desktop_mcp.dispatch_tool(client, "focus_window", {"query": "editor"})

    assert ("dashboard.snapshot", {}) in client.calls
    assert client.calls[-1][0] == "window.focus_fast"
    assert client.calls[-1][1]["window_id"] == 11
    assert result["structuredContent"]["success"] is True


def test_launch_app_resolves_registry_without_assistant_rpc():
    client = FakeClient()

    result = i3pm_desktop_mcp.dispatch_tool(client, "launch_app", {"app_name": "herdr"})

    assert [method for method, _params in client.calls] == ["daemon.apps", "launch.open"]
    assert client.calls[-1][1]["app_name"] == "herdr"
    assert result["structuredContent"]["target_id"] == "herdr"


def test_close_window_uses_dashboard_snapshot_for_target_resolution():
    client = FakeClient()

    result = i3pm_desktop_mcp.dispatch_tool(
        client,
        "close_window",
        {"query": "editor", "confirm": True},
    )

    assert ("dashboard.snapshot", {}) in client.calls
    assert client.calls[-1][0] == "window.action"
    assert client.calls[-1][1]["window_id"] == 11
    assert result["structuredContent"]["success"] is True


def test_script_does_not_call_retired_assistant_desktop_rpc():
    text = MCP_SCRIPT.read_text()

    assert "assistant.desktop" not in text
    assert "runtime.snapshot" not in text
