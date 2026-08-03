"""Unit tests for startup pruning of persisted project state.

What survives pruning is now decided by the checkout on disk, not by membership
in an inventory. The `project-usage.json` and `active-project.json` halves of
this routine went away with the inventory that ranked and named their entries.
"""

from __future__ import annotations

import importlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

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
            project_focused_workspace={},
        )
        self.launch_registry = self.state.launch_registry

    async def get_active_project(self):
        return self.state.active_project

    async def remove_window(self, _window_id: int):
        return None


class DummyFocusTracker:
    """Keeps only the one project name the caller declares live."""

    def __init__(self, path: Path, keep: str):
        self.project_focus_file = path
        self._keep = keep

    def _prune_project_focus_map(self, mapping):
        return {
            key: int(value)
            for key, value in mapping.items()
            if key == self._keep
        }


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


def _make_checkout(tmp_path: Path, name: str) -> Path:
    checkout = tmp_path / name
    checkout.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q"], cwd=checkout, check=True)
    return checkout


def _prepare_state(server, tmp_path: Path, monkeypatch, *, local_directory: str):
    active_worktree_file = tmp_path / "active-worktree.json"
    active_worktree_file.write_text(json.dumps({
        "qualified_name": "PittampalliOrg/stacks:main",
        "local_directory": local_directory,
    }))
    monkeypatch.setattr(
        constants_module.ConfigPaths,
        "ACTIVE_WORKTREE_FILE",
        active_worktree_file,
    )

    focus_file = tmp_path / "project-focus-state.json"
    focus_file.write_text(json.dumps({
        "vpittamp/nixos-config:main": 3,
        "PittampalliOrg/stacks:gone": 5,
    }))
    server.state_manager.focus_tracker = DummyFocusTracker(
        focus_file,
        keep="vpittamp/nixos-config:main",
    )
    return active_worktree_file, focus_file


def test_prune_keeps_context_for_a_live_checkout(server, tmp_path, monkeypatch):
    checkout = _make_checkout(tmp_path, "stacks-main")
    active_worktree_file, focus_file = _prepare_state(
        server,
        tmp_path,
        monkeypatch,
        local_directory=str(checkout),
    )

    stats = server.prune_persisted_project_state()

    assert stats == {"focus_removed": 1, "active_worktree_cleared": 0}
    assert active_worktree_file.exists()
    assert json.loads(focus_file.read_text()) == {"vpittamp/nixos-config:main": 3}


def test_prune_clears_context_for_a_vanished_checkout(server, tmp_path, monkeypatch):
    active_worktree_file, _focus_file = _prepare_state(
        server,
        tmp_path,
        monkeypatch,
        local_directory=str(tmp_path / "never-existed"),
    )

    stats = server.prune_persisted_project_state()

    assert stats["active_worktree_cleared"] == 1
    assert not active_worktree_file.exists()
