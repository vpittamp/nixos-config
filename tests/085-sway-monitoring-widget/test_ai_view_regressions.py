"""Regression tests for the QuickShell AI/session view wiring."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "shell.qml"
SESSION_ROW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "SessionRow.qml"
LAUNCHER_WINDOW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "windows" / "LauncherWindow.qml"
RUNTIME_PANEL_WINDOW_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "windows" / "RuntimePanelWindow.qml"
QUICKSHELL_DEFAULT_NIX = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "default.nix"
NOTIFICATION_TOAST_QML = REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "NotificationToast.qml"
HERDR_NIX = REPO_ROOT / "home-modules" / "terminal" / "herdr.nix"
I3PM_WINDOW_TS = REPO_ROOT / "home-modules" / "tools" / "i3pm" / "src" / "commands" / "window.ts"


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


def test_current_session_highlight_uses_single_dashboard_current_key():
    """Current row highlighting should not independently promote stale raw Herdr focus."""
    text = SHELL_QML.read_text()
    assert "function sessionIsCurrent(session)" in text
    current_index = text.index("if (current) {\n            return sessionMatchesKey(session, current);\n        }")
    focused_index = text.index("return boolOrFalse(session && session.focused) && boolOrFalse(session && session.is_current_host);")
    assert current_index < focused_index


def test_session_rows_use_optimistic_focus_for_immediate_highlight():
    """Clicking a Herdr row should update row visuals before the next dashboard snapshot."""
    text = SHELL_QML.read_text()
    panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    launcher_text = LAUNCHER_WINDOW_QML.read_text()
    row_text = SESSION_ROW_QML.read_text()

    assert "property bool currentOverride: false" in row_text
    assert "readonly property bool isCurrent: currentOverride || rootObject.sessionIsCurrent(session)" in row_text
    assert "function sessionMatchesKey(session, key)" in text
    assert "return sessionMatchesKey(session, optimistic);" in text
    assert "selected: root.sessionMatchesKey(modelData, root.selectedSessionKey)" in panel_text
    assert "currentOverride: root.sessionMatchesKey(modelData, root.optimisticCurrentSessionKey)" in panel_text
    assert "currentOverride: root.sessionMatchesKey(entry, root.optimisticCurrentSessionKey)" in launcher_text
    assert "if (current && !optimistic)" in text


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
    assert "stringOrEmpty(sessionOrKey.source) === \"herdr\" || stringOrEmpty(sessionOrKey.pane_id)" in text
    assert "return explicitTarget;" in text
    assert "const target = sessionFocusTarget(sessionData || resolvedSessionKey);" in text
    assert "runFocusTarget(target);" in text
    assert "function sendDaemonAction(method, params)" in services_text
    assert "Socket {" in services_text
    assert "daemonActionSocket.write(JSON.stringify(request) + \"\\n\");" in services_text
    assert "runDaemonAction(normalizedTarget.method, normalizedTarget.params);" in text


def test_local_window_and_workspace_clicks_use_fast_focus_with_optimistic_state():
    """Click-driven local window/workspace focus should avoid fork-per-click daemon calls."""
    text = SHELL_QML.read_text()
    runtime_panel_text = RUNTIME_PANEL_WINDOW_QML.read_text()
    bottom_bar_text = (REPO_ROOT / "home-modules" / "desktop" / "quickshell-runtime-shell" / "windows" / "BottomBarWindow.qml").read_text()
    window_command_text = I3PM_WINDOW_TS.read_text()

    assert "property int optimisticFocusedWindowId: 0" in text
    assert "property string optimisticFocusedWorkspaceName: \"\"" in text
    assert "method: \"window.focus_fast\"" in text
    assert "runDaemonSocketCall(\"workspace.focus_fast\", {workspace: workspaceName})" in text
    assert "if (optimisticFocusedWindowId > 0) {\n            return windowId === optimisticFocusedWindowId;\n        }" in text
    assert "if (optimistic) {\n            return workspaceName === optimistic;\n        }" in text
    assert "optimisticFocusedWindowId = windowId;" in text
    assert "optimisticFocusedWorkspaceName = workspaceName;" in text
    assert "root.windowIsFocused(windowData)" in runtime_panel_text
    assert "root.workspaceIsFocused(workspace)" in bottom_bar_text
    assert "client.request(\"window.focus_fast\", params)" in window_command_text
    assert "fallback_method === \"window.focus\"" in window_command_text


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
    """Herdr sessions should not start the old live tmux/session preview process."""
    text = SHELL_QML.read_text()
    launcher_text = LAUNCHER_WINDOW_QML.read_text()
    assert "if (stringOrEmpty(entry.source) === \"herdr\" || stringOrEmpty(entry.pane_id))" in text
    assert "message: \"Focus this Herdr pane to inspect live output.\"" in text
    assert "return;" in text
    assert "function sessionPreviewStatusText()" in text
    assert "root.sessionPreviewStatusText()" in launcher_text


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


def test_herdr_collapsed_groups_hide_inactive_children_but_keep_focused_child():
    text = SHELL_QML.read_text()
    assert "function visibleHerdrSpaces()" in text
    assert "!root.boolOrFalse(space && space.is_linked_worktree) || !herdrSpaceGroupCollapsed(groupKey) || root.boolOrFalse(space && space.focused)" in text


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
