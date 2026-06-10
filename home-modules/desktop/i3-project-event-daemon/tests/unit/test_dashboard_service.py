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
        "current_ai_session_key": "",
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

    async def runtime_loader(params, *, close_windows: bool):
        assert close_windows is True
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
            "schema_version": "i3pm.focus_state.v1",
            "generation": generation,
            "current_session_key": "",
            "current_ai_session_key": "",
            "current_window_id": 0,
            "current_workspace_name": "",
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


@pytest.mark.asyncio
async def test_snapshot_uses_owned_generations() -> None:
    service = _service()
    service.snapshot_version = 9
    service.session_generation = 4
    service.display_generation = 3
    service.focus_generation = 2

    result = await service.snapshot({})

    assert result["schema_version"] == "i3pm.dashboard.v2"
    assert result["snapshot_version"] == 9
    assert result["session_generation"] == 4
    assert result["display_generation"] == 3
    assert result["focus_generation"] == 2
    assert result["focus_state"]["generation"] == 2
    assert result["dashboard_invariants"]["ok"] is True


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
        "current_ai_session_key",
        "worktrees",
    ]
