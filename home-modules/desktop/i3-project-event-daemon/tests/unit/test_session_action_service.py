"""Unit tests for tmux-backed session action helpers."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace


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


session_action_service_module = importlib.import_module("i3_project_daemon.services.session_action_service")

SessionActionService = session_action_service_module.SessionActionService


def make_service(*, current_host: bool = True, run_command=None):
    calls = []

    def parse_remote_target(remote_target: str, connection_key: str):
        target = remote_target or connection_key
        if target == "missing":
            return "", "", 22
        if "@" in target:
            user, host_port = target.split("@", 1)
        else:
            user, host_port = "", target
        if ":" in host_port:
            host, port = host_port.rsplit(":", 1)
            return user, host, int(port)
        return user, host_port, 22

    def default_run_command(args, **_kwargs):
        calls.append(args)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    service = SessionActionService(
        parse_remote_target=parse_remote_target,
        connection_target_is_current_host=lambda _connection_key: current_host,
        run_command=run_command or default_run_command,
    )
    return service, calls


def test_select_tmux_target_uses_local_socket_for_current_host_ssh_context():
    service, calls = make_service(current_host=True)

    result = service.select_tmux_target(
        execution_mode="ssh",
        tmux_session="i3pm-test",
        tmux_window="1:codex-raw",
        tmux_pane="%3",
        remote_target="vpittamp@ryzen:22",
        connection_key="vpittamp@ryzen:22",
        tmux_socket="/tmp/tmux-1000/default",
    )

    assert result["success"] is True
    assert calls == [[
        "bash",
        "-lc",
        "tmux -S /tmp/tmux-1000/default select-window -t i3pm-test:1 >/dev/null 2>&1 && tmux -S /tmp/tmux-1000/default select-pane -t %3 >/dev/null 2>&1",
    ]]


def test_select_tmux_target_routes_non_current_host_over_ssh():
    service, calls = make_service(current_host=False)

    result = service.select_tmux_target(
        execution_mode="ssh",
        tmux_session="i3pm-test",
        tmux_window="1:codex-raw",
        tmux_pane="%3",
        remote_target="vpittamp@ryzen:2222",
        connection_key="vpittamp@ryzen:2222",
    )

    assert result["success"] is True
    assert calls[0][:7] == [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=2",
        "-p",
        "2222",
    ]
    assert calls[0][7] == "vpittamp@ryzen"
    assert "tmux select-window -t i3pm-test:1" in calls[0][8]


def test_verify_tmux_target_reports_mismatch():
    def run_command(args, **_kwargs):
        return SimpleNamespace(returncode=0, stdout="%4\n", stderr="")

    service, _calls = make_service(run_command=run_command)

    result = service.verify_tmux_target(
        execution_mode="local",
        tmux_session="i3pm-test",
        tmux_window="1:codex-raw",
        tmux_pane="%3",
    )

    assert result["success"] is False
    assert result["reason"] == "tmux_target_mismatch"
    assert result["active_tmux_pane"] == "%4"


def test_kill_tmux_pane_rejects_missing_remote_target():
    service, calls = make_service(current_host=False)

    result = service.kill_tmux_pane(
        execution_mode="ssh",
        tmux_pane="%3",
        remote_target="missing",
        connection_key="missing",
    )

    assert result == {
        "success": False,
        "reason": "missing_remote_target",
        "stderr": "",
    }
    assert calls == []
