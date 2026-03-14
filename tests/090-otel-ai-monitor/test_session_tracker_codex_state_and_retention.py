import importlib.util
import json
import sys
from datetime import datetime, timezone
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
    assert session_list.schema_version == "8"
    assert session_list.sessions[0].session_id == "codex:pid:706991"
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
async def test_tracker_restores_recent_working_session_from_previous_snapshot(tmp_path):
    snapshot_path = tmp_path / "otel-ai-sessions.json"
    updated_at = datetime.now(timezone.utc).isoformat()
    snapshot_path.write_text(json.dumps({
        "schema_version": "6",
        "type": "session_list",
        "updated_at": updated_at,
        "sessions": [{
            "session_id": "codex:native-restore",
            "native_session_id": "native-restore",
            "context_fingerprint": "pane=%9",
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
