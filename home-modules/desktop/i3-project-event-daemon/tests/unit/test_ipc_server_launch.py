"""Unit tests for daemon launch preparation and terminal helper selection."""

from __future__ import annotations

import importlib
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

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
registry_module = importlib.import_module("i3_project_daemon.services.registry_loader")

IPCServer = ipc_server_module.IPCServer
RegistryApp = registry_module.RegistryApp


LOCAL_PROJECT = str(Path.cwd())
REMOTE_PROJECT = "/srv/worktrees/nixos-config/main"
QUALIFIED_NAME = "vpittamp/nixos-config:main"


class DummyLaunchRegistry:
    def get_stats(self):
        return SimpleNamespace(total_pending=0)


class DummyStateManager:
    def __init__(self, active_project: str):
        self.state = SimpleNamespace(
            active_project=active_project,
            window_map={},
            launch_registry=DummyLaunchRegistry(),
        )
        self.launch_registry = self.state.launch_registry

    async def get_active_project(self):
        return self.state.active_project

    async def remove_window(self, _window_id: int):
        return None


def make_registry_app(
    *,
    name: str,
    parameters: list[str],
    command: str = "ghostty",
    terminal: bool = True,
    scope: str = "scoped",
    scoped_terminal_mode: str | None = None,
) -> RegistryApp:
    return RegistryApp(
        name=name,
        display_name=name.title(),
        icon="",
        command=command,
        parameters=parameters,
        terminal=terminal,
        expected_class="com.mitchellh.ghostty" if terminal else "Code",
        expected_title_contains=None,
        preferred_workspace=1,
        scope=scope,
        fallback_behavior="use_home",
        multi_instance=True,
        pwa_match_domains=[],
        scoped_terminal_mode=scoped_terminal_mode,
    )


def make_context(*, execution_mode: str, connection_key: str, remote: dict | None = None) -> dict:
    return {
        "qualified_name": QUALIFIED_NAME,
        "repo_qualified_name": "vpittamp/nixos-config",
        "branch": "main",
        "directory": REMOTE_PROJECT if execution_mode == "ssh" else LOCAL_PROJECT,
        "local_directory": LOCAL_PROJECT,
        "account": "vpittamp",
        "repo_name": "nixos-config",
        "remote": remote,
        "execution_mode": execution_mode,
        "host_alias": "ryzen" if execution_mode == "ssh" else "thinkpad",
        "connection_key": connection_key,
        "identity_key": f"{execution_mode}:{connection_key}",
        "context_key": f"{QUALIFIED_NAME}::{execution_mode}::{connection_key}",
    }


@pytest.fixture
def server_local():
    state_manager = DummyStateManager(QUALIFIED_NAME)
    server = IPCServer(state_manager)
    server.registry_loader.applications = {
        "terminal": make_registry_app(name="terminal", parameters=["-e", "bash", "-lc", "true"], scoped_terminal_mode="managed_project_terminal"),
        "yazi": make_registry_app(name="yazi", parameters=["-e", "yazi", "$PROJECT_DIR"], scoped_terminal_mode="dedicated_scoped_window"),
        "lazygit": make_registry_app(name="lazygit", parameters=["-e", "lazygit", "--path", "$PROJECT_DIR"], scoped_terminal_mode="dedicated_scoped_window"),
        "nvim": make_registry_app(name="nvim", parameters=["-e", "nvim", "$PROJECT_DIR"], scoped_terminal_mode="dedicated_scoped_window"),
        "code": make_registry_app(
            name="code",
            command="code",
            parameters=["$PROJECT_DIR"],
            terminal=False,
        ),
    }
    server.registry_loader.version = "test"
    server._set_active_runtime_context(
        make_context(execution_mode="local", connection_key="local@thinkpad")
    )
    return server


@pytest.fixture
def server_ssh():
    state_manager = DummyStateManager(QUALIFIED_NAME)
    server = IPCServer(state_manager)
    server.registry_loader.applications = {
        "terminal": make_registry_app(name="terminal", parameters=["-e", "bash", "-lc", "true"], scoped_terminal_mode="managed_project_terminal"),
        "yazi": make_registry_app(name="yazi", parameters=["-e", "yazi", "$PROJECT_DIR"], scoped_terminal_mode="dedicated_scoped_window"),
        "lazygit": make_registry_app(name="lazygit", parameters=["-e", "lazygit", "--path", "$PROJECT_DIR"], scoped_terminal_mode="dedicated_scoped_window"),
        "nvim": make_registry_app(name="nvim", parameters=["-e", "nvim", "$PROJECT_DIR"], scoped_terminal_mode="dedicated_scoped_window"),
        "code": make_registry_app(
            name="code",
            command="code",
            parameters=["$PROJECT_DIR"],
            terminal=False,
        ),
    }
    server.registry_loader.version = "test"
    server._set_active_runtime_context(
        make_context(
            execution_mode="ssh",
            connection_key="vpittamp@ryzen:22",
            remote={
                "enabled": True,
                "host": "ryzen",
                "user": "vpittamp",
                "port": 22,
                "remote_dir": REMOTE_PROJECT,
            },
        )
    )
    return server


@pytest.mark.asyncio
async def test_prepare_launch_terminal_local_uses_managed_tmux(server_local):
    spec = await server_local._prepare_launch({"app_name": "terminal", "register_launch": False})

    assert spec["execution_mode"] == "local"
    assert spec["launch_strategy"] == "managed_local_terminal"
    assert spec["terminal_launch"]["mode"] == "managed_project_terminal"
    assert spec["terminal_launch"]["helper_name"] == "project-terminal-launch.sh"
    assert spec["terminal_launch"]["helper_args"] == []
    assert spec["tmux_session_name"].startswith("i3pm-")


@pytest.mark.asyncio
async def test_prepare_launch_terminal_ssh_uses_managed_tmux(server_ssh):
    spec = await server_ssh._prepare_launch({"app_name": "terminal", "register_launch": False})

    assert spec["execution_mode"] == "ssh"
    assert spec["launch_strategy"] == "managed_remote_terminal"
    assert spec["terminal_launch"]["mode"] == "managed_project_terminal"
    assert spec["terminal_launch"]["helper_name"] == "project-terminal-launch.sh"
    assert spec["terminal_launch"]["remote"]["remote_dir"] == REMOTE_PROJECT
    assert spec["tmux_session_name"].startswith("i3pm-")


@pytest.mark.asyncio
async def test_prepare_launch_yazi_local_uses_scoped_terminal_command(server_local):
    spec = await server_local._prepare_launch({"app_name": "yazi", "register_launch": False})

    assert spec["execution_mode"] == "local"
    assert spec["launch_strategy"] == "dedicated_local_scoped_window"
    assert spec["terminal_launch"]["mode"] == "dedicated_scoped_window"
    assert spec["terminal_launch"]["helper_name"] == "project-command-launch.sh"
    assert spec["terminal_launch"]["helper_args"] == ["yazi", LOCAL_PROJECT]
    assert spec["terminal_role"] == "project-app:yazi"
    assert spec["tmux_session_name"] == ""


@pytest.mark.asyncio
async def test_prepare_launch_yazi_ssh_uses_remote_scoped_terminal_command(server_ssh):
    spec = await server_ssh._prepare_launch({"app_name": "yazi", "register_launch": False})

    assert spec["execution_mode"] == "ssh"
    assert spec["launch_strategy"] == "dedicated_remote_scoped_window"
    assert spec["terminal_launch"]["mode"] == "dedicated_scoped_window"
    assert spec["terminal_launch"]["helper_name"] == "project-command-launch.sh"
    assert spec["terminal_launch"]["helper_args"] == ["yazi", REMOTE_PROJECT]
    assert spec["terminal_launch"]["remote"]["host"] == "ryzen"
    assert spec["terminal_role"] == "project-app:yazi"
    assert spec["tmux_session_name"] == ""


@pytest.mark.asyncio
async def test_prepare_launch_lazygit_local_uses_path_target(server_local):
    spec = await server_local._prepare_launch({"app_name": "lazygit", "register_launch": False})

    assert spec["terminal_launch"]["mode"] == "dedicated_scoped_window"
    assert spec["terminal_launch"]["helper_args"] == ["lazygit", "--path", LOCAL_PROJECT]


@pytest.mark.asyncio
async def test_prepare_launch_lazygit_ssh_uses_path_target(server_ssh):
    spec = await server_ssh._prepare_launch({"app_name": "lazygit", "register_launch": False})

    assert spec["terminal_launch"]["mode"] == "dedicated_scoped_window"
    assert spec["terminal_launch"]["helper_args"] == ["lazygit", "--path", REMOTE_PROJECT]


@pytest.mark.asyncio
async def test_prepare_launch_nvim_local_uses_dedicated_window(server_local):
    spec = await server_local._prepare_launch({"app_name": "nvim", "register_launch": False})

    assert spec["launch_strategy"] == "dedicated_local_scoped_window"
    assert spec["terminal_launch"]["mode"] == "dedicated_scoped_window"
    assert spec["terminal_launch"]["helper_args"] == ["nvim", LOCAL_PROJECT]
    assert spec["terminal_role"] == "project-app:nvim"


@pytest.mark.asyncio
async def test_prepare_launch_nvim_ssh_uses_dedicated_window(server_ssh):
    spec = await server_ssh._prepare_launch({"app_name": "nvim", "register_launch": False})

    assert spec["launch_strategy"] == "dedicated_remote_scoped_window"
    assert spec["terminal_launch"]["mode"] == "dedicated_scoped_window"
    assert spec["terminal_launch"]["helper_args"] == ["nvim", REMOTE_PROJECT]
    assert spec["terminal_role"] == "project-app:nvim"


@pytest.mark.asyncio
async def test_prepare_launch_rejects_non_terminal_ssh(server_ssh):
    with pytest.raises(RuntimeError) as exc_info:
        await server_ssh._prepare_launch({"app_name": "code", "register_launch": False})

    payload = json.loads(str(exc_info.value))
    assert payload["data"]["app_name"] == "code"
    assert payload["data"]["ssh_policy"] == "terminal_only"


def test_build_remote_helper_script_for_scoped_terminal_command(server_ssh):
    spec = {
        "environment": {
            "I3PM_PROJECT_NAME": QUALIFIED_NAME,
            "I3PM_CONTEXT_KEY": f"{QUALIFIED_NAME}::ssh::vpittamp@ryzen:22",
        },
        "terminal_launch": {
            "mode": "dedicated_scoped_window",
            "helper_name": "project-command-launch.sh",
            "helper_args": ["yazi", REMOTE_PROJECT],
            "remote": {
                "host": "ryzen",
                "user": "vpittamp",
                "port": 22,
                "remote_dir": REMOTE_PROJECT,
            },
        },
    }

    helper_path = server_ssh._build_remote_terminal_helper_script(spec)
    try:
        content = helper_path.read_text()
    finally:
        helper_path.unlink(missing_ok=True)

    assert "ssh -tt -o BatchMode=yes -o ConnectTimeout=2 -p 22 vpittamp@ryzen" in content
    assert "I3PM_PROJECT_NAME=vpittamp/nixos-config:main" in content
    assert "I3PM_CONTEXT_KEY=vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22" in content
    assert "project-command-launch.sh" in content
    assert "/srv/worktrees/nixos-config/main" in content
    assert "yazi" in content
    assert "bash -c" not in content


def test_execute_launch_spec_uses_project_command_helper_for_local_scoped_terminal(server_local, monkeypatch):
    spec = {
        "app_name": "yazi",
        "command": "ghostty",
        "args": ["-e", "yazi", LOCAL_PROJECT],
        "execution_mode": "local",
        "local_project_directory": LOCAL_PROJECT,
        "environment": {},
        "terminal_launch": {
            "mode": "dedicated_scoped_window",
            "helper_name": "project-command-launch.sh",
            "helper_args": ["yazi", LOCAL_PROJECT],
        },
    }
    captured = {}

    monkeypatch.setattr(server_local, "_resolve_terminal_helper", lambda _name: Path("/tmp/project-command-launch.sh"))
    monkeypatch.setattr(ipc_server_module.shutil, "which", lambda _name: f"/usr/bin/{_name}")

    def fake_run(cmd, capture_output, text, check):
        captured["cmd"] = cmd
        return MagicMock(returncode=0, stderr="", stdout="")

    monkeypatch.setattr(ipc_server_module.subprocess, "run", fake_run)

    result = server_local._execute_launch_spec(spec)

    assert result["success"] is True
    assert captured["cmd"][-3] == "bash"
    assert captured["cmd"][-2] == "-lc"
    assert "project-command-launch.sh" in captured["cmd"][-1]
    assert "yazi" in captured["cmd"][-1]


def test_resolve_terminal_helper_prefers_packaged_helper_dir(server_local, monkeypatch, tmp_path):
    helper_name = "project-terminal-launch.sh"
    packaged_dir = tmp_path / "packaged"
    packaged_dir.mkdir()
    packaged_helper = packaged_dir / helper_name
    packaged_helper.write_text("#!/usr/bin/env bash\n")

    stale_local_bin = tmp_path / "local-bin"
    stale_local_bin.mkdir()
    stale_helper = stale_local_bin / helper_name
    stale_helper.write_text("#!/usr/bin/env bash\n")

    monkeypatch.setenv("I3PM_TERMINAL_HELPER_DIR", str(packaged_dir))
    monkeypatch.setattr(ipc_server_module.Path, "home", lambda: tmp_path)

    resolved = server_local._resolve_terminal_helper(helper_name)

    assert resolved == packaged_helper


@pytest.mark.asyncio
async def test_launch_open_reuses_existing_terminal_for_scoped_terminal_command(server_local):
    existing_window = SimpleNamespace(window_id=321)
    spec = {
        "app_name": "yazi",
        "project_name": QUALIFIED_NAME,
        "context_key": f"{QUALIFIED_NAME}::local::local@thinkpad",
        "execution_mode": "local",
        "terminal_role": "project-app:yazi",
        "connection_key": "local@thinkpad",
        "terminal_launch": {
            "mode": "dedicated_scoped_window",
            "helper_args": ["yazi", LOCAL_PROJECT],
        },
    }
    server_local._prepare_launch = AsyncMock(return_value=spec)
    server_local._get_reusable_context_terminal_window = AsyncMock(return_value=existing_window)
    server_local._window_focus = AsyncMock(return_value={"success": True, "window_id": 321})

    result = await server_local._launch_open({"app_name": "yazi"})

    server_local._window_focus.assert_awaited_once()
    assert result["success"] is True
    assert result["launch"]["reused_existing"] is True
    assert result["launch"]["window_id"] == 321
