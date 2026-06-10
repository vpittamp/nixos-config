"""Unit tests for tmux-backed session action helpers."""

from __future__ import annotations

import importlib
import importlib.util
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


@pytest.mark.asyncio
async def test_close_session_kills_local_tmux_pane_and_notifies():
    service, _calls = make_service(current_host=True)
    service.kill_tmux_pane = MagicMock(return_value={"success": True, "reason": "ok", "stderr": ""})
    close_managed_window = AsyncMock()
    clear_focus = MagicMock()
    notify_state_change = AsyncMock()

    result = await service.close_session(
        session_key="session-local-pane",
        sessions=[{
            "session_key": "session-local-pane",
            "tmux_session": "i3pm-main",
            "tmux_window": "1",
            "tmux_pane": "%3",
            "connection_key": "local@thinkpad",
            "source_is_current_host": True,
        }],
        close_managed_window=close_managed_window,
        clear_focus_if_session_matches=clear_focus,
        notify_state_change=notify_state_change,
    )

    service.kill_tmux_pane.assert_called_once_with(
        execution_mode="local",
        tmux_pane="%3",
        remote_target="local@thinkpad",
        connection_key="local@thinkpad",
        tmux_socket="",
    )
    close_managed_window.assert_not_awaited()
    clear_focus.assert_called_once_with("session-local-pane")
    notify_state_change.assert_awaited_once_with("ai_session_close")
    assert result["success"] is True
    assert result["close_mode"] == "local_tmux_pane"
    assert result["killed_tmux_pane"] == "%3"


@pytest.mark.asyncio
async def test_close_session_uses_source_connection_for_remote_tmux_pane():
    service, _calls = make_service(current_host=False)
    service.kill_tmux_pane = MagicMock(return_value={"success": True, "reason": "ok", "stderr": ""})
    notify_state_change = AsyncMock()

    result = await service.close_session(
        session_key="session-remote-pane",
        sessions=[{
            "session_key": "session-remote-pane",
            "tmux_session": "i3pm-main",
            "tmux_window": "2",
            "tmux_pane": "%7",
            "source_connection_key": "vpittamp@ryzen:22",
            "source_is_current_host": False,
            "terminal_context": {"remote_target": "vpittamp@ryzen:22"},
        }],
        close_managed_window=AsyncMock(),
        clear_focus_if_session_matches=MagicMock(),
        notify_state_change=notify_state_change,
    )

    service.kill_tmux_pane.assert_called_once_with(
        execution_mode="ssh",
        tmux_pane="%7",
        remote_target="vpittamp@ryzen:22",
        connection_key="vpittamp@ryzen:22",
        tmux_socket="",
    )
    notify_state_change.assert_awaited_once_with("ai_session_close")
    assert result["success"] is True
    assert result["close_mode"] == "remote_tmux_pane"
    assert result["connection_key"] == "vpittamp@ryzen:22"


@pytest.mark.asyncio
async def test_close_session_falls_back_to_managed_window_when_tmux_identity_missing():
    service, _calls = make_service(current_host=True)
    close_managed_window = AsyncMock(return_value=True)
    clear_focus = MagicMock()
    notify_state_change = AsyncMock()

    result = await service.close_session(
        session_key="session-window-only",
        sessions=[{
            "session_key": "session-window-only",
            "window_id": 42,
            "focus_connection_key": "local@thinkpad",
        }],
        close_managed_window=close_managed_window,
        clear_focus_if_session_matches=clear_focus,
        notify_state_change=notify_state_change,
    )

    close_managed_window.assert_awaited_once_with(42)
    clear_focus.assert_called_once_with("session-window-only")
    notify_state_change.assert_awaited_once_with("ai_session_close")
    assert result == {
        "success": True,
        "session_key": "session-window-only",
        "reason": "ok",
        "close_mode": "local_window_fallback",
        "closed_window_id": 42,
        "killed_tmux_pane": "",
        "connection_key": "local@thinkpad",
    }
