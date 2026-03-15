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
    assert "function sessionAlias(session)" in text
    assert "session.turn_owner" in text
    assert "session.activity_substate" in text
    assert "session.last_event_name" in text
    assert "session.status_reason" in text
    assert "sessionBadgeLabel(session)" in text


def test_grouped_session_pills_focus_by_session_key():
    """Session pills should focus via canonical session keys."""
    text = SHELL_QML.read_text()
    assert "function focusSession(sessionKey)" in text
    assert "const resolvedSessionKey = stringOrEmpty(sessionData && sessionData.session_key) || stringOrEmpty(sessionKey);" in text
    assert "root.focusSession(session);" in text
    assert "readonly property string activityLabel: sessionEntry ? root.sessionBadgeLabel(entry) : \"\"" in text


def test_session_titles_prefer_host_prefixed_tmux_alias_with_preview_support():
    """Launcher rows and preview titles should use host-prefixed raw pane aliases."""
    text = SHELL_QML.read_text()
    assert "function hostMonogram(mode, hostName, connectionKey)" in text
    assert "function buildSessionAlias(monogram, paneId)" in text
    assert "function sessionAlias(session)" in text
    assert "return prefix.charAt(0) + pane;" in text
    assert "const alias = sessionAlias(session);" in text
    assert "return alias;" in text
    assert "function sessionPreviewTitle()" in text
    assert "buildSessionAlias(" in text
    assert "stringOrEmpty(sessionPreview.tmux_pane)" in text


def test_session_secondary_label_prioritizes_project_and_phase():
    """Session subtitles should show project/worktree and high-level state."""
    text = SHELL_QML.read_text()
    assert "const project = shortProject(stringOrEmpty(session && (session.project_name || session.project || \"\")));" in text
    assert "const phase = compactSessionStateLabel(session);" in text
    assert "project !== \"Global\"" in text
    assert "bits.push(project);" in text
    assert "bits.push(phase);" in text


def test_session_sort_orders_by_host_bucket_before_numeric_pane_slot():
    """Stable ordering should bucket by host before ordering by pane number."""
    text = SHELL_QML.read_text()
    assert "function stableSessionCompare(left, right)" in text
    host_index = text.index("result = compareAscending(sessionHostGroupKey(left), sessionHostGroupKey(right));")
    pane_index = text.index("result = compareAscending(sessionPaneSlot(left), sessionPaneSlot(right));")
    window_index = text.index("result = compareAscending(sessionWindowSlot(left), sessionWindowSlot(right));")
    assert host_index < pane_index < window_index
