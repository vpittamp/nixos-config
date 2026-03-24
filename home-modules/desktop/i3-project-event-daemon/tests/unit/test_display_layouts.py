"""Unit tests for daemon-backed display layout metadata and application."""

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


ipc_server_module = importlib.import_module("i3_project_daemon.ipc_server")
monitor_profile_service_module = importlib.import_module("i3_project_daemon.monitor_profile_service")
monitor_profile_module = importlib.import_module("i3_project_daemon.models.monitor_profile")
monitor_config_module = importlib.import_module("i3_project_daemon.models.monitor_config")
workspace_manager_module = importlib.import_module("i3_project_daemon.workspace_manager")
output_state_manager_module = importlib.import_module("i3_project_daemon.output_state_manager")

IPCServer = ipc_server_module.IPCServer
MonitorProfileService = monitor_profile_service_module.MonitorProfileService
MonitorProfile = monitor_profile_module.MonitorProfile
HybridMonitorProfile = monitor_profile_module.HybridMonitorProfile
OutputStatesFile = monitor_config_module.OutputStatesFile


class DummyLaunchRegistry:
    def get_stats(self):
        return SimpleNamespace(total_pending=0)


class DummyStateManager:
    def __init__(self):
        self.state = SimpleNamespace(
            active_project="global",
            window_map={},
            launch_registry=DummyLaunchRegistry(),
        )
        self.launch_registry = self.state.launch_registry

    async def get_active_project(self):
        return self.state.active_project

    async def remove_window(self, _window_id: int):
        return None


def make_output(name: str, *, active: bool = True, focused: bool = False, x: int = 0, y: int = 0, width: int = 1920, height: int = 1080):
    return SimpleNamespace(
        name=name,
        active=active,
        focused=focused,
        rect=SimpleNamespace(x=x, y=y, width=width, height=height),
    )


@pytest.mark.asyncio
async def test_display_snapshot_exposes_layout_options(monkeypatch):
    server = IPCServer(DummyStateManager())
    server.i3_connection = SimpleNamespace(
        conn=SimpleNamespace(
            get_outputs=AsyncMock(return_value=[
                make_output("DP-1", focused=True, x=1920, width=1920, height=1200),
                make_output("DP-2", x=3840, width=1920, height=1200),
                make_output("HDMI-A-1", x=0, width=1920, height=1080),
            ]),
        ),
    )

    monkeypatch.setattr(
        output_state_manager_module,
        "load_output_states",
        lambda: SimpleNamespace(is_output_enabled=lambda _name: True),
    )

    default_profile = MonitorProfile(**{
        "name": "default",
        "description": "Full Ryzen desktop layout",
        "default": True,
        "outputs": [
            {"name": "DP-1", "enabled": True, "position": {"x": 1920, "y": 0, "width": 1920, "height": 1200}},
            {"name": "DP-2", "enabled": True, "position": {"x": 3840, "y": 0, "width": 1920, "height": 1200}},
            {"name": "HDMI-A-1", "enabled": True, "position": {"x": 0, "y": 0, "width": 1920, "height": 1080}},
        ],
    })
    single_profile = MonitorProfile(**{
        "name": "single",
        "description": "Moonlight single-monitor mode",
        "outputs": [
            {"name": "DP-1", "enabled": True, "position": {"x": 0, "y": 0, "width": 1920, "height": 1200}},
            {"name": "DP-2", "enabled": False, "position": {"x": 3840, "y": 0, "width": 1920, "height": 1200}},
            {"name": "HDMI-A-1", "enabled": False, "position": {"x": 0, "y": 0, "width": 1920, "height": 1080}},
        ],
    })

    server.monitor_profile_service = SimpleNamespace(
        get_current_profile=lambda: "default",
        list_profiles=lambda: ["default", "single"],
        get_profile=lambda name: {"default": default_profile, "single": single_profile}[name],
    )

    snapshot = await server._display_snapshot({})

    assert snapshot["current_layout"] == "default"
    assert snapshot["layouts"] == ["default", "single"]
    assert snapshot["layout_options"] == [
        {
            "name": "default",
            "label": "Default",
            "description": "Full Ryzen desktop layout",
            "output_names": ["DP-1", "DP-2", "HDMI-A-1"],
            "output_count": 3,
            "default": True,
            "current": True,
        },
        {
            "name": "single",
            "label": "Single",
            "description": "Moonlight single-monitor mode",
            "output_names": ["DP-1"],
            "output_count": 1,
            "default": False,
            "current": False,
        },
    ]


@pytest.mark.asyncio
async def test_handle_profile_change_disables_outputs_omitted_from_profile(monkeypatch):
    service = MonitorProfileService()
    service._profiles = {
        "default": MonitorProfile(**{
            "name": "default",
            "description": "Full Ryzen desktop layout",
            "default": True,
            "outputs": [
                {"name": "HDMI-A-1", "enabled": True, "position": {"x": 0, "y": 0, "width": 1920, "height": 1080}},
                {"name": "DP-1", "enabled": True, "position": {"x": 1920, "y": 0, "width": 1920, "height": 1200}},
                {"name": "DP-2", "enabled": True, "position": {"x": 3840, "y": 0, "width": 1920, "height": 1200}},
            ],
        }),
        "single": MonitorProfile(**{
            "name": "single",
            "description": "Moonlight single-monitor mode",
            "outputs": [
                {"name": "DP-1", "enabled": True, "position": {"x": 0, "y": 0, "width": 1920, "height": 1200}},
            ],
        }),
    }
    service._current_profile = "default"
    service._send_notification = AsyncMock(return_value=None)

    saved_states = OutputStatesFile()

    monkeypatch.setattr(
        monitor_profile_service_module,
        "load_output_states",
        lambda: saved_states,
    )
    monkeypatch.setattr(
        monitor_profile_service_module,
        "save_output_states",
        lambda states: True,
    )
    monkeypatch.setattr(
        workspace_manager_module,
        "assign_workspaces_with_monitor_roles",
        AsyncMock(return_value=None),
    )

    commands = []

    async def command(cmd: str):
        commands.append(cmd)
        return [SimpleNamespace(success=True, error="")]

    conn = SimpleNamespace(
        get_outputs=AsyncMock(return_value=[
            make_output("HDMI-A-1", x=0, width=1920, height=1080),
            make_output("DP-1", focused=True, x=1920, width=1920, height=1200),
            make_output("DP-2", x=3840, width=1920, height=1200),
        ]),
        get_workspaces=AsyncMock(return_value=[
            SimpleNamespace(name="1", output="HDMI-A-1"),
            SimpleNamespace(name="2", output="DP-1"),
            SimpleNamespace(name="3", output="DP-2"),
        ]),
        command=command,
    )

    changed = await service.handle_profile_change(conn, "single")

    assert changed is True
    assert saved_states.is_output_enabled("DP-1") is True
    assert saved_states.is_output_enabled("DP-2") is False
    assert saved_states.is_output_enabled("HDMI-A-1") is False
    assert "workspace 1" in commands
    assert "move workspace to output DP-1" in commands
    assert "workspace 3" in commands
    assert commands.count("move workspace to output DP-1") == 2
    assert "output HDMI-A-1 disable" in commands
    assert "output DP-2 disable" in commands
    assert "output DP-1 enable mode 1920x1200 position 0 0" in commands


@pytest.mark.asyncio
async def test_handle_profile_change_uses_hybrid_profiles_without_hostname_gate(monkeypatch):
    service = MonitorProfileService()
    service._profiles = {
        "local+1vnc": MonitorProfile(**{
            "name": "local+1vnc",
            "description": "ThinkPad panel plus one virtual display",
            "outputs": [
                {"name": "eDP-1", "enabled": True, "position": {"x": 0, "y": 0, "width": 1920, "height": 1200}},
                {"name": "HEADLESS-1", "enabled": True, "position": {"x": 1536, "y": 0, "width": 1920, "height": 1200}},
                {"name": "HEADLESS-2", "enabled": False, "position": {"x": 3456, "y": 0, "width": 1920, "height": 1200}},
            ],
        }),
    }
    service._hybrid_profiles = {
        "local+1vnc": HybridMonitorProfile(**{
            "name": "local+1vnc",
            "description": "ThinkPad panel plus one virtual display",
            "outputs": [
                {
                    "name": "eDP-1",
                    "type": "physical",
                    "enabled": True,
                    "position": {"x": 0, "y": 0, "width": 1920, "height": 1200},
                    "scale": 1.25,
                },
                {
                    "name": "HEADLESS-1",
                    "type": "virtual",
                    "enabled": True,
                    "position": {"x": 1536, "y": 0, "width": 1920, "height": 1200},
                    "scale": 1.0,
                    "vnc_port": 5900,
                },
                {
                    "name": "HEADLESS-2",
                    "type": "virtual",
                    "enabled": False,
                    "position": {"x": 3456, "y": 0, "width": 1920, "height": 1200},
                    "scale": 1.0,
                    "vnc_port": 5901,
                },
            ],
            "workspace_assignments": [
                {"output": "eDP-1", "workspaces": [1, 2, 6, 7, 8, 9]},
                {"output": "HEADLESS-1", "workspaces": [3, 4, 5]},
            ],
        }),
    }
    service._current_profile = "local-only"
    service._send_notification = AsyncMock(return_value=None)
    service.create_virtual_output = AsyncMock(return_value="HEADLESS-1")
    service.manage_wayvnc_service = AsyncMock(return_value=True)
    service.reassign_workspaces = AsyncMock(return_value=True)
    service.migrate_workspaces_from_disabled_outputs = AsyncMock(return_value=True)

    saved_states = OutputStatesFile()

    monkeypatch.setattr(
        monitor_profile_service_module,
        "load_output_states",
        lambda: saved_states,
    )
    monkeypatch.setattr(
        monitor_profile_service_module,
        "save_output_states",
        lambda states: True,
    )

    commands = []

    async def command(cmd: str):
        commands.append(cmd)
        return [SimpleNamespace(success=True, error="")]

    conn = SimpleNamespace(
        get_outputs=AsyncMock(side_effect=[
            [make_output("eDP-1", focused=True, x=0, width=1920, height=1200)],
            [
                make_output("eDP-1", focused=True, x=0, width=1920, height=1200),
                make_output("HEADLESS-1", x=1536, width=1920, height=1200),
            ],
        ]),
        command=command,
    )

    changed = await service.handle_profile_change(conn, "local+1vnc")

    assert changed is True
    assert service.create_virtual_output.await_count == 1
    assert service.manage_wayvnc_service.await_args_list[0].args == ("HEADLESS-1", "start")
    assert saved_states.is_output_enabled("eDP-1") is True
    assert saved_states.is_output_enabled("HEADLESS-1") is True
    assert saved_states.is_output_enabled("HEADLESS-2") is False
    assert "output eDP-1 mode 1920x1200 position 0 0 scale 1.25" in commands
    assert "output HEADLESS-1 mode 1920x1200 position 1536 0 scale 1.0" in commands


@pytest.mark.asyncio
async def test_hybrid_reassign_preserves_workspaces_on_enabled_outputs():
    service = MonitorProfileService()
    profile = HybridMonitorProfile(**{
        "name": "local+1vnc",
        "description": "ThinkPad panel plus one virtual display",
        "outputs": [
            {
                "name": "eDP-1",
                "type": "physical",
                "enabled": True,
                "position": {"x": 0, "y": 0, "width": 1920, "height": 1200},
                "scale": 1.25,
            },
            {
                "name": "HEADLESS-1",
                "type": "virtual",
                "enabled": True,
                "position": {"x": 1536, "y": 0, "width": 1920, "height": 1200},
                "scale": 1.0,
                "vnc_port": 5900,
            },
            {
                "name": "HEADLESS-2",
                "type": "virtual",
                "enabled": False,
                "position": {"x": 3456, "y": 0, "width": 1920, "height": 1200},
                "scale": 1.0,
                "vnc_port": 5901,
            },
        ],
        "workspace_assignments": [
            {"output": "eDP-1", "workspaces": [1, 2, 6, 7, 8, 9]},
            {"output": "HEADLESS-1", "workspaces": [3, 4, 5]},
        ],
    })

    move_mock = AsyncMock(return_value=True)
    service._move_workspace_to_output = move_mock

    conn = SimpleNamespace(
        get_workspaces=AsyncMock(return_value=[
            SimpleNamespace(name="1", output="HEADLESS-1"),
            SimpleNamespace(name="3", output="eDP-1"),
            SimpleNamespace(name="50", output="HEADLESS-2"),
        ]),
    )

    changed = await service.reassign_workspaces(conn, profile)

    assert changed is True
    move_mock.assert_awaited_once_with(conn, "50", "HEADLESS-1")


@pytest.mark.asyncio
async def test_workspace_move_to_output_uses_runtime_move_semantics():
    server = IPCServer(DummyStateManager())

    commands = []

    async def command(cmd: str):
        commands.append(cmd)
        return [SimpleNamespace(success=True, error="")]

    server.i3_connection = SimpleNamespace(conn=SimpleNamespace(command=command))
    server._send_tick_barrier = AsyncMock(return_value=None)

    result = await server._workspace_move_to_output({"workspace": "7", "output_name": "DP-1"})

    assert result == {"success": True, "workspace": "7", "output_name": "DP-1"}
    assert commands == ["workspace 7", "move workspace to output DP-1"]
    server._send_tick_barrier.assert_awaited_once_with("i3pm:workspace-output:7:DP-1")
