"""Unit tests for dashboard snapshot/event orchestration."""

from __future__ import annotations

import importlib
import importlib.util
import json
import sys
from pathlib import Path

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


dashboard_service_module = importlib.import_module("i3_project_daemon.services.dashboard_service")

DashboardService = dashboard_service_module.DashboardService


class FakeWriter:
    def __init__(self) -> None:
        self.lines: list[bytes] = []

    def write(self, data: bytes) -> None:
        self.lines.append(data)

    async def drain(self) -> None:
        return None


def _runtime_snapshot() -> dict:
    return {
        "active_project": None,
        "active_context": {},
        "active_terminal": {},
        "outputs": [],
        "active_outputs": [],
        "tracked_windows": [],
        "total_windows": 0,
        "state_health": {},
        "launch_stats": {},
        "scratchpad": {},
        "current_session_key": "",
        "herdr": {
            "herdr_generation": 0,
            "local_herdr_generation": 0,
            "remote_herdr_generation": {},
            "status": {},
            "workspaces": [],
            "tabs": [],
            "panes": [],
            "agents": [],
            "errors": [],
        },
    }


def _service(*, invalidations: list[str] | None = None) -> DashboardService:
    invalidations = invalidations if invalidations is not None else []

    async def runtime_loader(params):
        assert isinstance(params, dict)
        return _runtime_snapshot(), [], {}

    async def display_snapshot():
        return {"outputs": [], "display_generation": 0, "snapshot_version": 0}

    return DashboardService(
        runtime_loader=runtime_loader,
        display_snapshot=display_snapshot,
        build_projects=lambda runtime, sessions: [],
        build_worktrees=lambda runtime: _empty_worktrees(),
        build_focus_state=lambda runtime, sessions, *, generation: {
            "schema_version": "i3pm.focus_state.v2",
            "generation": generation,
            "current_session_key": "",
            "current_window_id": 0,
            "current_workspace_name": "",
            "current_herdr_pane_id": "",
            "current_herdr_host": "",
            "pending_intent_id": "",
        },
        build_lightweight_focus_state=lambda *, generation, base_focus_state=None: {
            "schema_version": "i3pm.focus_state.v2",
            "generation": generation,
            "current_session_key": str((base_focus_state or {}).get("current_session_key") or ""),
            "current_window_id": int((base_focus_state or {}).get("current_window_id") or 0),
            "current_workspace_name": "fast",
            "current_herdr_pane_id": "",
            "current_herdr_host": "",
            "pending_intent_id": "",
        },
        build_herdr_spaces=lambda herdr_snapshot, sessions: [],
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: invalidations.append("worktree"),
        timestamp=lambda: 42.0,
    )


async def _empty_worktrees() -> list[dict]:
    return []


async def _async_value(value: dict) -> dict:
    return value


@pytest.mark.asyncio
async def test_snapshot_uses_owned_generations() -> None:
    service = _service()
    service.snapshot_version = 9
    service.session_generation = 4
    service.display_generation = 3
    service.focus_generation = 2

    result = await service.snapshot({})

    assert result["schema_version"] == "i3pm.dashboard.v2"
    assert result["generation"] == 9
    assert result["snapshot_version"] == 9
    assert result["session_generation"] == 4
    assert result["display_generation"] == 3
    assert result["focus_generation"] == 2
    assert result["focus_state"]["generation"] == 2
    assert result["dashboard_invariants"]["ok"] is True

    health = await service.validate({})
    assert health["schema_version"] == "i3pm.dashboard.v2"
    assert health["focus_schema_version"] == "i3pm.focus_state.v2"
    assert health["generation"] == 9


@pytest.mark.asyncio
async def test_notify_state_change_advances_generations_and_notifies_subscribers() -> None:
    invalidations: list[str] = []
    service = _service(invalidations=invalidations)
    writer = FakeWriter()
    service.subscribe(writer)  # type: ignore[arg-type]

    await service.notify_state_change("worktree_changed")

    assert service.snapshot_version == 1
    assert service.session_generation == 1
    assert service.focus_generation == 1
    assert service.display_generation == 0
    assert invalidations == ["worktree"]
    assert len(writer.lines) == 1

    notification = json.loads(writer.lines[0].decode("utf-8"))
    assert notification["method"] == "session.changed"
    assert notification["params"]["generation"] == 1
    assert notification["params"]["changed_keys"] == [
        "focus_state",
        "active_ai_sessions",
        "worktrees",
    ]


@pytest.mark.asyncio
async def test_focus_event_payload_uses_lightweight_focus_state_without_snapshot_reload() -> None:
    runtime_loads = 0

    async def runtime_loader(params):
        nonlocal runtime_loads
        runtime_loads += 1
        assert isinstance(params, dict)
        return _runtime_snapshot(), [], {}

    service = DashboardService(
        runtime_loader=runtime_loader,
        display_snapshot=lambda: _async_value({"outputs": []}),
        build_projects=lambda runtime, sessions: [],
        build_worktrees=lambda runtime: _empty_worktrees(),
        build_focus_state=lambda runtime, sessions, *, generation: {
            "schema_version": "i3pm.focus_state.v2",
            "generation": generation,
            "current_session_key": "",
            "current_window_id": 1,
            "current_workspace_name": "1",
            "current_herdr_pane_id": "",
            "current_herdr_host": "",
            "pending_intent_id": "",
        },
        build_lightweight_focus_state=lambda *, generation, base_focus_state=None: {
            "schema_version": "i3pm.focus_state.v2",
            "generation": generation,
            "current_session_key": str((base_focus_state or {}).get("current_session_key") or ""),
            "current_window_id": int((base_focus_state or {}).get("current_window_id") or 0),
            "current_workspace_name": "2",
            "current_herdr_pane_id": "",
            "current_herdr_host": "",
            "pending_intent_id": "",
        },
        build_herdr_spaces=lambda herdr_snapshot, sessions: [],
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: None,
        timestamp=lambda: 42.0,
    )

    service.snapshot_version = 7
    service.focus_generation = 3
    await service.snapshot({})
    assert runtime_loads == 1

    payload = await service.event_payload(["focus_state"])

    assert runtime_loads == 1
    assert payload["generation"] == 7
    assert payload["focus_state"]["generation"] == 3
    assert payload["focus_state"]["current_session_key"] == ""
    assert payload["focus_state"]["current_window_id"] == 1
    assert payload["focus_state"]["current_workspace_name"] == "2"


@pytest.mark.asyncio
async def test_focus_event_payload_updates_session_rows_without_snapshot_reload() -> None:
    runtime_loads = 0

    async def runtime_loader(params):
        nonlocal runtime_loads
        runtime_loads += 1
        return _runtime_snapshot(), [], {}

    service = DashboardService(
        runtime_loader=runtime_loader,
        display_snapshot=lambda: _async_value({"outputs": []}),
        build_projects=lambda runtime, sessions: [],
        build_worktrees=lambda runtime: _empty_worktrees(),
        build_focus_state=lambda runtime, sessions, *, generation: {
            "schema_version": "i3pm.focus_state.v2",
            "generation": generation,
            "current_session_key": "",
            "current_window_id": 0,
            "current_workspace_name": "",
            "current_herdr_pane_id": "",
            "current_herdr_host": "",
            "pending_intent_id": "",
        },
        build_lightweight_focus_state=lambda *, generation, base_focus_state=None: {
            "schema_version": "i3pm.focus_state.v2",
            "generation": generation,
            "current_session_key": "session-b",
            "current_window_id": 0,
            "current_workspace_name": "2",
            "current_herdr_pane_id": str((base_focus_state or {}).get("current_herdr_pane_id") or ""),
            "current_herdr_host": str((base_focus_state or {}).get("current_herdr_host") or ""),
            "pending_intent_id": "",
        },
        build_herdr_spaces=lambda herdr_snapshot, sessions: [],
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: None,
        timestamp=lambda: 42.0,
    )
    service.snapshot_version = 10
    service.focus_generation = 6
    service._last_snapshot = {
        "status": "ok",
        "schema_version": "i3pm.dashboard.v2",
        "focus_state": {
            "current_session_key": "session-a",
            "current_herdr_pane_id": "pane-a",
            "current_herdr_host": "ryzen",
            "active_session": {"session_key": "session-a"},
        },
        "active_ai_sessions": [
            {
                "source": "herdr",
                "session_key": "session-a",
                "herdr_session": "session-a",
                "pane_id": "pane-a",
                "host_name": "ryzen",
                "focused": True,
                "is_current_window": True,
                "pane_active": True,
                "window_active": True,
            },
            {
                "source": "herdr",
                "session_key": "session-b",
                "herdr_session": "session-b",
                "pane_id": "pane-b",
                "host_name": "ryzen",
                "tool": "codex",
                "focused": False,
                "is_current_window": False,
                "pane_active": False,
                "window_active": False,
            },
        ],
    }

    payload = await service.event_payload(["focus_state"])

    assert runtime_loads == 0
    assert payload["focus_state"]["current_session_key"] == "session-b"
    assert payload["focus_state"]["current_herdr_pane_id"] == "pane-b"
    assert payload["focus_state"]["active_session"]["session_key"] == "session-b"
    assert [row["is_current_window"] for row in payload["active_ai_sessions"]] == [False, True]
    assert [row["focused"] for row in payload["active_ai_sessions"]] == [False, True]
