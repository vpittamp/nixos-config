"""Regression tests for Active AI rail and AI tmux view script wiring."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WINDOWS_VIEW_YUCK = REPO_ROOT / "home-modules" / "desktop" / "eww-monitoring-panel" / "yuck" / "windows-view.yuck.nix"
AI_TMUX_VIEW_NIX = REPO_ROOT / "home-modules" / "desktop" / "eww-monitoring-panel" / "scripts" / "ai-tmux-view.nix"
WINDOWS_SCRIPTS_NIX = REPO_ROOT / "home-modules" / "desktop" / "eww-monitoring-panel" / "scripts" / "windows.nix"


def test_active_ai_rail_visible_in_windows_detail_mode():
    """Rail should stay visible on Windows tab even when detail pane is open."""
    text = WINDOWS_VIEW_YUCK.read_text()
    assert ":visible {current_view_index == 0}" in text
    assert "No active or unread sessions" in text
    assert "current_view_index == 0 && selected_window_id == 0" not in text


def test_active_ai_review_pending_visual_hooks_present():
    """Windows view should include review_pending classes and unread dots."""
    text = WINDOWS_VIEW_YUCK.read_text()
    assert "review_pending ?: false" in text
    assert "active-ai-chip-unread-dot" in text
    assert "ai-badge-unread-dot" in text


def test_ai_tmux_view_supports_unseen_finished_sessions_by_default():
    """ai-tmux-view should include unseen-finished sessions with opt-out flag."""
    text = AI_TMUX_VIEW_NIX.read_text()
    assert "INCLUDE_UNSEEN_FINISHED=true" in text
    assert "--no-unseen-finished" in text
    assert "No active or unread sessions right now." in text


def test_focus_action_emits_seen_ack_event():
    """Focus-active script should emit explicit seen acknowledgements."""
    text = WINDOWS_SCRIPTS_NIX.read_text()
    assert "ack-ai-session-seen-action" in text
    assert "ai-session-seen-events.jsonl" in text


def test_focus_actions_pass_connection_key_for_session_and_badge_clicks():
    """Session and badge focus actions should pass connection identity for SSH tmux targeting."""
    text = WINDOWS_VIEW_YUCK.read_text()
    assert "session.connection_key ?: \"\"" in text
    assert "badge.connection_key ?: window.connection_key ?: \"\"" in text


def test_focus_script_supports_remote_tmux_targeting_over_ssh():
    """Focus script should execute tmux targeting remotely when execution mode is ssh."""
    text = WINDOWS_SCRIPTS_NIX.read_text()
    assert "parse_ssh_connection_key()" in text
    assert "run_remote_tmux()" in text
    assert "-o BatchMode=yes" in text
    assert "tmux_target_remote_ok" in text
    assert "tmux_remote_connection_invalid" in text
