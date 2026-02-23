import asyncio
import importlib.util
import sys
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import AsyncMock

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
from otel_ai_monitor.models import (  # type: ignore  # noqa: E402
    AITool,
    IdentityConfidence,
    Provider,
    Session,
    SessionState,
)
from otel_ai_monitor.session_tracker import SessionTracker  # type: ignore  # noqa: E402


class _DummyOutput:
    async def start(self) -> None:
        return None

    async def stop(self) -> None:
        return None

    async def write_update(self, update) -> None:  # pragma: no cover - not relevant to heartbeat tests
        return None

    async def write_session_list(self, session_list) -> None:
        return None


@pytest.mark.asyncio
async def test_metrics_heartbeat_does_not_extend_prompt_only_working_session(monkeypatch):
    tracker = SessionTracker(
        output=_DummyOutput(),
        quiet_period_sec=0.05,
        completed_timeout_sec=5.0,
        broadcast_interval_sec=1.0,
    )
    monkeypatch.setattr(
        tracker,
        "_resolve_window_context",
        AsyncMock(return_value=(None, None, {})),
    )

    now = datetime.now(timezone.utc)
    session = Session(
        session_id="codex:pid:321",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CODEX_CLI,
        provider=Provider.OPENAI,
        state=SessionState.WORKING,
        project="PittampalliOrg/workflow-builder:main",
        project_path=None,
        window_id=100,
        pid=321,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        pending_tools=0,
        is_streaming=False,
        state_seq=1,
        status_reason="event:codex.user_prompt",
    )

    await tracker.start()
    try:
        async with tracker._lock:
            tracker._sessions[session.session_id] = session
            tracker._reset_quiet_timer(session.session_id)

        await asyncio.sleep(0.02)
        await tracker.process_heartbeat_for_tool(AITool.CODEX_CLI, pid=321)
        await asyncio.sleep(0.06)

        async with tracker._lock:
            assert tracker._sessions[session.session_id].state == SessionState.COMPLETED
    finally:
        await tracker.stop()


@pytest.mark.asyncio
async def test_metrics_heartbeat_extends_streaming_working_session(monkeypatch):
    tracker = SessionTracker(
        output=_DummyOutput(),
        quiet_period_sec=0.05,
        completed_timeout_sec=5.0,
        broadcast_interval_sec=1.0,
    )
    monkeypatch.setattr(
        tracker,
        "_resolve_window_context",
        AsyncMock(return_value=(None, None, {})),
    )

    now = datetime.now(timezone.utc)
    session = Session(
        session_id="claude-code:pid:654",
        native_session_id=None,
        context_fingerprint=None,
        collision_group_id=None,
        identity_confidence=IdentityConfidence.PID,
        tool=AITool.CLAUDE_CODE,
        provider=Provider.ANTHROPIC,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=169,
        pid=654,
        trace_id=None,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        pending_tools=0,
        is_streaming=True,
        state_seq=1,
        status_reason="event:claude_code.stream_token",
    )

    await tracker.start()
    try:
        async with tracker._lock:
            tracker._sessions[session.session_id] = session
            tracker._reset_quiet_timer(session.session_id)

        await asyncio.sleep(0.02)
        await tracker.process_heartbeat_for_tool(AITool.CLAUDE_CODE, pid=654)
        await asyncio.sleep(0.04)

        async with tracker._lock:
            assert tracker._sessions[session.session_id].state == SessionState.WORKING

        await asyncio.sleep(0.05)
        async with tracker._lock:
            assert tracker._sessions[session.session_id].state == SessionState.COMPLETED
    finally:
        await tracker.stop()
