import importlib.util
import json
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest


def _load_otel_monitor_package():
    pkg_dir = (
        Path(__file__).resolve().parents[2]
        / "scripts"
        / "otel-ai-monitor"
    )
    spec = importlib.util.spec_from_file_location(
        "otel_ai_monitor",
        pkg_dir / "__init__.py",
        submodule_search_locations=[str(pkg_dir)],
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load otel_ai_monitor package")
    module = importlib.util.module_from_spec(spec)
    sys.modules["otel_ai_monitor"] = module
    spec.loader.exec_module(module)
    return module


_load_otel_monitor_package()
import otel_ai_monitor.session_tracker as session_tracker_module  # type: ignore  # noqa: E402
from otel_ai_monitor.models import (  # type: ignore  # noqa: E402
    AITool,
    IdentityConfidence,
    Provider,
    Session,
    SessionState,
    TerminalState,
    TelemetryEvent,
)
from otel_ai_monitor.session_tracker import SessionTracker, _derive_session_stage  # type: ignore  # noqa: E402


class _DummyOutput:
    def __init__(self, json_file_path: Path | None = None) -> None:
        self.json_file_path = json_file_path

    async def start(self) -> None:
        return None

    async def stop(self) -> None:
        return None

    async def write_update(self, update) -> None:  # pragma: no cover - not relevant here
        return None

    async def write_session_list(self, session_list) -> None:
        return None


@pytest.mark.asyncio
async def test_codex_api_request_enters_working_state(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    event = TelemetryEvent(
        event_name="codex.api_request",
        timestamp=datetime.now(timezone.utc),
        session_id="codex-native-session-test-001",
        tool=AITool.CODEX_CLI,
        attributes={
            "project": "vpittamp/nixos-config:main",
            "terminal.tmux.pane": "%777",
        },
    )

    await tracker.process_event(event)
    async with tracker._lock:
        matches = [
            s for s in tracker._sessions.values()
            if s.native_session_id == "codex-native-session-test-001"
        ]
        assert len(matches) == 1
        assert matches[0].state == SessionState.WORKING


@pytest.mark.asyncio
async def test_process_event_drops_stale_local_pid_before_resolution(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())

    monkeypatch.setattr(session_tracker_module, "pid_exists", lambda _pid: False)

    async def _unexpected_resolve(_pid: int):
        raise AssertionError("stale local PID should not resolve window context")

    monkeypatch.setattr(tracker, "_resolve_window_context", _unexpected_resolve)

    event = TelemetryEvent(
        event_name="codex.api_request",
        timestamp=datetime.now(timezone.utc),
        session_id="codex-native-stale-local",
        tool=AITool.CODEX_CLI,
        attributes={
            "process.pid": "424242",
            "terminal.execution_mode": "local",
            "terminal.connection_key": "local@thinkpad",
            "i3pm.context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "project": "vpittamp/nixos-config:main",
        },
    )

    await tracker.process_event(event)

    async with tracker._lock:
        assert tracker._sessions == {}


@pytest.mark.asyncio
async def test_process_event_repairs_restored_native_session_window_binding(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    restored = Session(
        session_id="codex:native-restore",
        native_session_id="native-restore",
        context_fingerprint="pane=%5",
        collision_group_id="codex:native-restore",
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=2212,
        pid=1108845,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="restored_snapshot",
    )
    restored.terminal_context.window_id = 2212
    restored.terminal_context.tmux_session = "workflow-builder/main"
    restored.terminal_context.tmux_window = "0:codex-raw"
    restored.terminal_context.tmux_pane = "%5"

    async with tracker._lock:
        tracker._sessions[restored.session_id] = restored
        tracker._session_pids[restored.session_id] = 1108845
        tracker._session_pids["native-restore"] = 1108845
        tracker._session_pids["codex:native-restore"] = 1108845
        tracker._native_session_map["codex:native-restore"] = {restored.session_id}

    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    async def _fake_resolve_window_context(pid: int):
        assert pid == 1108845
        return (
            2218,
            "PittampalliOrg/workflow-builder:main",
            {
                "tmux_session": "workflow-builder/main",
                "tmux_window": "0:codex-raw",
                "tmux_pane": "%5",
                "pty": "/dev/pts/5",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "context_key": "PittampalliOrg/workflow-builder:main::local::local@ryzen",
                "remote_target": None,
            },
        )

    monkeypatch.setattr(tracker, "_resolve_window_context", _fake_resolve_window_context)

    event = TelemetryEvent(
        event_name="codex.api_request",
        timestamp=now,
        session_id="native-restore",
        tool=AITool.CODEX_CLI,
        attributes={
            "project": "PittampalliOrg/workflow-builder:main",
        },
    )

    await tracker.process_event(event)

    async with tracker._lock:
        repaired_matches = [
            session
            for session in tracker._sessions.values()
            if session.native_session_id == "native-restore"
        ]
        assert len(repaired_matches) == 1
        repaired = repaired_matches[0]
        assert repaired.window_id == 2218
        assert repaired.terminal_context.window_id == 2218
        assert repaired.project == "PittampalliOrg/workflow-builder:main"


@pytest.mark.asyncio
async def test_process_event_preserves_established_tmux_identity_when_resolution_misses(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:native-sticky-pane",
        native_session_id="native-sticky-pane",
        context_fingerprint="pane=%6",
        collision_group_id="codex:native-sticky-pane",
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="PittampalliOrg/stacks:main",
        project_path="/home/vpittamp/repos/PittampalliOrg/stacks/main",
        window_id=18,
        pid=91112,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="event:codex.api_request",
    )
    session.terminal_context.window_id = 18
    session.terminal_context.terminal_anchor_id = "terminal-PittampalliOrg/stacks:main-8259-1773928355"
    session.terminal_context.binding_anchor_id = "terminal-PittampalliOrg/stacks:main-8259-1773928355"
    session.terminal_context.binding_state = "bound_local"
    session.terminal_context.binding_source = "tmux_metadata"
    session.terminal_context.tmux_session = "i3pm-pittampalliorg-stacks-ma-bc1d1663"
    session.terminal_context.tmux_window = "0:main"
    session.terminal_context.tmux_pane = "%6"
    session.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    session.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    session.terminal_context.tmux_resolution_source = "discovered"
    session.terminal_context.pty = "/dev/pts/10"
    session.terminal_context.execution_mode = "local"
    session.terminal_context.connection_key = "local@ryzen"
    session.terminal_context.context_key = "PittampalliOrg/stacks:main::local::local@ryzen"

    async with tracker._lock:
        tracker._sessions[session.session_id] = session
        tracker._session_pids[session.session_id] = 91112
        tracker._session_pids["native-sticky-pane"] = 91112
        tracker._session_pids["codex:native-sticky-pane"] = 91112
        tracker._native_session_map["codex:native-sticky-pane"] = {session.session_id}

    monkeypatch.setattr(session_tracker_module, "pid_exists", lambda _pid: True)
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    async def _missing_resolve(_pid: int):
        return (None, None, {})

    monkeypatch.setattr(tracker, "_resolve_window_context", _missing_resolve)

    event = TelemetryEvent(
        event_name="codex.sse_event",
        timestamp=now,
        session_id="native-sticky-pane",
        tool=AITool.CODEX_CLI,
        attributes={
            "process.pid": "91112",
            "event.kind": "response.output_text.delta",
            "project": "PittampalliOrg/stacks:main",
        },
    )

    await tracker.process_event(event)

    async with tracker._lock:
        kept = tracker._sessions["codex:native-sticky-pane"]
        assert kept.window_id == 18
        assert kept.terminal_context.tmux_session == "i3pm-pittampalliorg-stacks-ma-bc1d1663"
        assert kept.terminal_context.tmux_window == "0:main"
        assert kept.terminal_context.tmux_pane == "%6"
        assert kept.invalid_reason is None


@pytest.mark.asyncio
async def test_heartbeat_preserves_established_tmux_identity_when_resolution_misses(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:pid:91112",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="PittampalliOrg/stacks:main",
        project_path="/home/vpittamp/repos/PittampalliOrg/stacks/main",
        window_id=18,
        pid=91112,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="process_keepalive",
    )
    session.terminal_context.window_id = 18
    session.terminal_context.terminal_anchor_id = "terminal-PittampalliOrg/stacks:main-8259-1773928355"
    session.terminal_context.binding_anchor_id = "terminal-PittampalliOrg/stacks:main-8259-1773928355"
    session.terminal_context.binding_state = "bound_local"
    session.terminal_context.binding_source = "tmux_metadata"
    session.terminal_context.tmux_session = "i3pm-pittampalliorg-stacks-ma-bc1d1663"
    session.terminal_context.tmux_window = "0:main"
    session.terminal_context.tmux_pane = "%6"
    session.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    session.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    session.terminal_context.tmux_resolution_source = "discovered"
    session.terminal_context.pty = "/dev/pts/10"
    session.terminal_context.execution_mode = "local"
    session.terminal_context.connection_key = "local@ryzen"
    session.terminal_context.context_key = "PittampalliOrg/stacks:main::local::local@ryzen"

    async with tracker._lock:
        tracker._sessions[session.session_id] = session

    async def _missing_resolve(_pid: int):
        return (None, None, {})

    monkeypatch.setattr(tracker, "_resolve_window_context", _missing_resolve)

    await tracker.process_heartbeat_for_tool(AITool.CODEX_CLI, pid=91112)

    async with tracker._lock:
        kept = tracker._sessions["codex:pid:91112"]
        assert kept.window_id == 18
        assert kept.terminal_context.tmux_session == "i3pm-pittampalliorg-stacks-ma-bc1d1663"
        assert kept.terminal_context.tmux_window == "0:main"
        assert kept.terminal_context.tmux_pane == "%6"
        assert kept.invalid_reason is None


@pytest.mark.asyncio
async def test_resolve_window_context_prefers_tmux_anchor_over_stale_process_env(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())

    monkeypatch.setattr(
        session_tracker_module,
        "get_process_i3pm_env",
        lambda _pid: {
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
            "I3PM_TERMINAL_ANCHOR_ID": "terminal-vpittamp/nixos-config:main-stale",
            "I3PM_CONTEXT_VARIANT": "local",
            "I3PM_CONNECTION_KEY": "local@thinkpad",
            "I3PM_CONTEXT_KEY": "vpittamp/nixos-config:main::local::local@thinkpad",
        },
    )

    async def _fake_tmux_context(_pid: int):
        return {
            "terminal_anchor_id": "terminal-vpittamp/nixos-config:main-fresh",
            "project_name": "vpittamp/nixos-config:main",
            "tmux_session": "i3pm-vpittamp-nixos-config-ma-6e1abb85",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "tmux_resolution_source": "discovered",
            "pty": "/dev/pts/5",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
        }

    async def _fake_anchor_lookup(anchor_id: str):
        assert anchor_id == "terminal-vpittamp/nixos-config:main-fresh"
        return {
            "binding": "window",
            "window_id": 5,
            "project_name": "vpittamp/nixos-config:main",
        }

    monkeypatch.setattr(session_tracker_module, "get_tmux_context_for_pid", _fake_tmux_context)
    monkeypatch.setattr(session_tracker_module, "query_daemon_for_terminal_anchor", _fake_anchor_lookup)
    monkeypatch.setattr(
        session_tracker_module,
        "get_window_context_by_id",
        lambda window_id: {
            "project": "vpittamp/nixos-config:main",
            "execution_mode": "local",
            "connection_key": "local@thinkpad",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
        } if window_id == 5 else {},
    )

    window_id, project, terminal_context = await tracker._resolve_window_context(1416360)

    assert window_id == 5
    assert project == "vpittamp/nixos-config:main"
    assert terminal_context["terminal_anchor_id"] == "terminal-vpittamp/nixos-config:main-fresh"
    assert terminal_context["binding_anchor_id"] == "terminal-vpittamp/nixos-config:main-fresh"
    assert terminal_context["binding_state"] == "rebound_local"
    assert terminal_context["binding_source"] == "tmux_metadata"
    assert terminal_context["anchor_lookup"] == "window"
    assert terminal_context["context_key"] == "vpittamp/nixos-config:main::local::local@thinkpad"


@pytest.mark.asyncio
async def test_cleanup_keeps_native_session_when_pid_exits(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:retain-on-exit",
        native_session_id="native-codex-001",
        context_fingerprint="abc123",
        collision_group_id="codex:native-codex-001",
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path="/home/vpittamp/repos/vpittamp/nixos-config/main",
        window_id=174,
        pid=424242,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="event:codex.api_request",
    )
    session.terminal_context.window_id = 174
    session.terminal_context.tmux_pane = "%30"

    async with tracker._lock:
        tracker._sessions[session.session_id] = session

    monkeypatch.setattr(session_tracker_module, "get_all_window_ids", lambda: [174])

    def _fake_kill(pid: int, signal: int) -> None:
        if pid == 424242:
            raise ProcessLookupError()
        return None

    monkeypatch.setattr(session_tracker_module.os, "kill", _fake_kill)

    await tracker._cleanup_orphaned_windows()

    async with tracker._lock:
        kept = tracker._sessions.get("codex:retain-on-exit")
        assert kept is not None
        assert kept.pid is None
        assert kept.state == SessionState.COMPLETED
        assert kept.status_reason == "process_exited_retained"


@pytest.mark.asyncio
async def test_expire_sessions_retains_working_session_when_pid_is_still_running(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:pid:retain-live-process",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path="/home/vpittamp/repos/vpittamp/nixos-config/main",
        window_id=174,
        pid=424242,
        trace_id=None,
        created_at=now - timedelta(minutes=20),
        last_event_at=now - timedelta(minutes=10),
        state_changed_at=now - timedelta(minutes=10),
        state_seq=1,
        status_reason="event:codex.api_request",
    )
    session.terminal_context.execution_mode = "local"

    async with tracker._lock:
        tracker._sessions[session.session_id] = session

    monkeypatch.setattr(session_tracker_module.os, "kill", lambda pid, signal: None)

    await tracker._expire_sessions()

    async with tracker._lock:
        kept = tracker._sessions.get(session.session_id)
        assert kept is not None
        assert kept.status_reason == "process_keepalive"
        assert (datetime.now(timezone.utc) - kept.last_event_at).total_seconds() < 5


@pytest.mark.asyncio
async def test_expire_sessions_retains_working_session_when_tmux_target_is_still_live(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:pid:retain-live-tmux",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="PittampalliOrg/stacks:main",
        project_path="/home/vpittamp/repos/PittampalliOrg/stacks/main",
        window_id=18,
        pid=None,
        trace_id=None,
        created_at=now - timedelta(minutes=20),
        last_event_at=now - timedelta(minutes=10),
        state_changed_at=now - timedelta(minutes=10),
        state_seq=1,
        status_reason="event:codex.api_request",
    )
    session.terminal_context.execution_mode = "local"
    session.terminal_context.connection_key = "local@ryzen"
    session.terminal_context.context_key = "PittampalliOrg/stacks:main::local::local@ryzen"
    session.terminal_context.tmux_session = "i3pm-pittampalliorg-stacks-ma-bc1d1663"
    session.terminal_context.tmux_window = "0:main"
    session.terminal_context.tmux_pane = "%6"
    session.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    session.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    session.terminal_context.pty = "/dev/pts/10"

    async with tracker._lock:
        tracker._sessions[session.session_id] = session

    def _missing_process(pid: int, signal: int) -> None:
        raise ProcessLookupError()

    monkeypatch.setattr(session_tracker_module.os, "kill", _missing_process)
    monkeypatch.setattr(session_tracker_module, "tmux_target_exists", lambda **_kwargs: True)

    await tracker._expire_sessions()

    async with tracker._lock:
        kept = tracker._sessions.get(session.session_id)
        assert kept is not None
        assert kept.status_reason == "tmux_keepalive"
        assert (datetime.now(timezone.utc) - kept.last_event_at).total_seconds() < 5


def test_build_session_list_includes_resolved_pid_session_after_restart():
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:pid:706991",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path="/home/vpittamp/repos/vpittamp/nixos-config/main",
        window_id=219,
        pid=706991,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="process_detected",
    )
    session.terminal_context.window_id = 219
    session.terminal_context.terminal_anchor_id = "anchor-706991"
    session.terminal_context.pty = "/dev/pts/8"
    session.terminal_context.tmux_session = "nixos-config/main"
    session.terminal_context.execution_mode = "local"
    session.terminal_context.connection_key = "local@ryzen"
    session.terminal_context.context_key = "vpittamp/nixos-config:main::local::local@ryzen"

    tracker._sessions[session.session_id] = session

    session_list, _ = tracker._build_session_list_unlocked()

    assert len(session_list.sessions) == 1
    assert session_list.schema_version == "11"
    assert session_list.sessions[0].session_id == "codex:pid:706991"
    assert session_list.sessions[0].identity_phase == "provisional"
    assert session_list.sessions[0].identity_confidence == IdentityConfidence.PID
    assert session_list.sessions[0].project == "vpittamp/nixos-config:main"
    assert session_list.sessions[0].session_kind == "process"
    assert session_list.sessions[0].live is True
    assert session_list.sessions[0].session_project == "vpittamp/nixos-config:main"
    assert session_list.sessions[0].display_project == "vpittamp/nixos-config:main"
    assert session_list.sessions[0].stage == "starting"
    assert session_list.sessions[0].stage_label == "Starting"
    assert session_list.sessions[0].stage_detail == "Process detected"
    assert session_list.sessions[0].stage_visual_state == "working"
    assert session_list.sessions[0].turn_owner == "unknown"
    assert session_list.sessions[0].activity_substate == "starting"
    assert session_list.sessions[0].identity_source == "pid"
    assert session_list.sessions[0].lifecycle_source == "process"
    assert session_list.has_working is True


def test_build_session_list_exports_canonical_project_fields(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:pid:workflow-builder",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=314,
        pid=999001,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="process_detected",
    )
    session.terminal_context.window_id = 314
    session.terminal_context.terminal_anchor_id = "anchor-workflow-builder"
    session.terminal_context.tmux_session = "workflow-builder/main"
    session.terminal_context.tmux_window = "1:main"
    session.terminal_context.tmux_pane = "%37"
    session.terminal_context.execution_mode = "ssh"
    session.terminal_context.connection_key = "vpittamp@ryzen:22"
    session.terminal_context.context_key = "vpittamp/nixos-config:main::ssh::vpittamp@ryzen:22"

    tracker._sessions[session.session_id] = session

    monkeypatch.setattr(
        session_tracker_module,
        "get_window_context_by_id",
        lambda window_id: {"project": "vpittamp/nixos-config:main"} if window_id == 314 else {},
    )

    session_list, _ = tracker._build_session_list_unlocked()

    assert len(session_list.sessions) == 1
    item = session_list.sessions[0]
    assert item.project == "vpittamp/nixos-config:main"
    assert item.session_project == "vpittamp/nixos-config:main"
    assert item.window_project == "vpittamp/nixos-config:main"
    assert item.focus_project == "vpittamp/nixos-config:main"
    assert item.display_project == "vpittamp/nixos-config:main"
    assert item.project_source == "anchor"


def test_build_session_list_collapses_duplicate_sessions_on_same_tmux_surface(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(session_tracker_module, "tmux_target_exists", lambda **_kwargs: True)
    monkeypatch.setattr(
        session_tracker_module,
        "list_tmux_panes_sync",
        lambda: [{
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "tmux_session": "i3pm-vpittamp-nixos-config-ma-6e1abb85",
            "tmux_window": "1:codex-raw",
            "tmux_pane": "%4",
            "pane_pid": 283369,
            "pane_title": "codex --yolo",
            "pane_active": True,
            "window_active": True,
            "pty": "/dev/pts/5",
        }],
    )

    native = Session(
        session_id="codex:native-pane",
        native_session_id="native-pane",
        context_fingerprint="pane=%4",
        collision_group_id="codex:native-pane",
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path="/home/vpittamp/repos/vpittamp/nixos-config/main",
        window_id=14,
        pid=283369,
        trace_id="trace-native",
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=48,
        status_reason="event:codex.websocket_event",
    )
    native.pending_tools = 1
    native.terminal_context.window_id = 14
    native.terminal_context.terminal_anchor_id = "terminal-vpittamp/nixos-config:main-36847-1773601030"
    native.terminal_context.tmux_session = "i3pm-vpittamp-nixos-config-ma-6e1abb85"
    native.terminal_context.tmux_window = "1:codex-raw"
    native.terminal_context.tmux_pane = "%4"
    native.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    native.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    native.terminal_context.pty = "/dev/pts/5"
    native.terminal_context.execution_mode = "local"
    native.terminal_context.connection_key = "local@thinkpad"
    native.terminal_context.context_key = "vpittamp/nixos-config:main::local::local@thinkpad"

    duplicate = Session(
        session_id="codex:pid:283369",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=14,
        pid=283369,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="process_keepalive",
    )
    duplicate.terminal_context.window_id = 14
    duplicate.terminal_context.terminal_anchor_id = "terminal-vpittamp/nixos-config:main-36847-1773601030"
    duplicate.terminal_context.tmux_session = "i3pm-vpittamp-nixos-config-ma-6e1abb85"
    duplicate.terminal_context.tmux_window = "1:codex-raw"
    duplicate.terminal_context.tmux_pane = "%4"
    duplicate.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    duplicate.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    duplicate.terminal_context.pty = "/dev/pts/5"
    duplicate.terminal_context.execution_mode = "local"
    duplicate.terminal_context.connection_key = "local@thinkpad"
    duplicate.terminal_context.context_key = "vpittamp/nixos-config:main::local::local@thinkpad"

    tracker._sessions[native.session_id] = native
    tracker._sessions[duplicate.session_id] = duplicate

    session_list, _ = tracker._build_session_list_unlocked()

    assert len(session_list.sessions) == 1
    winner = session_list.sessions[0]
    assert winner.session_id == "codex:native-pane"
    assert winner.identity_confidence == IdentityConfidence.NATIVE
    assert winner.pending_tools == 1
    assert winner.surface_kind == "tmux-pane"
    assert "::%4::" in winner.surface_key
    assert winner.focusable is True


@pytest.mark.asyncio
async def test_ensure_process_session_reuses_canonical_same_surface_and_drops_pid_duplicate(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    pid = 1304538
    canonical_session_id = "codex:native-keep:7bb8dbd5a92e"
    duplicate_session_id = f"codex:pid:{pid}"

    canonical = Session(
        session_id=canonical_session_id,
        native_session_id="native-keep",
        context_fingerprint="7bb8dbd5a92e",
        collision_group_id="codex:native-keep",
        identity_confidence=IdentityConfidence.NATIVE,
        identity_phase="canonical",
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path="/home/vpittamp/repos/vpittamp/nixos-config/main",
        window_id=14,
        pid=pid,
        trace_id="trace-native",
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=9,
        status_reason="event:stream_token",
    )
    duplicate = Session(
        session_id=duplicate_session_id,
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        identity_phase="provisional",
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=14,
        pid=pid,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="process_detected",
    )
    for session in (canonical, duplicate):
        session.terminal_context.window_id = 14
        session.terminal_context.tmux_session = "i3pm-vpittamp-nixos-config-ma-6e1abb85"
        session.terminal_context.tmux_window = "0:main"
        session.terminal_context.tmux_pane = "%4"
        session.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
        session.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
        session.terminal_context.execution_mode = "local"
        session.terminal_context.connection_key = "local@thinkpad"
        session.terminal_context.context_key = "vpittamp/nixos-config:main::local::local@thinkpad"

    async with tracker._lock:
        tracker._sessions[canonical_session_id] = canonical
        tracker._sessions[duplicate_session_id] = duplicate

    async def _resolve_window_context(_pid: int):
        return (
            14,
            "vpittamp/nixos-config:main",
            {
                "window_id": 14,
                "tmux_session": "i3pm-vpittamp-nixos-config-ma-6e1abb85",
                "tmux_window": "0:main",
                "tmux_pane": "%4",
                "tmux_socket": "/run/user/1000/tmux-1000/default",
                "tmux_server_key": "/run/user/1000/tmux-1000/default",
                "execution_mode": "local",
                "connection_key": "local@thinkpad",
                "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            },
        )

    monkeypatch.setattr(tracker, "_refresh_metadata_cache", lambda: None)
    monkeypatch.setattr(tracker, "_load_pid_metadata", lambda _pid: {"project": "vpittamp/nixos-config:main"})
    monkeypatch.setattr(tracker, "_resolve_window_context", _resolve_window_context)

    resolved = await tracker._ensure_process_session_for_pid(AITool.CODEX_CLI, pid)

    assert resolved == canonical_session_id
    async with tracker._lock:
        assert canonical_session_id in tracker._sessions
        assert duplicate_session_id not in tracker._sessions


def test_build_context_fingerprint_ignores_pid_and_window_for_tmux_identity():
    first_terminal_context = {
        "tmux_server_key": "/run/user/1000/tmux-1000/default",
        "tmux_socket": "/run/user/1000/tmux-1000/default",
        "tmux_session": "i3pm-pittampalliorg-workflow--9594e5c9",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
        "pty": "/dev/pts/1",
        "host_name": "thinkpad",
        "execution_mode": "local",
        "connection_key": "local@thinkpad",
        "context_key": "PittampalliOrg/workflow-builder:main::local::local@thinkpad",
    }

    first = SessionTracker._build_context_fingerprint(
        12345,
        9,
        first_terminal_context,
        "PittampalliOrg/workflow-builder:main",
        "/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
    )
    second_terminal_context = dict(first_terminal_context)
    second_terminal_context["pty"] = "/dev/pts/99"
    second_terminal_context["tmux_socket"] = "/tmp/other-socket"
    second = SessionTracker._build_context_fingerprint(
        67890,
        114,
        second_terminal_context,
        "some-other-project",
        "/tmp/other-project",
    )

    assert first is not None
    assert first == second


@pytest.mark.asyncio
async def test_process_event_promotes_provisional_native_session_to_canonical_once_identity_is_complete(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    start = datetime.now(timezone.utc)
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)
    monkeypatch.setattr(session_tracker_module, "pid_exists", lambda _pid: True)

    async def _fake_resolve_window_context(pid: int):
        assert pid == 424242
        return (101, "vpittamp/nixos-config:main", {})

    monkeypatch.setattr(tracker, "_resolve_window_context", _fake_resolve_window_context)

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.api_request",
            timestamp=start,
            session_id="native-promote",
            tool=AITool.CODEX_CLI,
            attributes={
                "process.pid": "424242",
                "project": "vpittamp/nixos-config:main",
                "terminal.execution_mode": "local",
                "terminal.connection_key": "local@thinkpad",
                "terminal.tmux.session": "i3pm-vpittamp-nixos-config-main",
                "terminal.tmux.window": "0:main",
                "terminal.tmux.pane": "%5",
            },
        )
    )

    async with tracker._lock:
        provisional = tracker._sessions["codex:pid:424242"]
        assert provisional.identity_phase == "provisional"
        assert provisional.context_fingerprint is None

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.tool_result",
            timestamp=start + timedelta(seconds=1),
            session_id="native-promote",
            tool=AITool.CODEX_CLI,
            attributes={
                "process.pid": "424242",
                "project": "vpittamp/nixos-config:main",
                "terminal.execution_mode": "local",
                "terminal.connection_key": "local@thinkpad",
                "terminal.context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                "terminal.tmux.server_key": "/run/user/1000/tmux-1000/default",
                "terminal.tmux.socket": "/run/user/1000/tmux-1000/default",
                "terminal.tmux.session": "i3pm-vpittamp-nixos-config-main",
                "terminal.tmux.window": "0:main",
                "terminal.tmux.pane": "%5",
                "terminal.pty": "/dev/pts/5",
            },
        )
    )

    async with tracker._lock:
        matches = [s for s in tracker._sessions.values() if s.native_session_id == "native-promote"]
        assert len(matches) == 1
        promoted = matches[0]
        assert promoted.identity_phase == "canonical"
        assert promoted.session_id == f"codex:native-promote:{promoted.context_fingerprint}"
        assert promoted.context_fingerprint is not None
        assert "codex:pid:424242" not in tracker._sessions
        assert tracker._native_session_map["codex:native-promote"] == {promoted.session_id}
        stable_session_id = promoted.session_id
        stable_fingerprint = promoted.context_fingerprint

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.sse_event",
            timestamp=start + timedelta(seconds=2),
            session_id="native-promote",
            tool=AITool.CODEX_CLI,
            attributes={
                "process.pid": "424242",
                "project": "some-other-project",
                "host.name": "renamed-host",
                "terminal.execution_mode": "local",
                "terminal.connection_key": "local@thinkpad",
                "terminal.context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
                "terminal.tmux.server_key": "/run/user/1000/tmux-1000/default",
                "terminal.tmux.socket": "/tmp/changed-socket",
                "terminal.tmux.session": "i3pm-vpittamp-nixos-config-main",
                "terminal.tmux.window": "0:main",
                "terminal.tmux.pane": "%5",
                "terminal.pty": "/dev/pts/99",
            },
        )
    )

    async with tracker._lock:
        matches = [s for s in tracker._sessions.values() if s.native_session_id == "native-promote"]
        assert len(matches) == 1
        promoted = matches[0]
        assert promoted.identity_phase == "canonical"
        assert promoted.session_id == stable_session_id
        assert promoted.context_fingerprint == stable_fingerprint


@pytest.mark.asyncio
async def test_process_bootstrap_recovers_codex_native_session_from_surface_metadata(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    pid = 1932482

    async def _resolve_window_context(_pid: int):
        return (
            75,
            "NVIDIA/OpenShell:main",
            {
                "window_id": 75,
                "terminal_anchor_id": "terminal-NVIDIA/OpenShell:main-1801281-1773939293",
                "tmux_session": "i3pm-nvidia-openshell-main-5df2ad13",
                "tmux_window": "0:main",
                "tmux_pane": "%12",
                "tmux_socket": "/run/user/1000/tmux-1000/default",
                "tmux_server_key": "/run/user/1000/tmux-1000/default",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "context_key": "NVIDIA/OpenShell:main::local::local@ryzen",
                "pty": "/dev/pts/13",
            },
        )

    monkeypatch.setattr(tracker, "_refresh_metadata_cache", lambda: None)
    monkeypatch.setattr(tracker, "_resolve_window_context", _resolve_window_context)
    monkeypatch.setattr(
        tracker,
        "_load_codex_runtime_metadata_for_pid",
        lambda *_args, **_kwargs: {},
    )
    tracker._pid_metadata_cache = {}
    tracker._metadata_file_cache = {
        "native-openshell": {
            "session_id": "native-openshell",
            "pid": 999999,
            "tool": "codex",
            "project": "NVIDIA/OpenShell:main",
            "terminal_anchor_id": "terminal-NVIDIA/OpenShell:main-1801281-1773939293",
            "tmux_session": "i3pm-nvidia-openshell-main-5df2ad13",
            "tmux_window": "0:main",
            "tmux_pane": "%12",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "execution_mode": "local",
            "connection_key": "local@ryzen",
            "context_key": "NVIDIA/OpenShell:main::local::local@ryzen",
            "updated_at": "2026-03-19T23:06:24.000Z",
        }
    }

    resolved = await tracker._ensure_process_session_for_pid(AITool.CODEX_CLI, pid)

    async with tracker._lock:
        session = tracker._sessions[resolved]
        assert session.native_session_id == "native-openshell"
        assert session.identity_phase == "canonical"
        assert session.canonicalization_blocker is None
        assert resolved == f"codex:native-openshell:{session.context_fingerprint}"


@pytest.mark.asyncio
async def test_process_bootstrap_recovers_codex_native_session_from_runtime_logs(monkeypatch, tmp_path):
    tracker = SessionTracker(output=_DummyOutput())
    pid = 1932482
    native_session_id = "019d0705-bd49-7ad1-9621-d192901798e9"
    logs_dir = tmp_path / ".codex"
    logs_dir.mkdir(parents=True, exist_ok=True)
    database_path = logs_dir / "logs_1.sqlite"
    with sqlite3.connect(database_path) as connection:
        connection.execute(
            """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                ts_nanos INTEGER NOT NULL DEFAULT 0,
                level TEXT NOT NULL DEFAULT 'INFO',
                target TEXT NOT NULL DEFAULT '',
                message TEXT,
                module_path TEXT,
                file TEXT,
                line INTEGER,
                thread_id TEXT,
                process_uuid TEXT,
                estimated_bytes INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        connection.execute(
            """
            INSERT INTO logs (ts, thread_id, process_uuid)
            VALUES (?, ?, ?)
            """,
            (
                int(datetime(2026, 3, 19, 23, 46, 27, tzinfo=timezone.utc).timestamp()),
                native_session_id,
                f"pid:{pid}:759a7564-d7b2-4176-aca6-25c3c074dc66",
            ),
        )
        connection.commit()

    async def _resolve_window_context(_pid: int):
        return (
            75,
            "NVIDIA/OpenShell:main",
            {
                "window_id": 75,
                "terminal_anchor_id": "terminal-NVIDIA/OpenShell:main-1801281-1773939293",
                "tmux_session": "i3pm-nvidia-openshell-main-5df2ad13",
                "tmux_window": "0:main",
                "tmux_pane": "%12",
                "tmux_socket": "/run/user/1000/tmux-1000/default",
                "tmux_server_key": "/run/user/1000/tmux-1000/default",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "context_key": "NVIDIA/OpenShell:main::local::local@ryzen",
                "pty": "/dev/pts/13",
            },
        )

    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(tracker, "_refresh_metadata_cache", lambda: None)
    monkeypatch.setattr(tracker, "_resolve_window_context", _resolve_window_context)
    tracker._pid_metadata_cache = {}
    tracker._metadata_file_cache = {}

    resolved = await tracker._ensure_process_session_for_pid(AITool.CODEX_CLI, pid)

    async with tracker._lock:
        session = tracker._sessions[resolved]
        assert session.native_session_id == native_session_id
        assert session.identity_phase == "canonical"
        assert session.canonicalization_blocker is None
        assert resolved == f"codex:{native_session_id}:{session.context_fingerprint}"


@pytest.mark.asyncio
async def test_process_bootstrap_marks_codex_missing_native_session_id_blocker(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    pid = 424299

    async def _resolve_window_context(_pid: int):
        return (
            88,
            "NVIDIA/OpenShell:main",
            {
                "window_id": 88,
                "terminal_anchor_id": "terminal-NVIDIA/OpenShell:main-ephemeral",
                "tmux_session": "i3pm-nvidia-openshell-main-5df2ad13",
                "tmux_window": "0:main",
                "tmux_pane": "%12",
                "tmux_socket": "/run/user/1000/tmux-1000/default",
                "tmux_server_key": "/run/user/1000/tmux-1000/default",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "context_key": "NVIDIA/OpenShell:main::local::local@ryzen",
                "pty": "/dev/pts/13",
            },
        )

    monkeypatch.setattr(tracker, "_refresh_metadata_cache", lambda: None)
    monkeypatch.setattr(tracker, "_resolve_window_context", _resolve_window_context)
    tracker._pid_metadata_cache = {}
    tracker._metadata_file_cache = {}

    resolved = await tracker._ensure_process_session_for_pid(AITool.CODEX_CLI, pid)

    async with tracker._lock:
        session = tracker._sessions[resolved]
        assert session.identity_phase == "provisional"
        assert session.canonicalization_blocker == "missing_native_session_id"

    async with tracker._lock:
        session_list, _ = tracker._build_session_list_unlocked()
    assert session_list.sessions[0].canonicalization_blocker == "missing_native_session_id"


@pytest.mark.asyncio
async def test_process_bootstrap_does_not_recover_claude_native_session_from_project_only_metadata(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    pid = 643054

    async def _resolve_window_context(_pid: int):
        return (
            219,
            "vpittamp/nixos-config:main",
            {
                "window_id": 219,
                "tmux_session": "i3pm-vpittamp-nixos-config-ma-83466f26",
                "tmux_window": "2:claude-hook-test",
                "tmux_pane": "%9",
                "tmux_socket": "/run/user/1000/tmux-1000/default",
                "tmux_server_key": "/run/user/1000/tmux-1000/default",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
                "context_key": "vpittamp/nixos-config:main::local::local@ryzen",
                "pty": "/dev/pts/5",
            },
        )

    monkeypatch.setattr(tracker, "_refresh_metadata_cache", lambda: None)
    monkeypatch.setattr(tracker, "_resolve_window_context", _resolve_window_context)
    tracker._pid_metadata_cache = {}
    tracker._metadata_file_cache = {
        "f492ff0b-3888-4056-945d-8c68c799af2e": {
            "session_id": "f492ff0b-3888-4056-945d-8c68c799af2e",
            "pid": 27887,
            "tool": "claude-code",
            "project": "vpittamp/nixos-config:main",
            "updated_at": "2026-03-20T20:59:20.000Z",
        }
    }

    resolved = await tracker._ensure_process_session_for_pid(AITool.CLAUDE_CODE, pid)

    async with tracker._lock:
        session = tracker._sessions[resolved]
        assert session.native_session_id is None
        assert session.identity_phase == "provisional"
        assert session.canonicalization_blocker == "missing_native_session_id"


def test_build_session_list_prefers_live_session_over_retained_output_ready_on_same_tmux_surface(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(session_tracker_module, "tmux_target_exists", lambda **_kwargs: True)
    monkeypatch.setattr(
        session_tracker_module,
        "list_tmux_panes_sync",
        lambda: [{
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "tmux_session": "i3pm-pittampalliorg-workflow--9594e5c9",
            "tmux_window": "0:main",
            "tmux_pane": "%0",
            "pane_pid": 2123637,
            "pane_title": "codex resume --yolo",
            "pane_active": True,
            "window_active": True,
            "pty": "/dev/pts/1",
        }],
    )

    retained = Session(
        session_id="codex:old-session",
        native_session_id="old-session",
        context_fingerprint="pane=%0",
        collision_group_id="codex:old-session",
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.COMPLETED,
        project="PittampalliOrg/workflow-builder:main",
        project_path="/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
        window_id=9,
        pid=2123637,
        trace_id="trace-old",
        created_at=now - timedelta(minutes=20),
        last_event_at=now - timedelta(minutes=10),
        last_activity_at=now - timedelta(minutes=10),
        state_changed_at=now - timedelta(minutes=10),
        state_seq=8,
        status_reason="event:codex.Codex Session",
    )
    retained.terminal_context.window_id = 9
    retained.terminal_context.tmux_session = "i3pm-pittampalliorg-workflow--9594e5c9"
    retained.terminal_context.tmux_window = "0:main"
    retained.terminal_context.tmux_pane = "%0"
    retained.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    retained.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    retained.terminal_context.pty = "/dev/pts/1"
    retained.terminal_context.execution_mode = "local"
    retained.terminal_context.connection_key = "local@thinkpad"
    retained.terminal_context.context_key = "PittampalliOrg/workflow-builder:main::local::local@thinkpad"
    retained.terminal_state = TerminalState.EXPLICIT_COMPLETE

    live = Session(
        session_id="codex:live-session",
        native_session_id="live-session",
        context_fingerprint="pane=%0-live",
        collision_group_id="codex:live-session",
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="PittampalliOrg/workflow-builder:main",
        project_path="/home/vpittamp/repos/PittampalliOrg/workflow-builder/main",
        window_id=9,
        pid=2123637,
        trace_id="trace-live",
        created_at=now - timedelta(minutes=1),
        last_event_at=now,
        last_activity_at=now,
        state_changed_at=now,
        state_seq=3,
        status_reason="event:codex.tool_result",
    )
    live.terminal_context.window_id = 9
    live.terminal_context.tmux_session = "i3pm-pittampalliorg-workflow--9594e5c9"
    live.terminal_context.tmux_window = "0:main"
    live.terminal_context.tmux_pane = "%0"
    live.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    live.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    live.terminal_context.pty = "/dev/pts/1"
    live.terminal_context.execution_mode = "local"
    live.terminal_context.connection_key = "local@thinkpad"
    live.terminal_context.context_key = "PittampalliOrg/workflow-builder:main::local::local@thinkpad"

    tracker._sessions[retained.session_id] = retained
    tracker._sessions[live.session_id] = live

    session_list, _ = tracker._build_session_list_unlocked()

    assert len(session_list.sessions) == 1
    assert session_list.sessions[0].session_id == "codex:live-session"


@pytest.mark.asyncio
async def test_codex_response_completed_exports_user_turn_owner(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.api_request",
            timestamp=now,
            session_id="codex-native-session-turn-owner",
            tool=AITool.CODEX_CLI,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%55",
            },
        )
    )
    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.sse_event",
            timestamp=now,
            session_id="codex-native-session-turn-owner",
            tool=AITool.CODEX_CLI,
            attributes={
                "event.kind": "response.completed",
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%55",
            },
        )
    )

    async with tracker._lock:
        matches = [
            s for s in tracker._sessions.values()
            if s.native_session_id == "codex-native-session-turn-owner"
        ]
        assert len(matches) == 1
        stage_fields = _derive_session_stage(matches[0], now=now)

    assert getattr(stage_fields["turn_owner"], "value", stage_fields["turn_owner"]) == "user"
    assert getattr(stage_fields["activity_substate"], "value", stage_fields["activity_substate"]) == "output_ready"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("tool", "source", "provider_signal", "session_id", "native_session_id"),
    [
        (AITool.CODEX_CLI, "codex_notify", "agent-turn-complete", "codex-native-session-stopped", "codex-native-session-stopped"),
        (AITool.CLAUDE_CODE, "claude_stop_hook", "Stop", "claude-native-session-stopped", "claude-native-session-stopped"),
        (AITool.GEMINI_CLI, "gemini_after_agent", "AfterAgent", "gemini-native-session-stopped", "gemini-native-session-stopped"),
    ],
)
async def test_explicit_run_finished_marks_stopped_state(
    monkeypatch,
    tool,
    source,
    provider_signal,
    session_id,
    native_session_id,
):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.api_request" if tool == AITool.CODEX_CLI else (
                "claude_code.api_request" if tool == AITool.CLAUDE_CODE else "gemini_cli.api_request"
            ),
            timestamp=now,
            session_id=session_id,
            tool=tool,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%56",
            },
        )
    )
    await tracker.process_event(
        TelemetryEvent(
            event_name="ag_ui.run_finished",
            timestamp=now,
            session_id=session_id,
            tool=tool,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%56",
                "terminal_state_source": source,
                "provider_stop_signal": provider_signal,
            },
        )
    )

    async with tracker._lock:
        matches = [
            s for s in tracker._sessions.values()
            if s.native_session_id == native_session_id
        ]
        assert len(matches) == 1
        assert matches[0].state == SessionState.COMPLETED
        stage_fields = _derive_session_stage(matches[0], now=now)

    assert stage_fields["llm_stopped"] is True
    assert stage_fields["session_phase"] == "stopped"
    assert stage_fields["session_phase_label"] == "Stopped"
    assert stage_fields["terminal_state"] == TerminalState.EXPLICIT_COMPLETE
    assert stage_fields["terminal_state_label"] == "Stopped"
    assert stage_fields["terminal_state_source"] == source
    assert stage_fields["provider_stop_signal"] == provider_signal
    assert getattr(stage_fields["turn_owner"], "value", stage_fields["turn_owner"]) == "user"


@pytest.mark.asyncio
async def test_explicit_run_finished_survives_completed_timeout(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.api_request",
            timestamp=now,
            session_id="codex-native-session-timeout-stopped",
            tool=AITool.CODEX_CLI,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%57",
            },
        )
    )
    await tracker.process_event(
        TelemetryEvent(
            event_name="ag_ui.run_finished",
            timestamp=now + timedelta(seconds=1),
            session_id="codex-native-session-timeout-stopped",
            tool=AITool.CODEX_CLI,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%57",
                "terminal_state_source": "codex_notify",
                "provider_stop_signal": "agent-turn-complete",
            },
        )
    )

    async with tracker._lock:
        matches = [
            s for s in tracker._sessions.values()
            if s.native_session_id == "codex-native-session-timeout-stopped"
        ]
        assert len(matches) == 1
        session = matches[0]
        canonical_session_id = session.session_id

    await tracker._on_completed_timeout(canonical_session_id)

    async with tracker._lock:
        session = tracker._sessions[canonical_session_id]
        stage_fields = _derive_session_stage(session, now=now + timedelta(seconds=2))
        assert session.state == SessionState.IDLE
        assert session.terminal_state == TerminalState.EXPLICIT_COMPLETE
        assert session.terminal_state_source == "codex_notify"
        assert session.provider_stop_signal == "agent-turn-complete"

    assert stage_fields["output_ready"] is True
    assert stage_fields["llm_stopped"] is True
    assert stage_fields["session_phase"] == "stopped"
    assert stage_fields["terminal_state"] == TerminalState.EXPLICIT_COMPLETE
    assert stage_fields["terminal_state_source"] == "codex_notify"
    assert stage_fields["provider_stop_signal"] == "agent-turn-complete"
    assert getattr(stage_fields["turn_owner"], "value", stage_fields["turn_owner"]) == "user"


@pytest.mark.asyncio
async def test_claude_explicit_run_finished_rebinds_stale_process_identity(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    await tracker.process_event(
        TelemetryEvent(
            event_name="claude_code.api_request",
            timestamp=now,
            session_id="claude-stale-native-session",
            tool=AITool.CLAUDE_CODE,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "process.pid": 1141410,
                "terminal.tmux.session": "i3pm-vpittamp-nixos-config-ma-83466f26",
                "terminal.tmux.window": "5:claude-stop-verify-2",
                "terminal.tmux.pane": "%15",
                "terminal.tmux.socket": "/run/user/1000/tmux-1000/default",
                "terminal.tmux.server_key": "/run/user/1000/tmux-1000/default",
                "terminal.execution_mode": "local",
                "terminal.connection_key": "local@ryzen",
                "terminal.context_key": "vpittamp/nixos-config:main::local::local@ryzen",
            },
        )
    )

    await tracker.process_event(
        TelemetryEvent(
            event_name="ag_ui.run_finished",
            timestamp=now + timedelta(seconds=1),
            session_id="claude-fresh-native-session",
            tool=AITool.CLAUDE_CODE,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "process.pid": 1141410,
                "terminal.tmux.session": "i3pm-vpittamp-nixos-config-ma-83466f26",
                "terminal.tmux.window": "5:claude-stop-verify-2",
                "terminal.tmux.pane": "%15",
                "terminal.tmux.socket": "/run/user/1000/tmux-1000/default",
                "terminal.tmux.server_key": "/run/user/1000/tmux-1000/default",
                "terminal.execution_mode": "local",
                "terminal.connection_key": "local@ryzen",
                "terminal.context_key": "vpittamp/nixos-config:main::local::local@ryzen",
                "terminal_state_source": "claude_stop_hook",
                "provider_stop_signal": "Stop",
            },
        )
    )

    async with tracker._lock:
        stale_matches = [
            s for s in tracker._sessions.values()
            if s.native_session_id == "claude-stale-native-session"
        ]
        fresh_matches = [
            s for s in tracker._sessions.values()
            if s.native_session_id == "claude-fresh-native-session"
        ]
        assert len(stale_matches) == 0
        assert len(fresh_matches) == 1
        session = fresh_matches[0]
        stage_fields = _derive_session_stage(session, now=now + timedelta(seconds=2))

    assert session.pid == 1141410
    assert session.state == SessionState.COMPLETED
    assert stage_fields["session_phase"] == "stopped"
    assert stage_fields["terminal_state"] == TerminalState.EXPLICIT_COMPLETE
    assert stage_fields["terminal_state_source"] == "claude_stop_hook"
    assert stage_fields["provider_stop_signal"] == "Stop"


@pytest.mark.asyncio
async def test_explicit_run_finished_ignores_older_activity_and_clears_on_newer_turn(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(tracker, "_load_session_metadata_pid", lambda _sid: None)

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.api_request",
            timestamp=now,
            session_id="codex-native-session-sticky-stop",
            tool=AITool.CODEX_CLI,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%58",
            },
        )
    )
    await tracker.process_event(
        TelemetryEvent(
            event_name="ag_ui.run_finished",
            timestamp=now + timedelta(seconds=10),
            session_id="codex-native-session-sticky-stop",
            tool=AITool.CODEX_CLI,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%58",
                "terminal_state_source": "codex_notify",
                "provider_stop_signal": "agent-turn-complete",
            },
        )
    )
    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.api_request",
            timestamp=now + timedelta(seconds=5),
            session_id="codex-native-session-sticky-stop",
            tool=AITool.CODEX_CLI,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%58",
            },
        )
    )

    async with tracker._lock:
        matches = [
            s for s in tracker._sessions.values()
            if s.native_session_id == "codex-native-session-sticky-stop"
        ]
        assert len(matches) == 1
        session = matches[0]
        stage_fields = _derive_session_stage(session, now=now + timedelta(seconds=11))
        assert session.state == SessionState.COMPLETED
        assert session.terminal_state == TerminalState.EXPLICIT_COMPLETE

    assert stage_fields["session_phase"] == "stopped"
    assert stage_fields["llm_stopped"] is True

    await tracker.process_event(
        TelemetryEvent(
            event_name="codex.api_request",
            timestamp=now + timedelta(seconds=20),
            session_id="codex-native-session-sticky-stop",
            tool=AITool.CODEX_CLI,
            attributes={
                "project": "vpittamp/nixos-config:main",
                "terminal.tmux.pane": "%58",
            },
        )
    )

    async with tracker._lock:
        session = [
            s for s in tracker._sessions.values()
            if s.native_session_id == "codex-native-session-sticky-stop"
        ][0]
        stage_fields = _derive_session_stage(session, now=now + timedelta(seconds=21))
        assert session.state == SessionState.WORKING
        assert session.terminal_state == TerminalState.NONE
        assert session.terminal_state_source is None
        assert session.provider_stop_signal is None

    assert stage_fields["session_phase"] == "working"
    assert stage_fields["llm_stopped"] is False


@pytest.mark.asyncio
async def test_tracker_restores_recent_working_session_from_previous_snapshot(tmp_path):
    snapshot_path = tmp_path / "otel-ai-sessions.json"
    updated_at = datetime.now(timezone.utc).isoformat()
    snapshot_path.write_text(json.dumps({
        "schema_version": "11",
        "type": "session_list",
        "updated_at": updated_at,
        "sessions": [{
            "session_id": "codex:native-restore",
            "native_session_id": "native-restore",
            "context_fingerprint": "pane=%9",
            "identity_phase": "canonical",
            "collision_group_id": "codex:native-restore",
            "identity_confidence": "native",
            "tool": "codex",
            "state": "working",
            "project": "PittampalliOrg/stacks:main",
            "session_project": "PittampalliOrg/stacks:main",
            "window_project": "vpittamp/nixos-config:main",
            "focus_project": "vpittamp/nixos-config:main",
            "display_project": "PittampalliOrg/stacks:main",
            "project_source": "project_path",
            "project_path": "/home/vpittamp/repos/PittampalliOrg/stacks/main",
            "window_id": 219,
            "terminal_context": {
                "window_id": 219,
                "tmux_session": "stacks/main",
                "tmux_window": "1:main",
                "tmux_pane": "%9",
                "execution_mode": "ssh",
                "connection_key": "vpittamp@ryzen:22",
                "context_key": "PittampalliOrg/stacks:main::ssh::vpittamp@ryzen:22",
            },
            "pid": 706991,
            "trace_id": "abc123",
            "pending_tools": 1,
            "is_streaming": False,
            "state_seq": 3,
            "status_reason": "event:codex.tool_start",
            "updated_at": updated_at,
        }],
    }))

    tracker = SessionTracker(output=_DummyOutput(snapshot_path))
    await tracker._restore_previous_snapshot()

    async with tracker._lock:
        restored = tracker._sessions.get("codex:native-restore")
        assert restored is not None
        assert restored.native_session_id == "native-restore"
        assert restored.identity_confidence == IdentityConfidence.NATIVE
        assert restored.project == "PittampalliOrg/stacks:main"
        assert restored.project_path == "/home/vpittamp/repos/PittampalliOrg/stacks/main"
        assert restored.pending_tools == 1
        assert restored.terminal_context.tmux_pane == "%9"
        assert tracker._session_pids["codex:native-restore"] == 706991
        assert tracker._session_pids["native-restore"] == 706991
        assert "codex:native-restore" in tracker._native_session_map["codex:native-restore"]


def test_derive_session_stage_marks_quiet_alive_for_heartbeat_only_working_session():
    now = datetime.now(timezone.utc)
    session = Session(
        session_id="codex:quiet-alive",
        native_session_id="native-quiet-alive",
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=100,
        pid=321,
        trace_id="trace-quiet",
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        pending_tools=0,
        is_streaming=False,
        state_seq=1,
        status_reason="process_keepalive",
    )
    session.terminal_context.tmux_session = "i3pm-vpittamp-nixos-config-main"
    session.terminal_context.tmux_window = "0:main"
    session.terminal_context.tmux_pane = "%7"

    stage_fields = _derive_session_stage(session, now=now)

    assert stage_fields["session_phase"] == "quiet_alive"
    assert stage_fields["session_phase_label"] == "Quiet"


def test_derive_session_stage_marks_tmux_missing_when_tmux_identity_is_lost():
    now = datetime.now(timezone.utc)
    session = Session(
        session_id="codex:tmux-missing",
        native_session_id="native-tmux-missing",
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=101,
        pid=654,
        trace_id="trace-tmux-missing",
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        pending_tools=0,
        is_streaming=False,
        state_seq=1,
        status_reason="process_detected",
    )
    session.terminal_context.terminal_anchor_id = "terminal-anchor"
    session.terminal_context.tmux_resolution_source = "missing"

    stage_fields = _derive_session_stage(session, now=now)

    assert stage_fields["session_phase"] == "tmux_missing"
    assert stage_fields["session_phase_label"] == "Tmux missing"


def test_build_session_list_still_suppresses_unresolved_heuristic_session():
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)

    session = Session(
        session_id="codex:heuristic:1",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.HEURISTIC,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=None,
        pid=None,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="heuristic_only",
    )

    tracker._sessions[session.session_id] = session

    session_list, _ = tracker._build_session_list_unlocked()

    assert session_list.sessions == []


def test_build_session_list_keeps_local_tmux_session_visible_when_window_unbound(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(session_tracker_module, "tmux_target_exists", lambda **_kwargs: True)
    monkeypatch.setattr(
        session_tracker_module,
        "list_tmux_panes_sync",
        lambda: [{
            "tmux_socket": "/run/user/1000/tmux-1000/default",
            "tmux_server_key": "/run/user/1000/tmux-1000/default",
            "tmux_session": "i3pm-vpittamp-nixos-config-ma-6e1abb85",
            "tmux_window": "0:main",
            "tmux_pane": "%5",
            "pane_pid": 1234,
            "pane_title": "codex",
            "pane_active": True,
            "window_active": True,
            "pty": "/dev/pts/5",
        }],
    )
    monkeypatch.setattr(
        session_tracker_module,
        "read_tmux_session_i3pm_metadata_sync",
        lambda _socket, _session: {
            "binding_anchor_id": None,
            "binding_state": "tmux_present_unbound",
            "binding_source": None,
            "project_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::local::local@thinkpad",
            "connection_key": "local@thinkpad",
            "execution_mode": "local",
        },
    )

    session = Session(
        session_id="codex:native-unbound",
        native_session_id="native-unbound",
        context_fingerprint="pane=%5",
        collision_group_id="codex:native-unbound",
        identity_confidence=IdentityConfidence.NATIVE,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path="/home/vpittamp/repos/vpittamp/nixos-config/main",
        window_id=None,
        pid=1234,
        trace_id="trace-unbound",
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=2,
        status_reason="process_keepalive",
    )
    session.terminal_context.tmux_session = "i3pm-vpittamp-nixos-config-ma-6e1abb85"
    session.terminal_context.tmux_window = "0:main"
    session.terminal_context.tmux_pane = "%5"
    session.terminal_context.tmux_socket = "/run/user/1000/tmux-1000/default"
    session.terminal_context.tmux_server_key = "/run/user/1000/tmux-1000/default"
    session.terminal_context.pty = "/dev/pts/5"
    session.terminal_context.execution_mode = "local"
    session.terminal_context.connection_key = "local@thinkpad"
    session.terminal_context.context_key = "vpittamp/nixos-config:main::local::local@thinkpad"

    tracker._sessions[session.session_id] = session

    session_list, _ = tracker._build_session_list_unlocked()

    assert len(session_list.sessions) == 1
    item = session_list.sessions[0]
    assert item.session_id == "codex:native-unbound"
    assert item.window_id is None
    assert item.binding_state == "tmux_present_unbound"
    assert item.binding_anchor_id is None
    assert item.surface_kind == "tmux-pane"


@pytest.mark.asyncio
async def test_resolve_window_context_awaits_tmux_context(monkeypatch):
    tracker = SessionTracker(output=_DummyOutput())

    monkeypatch.setattr(
        session_tracker_module,
        "get_process_i3pm_env",
        lambda _pid: {
            "I3PM_TERMINAL_ANCHOR_ID": "anchor-1234",
            "I3PM_PROJECT_NAME": "vpittamp/nixos-config:main",
            "I3PM_EXECUTION_MODE": "local",
            "I3PM_CONNECTION_KEY": "local@thinkpad",
            "I3PM_CONTEXT_KEY": "vpittamp/nixos-config:main::local::local@thinkpad",
            "I3PM_REMOTE_HOST": "",
            "I3PM_REMOTE_USER": "",
            "I3PM_REMOTE_PORT": "22",
        },
    )

    async def _fake_tmux_context(pid: int):
        assert pid == 1234
        return {
            "tmux_session": "nixos-config/main",
            "tmux_window": "0:shell",
            "tmux_pane": "%30",
            "pty": "/dev/pts/30",
            "host_name": "thinkpad",
        }

    async def _fake_query_anchor(anchor_id: str):
        assert anchor_id == "anchor-1234"
        return {
            "terminal_anchor_id": anchor_id,
            "window_id": 174,
            "project_name": "vpittamp/nixos-config:main",
            "binding": "window_map",
            "matched": True,
        }

    monkeypatch.setattr(
        session_tracker_module,
        "query_daemon_for_terminal_anchor",
        _fake_query_anchor,
    )
    monkeypatch.setattr(session_tracker_module, "get_tmux_context_for_pid", _fake_tmux_context)

    window_id, project, terminal_context = await tracker._resolve_window_context(1234)

    assert window_id == 174
    assert project == "vpittamp/nixos-config:main"
    assert terminal_context["tmux_session"] == "nixos-config/main"
    assert terminal_context["tmux_window"] == "0:shell"
    assert terminal_context["tmux_pane"] == "%30"
    assert terminal_context["pty"] == "/dev/pts/30"
    assert terminal_context["connection_key"] == "local@thinkpad"
    assert terminal_context["context_key"] == "vpittamp/nixos-config:main::local::local@thinkpad"
    assert terminal_context["binding_anchor_id"] == "anchor-1234"
    assert terminal_context["binding_state"] == "bound_local"
