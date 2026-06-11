"""Unit tests for legacy monitor state RPC payload shaping."""

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


monitor_state_module = importlib.import_module("i3_project_daemon.services.monitor_state_service")
models_module = importlib.import_module("i3_project_daemon.models")

MonitorRole = models_module.MonitorRole
MonitorStateService = monitor_state_module.MonitorStateService


class _FakeDistribution:
    def model_dump(self):
        return {"one": {}, "two": {}, "three": {}}


class _FakeConfig:
    distribution = _FakeDistribution()
    workspace_preferences = {2: "secondary"}

    def model_dump(self):
        return {
            "version": "1.0",
            "workspace_preferences": {2: "secondary"},
        }


class _FakeManager:
    DEFAULT_CONFIG_PATH = Path("/default/workspace-monitor-mapping.json")
    last_validate_path = None

    def __init__(self) -> None:
        self.config_path = Path("/tmp/workspace-monitor-mapping.json")
        self.load_calls = []

    def load_config(self, force_reload: bool = False):
        self.load_calls.append(force_reload)
        return _FakeConfig()

    @staticmethod
    def validate_config_file(config_path: Path):
        _FakeManager.last_validate_path = config_path
        issue = SimpleNamespace(model_dump=lambda: {"severity": "warning"})
        config = SimpleNamespace(model_dump=lambda: {"version": "1.0"})
        return SimpleNamespace(valid=True, issues=[issue], config=config)

    def get_workspace_distribution(self, _monitor_count: int):
        return {
            MonitorRole.PRIMARY: [1],
            MonitorRole.SECONDARY: [2, 3],
        }


class _FakeManagerFactory:
    last_instance = None
    DEFAULT_CONFIG_PATH = _FakeManager.DEFAULT_CONFIG_PATH

    def __call__(self):
        self.last_instance = _FakeManager()
        return self.last_instance

    @staticmethod
    def validate_config_file(config_path: Path):
        return _FakeManager.validate_config_file(config_path)


def _service(**overrides):
    params = {
        "i3_connection_provider": lambda: SimpleNamespace(conn=SimpleNamespace()),
        "monitor_config_manager_cls": _FakeManagerFactory(),
    }
    params.update(overrides)
    return MonitorStateService(**params)


@pytest.mark.asyncio
async def test_monitor_config_validate_and_reload_log_queries() -> None:
    logged = []
    manager_factory = _FakeManagerFactory()

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _service(
        monitor_config_manager_cls=manager_factory,
        log_ipc_event=log_ipc_event,
    )

    config = await service.get_monitor_config()
    validation = await service.validate_monitor_config({"config_path": "/tmp/custom.json"})
    reload_result = await service.reload_monitor_config()

    assert config == {"version": "1.0", "workspace_preferences": {2: "secondary"}}
    assert validation == {
        "valid": True,
        "issues": [{"severity": "warning"}],
        "config": {"version": "1.0"},
    }
    assert _FakeManager.last_validate_path == Path("/tmp/custom.json")
    assert reload_result["success"] is True
    assert reload_result["changes"] == [
        "Configuration reloaded from /tmp/workspace-monitor-mapping.json",
        "Distribution rules updated for 3 monitor configurations",
        "Workspace preferences: 1 entries",
    ]
    assert [entry["event_type"] for entry in logged] == [
        "query::monitor_config",
        "config::validate_monitor",
        "config::reload_monitor",
    ]
    assert manager_factory.last_instance.load_calls == [True]


@pytest.mark.asyncio
async def test_reassign_workspaces_migrates_disabled_outputs_and_counts_changes() -> None:
    outputs = [
        SimpleNamespace(name="eDP-1", active=True),
        SimpleNamespace(name="HDMI-A-1", active=True),
    ]
    i3_connection = SimpleNamespace(
        conn=SimpleNamespace(),
        get_outputs=AsyncMock(return_value=outputs),
    )
    profile_service = SimpleNamespace(
        migrate_workspaces_from_disabled_outputs=AsyncMock(return_value=None)
    )
    workspace_snapshots = [
        [
            SimpleNamespace(name="1", output="HDMI-A-1"),
            SimpleNamespace(name="2", output="eDP-1"),
        ],
        [
            SimpleNamespace(name="1", output="eDP-1"),
            SimpleNamespace(name="2", output="eDP-1"),
        ],
    ]

    async def get_workspaces():
        return workspace_snapshots.pop(0)

    service = _service(
        i3_connection_provider=lambda: i3_connection,
        monitor_profile_service_provider=lambda: profile_service,
        sway_workspaces_provider=get_workspaces,
        load_output_states_fn=lambda: SimpleNamespace(
            is_output_enabled=lambda name: name == "eDP-1"
        ),
    )

    result = await service.reassign_workspaces({"dry_run": False})

    assert result == {"success": True, "assignments_made": 1, "errors": []}
    profile_service.migrate_workspaces_from_disabled_outputs.assert_awaited_once_with(
        i3_connection.conn,
        ["HDMI-A-1"],
        fallback_output="eDP-1",
    )


@pytest.mark.asyncio
async def test_get_monitors_shapes_dataclass_monitors() -> None:
    async def get_monitor_configs(_i3, _manager):
        return [
            SimpleNamespace(
                name="eDP-1",
                active=True,
                primary=True,
                role="primary",
                rect={"x": 0, "y": 0, "width": 1920, "height": 1200},
            )
        ]

    service = _service(get_monitor_configs_fn=get_monitor_configs)

    result = await service.get_monitors()

    assert result == [
        {
            "name": "eDP-1",
            "active": True,
            "primary": True,
            "role": MonitorRole.PRIMARY,
            "rect": {"x": 0, "y": 0, "width": 1920, "height": 1200},
            "current_workspace": None,
            "make": None,
            "model": None,
            "serial": None,
        }
    ]


@pytest.mark.asyncio
async def test_get_workspaces_resolves_explicit_and_default_targets() -> None:
    conn = SimpleNamespace(
        get_workspaces=AsyncMock(return_value=[
            SimpleNamespace(num=1, output="eDP-1", visible=True),
            SimpleNamespace(num=2, output="HDMI-A-1", visible=False),
        ])
    )

    async def get_monitor_configs(_i3, _manager):
        return [
            SimpleNamespace(name="eDP-1", role="primary"),
            SimpleNamespace(name="HDMI-A-1", role="secondary"),
        ]

    service = _service(
        i3_connection_provider=lambda: SimpleNamespace(conn=conn),
        get_monitor_configs_fn=get_monitor_configs,
    )

    result = await service.get_workspaces()

    assert result == [
        {
            "workspace_num": 1,
            "output_name": "eDP-1",
            "target_role": MonitorRole.PRIMARY,
            "target_output": "eDP-1",
            "source": "default",
            "visible": True,
            "window_count": 0,
        },
        {
            "workspace_num": 2,
            "output_name": "HDMI-A-1",
            "target_role": MonitorRole.SECONDARY,
            "target_output": "HDMI-A-1",
            "source": "explicit",
            "visible": False,
            "window_count": 0,
        },
    ]


@pytest.mark.asyncio
async def test_get_system_state_combines_monitor_and_workspace_payloads(monkeypatch) -> None:
    service = _service()
    monkeypatch.setattr(
        service,
        "get_monitors",
        AsyncMock(return_value=[
            {
                "name": "eDP-1",
                "active": True,
                "primary": True,
                "role": "primary",
                "rect": {"x": 0, "y": 0, "width": 1920, "height": 1200},
                "current_workspace": None,
            }
        ]),
    )
    monkeypatch.setattr(
        service,
        "get_workspaces",
        AsyncMock(return_value=[
            {
                "workspace_num": 1,
                "output_name": "eDP-1",
                "target_role": "primary",
                "target_output": "eDP-1",
                "source": "default",
                "visible": True,
                "window_count": 0,
            }
        ]),
    )

    result = await service.get_system_state()

    assert result["active_monitor_count"] == 1
    assert result["primary_output"] == "eDP-1"
    assert result["monitors"][0]["name"] == "eDP-1"
    assert result["workspaces"][0]["workspace_num"] == 1
    assert result["last_updated"] > 0
