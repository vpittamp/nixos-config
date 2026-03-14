"""Regression tests for the QuickShell AI/session view wiring."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "shell.qml"


def test_session_phase_prioritizes_review_and_unread_output():
    """Unread output and review-pending sessions should surface as attention."""
    text = SHELL_QML.read_text()
    assert "function sessionPhase(session)" in text
    assert "session.output_unseen" in text
    assert "session.review_pending" in text
    assert "return \"needs_attention\";" in text


def test_session_activity_uses_explicit_work_signals_and_ignores_stale_state():
    """Animation/motion should be driven by explicit work signals, not old broad stage heuristics."""
    text = SHELL_QML.read_text()
    assert "function sessionIsActivelyProcessing(session)" in text
    assert "session.pulse_working" in text
    assert "session.is_streaming" in text
    assert "pendingTools > 0" in text
    assert "session.output_ready" in text
    assert "session.output_unseen" in text
    assert "session.remote_source_stale" in text
    assert "freshness === \"stale\"" in text


def test_session_badge_uses_turn_owner_and_activity_substate_labels():
    """Launcher/session chips should expose telemetry-derived owner + substate labels."""
    text = SHELL_QML.read_text()
    assert "function sessionTurnOwnerLabel(session)" in text
    assert "function sessionActivitySubstateLabel(session)" in text
    assert "function sessionBadgeLabel(session)" in text
    assert "ownerLabel + \" · \" + substateLabel" in text
    assert "session.turn_owner" in text
    assert "session.activity_substate" in text


def test_session_badge_symbol_and_attention_hooks_cover_unread_output():
    """Badge symbol/state should react to blocked or unread-output conditions."""
    text = SHELL_QML.read_text()
    assert "function sessionBadgeSymbol(session)" in text
    assert "owner === \"blocked\" || state === \"needs_attention\"" in text
    assert "session.output_ready" in text
    assert "session.output_unseen" in text


def test_launcher_session_search_indexes_telemetry_fields():
    """Launcher session search should include telemetry-derived state terms."""
    text = SHELL_QML.read_text()
    assert "session.turn_owner" in text
    assert "session.activity_substate" in text
    assert "session.last_event_name" in text
    assert "session.status_reason" in text
    assert "sessionBadgeLabel(session)" in text


def test_grouped_session_pills_focus_by_session_key():
    """Session pills should focus via canonical session keys."""
    text = SHELL_QML.read_text()
    assert "root.focusSession(root.stringOrEmpty(session.session_key));" in text
    assert "readonly property string activityLabel: root.sessionBadgeLabel(session)" in text

