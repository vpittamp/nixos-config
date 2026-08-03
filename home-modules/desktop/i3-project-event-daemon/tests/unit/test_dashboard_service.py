"""Unit tests for dashboard snapshot/event orchestration."""

from __future__ import annotations

import asyncio
import importlib
import importlib.util
import json
import sys
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
    # A worktree event still ships the array; only the far more frequent
    # agent-session ticks drop it (see test_dashboard_model.py).
    assert notification["params"]["changed_keys"] == [
        "focus_state",
        "active_ai_sessions",
        "worktrees",
    ]


@pytest.mark.asyncio
async def test_concurrent_notify_state_change_writes_generations_in_order() -> None:
    # Without serialization a slower payload build lets a later caller write a
    # higher generation first; clients then drop the fresher data or reset on
    # phantom generation gaps.
    service = _service()
    writer = FakeWriter()
    service.subscribe(writer)  # type: ignore[arg-type]

    original_event_payload = service.event_payload
    delays = iter([0.05, 0.0])

    async def delayed_event_payload(changed_keys):
        await asyncio.sleep(next(delays, 0.0))
        return await original_event_payload(changed_keys)

    service.event_payload = delayed_event_payload  # type: ignore[method-assign]

    await asyncio.gather(
        service.notify_state_change("worktree_changed"),
        service.notify_state_change("worktree_changed"),
    )

    generations = [
        json.loads(line.decode("utf-8"))["params"]["generation"]
        for line in writer.lines
    ]
    assert generations == [1, 2]


@pytest.mark.asyncio
async def test_notify_state_change_closes_evicted_slow_subscriber() -> None:
    class SlowWriter(FakeWriter):
        def __init__(self) -> None:
            super().__init__()
            self.closed = False
            self.transport = SimpleNamespace(get_write_buffer_size=lambda: 2_000_000)

        def close(self) -> None:
            self.closed = True

    service = _service()
    slow_writer = SlowWriter()
    healthy_writer = FakeWriter()
    service.subscribers = {slow_writer, healthy_writer}  # type: ignore[assignment]

    await service.notify_state_change("focus_changed")

    # The evicted writer is closed so a blocked `dashboard watch` reader sees
    # EOF and reconnects; the healthy subscriber still received the event.
    assert service.subscribers == {healthy_writer}
    assert slow_writer.closed is True
    assert len(healthy_writer.lines) == 1


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
                "herdr_focused": True,
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
                "herdr_focused": False,
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
    # `herdr_focused` is Herdr's own per-pane flag, not sway's: while `focused`
    # is re-derived from the new sway focus above, this one must ride through
    # the focus-only delta path verbatim. No Herdr snapshot is refetched here,
    # so if this block ever starts overwriting it the shell loses the only
    # record of which pane the user would return to.
    assert [row["herdr_focused"] for row in payload["active_ai_sessions"]] == [True, False]


@pytest.mark.asyncio
async def test_snapshot_keeps_herdr_focused_while_reauthorizing_sway_focus() -> None:
    # Mirror of the delta-path assertion above for the full snapshot build:
    # sessions_with_authoritative_focus rebuilds each row with dict(row) and
    # overwrites only the sway-authoritative fields, so `herdr_focused` must
    # survive that flatten unchanged.
    async def runtime_loader(params):
        return _runtime_snapshot(), [
            {
                "source": "herdr",
                "session_key": "session-a",
                "pane_id": "pane-a",
                "host_name": "ryzen",
                "focused": True,
                "herdr_focused": True,
                "is_current_window": True,
                "pane_active": True,
                "window_active": True,
            },
            {
                "source": "herdr",
                "session_key": "session-b",
                "pane_id": "pane-b",
                "host_name": "ryzen",
                "focused": False,
                "herdr_focused": False,
                "is_current_window": False,
                "pane_active": False,
                "window_active": False,
            },
        ], {}

    service = DashboardService(
        runtime_loader=runtime_loader,
        display_snapshot=lambda: _async_value({"outputs": []}),
        build_projects=lambda runtime, sessions: [],
        build_worktrees=lambda runtime: _empty_worktrees(),
        build_focus_state=lambda runtime, sessions, *, generation: {
            "schema_version": "i3pm.focus_state.v2",
            "generation": generation,
            "current_session_key": "session-b",
            "current_window_id": 0,
            "current_workspace_name": "",
            "current_herdr_pane_id": "pane-b",
            "current_herdr_host": "ryzen",
            "pending_intent_id": "",
        },
        build_herdr_spaces=lambda herdr_snapshot, sessions: [],
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: None,
        timestamp=lambda: 42.0,
    )

    payload = await service.snapshot({})

    rows = payload["active_ai_sessions"]
    assert [row["focused"] for row in rows] == [False, True]
    assert [row["is_current_window"] for row in rows] == [False, True]
    assert [row["herdr_focused"] for row in rows] == [True, False]


@pytest.mark.asyncio
async def test_duplicate_herdr_focused_rows_warn_without_failing_the_snapshot() -> None:
    # Two rows claiming Herdr's per-pane focus on one host would let the shell
    # advertise two return targets. That is worth flagging, but only as a
    # warning: raising it as an issue would flip the payload out of "ok" over a
    # cosmetic hint, exactly the regression remote_herdr_focus_mismatch was
    # downgraded to avoid.
    async def runtime_loader(params):
        return _runtime_snapshot(), [
            {
                "source": "herdr",
                "session_key": "session-a",
                "pane_id": "pane-a",
                "host_name": "ryzen",
                "focused": False,
                "herdr_focused": True,
            },
            {
                "source": "herdr",
                "session_key": "session-b",
                "pane_id": "pane-b",
                "host_name": "ryzen",
                "focused": False,
                "herdr_focused": True,
            },
        ], {}

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
        build_herdr_spaces=lambda herdr_snapshot, sessions: [],
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: None,
        timestamp=lambda: 42.0,
    )

    payload = await service.snapshot({})

    invariants = payload["dashboard_invariants"]
    assert "duplicate_herdr_focused_sessions" in invariants["warnings"]
    assert "duplicate_herdr_focused_sessions" not in invariants["issues"]
    assert payload["status"] == "ok"


@pytest.mark.asyncio
async def test_git_bearing_event_payload_keeps_hydrated_herdr_space_git_fields() -> None:
    runtime_params: list[dict] = []

    async def runtime_loader(params):
        runtime_params.append(dict(params))
        session = {
            "source": "herdr",
            "session_key": "session-a",
            "pane_id": "pane-a",
            "agent_status": "idle",
        }
        if not params.get("skip_git_hydration", False):
            session.update({
                "git_compact": "↓2",
                "git_freshness": "fresh",
                "git_snapshot": {"status_compact": "↓2", "behind": 2},
            })
        return _runtime_snapshot(), [session], {}

    def build_herdr_spaces(_herdr_snapshot, sessions):
        space = {
            "space_key": "space-a",
            "label": "stacks",
            "branch_label": "main",
        }
        for field in ("git_compact", "git_freshness", "git_snapshot"):
            if field in sessions[0]:
                space[field] = sessions[0][field]
        return [space]

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
        build_herdr_spaces=build_herdr_spaces,
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: None,
        timestamp=lambda: 42.0,
    )

    payload = await service.event_payload(["focus_state", "active_ai_sessions", "herdr"])

    assert runtime_params[-1] == {"skip_git_hydration": False}
    assert payload["active_ai_sessions"][0]["git_compact"] == "↓2"
    assert payload["herdr"]["spaces"][0]["git_compact"] == "↓2"
    assert payload["herdr"]["spaces"][0]["git_snapshot"]["behind"] == 2


@pytest.mark.asyncio
async def test_non_git_event_payload_keeps_skip_git_hydration_fast_path() -> None:
    runtime_params: list[dict] = []

    async def runtime_loader(params):
        runtime_params.append(dict(params))
        return _runtime_snapshot(), [], {}

    service = DashboardService(
        runtime_loader=runtime_loader,
        display_snapshot=lambda: _async_value({"outputs": []}),
        build_projects=lambda runtime, sessions: [{"project": "global"}],
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
        build_herdr_spaces=lambda herdr_snapshot, sessions: [],
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: None,
        timestamp=lambda: 42.0,
    )

    await service.event_payload(["focus_state", "projects", "tracked_windows"])

    assert runtime_params[-1] == {"skip_git_hydration": True}


@pytest.mark.asyncio
async def test_lightweight_focus_payload_retains_git_fields_on_session_rows() -> None:
    # skip_git_hydration builds ship session rows without git_* fields; those
    # rows become _last_snapshot, so focus-only events must not blank the git
    # chips — the fields carry over from the last hydrated snapshot.
    async def runtime_loader(params):
        session = {
            "source": "herdr",
            "session_key": "session-a",
            "pane_id": "pane-a",
            "agent_status": "idle",
        }
        if not params.get("skip_git_hydration", False):
            session.update({
                "git_state": "dirty",
                "git_compact": "● 2",
                "git_freshness": "fresh",
                "git_snapshot": {"dirty_count": 2, "status_compact": "● 2"},
            })
        return _runtime_snapshot(), [session], {}

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
            "current_session_key": "",
            "current_window_id": 0,
            "current_workspace_name": "1",
            "current_herdr_pane_id": "",
            "current_herdr_host": "",
            "pending_intent_id": "",
        },
        build_herdr_spaces=lambda herdr_snapshot, sessions: [],
        list_launches=lambda **kwargs: [],
        invalidate_worktree_cache=lambda: None,
        timestamp=lambda: 42.0,
    )

    await service.snapshot({})  # hydrated build seeds _last_snapshot

    # Unhydrated build (e.g. window.changed) refreshes _last_snapshot but must
    # keep the git fields from the previous hydrated rows.
    await service.event_payload(["focus_state", "projects", "tracked_windows"])
    merged_row = service._last_snapshot["active_ai_sessions"][0]
    assert merged_row["git_compact"] == "● 2"
    assert merged_row["git_state"] == "dirty"

    payload = await service.event_payload(["focus_state"])

    row = payload["active_ai_sessions"][0]
    assert row["git_compact"] == "● 2"
    assert row["git_state"] == "dirty"
    assert row["git_snapshot"]["dirty_count"] == 2


@pytest.mark.asyncio
async def test_snapshot_can_omit_worktrees_for_shell_subscribers():
    # `worktrees` is ~100KB of a ~157KB snapshot and no shell surface renders
    # it, yet it rode through four serialization passes on every connect and
    # gap recovery. Clients that only drive the bars ask for it to be left out;
    # CLI consumers keep the default and still receive the array.
    built = []

    async def build_worktrees(runtime):
        built.append(runtime)
        return [{"qualified_name": "vpittamp/nixos-config:main"}]

    async def runtime_loader(params):
        return _runtime_snapshot(), [], {}

    service = DashboardService(
        runtime_loader=runtime_loader,
        display_snapshot=lambda: _async_value({"outputs": []}),
        build_projects=lambda runtime, sessions: [],
        build_worktrees=build_worktrees,
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
        build_herdr_spaces=lambda herdr, sessions: [],
        list_launches=lambda limit: [],
        invalidate_worktree_cache=lambda: None,
    )

    full = await service.snapshot({})
    assert len(full["worktrees"]) == 1
    assert len(built) == 1

    trimmed = await service.snapshot({"include_worktrees": False})
    assert trimmed["worktrees"] == []
    # Not merely filtered out of the payload — the build is skipped entirely,
    # so the cost of producing it is not paid either.
    assert len(built) == 1
