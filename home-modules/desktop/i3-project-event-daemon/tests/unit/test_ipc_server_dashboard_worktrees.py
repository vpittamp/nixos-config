"""Unit tests for dashboard worktree ranking and context metadata."""

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


def make_worktree(branch: str, **overrides):
    data = {
        "branch": branch,
        "path": f"/tmp/vpittamp/nixos-config/{branch}",
        "is_main": branch == "main",
        "is_clean": True,
        "is_stale": False,
        "has_conflicts": False,
        "ahead": 0,
        "behind": 0,
        "staged_count": 0,
        "modified_count": 0,
        "untracked_count": 0,
        "last_commit_message": f"commit for {branch}",
    }
    data.update(overrides)
    return data


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


@pytest.mark.asyncio
async def test_build_dashboard_worktrees_prefers_active_visibility_recency_and_dirtyness(server, tmp_path, monkeypatch):
    usage_file = tmp_path / "project-usage.json"
    usage_file.write_text(json.dumps({
        "version": 1,
        "projects": {
            "vpittamp/nixos-config:feature-recent": {"last_used_at": 300, "use_count": 1},
            "vpittamp/nixos-config:feature-frequent": {"last_used_at": 200, "use_count": 50},
            "vpittamp/nixos-config:feature-infrequent": {"last_used_at": 200, "use_count": 1},
        },
    }))
    monkeypatch.setattr(constants_module.ConfigPaths, "PROJECT_USAGE_FILE", usage_file)

    server._repo_list = AsyncMock(return_value={
        "repositories": [{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [
                make_worktree("main"),
                make_worktree("feature-visible"),
                make_worktree("feature-recent"),
                make_worktree("feature-frequent"),
                make_worktree("feature-infrequent"),
                make_worktree("feature-dirty", is_clean=False, modified_count=2),
                make_worktree("feature-clean"),
            ],
        }],
    })
    server._flatten_runtime_windows = lambda _snapshot: [
        {"project": "vpittamp/nixos-config:feature-visible", "hidden": False},
    ]
    server._get_project_remote_profile = lambda _qualified_name: None

    result = await server._build_dashboard_worktrees({
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "local",
        },
    })

    assert [item["qualified_name"] for item in result] == [
        "vpittamp/nixos-config:main",
        "vpittamp/nixos-config:feature-visible",
        "vpittamp/nixos-config:feature-recent",
        "vpittamp/nixos-config:feature-frequent",
        "vpittamp/nixos-config:feature-infrequent",
        "vpittamp/nixos-config:feature-dirty",
        "vpittamp/nixos-config:feature-clean",
    ]


@pytest.mark.asyncio
async def test_build_dashboard_worktrees_exposes_remote_availability_and_active_mode(server, tmp_path, monkeypatch):
    usage_file = tmp_path / "project-usage.json"
    usage_file.write_text(json.dumps({"version": 1, "projects": {}}))
    monkeypatch.setattr(constants_module.ConfigPaths, "PROJECT_USAGE_FILE", usage_file)

    server._repo_list = AsyncMock(return_value={
        "repositories": [{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [
                make_worktree("main"),
                make_worktree("feature-local"),
            ],
        }],
    })
    server._flatten_runtime_windows = lambda _snapshot: []
    server._get_project_remote_profile = lambda qualified_name: (
        {"enabled": True, "host": "ryzen"}
        if qualified_name == "vpittamp/nixos-config:main"
        else None
    )

    result = await server._build_dashboard_worktrees({
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "execution_mode": "ssh",
        },
    })

    assert result[0]["qualified_name"] == "vpittamp/nixos-config:main"
    assert result[0]["is_active"] is True
    assert result[0]["active_execution_mode"] == "ssh"
    assert result[0]["remote_available"] is True
    assert result[1]["qualified_name"] == "vpittamp/nixos-config:feature-local"
    assert result[1]["remote_available"] is False
