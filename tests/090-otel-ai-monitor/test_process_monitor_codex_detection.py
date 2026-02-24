import asyncio
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
from otel_ai_monitor.models import (  # type: ignore  # noqa: E402
    AITool,
    Provider,
    Session,
    SessionState,
)
from otel_ai_monitor.process_monitor import ProcessMonitor  # type: ignore  # noqa: E402


@pytest.mark.parametrize(
    ("cmdline", "expected"),
    [
        ("/nix/store/abc/bin/codex exec \"hello\"", True),
        ("/nix/store/abc/bin/codex", True),
        ("/nix/store/abc/bin/codex-raw --yolo", True),
        ("/nix/store/abc/bin/codex-raw", True),
        ("node /repo/scripts/codex-otel-interceptor.js", False),
        ("/nix/store/abc/bin/gemini", False),
        ("bash -lc echo codex-raw", False),
        ("", False),
    ],
)
def test_is_codex_process_handles_wrapper_and_raw_binary(cmdline, expected):
    monitor = ProcessMonitor(tracker=None)  # type: ignore[arg-type]
    assert monitor._is_codex_process(cmdline) is expected


@pytest.mark.parametrize(
    ("cmdline", "expected"),
    [
        (
            "/nix/store/abc-claude-code/bin/.claude-unwrapped --chrome --print hi",
            True,
        ),
        (
            "/nix/store/abc-claude-code/bin/.claude-unwrapped --chrome-native-host",
            False,
        ),
        (
            "/nix/store/abc-claude-code/bin/.claude-wrapped_ --print hi",
            True,
        ),
        (
            "/etc/profiles/per-user/vpittamp/bin/claude --print hi",
            True,
        ),
        (
            "node /repo/scripts/codex-otel-interceptor.js",
            False,
        ),
        (
            "/nix/store/abc/bin/gemini --print hi",
            False,
        ),
        (
            "",
            False,
        ),
    ],
)
def test_is_claude_process_handles_wrapped_and_native_host_filter(cmdline, expected):
    monitor = ProcessMonitor(tracker=None)  # type: ignore[arg-type]
    assert monitor._is_claude_process(cmdline) is expected


@pytest.mark.parametrize(
    ("cmdline", "expected"),
    [
        (
            "/nix/store/abc/bin/gemini --print hi",
            True,
        ),
        (
            "/nix/store/abc/bin/gemini",
            True,
        ),
        (
            "/nix/store/abc/bin/.gemini-wrapped --yolo",
            True,
        ),
        (
            "/nix/store/node/bin/node /nix/store/abc/bin/.gemini-wrapped --yolo",
            True,
        ),
        (
            "node /repo/scripts/gemini-otel-interceptor.js",
            False,
        ),
        (
            "bash /repo/scripts/gemini-hooks/finished.sh",
            False,
        ),
        (
            "/nix/store/abc/bin/claude --print hi",
            False,
        ),
        (
            "",
            False,
        ),
    ],
)
def test_is_gemini_process_handles_wrapped_and_node_binary(cmdline, expected):
    monitor = ProcessMonitor(tracker=None)  # type: ignore[arg-type]
    assert monitor._is_gemini_process(cmdline) is expected


@pytest.mark.asyncio
async def test_complete_session_resolves_rekeyed_native_session_by_pid():
    class _DummyTracker:
        def __init__(self):
            self._lock = asyncio.Lock()
            self._sessions = {}
            self.enable_notifications = False

        def _mark_dirty_unlocked(self):
            return None

        def _start_completed_timer(self, _session_id: str):
            return None

    tracker = _DummyTracker()
    monitor = ProcessMonitor(tracker=tracker)  # type: ignore[arg-type]
    now = datetime.now(timezone.utc)
    native_session_id = "claude-code:native-sid-1"

    tracker._sessions[native_session_id] = Session(
        session_id=native_session_id,
        native_session_id="native-sid-1",
        tool=AITool.CLAUDE_CODE,
        provider=Provider.ANTHROPIC,
        state=SessionState.WORKING,
        project="vpittamp/nixos-config:main",
        project_path=None,
        window_id=174,
        pid=12345,
        created_at=now,
        last_event_at=now,
        state_changed_at=now,
        state_seq=1,
        status_reason="process_detected",
    )
    # Simulate process map still pointing at stale pre-rekey pid session ID.
    monitor._process_sessions[12345] = "claude-code:pid:12345"

    await monitor._complete_session("claude-code:pid:12345", 12345)

    assert tracker._sessions[native_session_id].state == SessionState.COMPLETED
    assert monitor._process_sessions[12345] == native_session_id
