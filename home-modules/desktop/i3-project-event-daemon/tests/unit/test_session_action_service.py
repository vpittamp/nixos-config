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
async def test_focus_local_session_attach_rebinds_managed_terminal_and_verifies_tmux():
    service, _calls = make_service()
    service.select_tmux_target = MagicMock(return_value={"success": True, "reason": "ok"})
    service.verify_tmux_target = MagicMock(return_value={
        "success": True,
        "reason": "ok",
        "active_tmux_pane": "%9",
        "tmux_pane": "%9",
    })
    launch_open = AsyncMock(return_value={
        "success": True,
        "launch": {
            "success": True,
            "launch_id": "launch-1",
        },
        "spec": {
            "terminal_anchor_id": "anchor-1",
        },
    })
    set_focus_overrides = MagicMock()

    result = await service.focus_local_session_attach(
        session_key="session-local-attach",
        session={
            "session_key": "session-local-attach",
            "canonical_project_name": "PittampalliOrg/workflow-builder:main",
            "focus_connection_key": "local@thinkpad",
            "connection_key": "local@thinkpad",
            "surface_key": "surface-local-attach",
            "conflict_state": "",
            "tmux_session": "i3pm-workflow-builder",
            "tmux_window": "0:main",
            "tmux_pane": "%9",
            "terminal_context": {
                "tmux_socket": "/tmp/tmux-local",
                "connection_key": "local@thinkpad",
            },
        },
        intent_epoch=3,
        user_intent_is_current=lambda epoch: epoch == 3,
        stale_intent_result=MagicMock(),
        launch_open=launch_open,
        wait_for_launch_status=AsyncMock(return_value={
            "success": True,
            "launch_id": "launch-1",
            "status": "running",
            "reason": "window_bound",
        }),
        wait_for_terminal_window=AsyncMock(return_value={
            "matched": True,
            "window_id": 144,
            "terminal_anchor_id": "anchor-1",
        }),
        window_focus=AsyncMock(return_value={"success": True}),
        focus_state=AsyncMock(return_value={
            "current_ai_session_key": "session-local-attach",
            "focused_window_id": 144,
        }),
        set_focus_overrides=set_focus_overrides,
    )

    launch_open.assert_awaited_once_with({
        "app_name": "terminal",
        "qualified_name": "PittampalliOrg/workflow-builder:main",
        "context_variant_override": "local",
        "__intent_epoch": 3,
    })
    service.select_tmux_target.assert_called_once()
    service.verify_tmux_target.assert_called_once()
    set_focus_overrides.assert_called_once_with(
        session_key="session-local-attach",
        window_id=144,
        connection_key="local@thinkpad",
    )
    assert result["success"] is True
    assert result["focus_mode"] == "local_tmux_attachable"
    assert result["window_id"] == 144
    assert result["verification"]["success"] is True


@pytest.mark.asyncio
async def test_focus_local_session_attach_returns_stale_result_before_launch():
    service, _calls = make_service()
    stale_intent_result = MagicMock(return_value={
        "success": False,
        "reason": "superseded_before_local_attach",
    })

    result = await service.focus_local_session_attach(
        session_key="session-local-attach",
        session={
            "session_key": "session-local-attach",
            "project_name": "PittampalliOrg/workflow-builder:main",
        },
        intent_epoch=1,
        user_intent_is_current=lambda _epoch: False,
        stale_intent_result=stale_intent_result,
        launch_open=AsyncMock(),
        wait_for_launch_status=AsyncMock(),
        wait_for_terminal_window=AsyncMock(),
        window_focus=AsyncMock(),
        focus_state=AsyncMock(),
        set_focus_overrides=MagicMock(),
    )

    stale_intent_result.assert_called_once_with(
        session_key="session-local-attach",
        project_name="PittampalliOrg/workflow-builder:main",
        reason="superseded_before_local_attach",
    )
    assert result == {
        "success": False,
        "reason": "superseded_before_local_attach",
    }


@pytest.mark.asyncio
async def test_focus_remote_session_attach_reuses_matching_bridge_and_sets_override():
    service, _calls = make_service()
    set_focus_overrides = MagicMock()
    prepare_spec = MagicMock(return_value={
        "project_name": "PittampalliOrg/workflow-builder:main",
        "connection_key": "vpittamp@ryzen:22",
        "context_key": "PittampalliOrg/workflow-builder:main::host::ryzen",
        "terminal_role": "remote-session:abc123",
        "execution_mode": "ssh",
    })
    get_reusable = AsyncMock(return_value=SimpleNamespace(
        window_id=20,
        terminal_role="remote-session:abc123",
        remote_surface_key="surface-remote-pane",
        remote_session_key="session-remote-pane",
    ))
    wait_for_launch_status = AsyncMock(side_effect=AssertionError("should not wait"))

    result = await service.focus_remote_session_attach(
        session_key="session-remote-pane",
        session={
            "session_key": "session-remote-pane",
            "surface_key": "surface-remote-pane",
            "host_name": "ryzen",
            "tmux_pane": "%11",
        },
        intent_epoch=3,
        user_intent_is_current=lambda epoch: epoch == 3,
        stale_intent_result=MagicMock(),
        resolve_remote_attach_profile=MagicMock(return_value={"remote_host": "ryzen"}),
        prepare_remote_session_attach_spec=prepare_spec,
        find_live_sway_window=AsyncMock(return_value=None),
        state_window_for_id=MagicMock(),
        get_reusable_context_terminal_window=get_reusable,
        remote_bridge_window_mismatch_reason=MagicMock(return_value=""),
        close_managed_window=AsyncMock(),
        remove_window=AsyncMock(),
        invalidate_window_tree_cache=MagicMock(),
        register_launch_for_spec=AsyncMock(),
        execute_launch_spec=MagicMock(),
        wait_for_terminal_window=AsyncMock(),
        wait_for_launch_status=wait_for_launch_status,
        window_focus=AsyncMock(return_value={"success": True}),
        focus_state=AsyncMock(return_value={
            "current_ai_session_key": "session-remote-pane",
            "focused_window_id": 20,
        }),
        set_focus_overrides=set_focus_overrides,
    )

    prepare_spec.assert_called_once()
    get_reusable.assert_awaited_once_with(
        project_name="PittampalliOrg/workflow-builder:main",
        context_key="PittampalliOrg/workflow-builder:main::host::ryzen",
        execution_mode="ssh",
        app_name="terminal",
        terminal_role="remote-session:abc123",
    )
    wait_for_launch_status.assert_not_awaited()
    set_focus_overrides.assert_called_once_with(
        session_key="session-remote-pane",
        window_id=20,
        connection_key="vpittamp@ryzen:22",
    )
    assert result["success"] is True
    assert result["focus_mode"] == "remote_bridge_bound"
    assert result["launch"]["reused_existing"] is True
    assert result["launch_status"]["status"] == "reused_existing"
    assert result["verification"]["verification_source"] == "remote_launcher"


@pytest.mark.asyncio
async def test_focus_remote_session_attach_returns_stale_result_before_launch():
    service, _calls = make_service()
    current_checks = [True, False]
    stale_intent_result = MagicMock(return_value={
        "success": False,
        "reason": "superseded_before_remote_launch",
    })
    register_launch = AsyncMock()

    result = await service.focus_remote_session_attach(
        session_key="session-remote-pane",
        session={
            "session_key": "session-remote-pane",
            "project_name": "PittampalliOrg/workflow-builder:main",
        },
        intent_epoch=4,
        user_intent_is_current=lambda _epoch: current_checks.pop(0),
        stale_intent_result=stale_intent_result,
        resolve_remote_attach_profile=MagicMock(return_value={"remote_host": "ryzen"}),
        prepare_remote_session_attach_spec=MagicMock(return_value={
            "project_name": "PittampalliOrg/workflow-builder:main",
            "connection_key": "vpittamp@ryzen:22",
            "context_key": "PittampalliOrg/workflow-builder:main::host::ryzen",
            "terminal_role": "remote-session:abc123",
            "execution_mode": "ssh",
        }),
        find_live_sway_window=AsyncMock(return_value=None),
        state_window_for_id=MagicMock(),
        get_reusable_context_terminal_window=AsyncMock(return_value=None),
        remote_bridge_window_mismatch_reason=MagicMock(),
        close_managed_window=AsyncMock(),
        remove_window=AsyncMock(),
        invalidate_window_tree_cache=MagicMock(),
        register_launch_for_spec=register_launch,
        execute_launch_spec=MagicMock(),
        wait_for_terminal_window=AsyncMock(),
        wait_for_launch_status=AsyncMock(),
        window_focus=AsyncMock(),
        focus_state=AsyncMock(),
        set_focus_overrides=MagicMock(),
    )

    stale_intent_result.assert_called_once_with(
        session_key="session-remote-pane",
        project_name="PittampalliOrg/workflow-builder:main",
        reason="superseded_before_remote_launch",
    )
    register_launch.assert_not_awaited()
    assert result == {
        "success": False,
        "reason": "superseded_before_remote_launch",
    }


@pytest.mark.asyncio
async def test_focus_session_routes_remote_attach_and_acknowledges_boundaries():
    service, _calls = make_service()
    session = {
        "session_key": "session-remote",
        "window_id": 0,
        "focus_mode": "remote_bridge_attachable",
    }
    record_seen = MagicMock()
    acknowledge_stopped = MagicMock()
    acknowledge_user_input = MagicMock()
    focus_remote = AsyncMock(return_value={
        "success": True,
        "focus_mode": "remote_bridge_bound",
        "current_ai_session_key_after": "session-remote",
    })

    result = await service.focus_session(
        session_key="session-remote",
        sessions=[session],
        intent_epoch=7,
        record_session_seen=record_seen,
        acknowledge_stopped_session=acknowledge_stopped,
        acknowledge_user_input_session=acknowledge_user_input,
        focus_remote_session_attach=focus_remote,
        focus_local_session_attach=AsyncMock(),
        window_focus=AsyncMock(),
        wait_for_session_focus=AsyncMock(),
        focus_state=AsyncMock(),
        set_focus_overrides=MagicMock(),
    )

    record_seen.assert_called_once_with("session-remote")
    acknowledge_stopped.assert_called_once_with(session)
    acknowledge_user_input.assert_called_once_with(session)
    focus_remote.assert_awaited_once_with(
        session_key="session-remote",
        session=session,
        intent_epoch=7,
    )
    assert result["success"] is True
    assert result["focus_mode"] == "remote_bridge_bound"


@pytest.mark.asyncio
async def test_focus_session_local_tmux_uses_tmux_verification_without_wait():
    service, _calls = make_service()
    service.select_tmux_target = MagicMock(return_value={"success": True, "reason": "ok"})
    service.verify_tmux_target = MagicMock(return_value={
        "success": True,
        "reason": "ok",
        "active_tmux_pane": "%1",
        "tmux_pane": "%1",
    })
    wait_for_session_focus = AsyncMock(return_value={"success": False, "reason": "should_not_wait"})
    set_focus_overrides = MagicMock()

    result = await service.focus_session(
        session_key="session-local-pane",
        sessions=[{
            "session_key": "session-local-pane",
            "window_id": 101,
            "focus_mode": "local_window",
            "focus_project": "vpittamp/nixos-config:main",
            "focus_execution_mode": "local",
            "focus_connection_key": "local@ryzen",
            "connection_key": "local@ryzen",
            "surface_key": "surface-local-pane",
            "conflict_state": "",
            "execution_mode": "local",
            "tmux_session": "i3pm-main",
            "tmux_window": "1:codex-raw",
            "tmux_pane": "%1",
            "terminal_context": {},
        }],
        intent_epoch=0,
        record_session_seen=MagicMock(),
        acknowledge_stopped_session=MagicMock(),
        acknowledge_user_input_session=MagicMock(),
        focus_remote_session_attach=AsyncMock(),
        focus_local_session_attach=AsyncMock(),
        window_focus=AsyncMock(return_value={"success": True}),
        wait_for_session_focus=wait_for_session_focus,
        focus_state=AsyncMock(return_value={
            "current_ai_session_key": "session-local-pane",
            "focused_window_id": 101,
        }),
        set_focus_overrides=set_focus_overrides,
    )

    service.select_tmux_target.assert_called_once()
    service.verify_tmux_target.assert_called_once()
    wait_for_session_focus.assert_not_awaited()
    set_focus_overrides.assert_called_once_with(
        session_key="session-local-pane",
        window_id=101,
        connection_key="local@ryzen",
    )
    assert result["success"] is True
    assert result["verification"]["verification_source"] == "tmux"
    assert result["current_ai_session_key_after"] == "session-local-pane"


@pytest.mark.asyncio
async def test_focus_session_window_only_sets_override_before_waiting():
    service, _calls = make_service()
    overrides = []

    def set_focus_overrides(**kwargs):
        overrides.append(kwargs)

    async def wait_for_session_focus(session_key):
        assert session_key == "session-window-only"
        assert overrides == [{
            "session_key": "session-window-only",
            "window_id": 146,
            "connection_key": "vpittamp@ryzen:22",
        }]
        return {
            "success": True,
            "reason": "ok",
            "session_key": session_key,
            "current_session_key": session_key,
        }

    result = await service.focus_session(
        session_key="session-window-only",
        sessions=[{
            "session_key": "session-window-only",
            "window_id": 146,
            "focus_mode": "local_window",
            "focus_project": "PittampalliOrg/workflow-builder:main",
            "focus_execution_mode": "ssh",
            "focus_connection_key": "vpittamp@ryzen:22",
            "connection_key": "vpittamp@ryzen:22",
            "surface_key": "surface-window-only",
            "conflict_state": "",
            "terminal_context": {},
        }],
        intent_epoch=0,
        record_session_seen=MagicMock(),
        acknowledge_stopped_session=MagicMock(),
        acknowledge_user_input_session=MagicMock(),
        focus_remote_session_attach=AsyncMock(),
        focus_local_session_attach=AsyncMock(),
        window_focus=AsyncMock(return_value={"success": True}),
        wait_for_session_focus=wait_for_session_focus,
        focus_state=AsyncMock(return_value={
            "current_ai_session_key": "session-window-only",
            "focused_window_id": 146,
        }),
        set_focus_overrides=set_focus_overrides,
    )

    assert len(overrides) == 2
    assert result["success"] is True
    assert result["verification"]["success"] is True
    assert result["focused_window_id_after"] == 146


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
