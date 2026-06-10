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


def make_service(*, output_configure=None, notify=None) -> DisplayService:
    return DisplayService(
        notify_state_change=notify or AsyncMock(return_value=None),
        output_configure=output_configure or AsyncMock(return_value={"success": True}),
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
