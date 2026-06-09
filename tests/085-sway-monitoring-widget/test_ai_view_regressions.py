"""Regression tests for the QuickShell AI/session view wiring."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "shell.qml"
SESSION_ROW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "SessionRow.qml"
LAUNCHER_WINDOW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "windows" / "LauncherWindow.qml"
QUICKSHELL_DEFAULT_NIX = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "default.nix"
NOTIFICATION_TOAST_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "NotificationToast.qml"


def test_session_phase_prefers_raw_herdr_agent_status():
    """Herdr agent status should drive AI row state before legacy telemetry fields."""
    text = SHELL_QML.read_text()
    assert "function sessionPhase(session)" in text
    herdr_index = text.index("const rawHerdrStatus = stringOrEmpty(session && session.agent_status);")
    legacy_index = text.index("const phase = stringOrEmpty(session && session.session_phase).toLowerCase();")
    assert herdr_index < legacy_index
    assert "return herdrStatusState(rawHerdrStatus);" in text


def test_session_display_eligibility_accepts_herdr_panes_without_tmux_identity():
    """Herdr panes should be visible without terminal anchors or tmux fields."""
    text = SHELL_QML.read_text()
    assert "function sessionIsDisplayEligible(session)" in text
    assert "function sessionIsPanelDisplayEligible(session)" in text
    assert "stringOrEmpty(session.source) === \"herdr\" || stringOrEmpty(session.pane_id)" in text
    assert "return stringOrEmpty(session.pane_id).length > 0;" in text


def test_session_status_chip_renders_raw_herdr_status():
    """Session chips should title-case Herdr's status rather than custom lifecycle labels."""
    text = SHELL_QML.read_text()
    assert "function sessionActivityChipLabel(session)" in text
    assert "[\"working\", \"blocked\", \"done\", \"idle\", \"unknown\"].indexOf(state) >= 0" in text
    assert "return titleCaseWord(state);" in text
    assert "if (badgeState === \"blocked\")" in text
    assert "return \"Blocked\";" in text


def test_session_badge_symbol_and_attention_hooks_cover_blocked_herdr_status():
    """Badge symbol/state should react to Herdr blocked status directly."""
    text = SHELL_QML.read_text()
    assert "function sessionBadgeSymbol(session)" in text
    assert "if (state === \"blocked\")" in text
    assert "return \"!\";" in text
    assert "return phase === \"needs_attention\" || phase === \"blocked\";" in text


def test_current_session_highlight_uses_local_herdr_focus():
    """Current row highlighting should trust local Herdr focus before old session-key heuristics."""
    text = SHELL_QML.read_text()
    assert "function sessionIsCurrent(session)" in text
    focused_index = text.index("if (boolOrFalse(session && session.focused) && boolOrFalse(session && session.is_current_host))")
    key_index = text.index("return current === sessionIdentityKey(session) || current === stringOrEmpty(session && session.session_key);")
    assert focused_index < key_index


def test_launcher_session_search_indexes_herdr_fields():
    """Launcher session search should include Herdr-native status and identity terms."""
    text = SHELL_QML.read_text()
    assert "sessionPrimaryLabel(session)" in text
    assert "sessionSecondaryLabel(session)" in text
    assert "session && session.agent_status" in text
    assert "session && session.foreground_cwd" in text
    assert "session && session.cwd" in text
    assert "sessionBadgeLabel(session)" in text


def test_session_rows_focus_by_explicit_herdr_target():
    """Session rows should use daemon Herdr focus targets instead of tmux/window heuristics."""
    text = SHELL_QML.read_text()
    assert "function focusSession(sessionKey)" in text
    assert "function sessionFocusTarget(sessionOrKey)" in text
    assert "const explicitTarget = normalizedFocusTarget(sessionOrKey.focus_target);" in text
    assert "stringOrEmpty(sessionOrKey.source) === \"herdr\" || stringOrEmpty(sessionOrKey.pane_id)" in text
    assert "return explicitTarget;" in text
    assert "const target = sessionFocusTarget(sessionData || resolvedSessionKey);" in text
    assert "runFocusTarget(target);" in text


def test_side_panel_sessions_close_by_explicit_herdr_target():
    """Session rows should call Herdr close targets when provided."""
    text = SHELL_QML.read_text()
    assert "function sessionCloseTarget(session)" in text
    assert "return normalizedFocusTarget(session.close_target);" in text
    assert "function sessionHasClosableSurface(session)" in text
    assert "if (sessionCloseTarget(session))" in text
    assert "function closeSession(session)" in text
    assert "const explicitCloseTarget = sessionCloseTarget(session);" in text
    assert "runDaemonCall(explicitCloseTarget.method, explicitCloseTarget.params);" in text

    row_text = SESSION_ROW_QML.read_text()
    assert "property bool showCloseAction: interactive" in row_text
    assert "readonly property bool closableSurface: showCloseAction && rootObject.sessionHasClosableSurface(session)" in row_text
    assert "signal closeRequested" in row_text
    assert "visible: closableSurface" in row_text
    assert "z: 2" in row_text
    assert "sessionRow.closeRequested();" in row_text
    assert "id: sessionRowMouse" in row_text
    assert "z: 0" in row_text


def test_session_titles_prefer_herdr_agent_and_project():
    """Launcher rows should title Herdr sessions by agent and worktree/project."""
    text = SHELL_QML.read_text()
    assert "function sessionPrimaryLabel(session)" in text
    assert "const agent = toolLabel(session);" in text
    assert "const project = shortProject(stringOrEmpty(session && (session.project_name || session.project || \"\")));" in text
    assert "stringOrEmpty(session && session.source) === \"herdr\" || stringOrEmpty(session && session.pane_id)" in text
    assert "const host = displayHostName(stringOrEmpty(session && (session.herdr_host || session.host_name)));" in text
    assert "const isRemote = boolOrFalse(session && session.is_remote_herdr);" in text
    assert "bits.push(host);" in text
    assert "return bits.join(\" · \") || \"AI Session\";" in text


def test_session_secondary_label_uses_herdr_status_and_cwd():
    """Session subtitles should use Herdr status and cwd/foreground cwd."""
    text = SHELL_QML.read_text()
    assert "function sessionSecondaryLabel(session)" in text
    assert "const herdrStatus = stringOrEmpty(session && session.agent_status).toLowerCase();" in text
    assert "bits.push(titleCaseWord(herdrStatus));" in text
    assert "const foregroundCwd = stringOrEmpty(session && session.foreground_cwd);" in text
    assert "const cwd = stringOrEmpty(session && session.cwd);" in text
    assert "bits.push(parts[parts.length - 1]);" in text
    assert "return bits.join(\" • \");" in text


def test_launcher_preview_for_herdr_sessions_is_focus_only():
    """Herdr sessions should not start the old live tmux/session preview process."""
    text = SHELL_QML.read_text()
    launcher_text = LAUNCHER_WINDOW_QML.read_text()
    assert "if (stringOrEmpty(entry.source) === \"herdr\" || stringOrEmpty(entry.pane_id))" in text
    assert "message: \"Focus this Herdr pane to inspect live output.\"" in text
    assert "return;" in text
    assert "function sessionPreviewStatusText()" in text
    assert "root.sessionPreviewStatusText()" in launcher_text


def test_agent_action_toasts_bypass_general_toast_suppression_only_for_i3pm_agent():
    """Action-required agent notifications get a narrow toast allowance when general toasts are disabled."""
    shell_text = SHELL_QML.read_text()
    nix_text = QUICKSHELL_DEFAULT_NIX.read_text()
    toast_text = NOTIFICATION_TOAST_QML.read_text()

    assert "notificationAgentActionToastMaxPerOutput" in nix_text
    assert "agentActionToastMaxPerOutput = lib.mkOption" in nix_text
    assert "function notificationIsAgentAction(item)" in shell_text
    assert "appName === \"i3pm-agent\" || desktopEntry === \"i3pm-agent\"" in shell_text
    assert "const regularItems = toastLimit > 0 ? candidates.filter(item => !notificationIsAgentAction(item)).slice(0, toastLimit) : [];" in shell_text
    assert "const agentActionItems = agentActionToastLimit > 0 ? candidates.filter(item => notificationIsAgentAction(item)).slice(0, agentActionToastLimit) : [];" in shell_text
    assert "readonly property bool agentAction: rootObject.notificationIsAgentAction(itemData)" in toast_text
    assert "radius: agentAction ? 8 : 20" in toast_text


def test_session_sort_orders_by_host_bucket_before_numeric_pane_slot():
    """Stable ordering should bucket by host before ordering by pane number."""
    text = SHELL_QML.read_text()
    assert "function stableSessionCompare(left, right)" in text
    host_index = text.index("result = compareAscending(sessionHostGroupKey(left), sessionHostGroupKey(right));")
    pane_index = text.index("result = compareAscending(sessionPaneSlot(left), sessionPaneSlot(right));")
    window_index = text.index("result = compareAscending(sessionWindowSlot(left), sessionWindowSlot(right));")
    assert host_index < pane_index < window_index
