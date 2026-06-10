"""Unit tests for Herdr-native AI session rows."""

from __future__ import annotations

import asyncio
import importlib
import importlib.util
import json
import subprocess
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
            "custom_status": "reviewing diff",
            "cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "display_agent": "Codex auth",
            "focused": True,
            "foreground_cwd": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "pane_id": "w123-1",
            "revision": 7,
            "state_labels": {
                "blocked": "waiting for approval",
                "idle": "",
                "invalid-state": "ignored",
            },
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
    assert row["display_agent"] == "Codex auth"
    assert row["custom_status"] == "reviewing diff"
    assert row["state_labels"] == {"blocked": "waiting for approval"}
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


def test_herdr_row_uses_git_cwd_when_foreground_cwd_is_not_repo(server, tmp_path, monkeypatch):
    repo_path = tmp_path / "workflow-builder"
    repo_path.mkdir()
    subprocess.run(["git", "init", "-b", "fix/repo-editor-commit-guard"], cwd=repo_path, check=True)
    subprocess.run(["git", "remote", "add", "origin", "git@github.com:PittampalliOrg/workflow-builder.git"], cwd=repo_path, check=True)

    repos_file = tmp_path / "repos.json"
    repos_file.write_text(json.dumps({
        "repositories": [{
            "account": "PittampalliOrg",
            "name": "workflow-builder",
            "worktrees": [{
                "branch": "fix/repo-editor-commit-guard",
                "path": str(repo_path),
            }],
        }],
    }))
    monkeypatch.setattr(constants_module.ConfigPaths, "REPOS_FILE", repos_file)
    ipc_server_module._load_discovered_worktree_cache(force_refresh=True)

    rows = server._normalize_herdr_sessions({
        "agents": [{
            "agent": "codex",
            "agent_status": "working",
            "cwd": str(repo_path),
            "focused": True,
            "foreground_cwd": "/",
            "pane_id": "builder-pane",
            "workspace_id": "builder-ws",
        }],
        "panes": [{
            "agent": "codex",
            "agent_status": "working",
            "cwd": str(repo_path),
            "focused": True,
            "foreground_cwd": "/",
            "pane_id": "builder-pane",
            "workspace_id": "builder-ws",
        }],
    })

    assert rows[0]["working_dir"] == str(repo_path)
    assert rows[0]["project_name"] == "PittampalliOrg/workflow-builder:fix/repo-editor-commit-guard"
    assert rows[0]["repo_key"] == "PittampalliOrg/workflow-builder"
    assert rows[0]["repo_name"] == "workflow-builder"
    assert rows[0]["checkout_path"] == str(repo_path)
    assert rows[0]["branch_label"] == "fix/repo-editor-commit-guard"


def test_herdr_space_computes_git_metadata_when_worktree_list_misses_repo(server, tmp_path):
    repo_path = tmp_path / "workflow-builder"
    repo_path.mkdir()
    subprocess.run(["git", "init", "-b", "fix/repo-editor-commit-guard"], cwd=repo_path, check=True)
    subprocess.run(["git", "remote", "add", "origin", "git@github.com:PittampalliOrg/workflow-builder.git"], cwd=repo_path, check=True)
    local_host = server._local_host_alias()
    sessions = [{
        "session_key": "herdr:pane:local-pane",
        "source": "herdr",
        "agent": "codex",
        "agent_status": "working",
        "focused": True,
        "is_current_window": True,
        "herdr_host": local_host,
        "host_name": local_host,
        "is_current_host": True,
        "is_remote_herdr": False,
        "execution_mode": "local",
        "pane_id": "builder-pane",
        "project_name": "global",
        "workspace_id": "builder-ws",
        "cwd": str(repo_path),
        "foreground_cwd": "/",
    }]
    snapshot = {
        "workspaces": [{
            "workspace_id": "builder-ws",
            "label": "workflow-builder",
            "focused": True,
            "herdr_host": local_host,
            "execution_mode": "local",
            "is_remote_herdr": False,
        }],
        "worktrees": [{
            "workspace_id": "other-ws",
            "repo_key": "vpittamp/nixos-config",
            "repo_name": "nixos-config",
            "checkout_path": "/home/vpittamp/repos/vpittamp/nixos-config/main",
            "branch_label": "main",
            "herdr_host": local_host,
        }],
        "agents": sessions,
        "panes": [{
            "pane_id": "builder-pane",
            "workspace_id": "builder-ws",
            "herdr_host": local_host,
            "cwd": str(repo_path),
            "foreground_cwd": "/",
        }],
        "tabs": [],
    }

    spaces = server._build_herdr_spaces(snapshot, sessions)

    assert len(spaces) == 1
    assert spaces[0]["label"] == "workflow-builder"
    assert spaces[0]["repo_key"] == "PittampalliOrg/workflow-builder"
    assert spaces[0]["repo_name"] == "workflow-builder"
    assert spaces[0]["checkout_path"] == str(repo_path)
    assert spaces[0]["is_linked_worktree"] is False
    assert spaces[0]["branch_label"] == "fix/repo-editor-commit-guard"


def test_herdr_git_metadata_repo_name_uses_repo_key_for_main_checkout(server, tmp_path):
    repo_path = tmp_path / "workflow-builder" / "main"
    repo_path.mkdir(parents=True)
    subprocess.run(["git", "init", "-b", "fix/repo-editor-commit-guard"], cwd=repo_path, check=True)
    subprocess.run(["git", "remote", "add", "origin", "git@github.com:PittampalliOrg/workflow-builder.git"], cwd=repo_path, check=True)

    metadata = server._herdr_git_space_metadata(str(repo_path))

    assert metadata["repo_key"] == "PittampalliOrg/workflow-builder"
    assert metadata["repo_name"] == "workflow-builder"
    assert metadata["checkout_path"] == str(repo_path)
    assert metadata["branch_label"] == "fix/repo-editor-commit-guard"


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

    assert [space["label"] for space in spaces] == ["nixos-config"]
    assert [space["focused"] for space in spaces] == [True]
    assert spaces[0]["space_key"] == "herdr:ryzen:workspace:remote-ws"
    assert spaces[0]["project_name"] == "vpittamp/nixos-config:main"


def test_herdr_spaces_skip_agentless_local_workspaces_when_remote_agents_exist(server):
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
        "pane_id": "remote-pane",
        "project_name": "vpittamp/nixos-config:main",
        "workspace_id": "remote-ws",
    }]
    snapshot = {
        "workspaces": [{
            "workspace_id": "local-shell",
            "label": "~",
            "focused": False,
            "herdr_host": local_host,
            "execution_mode": "local",
            "is_remote_herdr": False,
        }, {
            "workspace_id": "local-main",
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
            "pane_id": "local-shell-pane",
            "workspace_id": "local-shell",
            "herdr_host": local_host,
        }, {
            "pane_id": "local-main-pane",
            "workspace_id": "local-main",
            "herdr_host": local_host,
        }, {
            "pane_id": "remote-pane",
            "workspace_id": "remote-ws",
            "herdr_host": "ryzen",
        }],
        "tabs": [],
    }

    spaces = server._build_herdr_spaces(snapshot, sessions)

    assert [space["space_key"] for space in spaces] == ["herdr:ryzen:workspace:remote-ws"]
    assert spaces[0]["agent_count"] == 1


@pytest.mark.asyncio
async def test_dashboard_snapshot_includes_herdr_spaces(server, monkeypatch):
    local_host = server._local_host_alias()
    sessions = [{
        "session_key": "herdr:pane:local-pane",
        "source": "herdr",
        "agent": "codex",
        "agent_status": "working",
        "focused": True,
        "is_current_window": True,
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
            "herdr_generation": 7,
            "local_herdr_generation": 7,
            "remote_herdr_generation": {"ryzen": 3},
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
    assert dashboard["herdr"]["herdr_generation"] == 7
    assert dashboard["herdr"]["local_herdr_generation"] == 7
    assert dashboard["herdr"]["remote_herdr_generation"] == {"ryzen": 3}
    assert dashboard["herdr"]["spaces"] == [{
        "space_key": f"herdr:{local_host}:workspace:local-ws",
        "host_key": local_host,
        "host_label": local_host,
        "workspace_id": "local-ws",
        "workspace_number": 0,
        "active_tab_id": "",
        "label": "nixos",
        "focused": True,
        "agent_status": "working",
        "agent_count": 1,
        "pane_count": 1,
        "tab_count": 1,
        "project_name": "vpittamp/nixos-config:main",
        "execution_mode": "local",
        "is_current_host": True,
        "group_key": "",
        "repo_key": "",
        "repo_name": "",
        "repo_root": "",
        "checkout_path": "",
        "is_linked_worktree": False,
        "is_group_parent": False,
        "group_member_count": 1,
        "branch_label": "",
        "focus_target": {
            "method": "herdr.workspace.focus",
            "params": {"workspace_id": "local-ws"},
        },
    }]


def test_herdr_spaces_build_worktree_group_metadata(server):
    local_host = server._local_host_alias()
    snapshot = {
        "workspaces": [{
            "workspace_id": "main-ws",
            "label": "nixos-config",
            "number": 1,
            "focused": False,
            "herdr_host": local_host,
            "execution_mode": "local",
            "is_remote_herdr": False,
            "worktree": {
                "repo_key": "vpittamp/nixos-config",
                "repo_name": "nixos-config",
                "repo_root": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                "checkout_path": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                "is_linked_worktree": False,
            },
        }, {
            "workspace_id": "feature-ws",
            "label": "nixos-config",
            "number": 2,
            "active_tab_id": "tab-feature",
            "focused": True,
            "herdr_host": local_host,
            "execution_mode": "local",
            "is_remote_herdr": False,
            "worktree": {
                "repo_key": "vpittamp/nixos-config",
                "repo_name": "nixos-config",
                "repo_root": "/home/vpittamp/repos/vpittamp/nixos-config/main",
                "checkout_path": "/home/vpittamp/repos/vpittamp/nixos-config/worktree/feature-spaces",
                "is_linked_worktree": True,
            },
        }],
        "worktrees": [{
            "workspace_id": "feature-ws",
            "branch": "feature/spaces",
            "checkout_path": "/home/vpittamp/repos/vpittamp/nixos-config/worktree/feature-spaces",
            "repo_key": "vpittamp/nixos-config",
            "herdr_host": local_host,
        }],
        "panes": [],
        "tabs": [],
        "agents": [],
    }

    spaces = server._build_herdr_spaces(snapshot, [])
    by_workspace = {space["workspace_id"]: space for space in spaces}
    parent = by_workspace["main-ws"]
    child = by_workspace["feature-ws"]

    assert parent["group_key"] == f"{local_host}:vpittamp/nixos-config"
    assert child["group_key"] == parent["group_key"]
    assert parent["is_group_parent"] is True
    assert child["is_group_parent"] is False
    assert child["is_linked_worktree"] is True
    assert parent["group_member_count"] == 2
    assert child["branch_label"] == "feature/spaces"
    assert child["workspace_number"] == 2
    assert child["active_tab_id"] == "tab-feature"


def test_herdr_explicit_worktree_metadata_wins_over_computed_fallback(server, tmp_path):
    repo_path = tmp_path / "workflow-builder"
    repo_path.mkdir()
    subprocess.run(["git", "init", "-b", "computed/branch"], cwd=repo_path, check=True)
    subprocess.run(["git", "remote", "add", "origin", "git@github.com:PittampalliOrg/workflow-builder.git"], cwd=repo_path, check=True)
    local_host = server._local_host_alias()
    snapshot = {
        "workspaces": [{
            "workspace_id": "feature-ws",
            "label": "workflow-builder",
            "focused": True,
            "herdr_host": local_host,
            "cwd": str(repo_path),
            "foreground_cwd": str(repo_path),
            "worktree": {
                "repo_key": "herdr/source-repo",
                "repo_name": "workflow-builder",
                "repo_root": "/herdr/source",
                "checkout_path": "/herdr/checkout",
                "is_linked_worktree": True,
                "branch_label": "explicit/herdr-branch",
            },
        }],
        "worktrees": [{
            "workspace_id": "feature-ws",
            "repo_key": "herdr/source-repo",
            "repo_name": "workflow-builder",
            "repo_root": "/herdr/source",
            "checkout_path": "/herdr/checkout",
            "is_linked_worktree": True,
            "branch_label": "explicit/herdr-branch",
            "herdr_host": local_host,
        }],
        "panes": [],
        "tabs": [],
        "agents": [],
    }

    spaces = server._build_herdr_spaces(snapshot, [])

    assert spaces[0]["repo_key"] == "herdr/source-repo"
    assert spaces[0]["repo_root"] == "/herdr/source"
    assert spaces[0]["checkout_path"] == "/herdr/checkout"
    assert spaces[0]["is_linked_worktree"] is True
    assert spaces[0]["branch_label"] == "explicit/herdr-branch"


def test_herdr_spaces_linked_only_workspaces_remain_flat(server):
    local_host = server._local_host_alias()
    snapshot = {
        "workspaces": [{
            "workspace_id": "feature-a",
            "label": "feature-a",
            "herdr_host": local_host,
            "worktree": {
                "repo_key": "vpittamp/nixos-config",
                "checkout_path": "/repo/worktree/feature-a",
                "is_linked_worktree": True,
            },
        }, {
            "workspace_id": "feature-b",
            "label": "feature-b",
            "herdr_host": local_host,
            "worktree": {
                "repo_key": "vpittamp/nixos-config",
                "checkout_path": "/repo/worktree/feature-b",
                "is_linked_worktree": True,
            },
        }],
        "panes": [],
        "tabs": [],
        "agents": [],
    }

    spaces = server._build_herdr_spaces(snapshot, [])

    assert [space["group_key"] for space in spaces] == ["", ""]
    assert [space["is_group_parent"] for space in spaces] == [False, False]


def test_herdr_spaces_non_worktree_repo_matches_remain_flat(server):
    local_host = server._local_host_alias()
    snapshot = {
        "workspaces": [{
            "workspace_id": "one",
            "label": "one",
            "herdr_host": local_host,
            "repo_key": "vpittamp/nixos-config",
        }, {
            "workspace_id": "two",
            "label": "two",
            "herdr_host": local_host,
            "repo_key": "vpittamp/nixos-config",
        }],
        "panes": [],
        "tabs": [],
        "agents": [],
    }

    spaces = server._build_herdr_spaces(snapshot, [])

    assert [space["group_key"] for space in spaces] == ["", ""]


def test_herdr_computed_git_workspaces_sharing_repo_remain_flat(server, tmp_path):
    repo_path = tmp_path / "workflow-builder"
    repo_path.mkdir()
    subprocess.run(["git", "init", "-b", "main"], cwd=repo_path, check=True)
    subprocess.run(["git", "remote", "add", "origin", "git@github.com:PittampalliOrg/workflow-builder.git"], cwd=repo_path, check=True)
    local_host = server._local_host_alias()
    snapshot = {
        "workspaces": [{
            "workspace_id": "one",
            "label": "workflow-builder",
            "herdr_host": local_host,
            "cwd": str(repo_path),
            "foreground_cwd": str(repo_path),
        }, {
            "workspace_id": "two",
            "label": "workflow-builder",
            "herdr_host": local_host,
            "cwd": str(repo_path),
            "foreground_cwd": str(repo_path),
        }],
        "panes": [],
        "tabs": [],
        "agents": [],
    }

    spaces = server._build_herdr_spaces(snapshot, [])

    assert [space["repo_key"] for space in spaces] == ["PittampalliOrg/workflow-builder", "PittampalliOrg/workflow-builder"]
    assert [space["is_linked_worktree"] for space in spaces] == [False, False]
    assert [space["group_key"] for space in spaces] == ["", ""]


def test_herdr_spaces_do_not_fabricate_branch_label_from_checkout_basename(server):
    local_host = server._local_host_alias()
    snapshot = {
        "workspaces": [{
            "workspace_id": "feature-ws",
            "label": "nixos-config",
            "herdr_host": local_host,
            "worktree": {
                "repo_key": "vpittamp/nixos-config",
                "checkout_path": "/home/vpittamp/repos/vpittamp/nixos-config/worktree/feature-fallback",
                "is_linked_worktree": True,
            },
        }],
        "panes": [],
        "tabs": [],
        "agents": [],
    }

    spaces = server._build_herdr_spaces(snapshot, [])

    assert spaces[0]["branch_label"] == ""


def test_herdr_worktree_result_array_normalizes_source_and_open_workspace(server):
    rows = server._herdr_worktree_result_array({
        "success": True,
        "result": {
            "source": {
                "repo_key": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/.bare",
                "repo_name": "workflow-builder",
                "repo_root": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/.bare",
            },
            "worktrees": [{
                "branch": "fix/repo-editor-commit-guard",
                "is_linked_worktree": True,
                "open_workspace_id": "w653b0849e328b1",
                "path": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
            }],
        },
    })

    assert rows == [{
        "branch": "fix/repo-editor-commit-guard",
        "branch_label": "fix/repo-editor-commit-guard",
        "is_linked_worktree": True,
        "open_workspace_id": "w653b0849e328b1",
        "path": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
        "workspace_id": "w653b0849e328b1",
        "repo_key": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/.bare",
        "repo_name": "workflow-builder",
        "repo_root": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/.bare",
        "checkout_path": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
    }]


def test_herdr_remote_worktree_space_remains_focus_only(server):
    snapshot = {
        "workspaces": [{
            "workspace_id": "remote-ws",
            "label": "builder",
            "focused": True,
            "herdr_host": "ryzen",
            "execution_mode": "ssh",
            "is_remote_herdr": True,
            "worktree": {
                "repo_key": "PittampalliOrg/workflow-builder",
                "repo_name": "workflow-builder",
                "checkout_path": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                "is_linked_worktree": False,
            },
        }],
        "panes": [],
        "tabs": [],
        "agents": [],
    }

    spaces = server._build_herdr_spaces(snapshot, [])

    assert spaces[0]["execution_mode"] == "ssh"
    assert spaces[0]["is_current_host"] is False
    assert "focus_target" not in spaces[0]
    assert "close_target" not in spaces[0]


@pytest.mark.asyncio
async def test_herdr_snapshot_merges_local_and_remote_rows(server, monkeypatch):
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }

    async def fake_run_herdr_json(args, timeout=2.0):
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

    proxy_calls = []

    async def fake_run_herdr_proxy_json(remote_target, args, timeout=2.5):
        assert remote_target == target
        proxy_calls.append(args)
        return {
            "success": True,
            "schema_version": "i3pm.herdr_proxy.v1",
            "protocol_version": 1,
            "status": {"success": True, "result": {"ok": True}},
            "agents": [{
                "agent": "claude",
                "agent_status": "NeedsInput",
                "cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                "focused": True,
                "foreground_cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                "pane_id": "remote-pane",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
            }],
            "panes": [{
                "agent": "claude",
                "agent_status": "NeedsInput",
                "cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                "focused": True,
                "foreground_cwd": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
                "pane_id": "remote-pane",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
            }],
            "workspaces": [],
            "tabs": [],
            "worktrees": [],
            "errors": [],
        }

    monkeypatch.setattr(server, "_load_herdr_remote_targets", lambda: [target])
    monkeypatch.setattr(server.herdr_service, "run_json", fake_run_herdr_json)
    monkeypatch.setattr(server.herdr_service, "run_proxy_json", fake_run_herdr_proxy_json)

    snapshot = await server._herdr_snapshot({"refresh": True})
    rows = snapshot["sessions"]

    assert snapshot["local_herdr_generation"] == 0
    assert snapshot["remote_herdr_generation"] == {"ryzen": 1}
    assert snapshot["remote_snapshots"][0]["herdr_generation"] == 1
    assert snapshot["remote_snapshots"][0]["proxy_schema_version"] == "i3pm.herdr_proxy.v1"
    assert proxy_calls == [["snapshot", "--json"]]
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

    async def fake_run_herdr_proxy_json(_remote_target, args, timeout=2.5):
        return {
            "success": False,
            "error": "timeout",
            "stderr": "",
            "command": ["ssh", "ryzen", "i3pm", "herdr-proxy", *args],
            "returncode": None,
        }

    monkeypatch.setattr(server.herdr_service, "run_proxy_json", fake_run_herdr_proxy_json)

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

    async def fake_run_herdr_json(args, timeout=2.0):
        calls.append(args)
        return {"success": True, "result": {"ok": True}}

    monkeypatch.setattr(server.herdr_service, "run_json", fake_run_herdr_json)

    server.herdr_service.snapshot_cache = {"sessions": [{"pane_id": "stale"}]}
    focus_result = await server._herdr_pane_focus({"pane_id": "w123-1"})
    server.herdr_service.snapshot_cache = {"sessions": [{"pane_id": "stale"}]}
    close_result = await server._herdr_pane_close({"pane_id": "w123-1"})

    assert calls == [
        ["agent", "focus", "w123-1"],
        ["pane", "close", "w123-1"],
    ]
    assert focus_result["success"] is True
    assert focus_result["pane_id"] == "w123-1"
    assert close_result["success"] is True
    assert close_result["pane_id"] == "w123-1"
    assert server.herdr_service.local_herdr_generation == 2
    assert server.herdr_service.snapshot_cache == {}


@pytest.mark.asyncio
async def test_herdr_remote_pane_focus_switches_pane_then_reuses_herdr_app(server, monkeypatch):
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }
    calls = []

    async def fake_run_herdr_proxy_json(remote_target, args, timeout=2.5):
        calls.append((remote_target, args))
        return {"success": True, "result": {"focused": True}}

    monkeypatch.setattr(server, "_load_herdr_remote_targets", lambda: [target])
    monkeypatch.setattr(server.herdr_service, "run_proxy_json", fake_run_herdr_proxy_json)
    server.notify_state_change = AsyncMock(return_value=None)
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

    assert calls == [(target, ["focus", "remote-pane", "--json"])]
    server._launch_open.assert_awaited_once_with({
        "app_name": "herdr",
        "__intent_epoch": 12,
        "focus_fast": True,
    })
    server.notify_state_change.assert_awaited_once_with("ai_session_herdr_changed")
    assert server.herdr_service.remote_generation_for("ryzen") == 1
    assert result["success"] is True
    assert result["launch"]["launch"]["reused_existing"] is True


def test_herdr_remote_pane_focus_updates_cached_remote_rows(server):
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }
    server.herdr_service.snapshot_cache = {
        "sessions": [
            {
                "session_key": "herdr:ryzen:pane:remote-a",
                "pane_id": "remote-a",
                "herdr_host": "ryzen",
                "connection_key": "vpittamp@ryzen:22",
                "focused": True,
            },
            {
                "session_key": "herdr:ryzen:pane:remote-b",
                "pane_id": "remote-b",
                "herdr_host": "ryzen",
                "connection_key": "vpittamp@ryzen:22",
                "focused": False,
            },
        ],
        "panes": [
            {
                "pane_id": "remote-a",
                "herdr_host": "ryzen",
                "connection_key": "vpittamp@ryzen:22",
                "focused": True,
            },
            {
                "pane_id": "remote-b",
                "herdr_host": "ryzen",
                "connection_key": "vpittamp@ryzen:22",
                "focused": False,
            },
        ],
        "remote_snapshots": [
            {
                "host": "ryzen",
                "ssh_target": "ryzen",
                "connection_key": "vpittamp@ryzen:22",
                "sessions": [
                    {"pane_id": "remote-a", "focused": True},
                    {"pane_id": "remote-b", "focused": False},
                ],
            },
        ],
    }

    server._apply_remote_herdr_focus_cache(target=target, pane_id="remote-b")

    sessions = server.herdr_service.snapshot_cache["sessions"]
    panes = server.herdr_service.snapshot_cache["panes"]
    remote_sessions = server.herdr_service.snapshot_cache["remote_snapshots"][0]["sessions"]
    assert sessions[0]["focused"] is False
    assert sessions[1]["focused"] is True
    assert sessions[1]["is_current_window"] is True
    assert sessions[1]["pane_active"] is True
    assert panes[0]["focused"] is False
    assert panes[1]["focused"] is True
    assert remote_sessions[0]["focused"] is False
    assert remote_sessions[1]["focused"] is True
    assert server._focus_session_override_key == "herdr:ryzen:pane:remote-b"


@pytest.mark.asyncio
async def test_herdr_event_subscription_sends_expected_payload_and_invalidates_cache(server, tmp_path, monkeypatch):
    socket_path = tmp_path / "herdr.sock"
    requests = []
    received_event = asyncio.Event()

    async def handle_client(reader, writer):
        line = await reader.readline()
        requests.append(json.loads(line.decode("utf-8")))
        writer.write(
            json.dumps({
                "id": "i3pm-herdr-events",
                "result": {"type": "subscription_started"},
            }).encode("utf-8") + b"\n"
        )
        await writer.drain()
        writer.write(json.dumps({
            "event": "pane_focused",
            "data": {"pane_id": "w123-1"},
        }).encode("utf-8") + b"\n")
        await writer.drain()
        received_event.set()
        writer.close()
        await writer.wait_closed()

    unix_server = await asyncio.start_unix_server(handle_client, path=str(socket_path))
    monkeypatch.setattr(server.herdr_service, "socket_path", lambda: socket_path)
    server.herdr_service.snapshot_cache = {"sessions": [{"pane_id": "stale"}]}
    server.herdr_service.snapshot_cache_time = 123.0
    server.herdr_service.notify_delay = 0.0
    server.notify_state_change = AsyncMock()

    try:
        with pytest.raises(ConnectionError):
            await server.herdr_service.connect_subscription_once()
    finally:
        unix_server.close()
        await unix_server.wait_closed()

    assert received_event.is_set()
    assert requests == [server.herdr_service.event_subscribe_payload()]
    subscriptions = requests[0]["params"]["subscriptions"]
    assert {"type": "workspace.created"} in subscriptions
    assert {"type": "workspace.updated"} in subscriptions
    assert {"type": "workspace.renamed"} in subscriptions
    assert {"type": "workspace.closed"} in subscriptions
    assert {"type": "workspace.focused"} in subscriptions
    assert {"type": "tab.created"} in subscriptions
    assert {"type": "tab.closed"} in subscriptions
    assert {"type": "tab.focused"} in subscriptions
    assert {"type": "tab.renamed"} in subscriptions
    assert {"type": "pane.created"} in subscriptions
    assert {"type": "pane.closed"} in subscriptions
    assert {"type": "pane.focused"} in subscriptions
    assert {"type": "pane.exited"} in subscriptions
    assert {"type": "pane.agent_detected"} in subscriptions
    assert server.herdr_service.snapshot_cache == {}
    assert server.herdr_service.snapshot_cache_time == 0.0
    await asyncio.sleep(0)
    server.notify_state_change.assert_awaited_once_with("ai_session_herdr_changed")


@pytest.mark.asyncio
async def test_herdr_subscription_event_does_not_collect_remote_snapshots(server, monkeypatch):
    server.herdr_service.snapshot_cache = {"sessions": [{"pane_id": "stale"}]}
    server.herdr_service.notify_delay = 0.0
    server.notify_state_change = AsyncMock()
    load_remote_targets = AsyncMock()
    monkeypatch.setattr(server, "_load_herdr_remote_targets", load_remote_targets)

    await server.herdr_service.handle_subscription_event({"event": "workspace_updated", "data": {}})

    assert server.herdr_service.snapshot_cache == {}
    load_remote_targets.assert_not_called()
    await asyncio.sleep(0)
    server.notify_state_change.assert_awaited_once_with("ai_session_herdr_changed")


@pytest.mark.asyncio
async def test_herdr_subscription_events_are_coalesced(server):
    server.herdr_service.notify_delay = 0.01
    server.notify_state_change = AsyncMock()

    await server.herdr_service.handle_subscription_event({"event": "pane_updated", "data": {"pane_id": "a"}})
    await server.herdr_service.handle_subscription_event({"event": "pane_updated", "data": {"pane_id": "b"}})
    await server.herdr_service.handle_subscription_event({"event": "pane_updated", "data": {"pane_id": "c"}})
    await asyncio.sleep(0.03)

    server.notify_state_change.assert_awaited_once_with("ai_session_herdr_changed")


@pytest.mark.asyncio
async def test_herdr_event_subscription_retries_after_failure(server):
    attempts = 0
    second_attempt = asyncio.Event()

    async def fail_connect_once():
        nonlocal attempts
        attempts += 1
        if attempts >= 2:
            second_attempt.set()
        raise RuntimeError("invalid ack")

    server.herdr_service.connect_subscription_once = fail_connect_once
    server.herdr_service.subscription_initial_backoff = 0.01
    server.herdr_service.subscription_max_backoff = 0.02

    task = asyncio.create_task(server.herdr_service.run_subscription())
    try:
        await asyncio.wait_for(second_attempt.wait(), timeout=1.0)
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)

    assert attempts >= 2
