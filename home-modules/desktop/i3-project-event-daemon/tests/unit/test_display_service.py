"""Unit tests for daemon display service."""

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


display_service_module = importlib.import_module("i3_project_daemon.services.display_service")
monitor_profile_module = importlib.import_module("i3_project_daemon.models.monitor_profile")
output_state_manager_module = importlib.import_module("i3_project_daemon.output_state_manager")

DisplayService = display_service_module.DisplayService
MonitorProfile = monitor_profile_module.MonitorProfile


def make_output(
    name: str,
    *,
    active: bool = True,
    focused: bool = False,
    scale: float = 1.0,
    x: int = 0,
    y: int = 0,
    width: int = 1920,
    height: int = 1080,
) -> SimpleNamespace:
    return SimpleNamespace(
        name=name,
        active=active,
        focused=focused,
        scale=scale,
        rect=SimpleNamespace(x=x, y=y, width=width, height=height),
    )


def make_service(
    *,
    run_sway_command=None,
    sway_command_succeeded=None,
    send_tick_barrier=None,
    notify=None,
) -> DisplayService:
    return DisplayService(
        notify_state_change=notify or AsyncMock(return_value=None),
        run_sway_command=run_sway_command or AsyncMock(return_value=[SimpleNamespace(success=True)]),
        sway_command_succeeded=(
            sway_command_succeeded
            or (lambda result: all(bool(getattr(item, "success", False)) for item in result))
        ),
        send_tick_barrier=send_tick_barrier or AsyncMock(return_value=None),
    )


@pytest.mark.asyncio
async def test_snapshot_shapes_outputs_and_layout_options(monkeypatch) -> None:
    service = make_service()
    monkeypatch.setattr(
        output_state_manager_module,
        "load_output_states",
        lambda: SimpleNamespace(is_output_enabled=lambda name: name != "DP-2"),
    )
    profile = MonitorProfile(**{
        "name": "dual",
        "description": "Dual display",
        "default": True,
        "outputs": [
            {"name": "DP-1", "enabled": True, "scale": 1.25, "position": {"x": 0, "y": 0, "width": 1920, "height": 1200}},
            {"name": "DP-2", "enabled": False, "position": {"x": 1920, "y": 0, "width": 1920, "height": 1200}},
        ],
    })
    monitor_profile_service = SimpleNamespace(
        get_current_profile=lambda: "dual",
        list_profiles=lambda: ["dual"],
        get_profile=lambda name: profile if name == "dual" else None,
    )
    i3_connection = SimpleNamespace(
        conn=SimpleNamespace(get_outputs=AsyncMock(return_value=[
            make_output("DP-1", focused=True, scale=1.25, height=1200),
            make_output("DP-2", x=1920, height=1200),
            make_output("__i3", active=False),
        ])),
    )

    result = await service.snapshot(
        i3_connection=i3_connection,
        monitor_profile_service=monitor_profile_service,
        display_generation=7,
        snapshot_version=11,
    )

    assert result["current_layout"] == "dual"
    assert result["layouts"] == ["dual"]
    assert result["display_generation"] == 7
    assert result["snapshot_version"] == 11
    assert result["outputs"] == [
        {
            "name": "DP-1",
            "active": True,
            "enabled": True,
            "focused": True,
            "primary": True,
            "scale": 1.25,
            "rect": {"x": 0, "y": 0, "width": 1920, "height": 1200},
        },
        {
            "name": "DP-2",
            "active": True,
            "enabled": False,
            "focused": False,
            "primary": False,
            "scale": 1.0,
            "rect": {"x": 1920, "y": 0, "width": 1920, "height": 1200},
        },
    ]
    assert result["layout_options"][0]["name"] == "dual"
    assert result["layout_options"][0]["output_names"] == ["DP-1"]
    assert result["layout_options"][0]["outputs"][0]["scale"] == 1.25


@pytest.mark.asyncio
async def test_cycle_applies_next_layout(monkeypatch, tmp_path) -> None:
    notify = AsyncMock(return_value=None)
    service = make_service(notify=notify)
    current_file = tmp_path / "monitor-profile.current"
    monitor_profile_service_module = importlib.import_module("i3_project_daemon.monitor_profile_service")
    monkeypatch.setattr(monitor_profile_service_module, "CURRENT_PROFILE_FILE", current_file)
    monkeypatch.setattr(
        output_state_manager_module,
        "load_output_states",
        lambda: SimpleNamespace(is_output_enabled=lambda _name: True),
    )
    monitor_profile_service = SimpleNamespace(
        get_current_profile=lambda: "a",
        list_profiles=lambda: ["a", "b"],
        get_profile=lambda _name: None,
        handle_profile_change=AsyncMock(return_value=True),
    )
    i3_connection = SimpleNamespace(
        conn=SimpleNamespace(
            get_outputs=AsyncMock(return_value=[make_output("DP-1", focused=True)]),
        ),
    )

    result = await service.cycle(
        {},
        i3_connection=i3_connection,
        monitor_profile_service=monitor_profile_service,
        display_generation=2,
        snapshot_version=3,
    )

    monitor_profile_service.handle_profile_change.assert_awaited_once_with(i3_connection.conn, "b")
    notify.assert_awaited_once_with("display_layout_changed")
    assert current_file.read_text(encoding="utf-8") == "b\n"
    assert result["applied"] is True


@pytest.mark.asyncio
async def test_configure_output_builds_command_and_ticks() -> None:
    run_sway_command = AsyncMock(return_value=[SimpleNamespace(success=True)])
    send_tick_barrier = AsyncMock(return_value=None)
    service = make_service(
        run_sway_command=run_sway_command,
        send_tick_barrier=send_tick_barrier,
    )

    result = await service.configure_output({
        "output_name": "DP-1",
        "enabled": True,
        "mode": "1920x1080@60Hz",
        "position_x": 10,
        "position_y": 20,
        "scale": 1.25,
    })

    assert result == {
        "success": True,
        "output_name": "DP-1",
        "command": "output DP-1 enable mode 1920x1080@60Hz position 10,20 scale 1.25",
    }
    run_sway_command.assert_awaited_once_with(
        "output DP-1 enable mode 1920x1080@60Hz position 10,20 scale 1.25"
    )
    send_tick_barrier.assert_awaited_once_with("i3pm:output-configure:DP-1")


@pytest.mark.asyncio
async def test_configure_output_reports_command_failure() -> None:
    service = make_service(run_sway_command=AsyncMock(return_value=[SimpleNamespace(success=False)]))

    result = await service.configure_output({"output_name": "DP-1", "scale": 2.0})

    assert result == {
        "success": False,
        "output_name": "DP-1",
        "error": "command_failed:output DP-1 scale 2.0",
    }


@pytest.mark.asyncio
async def test_configure_output_validates_required_fields() -> None:
    service = make_service()

    with pytest.raises(ValueError, match="output_name is required"):
        await service.configure_output({"scale": 1.0})

    with pytest.raises(ValueError, match="No output configuration fields"):
        await service.configure_output({"output_name": "DP-1"})


@pytest.mark.asyncio
async def test_create_virtual_output_runs_sway_command_and_tick() -> None:
    run_sway_command = AsyncMock(return_value=[SimpleNamespace(success=True)])
    send_tick_barrier = AsyncMock(return_value=None)
    service = make_service(
        run_sway_command=run_sway_command,
        send_tick_barrier=send_tick_barrier,
    )

    result = await service.create_virtual_output({})

    assert result == {"success": True}
    run_sway_command.assert_awaited_once_with("create_output")
    send_tick_barrier.assert_awaited_once_with("i3pm:output-create")


@pytest.mark.asyncio
async def test_move_workspace_to_output_uses_runtime_move_semantics() -> None:
    run_sway_command = AsyncMock(return_value=[SimpleNamespace(success=True)])
    send_tick_barrier = AsyncMock(return_value=None)
    service = make_service(
        run_sway_command=run_sway_command,
        send_tick_barrier=send_tick_barrier,
    )

    result = await service.move_workspace_to_output({"workspace": "7", "output_name": "DP-1"})

    assert result == {"success": True, "workspace": "7", "output_name": "DP-1"}
    assert [call.args[0] for call in run_sway_command.await_args_list] == [
        "workspace 7",
        "move workspace to output DP-1",
    ]
    send_tick_barrier.assert_awaited_once_with("i3pm:workspace-output:7:DP-1")


@pytest.mark.asyncio
async def test_move_workspace_to_output_reports_move_failure() -> None:
    run_sway_command = AsyncMock(side_effect=[
        [SimpleNamespace(success=True)],
        [SimpleNamespace(success=False)],
    ])
    service = make_service(run_sway_command=run_sway_command)

    result = await service.move_workspace_to_output({"workspace": "7", "output_name": "DP-1"})

    assert result == {
        "success": False,
        "workspace": "7",
        "output_name": "DP-1",
        "error": "command_failed:move workspace to output DP-1",
    }


@pytest.mark.asyncio
async def test_outputs_state_returns_cached_outputs_with_focused_output(monkeypatch) -> None:
    output_event_service_module = importlib.import_module(
        "i3_project_daemon.services.output_event_service"
    )
    cached_state = SimpleNamespace(active=True, to_dict=lambda: {"name": "DP-1", "active": True})
    monkeypatch.setattr(
        output_event_service_module,
        "get_output_event_service",
        lambda: SimpleNamespace(
            get_current_state=lambda: {"DP-1": cached_state},
            get_active_outputs=lambda: ["DP-1"],
        ),
    )
    i3_connection = SimpleNamespace(
        conn=SimpleNamespace(
            get_outputs=AsyncMock(return_value=[make_output("DP-1", focused=True)]),
        ),
    )
    service = make_service()

    result = await service.outputs_state({}, i3_connection=i3_connection)

    assert result == {
        "initialized": True,
        "outputs": {"DP-1": {"name": "DP-1", "active": True}},
        "count": 1,
        "active_count": 1,
        "active_outputs": ["DP-1"],
        "focused_output": "DP-1",
    }
