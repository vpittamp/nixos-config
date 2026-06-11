"""Regression tests for the QuickShell AI/session view wiring."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "shell.qml"
SESSION_ROW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "SessionRow.qml"
LAUNCHER_WINDOW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "windows" / "LauncherWindow.qml"
RUNTIME_PANEL_WINDOW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "windows" / "RuntimePanelWindow.qml"
RUNTIME_SERVICES_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "controllers" / "RuntimeServices.qml"
QUICKSHELL_DEFAULT_NIX = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "default.nix"
SWAY_KEYBINDINGS_NIX = REPO_ROOT / "home-modules" / "desktop" / "sway-keybindings.nix"
NOTIFICATION_TOAST_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "NotificationToast.qml"
WORKTREE_APP_SERVICE_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-worktree-app" / "WorktreeAppService.qml"
WORKTREE_APP_SHELL_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-worktree-app" / "shell.qml"
WORKTREE_APP_DEFAULT_NIX = REPO_ROOT / "home-modules" / "desktop" / "quickshell-worktree-app" / "default.nix"
HERDR_NIX = REPO_ROOT / "home-modules" / "terminal" / "herdr.nix"
TMUX_NIX = REPO_ROOT / "home-modules" / "terminal" / "tmux.nix"
CLAUDE_CODE_NIX = REPO_ROOT / "home-modules" / "ai-assistants" / "claude-code.nix"
CODEX_NIX = REPO_ROOT / "home-modules" / "ai-assistants" / "codex.nix"
COPILOT_CLI_NIX = REPO_ROOT / "home-modules" / "ai-assistants" / "copilot-cli.nix"
I3PM_WINDOW_TS = REPO_ROOT / "home-modules" / "tools" / "i3pm" / "src" / "commands" / "window.ts"
I3PM_DASHBOARD_TS = REPO_ROOT / "home-modules" / "tools" / "i3pm" / "src" / "commands" / "dashboard.ts"
I3PM_HERDR_PROXY_TS = REPO_ROOT / "home-modules" / "tools" / "i3pm" / "src" / "commands" / "herdr-proxy.ts"
I3PM_SESSION_TS = REPO_ROOT / "home-modules" / "tools" / "i3pm" / "src" / "commands" / "session.ts"
I3PM_MAIN_TS = REPO_ROOT / "home-modules" / "tools" / "i3pm" / "src" / "main.ts"
I3PM_DAEMON_CLIENT_TS = REPO_ROOT / "home-modules" / "tools" / "i3pm" / "src" / "services" / "daemon-client.ts"
IPC_SERVER_PY = REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "ipc_server.py"
DAEMON_DIR = REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon"
DAEMON_SERVICES_DIR = REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "services"
HERDR_SERVICE_PY = DAEMON_SERVICES_DIR / "herdr_service.py"
LAUNCH_SERVICE_PY = DAEMON_SERVICES_DIR / "launch_service.py"
DASHBOARD_MODEL_PY = DAEMON_SERVICES_DIR / "dashboard_model.py"
FOCUS_SERVICE_PY = DAEMON_SERVICES_DIR / "focus_service.py"
SESSION_RUNTIME_SERVICE_PY = DAEMON_SERVICES_DIR / "session_runtime_service.py"
PROJECT_REMOTE_LAUNCH_PY = REPO_ROOT / "scripts" / "project-remote-launch.py"
I3PM_MONITORING_DATA_PY = REPO_ROOT / "home-modules" / "tools" / "i3_project_manager" / "cli" / "monitoring_data.py"
I3PM_CLI_README = REPO_ROOT / "home-modules" / "tools" / "i3_project_manager" / "cli" / "README.md"
AI_SESSION_SYSTEM_DOC = REPO_ROOT / "docs" / "AI_SESSION_SYSTEM.md"


def test_session_phase_uses_only_raw_herdr_agent_status():
    """Herdr agent status should be the only AI row state authority."""
    text = SHELL_QML.read_text()
    assert "function sessionPhase(session)" in text
    session_phase_body = text.split("function sessionPhase(session)", 1)[1].split("function ", 1)[0]
    assert "return herdrStatusState(session && session.agent_status);" in session_phase_body
    retired_terms = [
        "session_phase",
        "stage_visual_state",
        "output_unseen",
        "review_pending",
        "needs_user_action",
        "output_ready",
        "process_running",
        "turn_owner",
        "activity_substate",
        "status_reason",
    ]
    for term in retired_terms:
        assert term not in text


def test_session_preview_and_worktree_app_do_not_render_legacy_phase_fields():
    """Secondary QuickShell surfaces should not render custom session phase metadata."""
    launcher_text = LAUNCHER_WINDOW_QML.read_text()
    worktree_text = WORKTREE_APP_SHELL_QML.read_text()
    retired_terms = [
        "session_phase",
        "turn_owner",
        "activity_substate",
        "status_reason",
        "sessionPreviewOwnerChip",
    ]
    for term in retired_terms:
        assert term not in launcher_text
        assert term not in worktree_text
    assert "const phase = stringOrEmpty(session && session.agent_status) || \"idle\";" in worktree_text
    assert "tmux_pane" not in worktree_text
    assert "const pane = stringOrEmpty(session && (session.pane_id || session.pane_label));" in worktree_text


def test_ai_session_status_does_not_use_notification_boundary_adapters():
    """Notification-derived status fields should not drive the AI session UI."""
    shell_text = SHELL_QML.read_text()
    daemon_text = IPC_SERVER_PY.read_text()
    service_text = "\n".join(path.read_text() for path in DAEMON_SERVICES_DIR.glob("*.py"))

    retired_fields = [
        "notification_boundary_type",
        "user_input_notification_pending",
        "stopped_notification_pending",
        "llm_stopped",
        "explicit_complete",
    ]
    for field in retired_fields:
        assert field not in shell_text

    assert "SessionAttentionService" not in daemon_text
    assert "session_attention_service" not in daemon_text
    for field in retired_fields[:3]:
        assert field not in service_text


def test_assistant_desktop_rpc_surface_is_retired():
    """The old assistant.desktop RPC should not compete with Herdr/dashboard state."""
    daemon_text = IPC_SERVER_PY.read_text()
    client_text = I3PM_DAEMON_CLIENT_TS.read_text()

    assert not (DAEMON_SERVICES_DIR / "assistant_desktop_service.py").exists()
    assert "assistant.desktop" not in daemon_text
    assert "_assistant_desktop" not in daemon_text
    assert "AssistantDesktopService" not in daemon_text
    assert "assistant.desktop" not in client_text
    assert "getAssistantDesktopSnapshot" not in client_text


def test_provider_completion_hooks_do_not_drive_ai_session_state():
    claude_text = CLAUDE_CODE_NIX.read_text()
    codex_text = CODEX_NIX.read_text()

    assert "scripts/claude-hooks/finished.sh" not in claude_text
    assert "Stop = [{" not in claude_text
    assert "scripts/codex-hooks/notify.js" not in codex_text
    assert "notify = [" not in codex_text
    assert not (REPO_ROOT / "scripts" / "claude-hooks" / "finished.sh").exists()
    assert not (REPO_ROOT / "scripts" / "claude-hooks" / "stop-notification-simple.sh.bak").exists()
    assert not (REPO_ROOT / "scripts" / "claude-hooks" / "bash-history.sh").exists()
    assert not (REPO_ROOT / "scripts" / "codex-hooks" / "notify.js").exists()


def test_retired_ai_finished_notification_helper_is_not_active():
    copilot_text = COPILOT_CLI_NIX.read_text()

    assert not (REPO_ROOT / "scripts" / "ai-finished-notification.sh").exists()
    assert not (
        REPO_ROOT
        / "home-modules"
        / "desktop"
        / "i3-project-event-daemon"
        / "models"
        / "notification_context.py"
    ).exists()
    assert not (
        REPO_ROOT
        / "tests"
        / "079-preview-pane-user-experience"
        / "test_notification_click.py"
    ).exists()
    assert "minimal-otel-interceptor" not in copilot_text
    assert "Claude Code's interceptor" not in copilot_text
    assert not (REPO_ROOT / "tests" / "091-optimize-i3pm-project" / "debug_notification_system.sh").exists()
    assert not (REPO_ROOT / "tests" / "091-optimize-i3pm-project" / "test_manual_notification.sh").exists()
    assert not (REPO_ROOT / "tests" / "091-optimize-i3pm-project" / "test_notification_callback.sh").exists()
    assert not (REPO_ROOT / "tests" / "091-optimize-i3pm-project" / "test_notification_simple.sh").exists()


def test_retired_notification_badge_service_is_not_active_runtime_state():
    daemon_text = IPC_SERVER_PY.read_text()
    services_text = (REPO_ROOT / "home-modules" / "services" / "i3-project-daemon.nix").read_text()
    monitoring_data_text = I3PM_MONITORING_DATA_PY.read_text()
    daemon_client_text = (REPO_ROOT / "home-modules" / "tools" / "i3_project_manager" / "core" / "daemon_client.py").read_text()
    handlers_text = (REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "handlers.py").read_text()

    assert not (REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "badge_service.py").exists()
    assert "create_badge" not in daemon_text
    assert "clear_badge" not in daemon_text
    assert "get_badge_state" not in daemon_text
    assert "badge_state" not in daemon_text
    assert "i3pm-badges" not in services_text
    assert "load_badge_state_from_files" not in monitoring_data_text
    assert "create_badge_watcher" not in monitoring_data_text
    assert "i3pm-badges" not in monitoring_data_text
    assert "get_badge_state" not in daemon_client_text
    assert "badge_service" not in handlers_text


def test_session_display_eligibility_accepts_herdr_panes_without_tmux_identity():
    """AI session display eligibility should be Herdr-native, not tmux-derived."""
    text = SHELL_QML.read_text()
    assert "function sessionIsDisplayEligible(session)" in text
    assert "function sessionIsPanelDisplayEligible(session)" in text
    assert "stringOrEmpty(session.source) === \"herdr\" || stringOrEmpty(session.pane_id)" in text
    assert "return stringOrEmpty(session.pane_id).length > 0;" in text
    eligibility_body = text.split("function sessionIsDisplayEligible(session)", 1)[1].split("function sessionIsPanelDisplayEligible", 1)[0]
    panel_eligibility_body = text.split("function sessionIsPanelDisplayEligible(session)", 1)[1].split("function stableSessionCompare", 1)[0]
    for body in [eligibility_body, panel_eligibility_body]:
        assert "terminal_anchor_id" not in body
        assert "tmux_session" not in body
        assert "tmux_window" not in body
        assert "tmux_pane" not in body
        assert "process_running" not in body


def test_session_preview_and_sorting_use_herdr_pane_identity_not_tmux_fields():
    """Launcher session preview/sorting should not reintroduce tmux pane identity."""
    text = SHELL_QML.read_text()
    session_preview_body = text.split("function emptySessionPreview()", 1)[1].split("function activeLauncherSessionEntry", 1)[0]
    restart_preview_body = text.split("function restartSessionPreview()", 1)[1].split("function ensureSessionPreviewForSelection", 1)[0]
    preview_title_body = text.split("function sessionPreviewTitle()", 1)[1].split("function sessionPreviewSubtitle", 1)[0]
    preview_subtitle_body = text.split("function sessionPreviewSubtitle()", 1)[1].split("function sessionPreviewSemanticBits", 1)[0]
    stable_compare_body = text.split("function stableSessionCompare(left, right)", 1)[1].split("function stableSortedSessions", 1)[0]
    launcher_compare_body = text.split("function launcherSessionCompare(left, right)", 1)[1].split("function launcherSessionGroups", 1)[0]

    for body in [
        session_preview_body,
        restart_preview_body,
        preview_title_body,
        preview_subtitle_body,
        stable_compare_body,
        launcher_compare_body,
    ]:
        assert "tmux_session" not in body
        assert "tmux_window" not in body
        assert "tmux_pane" not in body

    assert "stringOrEmpty(session && (session.pane_id || session.pane_label))" in text
    assert "const paneId = stringOrEmpty(session && session.pane_id).trim();" in text


def test_project_window_cards_do_not_embed_ai_session_badges():
    """Herdr sessions should stay in session surfaces, not project/window badges."""
    shell_text = SHELL_QML.read_text()
    runtime_panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    launcher_text = LAUNCHER_WINDOW_QML.read_text()
    dashboard_model_text = DASHBOARD_MODEL_PY.read_text()

    for text in [shell_text, runtime_panel_text, launcher_text]:
        assert "windowSessionIcons" not in text
        assert "windowSessionOverflowCount" not in text
        assert "ai_session_count" not in text
        assert "windowData.sessions" not in text

    assert '"sessions": session_items' not in dashboard_model_text
    assert '"ai_session_count"' not in dashboard_model_text


def test_focus_state_active_session_uses_herdr_identity_not_tmux_fields():
    """Daemon focus_state should expose Herdr pane identity, not tmux pane identity."""
    text = FOCUS_SERVICE_PY.read_text()
    focus_body = text.split("def build_focus_state_payload", 1)[1].split("def ", 1)[0]

    assert '"current_herdr_pane_id": str(active_session.get("pane_id") or "").strip(),' in focus_body
    assert '"pane_id": str(active_session.get("pane_id") or "").strip(),' in focus_body
    assert "active_session.get(\"tmux_pane\")" not in focus_body
    assert '"tmux_session"' not in focus_body
    assert '"tmux_window"' not in focus_body
    assert '"tmux_pane"' not in focus_body


def test_daemon_session_rows_strip_legacy_tmux_identity_fields():
    """Daemon AI session rows should expose Herdr identity, not terminal/tmux identity."""
    herdr_text = (REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "services" / "herdr_service.py").read_text()
    ipc_text = IPC_SERVER_PY.read_text()

    assert "RETIRED_SESSION_UI_STATE_FIELDS" in herdr_text
    assert '"terminal_context"' in herdr_text
    assert '"tmux_session"' in herdr_text
    assert "if key not in RETIRED_SESSION_UI_STATE_FIELDS" in herdr_text
    assert "if key not in RETIRED_SESSION_UI_STATE_FIELDS" in ipc_text


def test_session_status_chip_renders_raw_herdr_status():
    """Session chips should title-case Herdr's status rather than custom lifecycle labels."""
    text = SHELL_QML.read_text()
    assert "function sessionActivityChipLabel(session)" in text
    assert "[\"working\", \"blocked\", \"done\", \"idle\", \"unknown\"].indexOf(state) >= 0" in text
    assert "return [\"working\", \"blocked\", \"done\", \"idle\", \"unknown\"].indexOf(state) >= 0 ? herdrStatusLabel(session) : compactSessionStateLabel(session);" in text
    assert "if (badgeState === \"blocked\")" in text
    assert "return \"Blocked\";" in text


def test_session_badge_symbol_and_attention_hooks_cover_blocked_herdr_status():
    """Badge symbol/state should react to Herdr blocked status directly."""
    text = SHELL_QML.read_text()
    assert "function sessionBadgeSymbol(session)" in text
    assert "if (state === \"blocked\")" in text
    assert "return \"!\";" in text
    assert "return sessionPhase(session) === \"blocked\";" in text


def test_current_session_highlight_uses_single_dashboard_current_key():
    """Current row highlighting should use the daemon focus_state key only."""
    text = SHELL_QML.read_text()
    assert "function sessionIsCurrent(session)" in text
    assert "function currentSessionKey()" in text
    assert "dashboardFocusState().current_session_key" in text
    current_index = text.index("if (current) {\n            return sessionMatchesKey(session, current);\n        }")
    false_index = text.index("return false;", current_index)
    assert current_index < false_index
    assert "return boolOrFalse(session && session.focused) && boolOrFalse(session && session.is_current_host);" not in text


def test_session_rows_use_daemon_focus_state_for_current_highlight():
    """Session rows should render current state from daemon focus_state, not local optimism."""
    text = SHELL_QML.read_text()
    panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    launcher_text = LAUNCHER_WINDOW_QML.read_text()
    row_text = SESSION_ROW_QML.read_text()

    assert "property bool currentOverride: false" in row_text
    assert "readonly property bool isCurrent: currentOverride || rootObject.sessionIsCurrent(session)" in row_text
    assert "function sessionMatchesKey(session, key)" in text
    assert "function pendingFocusIntent()" in text
    assert "function pendingFocusIntentMatches(kind, targetKey)" in text
    assert "function sessionPendingFocusTargetKey(session)" in text
    assert 'pendingFocusIntentMatches("herdr_pane_focus", pendingSessionTarget)' in text
    assert "optimisticCurrentSessionKey" not in text
    assert "optimisticCurrentSessionKey" not in panel_text
    assert "optimisticCurrentSessionKey" not in launcher_text
    assert "selected: root.sessionMatchesKey(modelData, root.selectedSessionKey)" in panel_text
    assert "currentOverride: root.sessionIsCurrent(modelData)" in panel_text
    assert "currentOverride: root.sessionIsCurrent(entry)" in launcher_text
    assert "const current = currentSessionKey();" in text
    current_session_key_body = text.split("function currentSessionKey()", 1)[1].split("function sessionMatchesKey", 1)[0]
    assert "dashboard.current_ai_session_key" not in current_session_key_body
    assert "dashboardFocusState().current_ai_session_key" not in current_session_key_body
    assert "current_ai_session_key: \"\"" not in text


def test_daemon_runtime_uses_current_session_key_not_retired_ai_alias():
    """Runtime snapshots should not keep the retired AI-specific current-session alias alive."""
    daemon_text = (REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "ipc_server.py").read_text()
    focus_service_text = (
        REPO_ROOT
        / "home-modules"
        / "desktop"
        / "i3-project-event-daemon"
        / "services"
        / "focus_service.py"
    ).read_text()
    dashboard_git_text = (
        REPO_ROOT
        / "home-modules"
        / "desktop"
        / "i3-project-event-daemon"
        / "services"
        / "dashboard_git_service.py"
    ).read_text()

    active_runtime_text = "\n".join([daemon_text, focus_service_text, dashboard_git_text])
    assert 'runtime_snapshot["current_session_key"] = current_session_key' in daemon_text
    assert 'runtime_snapshot["current_ai_session_key"]' not in active_runtime_text
    assert 'runtime_snapshot.get("current_ai_session_key")' not in active_runtime_text
    assert '"current_ai_session_key_after"' not in daemon_text


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
    services_text = (REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "controllers" / "RuntimeServices.qml").read_text()
    assert "function focusSession(sessionKey)" in text
    assert "function sessionFocusTarget(sessionOrKey)" in text
    assert "const explicitTarget = normalizedFocusTarget(sessionOrKey.focus_target);" in text
    assert "function sessionByKey(sessionKey)" in text
    assert "return session ? normalizedFocusTarget(session.focus_target) : null;" in text
    assert "return explicitTarget;" in text
    assert "const target = sessionFocusTarget(sessionData || resolvedSessionKey);" in text
    assert "runFocusTarget(target);" in text
    assert 'method: "session.focus"' not in text
    assert "sessionSpawnRemoteAttachTarget" not in text
    assert "function sendDaemonAction(method, params)" in services_text
    assert "Socket {" in services_text
    assert "daemonActionSocket.write(JSON.stringify(request) + \"\\n\");" in services_text
    assert "runDaemonAction(normalizedTarget.method, normalizedTarget.params);" in text


def test_worktree_app_session_focus_uses_explicit_herdr_target():
    """Standalone Worktree Manager must not call the retired session focus CLI."""
    shell_text = WORKTREE_APP_SHELL_QML.read_text()
    service_text = WORKTREE_APP_SERVICE_QML.read_text()

    assert "function focusSession(session)" in service_text
    assert "normalizedActionTarget(session && session.focus_target)" in service_text
    assert '"daemon", "call", normalizedMethod' in service_text
    assert '"session", "focus"' not in service_text
    assert "i3pmBin, \"session\"" not in service_text
    assert "appService.focusSession(modelData)" in shell_text
    assert "appService.focusSession(root.stringOrEmpty(modelData.session_key))" not in shell_text


def test_retired_session_bridge_cleanup_surface_stays_removed():
    """Herdr sessions should not revive the old tmux bridge cleanup/doctor path."""
    daemon_text = IPC_SERVER_PY.read_text()
    herdr_service_text = HERDR_SERVICE_PY.read_text()
    launch_service_text = LAUNCH_SERVICE_PY.read_text()
    remote_launch_text = PROJECT_REMOTE_LAUNCH_PY.read_text()
    session_cli_text = I3PM_SESSION_TS.read_text()

    assert not SESSION_RUNTIME_SERVICE_PY.exists()
    for retired in [
        "SessionRuntimeService",
        "session_runtime_service",
        '"session.cleanup"',
        '"session.doctor"',
        "_session_cleanup",
        "_session_doctor",
        "_reconcile_session_runtime_state",
        "_load_session_items",
    ]:
        assert retired not in daemon_text

    for retired in [
        "stale_remote_bridge_windows",
        "bridge_diagnostics",
        "remote_bridge_window_mismatch_reason",
    ]:
        assert retired not in herdr_service_text

    for retired in [
        "build_remote_session_attach_spec",
        "prepare_remote_session_attach_spec",
        "remote_session_terminal_role",
        "attach_ai_session",
    ]:
        assert retired not in launch_service_text

    for retired in [
        "build_remote_attach_script",
        "attach_ai_session",
        "attach-session",
        "select-pane",
        "remote AI attach requires exact tmux",
    ]:
        assert retired not in remote_launch_text
    assert "remote AI tmux attach specs are retired" in remote_launch_text

    assert "session.cleanup" not in session_cli_text
    assert "session.doctor" not in session_cli_text
    assert "cleanup" not in session_cli_text
    assert "doctor" not in session_cli_text


def test_retired_remote_ai_bridge_metadata_stays_removed():
    """Remote AI rows should be Herdr-native, not local tmux bridge windows."""
    active_daemon_text = "\n".join(
        path.read_text()
        for path in [
            IPC_SERVER_PY,
            DAEMON_DIR / "handlers.py",
            DAEMON_DIR / "state.py",
            DAEMON_DIR / "models" / "legacy.py",
            DAEMON_SERVICES_DIR / "window_filter.py",
        ]
    )
    shell_text = SHELL_QML.read_text()

    for retired in [
        "I3PM_REMOTE_SESSION_KEY",
        "I3PM_REMOTE_SURFACE_KEY",
        "I3PM_REMOTE_TMUX",
        "remote_session_key",
        "remote_surface_key",
        "remote_tmux_",
    ]:
        assert retired not in active_daemon_text

    for retired in [
        "remote_bridge_bound",
        "remote_bridge_attachable",
        "remote_spawnable",
        "bridge_window_id",
        "remote_source_stale",
        "tmux_missing",
        "stale_source",
        "exact_remote_tmux_attachable",
        "exact_remote_bridge_bound",
    ]:
        assert retired not in shell_text

    assert "remote_herdr_attach" in shell_text


def test_local_window_and_workspace_clicks_use_fast_focus_without_optimistic_state():
    """Click-driven local window/workspace focus should use fast daemon calls and daemon focus_state."""
    text = SHELL_QML.read_text()
    runtime_panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    bottom_bar_text = (REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "windows" / "BottomBarWindow.qml").read_text()
    window_command_text = I3PM_WINDOW_TS.read_text()

    assert "optimisticFocusedWindowId" not in text
    assert "optimisticFocusedWorkspaceName" not in text
    assert "function dashboardFocusState()" in text
    assert "dashboardFocusState().current_window_id" in text
    assert "dashboardFocusState().current_workspace_name" in text
    window_focus_body = text.split("function windowIsFocused(windowData)", 1)[1].split("function windowIsCurrentTarget", 1)[0]
    assert "dashboardFocusState().focused_window_id" not in window_focus_body
    assert 'pendingFocusIntentMatches("window_focus", String(windowId))' in window_focus_body
    focus_command_body = text.split("if (windowFastFocusEligible(windowData))", 1)[1].split("if (explicitTarget)", 1)[0]
    assert "windowData.current_ai_session_key" not in focus_command_body
    assert "const focused = workspaceIsFocused(name);" in text
    workspace_focus_body = text.split("function workspaceIsFocused(workspace)", 1)[1].split("function workspaceChipFill", 1)[0]
    assert 'pendingFocusIntentMatches("workspace_focus", workspaceName)' in workspace_focus_body
    assert "focused: boolOrFalse(workspace?.focused)" not in text
    assert "output.current_workspace" not in text
    assert "focused: windowIsFocused(windowData)" in text
    assert "const leftFocused = windowIsFocused(left);" in text
    assert "method: \"window.focus_fast\"" in text
    assert "runDaemonSocketCall(\"workspace.focus_fast\", {workspace: workspaceName})" in text
    assert "root.windowIsFocused(windowData)" in runtime_panel_text
    assert "root.workspaceIsFocused(workspace)" in bottom_bar_text
    assert "client.request(\"window.focus_fast\", params)" in window_command_text
    assert "fallback_method === \"window.focus\"" in window_command_text


def test_dashboard_watch_uses_reducer_style_snapshot_and_event_paths():
    """Dashboard updates should flow through snapshot/event reducers, not direct raw replacement."""
    text = SHELL_QML.read_text()
    services_text = (REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "controllers" / "RuntimeServices.qml").read_text()
    worktree_service_text = WORKTREE_APP_SERVICE_QML.read_text()
    dashboard_command_text = I3PM_DASHBOARD_TS.read_text()
    daemon_client_text = I3PM_DAEMON_CLIENT_TS.read_text()
    quickshell_default_nix_text = QUICKSHELL_DEFAULT_NIX.read_text()
    assert "function applySnapshot(snapshot)" in text
    assert "function applyEvent(event)" in text
    assert "function resetDashboard(status, errorMessage)" in text
    assert "function afterDashboardApplied()" in text
    assert "const eventGeneration = dashboardGeneration(event);" in text
    assert "if (eventGeneration >= 0 && currentGeneration >= 0 && eventGeneration <= currentGeneration)" in text
    assert "eventType === \"dashboard.invalidated\"" in text
    assert "changedKeys.indexOf(\"dashboard\") !== -1" in text
    assert "Object.assign({}, dashboard, payload" in text
    assert "applyEvent(parsed);" in text
    assert "applySnapshot(parsed);" in text
    assert 'command: [runtimeConfig.i3pmWatchBin, "dashboard", "watch"]' in services_text
    assert "readonly property string i3pmWatchBin" in quickshell_default_nix_text
    assert "quickshell-i3pm-watch" in quickshell_default_nix_text
    assert "[d]eno .*main[.]ts dashboard watch" in quickshell_default_nix_text
    assert "kill -KILL" in quickshell_default_nix_text
    assert "kill -0" in quickshell_default_nix_text
    assert '"--interval", String(runtimeConfig.dashboardHeartbeatMs)' not in services_text
    assert "dashboardHeartbeatMs" not in quickshell_default_nix_text
    assert "function applyDashboardSnapshot(payload)" in worktree_service_text
    assert "function applyDashboardEvent(event)" in worktree_service_text
    assert 'dashboardWatchProcess.command = [appConfig.i3pmBin, "dashboard", "watch"];' in worktree_service_text
    assert "watch emits one initial snapshot, then typed dashboard delta events." in dashboard_command_text
    assert "const encoded = JSON.stringify(event);" in dashboard_command_text
    assert '"interval"' not in dashboard_command_text
    assert "--interval" not in dashboard_command_text
    assert 'message.method !== "state_changed"' not in daemon_client_text
    assert 'event["method"] == "state_changed"' not in (REPO_ROOT / "home-modules" / "tools" / "i3_project_manager" / "core" / "daemon_client.py").read_text()
    assert '"state_changed"' not in dashboard_command_text
    assert "if (params.event_type === undefined)" in daemon_client_text
    assert "const eventType = String(params.event_type);" in daemon_client_text
    assert 'if (!eventType.includes(".") || message.method !== eventType)' in daemon_client_text


def test_worktree_app_uses_daemon_focus_state_and_no_heartbeat_config():
    """Standalone worktree app should render focus from daemon focus_state and rely on dashboard events."""
    shell_text = WORKTREE_APP_SHELL_QML.read_text()
    service_text = WORKTREE_APP_SERVICE_QML.read_text()
    default_nix_text = WORKTREE_APP_DEFAULT_NIX.read_text()

    assert "function dashboardFocusState()" in shell_text
    assert "function windowIsFocused(windowData)" in shell_text
    window_focus_body = shell_text.split("function windowIsFocused(windowData)", 1)[1].split("function shortProject", 1)[0]
    assert "dashboardFocusState().focused_window_id" not in window_focus_body
    assert "function pendingFocusIntent()" in shell_text
    assert "function pendingFocusIntentMatches(kind, targetKey)" in shell_text
    assert 'pendingFocusIntentMatches("window_focus", String(windowId))' in window_focus_body
    assert "windows.find(windowData => windowIsFocused(windowData))" in shell_text
    assert "windowData.focused" not in shell_text
    assert 'dashboardWatchProcess.command = [appConfig.i3pmBin, "dashboard", "watch"];' in service_text
    assert "dashboardHeartbeatMs" not in default_nix_text


def test_panel_toggle_uses_quickshell_named_runtime_command():
    runtime_shell_nix = QUICKSHELL_DEFAULT_NIX.read_text()
    sway_keybindings_nix = SWAY_KEYBINDINGS_NIX.read_text()

    assert 'writeShellScriptBin "toggle-runtime-panel"' in runtime_shell_nix
    assert "exec toggle-runtime-panel" in sway_keybindings_nix
    assert 'writeShellScriptBin "toggle-monitoring-panel"' not in runtime_shell_nix
    assert "exec toggle-monitoring-panel" not in sway_keybindings_nix


def test_legacy_monitoring_docs_do_not_claim_ai_or_ui_authority():
    monitoring_data_text = I3PM_MONITORING_DATA_PY.read_text()
    cli_readme_text = I3PM_CLI_README.read_text()
    ai_session_doc_text = AI_SESSION_SYSTEM_DOC.read_text()

    assert "Legacy monitoring data compatibility backend" in monitoring_data_text
    assert "It is no longer the active QuickShell runtime state authority." in monitoring_data_text
    assert "outputs JSON for Eww consumption" not in monitoring_data_text
    assert '"ai_sessions"' not in monitoring_data_text
    assert "eww-monitoring-panel" not in cli_readme_text
    assert "OTEL remains telemetry-only" in ai_session_doc_text
    assert "Eww monitoring panel state, defpolls, or `monitoring_data.py` as UI authority" in ai_session_doc_text


def test_i3pm_herdr_proxy_exposes_snapshot_focus_and_event_stream():
    text = I3PM_HERDR_PROXY_TS.read_text()
    main_cli_text = I3PM_MAIN_TS.read_text()
    assert "i3pm herdr-proxy <snapshot|events|focus> [--json|--jsonl]" in text
    assert "events [--jsonl]" in text
    assert 'subcommand === "snapshot"' in text
    assert 'subcommand === "focus"' in text
    assert 'subcommand === "events"' in text
    assert '"herdr.proxy.snapshot"' in text
    assert '"herdr.proxy.pane.focus"' in text
    assert "client.subscribeToStateChanges()" in text
    assert 'schema_version: "i3pm.herdr_proxy.event.v1"' in text
    assert 'eventType === "herdr.changed"' in text
    assert 'changedKeys.includes("herdr")' in text
    assert "i3pm herdr-proxy events --jsonl" in main_cli_text


def test_side_panel_sessions_close_by_explicit_herdr_target():
    """Session rows should call Herdr close targets when provided."""
    text = SHELL_QML.read_text()
    assert "function sessionCloseTarget(session)" in text
    assert "return normalizedFocusTarget(session.close_target);" in text
    assert "function sessionHasClosableSurface(session)" in text
    assert "if (sessionCloseTarget(session))" in text
    assert "sessionHasTmuxCloseTarget" not in text
    assert "sessionCloseProcess" not in text
    assert '"session", "close"' not in text
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


def test_legacy_session_action_rpc_surface_is_retired():
    """AI session actions should be Herdr targets, not the old tmux session RPCs."""
    daemon_text = IPC_SERVER_PY.read_text()
    session_cli_text = I3PM_SESSION_TS.read_text()
    main_cli_text = I3PM_MAIN_TS.read_text()

    assert not (DAEMON_SERVICES_DIR / "session_action_service.py").exists()
    for retired in [
        "SessionActionService",
        "session_action_service",
        '"session.focus"',
        '"session.close"',
        '"session.spawn_remote_attach"',
        "def _session_focus",
        "def _session_close",
        "def _session_spawn_remote_attach",
    ]:
        assert retired not in daemon_text

    assert 'subcommand === "focus"' not in session_cli_text
    assert 'subcommand === "close"' not in session_cli_text
    assert "session.focus" not in session_cli_text
    assert "session.close" not in session_cli_text
    assert "AI session inspection and focus commands" not in main_cli_text


def test_remote_herdr_aggregation_uses_proxy_only():
    """ThinkPad remote Herdr state should not fall back to direct SSH fanout commands."""
    herdr_service_text = (REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon" / "services" / "herdr_service.py").read_text()

    assert "def run_proxy_json" in herdr_service_text
    assert "def run_ssh_json" not in herdr_service_text
    assert '["ssh", ssh_target, "herdr", *args]' not in herdr_service_text
    assert '["ssh", str(target.get("ssh_target") or "").strip(), "herdr"]' not in herdr_service_text
    assert 'self.ssh_command_prefix(ssh_target) + ["herdr", *args]' not in herdr_service_text
    assert '["i3pm", "herdr-proxy", *args]' in herdr_service_text
    assert '["i3pm", "herdr-proxy", "events", "--jsonl"]' in herdr_service_text


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
    assert "const customStatus = stringOrEmpty(session && session.custom_status);" in text
    assert "bits.push(herdrStatusLabel(session));" in text
    assert "bits.push(customStatus);" in text
    assert "const foregroundCwd = stringOrEmpty(session && session.foreground_cwd);" in text
    assert "const cwd = stringOrEmpty(session && session.cwd);" in text
    assert "bits.push(parts[parts.length - 1]);" in text
    assert "return bits.join(\" • \");" in text


def test_herdr_visual_metadata_controls_labels_without_changing_icon_family():
    """Herdr display labels and custom state labels should drive text, not icon identity."""
    text = SHELL_QML.read_text()
    assert "function herdrStatusLabel(session)" in text
    assert 'const override = stringOrEmpty(labels[state]);' in text
    assert 'return titleCaseWord(state);' in text
    assert 'const displayAgent = stringOrEmpty(session && session.display_agent);' in text
    assert 'return displayAgent;' in text
    assert 'if (tool === "opencode") {' in text
    assert 'return "OpenCode";' in text
    assert 'if (tool === "github-copilot" || tool === "copilot") {' in text
    assert 'return "GitHub Copilot";' in text
    assert 'return "file://" + shellConfig.aiFallbackIcon;' in text


def test_launcher_preview_for_herdr_sessions_is_focus_only():
    """Session launcher inspection should be focus-only instead of a tmux preview process."""
    text = SHELL_QML.read_text()
    launcher_text = LAUNCHER_WINDOW_QML.read_text()
    runtime_services_text = RUNTIME_SERVICES_QML.read_text()
    session_command_text = I3PM_SESSION_TS.read_text()
    main_command_text = I3PM_MAIN_TS.read_text()
    daemon_text = (REPO_ROOT / "home-modules/desktop/i3-project-event-daemon/ipc_server.py").read_text()
    assert "const herdrSession = stringOrEmpty(entry.source) === \"herdr\" || stringOrEmpty(entry.pane_id);" in text
    assert 'preview_mode: "focus_only"' in text
    assert 'preview_reason: herdrSession ? "herdr_focus_only" : "herdr_focus_required"' in text
    assert '"Focus this Herdr pane to inspect live output."' in text
    assert "function sessionPreviewStatusText()" in text
    assert "root.sessionPreviewStatusText()" in launcher_text
    assert "sessionPreviewProcess" not in text
    assert "sessionPreviewProcess" not in runtime_services_text
    assert "parseSessionPreview" not in text
    assert '"session", "preview", sessionKey, "--jsonl", "--lines", "100"' not in text
    assert '"session", "preview", "", "--jsonl", "--lines", "100"' not in runtime_services_text
    assert '"session", "preview", sessionKey, "--follow"' not in text
    assert '"session", "preview", "", "--follow"' not in runtime_services_text
    assert "--follow" not in session_command_text
    assert "session preview <session_key>" not in session_command_text
    assert "session preview <session_key>" not in main_command_text
    assert "session preview <session_key> --follow" not in main_command_text
    assert '"session.preview"' not in daemon_text
    assert "_session_preview" not in daemon_text
    assert 'message: "Loading live pane preview..."' not in text
    assert "sessionPreviewFollowChipVisible" not in text
    assert "sessionPreviewAutoFollow" not in text
    assert "sessionPreviewFollowTimer" not in text
    assert "sessionPreviewFollowChipVisible" not in launcher_text
    assert '"legacy-tmux-preview"' not in session_command_text
    assert "allow_legacy_tmux_preview" not in session_command_text
    assert "legacy_tmux_preview_disabled" not in session_command_text
    assert '"local_stream"' not in session_command_text
    assert '"ssh_stream"' not in session_command_text


def test_tmux_does_not_expose_retired_ai_session_overview_popup():
    """Tmux should not expose the retired AI-session pane mirror UI."""
    text = TMUX_NIX.read_text()
    assert "ai-tmux-view-action" not in text
    assert "Active AI sessions overview popup" not in text


def test_legacy_monitoring_does_not_fan_out_remote_tmux_sessions():
    """Legacy project JSON should not synthesize AI/session windows from remote tmux."""
    text = I3PM_MONITORING_DATA_PY.read_text()
    retired_terms = [
        "REMOTE_SESH_CACHE",
        "_fetch_remote_tmux_sessions",
        "_build_remote_session_window",
        "_augment_projects_with_remote_sessions",
        "remote-sesh",
        "sesh list",
        "tmux/sesh",
    ]
    for term in retired_terms:
        assert term not in text


def test_herdr_space_groups_collapse_state_defaults_expanded():
    text = SHELL_QML.read_text()
    assert "property var collapsedHerdrSpaceGroups: ({})" in text
    assert "function herdrSpaceGroupCollapsed(groupKey)" in text
    assert "collapsedHerdrSpaceGroups[key] === true" in text
    assert "function toggleHerdrSpaceGroup(groupKey)" in text
    assert "delete next[key];" in text


def test_herdr_space_rows_use_visible_group_model_and_lowercase_copy():
    panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    assert 'text: "spaces"' in panel_text
    assert 'text: "agents"' in panel_text
    assert "text: String(root.visibleHerdrSpaces().length)" in panel_text
    assert "values: root.visibleHerdrSpaces()" in panel_text


def test_herdr_parent_rows_render_chevrons_and_children_indent():
    text = SHELL_QML.read_text()
    panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    assert "function herdrSpaceChevron(space)" in text
    assert "return herdrSpaceGroupCollapsed(herdrSpaceGroupKey(space)) ? \"▸\" : \"▾\";" in text
    assert "function herdrSpaceIndent(space)" in text
    assert "return boolOrFalse(space && space.is_linked_worktree) && stringOrEmpty(space && space.group_key).length > 0 ? 18 : 0;" in text
    assert "text: root.herdrSpaceChevron(space)" in panel_text
    assert "root.toggleHerdrSpaceGroup(herdrSpaceRow.groupKey);" in panel_text
    assert "anchors.leftMargin: 16 + root.herdrSpaceIndent(space)" in panel_text


def test_remote_host_token_uses_tailscale_blue_not_orange():
    text = SHELL_QML.read_text()
    assert "function hostToken(mode, hostName, connectionKey)" in text
    assert "icon: icon," in text
    assert "foreground: colors.blue," in text
    assert "background: isRemote ? colors.blueBg : colors.blueWash," in text
    assert "border: colors.blueMuted," in text
    assert "foreground: isRemote ? colors.orange : colors.blue" not in text
    assert "background: isRemote ? colors.orangeBg : colors.blueWash" not in text


def test_herdr_space_focus_uses_daemon_focus_state_for_collapsed_children():
    text = SHELL_QML.read_text()
    panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    assert "function visibleHerdrSpaces()" in text
    assert "function herdrSpaceIsFocused(space)" in text
    assert "const focus = dashboardFocusState();" in text
    assert "focus.current_herdr_pane_id" in text
    assert "focus.current_herdr_host" in text
    focus_body = text.split("function herdrSpaceIsFocused(space)", 1)[1].split("function visibleHerdrSpaces", 1)[0]
    assert "focus.herdr_pane_id" not in focus_body
    assert "focus.pane_id" not in focus_body
    assert "focus.herdr_host" not in focus_body
    assert "focus.host_name" not in focus_body
    assert "!root.boolOrFalse(space && space.is_linked_worktree) || !herdrSpaceGroupCollapsed(groupKey) || herdrSpaceIsFocused(space)" in text
    assert "readonly property bool spaceFocused: root.herdrSpaceIsFocused(space)" in panel_text
    assert "space && space.focused" not in text
    assert "space.focused" not in panel_text


def test_herdr_group_aggregate_status_drives_collapsed_parent_dot():
    text = SHELL_QML.read_text()
    assert "function herdrSpaceStatusPriority(status)" in text
    assert "if (state === \"blocked\")" in text
    assert "return 5;" in text
    assert "function herdrAggregateStatusForGroup(groupKey)" in text
    assert "function herdrSpaceEffectiveStatus(space)" in text
    assert "herdrSpaceGroupCollapsed(herdrSpaceGroupKey(space))" in text
    assert "const state = herdrSpaceEffectiveStatus(space);" in text


def test_herdr_space_rows_do_not_render_text_status_badges():
    text = SHELL_QML.read_text()
    panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    assert "text: root.herdrSpaceStatusLabel(space)" not in panel_text
    assert "root.herdrSpaceStatusBackground(space)" not in panel_text
    assert "function herdrSpaceStatusLabel(space)" not in text
    assert "function herdrSpaceStatusBackground(space)" not in text
    assert "text: root.herdrSpaceStatusDot(space)" in panel_text
    assert "function herdrSpaceStatusDot(space)" in text
    assert "readonly property var token: root.herdrSpaceHostToken(space)" not in panel_text


def test_herdr_child_space_titles_use_custom_label_before_branch_label():
    text = SHELL_QML.read_text()
    assert "function herdrSpaceTitle(space)" in text
    assert "if (boolOrFalse(space && space.is_linked_worktree))" in text
    assert "const branchLabel = herdrSpaceBranchLabel(space);" in text
    assert "label !== stringOrEmpty(space && space.repo_name)" in text
    assert "return branchLabel;" in text


def test_herdr_space_meta_label_uses_branch_git_notation():
    text = SHELL_QML.read_text()
    panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    assert "function herdrSpaceBranchLabel(space)" in text
    assert "branchLabel.indexOf(\"worktree/\") === 0" in text
    assert "function herdrSpaceMetaLabel(space)" in text
    assert "const branch = herdrSpaceBranchLabel(space);" in text
    assert "return branch;" in text
    assert "displayHostName(stringOrEmpty(space && (space.host_label || space.host_key)))" not in text
    assert "space.agent_count" not in text
    assert "space.pane_count" not in text
    assert "space.tab_count" not in text
    assert "visible: text.length > 0" in panel_text


def test_herdr_session_space_lookup_uses_workspace_and_host_key():
    text = SHELL_QML.read_text()
    assert "function herdrSessionSpace(session)" in text
    assert "const expectedKey = host + \"::\" + workspaceId;" in text
    assert "const spaceWorkspaceId = stringOrEmpty(space && space.workspace_id);" in text
    assert "const spaceHost = stringOrEmpty(space && (space.host_key || space.host_label)).toLowerCase();" in text
    assert "if ((spaceHost + \"::\" + spaceWorkspaceId) !== expectedKey)" in text


def test_herdr_config_enables_system_notifications_without_sound():
    text = HERDR_NIX.read_text()
    assert '[ui.toast]' in text
    assert 'delivery = "system"' in text
    assert 'delay_seconds = 1' in text
    assert 'delivery = "off"' not in text
    assert '[ui.sound]' in text
    assert 'enabled = false' in text
    assert 'enabled = true' not in text
    assert '[experimental]' in text
    assert 'pane_history = true' in text


def test_optional_herdr_integrations_are_guarded_by_existing_app_config_dirs():
    text = HERDR_NIX.read_text()
    assert 'home.activation.ensureOptionalHerdrIntegrations' in text
    assert 'if [ -d "$HOME/.copilot" ]; then' in text
    assert 'herdr integration install copilot' in text
    assert 'if [ -d "$HOME/.config/opencode" ]; then' in text
    assert 'herdr integration install opencode' in text
    assert 'mkdir -p "$HOME/.copilot"' not in text
    assert 'mkdir -p "$HOME/.config/opencode"' not in text


def test_antigravity_short_tool_id_uses_gemini_visual_family():
    """The agy short id should render with the same icon and tint as Gemini/Antigravity."""
    text = SHELL_QML.read_text()
    config_text = QUICKSHELL_DEFAULT_NIX.read_text()
    agy_family = 'tool === "gemini" || tool === "gemini-cli" || tool === "antigravity" || tool === "antigravity-cli" || tool === "agy"'
    assert text.count(agy_family) >= 4
    assert agy_family + ") {\n            return \"file://\" + shellConfig.geminiIcon;" in text
    assert 'readonly property string geminiIcon: "${../../../assets/icons/gemini.png}"' in config_text


def test_legacy_agent_action_toast_path_is_removed():
    """QuickShell should not keep a special toast lane for the retired i3pm-agent notifier."""
    shell_text = SHELL_QML.read_text()
    nix_text = QUICKSHELL_DEFAULT_NIX.read_text()
    toast_text = NOTIFICATION_TOAST_QML.read_text()
    monitoring_data_text = I3PM_MONITORING_DATA_PY.read_text()

    assert "notificationAgentActionToastMaxPerOutput" not in nix_text
    assert "agentActionToastMaxPerOutput" not in nix_text
    assert "function notificationIsAgentAction(item)" not in shell_text
    assert "i3pm-agent" not in shell_text
    assert "agentAction" not in toast_text
    assert "emit_ai_state_transition_notifications" not in monitoring_data_text
    assert "AI_SESSION_NOTIFY_FILE" not in monitoring_data_text


def test_session_sort_orders_by_host_bucket_before_numeric_pane_slot():
    """Stable ordering should bucket by host before ordering by pane number."""
    text = SHELL_QML.read_text()
    assert "function stableSessionCompare(left, right)" in text
    host_index = text.index("result = compareAscending(sessionHostGroupKey(left), sessionHostGroupKey(right));")
    pane_index = text.index("result = compareAscending(sessionPaneSlot(left), sessionPaneSlot(right));")
    window_index = text.index("result = compareAscending(sessionWindowSlot(left), sessionWindowSlot(right));")
    assert host_index < pane_index < window_index
