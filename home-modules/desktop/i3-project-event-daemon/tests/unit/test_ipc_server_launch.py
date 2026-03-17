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
    def __init__(self):
        self._launches = {}

    def get_stats(self):
        return SimpleNamespace(total_pending=0)

    async def add(self, launch):
        launch_id = f"launch-{len(self._launches) + 1}"
        self._launches[launch_id] = launch
        return launch_id

    async def get_by_terminal_anchor(self, terminal_anchor_id):
        for launch in self._launches.values():
            if str(getattr(launch, "terminal_anchor_id", "") or "").strip() == str(terminal_anchor_id or "").strip():
                return launch
        return None


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
    server._local_host_alias = lambda: "thinkpad"
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
    server._local_host_alias = lambda: "thinkpad"
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


@pytest.fixture
def server_ssh_current_host():
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
    server._local_host_alias = lambda: "ryzen"
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
    assert spec["environment"]["I3PM_TMUX_SOCKET"] == server_local._canonical_tmux_socket()
    assert spec["environment"]["I3PM_TMUX_SERVER_KEY"] == server_local._canonical_tmux_socket()


@pytest.mark.asyncio
async def test_prepare_launch_terminal_ssh_uses_managed_tmux(server_ssh):
    spec = await server_ssh._prepare_launch({"app_name": "terminal", "register_launch": False})

    assert spec["execution_mode"] == "ssh"
    assert spec["launch_strategy"] == "managed_remote_terminal"
    assert spec["terminal_launch"]["mode"] == "managed_project_terminal"
    assert spec["terminal_launch"]["helper_name"] == "project-terminal-launch.sh"
    assert spec["terminal_launch"]["remote"]["remote_dir"] == REMOTE_PROJECT
    assert spec["tmux_session_name"].startswith("i3pm-")
    assert spec["environment"]["I3PM_TMUX_SOCKET"] == server_ssh._canonical_tmux_socket()
    assert spec["environment"]["I3PM_TMUX_SERVER_KEY"] == server_ssh._canonical_tmux_socket()


@pytest.mark.asyncio
async def test_prepare_launch_terminal_ssh_current_host_uses_remote_transport(server_ssh_current_host):
    spec = await server_ssh_current_host._prepare_launch({"app_name": "terminal", "register_launch": False})

    assert spec["execution_mode"] == "ssh"
    assert spec["launch_strategy"] == "managed_remote_terminal"
    assert spec["launch_transport"] == "remote_helper"
    assert spec["terminal_launch"]["mode"] == "managed_project_terminal"
    assert spec["terminal_launch"]["remote"]["host"] == "ryzen"
    assert spec["environment"]["I3PM_CONNECTION_KEY"] == "vpittamp@ryzen:22"
    assert spec["environment"]["I3PM_CONTEXT_VARIANT"] == "ssh"


@pytest.mark.asyncio
async def test_register_launch_for_spec_persists_local_spec_and_status(server_local, tmp_path):
    server_local._runtime_dir = lambda: tmp_path
    spec = await server_local._prepare_launch({"app_name": "terminal", "register_launch": False})

    registration = await server_local._register_launch_for_spec(spec)
    launch_id = registration["launch_id"]
    spec_payload = json.loads(server_local._launch_spec_file(launch_id).read_text())
    status_payload = json.loads(server_local._launch_status_file(launch_id).read_text())

    assert spec_payload["launch_id"] == launch_id
    assert spec_payload["launch_transport"] == "local_helper"
    assert spec_payload["tmux_session_name"].startswith("i3pm-")
    assert status_payload["status"] == "queued"
    assert status_payload["reason"] == "queued"


@pytest.mark.asyncio
async def test_launch_status_reconciles_managed_session_to_waiting_and_running(server_local, tmp_path):
    server_local._runtime_dir = lambda: tmp_path
    spec = await server_local._prepare_launch({"app_name": "terminal", "register_launch": False})
    registration = await server_local._register_launch_for_spec(spec)
    launch_id = registration["launch_id"]

    server_local._managed_tmux_session_probe = MagicMock(return_value={
        "exists": True,
        "healthy": True,
        "reason": "healthy",
        "tmux_session_name": spec["tmux_session_name"],
        "tmux_socket": server_local._canonical_tmux_socket(),
    })
    server_local._get_terminal_anchor = AsyncMock(return_value={
        "matched": False,
        "window_id": 0,
    })
    server_local._write_launch_status(
        launch_id=launch_id,
        status="session_validating",
        spec=spec,
        reason="session_validating",
    )

    waiting = await server_local._launch_status({"launch_id": launch_id})

    assert waiting["status"] == "waiting_window"
    assert waiting["reason"] == "waiting_window"

    server_local._get_terminal_anchor = AsyncMock(return_value={
        "matched": True,
        "window_id": 12,
    })
    running = await server_local._launch_status({"launch_id": launch_id})

    assert running["status"] == "running"
    assert running["reason"] == "window_bound"


@pytest.mark.asyncio
async def test_mark_launch_window_closed_sets_reusable_headless(server_local, tmp_path):
    server_local._runtime_dir = lambda: tmp_path
    spec = await server_local._prepare_launch({"app_name": "terminal", "register_launch": False})
    registration = await server_local._register_launch_for_spec(spec)
    launch_id = registration["launch_id"]

    server_local._managed_tmux_session_probe = MagicMock(return_value={
        "exists": True,
        "healthy": True,
        "reason": "healthy",
        "tmux_session_name": spec["tmux_session_name"],
        "tmux_socket": server_local._canonical_tmux_socket(),
    })
    server_local._write_launch_status(
        launch_id=launch_id,
        status="running",
        spec=spec,
        reason="window_bound",
    )

    result = await server_local._mark_launch_window_closed(SimpleNamespace(
        correlation_launch_id=launch_id,
        terminal_anchor_id=spec["terminal_anchor_id"],
    ))

    assert result["status"] == "reusable_headless"
    assert result["reason"] == "headless_reusable"


@pytest.mark.asyncio
async def test_launch_open_clears_stale_focus_override_for_explicit_project_intent(server_local):
    server_local._set_focus_overrides(
        session_key="session-stale",
        window_id=29,
        connection_key="vpittamp@ryzen:22",
    )
    server_local._get_reusable_context_terminal_window = AsyncMock(
        return_value=SimpleNamespace(window_id=7)
    )
    server_local._dispatch_managed_terminal_command = lambda _spec: None
    server_local._window_focus = AsyncMock(return_value={"success": True, "window_id": 7})

    result = await server_local._launch_open({
        "app_name": "terminal",
        "__intent_epoch": 1,
    })

    assert result["success"] is True
    assert result["launch"]["reused_existing"] is True
    assert server_local._focus_session_override_key == ""
    assert server_local._focus_window_override == {"window_id": 0, "connection_key": ""}


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
async def test_prepare_launch_yazi_ssh_current_host_uses_remote_scoped_window(server_ssh_current_host):
    spec = await server_ssh_current_host._prepare_launch({"app_name": "yazi", "register_launch": False})

    assert spec["execution_mode"] == "ssh"
    assert spec["launch_strategy"] == "dedicated_remote_scoped_window"
    assert spec["launch_transport"] == "remote_helper"
    assert spec["terminal_launch"]["mode"] == "dedicated_scoped_window"
    assert spec["terminal_launch"]["remote"]["host"] == "ryzen"


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


@pytest.mark.asyncio
async def test_build_remote_session_attach_spec_overrides_bridge_context_env(server_ssh):
    session = {
        "session_key": "codex|session-remote",
        "surface_key": "surface-remote",
        "project_name": QUALIFIED_NAME,
        "tmux_session": "i3pm-vpittamp-nixos-config-ma-6e1abb85",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "tmux_session": "i3pm-vpittamp-nixos-config-ma-6e1abb85",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
        },
    }
    attach_profile = {
        "connection_key": "vpittamp@thinkpad:22",
        "context_key": f"{QUALIFIED_NAME}::ssh::vpittamp@thinkpad:22",
        "remote_user": "vpittamp",
        "remote_host": "thinkpad",
        "remote_port": 22,
        "remote_dir": "",
    }

    spec = await server_ssh._build_remote_session_attach_spec(session, attach_profile=attach_profile)

    assert spec["connection_key"] == "vpittamp@thinkpad:22"
    assert spec["context_key"] == f"{QUALIFIED_NAME}::ssh::vpittamp@thinkpad:22"
    assert spec["environment"]["I3PM_CONNECTION_KEY"] == "vpittamp@thinkpad:22"
    assert spec["environment"]["I3PM_CONTEXT_KEY"] == f"{QUALIFIED_NAME}::ssh::vpittamp@thinkpad:22"
    assert spec["environment"]["I3PM_REMOTE_HOST"] == "thinkpad"
    assert spec["environment"]["I3PM_REMOTE_USER"] == "vpittamp"


@pytest.mark.asyncio
async def test_build_remote_session_attach_spec_does_not_require_local_worktree(server_ssh, monkeypatch):
    remote_only_project = "PittampalliOrg/workflow-builder:104-create-coding-agent"
    session = {
        "session_key": "codex|session-remote",
        "surface_key": "surface-remote",
        "project_name": remote_only_project,
        "project": remote_only_project,
        "tmux_session": "i3pm-pittampalliorg-workflow--919ce57f",
        "tmux_window": "0:main",
        "tmux_pane": "%2",
        "terminal_context": {
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "tmux_session": "i3pm-pittampalliorg-workflow--919ce57f",
            "tmux_window": "0:main",
            "tmux_pane": "%2",
        },
    }
    attach_profile = {
        "project_name": remote_only_project,
        "connection_key": "vpittamp@ryzen:22",
        "context_key": f"{remote_only_project}::ssh::vpittamp@ryzen:22",
        "remote_user": "vpittamp",
        "remote_host": "ryzen",
        "remote_port": 22,
        "remote_dir": "/home/vpittamp/repos/PittampalliOrg/workflow-builder/104-create-coding-agent",
    }

    monkeypatch.setattr(
        server_ssh,
        "_find_worktree_by_qualified_name",
        lambda _qualified_name: (_ for _ in ()).throw(AssertionError("should not resolve local worktree")),
    )

    spec = await server_ssh._build_remote_session_attach_spec(session, attach_profile=attach_profile)

    assert spec["project_name"] == remote_only_project
    assert spec["execution_mode"] == "ssh"
    assert spec["launch_transport"] == "remote_helper"
    assert spec["project_directory"] == "/home/vpittamp/repos/PittampalliOrg/workflow-builder/104-create-coding-agent"
    assert spec["local_project_directory"] == ""
    assert spec["context_key"] == f"{remote_only_project}::ssh::vpittamp@ryzen:22"
    assert spec["environment"]["I3PM_PROJECT_NAME"] == remote_only_project
    assert spec["environment"]["I3PM_CONTEXT_KEY"] == f"{remote_only_project}::ssh::vpittamp@ryzen:22"
    assert spec["terminal_launch"]["remote_attach"]["tmux_pane"] == "%2"


def test_build_remote_helper_script_for_scoped_terminal_command(server_ssh):
    spec = {
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
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


def test_build_remote_helper_script_for_remote_attach_without_remote_dir(server_ssh):
    spec = {
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "environment": {
            "I3PM_PROJECT_NAME": QUALIFIED_NAME,
            "I3PM_CONTEXT_KEY": f"{QUALIFIED_NAME}::ssh::vpittamp@ryzen:22",
            "I3PM_REMOTE_SESSION_KEY": "codex|remote-session",
        },
        "terminal_launch": {
            "mode": "managed_project_terminal",
            "helper_name": "project-terminal-launch.sh",
            "tmux_session_name": "i3pm-remote-shell",
            "remote": {
                "host": "ryzen",
                "user": "vpittamp",
                "port": 22,
                "remote_dir": "",
            },
            "remote_attach": {
                "tmux_socket": "/run/user/1000/tmux-1000/default",
                "tmux_session": "i3pm-vpittamp-nixos-config-ma-6e1abb85",
                "tmux_window": "0:main",
                "tmux_pane": "%0",
            },
        },
    }

    helper_path = server_ssh._build_remote_terminal_helper_script(spec)
    try:
        content = helper_path.read_text()
    finally:
        helper_path.unlink(missing_ok=True)

    assert "ssh -tt -o BatchMode=yes -o ConnectTimeout=2 -p 22 vpittamp@ryzen" in content
    assert "tmux -S /run/user/1000/tmux-1000/default has-session -t i3pm-vpittamp-nixos-config-ma-6e1abb85" in content
    assert "attach-session -t i3pm-vpittamp-nixos-config-ma-6e1abb85" in content
    assert "cd " not in content


def test_build_remote_helper_script_allows_current_host_ssh_launch(server_ssh_current_host):
    spec = {
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "environment": {
            "I3PM_PROJECT_NAME": QUALIFIED_NAME,
            "I3PM_CONTEXT_KEY": f"{QUALIFIED_NAME}::ssh::vpittamp@ryzen:22",
        },
        "terminal_launch": {
            "mode": "managed_project_terminal",
            "helper_name": "project-terminal-launch.sh",
            "tmux_session_name": "i3pm-remote-shell",
            "remote": {
                "host": "ryzen",
                "user": "vpittamp",
                "port": 22,
                "remote_dir": REMOTE_PROJECT,
            },
        },
    }

    helper_path = server_ssh_current_host._build_remote_terminal_helper_script(spec)
    try:
        content = helper_path.read_text()
    finally:
        helper_path.unlink(missing_ok=True)

    assert "vpittamp@ryzen" in content
    assert "project-terminal-launch.sh" in content


def test_managed_tmux_command_shell_uses_canonical_socket(server_local):
    script = server_local._managed_tmux_command_shell(
        session_name="i3pm-vpittamp-nixos-config-main",
        tmux_socket=server_local._canonical_tmux_socket(),
        working_dir=LOCAL_PROJECT,
        command_args=["yazi", LOCAL_PROJECT],
        environment={
            "I3PM_PROJECT_NAME": QUALIFIED_NAME,
            "I3PM_TMUX_SOCKET": server_local._canonical_tmux_socket(),
        },
    )

    assert f"tmux -S {server_local._canonical_tmux_socket()} has-session -t i3pm-vpittamp-nixos-config-main" in script
    assert f"tmux -S {server_local._canonical_tmux_socket()} set-environment -t i3pm-vpittamp-nixos-config-main I3PM_PROJECT_NAME {QUALIFIED_NAME}" in script
    assert f"tmux -S {server_local._canonical_tmux_socket()} new-window -t i3pm-vpittamp-nixos-config-main" in script


def test_dispatch_managed_terminal_command_ssh_current_host_uses_local_tmux_dispatch(server_ssh_current_host, monkeypatch):
    spec = {
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "local_project_directory": LOCAL_PROJECT,
        "project_directory": REMOTE_PROJECT,
        "launch_transport": "local_helper",
        "environment": {
            "I3PM_TMUX_SOCKET": server_ssh_current_host._canonical_tmux_socket(),
            "I3PM_CONTEXT_KEY": f"{QUALIFIED_NAME}::ssh::vpittamp@ryzen:22",
        },
        "terminal_launch": {
            "mode": "managed_project_terminal",
            "tmux_session_name": "i3pm-vpittamp-nixos-config-main",
            "helper_args": ["yazi", LOCAL_PROJECT],
            "remote": {
                "host": "ryzen",
                "user": "vpittamp",
                "port": 22,
                "remote_dir": REMOTE_PROJECT,
            },
        },
    }
    captured = {}

    def fake_run(cmd, capture_output, text, check):
        captured["cmd"] = cmd
        return MagicMock(returncode=0, stderr="", stdout="")

    monkeypatch.setattr(ipc_server_module.subprocess, "run", fake_run)

    result = server_ssh_current_host._dispatch_managed_terminal_command(spec)

    assert result["success"] is True
    assert captured["cmd"][:2] == ["bash", "-lc"]
    assert "tmux -S" in captured["cmd"][2]
    assert "ssh -o" not in captured["cmd"][2]
    assert "BatchMode=yes" not in captured["cmd"][2]


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


def test_execute_launch_spec_ssh_current_host_uses_local_terminal_helper(server_ssh_current_host, monkeypatch):
    spec = {
        "app_name": "terminal",
        "command": "ghostty",
        "args": ["-e", "bash", "-lc", "true"],
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "launch_transport": "local_helper",
        "local_project_directory": LOCAL_PROJECT,
        "environment": {
            "I3PM_CONTEXT_KEY": f"{QUALIFIED_NAME}::ssh::vpittamp@ryzen:22",
        },
        "terminal_launch": {
            "mode": "managed_project_terminal",
            "helper_name": "project-terminal-launch.sh",
            "helper_args": [],
        },
    }
    captured = {}

    monkeypatch.setattr(server_ssh_current_host, "_resolve_terminal_helper", lambda _name: Path("/tmp/project-terminal-launch.sh"))
    monkeypatch.setattr(server_ssh_current_host, "_build_remote_terminal_helper_script", lambda _spec: (_ for _ in ()).throw(AssertionError("unexpected remote helper")))
    monkeypatch.setattr(ipc_server_module.shutil, "which", lambda _name: f"/usr/bin/{_name}")

    def fake_run(cmd, capture_output, text, check):
        captured["cmd"] = cmd
        return MagicMock(returncode=0, stderr="", stdout="")

    monkeypatch.setattr(ipc_server_module.subprocess, "run", fake_run)

    result = server_ssh_current_host._execute_launch_spec(spec)

    assert result["success"] is True
    assert captured["cmd"][-3] == "bash"
    assert captured["cmd"][-2] == "-lc"
    assert "project-terminal-launch.sh" in captured["cmd"][-1]
    assert "i3pm-remote-launch" not in captured["cmd"][-1]


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


@pytest.mark.asyncio
async def test_launch_open_does_not_reuse_remote_bridge_when_context_mark_drifted(server_ssh):
    spec = {
        "app_name": "terminal",
        "project_name": QUALIFIED_NAME,
        "context_key": f"{QUALIFIED_NAME}::ssh::vpittamp@ryzen:22",
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "launch_transport": "remote_helper",
        "terminal_role": "project-main",
        "terminal_anchor_id": "terminal-anchor",
        "preferred_workspace": 1,
        "tmux_session_name": "i3pm-vpittamp-nixos-config-ma-30c6d27c",
        "terminal_launch": {
            "mode": "managed_project_terminal",
            "helper_args": [],
        },
    }
    server_ssh._prepare_launch = AsyncMock(return_value=spec)
    server_ssh._get_reusable_context_terminal_window = AsyncMock(return_value=None)
    server_ssh._register_launch_for_spec = AsyncMock(return_value={"launch_id": "launch-1"})
    server_ssh._execute_launch_spec = MagicMock(return_value={"success": True, "launch_id": "launch-1"})

    result = await server_ssh._launch_open({"app_name": "terminal"})

    server_ssh._register_launch_for_spec.assert_awaited_once()
    server_ssh._execute_launch_spec.assert_called_once_with(spec)
    assert result["success"] is True
    assert result["launch"]["success"] is True
    assert result["spec"]["launch_strategy"] is None
