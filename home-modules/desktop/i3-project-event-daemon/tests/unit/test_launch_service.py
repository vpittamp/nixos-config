"""Unit tests for launch persistence service."""

from __future__ import annotations

import importlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Dict, List, Optional
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


launch_service_module = importlib.import_module("i3_project_daemon.services.launch_service")

LaunchService = launch_service_module.LaunchService


def load_json_file(path: Path) -> Dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        return payload if isinstance(payload, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def parse_context_target_host(value: Any) -> str:
    text = str(value or "").strip()
    if "::host::" in text:
        return text.rsplit("::host::", 1)[1]
    if "::ssh::" in text:
        return text.rsplit("::ssh::", 1)[1]
    if "::local::" in text:
        return text.rsplit("::local::", 1)[1].removeprefix("local@")
    return ""


class DummyLaunchRegistry:
    def __init__(self) -> None:
        self._launches: Dict[str, Any] = {}

    def get_stats(self) -> SimpleNamespace:
        return SimpleNamespace(total_pending=len(self._launches))

    async def add(self, launch: Any) -> str:
        launch_id = f"launch-{len(self._launches) + 1}"
        self._launches[launch_id] = launch
        return launch_id

    async def get_by_terminal_anchor(self, terminal_anchor_id: str) -> Any:
        for launch in self._launches.values():
            if str(getattr(launch, "terminal_anchor_id", "") or "").strip() == str(terminal_anchor_id or "").strip():
                return launch
        return None

    async def get_pending_launches(self, *, include_matched: bool = False) -> List[Dict[str, Any]]:
        launches = []
        for launch_id, launch in self._launches.items():
            if bool(getattr(launch, "matched", False)) and not include_matched:
                continue
            launches.append({
                "launch_id": launch_id,
                "app_name": getattr(launch, "app_name", ""),
                "project_name": getattr(launch, "project_name", ""),
                "matched": bool(getattr(launch, "matched", False)),
            })
        return launches


def make_service(
    tmp_path: Path,
    *,
    transport: str = "local_helper",
    run_commands: Optional[List[List[str]]] = None,
    helper_path: Path = Path("/tmp/project-remote-launch.py"),
    which_map: Optional[Dict[str, str]] = None,
    reconcile_calls: Optional[List[Dict[str, Any]]] = None,
    launch_registry: Optional[DummyLaunchRegistry] = None,
    require_registry_app: Optional[Any] = None,
) -> LaunchService:
    def fake_run(
        cmd: List[str],
        *args: Any,
        **kwargs: Any,
    ) -> subprocess.CompletedProcess[str]:
        if run_commands is not None:
            run_commands.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, "", "")

    def fake_reconcile(*args: Any, **kwargs: Any) -> None:
        if reconcile_calls is not None:
            reconcile_calls.append({"args": args, "kwargs": kwargs})

    return LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda value: "local_process" if str(value or "") == "thinkpad" else "ssh",
        local_host_alias=lambda: "thinkpad",
        resolve_terminal_launch_transport=lambda **_kwargs: transport,
        tmux_command_prefix=lambda tmux_socket="": f"tmux -S {tmux_socket}" if tmux_socket else "tmux",
        canonical_tmux_socket=lambda: "/run/user/1000/tmux-1000/default",
        resolve_terminal_helper=lambda _name: helper_path,
        run_command=fake_run,
        repo_root=lambda: PACKAGE_ROOT,
        which=lambda command: (which_map or {}).get(command),
        schedule_launch_reconcile=fake_reconcile,
        launch_registry=(lambda: launch_registry) if launch_registry is not None else None,
        require_registry_app=require_registry_app,
    )


def test_write_status_persists_normalized_launch_payload(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.write_status(
        launch_id="launch-1",
        status="running",
        spec={
            "project_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::host::ryzen",
            "connection_key": "vpittamp@ryzen:22",
            "terminal_anchor_id": "anchor-1",
            "launch_kind": "open_project_terminal",
        },
        reason="window_bound",
        extra={"window_id": 12},
    )

    assert result["launch_id"] == "launch-1"
    assert result["status"] == "running"
    assert result["target_host"] == "ryzen"
    assert result["transport_kind"] == "ssh"
    assert result["window_id"] == 12
    assert service.read_status("launch-1")["reason"] == "window_bound"


def test_list_statuses_returns_newest_first_and_honors_limit(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    service.write_status(launch_id="launch-a", status="queued")
    service.write_status(launch_id="launch-b", status="running")

    statuses = service.list_statuses(limit=1)

    assert len(statuses) == 1
    assert statuses[0]["launch_id"] == "launch-b"


def test_write_local_spec_persists_spec_and_initial_status(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    spec_path = service.write_local_spec(
        spec={
            "launch": {"launch_id": "launch-local"},
            "project_name": "vpittamp/nixos-config:main",
            "target_host": "thinkpad",
            "transport_kind": "local_process",
            "connection_key": "local@thinkpad",
            "project_directory": "/repo",
            "local_project_directory": "/repo",
            "terminal_anchor_id": "anchor-local",
            "tmux_session_name": "i3pm-main",
            "terminal_role": "project-main",
            "terminal_launch": {"mode": "managed_project_terminal"},
            "environment": {"I3PM_CONTEXT_KEY": "ctx"},
            "launch_transport": "local_helper",
        },
        launch_kind="open_project_terminal",
    )

    payload = load_json_file(spec_path)
    status = service.read_status("launch-local")

    assert payload["launch_id"] == "launch-local"
    assert payload["terminal_role"] == "project-main"
    assert payload["status_file"] == str(service.status_file("launch-local"))
    assert status["status"] == "queued"
    assert status["reason"] == "queued"
    assert status["target_host"] == "thinkpad"


def test_launch_identity_and_tmux_session_name_are_stable(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    identity = service.build_launch_identity(
        app_name="terminal",
        project_name="repo/main",
        launcher_pid=123,
        app_id_override="anchor-explicit",
    )
    session_name_a = service.build_context_tmux_session_name(
        project_name="PittampalliOrg/nixos-config:main",
        context_key="ctx-main",
        terminal_role="project-main",
    )
    session_name_b = service.build_context_tmux_session_name(
        project_name="PittampalliOrg/nixos-config:main",
        context_key="ctx-main",
        terminal_role="project-main",
    )

    assert identity == {
        "app_instance_id": "anchor-explicit",
        "terminal_anchor_id": "anchor-explicit",
    }
    assert session_name_a == session_name_b
    assert session_name_a.startswith("i3pm-pittampalliorg-nixos-c")


def test_build_launch_open_response_shapes_reuse_contract(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.build_launch_open_response(
        spec={
            "app_name": "code",
            "target_host": "thinkpad",
            "transport_kind": "local_process",
            "project_name": "vpittamp/nixos-config:main",
            "context_key": "ctx",
            "terminal_anchor_id": "code-anchor",
            "preferred_workspace": 2,
            "tmux_session_name": "",
            "terminal_role": "",
        },
        launch_result={"success": True},
        launch_strategy="focus_existing_window",
        reused_existing=True,
        window_id=456,
        include_spec_window_id=True,
    )

    assert result["success"] is True
    assert result["launch"] == {
        "success": True,
        "reused_existing": True,
        "window_id": 456,
    }
    assert result["spec"]["launch_strategy"] == "focus_existing_window"
    assert result["spec"]["reused_existing"] is True
    assert result["spec"]["window_id"] == 456


@pytest.mark.asyncio
async def test_open_launch_reuses_existing_single_instance_app_window(tmp_path: Path) -> None:
    app = SimpleNamespace(name="code", multi_instance=False, terminal=False, command="code")
    service = make_service(tmp_path, require_registry_app=lambda _app_name: app)
    existing_window = SimpleNamespace(window_id=456)
    spec = {
        "app_name": "code",
        "project_name": "vpittamp/nixos-config:main",
        "context_key": "ctx",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "terminal_anchor_id": "code-anchor",
        "terminal_launch": {},
    }
    service.get_reusable_context_app_window = AsyncMock(return_value=existing_window)
    service.register_launch_for_spec = AsyncMock()
    service.execute_launch_spec = MagicMock()
    focus_window = AsyncMock(return_value={"success": True, "window_id": 456})
    focus_window_fast = AsyncMock(return_value={"success": True, "window_id": 999})
    clear_focus_overrides = MagicMock()

    result = await service.open_launch(
        payload={"app_name": "code"},
        prepare_launch=AsyncMock(return_value=spec),
        focus_window=focus_window,
        focus_window_fast=focus_window_fast,
        clear_focus_overrides=clear_focus_overrides,
    )

    service.get_reusable_context_app_window.assert_awaited_once()
    service.register_launch_for_spec.assert_not_awaited()
    service.execute_launch_spec.assert_not_called()
    focus_window.assert_awaited_once_with({
        "window_id": 456,
        "project_name": "vpittamp/nixos-config:main",
        "target_variant": "local",
        "connection_key": "local@thinkpad",
    })
    focus_window_fast.assert_not_awaited()
    clear_focus_overrides.assert_not_called()
    assert result["launch"]["reused_existing"] is True
    assert result["launch"]["window_id"] == 456
    assert result["spec"]["launch_strategy"] == "focus_existing_window"


@pytest.mark.asyncio
async def test_open_launch_registers_and_executes_when_no_reusable_window(tmp_path: Path) -> None:
    app = SimpleNamespace(name="terminal", multi_instance=True, terminal=True, command="alacritty")
    service = make_service(tmp_path, require_registry_app=lambda _app_name: app)
    spec = {
        "app_name": "terminal",
        "project_name": "vpittamp/nixos-config:main",
        "context_key": "ctx",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "terminal_anchor_id": "terminal-anchor",
        "terminal_launch": {"mode": "managed_project_terminal"},
        "terminal_role": "project-main",
        "tmux_session_name": "i3pm-main",
    }
    service.get_reusable_context_terminal_window = AsyncMock(return_value=None)
    service.register_launch_for_spec = AsyncMock(return_value={"launch_id": "launch-1"})
    service.execute_launch_spec = MagicMock(return_value={"success": True, "launch_id": "launch-1"})

    result = await service.open_launch(
        payload={"app_name": "terminal"},
        prepare_launch=AsyncMock(return_value=spec),
        focus_window=AsyncMock(),
        focus_window_fast=AsyncMock(),
        clear_focus_overrides=MagicMock(),
    )

    service.get_reusable_context_terminal_window.assert_awaited_once()
    service.register_launch_for_spec.assert_awaited_once_with(spec)
    service.execute_launch_spec.assert_called_once_with(spec)
    assert spec["launch"] == {"launch_id": "launch-1"}
    assert result["launch"] == {"success": True, "launch_id": "launch-1"}
    assert result["spec"]["window_id"] == 0


def test_build_terminal_launch_config_shapes_managed_remote_command(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.build_terminal_launch_config(
        app=SimpleNamespace(name="lazygit", terminal=True),
        scoped_launch=True,
        project_name="vpittamp/nixos-config:main",
        context_key="ctx",
        connection_key="vpittamp@ryzen:22",
        launch_transport="remote_helper",
        remote_profile={
            "host": "ryzen",
            "user": "vpittamp",
            "port": 22,
            "remote_dir": "/home/vpittamp/repos/vpittamp/nixos-config/main",
        },
        scoped_terminal_mode="reuse_project_terminal",
        scoped_terminal_command=["lazygit"],
        tmux_session_name="",
        terminal_role="project-main",
        remote_session_name_override="",
    )

    assert result["launch_strategy"] == "managed_remote_terminal_command"
    assert str(result["tmux_session_name"]).startswith("i3pm-vpittamp-nixos-config-ma-")
    assert result["terminal_launch"]["mode"] == "managed_project_terminal"
    assert result["terminal_launch"]["helper_args"] == ["lazygit"]
    assert result["terminal_launch"]["remote"]["host"] == "ryzen"


def test_build_terminal_launch_config_shapes_dedicated_scoped_window(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.build_terminal_launch_config(
        app=SimpleNamespace(name="yazi", terminal=True),
        scoped_launch=True,
        project_name="vpittamp/nixos-config:main",
        context_key="ctx",
        connection_key="local@thinkpad",
        launch_transport="local_helper",
        remote_profile=None,
        scoped_terminal_mode="dedicated_scoped_window",
        scoped_terminal_command=["yazi", "/repo"],
        tmux_session_name="",
        terminal_role="project-app:yazi",
        remote_session_name_override="",
    )

    assert result["launch_strategy"] == "dedicated_local_scoped_window"
    assert result["tmux_session_name"] == ""
    assert result["terminal_launch"] == {
        "mode": "dedicated_scoped_window",
        "terminal_role": "project-app:yazi",
        "helper_name": "project-command-launch.sh",
        "helper_args": ["yazi", "/repo"],
    }


def test_build_terminal_identity_shapes_project_terminal(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.build_terminal_identity(
        app=SimpleNamespace(name="terminal", terminal=True),
        scoped_launch=True,
        project_name="vpittamp/nixos-config:main",
        context_key="ctx",
        scoped_terminal_mode="reuse_project_terminal",
        prepared_args=["-e", "bash"],
    )

    assert result["terminal_role"] == "project-main"
    assert str(result["tmux_session_name"]).startswith("i3pm-vpittamp-nixos-config-ma-")
    assert result["scoped_terminal_command"] == []


def test_build_terminal_identity_shapes_dedicated_scoped_app(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.build_terminal_identity(
        app=SimpleNamespace(name="yazi", terminal=True),
        scoped_launch=True,
        project_name="vpittamp/nixos-config:main",
        context_key="ctx",
        scoped_terminal_mode="dedicated_scoped_window",
        prepared_args=["-e", "yazi", "/repo"],
    )

    assert result == {
        "terminal_role": "project-app:yazi",
        "tmux_session_name": "",
        "scoped_terminal_command": ["yazi", "/repo"],
    }


def test_launch_parameter_substitution_and_scoped_command_validation(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    rendered = service.substitute_launch_parameter(
        "$PROJECT_DIR $SESSION_NAME $WORKSPACE",
        project_name="repo/main",
        project_dir="/repo/main",
        session_name="main",
        project_display_name="main",
        project_icon="",
        preferred_workspace=7,
    )

    assert rendered == "/repo/main main 7"
    assert service.extract_scoped_terminal_command(
        app_name="lazygit",
        prepared_args=["-e", "lazygit", "/repo/main"],
    ) == ["lazygit", "/repo/main"]
    with pytest.raises(RuntimeError, match="Unresolved launch parameter"):
        service.substitute_launch_parameter(
            "$PROJECT_UNKNOWN",
            project_name="repo/main",
            project_dir="/repo/main",
            session_name="main",
            project_display_name="main",
            project_icon="",
            preferred_workspace=7,
        )
    with pytest.raises(RuntimeError, match="must use Ghostty"):
        service.extract_scoped_terminal_command(
            app_name="lazygit",
            prepared_args=["--bad"],
        )


def test_build_prepared_args_renders_registry_parameters(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.build_prepared_args(
        parameters=[
            "-e",
            "bash",
            "-lc",
            "cd $PROJECT_DIR && echo $PROJECT_NAME $PROJECT_DISPLAY_NAME $SESSION_NAME $WORKSPACE",
        ],
        project_name="vpittamp/nixos-config:main",
        project_dir="/home/vpittamp/repos/vpittamp/nixos-config/main",
        session_name="nixos-config_main",
        project_display_name="main",
        project_icon="",
        preferred_workspace=7,
    )

    assert result == [
        "-e",
        "bash",
        "-lc",
        "cd /home/vpittamp/repos/vpittamp/nixos-config/main && echo vpittamp/nixos-config:main main nixos-config_main 7",
    ]


def test_build_launch_env_includes_remote_tmux_and_worktree_metadata(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    env = service.build_launch_env(
        app_name="terminal",
        scope="scoped",
        preferred_workspace=3,
        expected_class="com.mitchellh.ghostty",
        project_name="repo/main",
        project_dir="/srv/repo/main",
        local_project_dir="/repo/main",
        project_display_name="main",
        execution_mode="ssh",
        target_host="ryzen",
        transport_kind="ssh",
        connection_key="vpittamp@ryzen:22",
        context_key="repo/main::ssh::vpittamp@ryzen:22",
        remote_profile={
            "host": "ryzen",
            "user": "vpittamp",
            "port": 22,
            "remote_dir": "/srv/repo/main",
        },
        launcher_pid=123,
        launch_identity={
            "app_instance_id": "launch-1",
            "terminal_anchor_id": "anchor-1",
        },
        terminal_role="project-main",
        tmux_session_name="i3pm-main",
        restore_mark="mark-1",
        remote_session_name="remote-main",
        worktree_branch="main",
        worktree_account="PittampalliOrg",
        worktree_repo="nixos-config",
    )

    assert env["I3PM_APP_ID"] == "launch-1"
    assert env["I3PM_REMOTE_ENABLED"] == "true"
    assert env["I3PM_REMOTE_HOST"] == "ryzen"
    assert env["I3PM_REMOTE_DIR"] == "/srv/repo/main"
    assert env["I3PM_TMUX_SOCKET"] == "/run/user/1000/tmux-1000/default"
    assert env["I3PM_RESTORE_MARK"] == "mark-1"
    assert env["I3PM_IS_WORKTREE"] == "true"


def test_write_remote_spec_persists_remote_payload(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    spec_path = service.write_remote_spec(
        spec={
            "launch": {"launch_id": "launch-remote"},
            "project_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::host::ryzen",
            "transport_kind": "ssh",
            "connection_key": "vpittamp@ryzen:22",
            "project_directory": "/srv/repo",
            "local_project_directory": "/home/repo",
            "terminal_anchor_id": "anchor-remote",
            "tmux_session_name": "i3pm-remote",
            "terminal_launch": {"mode": "managed_project_terminal"},
            "environment": {"I3PM_CONTEXT_KEY": "ctx"},
            "launch_transport": "remote_helper",
        },
        launch_kind="open_project_terminal",
    )

    payload = load_json_file(spec_path)
    status = service.read_status("launch-remote")

    assert payload["target_host"] == "ryzen"
    assert payload["launch_transport"] == "remote_helper"
    assert payload["status_file"] == str(service.status_file("launch-remote"))
    assert status["connection_key"] == "vpittamp@ryzen:22"
    assert status["launch_kind"] == "open_project_terminal"


@pytest.mark.asyncio
async def test_register_pending_launch_skips_without_workspace(tmp_path: Path) -> None:
    registry = DummyLaunchRegistry()
    service = make_service(tmp_path, launch_registry=registry)
    app = SimpleNamespace(
        name="terminal",
        expected_class="com.mitchellh.ghostty",
        pwa_match_domains=[],
    )

    result = await service.register_pending_launch(
        app=app,
        project_name="repo/main",
        project_directory="/repo/main",
        launcher_pid=123,
        terminal_anchor_id="anchor-skip",
        preferred_workspace=None,
    )

    assert result["status"] == "skipped"
    assert result["launch_id"] == ""
    assert result["pending_count"] == 0


@pytest.mark.asyncio
async def test_register_launch_for_spec_persists_local_spec(tmp_path: Path) -> None:
    registry = DummyLaunchRegistry()
    app = SimpleNamespace(
        name="terminal",
        expected_class="com.mitchellh.ghostty",
        pwa_match_domains=["example.com"],
    )
    service = make_service(tmp_path, launch_registry=registry)
    spec = {
        "app_name": "terminal",
        "project_name": "repo/main",
        "target_host": "thinkpad",
        "transport_kind": "local_process",
        "connection_key": "local@thinkpad",
        "context_key": "repo/main::local::local@thinkpad",
        "project_directory": "/repo/main",
        "local_project_directory": "/repo/main",
        "preferred_workspace": 1,
        "terminal_anchor_id": "anchor-local",
        "tmux_session_name": "i3pm-main",
        "terminal_role": "project-main",
        "terminal_launch": {"mode": "managed_project_terminal"},
        "environment": {"I3PM_LAUNCHER_PID": "123"},
        "launch_transport": "local_helper",
    }

    result = await service.register_launch_for_spec(spec, app=app)

    assert result["status"] == "success"
    assert result["launch_id"] == "launch-1"
    assert spec["launch"] == {"launch_id": "launch-1"}
    assert load_json_file(service.spec_file("launch-1"))["launch_transport"] == "local_helper"
    assert service.read_status("launch-1")["status"] == "queued"


@pytest.mark.asyncio
async def test_register_launch_for_spec_persists_remote_spec(tmp_path: Path) -> None:
    registry = DummyLaunchRegistry()
    app = SimpleNamespace(
        name="terminal",
        expected_class="com.mitchellh.ghostty",
        pwa_match_domains=[],
    )
    service = make_service(tmp_path, launch_registry=registry)
    spec = {
        "app_name": "terminal",
        "project_name": "repo/main",
        "target_host": "ryzen",
        "transport_kind": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "repo/main::ssh::vpittamp@ryzen:22",
        "project_directory": "/srv/repo/main",
        "local_project_directory": "/repo/main",
        "preferred_workspace": 1,
        "terminal_anchor_id": "anchor-remote",
        "tmux_session_name": "i3pm-main",
        "terminal_launch": {"mode": "managed_project_terminal"},
        "environment": {"I3PM_LAUNCHER_PID": "123"},
        "launch_transport": "remote_helper",
    }

    result = await service.register_launch_for_spec(spec, app=app)

    assert result["launch_id"] == "launch-1"
    payload = load_json_file(service.spec_file("launch-1"))
    assert payload["launch_transport"] == "remote_helper"
    assert payload["target_host"] == "ryzen"
    assert service.read_status("launch-1")["transport_kind"] == "ssh"


def test_find_context_terminal_window_matches_role_and_prefers_visible_workspace(tmp_path: Path) -> None:
    hidden = SimpleNamespace(
        window_id=10,
        project="repo/main",
        context_key="repo/main::local::local@thinkpad",
        execution_mode="local",
        terminal_role="project-main",
        app_identifier="terminal",
        tmux_session_name="i3pm-main",
        workspace="",
    )
    visible = SimpleNamespace(
        window_id=11,
        project="repo/main",
        context_key="repo/main::local::local@thinkpad",
        execution_mode="local",
        terminal_role="project-main",
        app_identifier="terminal",
        tmux_session_name="i3pm-main",
        workspace="1",
    )
    other_role = SimpleNamespace(
        window_id=12,
        project="repo/main",
        context_key="repo/main::local::local@thinkpad",
        execution_mode="local",
        terminal_role="project-app:lazygit",
        app_identifier="lazygit",
        tmux_session_name="i3pm-main",
        workspace="1",
    )
    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        window_map_items=lambda: [(10, hidden), (11, visible), (12, other_role)],
    )

    result = service.find_context_terminal_window(
        project_name="repo/main",
        context_key="repo/main::local::local@thinkpad",
        execution_mode="local",
        app_name="terminal",
        terminal_role="project-main",
    )

    assert result is visible


def test_find_context_app_window_candidates_filters_scope_mode_and_class(tmp_path: Path) -> None:
    older = SimpleNamespace(
        window_id=20,
        execution_mode="local",
        project="repo/main",
        window_class="code",
        window_instance="code",
        created=10,
    )
    newer_wrong_project = SimpleNamespace(
        window_id=21,
        execution_mode="local",
        project="repo/other",
        window_class="code",
        window_instance="code",
        created=30,
    )
    newer = SimpleNamespace(
        window_id=22,
        execution_mode="local",
        project="repo/main",
        window_class="code",
        window_instance="code",
        created=20,
    )
    wrong_mode = SimpleNamespace(
        window_id=23,
        execution_mode="ssh",
        project="repo/main",
        window_class="code",
        window_instance="code",
        created=40,
    )
    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        window_map_items=lambda: [
            (20, older),
            (21, newer_wrong_project),
            (22, newer),
            (23, wrong_mode),
        ],
    )
    app = SimpleNamespace(
        name="code",
        scope="scoped",
        terminal=False,
        expected_class="code",
        pwa_match_domains=[],
    )

    result = service.find_context_app_window_candidates(
        app=app,
        project_name="repo/main",
        execution_mode="local",
    )

    assert result == [newer, older]


def test_find_context_app_window_candidates_allows_global_app_any_project(tmp_path: Path) -> None:
    global_window = SimpleNamespace(
        window_id=24,
        execution_mode="local",
        project="repo/other",
        window_class="headlamp",
        window_instance="headlamp",
        created=10,
    )
    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        window_map_items=lambda: [(24, global_window)],
    )
    app = SimpleNamespace(
        name="headlamp",
        scope="global",
        terminal=False,
        expected_class="headlamp",
        pwa_match_domains=[],
    )

    result = service.find_context_app_window_candidates(
        app=app,
        project_name="repo/main",
        execution_mode="local",
    )

    assert result == [global_window]


@pytest.mark.asyncio
async def test_get_reusable_context_terminal_window_prunes_stale_candidate(tmp_path: Path) -> None:
    stale = SimpleNamespace(
        window_id=31,
        project="repo/main",
        context_key="repo/main::local::local@thinkpad",
        execution_mode="local",
        terminal_role="project-main",
        app_identifier="terminal",
        tmux_session_name="i3pm-main",
        workspace="1",
    )
    removed: List[int] = []
    invalidated: List[bool] = []

    async def fake_live_window(_window_id: int) -> Optional[Any]:
        return None

    async def fake_remove_window(window_id: int) -> None:
        removed.append(window_id)

    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        window_map_items=lambda: [(31, stale)],
        find_live_window=fake_live_window,
        remove_window=fake_remove_window,
        invalidate_window_tree_cache=lambda: invalidated.append(True),
    )

    result = await service.get_reusable_context_terminal_window(
        project_name="repo/main",
        context_key="repo/main::local::local@thinkpad",
        execution_mode="local",
        app_name="terminal",
        terminal_role="project-main",
    )

    assert result is None
    assert removed == [31]
    assert invalidated == [True]


@pytest.mark.asyncio
async def test_get_reusable_context_app_window_returns_first_live_candidate(tmp_path: Path) -> None:
    stale = SimpleNamespace(
        window_id=41,
        execution_mode="local",
        project="repo/main",
        window_class="code",
        window_instance="code",
        created=20,
    )
    live = SimpleNamespace(
        window_id=42,
        execution_mode="local",
        project="repo/main",
        window_class="code",
        window_instance="code",
        created=10,
    )
    removed: List[int] = []

    async def fake_live_window(window_id: int) -> Optional[Any]:
        return SimpleNamespace(id=window_id) if window_id == 42 else None

    async def fake_remove_window(window_id: int) -> None:
        removed.append(window_id)

    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        window_map_items=lambda: [(41, stale), (42, live)],
        find_live_window=fake_live_window,
        remove_window=fake_remove_window,
    )
    app = SimpleNamespace(
        name="code",
        scope="scoped",
        terminal=False,
        expected_class="code",
        pwa_match_domains=[],
    )

    result = await service.get_reusable_context_app_window(
        app=app,
        project_name="repo/main",
        execution_mode="local",
    )

    assert result is live
    assert removed == []


@pytest.mark.asyncio
async def test_launch_stats_and_pending_launches_use_registry_boundary(tmp_path: Path) -> None:
    registry = DummyLaunchRegistry()
    service = make_service(tmp_path, launch_registry=registry)
    app = SimpleNamespace(
        name="terminal",
        expected_class="com.mitchellh.ghostty",
        pwa_match_domains=[],
    )
    await service.register_pending_launch(
        app=app,
        project_name="repo/main",
        project_directory="/repo/main",
        launcher_pid=123,
        terminal_anchor_id="anchor-main",
        preferred_workspace=1,
    )

    stats = service.launch_stats()
    pending = await service.pending_launches()

    assert stats["total_pending"] == 1
    assert stats["total_matched"] == 0
    assert pending == {
        "launches": [{
            "launch_id": "launch-1",
            "app_name": "terminal",
            "project_name": "repo/main",
            "matched": False,
        }]
    }


def test_build_remote_helper_script_rejects_retired_remote_attach_specs(tmp_path: Path) -> None:
    service = make_service(tmp_path, transport="remote_helper")
    spec = {
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "environment": {},
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

    with pytest.raises(RuntimeError, match="Remote AI tmux attach specs are retired"):
        service.build_remote_terminal_helper_script(spec)


def test_managed_tmux_command_shell_uses_canonical_socket(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    script = service.managed_tmux_command_shell(
        session_name="i3pm-vpittamp-nixos-config-main",
        tmux_socket="",
        working_dir="/repo/main",
        command_args=["yazi", "/repo/main"],
        environment={
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
            "PATH": "/bin",
        },
    )

    assert "tmux -S /run/user/1000/tmux-1000/default has-session -t i3pm-vpittamp-nixos-config-main" in script
    assert "set-environment -t i3pm-vpittamp-nixos-config-main I3PM_PROJECT_NAME vpittamp/nixos-config:main" in script
    assert "PATH" not in script
    assert "new-window -t i3pm-vpittamp-nixos-config-main" in script


def test_dispatch_managed_terminal_command_local_uses_tmux_dispatch(tmp_path: Path) -> None:
    commands: List[List[str]] = []
    service = make_service(tmp_path, transport="local_helper", run_commands=commands)

    result = service.dispatch_managed_terminal_command({
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "local_project_directory": "/repo/main",
        "project_directory": "/srv/repo/main",
        "launch_transport": "local_helper",
        "environment": {
            "I3PM_TMUX_SOCKET": "/run/user/1000/tmux-1000/default",
            "I3PM_CONTEXT_KEY": "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
        },
        "terminal_launch": {
            "mode": "managed_project_terminal",
            "tmux_session_name": "i3pm-vpittamp-nixos-config-main",
            "helper_args": ["yazi", "/repo/main"],
        },
    })

    assert result == {"success": True, "reason": "ok"}
    assert commands[0][:2] == ["bash", "-lc"]
    assert "tmux -S /run/user/1000/tmux-1000/default" in commands[0][2]
    assert "ssh -o" not in commands[0][2]


def test_execute_launch_spec_local_managed_terminal_updates_status_and_reconciles(tmp_path: Path) -> None:
    commands: List[List[str]] = []
    reconcile_calls: List[Dict[str, Any]] = []
    service = make_service(
        tmp_path,
        transport="local_helper",
        run_commands=commands,
        helper_path=Path("/tmp/project-terminal-launch.sh"),
        which_map={"ghostty": "/usr/bin/ghostty"},
        reconcile_calls=reconcile_calls,
    )

    result = service.execute_launch_spec({
        "app_name": "terminal",
        "command": "ghostty",
        "args": ["-e", "bash"],
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "local_project_directory": "/repo/main",
        "environment": {"I3PM_CONTEXT_KEY": "ctx"},
        "launch": {"launch_id": "launch-managed"},
        "terminal_launch": {
            "mode": "managed_project_terminal",
            "helper_name": "project-terminal-launch.sh",
            "helper_args": ["codex"],
        },
    })

    assert result["success"] is True
    assert result["launch_id"] == "launch-managed"
    assert commands[0][0] == "systemd-run"
    assert "--property=KillMode=process" in commands[0]
    assert commands[0][-3:] == ["bash", "-lc", "exec ghostty -e /tmp/project-terminal-launch.sh /repo/main codex"]
    assert service.read_status("launch-managed")["status"] == "session_validating"
    assert reconcile_calls == [{
        "args": ("launch-managed",),
        "kwargs": {"anchor_bound": None, "attempts": 30, "delay_s": 0.2},
    }]


def test_execute_launch_spec_local_pwa_uses_sway_exec(tmp_path: Path) -> None:
    commands: List[List[str]] = []
    service = make_service(
        tmp_path,
        transport="local_helper",
        run_commands=commands,
        which_map={"launch-pwa-by-name": "/usr/bin/launch-pwa-by-name"},
    )

    result = service.execute_launch_spec({
        "app_name": "gmail-pwa",
        "command": "launch-pwa-by-name",
        "args": ["01JCYF9K4Q9V6X8YJ1MNSPT0D7"],
        "execution_mode": "local",
        "local_project_directory": "",
        "environment": {"I3PM_CONTEXT_KEY": "ctx"},
        "launch": {"launch_id": "launch-pwa"},
    })

    assert result["success"] is True
    assert result["pid"] == 0
    assert commands[0][:2] == ["swaymsg", "--quiet"]
    assert "exec env I3PM_CONTEXT_KEY=ctx /usr/bin/launch-pwa-by-name 01JCYF9K4Q9V6X8YJ1MNSPT0D7" in commands[0][2]
    assert service.read_status("launch-pwa")["status"] == "waiting_window"


def test_managed_tmux_session_probe_accepts_matching_metadata(tmp_path: Path) -> None:
    def fake_run(cmd: List[str], *args: Any, **kwargs: Any) -> subprocess.CompletedProcess[str]:
        if cmd[-3:] == ["has-session", "-t", "i3pm-main"]:
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[-1] == "@i3pm_managed":
            return subprocess.CompletedProcess(cmd, 0, "1\n", "")
        if cmd[-1] == "@i3pm_context_key":
            return subprocess.CompletedProcess(cmd, 0, "repo/main::local::local@thinkpad\n", "")
        if cmd[-1] == "@i3pm_terminal_role":
            return subprocess.CompletedProcess(cmd, 0, "project-main\n", "")
        if cmd[-1] == "@i3pm_tmux_server_key":
            return subprocess.CompletedProcess(cmd, 0, "/run/user/1000/tmux-1000/default\n", "")
        if cmd[-1] == "@i3pm_schema_version":
            return subprocess.CompletedProcess(cmd, 0, "1\n", "")
        return subprocess.CompletedProcess(cmd, 1, "", "unexpected command")

    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        canonical_tmux_socket=lambda: "/run/user/1000/tmux-1000/default",
        run_command=fake_run,
    )

    result = service.managed_tmux_session_probe({
        "tmux_session_name": "i3pm-main",
        "context_key": "repo/main::local::local@thinkpad",
        "terminal_role": "project-main",
        "environment": {
            "I3PM_TMUX_SOCKET": "/run/user/1000/tmux-1000/default",
        },
    })

    assert result["exists"] is True
    assert result["healthy"] is True
    assert result["reason"] == "healthy"
    assert result["metadata"]["terminal_role"] == "project-main"


@pytest.mark.asyncio
async def test_reconcile_launch_runtime_status_marks_bound_window_running(tmp_path: Path) -> None:
    def fake_run(cmd: List[str], *args: Any, **kwargs: Any) -> subprocess.CompletedProcess[str]:
        if cmd[-3:] == ["has-session", "-t", "i3pm-main"]:
            return subprocess.CompletedProcess(cmd, 0, "", "")
        option_values = {
            "@i3pm_managed": "1",
            "@i3pm_context_key": "repo/main::local::local@thinkpad",
            "@i3pm_terminal_role": "project-main",
            "@i3pm_tmux_server_key": "/run/user/1000/tmux-1000/default",
            "@i3pm_schema_version": "1",
        }
        if cmd[-1] in option_values:
            return subprocess.CompletedProcess(cmd, 0, f"{option_values[cmd[-1]]}\n", "")
        return subprocess.CompletedProcess(cmd, 1, "", "unexpected command")

    async def fake_anchor(_params: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "matched": True,
            "window_id": 88,
        }

    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        canonical_tmux_socket=lambda: "/run/user/1000/tmux-1000/default",
        run_command=fake_run,
        get_terminal_anchor=fake_anchor,
    )
    service.write_local_spec(
        spec={
            "launch": {"launch_id": "launch-main"},
            "project_name": "repo/main",
            "target_host": "thinkpad",
            "transport_kind": "local_process",
            "connection_key": "local@thinkpad",
            "project_directory": "/repo/main",
            "local_project_directory": "/repo/main",
            "terminal_anchor_id": "anchor-main",
            "tmux_session_name": "i3pm-main",
            "terminal_role": "project-main",
            "context_key": "repo/main::local::local@thinkpad",
            "terminal_launch": {"mode": "managed_project_terminal"},
            "environment": {
                "I3PM_TMUX_SOCKET": "/run/user/1000/tmux-1000/default",
            },
            "launch_transport": "local_helper",
        },
        launch_kind="open_project_terminal",
    )

    result = await service.reconcile_launch_runtime_status("launch-main")

    assert result["status"] == "running"
    assert result["reason"] == "window_bound"
    assert result["anchor_bound"] is True
    assert result["tmux_session_healthy"] is True


@pytest.mark.asyncio
async def test_wait_for_launch_status_requires_anchor_when_requested(tmp_path: Path) -> None:
    anchor_calls = 0

    async def fake_anchor(_params: Dict[str, Any]) -> Dict[str, Any]:
        nonlocal anchor_calls
        anchor_calls += 1
        return {
            "matched": anchor_calls >= 2,
            "window_id": 42 if anchor_calls >= 2 else 0,
        }

    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        get_terminal_anchor=fake_anchor,
    )
    service.write_status(
        launch_id="launch-wait",
        status="running",
        reason="window_bound",
        spec={
            "terminal_anchor_id": "anchor-wait",
            "launch_kind": "open_project_terminal",
        },
    )

    result = await service.wait_for_launch_status(
        "launch-wait",
        terminal_anchor_id="anchor-wait",
        attempts=3,
        delay_s=0,
    )

    assert result["success"] is True
    assert result["reason"] == "ok"
    assert result["anchor_bound"] is True
    assert anchor_calls == 2


@pytest.mark.asyncio
async def test_terminal_anchor_resolves_window_map_binding(tmp_path: Path) -> None:
    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        window_map_items=lambda: [(
            101,
            SimpleNamespace(
                terminal_anchor_id="anchor-live",
                project="repo/main",
                app_identifier="terminal",
                workspace="1",
                terminal_role="project-main",
                tmux_session_name="i3pm-main",
            ),
        )],
    )

    result = await service.terminal_anchor("anchor-live")

    assert result["matched"] is True
    assert result["binding"] == "window_map"
    assert result["window_id"] == 101
    assert result["terminal_role"] == "project-main"


@pytest.mark.asyncio
async def test_terminal_anchor_resolves_pending_launch_binding(tmp_path: Path) -> None:
    async def fake_pending(_anchor: str) -> Any:
        return SimpleNamespace(
            launch_id="launch-pending",
            project_name="repo/main",
            app_name="terminal",
            workspace_number=2,
        )

    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        window_map_items=lambda: [],
        get_pending_launch_by_terminal_anchor=fake_pending,
    )

    result = await service.terminal_anchor("anchor-pending")

    assert result["matched"] is False
    assert result["binding"] == "pending"
    assert result["launch_id"] == "launch-pending"
    assert result["workspace"] == 2


@pytest.mark.asyncio
async def test_wait_for_terminal_window_returns_bound_anchor(tmp_path: Path) -> None:
    calls = 0

    async def fake_anchor(_params: Dict[str, Any]) -> Dict[str, Any]:
        nonlocal calls
        calls += 1
        return {
            "terminal_anchor_id": "anchor-window",
            "matched": calls >= 3,
            "window_id": 77 if calls >= 3 else 0,
        }

    service = LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda _value: "local_process",
        local_host_alias=lambda: "thinkpad",
        get_terminal_anchor=fake_anchor,
    )

    result = await service.wait_for_terminal_window(
        "anchor-window",
        attempts=4,
        delay_s=0,
    )

    assert result["matched"] is True
    assert result["window_id"] == 77
    assert calls == 3
