"""Unit tests for session attention state service."""

from __future__ import annotations

import importlib
import importlib.util
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


attention_module = importlib.import_module("i3_project_daemon.services.session_attention_service")

SessionAttentionService = attention_module.SessionAttentionService


def test_background_done_session_becomes_needs_attention() -> None:
    service = SessionAttentionService()
    sessions = [
        {
            "session_key": "session-background",
            "window_id": 101,
            "session_phase": "done",
            "session_phase_label": "Done",
        }
    ]

    service.apply_session_attention_state(
        sessions,
        focused_window_id=202,
        current_session_key="",
    )

    assert sessions[0]["session_phase"] == "needs_attention"
    assert sessions[0]["session_phase_label"] == "Needs attention"
    assert sessions[0]["stopped_notification_pending"] is False
    assert sessions[0]["user_input_notification_pending"] is False


def test_explicit_stop_requires_attention_until_acknowledged() -> None:
    service = SessionAttentionService()
    session = {
        "session_key": "session-stopped",
        "window_id": 101,
        "llm_stopped": True,
        "updated_at": "2026-06-10T22:00:00Z",
        "session_phase": "done",
    }
    sessions = [session]

    service.apply_session_attention_state(
        sessions,
        focused_window_id=202,
        current_session_key="",
    )

    assert session["session_phase"] == "stopped"
    assert session["stopped_notification_pending"] is True
    assert service.stopped_notifications["session-stopped"]["acknowledged"] is False

    assert service.acknowledge_stopped_session_notification(session) is True
    assert session["session_phase"] == "done"
    assert session["stopped_notification_pending"] is False
    assert service.stopped_notifications["session-stopped"]["acknowledged"] is True


@pytest.mark.parametrize("reason", ["elicitation", "permission", "auth", "rate_limit", "max_tokens", "error"])
def test_user_input_boundary_requires_attention_for_supported_reasons(reason: str) -> None:
    service = SessionAttentionService()
    session = {
        "session_key": "session-input",
        "window_id": 101,
        "tool": "codex",
        "notification_boundary_type": "user_input_required",
        "notification_boundary_reason": reason,
        "notification_boundary_at": "2026-06-10T22:00:00Z",
        "process_running": True,
        "session_phase": "working",
    }

    service.apply_session_attention_state(
        [session],
        focused_window_id=202,
        current_session_key="",
    )

    assert session["session_phase"] == "needs_attention"
    assert session["user_input_notification_pending"] is True
    assert service.acknowledge_user_input_session_notification(session) is True
    assert session["session_phase"] == "idle"
    assert session["user_input_notification_pending"] is False
