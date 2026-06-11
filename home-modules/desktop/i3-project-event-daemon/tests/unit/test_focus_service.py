"""Unit tests for daemon-owned focus service selection and view model."""

from __future__ import annotations

import importlib
import importlib.util
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


focus_service_module = importlib.import_module("i3_project_daemon.services.focus_service")

FocusService = focus_service_module.FocusService


def normalize_connection_key(value: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    if text.startswith("local@"):
        return text
    return text.lower()


def make_service() -> FocusService:
    return FocusService(normalize_connection_key=normalize_connection_key)


def make_action_service(
    *,
    sway_available=True,
    command_result=None,
    workspaces=None,
    notify_state_change=None,
    send_tick_barrier=None,
) -> FocusService:
    return FocusService(
        normalize_connection_key=normalize_connection_key,
        sway_available=lambda: sway_available,
        run_sway_command=AsyncMock(return_value=command_result if command_result is not None else [SimpleNamespace(success=True)]),
        sway_command_succeeded=lambda result: all(bool(getattr(item, "success", False)) for item in result),
        get_sway_workspaces=AsyncMock(return_value=workspaces if workspaces is not None else []),
        send_tick_barrier=send_tick_barrier or AsyncMock(return_value=None),
        notify_state_change=notify_state_change or AsyncMock(return_value=None),
    )


def make_window_focus_service(**overrides) -> FocusService:
    defaults = {
        "sway_available": lambda: True,
        "run_sway_command": AsyncMock(return_value=[SimpleNamespace(success=True)]),
        "sway_command_succeeded": lambda result: all(bool(getattr(item, "success", False)) for item in result),
        "send_tick_barrier": AsyncMock(return_value=None),
        "window_is_locally_tracked": AsyncMock(return_value=False),
        "connection_target_is_current_host": lambda _connection_key: True,
        "remote_daemon_request": AsyncMock(return_value={}),
        "switch_runtime_context": AsyncMock(return_value={"switched": False}),
        "get_window_transition_state": AsyncMock(return_value={
            "exists": True,
            "current_workspace": "1",
            "workspace_name": "1",
            "in_scratchpad": False,
            "floating": False,
            "fullscreen_mode": 0,
        }),
        "build_window_focus_transition": lambda **_kwargs: {
            "kind": "direct",
            "commands": ["[con_id=101] focus"],
            "expected": {"workspace_name": "1", "floating": False, "fullscreen_mode": 0},
        },
        "window_matches_transition_target": AsyncMock(return_value=True),
        "verify_window_focus": AsyncMock(return_value={"success": True, "reason": "ok"}),
        "focus_state_provider": AsyncMock(return_value={
            "success": True,
            "current_session_key": "session-current",
            "current_window_id": 101,
        }),
    }
    defaults.update(overrides)
    return FocusService(
        normalize_connection_key=normalize_connection_key,
        **defaults,
    )


def make_tree_node(
    node_id: int,
    *,
    workspace_name: str = "1",
    workspace_number: int = 1,
    focused: bool = False,
    floating: str = "auto_off",
    fullscreen_mode: int = 0,
    scratchpad_state: str = "none",
    parent=None,
    nodes=None,
    floating_nodes=None,
):
    workspace = SimpleNamespace(name=workspace_name, num=workspace_number)
    return SimpleNamespace(
        id=node_id,
        focused=focused,
        floating=floating,
        fullscreen_mode=fullscreen_mode,
        scratchpad_state=scratchpad_state,
        parent=parent,
        rect=SimpleNamespace(x=10, y=20, width=800, height=600),
        nodes=nodes or [],
        floating_nodes=floating_nodes or [],
        workspace=lambda: workspace,
    )


def test_connection_target_is_current_host_matches_parsed_remote_host() -> None:
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        local_host=lambda: "thinkpad",
        parse_remote_target=lambda _target, connection_key: (
            "vpittamp",
            "thinkpad" if connection_key else "",
            22,
        ),
    )

    assert service.connection_target_is_current_host("vpittamp@thinkpad:22") is True
    assert service.connection_target_is_current_host("") is False


def test_connection_target_is_current_host_rejects_different_host() -> None:
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        local_host=lambda: "thinkpad",
        parse_remote_target=lambda _target, _connection_key: ("vpittamp", "ryzen", 22),
    )

    assert service.connection_target_is_current_host("vpittamp@ryzen:22") is False


@pytest.mark.asyncio
async def test_window_is_locally_tracked_matches_window_map_key_and_fields() -> None:
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        window_map_snapshot=AsyncMock(return_value={
            101: SimpleNamespace(window_id=101, con_id=1001),
            202: SimpleNamespace(window_id=44, con_id=303),
            "404": {"window_id": 304, "con_id": 405},
        }),
    )

    assert await service.window_is_locally_tracked(101) is True
    assert await service.window_is_locally_tracked(44) is True
    assert await service.window_is_locally_tracked(405) is True
    assert await service.window_is_locally_tracked(404) is True
    assert await service.window_is_locally_tracked(999) is False


@pytest.mark.asyncio
async def test_window_is_locally_tracked_reports_false_on_snapshot_error() -> None:
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        window_map_snapshot=AsyncMock(side_effect=RuntimeError("boom")),
    )

    assert await service.window_is_locally_tracked(101) is False


def test_select_current_session_key_clears_stale_window_override() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="session-old",
        window_id=133,
        connection_key="local@thinkpad",
    )
    sessions = [
        {
            "session_key": "session-old",
            "window_id": 133,
            "is_current_host": True,
            "window_active": False,
            "pane_active": True,
        },
        {
            "session_key": "session-new",
            "window_id": 146,
            "is_current_host": True,
            "window_active": True,
            "pane_active": False,
        },
    ]

    result = service.select_current_session_key(sessions, focused_window_id=146)

    assert result == "session-new"
    assert service.session_override_key == ""
    assert service.window_override == {"window_id": 0, "connection_key": ""}


def test_select_current_session_key_prefers_focused_remote_herdr_override() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="herdr:ryzen:pane:w1-1",
        window_id=0,
        connection_key="vpittamp@ryzen:22",
    )
    sessions = [
        {
            "session_key": "herdr:thinkpad:pane:w0-1",
            "source": "herdr",
            "focused": True,
            "is_current_host": True,
        },
        {
            "session_key": "herdr:ryzen:pane:w1-1",
            "source": "herdr",
            "focused": True,
            "is_current_host": False,
        },
    ]

    result = service.select_current_session_key(sessions, focused_window_id=0)

    assert result == "herdr:ryzen:pane:w1-1"


def test_mark_current_session_produces_single_current_row() -> None:
    service = make_service()
    sessions = [
        {"session_key": "session-a", "is_current_window": True},
        {"session_key": "session-b", "is_current_window": True},
    ]

    service.mark_current_session(sessions, current_session_key="session-b")

    assert [session["is_current_window"] for session in sessions] == [False, True]


def test_clear_if_session_matches_clears_focus_overrides() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="session-a",
        window_id=77,
        connection_key="LOCAL@THINKPAD",
    )

    assert service.clear_if_session_matches("session-b") is False
    assert service.override_payload() == {
        "session_key": "session-a",
        "window_id": 77,
        "connection_key": "local@thinkpad",
    }

    assert service.clear_if_session_matches("session-a") is True
    assert service.override_payload() == {
        "session_key": "",
        "window_id": 0,
        "connection_key": "",
    }


def test_prune_invalid_overrides_reports_cleared_state() -> None:
    service = make_service()
    service.set_focus_overrides(
        session_key="session-old",
        window_id=404,
        connection_key="local@thinkpad",
    )

    result = service.prune_invalid_overrides(
        live_session_keys=["session-new"],
        live_window_ids=[101, 202],
        stale_window_ids=[404],
    )

    assert result == {
        "cleared_session_override": True,
        "cleared_window_override": True,
    }
    assert service.override_payload() == {
        "session_key": "",
        "window_id": 0,
        "connection_key": "",
    }


def test_build_focus_state_payload_uses_daemon_focus_fields() -> None:
    service = make_service()
    service.begin_focus_intent(
        intent_id="intent-7",
        kind="window_focus",
        target_key="101",
        created_at=123.5,
        generation=7,
    )
    runtime_snapshot = {
        "active_context": {"connection_key": "local@thinkpad"},
        "current_session_key": "session-current",
        "focused_window_id": 101,
        "outputs": [
            {
                "current_workspace": "2",
                "workspaces": [
                    {"name": "1", "focused": False},
                    {"name": "2", "focused": True},
                ],
            }
        ],
    }
    sessions = [
        {
            "session_key": "session-current",
            "pane_id": "pane-1",
            "host_name": "thinkpad",
            "agent": "codex",
            "window_id": 101,
        }
    ]

    result = service.build_focus_state_payload(
        runtime_snapshot,
        sessions,
        generation=42,
    )

    assert result["schema_version"] == "i3pm.focus_state.v2"
    assert result["generation"] == 42
    assert result["current_session_key"] == "session-current"
    assert "current_ai_session_key" not in result
    assert result["current_window_id"] == 101
    assert "focused_window_id" not in result
    assert result["current_workspace_name"] == "2"
    assert result["current_herdr_pane_id"] == "pane-1"
    assert result["current_herdr_host"] == "thinkpad"
    assert result["pending_intent_id"] == "intent-7"
    assert result["focus_intent"] == {
        "intent_id": "intent-7",
        "kind": "window_focus",
        "target_key": "101",
        "state": "pending",
        "created_at": 123.5,
        "generation": 7,
        "reason": "",
    }
    assert result["active_session"]["agent"] == "codex"


def test_build_focus_state_payload_prefers_focused_workspace_over_output_current_fallback() -> None:
    service = make_service()
    runtime_snapshot = {
        "active_context": {"connection_key": "local@thinkpad"},
        "current_session_key": "",
        "focused_window_id": 0,
        "outputs": [
            {
                "name": "DP-7",
                "current_workspace": "1",
                "workspaces": [
                    {"name": "1", "focused": False, "visible": True},
                ],
            },
            {
                "name": "eDP-1",
                "current_workspace": "2",
                "workspaces": [
                    {"name": "2", "focused": True, "visible": False},
                ],
            },
        ],
    }

    result = service.build_focus_state_payload(runtime_snapshot, [], generation=5)

    assert result["current_workspace_name"] == "2"


@pytest.mark.asyncio
async def test_focus_workspace_fast_skips_notification_and_verification() -> None:
    notify_state_change = AsyncMock(return_value=None)
    send_tick_barrier = AsyncMock(return_value=None)
    service = make_action_service(
        notify_state_change=notify_state_change,
        send_tick_barrier=send_tick_barrier,
    )

    result = await service.focus_workspace_fast({"workspace": "3"})

    assert result == {"success": True, "workspace": "3", "fast": True}
    service._run_sway_command.assert_awaited_once_with("workspace number 3")
    send_tick_barrier.assert_not_awaited()
    notify_state_change.assert_not_awaited()


@pytest.mark.asyncio
async def test_focus_workspace_fast_keeps_pending_intent_until_finalized() -> None:
    service = make_action_service()
    service.begin_user_focus_intent(
        intent_id="intent-7",
        method="workspace.focus_fast",
        params={"workspace": "3"},
        created_at=700.0,
        generation=7,
    )

    result = await service.focus_workspace_fast({"workspace": "3"})

    assert result["success"] is True
    assert service.pending_intent_id == "intent-7"
    assert service.focus_intent_payload()["state"] == "pending"


@pytest.mark.asyncio
async def test_focus_workspace_waits_for_confirmed_workspace() -> None:
    notify_state_change = AsyncMock(return_value=None)
    send_tick_barrier = AsyncMock(return_value=None)
    get_workspaces = AsyncMock(
        side_effect=[
            [SimpleNamespace(name="1", focused=True), SimpleNamespace(name="3", focused=False)],
            [SimpleNamespace(name="1", focused=False), SimpleNamespace(name="3", focused=True)],
        ]
    )
    service = make_action_service(
        notify_state_change=notify_state_change,
        send_tick_barrier=send_tick_barrier,
    )
    service._get_sway_workspaces = get_workspaces

    result = await service.focus_workspace({"workspace": "3"})

    assert result == {"success": True, "workspace": "3"}
    service._run_sway_command.assert_awaited_once_with("workspace number 3")
    send_tick_barrier.assert_awaited_once_with("i3pm:workspace-focus:3")
    notify_state_change.assert_awaited_once_with("focus_changed")


@pytest.mark.asyncio
async def test_focus_workspace_returns_failure_when_command_fails() -> None:
    service = make_action_service(command_result=[SimpleNamespace(success=False)])

    result = await service.focus_workspace({"workspace": "3"})

    assert result == {
        "success": False,
        "workspace": "3",
        "error": "command_failed:workspace number 3",
    }


@pytest.mark.asyncio
async def test_focus_workspace_requires_sway_connection() -> None:
    service = make_action_service(sway_available=False)

    with pytest.raises(RuntimeError, match="Sway connection is unavailable"):
        await service.focus_workspace_fast({"workspace": "3"})


@pytest.mark.asyncio
async def test_focus_window_service_local_success_sets_overrides() -> None:
    service = make_window_focus_service()

    result = await service.focus_window(
        window_id=101,
        project_name="vpittamp/nixos-config:main",
        connection_key="local@thinkpad",
    )

    assert result["success"] is True
    assert result["window_id"] == 101
    assert result["project_name"] == "vpittamp/nixos-config:main"
    assert result["current_session_key_after"] == "session-current"
    assert result["focused_window_id_after"] == 101
    assert result["verification"] == {"success": True, "reason": "ok"}
    assert service.override_payload() == {
        "session_key": "session-current",
        "window_id": 101,
        "connection_key": "local@thinkpad",
    }


@pytest.mark.asyncio
async def test_focus_window_service_remote_handoff_sets_remote_override() -> None:
    remote_daemon_request = AsyncMock(return_value={
        "success": True,
        "remote_host": "ryzen",
        "result": {
            "success": True,
            "focus_state_after": {
                "current_session_key": "session-remote",
                "current_window_id": 175,
            },
            "verification": {"success": True, "reason": "ok"},
        },
    })
    service = make_window_focus_service(
        window_is_locally_tracked=AsyncMock(return_value=False),
        connection_target_is_current_host=lambda _connection_key: False,
        remote_daemon_request=remote_daemon_request,
    )

    result = await service.focus_window(
        window_id=175,
        project_name="PittampalliOrg/stacks:main",
        target_variant="ssh",
        connection_key="vpittamp@ryzen:22",
    )

    assert result["success"] is True
    assert result["target_variant"] == "ssh"
    assert result["focus_target_host"] == "ryzen"
    assert result["current_session_key_after"] == "session-remote"
    assert result["focused_window_id_after"] == 175
    remote_daemon_request.assert_awaited_once()
    assert service.override_payload() == {
        "session_key": "session-remote",
        "window_id": 175,
        "connection_key": "vpittamp@ryzen:22",
    }


@pytest.mark.asyncio
async def test_focus_service_remote_daemon_request_runs_ssh_json_rpc() -> None:
    remote_run_command = AsyncMock(return_value=SimpleNamespace(
        returncode=0,
        stdout='noise\n{"success":true,"current_session_key_after":"session-remote"}\n',
        stderr="",
    ))
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        parse_remote_target=lambda _target, connection_key: ("vpittamp", "ryzen", 2222),
        remote_run_command=remote_run_command,
    )

    result = await service.remote_daemon_request(
        connection_key="vpittamp@ryzen:2222",
        method="window.focus",
        params={"window_id": 175},
    )

    assert result["success"] is True
    assert result["reason"] == "ok"
    assert result["remote_user"] == "vpittamp"
    assert result["remote_host"] == "ryzen"
    assert result["remote_port"] == 2222
    assert result["result"] == {
        "success": True,
        "current_session_key_after": "session-remote",
    }
    args = remote_run_command.await_args.args
    assert args[:7] == (
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=3",
        "-p",
        "2222",
    )
    assert args[7] == "vpittamp@ryzen"
    assert "i3pm daemon call window.focus" in args[8]


@pytest.mark.asyncio
async def test_focus_service_remote_daemon_request_reports_transport_failure() -> None:
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        parse_remote_target=lambda _target, _connection_key: ("", "ryzen", 22),
        remote_run_command=AsyncMock(return_value=SimpleNamespace(
            returncode=255,
            stdout="",
            stderr="ssh failed",
        )),
    )

    result = await service.remote_daemon_request(
        connection_key="ryzen",
        method="window.focus",
        params={"window_id": 175},
    )

    assert result["success"] is False
    assert result["reason"] == "remote_transport_failed"
    assert result["remote_host"] == "ryzen"
    assert result["stderr"] == "ssh failed"


@pytest.mark.asyncio
async def test_focus_service_remote_daemon_request_reports_missing_target() -> None:
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        parse_remote_target=lambda _target, _connection_key: ("", "", 22),
    )

    result = await service.remote_daemon_request(
        connection_key="",
        method="window.focus",
        params={"window_id": 175},
    )

    assert result == {
        "success": False,
        "reason": "missing_remote_target",
        "remote_host": "",
        "remote_port": 22,
        "stdout": "",
        "stderr": "",
        "result": None,
    }


@pytest.mark.asyncio
async def test_focus_window_service_requires_window_dependencies() -> None:
    service = make_service()

    with pytest.raises(RuntimeError, match="Window focus dependencies are unavailable"):
        await service.focus_window(window_id=101)


@pytest.mark.asyncio
async def test_focus_window_fast_service_direct_success_skips_transition() -> None:
    run_sway_command = AsyncMock(return_value=[SimpleNamespace(success=True)])
    get_window_transition_state = AsyncMock(return_value={"exists": True})
    notify_state_change = AsyncMock(return_value=None)
    service = make_window_focus_service(
        run_sway_command=run_sway_command,
        get_window_transition_state=get_window_transition_state,
        notify_state_change=notify_state_change,
    )

    result = await service.focus_window_fast({
        "window_id": 30,
        "target_variant": "local",
        "connection_key": "local@ryzen",
        "session_key": "session-current",
    })

    assert result == {
        "success": True,
        "window_id": 30,
        "fast": True,
        "direct": True,
        "command": "[con_id=30] focus",
        "transition": "direct_focus",
    }
    run_sway_command.assert_awaited_once_with("[con_id=30] focus")
    get_window_transition_state.assert_not_awaited()
    notify_state_change.assert_not_awaited()
    assert service.override_payload() == {
        "session_key": "session-current",
        "window_id": 30,
        "connection_key": "local@ryzen",
    }


@pytest.mark.asyncio
async def test_focus_window_fast_service_falls_back_to_transition() -> None:
    calls = []

    async def run_sway_command(command):
        calls.append(command)
        return [SimpleNamespace(success=len(calls) > 1)]

    service = make_window_focus_service(
        run_sway_command=AsyncMock(side_effect=run_sway_command),
        get_window_transition_state=AsyncMock(return_value={
            "exists": True,
            "current_workspace": "1",
            "workspace_name": "2",
        }),
        build_window_focus_transition=lambda **_kwargs: {
            "kind": "workspace_switch",
            "commands": ["workspace 2", "[con_id=31] focus"],
        },
    )

    result = await service.focus_window_fast({
        "window_id": 31,
        "target_variant": "local",
        "connection_key": "local@ryzen",
    })

    assert result == {
        "success": True,
        "window_id": 31,
        "fast": True,
        "command": "workspace 2; [con_id=31] focus",
        "transition": "workspace_switch",
    }
    assert calls == ["[con_id=31] focus", "workspace 2; [con_id=31] focus"]


@pytest.mark.asyncio
async def test_focus_window_fast_service_rejects_remote_target() -> None:
    run_sway_command = AsyncMock(return_value=[SimpleNamespace(success=True)])
    get_window_transition_state = AsyncMock(return_value={"exists": True})
    service = make_window_focus_service(
        run_sway_command=run_sway_command,
        get_window_transition_state=get_window_transition_state,
        window_is_locally_tracked=AsyncMock(return_value=False),
        connection_target_is_current_host=lambda _connection_key: False,
    )

    result = await service.focus_window_fast({
        "window_id": 175,
        "target_variant": "ssh",
        "connection_key": "vpittamp@ryzen:22",
    })

    assert result == {
        "success": False,
        "window_id": 175,
        "reason": "remote_target_not_fast_focusable",
        "fallback_method": "window.focus",
    }
    run_sway_command.assert_not_awaited()
    get_window_transition_state.assert_not_awaited()


@pytest.mark.asyncio
async def test_focus_service_resolves_focused_window_from_sway_tree() -> None:
    focused_node = SimpleNamespace(focused=True, id=909, nodes=[], floating_nodes=[])
    tree = SimpleNamespace(
        focused=False,
        id=1,
        nodes=[
            SimpleNamespace(focused=False, id=2, nodes=[], floating_nodes=[]),
            SimpleNamespace(focused=False, id=3, nodes=[focused_node], floating_nodes=[]),
        ],
        floating_nodes=[],
    )
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        sway_available=lambda: True,
        get_sway_tree=AsyncMock(return_value=tree),
    )

    assert await service.focused_window_id() == 909
    assert await service.verify_window_focus(909) == {
        "success": True,
        "window_id": 909,
        "focused_window_id": 909,
        "reason": "ok",
    }


@pytest.mark.asyncio
async def test_focus_service_verify_window_focus_reports_mismatch() -> None:
    tree = SimpleNamespace(focused=True, id=100, nodes=[], floating_nodes=[])
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        sway_available=lambda: True,
        get_sway_tree=AsyncMock(return_value=tree),
    )

    result = await service.verify_window_focus(101)

    assert result == {
        "success": False,
        "window_id": 101,
        "focused_window_id": 100,
        "reason": "focused_window_mismatch",
    }


@pytest.mark.asyncio
async def test_focus_service_matches_transition_target_from_transition_state() -> None:
    get_window_transition_state = AsyncMock(return_value={
        "exists": True,
        "in_scratchpad": False,
        "floating": True,
        "fullscreen_mode": 1,
    })
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        get_window_transition_state=get_window_transition_state,
    )

    assert await service.window_matches_transition_target({
        "window_id": 44,
        "in_scratchpad": False,
        "floating": True,
        "fullscreen_mode": 1,
    }) is True
    get_window_transition_state.assert_awaited_once_with(44)


@pytest.mark.asyncio
async def test_focus_service_rejects_transition_target_mismatch() -> None:
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        get_window_transition_state=AsyncMock(return_value={
            "exists": True,
            "in_scratchpad": True,
            "floating": False,
            "fullscreen_mode": 0,
        }),
    )

    assert await service.window_matches_transition_target({
        "window_id": 44,
        "in_scratchpad": False,
        "floating": False,
        "fullscreen_mode": 0,
    }) is False


@pytest.mark.asyncio
async def test_focus_service_reads_native_window_transition_state_from_tree() -> None:
    focused = make_tree_node(10, workspace_name="1", workspace_number=1, focused=True)
    target = make_tree_node(
        20,
        workspace_name="2",
        workspace_number=2,
        floating="user_on",
        fullscreen_mode=1,
    )
    tree = make_tree_node(1, nodes=[focused, target])
    get_saved_window_state = AsyncMock(return_value={"workspace_number": 2})
    service = FocusService(
        normalize_connection_key=normalize_connection_key,
        sway_available=lambda: True,
        get_sway_tree=AsyncMock(return_value=tree),
        get_saved_window_state=get_saved_window_state,
    )

    result = await service.get_window_transition_state(20)

    assert result["exists"] is True
    assert result["window_id"] == 20
    assert result["current_workspace"] == "1"
    assert result["workspace_name"] == "2"
    assert result["workspace_number"] == 2
    assert result["floating"] is True
    assert result["fullscreen_mode"] == 1
    assert result["geometry"] == {"x": 10, "y": 20, "width": 800, "height": 600}
    assert result["saved_state"] == {"workspace_number": 2}
    get_saved_window_state.assert_awaited_once_with(20)


def test_focus_service_builds_scratchpad_restore_transition() -> None:
    service = make_service()

    transition = service.build_window_focus_transition(
        window_id=44,
        state={
            "current_workspace": "1",
            "workspace_name": "__i3_scratch",
            "workspace_number": 0,
            "in_scratchpad": True,
            "floating": True,
            "floating_state": "user_on",
            "fullscreen_mode": 0,
            "saved_state": {
                "workspace_number": 3,
                "floating": False,
                "geometry": None,
                "fullscreen_mode": 1,
                "original_scratchpad": False,
            },
        },
    )

    assert transition["kind"] == "scratchpad_restore"
    assert transition["commands"] == [
        "workspace number 3",
        "[con_id=44] move workspace number 3",
        "[con_id=44] floating disable",
        "[con_id=44] fullscreen enable",
        "[con_id=44] focus",
    ]
    assert transition["expected"] == {
        "window_id": 44,
        "in_scratchpad": False,
        "floating": False,
        "fullscreen_mode": 1,
        "workspace_name": "3",
        "workspace_number": 3,
    }


def test_focus_service_builds_workspace_switch_transition_with_quoted_workspace() -> None:
    service = make_service()

    transition = service.build_window_focus_transition(
        window_id=45,
        state={
            "current_workspace": "1",
            "workspace_name": "dev work",
            "workspace_number": 0,
            "in_scratchpad": False,
            "floating": False,
            "floating_state": "auto_off",
            "fullscreen_mode": 0,
            "saved_state": None,
        },
    )

    assert transition["kind"] == "workspace_switch"
    assert transition["commands"] == [
        "workspace 'dev work'",
        "[con_id=45] floating disable",
        "[con_id=45] focus",
    ]


@pytest.mark.asyncio
async def test_window_action_service_runs_single_command_and_tick() -> None:
    run_sway_command = AsyncMock(return_value=[SimpleNamespace(success=True)])
    send_tick_barrier = AsyncMock(return_value=None)
    service = make_window_focus_service(
        run_sway_command=run_sway_command,
        send_tick_barrier=send_tick_barrier,
    )

    result = await service.window_action({
        "window_id": 404,
        "action": "floating_toggle",
    })

    assert result == {"success": True, "window_id": 404, "action": "floating_toggle"}
    run_sway_command.assert_awaited_once_with("[con_id=404] floating toggle")
    send_tick_barrier.assert_awaited_once_with("i3pm:window-action:floating_toggle:404")


@pytest.mark.asyncio
async def test_window_action_service_runs_layout_command_sequence() -> None:
    run_sway_command = AsyncMock(return_value=[SimpleNamespace(success=True)])
    service = make_window_focus_service(run_sway_command=run_sway_command)

    result = await service.window_action({
        "window_id": 405,
        "action": "layout_tabbed",
    })

    assert result["success"] is True
    assert [call.args[0] for call in run_sway_command.await_args_list] == [
        "[con_id=405] focus",
        "layout tabbed",
    ]


@pytest.mark.asyncio
async def test_window_action_service_reports_command_failure() -> None:
    run_sway_command = AsyncMock(side_effect=[
        [SimpleNamespace(success=True)],
        [SimpleNamespace(success=False)],
    ])
    service = make_window_focus_service(run_sway_command=run_sway_command)

    result = await service.window_action({
        "window_id": 406,
        "action": "split_v",
    })

    assert result == {
        "success": False,
        "window_id": 406,
        "action": "split_v",
        "error": "command_failed:split v",
    }


@pytest.mark.asyncio
async def test_window_action_service_focus_delegates_to_focus_window() -> None:
    service = make_window_focus_service()

    result = await service.window_action({
        "window_id": 101,
        "action": "focus",
        "project_name": "vpittamp/nixos-config:main",
        "target_variant": "local",
    })

    assert result["success"] is True
    assert result["window_id"] == 101
    assert result["project_name"] == "vpittamp/nixos-config:main"
    assert service.window_override == {"window_id": 101, "connection_key": ""}


@pytest.mark.asyncio
async def test_window_action_service_validates_window_and_action() -> None:
    service = make_window_focus_service()

    with pytest.raises(ValueError, match="window_id must be a positive integer"):
        await service.window_action({"window_id": 0, "action": "kill"})

    with pytest.raises(ValueError, match="action is required"):
        await service.window_action({"window_id": 101})

    with pytest.raises(ValueError, match="Unsupported window action"):
        await service.window_action({"window_id": 101, "action": "warp"})


def test_focus_intent_transitions_pending_to_confirmed() -> None:
    service = make_service()
    service.begin_focus_intent(
        intent_id="intent-8",
        kind="workspace_focus",
        target_key="2",
        created_at=200.0,
        generation=8,
    )

    result = service.finish_focus_intent(
        intent_id="intent-8",
        state="confirmed",
        reason="ok",
    )

    assert service.pending_intent_id == ""
    assert result["state"] == "confirmed"
    assert result["intent_id"] == "intent-8"
    assert result["kind"] == "workspace_focus"
    assert result["target_key"] == "2"
    assert result["reason"] == "ok"


def test_focus_intent_transitions_pending_to_failed() -> None:
    service = make_service()
    service.begin_focus_intent(
        intent_id="intent-9",
        kind="herdr_pane_focus",
        target_key="ryzen:pane-1",
        created_at=300.0,
        generation=9,
    )

    result = service.finish_focus_intent(
        intent_id="intent-9",
        state="failed",
        reason="remote_transport_failed",
    )

    assert service.pending_intent_id == ""
    assert result["state"] == "failed"
    assert result["reason"] == "remote_transport_failed"


def test_focus_intent_kind_and_target_maps_focus_methods() -> None:
    assert FocusService.focus_intent_kind_and_target(
        method="window.focus_fast",
        params={"window_id": 101},
    ) == ("window_focus", "101")
    assert FocusService.focus_intent_kind_and_target(
        method="workspace.focus",
        params={"workspace": "33"},
    ) == ("workspace_focus", "33")
    assert FocusService.focus_intent_kind_and_target(
        method="herdr.remote.pane.focus",
        params={"ssh_target": "ryzen", "pane_id": "pane-1"},
    ) == ("herdr_pane_focus", "ryzen:pane-1")
    assert FocusService.focus_intent_kind_and_target(
        method="herdr.workspace.focus",
        params={"workspace_id": "workspace-1"},
    ) == ("herdr_workspace_focus", "workspace-1")


def test_begin_user_focus_intent_ignores_non_focus_methods() -> None:
    service = make_service()

    result = service.begin_user_focus_intent(
        intent_id="intent-1",
        method="daemon.status",
        params={},
        created_at=100.0,
        generation=1,
    )

    assert result == {}
    assert service.focus_intent_payload() == {}


def test_begin_user_focus_intent_records_formal_contract_fields() -> None:
    service = make_service()

    result = service.begin_user_focus_intent(
        intent_id="intent-10",
        method="herdr.pane.focus",
        params={"pane_id": "pane-2"},
        created_at=400.0,
        generation=10,
    )

    assert result == {
        "intent_id": "intent-10",
        "kind": "herdr_pane_focus",
        "target_key": "pane-2",
        "state": "pending",
        "created_at": 400.0,
        "generation": 10,
        "reason": "",
    }
    assert service.pending_intent_id == "intent-10"


def test_advance_user_intent_increments_epoch_without_non_focus_highlight() -> None:
    service = make_service()

    epoch = service.advance_user_intent(
        method="launch.open",
        params={"app_name": "firefox"},
        created_at=450.0,
    )

    assert epoch == 1
    assert service.user_intent_epoch == 1
    assert service.user_intent_is_current(1) is True
    assert service.user_intent_is_current(2) is False
    assert service.user_intent_is_current(0) is True
    assert service.focus_intent_payload() == {}


def test_advance_user_intent_begins_focus_intent_for_focus_methods() -> None:
    service = make_service()

    epoch = service.advance_user_intent(
        method="workspace.focus_fast",
        params={"workspace": "5"},
        created_at=455.0,
    )

    assert epoch == 1
    assert service.focus_intent_payload() == {
        "intent_id": "intent-1",
        "kind": "workspace_focus",
        "target_key": "5",
        "state": "pending",
        "created_at": 455.0,
        "generation": 1,
        "reason": "",
    }


def test_finalize_focus_intent_for_result_uses_result_error_reason() -> None:
    service = make_service()
    service.begin_user_focus_intent(
        intent_id="intent-11",
        method="workspace.focus_fast",
        params={"workspace": "9"},
        created_at=500.0,
        generation=11,
    )

    result = service.finalize_focus_intent_for_result(
        method="workspace.focus_fast",
        intent_epoch=11,
        result={"success": False, "error": "command_failed:workspace number 9"},
    )

    assert result["intent_id"] == "intent-11"
    assert result["kind"] == "workspace_focus"
    assert result["target_key"] == "9"
    assert result["state"] == "failed"
    assert result["reason"] == "command_failed:workspace number 9"
    assert service.pending_intent_id == ""


def test_fail_focus_intent_for_exception_marks_active_intent_failed() -> None:
    service = make_service()
    service.begin_user_focus_intent(
        intent_id="intent-12",
        method="window.focus",
        params={"window_id": 808},
        created_at=600.0,
        generation=12,
    )

    result = service.fail_focus_intent_for_exception(
        method="window.focus",
        intent_epoch=12,
        reason="boom",
    )

    assert result["intent_id"] == "intent-12"
    assert result["kind"] == "window_focus"
    assert result["state"] == "failed"
    assert result["reason"] == "boom"
    assert service.pending_intent_id == ""
