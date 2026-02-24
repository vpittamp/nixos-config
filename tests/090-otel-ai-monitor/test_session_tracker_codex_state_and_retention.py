import importlib.util
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
from otel_ai_monitor.session_tracker import SessionTracker  # type: ignore  # noqa: E402


class _DummyOutput:
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
