"""Unit tests for diagnostic RPC payload shaping."""

from __future__ import annotations

import importlib
import importlib.util
import json
import sys
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

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


diagnostic_module = importlib.import_module("i3_project_daemon.services.diagnostic_service")
DiagnosticService = diagnostic_module.DiagnosticService


class _EventBuffer:
    def __init__(self, events):
        self.events = events

    def get_recent(self, limit=50, event_type=None):
        events = self.events
        if event_type:
            events = [event for event in events if event.event_type == event_type]
        return events[:limit]


def _state_manager(*, window_map=None, windows=None):
    return SimpleNamespace(
        state=SimpleNamespace(
            window_map=window_map or {},
            windows=windows or {},
        )
    )


async def _noop_log(**_kwargs):
    return None


def _service(**overrides):
    defaults = {
        "state_manager": _state_manager(),
        "event_buffer": None,
        "i3_connection_provider": lambda: None,
        "daemon_status_service": SimpleNamespace(health_check=lambda: {"overall_status": "healthy"}),
        "get_workspaces": lambda: [],
        "log_ipc_event": _noop_log,
        "registry_path": Path("/missing/application-registry.json"),
    }
    defaults.update(overrides)
    return DiagnosticService(**defaults)


@pytest.mark.asyncio
async def test_window_environment_parses_i3pm_env(monkeypatch) -> None:
    monkeypatch.setattr(
        diagnostic_module,
        "read_process_environ",
        lambda _pid: {
            "I3PM_APP_ID": "codex",
            "I3PM_APP_NAME": "Codex",
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
            "I3PM_PROJECT_DIR": "/repo",
            "I3PM_SCOPE": "project",
            "I3PM_TARGET_WORKSPACE": "3",
            "I3PM_EXPECTED_CLASS": "Alacritty",
        },
    )
    service = _service()

    result = await service.window_environment({"pid": 123})

    assert result == {
        "app_id": "codex",
        "app_name": "Codex",
        "project_name": "vpittamp/nixos-config:main",
        "project_dir": "/repo",
        "scope": "project",
        "target_workspace": 3,
        "expected_class": "Alacritty",
    }


@pytest.mark.asyncio
async def test_workspace_rule_reads_registry_and_logs(tmp_path) -> None:
    registry_path = tmp_path / "application-registry.json"
    registry_path.write_text(json.dumps({
        "codex": {
            "expected_class": "Alacritty",
            "aliases": ["codex-cli"],
            "preferred_workspace": 2,
            "fallback_behavior": "current",
            "display_name": "Codex",
        }
    }))
    logged = []

    async def log_event(**kwargs):
        logged.append(kwargs)

    service = _service(registry_path=registry_path, log_ipc_event=log_event)

    result = await service.workspace_rule({"app_name": "codex"})

    assert result == {
        "app_identifier": "Alacritty",
        "matching_strategy": "normalized",
        "aliases": ["codex-cli"],
        "target_workspace": 2,
        "fallback_behavior": "current",
        "app_name": "codex",
        "description": "Codex",
    }
    assert logged[0]["event_type"] == "get_workspace_rule"
    assert logged[0]["params"] == {"app_name": "codex"}


@pytest.mark.asyncio
async def test_validate_state_reports_workspace_mismatch() -> None:
    workspace = SimpleNamespace(num=2)
    i3_window = SimpleNamespace(id=42, workspace=lambda: workspace)
    tree = SimpleNamespace(leaves=lambda: [i3_window])
    connection = SimpleNamespace(is_connected=True, get_tree=lambda: tree)

    async def get_tree():
        return tree

    connection.get_tree = get_tree
    service = _service(
        state_manager=_state_manager(
            window_map={42: SimpleNamespace(workspace_number=1)}
        ),
        i3_connection_provider=lambda: connection,
    )

    result = await service.validate_state()

    assert result["total_windows_checked"] == 1
    assert result["windows_inconsistent"] == 1
    assert result["is_consistent"] is False
    assert result["mismatches"] == [{
        "window_id": 42,
        "property_name": "workspace",
        "daemon_value": "1",
        "i3_value": "2",
        "severity": "warning",
    }]


@pytest.mark.asyncio
async def test_recent_events_formats_and_validates_limit() -> None:
    event = SimpleNamespace(
        event_id="evt-1",
        event_type="window::focus",
        timestamp=datetime(2026, 1, 1, 12, 0, 0),
        source="i3",
        window_id=42,
        window_class="Alacritty",
        window_title="Codex",
        workspace_name="2",
        project_name="vpittamp/nixos-config:main",
        processing_duration_ms=3.5,
        error=None,
    )
    service = _service(event_buffer=_EventBuffer([event]))

    result = await service.recent_events({"limit": 10, "event_type": "window::focus"})

    assert result == [{
        "event_id": "evt-1",
        "event_type": "window::focus",
        "timestamp": "2026-01-01T12:00:00",
        "source": "i3",
        "window_id": 42,
        "window_class": "Alacritty",
        "window_title": "Codex",
        "workspace_name": "2",
        "project_name": "vpittamp/nixos-config:main",
        "processing_duration_ms": 3.5,
        "error": None,
    }]

    with pytest.raises(RuntimeError, match="Invalid limit"):
        await service.recent_events({"limit": 501})


@pytest.mark.asyncio
async def test_report_combines_health_i3_state_and_optional_sections() -> None:
    tree = SimpleNamespace(leaves=lambda: [object(), object()])

    async def get_tree():
        return tree

    async def get_outputs():
        return [SimpleNamespace(active=True), SimpleNamespace(active=False)]

    async def get_workspaces():
        return [SimpleNamespace(name="1"), SimpleNamespace(name="2")]

    connection = SimpleNamespace(
        is_connected=lambda: True,
        get_tree=get_tree,
        get_outputs=get_outputs,
    )
    event = SimpleNamespace(
        event_id="evt-1",
        event_type="tick::barrier",
        timestamp=None,
        source="daemon",
        window_id=None,
        window_class=None,
        window_title=None,
        workspace_name=None,
        project_name=None,
        processing_duration_ms=None,
        error=None,
    )
    service = _service(
        state_manager=_state_manager(
            windows={7: SimpleNamespace(window_class="Alacritty", workspace_number=2)}
        ),
        event_buffer=_EventBuffer([event]),
        i3_connection_provider=lambda: connection,
        get_workspaces=get_workspaces,
    )

    result = await service.report({"include_windows": True, "include_events": True})

    assert result["overall_status"] == "healthy"
    assert result["i3_ipc_state"] == {
        "total_windows": 2,
        "total_workspaces": 2,
        "total_outputs": 1,
    }
    assert result["tracked_windows"] == [{
        "window_id": 7,
        "window_class": "Alacritty",
        "workspace": 2,
    }]
    assert result["recent_events"][0]["event_id"] == "evt-1"
