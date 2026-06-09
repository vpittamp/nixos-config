"""Unit tests for Herdr-native AI session rows."""

from __future__ import annotations

import importlib
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


PACKAGE_ROOT = Path(__file__).parent.parent.parent

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
constants_module = importlib.import_module("i3_project_daemon.constants")

IPCServer = ipc_server_module.IPCServer


class DummyLaunchRegistry:
    def get_stats(self):
        return SimpleNamespace(total_pending=0)


class DummyStateManager:
    def __init__(self):
        self.state = SimpleNamespace(
            active_project="global",
            window_map={},
            launch_registry=DummyLaunchRegistry(),
        )
        self.launch_registry = self.state.launch_registry

    async def get_active_project(self):
        return self.state.active_project

    async def remove_window(self, _window_id: int):
        return None


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


def test_herdr_rows_preserve_status_and_targets(server, tmp_path, monkeypatch):
    repos_file = tmp_path / "repos.json"
    repos_file.write_text(json.dumps({
        "repositories": [{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [{
                "branch": "main",
                "path": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            }],
        }],
    }))
    monkeypatch.setattr(constants_module.ConfigPaths, "REPOS_FILE", repos_file)
    ipc_server_module._load_discovered_worktree_cache(force_refresh=True)

    rows = server._normalize_herdr_sessions({
        "agents": [{
            "agent": "codex",
            "agent_status": "blocked",
            "cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "focused": True,
            "foreground_cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "pane_id": "w123-1",
            "revision": 7,
            "tab_id": "w123:1",
            "terminal_id": "term_123",
            "workspace_id": "w123",
        }],
        "panes": [{
            "agent": "codex",
            "agent_status": "blocked",
            "cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "focused": True,
            "foreground_cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "pane_id": "w123-1",
            "revision": 7,
            "tab_id": "w123:1",
            "terminal_id": "term_123",
            "workspace_id": "w123",
        }],
    })

    assert len(rows) == 1
    row = rows[0]
    assert row["source"] == "herdr"
    assert row["agent_status"] == "blocked"
    assert row["session_key"] == "herdr:pane:w123-1"
    assert row["workspace_id"] == "w123"
    assert row["tab_id"] == "w123:1"
    assert row["pane_id"] == "w123-1"
    assert row["terminal_id"] == "term_123"
    assert row["project_name"] == "vpittamp/nixos-config:main"
    assert row["focused"] is True
    assert row["focus_target"] == {
        "method": "herdr.pane.focus",
        "params": {"pane_id": "w123-1"},
    }
    assert row["close_target"] == {
        "method": "herdr.pane.close",
        "params": {"pane_id": "w123-1"},
    }
    assert row["herdr_host"]
    assert row["is_remote_herdr"] is False
    assert row["is_current_host"] is True


def test_herdr_rows_skip_plain_panes_and_keep_unknown_status(server):
    rows = server._normalize_herdr_sessions({
        "agents": [],
        "panes": [{
            "agent_status": "unknown",
            "cwd": "/tmp",
            "focused": False,
            "foreground_cwd": "/tmp",
            "pane_id": "plain-1",
            "tab_id": "plain:1",
            "terminal_id": "term_plain",
            "workspace_id": "plain",
        }, {
            "agent": "claude",
            "agent_status": "done",
            "cwd": "/tmp",
            "focused": False,
            "foreground_cwd": "/tmp",
            "pane_id": "agent-1",
            "tab_id": "agent:1",
            "terminal_id": "term_agent",
            "workspace_id": "agent",
        }],
    })

    assert len(rows) == 1
    assert rows[0]["agent"] == "claude"
    assert rows[0]["agent_status"] == "done"
    assert rows[0]["focus_target"]["params"] == {"pane_id": "agent-1"}


def test_herdr_spaces_group_by_host_workspace_and_prioritize_status(server):
    sessions = [{
        "source": "herdr",
        "agent": "codex",
        "agent_status": "working",
        "focused": False,
        "herdr_host": server._local_host_alias(),
        "host_name": server._local_host_alias(),
        "is_current_host": True,
        "is_remote_herdr": False,
        "execution_mode": "local",
        "pane_id": "local-pane-1",
        "project_name": "vpittamp/nixos-config:main",
        "workspace_id": "local-ws",
    }, {
        "source": "herdr",
        "agent": "claude",
        "agent_status": "done",
        "focused": False,
        "herdr_host": "ryzen",
        "host_name": "ryzen",
        "is_current_host": False,
        "is_remote_herdr": True,
        "execution_mode": "ssh",
        "pane_id": "remote-pane-1",
        "project_name": "PittampalliOrg/workflow-builder:main",
        "workspace_id": "remote-ws",
    }, {
        "source": "herdr",
        "agent": "codex",
        "agent_status": "NeedsInput",
        "focused": True,
        "herdr_host": "ryzen",
        "host_name": "ryzen",
        "is_current_host": False,
        "is_remote_herdr": True,
        "execution_mode": "ssh",
        "pane_id": "remote-pane-2",
        "project_name": "PittampalliOrg/workflow-builder:main",
        "workspace_id": "remote-ws",
    }]
    snapshot = {
        "workspaces": [{
            "workspace_id": "local-ws",
            "name": "nixos",
            "focused": False,
            "herdr_host": server._local_host_alias(),
            "execution_mode": "local",
            "is_remote_herdr": False,
        }, {
            "workspace_id": "remote-ws",
            "name": "builder",
            "focused": True,
            "herdr_host": "ryzen",
            "execution_mode": "ssh",
            "is_remote_herdr": True,
        }],
        "agents": sessions,
        "panes": [
            {"pane_id": "local-pane-1", "workspace_id": "local-ws", "herdr_host": server._local_host_alias()},
            {"pane_id": "remote-pane-1", "workspace_id": "remote-ws", "herdr_host": "ryzen"},
            {"pane_id": "remote-pane-2", "workspace_id": "remote-ws", "herdr_host": "ryzen"},
        ],
        "tabs": [
            {"tab_id": "local-tab", "workspace_id": "local-ws", "herdr_host": server._local_host_alias()},
            {"tab_id": "remote-tab", "workspace_id": "remote-ws", "herdr_host": "ryzen"},
        ],
    }

    spaces = server._build_herdr_spaces(snapshot, sessions)

    assert [space["space_key"] for space in spaces] == [
        "herdr:ryzen:workspace:remote-ws",
        f"herdr:{server._local_host_alias()}:workspace:local-ws",
    ]
    remote_space = spaces[0]
    local_space = spaces[1]
    assert remote_space["focused"] is True
    assert remote_space["agent_status"] == "blocked"
    assert remote_space["agent_count"] == 2
    assert remote_space["pane_count"] == 2
    assert remote_space["tab_count"] == 1
    assert remote_space["project_name"] == "PittampalliOrg/workflow-builder:main"
    assert "focus_target" not in remote_space
    assert local_space["agent_status"] == "working"
    assert local_space["focus_target"] == {
        "method": "herdr.workspace.focus",
        "params": {"workspace_id": "local-ws"},
    }


def test_herdr_spaces_use_sidebar_names_and_single_effective_focus(server):
    local_host = server._local_host_alias()
    sessions = [{
        "source": "herdr",
        "agent": "codex",
        "agent_status": "working",
        "focused": True,
        "herdr_host": "ryzen",
        "host_name": "ryzen",
        "is_current_host": False,
        "is_remote_herdr": True,
        "execution_mode": "ssh",
        "pane_id": "remote-pane-1",
        "project_name": "vpittamp/nixos-config:main",
        "workspace_id": "remote-ws",
    }]
    snapshot = {
        "workspaces": [{
            "workspace_id": "local-ws",
            "label": "main",
            "focused": True,
            "herdr_host": local_host,
            "execution_mode": "local",
            "is_remote_herdr": False,
        }, {
            "workspace_id": "remote-ws",
            "label": "nixos-config",
            "focused": True,
            "herdr_host": "ryzen",
            "execution_mode": "ssh",
            "is_remote_herdr": True,
        }],
        "agents": sessions,
        "panes": [{
            "pane_id": "remote-pane-1",
            "workspace_id": "remote-ws",
            "herdr_host": "ryzen",
        }],
        "tabs": [],
    }

    spaces = server._build_herdr_spaces(snapshot, sessions)

    assert [space["label"] for space in spaces] == ["nixos-config", "main"]
    assert [space["focused"] for space in spaces] == [True, False]
    assert spaces[0]["space_key"] == "herdr:ryzen:workspace:remote-ws"
    assert spaces[0]["project_name"] == "vpittamp/nixos-config:main"


@pytest.mark.asyncio
async def test_dashboard_snapshot_includes_herdr_spaces(server, monkeypatch):
    local_host = server._local_host_alias()
    sessions = [{
        "source": "herdr",
        "agent": "codex",
        "agent_status": "working",
        "focused": True,
        "herdr_host": local_host,
        "host_name": local_host,
        "is_current_host": True,
        "is_remote_herdr": False,
        "execution_mode": "local",
        "pane_id": "local-pane",
        "project_name": "vpittamp/nixos-config:main",
        "workspace_id": "local-ws",
    }]
    runtime_snapshot = {
        "current_ai_session_key": "herdr:pane:local-pane",
        "herdr": {
            "status": {"success": True},
            "workspaces": [{
                "workspace_id": "local-ws",
                "label": "nixos",
                "focused": True,
                "herdr_host": local_host,
                "execution_mode": "local",
                "is_remote_herdr": False,
            }],
            "agents": sessions,
            "panes": [{
                "pane_id": "local-pane",
                "workspace_id": "local-ws",
                "herdr_host": local_host,
            }],
            "tabs": [{
                "tab_id": "local-tab",
                "workspace_id": "local-ws",
                "herdr_host": local_host,
            }],
            "errors": [],
        },
        "outputs": [],
        "active_outputs": [],
        "total_windows": 0,
        "tracked_windows": [],
        "dashboard_worktrees": [{"kind": "global"}],
    }

    async def fake_runtime(_params, close_windows=True):
        assert close_windows is True
        return runtime_snapshot, sessions, {}

    monkeypatch.setattr(server, "_load_reconciled_session_runtime", fake_runtime)
    monkeypatch.setattr(server, "_display_snapshot", AsyncMock(return_value={}))

    dashboard = await server._dashboard_snapshot({})

    assert dashboard["active_ai_sessions"] == sessions
    assert dashboard["current_ai_session_key"] == "herdr:pane:local-pane"
    assert dashboard["herdr"]["spaces"] == [{
        "space_key": f"herdr:{local_host}:workspace:local-ws",
        "host_key": local_host,
        "host_label": local_host,
        "workspace_id": "local-ws",
        "label": "nixos",
        "focused": True,
        "agent_status": "working",
        "agent_count": 1,
        "pane_count": 1,
        "tab_count": 1,
        "project_name": "vpittamp/nixos-config:main",
        "execution_mode": "local",
        "is_current_host": True,
        "focus_target": {
            "method": "herdr.workspace.focus",
            "params": {"workspace_id": "local-ws"},
        },
    }]


@pytest.mark.asyncio
async def test_herdr_snapshot_merges_local_and_remote_rows(server, monkeypatch):
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }

    async def fake_run_herdr_json(args):
        command = " ".join(args)
        if command == "status --json":
            return {"success": True, "result": {"ok": True}}
        if command == "agent list":
            return {
                "success": True,
                "result": {
                    "agents": [{
                        "agent": "codex",
                        "agent_status": "blocked",
                        "cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                        "focused": True,
                        "foreground_cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                        "pane_id": "local-pane",
                    }],
                },
            }
        if command == "pane list":
            return {
                "success": True,
                "result": {
                    "panes": [{
                        "agent": "codex",
                        "agent_status": "blocked",
                        "cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                        "focused": True,
                        "foreground_cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                        "pane_id": "local-pane",
                    }],
                },
            }
        key = args[0] + "s"
        return {"success": True, "result": {key: []}}

    async def fake_run_herdr_ssh_json(remote_target, args):
        assert remote_target == target
        command = " ".join(args)
        if command == "status --json":
            return {"success": True, "result": {"ok": True}}
        if command == "agent list":
            return {
                "success": True,
                "result": {
                    "agents": [{
                        "agent": "claude",
                        "agent_status": "NeedsInput",
                        "cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                        "focused": True,
                        "foreground_cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                        "pane_id": "remote-pane",
                    }],
                },
            }
        if command == "pane list":
            return {
                "success": True,
                "result": {
                    "panes": [{
                        "agent": "claude",
                        "agent_status": "NeedsInput",
                        "cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                        "focused": True,
                        "foreground_cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                        "pane_id": "remote-pane",
                    }],
                },
            }
        key = args[0] + "s"
        return {"success": True, "result": {key: []}}

    monkeypatch.setattr(server, "_load_herdr_remote_targets", lambda: [target])
    monkeypatch.setattr(server, "_run_herdr_json", fake_run_herdr_json)
    monkeypatch.setattr(server, "_run_herdr_ssh_json", fake_run_herdr_ssh_json)

    snapshot = await server._herdr_snapshot({"refresh": True})
    rows = snapshot["sessions"]

    assert [row["session_key"] for row in rows] == [
        "herdr:pane:local-pane",
        "herdr:ryzen:pane:remote-pane",
    ]
    local_row = rows[0]
    remote_row = rows[1]
    assert local_row["agent_status"] == "blocked"
    assert local_row["close_target"]["method"] == "herdr.pane.close"
    assert remote_row["agent_status"] == "NeedsInput"
    assert remote_row["herdr_host"] == "ryzen"
    assert remote_row["ssh_target"] == "ryzen"
    assert remote_row["is_remote_herdr"] is True
    assert remote_row["execution_mode"] == "ssh"
    assert remote_row["connection_key"] == "vpittamp@ryzen:22"
    assert remote_row["focus_target"] == {
        "method": "herdr.remote.pane.focus",
        "params": {
            "pane_id": "remote-pane",
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
            "app_name": "herdr",
        },
    }
    assert remote_row["close_target"] == {}
    assert server._select_current_session_key(rows, focused_window_id=0) == "herdr:pane:local-pane"


@pytest.mark.asyncio
async def test_herdr_remote_unreachable_reports_error_without_rows(server, monkeypatch):
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }

    async def fake_run_herdr_ssh_json(_remote_target, args):
        return {
            "success": False,
            "error": "timeout",
            "stderr": "",
            "command": ["ssh", "ryzen", "herdr", *args],
            "returncode": None,
        }

    monkeypatch.setattr(server, "_run_herdr_ssh_json", fake_run_herdr_ssh_json)

    snapshot = await server._herdr_remote_snapshot(target)

    assert snapshot["success"] is False
    assert snapshot["sessions"] == []
    assert snapshot["agents"] == []
    assert snapshot["errors"]
    assert snapshot["errors"][0]["remote"] is True
    assert snapshot["errors"][0]["host"] == "ryzen"


@pytest.mark.asyncio
async def test_herdr_pane_actions_call_herdr_with_pane_id(server, monkeypatch):
    calls = []

    async def fake_run_herdr_json(args):
        calls.append(args)
        return {"success": True, "result": {"ok": True}}

    monkeypatch.setattr(server, "_run_herdr_json", fake_run_herdr_json)

    focus_result = await server._herdr_pane_focus({"pane_id": "w123-1"})
    close_result = await server._herdr_pane_close({"pane_id": "w123-1"})

    assert calls == [
        ["agent", "focus", "w123-1"],
        ["pane", "close", "w123-1"],
    ]
    assert focus_result["success"] is True
    assert focus_result["pane_id"] == "w123-1"
    assert close_result["success"] is True
    assert close_result["pane_id"] == "w123-1"


@pytest.mark.asyncio
async def test_herdr_remote_pane_focus_switches_pane_then_reuses_herdr_app(server, monkeypatch):
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }
    calls = []

    async def fake_run_herdr_ssh_json(remote_target, args):
        calls.append((remote_target, args))
        return {"success": True, "result": {"focused": True}}

    monkeypatch.setattr(server, "_load_herdr_remote_targets", lambda: [target])
    monkeypatch.setattr(server, "_run_herdr_ssh_json", fake_run_herdr_ssh_json)
    server._launch_open = AsyncMock(return_value={
        "success": True,
        "launch": {
            "success": True,
            "reused_existing": True,
            "window_id": 777,
        },
    })

    result = await server._herdr_remote_pane_focus({
        "pane_id": "remote-pane",
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
        "__intent_epoch": 12,
    })

    assert calls == [(target, ["agent", "focus", "remote-pane"])]
    server._launch_open.assert_awaited_once_with({
        "app_name": "herdr",
        "__intent_epoch": 12,
    })
    assert result["success"] is True
    assert result["launch"]["launch"]["reused_existing"] is True
