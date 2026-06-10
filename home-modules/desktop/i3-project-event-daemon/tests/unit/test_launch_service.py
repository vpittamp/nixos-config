"""Unit tests for launch persistence service."""

from __future__ import annotations

import importlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


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


def make_service(
    tmp_path: Path,
    *,
    transport: str = "local_helper",
    run_commands: Optional[List[List[str]]] = None,
    helper_path: Path = Path("/tmp/project-remote-launch.py"),
) -> LaunchService:
    def fake_run(
        cmd: List[str],
        capture_output: bool,
        text: bool,
        check: bool,
    ) -> subprocess.CompletedProcess[str]:
        if run_commands is not None:
            run_commands.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, "", "")

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


def test_build_remote_helper_script_for_remote_attach_without_remote_dir(tmp_path: Path) -> None:
    service = make_service(tmp_path, transport="remote_helper")
    helper_path = service.build_remote_terminal_helper_script({
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "environment": {
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
            "I3PM_CONTEXT_KEY": "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22",
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
    })
    try:
        content = helper_path.read_text()
    finally:
        helper_path.unlink(missing_ok=True)

    assert "ssh -tt -o BatchMode=yes -o ConnectTimeout=2 -p 22 vpittamp@ryzen" in content
    assert "tmux -S /run/user/1000/tmux-1000/default has-session -t i3pm-vpittamp-nixos-config-ma-6e1abb85" in content
    assert "attach-session -t i3pm-vpittamp-nixos-config-ma-6e1abb85" in content
    assert "cd " not in content


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
