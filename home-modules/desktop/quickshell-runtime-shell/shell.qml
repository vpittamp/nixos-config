import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.I3
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets
import "controllers" as Controllers
import "windows" as Windows

ShellRoot {
    id: root
    readonly property QtObject shellRootRef: root

    ShellConfig {
        id: shellConfig
    }

    AssistantService {
        id: assistantService
        shellConfigName: shellConfig.configName
        contextLabel: root.worktreePickerSummaryTitle()
        contextDetails: root.activeContextSummaryLabel()
    }

    readonly property var launcherField: launcherWindow ? launcherWindow.launcherFieldRef : null
    readonly property var launcherList: launcherWindow ? launcherWindow.launcherListRef : null
    readonly property var settingsCommandQueryField: settingsWindow ? settingsWindow.settingsCommandQueryFieldRef : null
    readonly property var settingsCommandsList: settingsWindow ? settingsWindow.settingsCommandsListRef : null
    readonly property var clock: runtimeServices ? runtimeServices.clockRef : null
    readonly property var launcherFocusTimer: runtimeServices ? runtimeServices.launcherFocusTimerRef : null
    readonly property var launcherQueryDebounce: runtimeServices ? runtimeServices.launcherQueryDebounceRef : null
    readonly property var launcherSessionSwitcherOpenTimer: runtimeServices ? runtimeServices.launcherSessionSwitcherOpenTimerRef : null
    readonly property var sessionPreviewDebounce: runtimeServices ? runtimeServices.sessionPreviewDebounceRef : null
    readonly property var sessionPreviewFollowTimer: runtimeServices ? runtimeServices.sessionPreviewFollowTimerRef : null
    readonly property var settingsFocusTimer: runtimeServices ? runtimeServices.settingsFocusTimerRef : null
    readonly property var settingsCommandQueryDebounce: runtimeServices ? runtimeServices.settingsCommandQueryDebounceRef : null
    readonly property var snippetEditorProcess: runtimeServices ? runtimeServices.snippetEditorProcessRef : null
    readonly property var settingsCommandQueryProcess: runtimeServices ? runtimeServices.settingsCommandQueryProcessRef : null
    readonly property var launcherQueryProcess: runtimeServices ? runtimeServices.launcherQueryProcessRef : null
    readonly property var sessionPreviewProcess: runtimeServices ? runtimeServices.sessionPreviewProcessRef : null
    readonly property var sessionCloseProcess: runtimeServices ? runtimeServices.sessionCloseProcessRef : null
    readonly property var dashboardWatcher: runtimeServices ? runtimeServices.dashboardWatcherRef : null

    property var dashboard: ({
            status: "loading",
            active_context: {},
            active_terminal: {},
            active_ai_sessions: [],
            active_ai_sessions_mru: [],
            current_ai_session_key: "",
            display_layout: {},
            outputs: [],
            projects: [],
            worktrees: [],
            scratchpad: {},
            state_health: {},
            total_windows: 0
        })
    property var notificationState: ({
            count: 0,
            dnd: false,
            visible: false,
            inhibited: false,
            has_unread: false,
            display_count: "0",
            error: false
        })
    property var notificationFeed: []
    property var notificationRuntimeMap: ({})
    property var notificationLifecycleConnected: ({})
    property bool notificationCenterVisible: false
    property bool notificationDetailVisible: false
    property var notificationDetailItem: null
    property bool notificationDnd: false
    property var networkState: ({
            connected: false,
            kind: "offline",
            label: "Offline",
            signal: null
        })
    property var daemonHealthState: ({
            status: "unknown",
            errors: 0,
            events: 0,
            memory_mb: 0,
            last_error: ""
        })

    property var systemStatsState: ({
            memory_percent: 0,
            memory_used_gb: 0,
            memory_total_gb: 0,
            swap_used_gb: 0,
            swap_total_gb: 0,
            load1: 0,
            load5: 0,
            load15: 0,
            temperature_c: null,
            system_generation: 0
        })
    property bool panelVisible: true
    property string panelSection: "runtime"
    property string runtimePanelExpandedSection: "sessions"
    property bool dockedMode: true
    property bool powerMenuVisible: false
    property bool audioPopupVisible: false
    property bool bluetoothPopupVisible: false
    property bool worktreePickerVisible: false
    property bool launcherVisible: false
    property bool launcherLoading: false
    property bool launcherNormalizingInput: false
    property bool settingsVisible: false
    property string settingsSection: "commands"
    property string settingsCommandQuery: ""
    property bool settingsCommandNormalizingInput: false
    property bool settingsCommandLoading: false
    property string settingsCommandError: ""
    property int settingsCommandSelectedIndex: 0
    property var settingsCommandEntries: []
    property string launcherMode: "apps"
    property bool launcherSessionSwitcherActive: false
    property int launcherSessionSwitcherPendingDelta: 0
    property string launcherQuery: ""
    property string launcherError: ""
    property int launcherSelectedIndex: 0
    property var launcherEntries: []
    property var launcherSessionEntryOrder: []
    property bool launcherPointerSelectionEnabled: true
    property bool snippetEditorBusy: false
    property string snippetEditorError: ""
    property string snippetEditorMessage: ""
    property int snippetEditorIndex: -1
    property int snippetEditorSelectionHint: -1
    property bool snippetEditorNewDraft: false
    property bool snippetEditorDirty: false
    property bool snippetEditorSyncing: false
    property string snippetEditorLoadedIdentity: ""
    property string snippetEditorName: ""
    property string snippetEditorCommand: ""
    property string snippetEditorDescription: ""
    property var onePasswordEntriesCache: []
    property var expandedSessionGroups: ({})
    property string lastFocusedSessionKey: ""
    property string selectedSessionKey: ""
    property var sessionClosePendingMap: ({})
    property string sessionCloseProcessTargetKey: ""
    property string sessionCloseProcessStdout: ""
    property string sessionCloseProcessStderr: ""
    property string sessionPreviewTargetKey: ""
    property bool sessionPreviewStopExpected: false
    property bool sessionPreviewAutoFollow: true
    property bool sessionPreviewHasUnseenOutput: false
    property bool sessionPreviewProgrammaticScroll: false
    property var sessionPreview: ({
            status: "idle",
            kind: "status",
            session_key: "",
            preview_mode: "",
            preview_reason: "",
            is_live: false,
            is_remote: false,
            tool: "",
            project_name: "",
            host_name: "",
            connection_key: "",
            execution_mode: "",
            focus_mode: "",
            availability_state: "",
            focusability_reason: "",
            window_id: 0,
            bridge_window_id: 0,
            bridge_state: "",
            pane_label: "",
            pane_title: "",
            tmux_session: "",
            tmux_window: "",
            tmux_pane: "",
            surface_key: "",
            session_phase: "",
            session_phase_label: "",
            turn_owner: "",
            turn_owner_label: "",
            activity_substate: "",
            activity_substate_label: "",
            status_reason: "",
            content: "",
            message: "",
            updated_at: ""
        })
    readonly property var primaryScreen: resolvePrimaryScreen()
    readonly property string primaryOutputName: screenOutputName(primaryScreen)


    readonly property var colors: ({
            bg: "#0d1117",
            panel: "#111827",
            panelAlt: "#131d2a",
            card: "#161f2c",
            cardAlt: "#0f1722",
            border: "#273244",
            borderStrong: "#334155",
            text: "#e7edf5",
            muted: "#92a1b5",
            subtle: "#64748b",
            lineSoft: "#202b3a",
            textDim: "#b4c0d1",
            accent: "#d1fae5",
            accentBg: "#123329",
            blue: "#93c5fd",
            blueBg: "#16243a",
            blueMuted: "#5d7ba2",
            blueWash: "#152231",
            amber: "#f7d38c",
            amberBg: "#3a2912",
            orange: "#fb923c",
            orangeBg: "#3a2414",
            red: "#fda4af",
            redBg: "#3b1820",
            teal: "#67e8f9",
            tealBg: "#102a33",
            violet: "#c4b5fd",
            violetBg: "#241b43"
        })
    readonly property int fastColorMs: 90

    function arrayOrEmpty(value) {
        if (!value) {
            return [];
        }
        if (Array.isArray(value)) {
            return value;
        }
        try {
            return Array.from(value);
        } catch (_error) {
            return [];
        }
    }

    function stringOrEmpty(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function shortProject(name) {
        const value = stringOrEmpty(name);
        if (!value || value === "global") {
            return "Global";
        }

        const accountSplit = value.split("/");
        const repo = accountSplit[accountSplit.length - 1] || value;
        return repo;
    }

    function modeLabel(mode) {
        const value = stringOrEmpty(mode).toLowerCase();
        if (value === "ssh") {
            return "SSH";
        }
        if (value === "local") {
            return "Local";
        }
        return value ? value : "Global";
    }

    function currentContextTitle() {
        const context = dashboard.active_context || {};
        const qualified = stringOrEmpty(context.qualified_name || context.project_name);
        return qualified ? shortProject(qualified) : "Global";
    }

    function activeContextProjectName() {
        const context = dashboard.active_context || {};
        return stringOrEmpty(context.qualified_name || context.project_name);
    }

    function activeContextExecutionMode() {
        const context = dashboard.active_context || {};
        return stringOrEmpty(context.execution_mode || "local") || "local";
    }

    function isGlobalContext() {
        const project = activeContextProjectName();
        return !project || project === "global";
    }

    function activeContextHostName() {
        const context = dashboard.active_context || {};
        const remote = context.remote || {};
        const executionMode = stringOrEmpty(context.execution_mode || "local");

        if (executionMode === "ssh") {
            return stringOrEmpty(remote.host_alias || remote.host || context.host_alias || context.connection_key);
        }

        return stringOrEmpty(context.host_alias || shellConfig.hostName);
    }

    function activeContextSummaryLabel() {
        if (isGlobalContext()) {
            return "Shared  " + currentLayoutLabel();
        }

        const hostName = activeContextHostName();
        const parts = [modeLabel(activeContextExecutionMode())];
        if (hostName) {
            parts.push(hostName);
        }
        parts.push(currentLayoutLabel());
        return parts.join("  ");
    }

    function activeTerminal() {
        const terminal = dashboard.active_terminal || {};
        return terminal && typeof terminal === "object" ? terminal : {};
    }

    function activeTerminalAvailable() {
        return boolOrFalse(activeTerminal().available);
    }

    function activeTerminalChipLabel() {
        if (isGlobalContext()) {
            return "";
        }
        return activeTerminalAvailable() ? "Focus shell" : "Open shell";
    }

    function activeTerminalMetaLabel() {
        if (isGlobalContext()) {
            return "";
        }

        const terminal = activeTerminal();
        const sessionName = stringOrEmpty(terminal.tmux_session_name);
        if (sessionName) {
            return activeTerminalAvailable() ? "Live tmux session" : "Reusable tmux session";
        }
        return activeTerminalAvailable() ? "Shell available" : "Shell not started";
    }

    function openActiveTerminal() {
        if (isGlobalContext()) {
            return;
        }
        runDetached([shellConfig.i3pmBin, "launch", "open", "terminal"]);
    }

    function activeSessions() {
        return uniqueSessions(arrayOrEmpty(dashboard.active_ai_sessions));
    }

    function sessionMru() {
        const mru = uniqueSessions(arrayOrEmpty(dashboard.active_ai_sessions_mru));
        return mru.length ? mru : activeSessions();
    }

    function panelSessions() {
        return stableSortedSessions(activeSessions().filter(session => sessionIsPanelDisplayEligible(session)));
    }

    function sessionIdentityKey(session) {
        const sessionKey = stringOrEmpty(session && session.session_key);
        if (sessionKey) {
            return sessionKey;
        }

        const surfaceKey = stringOrEmpty(session && session.surface_key);
        if (surfaceKey) {
            return surfaceKey;
        }

        return [stringOrEmpty(session && session.tool), stringOrEmpty(session && session.connection_key), stringOrEmpty(session && session.context_key), String(Number(session && session.window_id || 0)), String(Number(session && session.pid || 0)), String(Number(session && session.pane_pid || 0)), stringOrEmpty(session && session.pane_label)].join("::");
    }

    function uniqueSessions(items) {
        const list = arrayOrEmpty(items);
        const unique = [];
        const seen = {};

        for (let i = 0; i < list.length; i += 1) {
            const session = list[i];
            const identityKey = sessionIdentityKey(session);
            if (!identityKey || seen[identityKey]) {
                continue;
            }
            seen[identityKey] = true;
            unique.push(session);
        }

        return unique;
    }

    function firstNumber(value, fallback) {
        const match = stringOrEmpty(value).match(/-?\d+/);
        if (!match || !match.length) {
            return fallback;
        }
        const parsed = Number(match[0]);
        return Number.isFinite(parsed) ? parsed : fallback;
    }

    function compareAscending(left, right) {
        if (left < right) {
            return -1;
        }
        if (left > right) {
            return 1;
        }
        return 0;
    }

    function compareDescending(left, right) {
        if (left > right) {
            return -1;
        }
        if (left < right) {
            return 1;
        }
        return 0;
    }

    function sessionWindowSlot(session) {
        return firstNumber(session && session.tmux_window, 1000000);
    }

    function sessionPaneSlot(session) {
        return firstNumber(session && session.tmux_pane, firstNumber(session && session.pane_label, 1000000));
    }

    function sessionIsCurrentHost(session) {
        return boolOrFalse(session && session.is_current_host);
    }

    function windowIsCurrentTarget(windowData) {
        return boolOrFalse(windowData && windowData.focused);
    }

    function sessionIsDisplayEligible(session) {
        if (!session || typeof session !== "object") {
            return false;
        }

        const terminalAnchor = stringOrEmpty(session.terminal_anchor_id);
        const hasTmuxIdentity = stringOrEmpty(session.tmux_session) && stringOrEmpty(session.tmux_window) && stringOrEmpty(session.tmux_pane);
        if (!terminalAnchor && !hasTmuxIdentity) {
            return false;
        }

        if (boolOrFalse(session.remote_source_stale)) {
            return false;
        }

        const phase = sessionPhase(session);
        if (phase === "working" || phase === "needs_attention" || phase === "done") {
            return true;
        }

        return boolOrFalse(session.process_running);
    }

    function sessionIsPanelDisplayEligible(session) {
        if (!session || typeof session !== "object") {
            return false;
        }

        const terminalAnchor = stringOrEmpty(session.terminal_anchor_id);
        const hasTmuxIdentity = stringOrEmpty(session.tmux_session) && stringOrEmpty(session.tmux_window) && stringOrEmpty(session.tmux_pane);
        if (!terminalAnchor && !hasTmuxIdentity) {
            return false;
        }

        const phase = sessionPhase(session);
        if (phase === "working" || phase === "needs_attention" || phase === "done") {
            return true;
        }

        return boolOrFalse(session.process_running);
    }

    function stableSessionCompare(left, right) {
        let result = compareDescending(sessionIsCurrentHost(left) ? 1 : 0, sessionIsCurrentHost(right) ? 1 : 0);
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionHostGroupKey(left), sessionHostGroupKey(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionPaneSlot(left), sessionPaneSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionWindowSlot(left), sessionWindowSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.tmux_session), stringOrEmpty(right && right.tmux_session));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.pane_label), stringOrEmpty(right && right.pane_label));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.tool), stringOrEmpty(right && right.tool));
        if (result !== 0) {
            return result;
        }

        return compareAscending(sessionIdentityKey(left), sessionIdentityKey(right));
    }

    function stableSortedSessions(items) {
        const sessions = uniqueSessions(items).slice();
        sessions.sort((left, right) => stableSessionCompare(left, right));
        return sessions;
    }

    function groupHasCurrentSession(group) {
        const sessions = arrayOrEmpty(group && group.sessions);
        for (let i = 0; i < sessions.length; i += 1) {
            if (sessionIsCurrent(sessions[i])) {
                return true;
            }
        }
        return false;
    }

    function projectGroupFor(projectName, executionMode) {
        const projects = arrayOrEmpty(dashboard.projects);
        const project = stringOrEmpty(projectName);
        const mode = stringOrEmpty(executionMode || "local") || "local";

        return projects.find(projectGroup => stringOrEmpty(projectGroup.project) === project && stringOrEmpty(projectGroup.execution_mode || "local") === mode) || null;
    }

    function focusPreferredWindowForContext(projectName, executionMode) {
        const projectGroup = projectGroupFor(projectName, executionMode);
        if (!projectGroup) {
            return false;
        }

        const windows = arrayOrEmpty(projectGroup.windows).filter(windowData => !boolOrFalse(windowData.hidden));
        if (!windows.length) {
            return false;
        }

        const focusedWindow = windows.find(windowData => boolOrFalse(windowData.focused));
        focusWindow(focusedWindow || windows[0]);
        return true;
    }

    function compactSessions() {
        return panelSessions().slice(0, 10);
    }

    function primaryOutputCandidates() {
        return arrayOrEmpty(shellConfig.primaryOutputs).map(value => stringOrEmpty(value)).filter(value => value);
    }

    function findScreenByOutputName(outputName) {
        const target = stringOrEmpty(outputName);
        if (!target) {
            return null;
        }

        const screens = arrayOrEmpty(Quickshell.screens);
        for (let i = 0; i < screens.length; i += 1) {
            const screen = screens[i];
            if (screenOutputName(screen) === target) {
                return screen;
            }
        }

        return null;
    }

    function monitorForScreen(screen) {
        if (!screen) {
            return null;
        }
        try {
            return I3.monitorFor(screen);
        } catch (_error) {
            return null;
        }
    }

    function screenOutputName(screen) {
        const monitor = monitorForScreen(screen);
        const monitorName = stringOrEmpty(monitor ? monitor.name : "");
        if (monitorName) {
            return monitorName;
        }
        return stringOrEmpty(screen ? screen.name : "");
    }

    function notificationToastOuterMargin() {
        return 18;
    }

    function notificationToastTopInset() {
        return shellConfig.topBarHeight + notificationToastOuterMargin();
    }

    function notificationToastRightInset(outputName) {
        let inset = notificationToastOuterMargin();
        if (panelVisible && stringOrEmpty(outputName) === primaryOutputName) {
            inset += shellConfig.panelWidth + 12;
        }
        return inset;
    }

    function notificationToastWidthForScreen(screen, outputName) {
        const fallbackWidth = 380;
        const screenWidth = Number(screen && screen.width || 0);

        if (screenWidth <= 0) {
            return fallbackWidth;
        }

        const availableWidth = screenWidth - notificationToastOuterMargin() - notificationToastRightInset(outputName);
        if (availableWidth <= 0) {
            return fallbackWidth;
        }

        return Math.max(1, Math.min(fallbackWidth, availableWidth));
    }

    function livePrimaryOutputName() {
        const displayLayout = dashboard.display_layout || {};
        const outputs = arrayOrEmpty(displayLayout.outputs);

        for (let i = 0; i < outputs.length; i += 1) {
            const output = outputs[i];
            if (!output || !output.primary || !output.active || output.enabled === false) {
                continue;
            }

            const name = stringOrEmpty(output.name);
            if (name) {
                return name;
            }
        }

        return "";
    }

    function resolvePrimaryScreen() {
        const screens = arrayOrEmpty(Quickshell.screens);
        if (!screens.length) {
            return null;
        }

        const candidates = primaryOutputCandidates();
        for (let i = 0; i < candidates.length; i += 1) {
            const preferredScreen = findScreenByOutputName(candidates[i]);
            if (preferredScreen) {
                return preferredScreen;
            }
        }

        const livePrimaryScreen = findScreenByOutputName(livePrimaryOutputName());
        if (livePrimaryScreen) {
            return livePrimaryScreen;
        }

        const focusedMonitor = I3.focusedMonitor;
        const focusedScreen = findScreenByOutputName(stringOrEmpty(focusedMonitor ? focusedMonitor.name : ""));
        if (focusedScreen) {
            return focusedScreen;
        }

        return screens[0];
    }

    function workspacesForScreen(screen) {
        const outputName = screenOutputName(screen);
        const items = [];
        const workspaces = arrayOrEmpty(I3.workspaces);

        for (let i = 0; i < workspaces.length; i += 1) {
            const workspace = workspaces[i];
            const monitor = workspace && workspace.monitor ? workspace.monitor : null;
            const workspaceOutput = stringOrEmpty(monitor ? monitor.name : "");
            if (!outputName || !workspaceOutput || workspaceOutput === outputName) {
                items.push(workspace);
            }
        }

        items.sort((left, right) => Number(left?.num || 0) - Number(right?.num || 0));
        return items;
    }

    function dashboardWorkspacesForOutput(outputName) {
        const outputs = arrayOrEmpty(dashboard.outputs);
        const target = stringOrEmpty(outputName);
        const items = [];

        for (let i = 0; i < outputs.length; i += 1) {
            const output = outputs[i];
            if (stringOrEmpty(output ? output.name : "") !== target) {
                continue;
            }

            const currentWorkspace = stringOrEmpty(output.current_workspace);
            const workspaces = arrayOrEmpty(output.workspaces);
            for (let j = 0; j < workspaces.length; j += 1) {
                const workspace = workspaces[j];
                const name = stringOrEmpty(workspace ? workspace.name : "");
                if (name.indexOf("scratchpad") === 0) {
                    continue;
                }
                items.push({
                    num: Number(workspace?.number || 0),
                    name: name,
                    focused: boolOrFalse(workspace?.focused) || (name !== "" && name === currentWorkspace),
                    active: boolOrFalse(workspace?.visible) || (name !== "" && name === currentWorkspace),
                    urgent: boolOrFalse(workspace?.urgent),
                    output: target
                });
            }
            break;
        }

        items.sort((left, right) => Number(left?.num || 0) - Number(right?.num || 0));
        return items;
    }

    function barWorkspacesForOutput(outputName) {
        const dashboardWorkspaces = dashboardWorkspacesForOutput(outputName);
        if (dashboardWorkspaces.length > 0) {
            return dashboardWorkspaces;
        }
        return workspacesForScreen(findScreenByOutputName(outputName));
    }

    function currentLayoutLabel() {
        const displayLayout = dashboard.display_layout || {};
        const layout = stringOrEmpty(displayLayout.current_layout);
        if (layout) {
            return layout;
        }
        return primaryOutputName || "Display";
    }

    function focusedOutputName() {
        return stringOrEmpty(I3.focusedMonitor ? I3.focusedMonitor.name : "");
    }

    function isPrimaryOutput(outputName) {
        return stringOrEmpty(outputName) !== "" && stringOrEmpty(outputName) === primaryOutputName;
    }

    function isFocusedOutput(outputName) {
        return stringOrEmpty(outputName) !== "" && stringOrEmpty(outputName) === focusedOutputName();
    }

    function notificationsBackendNative() {
        return stringOrEmpty(shellConfig.notificationBackend).toLowerCase() === "native";
    }

    function notificationTargetOutputName() {
        return focusedOutputName() || primaryOutputName || stringOrEmpty(shellConfig.hostName);
    }

    function notificationBodyFormat() {
        return shellConfig.notificationMarkupEnabled ? Text.StyledText : Text.PlainText;
    }

    function notificationActionIdentifier(action) {
        return stringOrEmpty(action && action.identifier);
    }

    function notificationActionText(action) {
        return stringOrEmpty(action && action.text) || "Open";
    }

    function notificationUnread(item) {
        return boolOrFalse(item && item.unread);
    }

    function notificationClosed(item) {
        return boolOrFalse(item && item.closed);
    }

    function notificationIsCritical(item) {
        return stringOrEmpty(item && item.urgency).toLowerCase() === "critical";
    }

    function notificationHasActions(item) {
        return arrayOrEmpty(item && item.actions).length > 0;
    }

    function notificationPrimaryAction(item) {
        const actions = arrayOrEmpty(item && item.actions);
        return actions.length > 0 ? actions[0] : null;
    }

    function notificationAppLabel(item) {
        const appName = stringOrEmpty(item && item.app_name);
        const desktopEntry = stringOrEmpty(item && item.desktop_entry);
        if (appName) {
            return appName;
        }
        if (desktopEntry) {
            return desktopEntry;
        }
        return "Notification";
    }

    function notificationHeadline(item) {
        const summary = stringOrEmpty(item && item.summary);
        if (summary) {
            return summary;
        }
        return notificationAppLabel(item);
    }

    function notificationBody(item) {
        return stringOrEmpty(item && item.body);
    }

    function notificationAvatarText(item) {
        const label = notificationAppLabel(item);
        return label ? label.slice(0, 1).toUpperCase() : "•";
    }

    function notificationResolvedIcon(item) {
        const appIcon = stringOrEmpty(item && item.app_icon);
        if (appIcon) {
            return Quickshell.iconPath(appIcon, true) || appIcon;
        }

        const desktopEntry = stringOrEmpty(item && item.desktop_entry);
        if (desktopEntry) {
            return Quickshell.iconPath(desktopEntry, true);
        }

        return "";
    }

    function notificationResolvedImage(item) {
        if (!shellConfig.notificationImagesEnabled) {
            return "";
        }
        return stringOrEmpty(item && item.image);
    }

    function notificationAccentColor(item) {
        if (notificationIsCritical(item)) {
            return colors.red;
        }
        if (notificationHasActions(item)) {
            return colors.teal;
        }
        if (notificationUnread(item)) {
            return colors.blue;
        }
        return colors.violet;
    }

    function notificationAvatarFill(item) {
        if (notificationIsCritical(item)) {
            return colors.redBg;
        }
        if (notificationHasActions(item)) {
            return colors.tealBg;
        }
        if (notificationUnread(item)) {
            return colors.blueBg;
        }
        return colors.panelAlt;
    }

    function notificationCardFill(item) {
        if (notificationIsCritical(item)) {
            return colors.redBg;
        }
        if (notificationUnread(item)) {
            return colors.blueWash;
        }
        return colors.cardAlt;
    }

    function notificationCardBorder(item) {
        if (notificationIsCritical(item)) {
            return colors.red;
        }
        if (notificationUnread(item)) {
            return colors.blueMuted;
        }
        return colors.lineSoft;
    }

    function notificationMetaLabel(item) {
        const parts = [];
        const appLabel = notificationAppLabel(item);
        if (appLabel) {
            parts.push(appLabel);
        }
        const outputName = stringOrEmpty(item && item.output_name);
        if (outputName) {
            parts.push(outputName);
        }
        const closedReason = stringOrEmpty(item && item.closed_reason);
        if (closedReason) {
            parts.push(closedReason);
        } else if (notificationUnread(item)) {
            parts.push("Unread");
        } else if (notificationClosed(item)) {
            parts.push("Seen");
        } else {
            parts.push("Live");
        }
        return parts.join(" • ");
    }

    function notificationDisplayCount(count) {
        const value = Number(count || 0);
        if (value > 9) {
            return "9+";
        }
        return String(Math.max(0, value));
    }

    function notificationUnreadCount() {
        return notificationFeed.filter(item => notificationUnread(item)).length;
    }

    function visibleNotificationItems() {
        return notificationFeed.filter(item => !notificationClosed(item));
    }

    function notificationPanelItems() {
        return notificationFeed.slice(0, Math.max(1, Number(shellConfig.notificationHistoryLimit || 80)));
    }

    function notificationHeroItem() {
        const live = visibleNotificationItems();
        if (live.length > 0) {
            return live[0];
        }
        return notificationFeed.length > 0 ? notificationFeed[0] : null;
    }

    function toastItemsForOutput(outputName) {
        return notificationFeed.filter(item => !notificationClosed(item) && boolOrFalse(item.toast_visible) && stringOrEmpty(item.output_name) === stringOrEmpty(outputName)).slice(0, Math.max(1, Number(shellConfig.notificationToastMaxPerOutput || 4)));
    }

    function refreshNotificationState() {
        const unreadCount = notificationUnreadCount();
        notificationState = {
            count: unreadCount,
            dnd: notificationDnd,
            visible: notificationCenterVisible,
            inhibited: false,
            has_unread: unreadCount > 0,
            display_count: notificationDisplayCount(unreadCount),
            error: false
        };
    }

    function replaceNotificationItem(updatedItem) {
        const next = [];
        let replaced = false;
        for (let i = 0; i < notificationFeed.length; i += 1) {
            const item = notificationFeed[i];
            if (Number(item && item.id) === Number(updatedItem && updatedItem.id)) {
                next.push(updatedItem);
                replaced = true;
            } else {
                next.push(item);
            }
        }
        if (!replaced) {
            next.unshift(updatedItem);
        }
        notificationFeed = next.slice(0, Math.max(1, Number(shellConfig.notificationHistoryLimit || 80)));
        refreshNotificationState();
    }

    function markNotificationRead(notificationId) {
        const targetId = Number(notificationId || 0);
        if (!targetId) {
            return;
        }
        for (let i = 0; i < notificationFeed.length; i += 1) {
            const item = notificationFeed[i];
            if (Number(item && item.id) !== targetId || !notificationUnread(item)) {
                continue;
            }
            replaceNotificationItem({
                id: item.id,
                app_name: item.app_name,
                app_icon: item.app_icon,
                desktop_entry: item.desktop_entry,
                summary: item.summary,
                body: item.body,
                urgency: item.urgency,
                output_name: item.output_name,
                image: item.image,
                unread: false,
                closed: item.closed,
                closed_reason: item.closed_reason,
                toast_visible: item.toast_visible,
                actions: arrayOrEmpty(item.actions)
            });
            break;
        }
    }

    function markAllNotificationsRead() {
        let changed = false;
        const next = notificationFeed.map(item => {
            if (!notificationUnread(item)) {
                return item;
            }
            changed = true;
            return {
                id: item.id,
                app_name: item.app_name,
                app_icon: item.app_icon,
                desktop_entry: item.desktop_entry,
                summary: item.summary,
                body: item.body,
                urgency: item.urgency,
                output_name: item.output_name,
                image: item.image,
                unread: false,
                closed: item.closed,
                closed_reason: item.closed_reason,
                toast_visible: item.toast_visible,
                actions: arrayOrEmpty(item.actions)
            };
        });
        if (changed) {
            notificationFeed = next;
        }
        refreshNotificationState();
    }

    function clearNotifications() {
        const ids = notificationFeed.map(item => Number(item && item.id)).filter(id => id > 0);
        for (let i = 0; i < ids.length; i += 1) {
            dismissNotification(ids[i]);
        }
        notificationFeed = [];
        notificationRuntimeMap = ({});
        refreshNotificationState();
    }

    function notificationTimeoutFor(item) {
        if (notificationIsCritical(item)) {
            return Number(shellConfig.notificationCriticalTimeoutMs || 0);
        }
        return Number(item && item.timeout_ms) > 0 ? Number(item.timeout_ms) : Number(shellConfig.notificationDefaultTimeoutMs || 8000);
    }

    function dismissNotification(notificationId) {
        const targetId = Number(notificationId || 0);
        if (!targetId) {
            return;
        }
        const notification = notificationRuntimeMap[String(targetId)];
        if (notification) {
            notification.dismiss();
        } else {
            for (let i = 0; i < notificationFeed.length; i += 1) {
                const item = notificationFeed[i];
                if (Number(item && item.id) !== targetId) {
                    continue;
                }
                replaceNotificationItem({
                    id: item.id,
                    app_name: item.app_name,
                    app_icon: item.app_icon,
                    desktop_entry: item.desktop_entry,
                    summary: item.summary,
                    body: item.body,
                    urgency: item.urgency,
                    output_name: item.output_name,
                    image: item.image,
                    unread: false,
                    closed: true,
                    closed_reason: "Dismissed",
                    toast_visible: false,
                    actions: arrayOrEmpty(item.actions)
                });
                break;
            }
        }
    }

    function expireNotification(notificationId) {
        const targetId = Number(notificationId || 0);
        if (!targetId) {
            return;
        }
        const notification = notificationRuntimeMap[String(targetId)];
        if (notification) {
            notification.expire();
        }
    }

    function invokeNotificationAction(notificationId, actionId) {
        const targetId = Number(notificationId || 0);
        const notification = notificationRuntimeMap[String(targetId)];
        if (!notification) {
            return;
        }
        const actions = arrayOrEmpty(notification.actions);
        for (let i = 0; i < actions.length; i += 1) {
            const action = actions[i];
            if (notificationActionIdentifier(action) !== stringOrEmpty(actionId)) {
                continue;
            }
            markNotificationRead(targetId);
            action.invoke();
            break;
        }
    }

    function showNotificationDetail(id) {
        var feed = arrayOrEmpty(notificationFeed);
        for (var i = 0; i < feed.length; i += 1) {
            if (Number(feed[i] && feed[i].id) === id) {
                notificationDetailItem = feed[i];
                notificationDetailVisible = true;
                return;
            }
        }
    }

    function hideNotificationDetail() {
        notificationDetailVisible = false;
        notificationDetailItem = null;
    }

    function toggleNotifications() {
        panelVisible = true;
        notificationCenterVisible = !notificationCenterVisible;
    }

    function toggleNotificationDnd() {
        notificationDnd = !notificationDnd;
        refreshNotificationState();
    }

    function connectNotificationLifecycle(notification) {
        const targetId = Number(notification && notification.id);
        if (!targetId) {
            return;
        }
        if (notificationLifecycleConnected[String(targetId)]) {
            return;
        }
        notificationLifecycleConnected = Object.assign({}, notificationLifecycleConnected, {
            [String(targetId)]: true
        });
        notification.closed.connect(function(reason) {
            const reasonLabel = String(reason).indexOf("Expired") >= 0 ? "Expired" : (String(reason).indexOf("Dismissed") >= 0 ? "Dismissed" : "Closed");
            delete notificationRuntimeMap[String(targetId)];
            delete notificationLifecycleConnected[String(targetId)];
            for (let i = 0; i < notificationFeed.length; i += 1) {
                const item = notificationFeed[i];
                if (Number(item && item.id) !== targetId) {
                    continue;
                }
                replaceNotificationItem({
                    id: item.id,
                    app_name: item.app_name,
                    app_icon: item.app_icon,
                    desktop_entry: item.desktop_entry,
                    summary: item.summary,
                    body: item.body,
                    urgency: item.urgency,
                    output_name: item.output_name,
                    image: item.image,
                    unread: item.unread,
                    closed: true,
                    closed_reason: reasonLabel,
                    toast_visible: false,
                    timeout_ms: item.timeout_ms,
                    actions: arrayOrEmpty(item.actions)
                });
                break;
            }
        });
    }

    function handleNativeNotification(notification) {
        const targetId = Number(notification && notification.id);
        if (!targetId) {
            return;
        }

        notification.tracked = true;
        notificationRuntimeMap = Object.assign({}, notificationRuntimeMap, {
            [String(targetId)]: notification
        });

        connectNotificationLifecycle(notification);

        const snapshot = {
            id: targetId,
            app_name: stringOrEmpty(notification.appName),
            app_icon: stringOrEmpty(notification.appIcon),
            desktop_entry: stringOrEmpty(notification.desktopEntry),
            summary: stringOrEmpty(notification.summary),
            body: stringOrEmpty(notification.body),
            urgency: stringOrEmpty(NotificationUrgency.toString(notification.urgency)),
            output_name: notificationTargetOutputName(),
            image: shellConfig.notificationImagesEnabled ? stringOrEmpty(notification.image) : "",
            unread: true,
            closed: false,
            closed_reason: "",
            toast_visible: !notificationDnd || stringOrEmpty(NotificationUrgency.toString(notification.urgency)).toLowerCase() === "critical",
            timeout_ms: notification.expireTimeout,
            actions: arrayOrEmpty(notification.actions).map(action => ({
                identifier: notificationActionIdentifier(action),
                text: notificationActionText(action)
            }))
        };

        replaceNotificationItem(snapshot);
    }

    function topBarTimeText() {
        if (!clock) {
            return "";
        }
        return Qt.formatDateTime(clock.date, shellConfig.topBarShowSeconds ? "ddd MMM d  h:mm:ss AP" : "ddd MMM d  h:mm AP");
    }

    function neutralChipFill(hovered) {
        return colors.cardAlt;
    }

    function neutralChipBorder(hovered) {
        return hovered ? colors.blueMuted : colors.border;
    }

    function neutralChipText(hovered) {
        return colors.text;
    }

    function stateChipFill(active, hovered, activeFill) {
        return active ? activeFill : colors.cardAlt;
    }

    function stateChipBorder(active, hovered, activeBorder) {
        return active ? activeBorder : neutralChipBorder(hovered);
    }

    function stateChipText(active, hovered, activeText) {
        return active ? activeText : neutralChipText(hovered);
    }

    function sidebarRowFill(windowData, hovered) {
        if (boolOrFalse(windowData && windowData.focused)) {
            return colors.blueWash;
        }
        if (hovered) {
            return boolOrFalse(windowData && windowData.hidden) ? colors.cardAlt : colors.card;
        }
        return boolOrFalse(windowData && windowData.hidden) ? colors.cardAlt : colors.bg;
    }

    function sidebarRowBorder(windowData, hovered) {
        if (boolOrFalse(windowData && windowData.focused)) {
            return colors.blueMuted;
        }
        return hovered ? colors.borderStrong : "transparent";
    }

    function sidebarRowText(windowData, hovered) {
        return boolOrFalse(windowData && windowData.focused) || hovered ? colors.text : colors.textDim;
    }

    function chooserRowFill(hovered) {
        return hovered ? colors.panelAlt : colors.cardAlt;
    }

    function chooserRowBorder(hovered) {
        return hovered ? colors.borderStrong : colors.lineSoft;
    }

    function workspaceChipFill(workspace, hovered) {
        if (boolOrFalse(workspace && workspace.focused)) {
            return colors.blue;
        }
        if (hovered) {
            return colors.card;
        }
        return boolOrFalse(workspace && workspace.active) ? colors.card : colors.cardAlt;
    }

    function workspaceChipBorder(workspace, hovered) {
        if (boolOrFalse(workspace && workspace.focused)) {
            return colors.blue;
        }
        if (boolOrFalse(workspace && workspace.urgent)) {
            return colors.red;
        }
        return hovered ? colors.borderStrong : colors.border;
    }

    function workspaceChipText(workspace, hovered) {
        if (boolOrFalse(workspace && workspace.focused)) {
            return colors.bg;
        }
        return hovered ? colors.text : colors.textDim;
    }

    function audioNode() {
        return Pipewire.ready ? Pipewire.defaultAudioSink : null;
    }

    function audioNodes() {
        const nodes = arrayOrEmpty(Pipewire.nodes ? Pipewire.nodes.values : []);
        const sinks = [];
        for (let i = 0; i < nodes.length; i += 1) {
            const node = nodes[i];
            if (!(node && node.ready && boolOrFalse(node.isSink) && node.audio)) {
                continue;
            }
            sinks.push(node);
        }
        return sinks;
    }

    function audioSinkIdentity(node) {
        return stringOrEmpty(node && (node.objectSerial || node.id || node.name || node.nickname || node.description));
    }

    function audioSinkLabel(node) {
        return stringOrEmpty(node && (node.description || node.nickname || node.name || "Audio output"));
    }

    function audioSinkIsActive(node) {
        return audioSinkIdentity(node) === audioSinkIdentity(audioNode());
    }

    function audioReady() {
        const node = audioNode();
        return !!(node && node.ready && node.audio);
    }

    function volumePercent() {
        const node = audioNode();
        if (!(node && node.audio)) {
            return 0;
        }
        return Math.round(Math.max(0, Number(node.audio.volume || 0)) * 100);
    }

    function audioLabel() {
        if (!audioReady()) {
            return "Audio --";
        }
        const node = audioNode();
        if (boolOrFalse(node.audio.muted) || volumePercent() === 0) {
            return "Muted";
        }
        return "Vol " + String(volumePercent()) + "%";
    }

    function audioDetail() {
        const node = audioNode();
        if (!(node && node.ready)) {
            return "PipeWire unavailable";
        }
        return audioSinkLabel(node);
    }

    function changeVolume(delta) {
        const node = audioNode();
        if (!(node && node.audio)) {
            return;
        }

        const current = Math.max(0, Number(node.audio.volume || 0));
        node.audio.volume = Math.max(0, Math.min(1.5, current + delta));
    }

    function toggleMute() {
        const node = audioNode();
        if (!(node && node.audio)) {
            return;
        }
        node.audio.muted = !boolOrFalse(node.audio.muted);
    }

    function setPreferredAudioSink(node) {
        if (!(Pipewire.ready && node && node.ready)) {
            return;
        }
        Pipewire.preferredDefaultAudioSink = node;
    }

    function defaultBluetoothAdapter() {
        return Bluetooth.defaultAdapter || null;
    }

    function bluetoothAvailable() {
        return !!defaultBluetoothAdapter();
    }

    function bluetoothEnabled() {
        const adapter = defaultBluetoothAdapter();
        return !!(adapter && adapter.enabled);
    }

    function bluetoothDevices() {
        const adapter = defaultBluetoothAdapter();
        if (!adapter) {
            return [];
        }
        const devices = adapter.devices;
        return arrayOrEmpty(devices && devices.values ? devices.values : devices);
    }

    function bluetoothConnectedDevices() {
        const devices = bluetoothDevices();
        const connected = [];
        for (let i = 0; i < devices.length; i += 1) {
            if (boolOrFalse(devices[i] && devices[i].connected)) {
                connected.push(devices[i]);
            }
        }
        return connected;
    }

    function bluetoothConnectedCount() {
        return bluetoothConnectedDevices().length;
    }

    function bluetoothLabel() {
        if (!bluetoothAvailable()) {
            return "BT --";
        }
        if (!bluetoothEnabled()) {
            return "BT Off";
        }
        const connected = bluetoothConnectedCount();
        if (connected > 0) {
            return "BT " + String(connected);
        }
        return "BT On";
    }

    function bluetoothDetail() {
        if (!bluetoothAvailable()) {
            return "No Bluetooth adapter";
        }
        if (!bluetoothEnabled()) {
            return "Bluetooth disabled";
        }
        const connected = bluetoothConnectedDevices();
        if (!connected.length) {
            return "Bluetooth enabled";
        }
        const names = [];
        for (let i = 0; i < connected.length; i += 1) {
            names.push(stringOrEmpty(connected[i] && connected[i].name) || "Connected device");
        }
        return names.join(" • ");
    }

    function setBluetoothEnabled(enabled) {
        const adapter = defaultBluetoothAdapter();
        if (!adapter) {
            return;
        }
        adapter.enabled = enabled;
    }

    function toggleBluetoothEnabled() {
        setBluetoothEnabled(!bluetoothEnabled());
    }

    function toggleBluetoothDevice(device) {
        if (!device) {
            return;
        }
        if (boolOrFalse(device.connected)) {
            device.disconnect();
            return;
        }
        device.connect();
    }

    function batteryDevice() {
        return UPower.displayDevice;
    }

    function batteryReady() {
        const device = batteryDevice();
        return !!(device && device.ready && device.isPresent && device.isLaptopBattery);
    }

    function batteryDurationCompact(seconds) {
        const totalSeconds = Math.max(0, Math.round(Number(seconds || 0)));
        if (totalSeconds <= 0) {
            return "";
        }

        const totalMinutes = Math.round(totalSeconds / 60);
        if (totalMinutes < 60) {
            return String(totalMinutes) + "m";
        }

        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        if (minutes <= 0) {
            return String(hours) + "h";
        }
        return String(hours) + "h " + String(minutes) + "m";
    }

    function batteryDurationLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }

        if (device.state === UPowerDeviceState.Charging && Number(device.timeToFull || 0) > 0) {
            return batteryDurationCompact(device.timeToFull) + " to full";
        }
        if (device.state === UPowerDeviceState.Discharging && Number(device.timeToEmpty || 0) > 0) {
            return batteryDurationCompact(device.timeToEmpty) + " left";
        }
        return "";
    }

    function batteryPercentNumber() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return 0;
        }

        let percentage = Number(device.percentage || 0);
        if (percentage > 0 && percentage <= 1.5) {
            percentage *= 100;
        }
        return Math.round(Math.max(0, percentage));
    }

    function batteryLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }

        const percentage = batteryPercentNumber();
        const duration = batteryDurationLabel();
        if (device.state === UPowerDeviceState.Charging) {
            return duration ? "Charging " + String(percentage) + "% · " + duration : "Charging " + String(percentage) + "%";
        }
        if (device.state === UPowerDeviceState.FullyCharged) {
            return "Full " + String(percentage) + "%";
        }
        return duration ? "Battery " + String(percentage) + "% · " + duration : "Battery " + String(percentage) + "%";
    }

    function batteryPercentValue() {
        return batteryPercentNumber();
    }

    function batteryIsDischarging() {
        const device = batteryDevice();
        return batteryReady() && device.state === UPowerDeviceState.Discharging;
    }

    function batteryCritical() {
        return batteryIsDischarging() && batteryPercentValue() <= 15;
    }

    function batteryLow() {
        return batteryIsDischarging() && batteryPercentValue() <= 30;
    }

    function batteryTooltip() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }

        const bits = [batteryLabel()];
        const duration = batteryDurationLabel();
        if (duration) {
            bits.push(duration);
        }
        return bits.join(" • ");
    }

    function batteryIconSource() {
        const device = batteryDevice();
        const iconName = stringOrEmpty(device ? device.iconName : "");
        return iconName ? Quickshell.iconPath(iconName, true) : "";
    }

    function networkLabel() {
        if (!boolOrFalse(networkState.connected)) {
            return "Offline";
        }
        if (stringOrEmpty(networkState.kind) === "wifi" && networkState.signal !== null && networkState.signal !== undefined) {
            return "Wi-Fi " + String(networkState.signal) + "%";
        }
        if (stringOrEmpty(networkState.kind) === "ethernet") {
            return "Ethernet";
        }
        return stringOrEmpty(networkState.label || "Connected");
    }

    function networkDetail() {
        if (!boolOrFalse(networkState.connected)) {
            return "No active NetworkManager connection";
        }
        return stringOrEmpty(networkState.label || "Connected");
    }

    function networkChipText(hovered) {
        if (!boolOrFalse(networkState.connected)) {
            return hovered ? colors.amber : colors.subtle;
        }
        return neutralChipText(hovered);
    }

    function systemStatsMemoryPercentValue() {
        return Math.round(Math.max(0, Number(systemStatsState.memory_percent || 0)));
    }

    function systemStatsMemoryLabel() {
        return "Mem " + String(systemStatsMemoryPercentValue()) + "%";
    }

    function systemStatsMemoryTooltip() {
        const bits = [
            String(Number(systemStatsState.memory_used_gb || 0).toFixed(1)) + " / " + String(Number(systemStatsState.memory_total_gb || 0).toFixed(1)) + " GB",
            "load " + String(Number(systemStatsState.load1 || 0).toFixed(2))
        ];
        if (Number(systemStatsState.swap_total_gb || 0) > 0) {
            bits.push("swap " + String(Number(systemStatsState.swap_used_gb || 0).toFixed(1)) + " GB");
        }
        if (systemStatsState.temperature_c !== null && systemStatsState.temperature_c !== undefined) {
            bits.push(String(systemStatsState.temperature_c) + "°C");
        }
        return bits.join(" • ");
    }

    function systemGenerationLabel() {
        var gen = Number(systemStatsState.system_generation || 0);
        return gen > 0 ? ("Gen " + String(gen)) : "Gen ?";
    }

    function systemStatsSummaryLabel() {
        const bits = ["Mem " + String(systemStatsMemoryPercentValue()) + "%", "Load " + String(Number(systemStatsState.load1 || 0).toFixed(2))];
        if (systemStatsState.temperature_c !== null && systemStatsState.temperature_c !== undefined) {
            bits.push(String(systemStatsState.temperature_c) + "°C");
        }
        return bits.join(" • ");
    }

    function notificationChipFill(hovered) {
        const dnd = boolOrFalse(notificationState.dnd);
        const visible = boolOrFalse(notificationState.visible);
        if (dnd) {
            return stateChipFill(true, hovered, colors.amberBg);
        }
        if (visible) {
            return stateChipFill(true, hovered, colors.blueBg);
        }
        return neutralChipFill(hovered);
    }

    function notificationChipBorder(hovered) {
        const dnd = boolOrFalse(notificationState.dnd);
        const visible = boolOrFalse(notificationState.visible);
        const unread = boolOrFalse(notificationState.has_unread);
        if (dnd) {
            return stateChipBorder(true, hovered, colors.amber);
        }
        if (visible) {
            return stateChipBorder(true, hovered, colors.blue);
        }
        if (unread) {
            return colors.blue;
        }
        return neutralChipBorder(hovered);
    }

    function notificationChipText(hovered) {
        const dnd = boolOrFalse(notificationState.dnd);
        const visible = boolOrFalse(notificationState.visible);
        if (dnd) {
            return stateChipText(true, hovered, colors.amber);
        }
        if (visible) {
            return stateChipText(true, hovered, colors.blue);
        }
        return neutralChipText(hovered);
    }

    function audioMuted() {
        return boolOrFalse(audioNode() && audioNode().audio && audioNode().audio.muted);
    }

    function audioChipBorder(hovered) {
        if (audioMuted()) {
            return colors.red;
        }
        return neutralChipBorder(hovered);
    }

    function audioChipText(hovered) {
        if (audioMuted()) {
            return colors.red;
        }
        return neutralChipText(hovered);
    }

    function batteryChipBorder(hovered) {
        if (batteryCritical()) {
            return colors.red;
        }
        if (batteryLow()) {
            return colors.amber;
        }
        return neutralChipBorder(hovered);
    }

    function batteryChipText(hovered) {
        if (batteryCritical()) {
            return colors.red;
        }
        if (batteryLow()) {
            return colors.amber;
        }
        return neutralChipText(hovered);
    }

    function powerChipFill(hovered) {
        return root.powerMenuVisible ? colors.redBg : neutralChipFill(hovered);
    }

    function powerChipBorder(hovered) {
        return root.powerMenuVisible ? colors.red : neutralChipBorder(hovered);
    }

    function powerChipText(hovered) {
        return root.powerMenuVisible ? colors.red : neutralChipText(hovered);
    }

    function notificationLabel() {
        if (boolOrFalse(notificationState.dnd)) {
            return "DND";
        }
        if (boolOrFalse(notificationState.has_unread)) {
            return "Notif " + stringOrEmpty(notificationState.display_count || "0");
        }
        return "Notif";
    }

    function notificationDetail() {
        if (boolOrFalse(notificationState.dnd)) {
            return "Do not disturb enabled";
        }
        if (boolOrFalse(notificationState.visible)) {
            return "Notification center open";
        }
        if (boolOrFalse(notificationState.has_unread)) {
            return stringOrEmpty(notificationState.display_count || "0") + " unread notifications";
        }
        return "No unread notifications";
    }

    function sessionViewportWidth() {
        return Math.max(0, panelWindow.width - 44);
    }

    function sessionColumnCountForWidth(width) {
        return width >= 240 ? 2 : 1;
    }

    function sessionCardWidthForWidth(width) {
        const columns = sessionColumnCountForWidth(width);
        const available = Math.max(0, width);
        const spacing = 8 * Math.max(0, columns - 1);
        return Math.floor((available - spacing) / columns);
    }

    function sessionRowCountForWidth(width) {
        const columns = Math.max(1, sessionColumnCountForWidth(width));
        return Math.ceil(compactSessions().length / columns);
    }

    function sessionRailHeightForWidth(width) {
        const rows = Math.max(1, sessionRowCountForWidth(width));
        const visibleRows = Math.min(2, rows);
        const cardHeight = 58;
        const spacing = 8;
        return 16 + (visibleRows * cardHeight) + (Math.max(0, visibleRows - 1) * spacing);
    }

    function dashboardWorktrees() {
        return arrayOrEmpty(dashboard.worktrees);
    }

    function activeWorktreeItem() {
        const items = worktreeItems();
        for (let i = 0; i < items.length; i += 1) {
            if (boolOrFalse(items[i].is_active)) {
                return items[i];
            }
        }
        return items.length ? items[0] : null;
    }

    function worktreePickerSummaryTitle() {
        const activeItem = activeWorktreeItem();
        return worktreeDisplayName(activeItem);
    }

    function inactiveWorktreeItems() {
        const items = worktreeItems();
        const filtered = [];
        for (let i = 0; i < items.length; i += 1) {
            const item = items[i];
            if (!item || boolOrFalse(item.is_active) || stringOrEmpty(item.kind) === "global") {
                continue;
            }
            filtered.push(item);
        }
        return filtered;
    }

    function worktreeItems() {
        const items = [
            {
                kind: "global",
                qualified_name: "global",
                is_active: root.isGlobalContext(),
                active_execution_mode: root.activeContextExecutionMode(),
                remote_available: false,
                visible_window_count: 0,
                scoped_window_count: 0,
                is_clean: true,
                dirty_count: 0,
                last_used_at: 0,
                use_count: 0
            }
        ];

        const worktrees = dashboardWorktrees();
        for (let i = 0; i < worktrees.length; i += 1) {
            const worktree = worktrees[i];
            items.push({
                kind: "worktree",
                qualified_name: stringOrEmpty(worktree.qualified_name),
                repo_display: stringOrEmpty(worktree.repo_display),
                repo_name: stringOrEmpty(worktree.repo_name),
                account: stringOrEmpty(worktree.account),
                branch: stringOrEmpty(worktree.branch),
                path: stringOrEmpty(worktree.path),
                is_main: boolOrFalse(worktree.is_main),
                is_clean: boolOrFalse(worktree.is_clean),
                is_stale: boolOrFalse(worktree.is_stale),
                has_conflicts: boolOrFalse(worktree.has_conflicts),
                ahead: Number(worktree.ahead || 0),
                behind: Number(worktree.behind || 0),
                dirty_count: Number(worktree.dirty_count || 0),
                is_active: boolOrFalse(worktree.is_active),
                active_execution_mode: stringOrEmpty(worktree.active_execution_mode),
                remote_available: boolOrFalse(worktree.remote_available),
                visible_window_count: Number(worktree.visible_window_count || 0),
                scoped_window_count: Number(worktree.scoped_window_count || 0),
                last_used_at: Number(worktree.last_used_at || 0),
                use_count: Number(worktree.use_count || 0),
                last_commit_message: stringOrEmpty(worktree.last_commit_message)
            });
        }

        return items;
    }

    function normalizeLauncherMode(mode) {
        const value = stringOrEmpty(mode).toLowerCase();
        if (value === "files") {
            return "files";
        }
        if (value === "urls") {
            return "urls";
        }
        if (value === "projects") {
            return "projects";
        }
        if (value === "runner") {
            return "runner";
        }
        if (value === "snippets") {
            return "snippets";
        }
        if (value === "sessions") {
            return "sessions";
        }
        if (value === "windows") {
            return "windows";
        }
        if (value === "onepassword") {
            return "onepassword";
        }
        if (value === "clipboard") {
            return "clipboard";
        }
        return "apps";
    }

    function launcherModeOrder() {
        return ["apps", "files", "urls", "projects", "runner", "snippets", "onepassword", "clipboard", "sessions", "windows"];
    }

    function setLauncherMode(mode) {
        launcherMode = normalizeLauncherMode(mode);
    }

    function showLauncher(mode, query) {
        settingsVisible = false;
        if (!launcherVisible) {
            launcherVisible = true;
        }

        const nextMode = normalizeLauncherMode(mode);
        const nextQuery = stringOrEmpty(query);

        if (launcherMode !== nextMode) {
            launcherMode = nextMode;
        }
        if (launcherQuery !== nextQuery) {
            launcherQuery = nextQuery;
        }

        launcherQueryDebounce.stop();
        restartLauncherQuery();
        launcherFocusTimer.restart();
    }

    function cycleLauncherMode(delta) {
        const modes = launcherModeOrder();
        if (!modes.length) {
            return;
        }

        const current = normalizeLauncherMode(launcherMode);
        const currentIndex = modes.indexOf(current);
        const startIndex = currentIndex >= 0 ? currentIndex : 0;
        const nextIndex = (startIndex + delta + modes.length) % modes.length;
        setLauncherMode(modes[nextIndex]);
    }

    function launcherTitle() {
        if (launcherMode === "files") {
            return "Find File";
        }
        if (launcherMode === "urls") {
            return "Open URL";
        }
        if (launcherMode === "projects") {
            return "Switch Project";
        }
        if (launcherMode === "runner") {
            return "Run Command";
        }
        if (launcherMode === "snippets") {
            return "Curated Commands";
        }
        if (launcherMode === "sessions") {
            return "AI Sessions";
        }
        if (launcherMode === "windows") {
            return "Windows";
        }
        if (launcherMode === "onepassword") {
            return "1Password";
        }
        if (launcherMode === "clipboard") {
            return "Clipboard";
        }
        return "Launch App";
    }

    function launcherPlaceholderText() {
        if (launcherMode === "files") {
            return "Search files from home or type a path prefix";
        }
        if (launcherMode === "urls") {
            return "Search Chrome URLs, bookmarks, tabs, or paste a link";
        }
        if (launcherMode === "projects") {
            return "Filter projects";
        }
        if (launcherMode === "runner") {
            return "Type a shell command";
        }
        if (launcherMode === "snippets") {
            return "Search curated commands";
        }
        if (launcherMode === "sessions") {
            return "Filter AI sessions";
        }
        if (launcherMode === "windows") {
            return "Filter windows";
        }
        if (launcherMode === "onepassword") {
            return "Search 1Password";
        }
        if (launcherMode === "clipboard") {
            return "Search clipboard history";
        }
        return "Search apps or type /, ;u, ;p, >, $, ;s, ;w, *, or :";
    }

    function launcherHelpText() {
        if (launcherMode === "files") {
            return "Enter open  •  Ctrl+Enter location  •  Ctrl+1 Apps";
        }
        if (launcherMode === "urls") {
            return "Enter open  •  Shift+Enter browser  •  Ctrl+Enter copy  •  Ctrl+3 Projects";
        }
        if (launcherMode === "projects") {
            return "Tab modes  •  Up/Down results  •  Ctrl+1 Apps  •  Ctrl+2 URLs";
        }
        if (launcherMode === "runner") {
            return "Tab modes  •  Enter run  •  Shift+Enter terminal  •  Ctrl+9 Snippets";
        }
        if (launcherMode === "snippets") {
            return "Enter run  •  Shift+Enter scratchpad  •  Manage via toggle-runtime-settings";
        }
        if (launcherMode === "sessions") {
            return "Mod+Tab cycle  •  Release Mod to focus  •  Enter focus  •  Ctrl+6 Windows";
        }
        if (launcherMode === "windows") {
            return "Tab modes  •  Up/Down windows  •  Enter focus  •  Ctrl+W close";
        }
        if (launcherMode === "onepassword") {
            return "Tab modes  •  Enter password  •  Shift+Enter user  •  Ctrl+Enter OTP";
        }
        if (launcherMode === "clipboard") {
            return "Tab modes  •  Enter smart paste  •  Ctrl+D remove";
        }
        return "Tab modes  •  Up/Down results  •  Ctrl+2 URLs";
    }

    function launcherStatusText() {
        if (launcherLoading) {
            if (launcherMode === "files") {
                return "Searching files";
            }
            if (launcherMode === "urls") {
                return "Loading Chrome URLs";
            }
            if (launcherMode === "onepassword") {
                return "Loading 1Password items";
            }
            if (launcherMode === "clipboard") {
                return "Loading clipboard history";
            }
            if (launcherMode === "runner") {
                return "Preparing command";
            }
            if (launcherMode === "snippets") {
                return "Loading curated commands";
            }
            return "Searching with Elephant";
        }
        if (launcherMode === "files") {
            return launcherEntries.length ? launcherEntries.length + " file result" + (launcherEntries.length === 1 ? "" : "s") : "No matching files";
        }
        if (launcherMode === "urls") {
            return launcherEntries.length ? launcherEntries.length + " URL result" + (launcherEntries.length === 1 ? "" : "s") : "No matching URLs";
        }
        if (launcherMode === "projects") {
            return launcherEntries.length ? launcherEntries.length + " project context" + (launcherEntries.length === 1 ? "" : "s") : "No matching projects";
        }
        if (launcherMode === "runner") {
            return launcherEntries.length ? launcherEntries.length + " command ready" : "Type a command to run";
        }
        if (launcherMode === "snippets") {
            return launcherEntries.length ? launcherEntries.length + " curated command" + (launcherEntries.length === 1 ? "" : "s") : "No matching curated commands";
        }
        if (launcherMode === "sessions") {
            return launcherEntries.length ? launcherEntries.length + " AI session" + (launcherEntries.length === 1 ? "" : "s") : "No matching AI sessions";
        }
        if (launcherMode === "windows") {
            return launcherEntries.length ? launcherEntries.length + " window" + (launcherEntries.length === 1 ? "" : "s") : "No matching windows";
        }
        if (launcherMode === "onepassword") {
            return launcherEntries.length ? launcherEntries.length + " 1Password item" + (launcherEntries.length === 1 ? "" : "s") : "No matching 1Password items";
        }
        if (launcherMode === "clipboard") {
            return launcherEntries.length ? launcherEntries.length + " clipboard item" + (launcherEntries.length === 1 ? "" : "s") : "No matching clipboard items";
        }
        return launcherEntries.length ? launcherEntries.length + " app" + (launcherEntries.length === 1 ? "" : "s") : "No matching apps";
    }

    function launcherEmptyText() {
        if (launcherError) {
            return launcherError;
        }
        if (launcherMode === "files") {
            return "No files match the current query";
        }
        if (launcherMode === "urls") {
            return "No Chrome URLs or PWAs match the current query";
        }
        if (launcherMode === "projects") {
            return "No projects match the current query";
        }
        if (launcherMode === "runner") {
            return "Type a command to run from the current context";
        }
        if (launcherMode === "snippets") {
            return "No curated commands match the current query";
        }
        if (launcherMode === "sessions") {
            return "No AI sessions match the current query";
        }
        if (launcherMode === "windows") {
            return "No windows match the current query";
        }
        if (launcherMode === "onepassword") {
            return "No 1Password items match the current query";
        }
        if (launcherMode === "clipboard") {
            return "No clipboard items match the current query";
        }
        return "No apps match the current query";
    }

    function updateLauncherInput(rawInput) {
        let nextMode = launcherMode;
        let nextQuery = stringOrEmpty(rawInput);

        if (nextQuery === "/" || nextQuery.indexOf("/") === 0) {
            nextMode = "files";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";u") === 0) {
            nextMode = "urls";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";p") === 0) {
            nextMode = "projects";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        } else if (nextQuery === ">" || nextQuery.indexOf(">") === 0) {
            nextMode = "runner";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery === "$" || nextQuery.indexOf("$") === 0) {
            nextMode = "snippets";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";s") === 0) {
            nextMode = "sessions";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";w") === 0) {
            nextMode = "windows";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        } else if (nextQuery === "*" || nextQuery.indexOf("* ") === 0) {
            nextMode = "onepassword";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery === ":" || nextQuery.indexOf(":") === 0) {
            nextMode = "clipboard";
            nextQuery = nextQuery.slice(1).replace(/^\s+/, "");
        } else if (nextQuery.indexOf(";a") === 0) {
            nextMode = "apps";
            nextQuery = nextQuery.slice(2).replace(/^\s+/, "");
        }

        if (launcherMode !== nextMode) {
            launcherMode = nextMode;
        }
        if (launcherQuery !== nextQuery) {
            launcherQuery = nextQuery;
        }
        if (launcherSessionSwitcherActive && (nextMode !== "sessions" || nextQuery !== "")) {
            launcherSessionSwitcherActive = false;
        }
        if (launcherField && launcherField.text !== nextQuery) {
            launcherNormalizingInput = true;
            launcherField.text = nextQuery;
            launcherNormalizingInput = false;
        }
    }

    function launcherQueryTokens(query) {
        const trimmed = stringOrEmpty(query).trim().toLowerCase();
        if (!trimmed) {
            return [];
        }
        return trimmed.split(/\s+/).filter(function (token) {
            return !!token;
        });
    }

    function launcherTokensMatch(tokens, haystackParts) {
        if (!tokens.length) {
            return true;
        }

        const haystack = haystackParts.join(" ").toLowerCase();
        for (let i = 0; i < tokens.length; i += 1) {
            if (haystack.indexOf(tokens[i]) === -1) {
                return false;
            }
        }
        return true;
    }

    function launcherProjectSubtitle(item) {
        if (!item) {
            return "";
        }
        if (stringOrEmpty(item.kind) === "global") {
            return "Return to global context";
        }

        const bits = [];
        const path = stringOrEmpty(item.path);
        if (path) {
            bits.push(path);
        }
        if (Number(item.dirty_count || 0) > 0) {
            bits.push("dirty:" + String(Number(item.dirty_count || 0)));
        }
        if (Number(item.visible_window_count || 0) > 0) {
            bits.push("visible:" + String(Number(item.visible_window_count || 0)));
        }
        if (Number(item.scoped_window_count || 0) > Number(item.visible_window_count || 0)) {
            bits.push("scoped:" + String(Number(item.scoped_window_count || 0)));
        }
        return bits.join("  •  ");
    }

    function launcherProjectMatches(entry, query) {
        const trimmed = stringOrEmpty(query).trim().toLowerCase();
        if (!trimmed) {
            return true;
        }

        const tokens = trimmed.split(/\s+/).filter(function (token) {
            return !!token;
        });
        const haystack = [stringOrEmpty(entry.qualified_name), stringOrEmpty(entry.repo_display), stringOrEmpty(entry.repo_name), stringOrEmpty(entry.account), stringOrEmpty(entry.branch), stringOrEmpty(entry.path), stringOrEmpty(entry.variant), stringOrEmpty(entry.text), stringOrEmpty(entry.subtext)].join(" ").toLowerCase();

        for (let i = 0; i < tokens.length; i += 1) {
            if (haystack.indexOf(tokens[i]) === -1) {
                return false;
            }
        }

        return true;
    }

    function onePasswordCategoryLabel(category) {
        const value = stringOrEmpty(category).toLowerCase();
        if (value === "login") {
            return "Login";
        }
        if (value === "secure_note") {
            return "Note";
        }
        if (value === "ssh_key") {
            return "SSH";
        }
        if (value === "credit_card") {
            return "Card";
        }
        if (value === "identity") {
            return "Identity";
        }
        if (value === "document") {
            return "Document";
        }
        if (value === "password") {
            return "Password";
        }
        if (value === "api_credential") {
            return "API";
        }
        if (!value) {
            return "";
        }
        return value.replace(/_/g, " ");
    }

    function onePasswordEntries(query) {
        const trimmed = stringOrEmpty(query).trim().toLowerCase();
        const tokens = trimmed ? trimmed.split(/\s+/).filter(function (token) {
            return !!token;
        }) : [];

        return arrayOrEmpty(onePasswordEntriesCache).filter(function (entry) {
            if (!tokens.length) {
                return true;
            }

            const haystack = [stringOrEmpty(entry.text), stringOrEmpty(entry.subtext), stringOrEmpty(entry.category), onePasswordCategoryLabel(entry.category)].join(" ").toLowerCase();

            for (let i = 0; i < tokens.length; i += 1) {
                if (haystack.indexOf(tokens[i]) === -1) {
                    return false;
                }
            }

            return true;
        });
    }

    function launcherEntryHasState(entry, stateName) {
        const target = stringOrEmpty(stateName).toLowerCase();
        const states = arrayOrEmpty(entry && entry.state);
        for (let i = 0; i < states.length; i += 1) {
            if (stringOrEmpty(states[i]).toLowerCase() === target) {
                return true;
            }
        }
        return false;
    }

    function launcherFileIsDirectory(entry) {
        if (stringOrEmpty(entry && entry.kind) !== "file") {
            return false;
        }
        if (launcherEntryHasState(entry, "dir") || launcherEntryHasState(entry, "directory") || launcherEntryHasState(entry, "folder")) {
            return true;
        }
        const identifier = stringOrEmpty(entry && entry.identifier);
        return identifier.endsWith("/");
    }

    function clipboardEntryHasImagePreview(entry) {
        if (stringOrEmpty(entry && entry.kind) !== "clipboard") {
            return false;
        }
        const previewType = stringOrEmpty(entry && entry.preview_type).toLowerCase();
        const preview = stringOrEmpty(entry && entry.preview);
        if (previewType !== "file" || !preview) {
            return false;
        }
        if (preview.indexOf("/") === 0) {
            return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(preview);
        }
        if (preview.indexOf("file://") === 0) {
            return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(preview);
        }
        return false;
    }

    function clipboardImageSource(entry) {
        if (!clipboardEntryHasImagePreview(entry)) {
            return "";
        }
        const preview = stringOrEmpty(entry && entry.preview);
        if (preview.indexOf("file://") === 0) {
            return preview;
        }
        if (preview.indexOf("/") === 0) {
            return "file://" + preview;
        }
        return "";
    }

    function clipboardEntryTitle(entry) {
        const text = stringOrEmpty(entry && entry.text).trim();
        if (text) {
            return text.replace(/\s+/g, " ");
        }
        if (clipboardEntryHasImagePreview(entry)) {
            return "Image clipboard item";
        }
        return "Clipboard item";
    }

    function clipboardEntrySubtitle(entry) {
        const bits = [];
        const subtext = stringOrEmpty(entry && entry.subtext);
        if (subtext) {
            bits.push(subtext);
        }
        if (launcherEntryHasState(entry, "pinned")) {
            bits.push("Pinned");
        }
        if (clipboardEntryHasImagePreview(entry)) {
            bits.push("Image");
        }
        return bits.join("  •  ");
    }

    function activeClipboardEntry() {
        const entry = activeLauncherEntry();
        if (stringOrEmpty(entry && entry.kind) !== "clipboard") {
            return null;
        }
        return entry;
    }

    function clipboardPreviewTitle(entry) {
        return clipboardEntryTitle(entry);
    }

    function clipboardPreviewBody(entry) {
        if (!entry) {
            return "";
        }
        const previewType = stringOrEmpty(entry.preview_type).toLowerCase();
        if (previewType === "text") {
            const preview = stringOrEmpty(entry.preview);
            return preview || stringOrEmpty(entry.text);
        }
        if (previewType === "file") {
            return stringOrEmpty(entry.preview);
        }
        return stringOrEmpty(entry.preview) || stringOrEmpty(entry.text);
    }

    function emptySessionPreview() {
        return {
            status: "idle",
            kind: "status",
            session_key: "",
            preview_mode: "",
            preview_reason: "",
            is_live: false,
            is_remote: false,
            tool: "",
            project_name: "",
            host_name: "",
            connection_key: "",
            execution_mode: "",
            focus_mode: "",
            window_id: 0,
            pane_label: "",
            pane_title: "",
            tmux_session: "",
            tmux_window: "",
            tmux_pane: "",
            surface_key: "",
            session_phase: "",
            session_phase_label: "",
            turn_owner: "",
            turn_owner_label: "",
            activity_substate: "",
            activity_substate_label: "",
            status_reason: "",
            content: "",
            message: "",
            updated_at: ""
        };
    }

    function activeLauncherSessionEntry() {
        const entry = activeLauncherEntry();
        if (stringOrEmpty(entry && entry.kind) !== "session") {
            return null;
        }
        return entry;
    }

    function clearSessionPreview() {
        sessionPreviewTargetKey = "";
        sessionPreviewAutoFollow = true;
        sessionPreviewHasUnseenOutput = false;
        sessionPreview = emptySessionPreview();
        if (sessionPreviewProcess.running) {
            sessionPreviewStopExpected = true;
            sessionPreviewProcess.running = false;
        }
    }

    function parseSessionPreview(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null" || raw.indexOf("{") !== 0) {
            return;
        }

        try {
            const previous = Object.assign({}, sessionPreview);
            const next = Object.assign(emptySessionPreview(), JSON.parse(raw));
            const contentChanged = stringOrEmpty(previous.content) !== stringOrEmpty(next.content) || stringOrEmpty(previous.updated_at) !== stringOrEmpty(next.updated_at) || stringOrEmpty(previous.status) !== stringOrEmpty(next.status) || stringOrEmpty(previous.kind) !== stringOrEmpty(next.kind);
            sessionPreview = next;
            if (contentChanged && stringOrEmpty(next.status) === "live") {
                if (sessionPreviewAutoFollow) {
                    sessionPreviewFollowTimer.restart();
                } else {
                    sessionPreviewHasUnseenOutput = true;
                }
            }
        } catch (error) {
            console.warn("session.preview.parse:", raw, error);
        }
    }

    function restartSessionPreview() {
        const entry = activeLauncherSessionEntry();
        if (!launcherVisible || launcherMode !== "sessions" || !entry) {
            clearSessionPreview();
            return;
        }

        const sessionKey = stringOrEmpty(entry.session_key || entry.identifier);
        if (!sessionKey) {
            clearSessionPreview();
            return;
        }

        sessionPreviewTargetKey = sessionKey;
        sessionPreviewAutoFollow = true;
        sessionPreviewHasUnseenOutput = false;
        sessionPreview = Object.assign(emptySessionPreview(), {
            status: "loading",
            kind: "status",
            session_key: sessionKey,
            tool: toolLabel(entry),
            project_name: stringOrEmpty(entry.project_name || entry.project),
            host_name: stringOrEmpty(entry.host_name),
            pane_label: sessionPaneLabel(entry),
            message: "Loading live pane preview..."
        });

        if (sessionPreviewProcess.running) {
            sessionPreviewStopExpected = true;
            sessionPreviewProcess.running = false;
        }
        sessionPreviewProcess.command = [shellConfig.i3pmBin, "session", "preview", sessionKey, "--follow", "--jsonl", "--lines", "100"];
        sessionPreviewProcess.running = true;
    }

    function ensureSessionPreviewForSelection() {
        const entry = activeLauncherSessionEntry();
        if (!launcherVisible || launcherMode !== "sessions" || !entry) {
            clearSessionPreview();
            return;
        }

        const sessionKey = stringOrEmpty(entry.session_key || entry.identifier);
        if (!sessionKey) {
            clearSessionPreview();
            return;
        }

        if (sessionPreviewTargetKey === sessionKey && sessionPreviewProcess.running) {
            return;
        }

        if (sessionPreviewTargetKey === sessionKey && !sessionPreviewProcess.running && stringOrEmpty(sessionPreview.status) === "live") {
            return;
        }

        sessionPreviewDebounce.restart();
    }

    function sessionPreviewTitle() {
        const alias = buildSessionAlias(
            hostMonogram(
                stringOrEmpty(sessionPreview.execution_mode),
                stringOrEmpty(sessionPreview.host_name),
                stringOrEmpty(sessionPreview.connection_key)
            ),
            stringOrEmpty(sessionPreview.tmux_pane)
        );
        if (alias.length > 0) {
            return alias;
        }
        const entry = activeLauncherSessionEntry();
        return entry ? sessionPrimaryLabel(entry) : "Session Preview";
    }

    function sessionPreviewSubtitle() {
        const bits = [];
        const host = stringOrEmpty(sessionPreview.host_name);
        const project = shortProject(stringOrEmpty(sessionPreview.project_name));
        const availability = sessionAvailabilityLabel(sessionPreview);
        if (host) {
            bits.push(displayHostName(host));
        }
        if (project && project !== "Global") {
            bits.push(project);
        }
        if (availability.length > 0 && sessionAvailabilityState(sessionPreview) !== "local_window") {
            bits.push(availability);
        }
        if (stringOrEmpty(sessionPreview.tmux_session)) {
            bits.push(stringOrEmpty(sessionPreview.tmux_session));
        }
        return bits.join("  •  ");
    }

    function sessionPreviewSemanticBits() {
        const bits = [];
        const phase = stringOrEmpty(sessionPreview.session_phase_label || sessionPreview.session_phase);
        const owner = stringOrEmpty(sessionPreview.turn_owner_label || sessionPreview.turn_owner);
        const substate = stringOrEmpty(sessionPreview.activity_substate_label || sessionPreview.activity_substate);
        if (phase) {
            bits.push(phase);
        }
        if (owner) {
            bits.push(owner);
        }
        if (substate) {
            bits.push(substate);
        }
        return bits;
    }

    function sessionPreviewSemanticSummary() {
        return sessionPreviewSemanticBits().join("  •  ");
    }

    function sessionPreviewOwnerChipColor() {
        const owner = stringOrEmpty(sessionPreview.turn_owner).toLowerCase();
        if (owner === "llm") {
            return colors.accent;
        }
        if (owner === "blocked") {
            return colors.orange;
        }
        if (owner === "user") {
            return colors.blue;
        }
        return colors.textDim;
    }

    function sessionPreviewOwnerChipBackground() {
        const owner = stringOrEmpty(sessionPreview.turn_owner).toLowerCase();
        if (owner === "llm") {
            return colors.accentBg;
        }
        if (owner === "blocked") {
            return colors.orangeBg;
        }
        if (owner === "user") {
            return colors.blueBg;
        }
        return colors.panelAlt;
    }

    function sessionPreviewOwnerChipBorder() {
        const owner = stringOrEmpty(sessionPreview.turn_owner).toLowerCase();
        if (owner === "llm") {
            return colors.accent;
        }
        if (owner === "blocked") {
            return colors.orange;
        }
        if (owner === "user") {
            return colors.blue;
        }
        return colors.border;
    }

    function sessionPreviewBody() {
        const content = stringOrEmpty(sessionPreview.content);
        if (content) {
            return content;
        }
        return stringOrEmpty(sessionPreview.message);
    }

    function sessionPreviewBadgeText() {
        if (stringOrEmpty(sessionPreview.status) === "loading") {
            return "Loading";
        }
        if (boolOrFalse(sessionPreview.is_live)) {
            return "Live";
        }
        if (boolOrFalse(sessionPreview.is_remote)) {
            return "Remote";
        }
        if (stringOrEmpty(sessionPreview.status) === "error") {
            return "Error";
        }
        return "Info";
    }

    function sessionPreviewFollowChipVisible() {
        return stringOrEmpty(sessionPreview.status) === "live" && boolOrFalse(sessionPreview.is_live);
    }

    function sessionPreviewFollowChipText() {
        if (sessionPreviewHasUnseenOutput) {
            return "New output";
        }
        return sessionPreviewAutoFollow ? "Following" : "Paused";
    }

    function sessionPreviewFollowChipColor() {
        if (sessionPreviewHasUnseenOutput) {
            return colors.orange;
        }
        return sessionPreviewAutoFollow ? colors.accent : colors.blue;
    }

    function sessionPreviewFollowChipBackground() {
        if (sessionPreviewHasUnseenOutput) {
            return colors.orangeBg;
        }
        return sessionPreviewAutoFollow ? colors.accentBg : colors.blueBg;
    }

    function sessionPreviewScrollToBottom() {
        if (!sessionPreviewFlick) {
            return;
        }
        sessionPreviewProgrammaticScroll = true;
        sessionPreviewFlick.contentY = Math.max(0, sessionPreviewFlick.contentHeight - sessionPreviewFlick.height);
        sessionPreviewProgrammaticScroll = false;
        sessionPreviewHasUnseenOutput = false;
    }

    function resumeSessionPreviewFollow() {
        sessionPreviewAutoFollow = true;
        sessionPreviewHasUnseenOutput = false;
        sessionPreviewFollowTimer.restart();
    }

    function sessionLauncherEntry(session) {
        const parentWindow = findWindowById(Number(session && session.window_id || 0));
        return Object.assign({}, session, {
            kind: "session",
            identifier: stringOrEmpty(session && session.session_key),
            text: sessionPrimaryLabel(session),
            subtext: sessionSecondaryLabel(session),
            badge_label: sessionBadgeLabel(session),
            host_label: sessionHostLabel(session),
            host_token: sessionHostToken(session),
            project_label: shortProject(stringOrEmpty(session && (session.project_name || session.project || "global"))),
            window_title: parentWindow ? stringOrEmpty(displayTitle(parentWindow)) : ""
        });
    }

    function launcherSessionMatches(session, tokens) {
        const parentWindow = findWindowById(Number(session && session.window_id || 0));
        const hostTokenData = sessionHostToken(session);
        return launcherTokensMatch(tokens, [sessionPrimaryLabel(session), sessionSecondaryLabel(session), sessionBadgeLabel(session), compactSessionStateLabel(session), sessionAvailabilityLabel(session), sessionTurnOwnerLabel(session), sessionActivitySubstateLabel(session), toolLabel(session), sessionHostLabel(session), stringOrEmpty(hostTokenData && hostTokenData.label), sessionIdentityLabel(session), sessionPaneLocatorLabel(session), sessionPidLabel(session), stringOrEmpty(session && session.project_name), stringOrEmpty(session && session.project), stringOrEmpty(session && session.stage), stringOrEmpty(session && session.turn_owner), stringOrEmpty(session && session.activity_substate), stringOrEmpty(session && session.last_event_name), stringOrEmpty(session && session.status_reason), parentWindow ? stringOrEmpty(displayTitle(parentWindow)) : ""]);
    }

    function launcherSessionHostSortKey(session) {
        const connectionKey = stringOrEmpty(session && session.connection_key);
        if (connectionKey) {
            return connectionKey;
        }

        const contextKey = stringOrEmpty(session && session.context_key);
        if (contextKey) {
            return contextKey;
        }

        const terminalAnchor = stringOrEmpty(session && session.terminal_anchor_id);
        if (terminalAnchor) {
            return terminalAnchor;
        }

        return stringOrEmpty(session && session.host_name);
    }

    function launcherSessionCompare(left, right) {
        let result = compareAscending(launcherSessionHostSortKey(left), launcherSessionHostSortKey(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.project_name || left && left.project), stringOrEmpty(right && right.project_name || right && right.project));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.tmux_session), stringOrEmpty(right && right.tmux_session));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionWindowSlot(left), sessionWindowSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(sessionPaneSlot(left), sessionPaneSlot(right));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.tool), stringOrEmpty(right && right.tool));
        if (result !== 0) {
            return result;
        }

        return compareAscending(sessionIdentityKey(left), sessionIdentityKey(right));
    }

    function launcherSessionGroups(query) {
        const tokens = launcherQueryTokens(query);
        const groups = groupedSessionBands();
        if (!tokens.length) {
            return groups;
        }

        const filteredGroups = [];
        for (let i = 0; i < groups.length; i += 1) {
            const group = groups[i];
            const nextGroup = Object.assign({}, group, {
                sessions: [],
                project_groups: []
            });
            const projectGroups = arrayOrEmpty(group && group.project_groups);
            for (let j = 0; j < projectGroups.length; j += 1) {
                const projectGroup = projectGroups[j];
                const matchedSessions = arrayOrEmpty(projectGroup && projectGroup.sessions).filter(function (session) {
                    return launcherSessionMatches(session, tokens);
                });
                if (!matchedSessions.length) {
                    continue;
                }
                nextGroup.project_groups.push(Object.assign({}, projectGroup, {
                    sessions: matchedSessions
                }));
                nextGroup.sessions = nextGroup.sessions.concat(matchedSessions);
            }
            if (nextGroup.project_groups.length) {
                filteredGroups.push(nextGroup);
            }
        }
        return filteredGroups;
    }

    function launcherSessionEntries(query) {
        const tokens = launcherQueryTokens(query);
        const sessions = activeSessions().filter(function(session) {
            return sessionIsDisplayEligible(session) && launcherSessionMatches(session, tokens);
        }).slice();
        sessions.sort((left, right) => launcherSessionCompare(left, right));

        const entries = [];
        for (let i = 0; i < sessions.length; i += 1) {
            entries.push(sessionLauncherEntry(sessions[i]));
        }
        return entries;
    }

    function launcherSessionSwitcherEntries() {
        const entries = [];
        const sessions = arrayOrEmpty(sessionMru()).filter(session => sessionIsDisplayEligible(session));
        for (let i = 0; i < sessions.length; i += 1) {
            entries.push(sessionLauncherEntry(sessions[i]));
        }
        return entries;
    }

    function launcherWindowMatches(windowData, tokens) {
        const sessions = arrayOrEmpty(windowData && windowData.sessions);
        const sessionBits = [];
        for (let i = 0; i < sessions.length; i += 1) {
            sessionBits.push(sessionPrimaryLabel(sessions[i]));
            sessionBits.push(toolLabel(sessions[i]));
            sessionBits.push(sessionHostLabel(sessions[i]));
        }

        const hostTokenData = windowHostToken(windowData);
        return launcherTokensMatch(tokens, [displayTitle(windowData), displayMeta(windowData), appLabel(windowData), stringOrEmpty(windowData && windowData.project), stringOrEmpty(windowData && windowData.workspace), stringOrEmpty(windowData && windowData.output), stringOrEmpty(windowData && windowData.execution_mode), stringOrEmpty(hostTokenData && hostTokenData.label), sessionBits.join(" ")]);
    }

    function launcherWindowProjects(query) {
        const tokens = launcherQueryTokens(query);
        const projects = panelProjects();
        if (!tokens.length) {
            return projects;
        }

        const filteredProjects = [];
        for (let i = 0; i < projects.length; i += 1) {
            const projectGroup = projects[i];
            const matchedWindows = arrayOrEmpty(projectGroup && projectGroup.windows).filter(function (windowData) {
                return launcherWindowMatches(windowData, tokens);
            });
            if (!matchedWindows.length) {
                continue;
            }
            filteredProjects.push(Object.assign({}, projectGroup, {
                windows: matchedWindows
            }));
        }
        return filteredProjects;
    }

    function launcherWindowEntries(query) {
        const entries = [];
        const projects = launcherWindowProjects(query);
        for (let i = 0; i < projects.length; i += 1) {
            const windows = arrayOrEmpty(projects[i] && projects[i].windows);
            for (let j = 0; j < windows.length; j += 1) {
                entries.push(Object.assign({}, windows[j], {
                    kind: "window",
                    identifier: String(Number(windows[j] && (windows[j].id || windows[j].window_id) || 0)),
                    text: displayTitle(windows[j]),
                    subtext: displayMeta(windows[j]),
                    host_token: windowHostToken(windows[j])
                }));
            }
        }
        return entries;
    }

    function launcherEntryIdentity(entry) {
        const kind = stringOrEmpty(entry && entry.kind);
        if (kind === "session") {
            return "session::" + stringOrEmpty(entry && entry.session_key);
        }
        if (kind === "window") {
            return "window::" + String(Number(entry && (entry.id || entry.window_id) || 0));
        }
        const identityValue = stringOrEmpty(entry && (entry.identifier || entry.qualified_name || entry.text || entry.subtext));
        if (!identityValue) {
            return "";
        }
        if (!kind) {
            return "app::" + identityValue;
        }
        return kind + "::" + identityValue;
    }

    function launcherEntryModelKey(entry, indexHint) {
        const identity = launcherEntryIdentity(entry);
        if (identity) {
            return identity;
        }

        const numericIndex = Number(indexHint || 0);
        const safeIndex = isNaN(numericIndex) ? 0 : Math.max(0, Math.floor(numericIndex));
        return "launcher::" + String(safeIndex);
    }

    function normalizeLauncherEntries(entries) {
        const sourceEntries = arrayOrEmpty(entries);
        const normalized = [];
        for (let i = 0; i < sourceEntries.length; i += 1) {
            const entry = sourceEntries[i];
            if (!entry || typeof entry !== "object") {
                continue;
            }
            normalized.push(Object.assign({}, entry, {
                model_key: launcherEntryModelKey(entry, i)
            }));
        }
        return normalized;
    }

    function orderedLauncherSessionEntries(entries) {
        const nextEntries = arrayOrEmpty(entries);
        if (launcherMode !== "sessions") {
            return nextEntries;
        }

        const previousOrder = arrayOrEmpty(launcherSessionEntryOrder);
        if (!previousOrder.length) {
            launcherSessionEntryOrder = nextEntries.map(function(entry) {
                return launcherEntryIdentity(entry);
            }).filter(function(identity) {
                return identity.length > 0;
            });
            return nextEntries;
        }

        const remainingByIdentity = {};
        for (let i = 0; i < nextEntries.length; i += 1) {
            const entry = nextEntries[i];
            const identity = launcherEntryIdentity(entry);
            if (!identity) {
                continue;
            }
            remainingByIdentity[identity] = entry;
        }

        const ordered = [];
        const seen = {};
        for (let i = 0; i < previousOrder.length; i += 1) {
            const identity = previousOrder[i];
            if (!identity || !remainingByIdentity[identity]) {
                continue;
            }
            ordered.push(remainingByIdentity[identity]);
            seen[identity] = true;
        }

        for (let i = 0; i < nextEntries.length; i += 1) {
            const entry = nextEntries[i];
            const identity = launcherEntryIdentity(entry);
            if (identity && seen[identity]) {
                continue;
            }
            ordered.push(entry);
            if (identity) {
                seen[identity] = true;
            }
        }

        launcherSessionEntryOrder = ordered.map(function(entry) {
            return launcherEntryIdentity(entry);
        }).filter(function(identity) {
            return identity.length > 0;
        });

        return ordered;
    }

    function setLauncherEntries(entries) {
        const nextEntries = normalizeLauncherEntries(orderedLauncherSessionEntries(entries));
        const previousIdentity = launcherEntryIdentity(activeLauncherEntry());
        launcherEntries = nextEntries;

        if (!nextEntries.length) {
            launcherSelectedIndex = 0;
            resetLauncherListViewport();
            if (launcherMode === "sessions") {
                clearSessionPreview();
            }
            return;
        }

        if (previousIdentity) {
            const previousIndex = nextEntries.findIndex(function (candidate) {
                return launcherEntryIdentity(candidate) === previousIdentity;
            });
            if (previousIndex >= 0) {
                launcherSelectedIndex = previousIndex;
                syncLauncherListSelection();
                if (launcherMode === "sessions") {
                    ensureSessionPreviewForSelection();
                }
                return;
            }
        }

        launcherSelectedIndex = Math.max(0, Math.min(launcherSelectedIndex, nextEntries.length - 1));
        syncLauncherListSelection();
        if (launcherMode === "sessions") {
            ensureSessionPreviewForSelection();
        }
    }

    function normalizeSettingsSection(section) {
        const normalized = stringOrEmpty(section).toLowerCase();
        if (normalized === "devices") {
            return "devices";
        }
        return "commands";
    }

    function setSettingsSection(section) {
        settingsSection = normalizeSettingsSection(section);
    }

    function openSettings(section) {
        setSettingsSection(section);
        audioPopupVisible = false;
        bluetoothPopupVisible = false;
        settingsVisible = true;
    }

    function closeSettings() {
        settingsVisible = false;
    }

    function activeSettingsCommandEntry() {
        const entries = arrayOrEmpty(settingsCommandEntries);
        if (!entries.length) {
            return null;
        }
        if (settingsCommandSelectedIndex < 0 || settingsCommandSelectedIndex >= entries.length) {
            return entries[0];
        }
        return entries[settingsCommandSelectedIndex];
    }

    function setSettingsCommandEntries(entries) {
        const nextEntries = arrayOrEmpty(entries);
        const previousIdentity = launcherEntryIdentity(activeSettingsCommandEntry());
        settingsCommandEntries = nextEntries;

        if (!nextEntries.length) {
            settingsCommandSelectedIndex = 0;
            return;
        }

        if (snippetEditorSelectionHint >= 0) {
            settingsCommandSelectedIndex = Math.max(0, Math.min(snippetEditorSelectionHint, nextEntries.length - 1));
            snippetEditorSelectionHint = -1;
            return;
        }

        if (previousIdentity) {
            const previousIndex = nextEntries.findIndex(function (candidate) {
                return launcherEntryIdentity(candidate) === previousIdentity;
            });
            if (previousIndex >= 0) {
                settingsCommandSelectedIndex = previousIndex;
                return;
            }
        }

        settingsCommandSelectedIndex = Math.max(0, Math.min(settingsCommandSelectedIndex, nextEntries.length - 1));
    }

    function resetSnippetEditor() {
        snippetEditorSyncing = true;
        snippetEditorBusy = false;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorIndex = -1;
        snippetEditorSelectionHint = -1;
        snippetEditorNewDraft = false;
        snippetEditorDirty = false;
        snippetEditorLoadedIdentity = "";
        snippetEditorName = "";
        snippetEditorCommand = "";
        snippetEditorDescription = "";
        snippetEditorSyncing = false;
    }

    function activeSnippetEntry() {
        const entry = activeSettingsCommandEntry();
        if (stringOrEmpty(entry && entry.kind) !== "snippet") {
            return null;
        }
        return entry;
    }

    function snippetEditorTitle() {
        return snippetEditorNewDraft ? "New Command" : "Edit Command";
    }

    function snippetEditorStatus() {
        if (snippetEditorError) {
            return snippetEditorError;
        }
        if (snippetEditorBusy) {
            return "Saving curated command";
        }
        if (snippetEditorMessage) {
            return snippetEditorMessage;
        }
        if (snippetEditorDirty) {
            return "Unsaved changes";
        }
        if (snippetEditorNewDraft) {
            return "Create a curated command saved to Elephant snippets";
        }
        return "Selected command is stored in Elephant snippets";
    }

    function snippetEditorCanSave() {
        return stringOrEmpty(snippetEditorName).trim().length > 0 && stringOrEmpty(snippetEditorCommand).trim().length > 0 && !snippetEditorBusy;
    }

    function startSnippetDraft() {
        snippetEditorSyncing = true;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorIndex = -1;
        snippetEditorSelectionHint = -1;
        snippetEditorNewDraft = true;
        snippetEditorDirty = false;
        snippetEditorLoadedIdentity = "";
        snippetEditorName = stringOrEmpty(snippetEditorName).trim() ? snippetEditorName : stringOrEmpty(settingsCommandQuery).trim();
        snippetEditorCommand = stringOrEmpty(snippetEditorCommand).trim() ? snippetEditorCommand : "";
        snippetEditorDescription = stringOrEmpty(snippetEditorDescription).trim() ? snippetEditorDescription : "";
        snippetEditorSyncing = false;
    }

    function loadSnippetEditor(entry) {
        if (stringOrEmpty(entry && entry.kind) !== "snippet") {
            startSnippetDraft();
            return;
        }
        snippetEditorSyncing = true;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorIndex = Number(entry && entry.index);
        snippetEditorSelectionHint = snippetEditorIndex;
        snippetEditorNewDraft = false;
        snippetEditorDirty = false;
        snippetEditorLoadedIdentity = launcherEntryIdentity(entry);
        snippetEditorName = stringOrEmpty(entry && entry.text);
        snippetEditorCommand = stringOrEmpty(entry && entry.command);
        snippetEditorDescription = stringOrEmpty(entry && entry.description);
        snippetEditorSyncing = false;
    }

    function syncSnippetEditorFromSelection() {
        if (!settingsVisible || settingsSection !== "commands" || snippetEditorBusy) {
            return;
        }
        const entry = activeSnippetEntry();
        if (!entry) {
            if (!snippetEditorNewDraft || (!settingsCommandEntries.length && !stringOrEmpty(snippetEditorName).trim() && !stringOrEmpty(snippetEditorCommand).trim())) {
                startSnippetDraft();
            }
            return;
        }
        const identity = launcherEntryIdentity(entry);
        if (!snippetEditorNewDraft && snippetEditorLoadedIdentity === identity && snippetEditorIndex === Number(entry && entry.index)) {
            return;
        }
        loadSnippetEditor(entry);
    }

    function beginNewSnippetFromQuery() {
        snippetEditorSyncing = true;
        snippetEditorName = stringOrEmpty(settingsCommandQuery).trim();
        snippetEditorCommand = "";
        snippetEditorDescription = "";
        snippetEditorSyncing = false;
        startSnippetDraft();
    }

    function submitSnippetMutation(command) {
        if (snippetEditorProcess.running) {
            snippetEditorProcess.running = false;
        }
        snippetEditorBusy = true;
        snippetEditorError = "";
        snippetEditorMessage = "";
        snippetEditorProcess.command = command;
        snippetEditorProcess.running = true;
    }

    function saveSnippetEditor() {
        if (!snippetEditorCanSave()) {
            snippetEditorError = "Command name and command text are required";
            return;
        }
        submitSnippetMutation([shellConfig.snippetsManageBin, "upsert", String(snippetEditorNewDraft ? -1 : snippetEditorIndex), stringOrEmpty(snippetEditorName).trim(), stringOrEmpty(snippetEditorCommand).trim(), stringOrEmpty(snippetEditorDescription).trim()]);
    }

    function removeSnippetEditorEntry() {
        if (snippetEditorBusy || snippetEditorNewDraft || snippetEditorIndex < 0) {
            return;
        }
        submitSnippetMutation([shellConfig.snippetsManageBin, "remove", String(snippetEditorIndex)]);
    }

    function moveSnippetEditorEntry(direction) {
        if (snippetEditorBusy || snippetEditorNewDraft || snippetEditorIndex < 0) {
            return;
        }
        submitSnippetMutation([shellConfig.snippetsManageBin, "move", String(snippetEditorIndex), direction]);
    }

    function handleSnippetMutationResult(data) {
        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            snippetEditorBusy = false;
            return;
        }
        try {
            const parsed = JSON.parse(raw);
            snippetEditorBusy = false;
            snippetEditorError = "";
            snippetEditorMessage = stringOrEmpty(parsed && parsed.message);
            if (parsed && parsed.index !== undefined && parsed.index !== null) {
                snippetEditorSelectionHint = Number(parsed.index);
            }
            if (stringOrEmpty(parsed && parsed.action) === "remove") {
                snippetEditorLoadedIdentity = "";
                snippetEditorNewDraft = false;
            }
            settingsCommandQueryDebounce.restart();
            if (launcherVisible && launcherMode === "snippets") {
                launcherQueryDebounce.restart();
            }
        } catch (error) {
            snippetEditorBusy = false;
            snippetEditorError = "Unable to update curated commands";
            console.warn("settings.commands.mutation:", raw, error);
        }
    }

    function settingsTitle() {
        return settingsSection === "devices" ? "Devices" : "Settings";
    }

    function settingsCommandStatusText() {
        if (settingsCommandError) {
            return settingsCommandError;
        }
        if (settingsCommandLoading) {
            return "Loading commands";
        }
        if (settingsCommandEntries.length) {
            return settingsCommandEntries.length + " command" + (settingsCommandEntries.length === 1 ? "" : "s");
        }
        return "No commands match the current query";
    }

    function settingsCommandEmptyText() {
        if (settingsCommandError) {
            return settingsCommandError;
        }
        return settingsCommandQuery.trim().length ? "No commands match the current query" : "No commands yet. Create one from the editor.";
    }

    function moveSettingsCommandSelection(delta) {
        const entries = arrayOrEmpty(settingsCommandEntries);
        if (!entries.length) {
            settingsCommandSelectedIndex = 0;
            return;
        }
        settingsCommandSelectedIndex = (settingsCommandSelectedIndex + delta + entries.length) % entries.length;
    }

    function restartSettingsCommandQuery() {
        if (!settingsVisible || settingsSection !== "commands") {
            return;
        }

        settingsCommandError = "";

        if (settingsCommandQueryProcess.running) {
            settingsCommandQueryProcess.running = false;
        }

        settingsCommandLoading = true;
        settingsCommandQueryProcess.command = [shellConfig.snippetsListBin, settingsCommandQuery, "200"];
        settingsCommandQueryProcess.running = true;
    }

    function parseSettingsCommandResults(data) {
        if (!settingsVisible || settingsSection !== "commands") {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setSettingsCommandEntries([]);
            settingsCommandLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setSettingsCommandEntries(Array.isArray(parsed) ? parsed : []);
            if (!settingsCommandEntries.length && !snippetEditorBusy) {
                startSnippetDraft();
            }
            settingsCommandLoading = false;
            settingsCommandError = "";
        } catch (error) {
            setSettingsCommandEntries([]);
            settingsCommandLoading = false;
            settingsCommandError = "Unable to load commands";
            console.warn("settings.commands.parse:", raw, error);
        }
    }

    function projectLauncherEntries(query) {
        const entries = [];
        const worktrees = dashboardWorktrees();

        if (!isGlobalContext()) {
            entries.push({
                kind: "global",
                identifier: "__clear__",
                text: "Clear Project Context",
                subtext: "Return to global context",
                qualified_name: "global",
                variant: "clear",
                is_active: false,
                active_execution_mode: "",
                remote_available: false,
                repo_display: "",
                repo_name: "",
                account: "",
                branch: "",
                path: "",
                is_main: false,
                is_clean: true,
                is_stale: false,
                has_conflicts: false,
                ahead: 0,
                behind: 0,
                dirty_count: 0,
                visible_window_count: 0,
                scoped_window_count: 0,
                last_used_at: 0,
                use_count: 0
            });
        }

        for (let i = 0; i < worktrees.length; i += 1) {
            const worktree = worktrees[i];
            if (!worktree) {
                continue;
            }

            const baseItem = {
                kind: "project",
                qualified_name: stringOrEmpty(worktree.qualified_name),
                repo_display: stringOrEmpty(worktree.repo_display),
                repo_name: stringOrEmpty(worktree.repo_name),
                account: stringOrEmpty(worktree.account),
                branch: stringOrEmpty(worktree.branch),
                path: stringOrEmpty(worktree.path),
                is_main: boolOrFalse(worktree.is_main),
                is_clean: boolOrFalse(worktree.is_clean),
                is_stale: boolOrFalse(worktree.is_stale),
                has_conflicts: boolOrFalse(worktree.has_conflicts),
                ahead: Number(worktree.ahead || 0),
                behind: Number(worktree.behind || 0),
                dirty_count: Number(worktree.dirty_count || 0),
                active_execution_mode: stringOrEmpty(worktree.active_execution_mode),
                remote_available: boolOrFalse(worktree.remote_available),
                visible_window_count: Number(worktree.visible_window_count || 0),
                scoped_window_count: Number(worktree.scoped_window_count || 0),
                last_used_at: Number(worktree.last_used_at || 0),
                use_count: Number(worktree.use_count || 0),
                last_commit_message: stringOrEmpty(worktree.last_commit_message)
            };

            const variants = baseItem.remote_available ? ((boolOrFalse(worktree.is_active) && baseItem.active_execution_mode === "ssh") ? ["ssh", "local"] : ["local", "ssh"]) : ["local"];

            for (let j = 0; j < variants.length; j += 1) {
                const variant = variants[j];
                const entry = {
                    kind: "project",
                    identifier: baseItem.qualified_name + "::" + variant,
                    text: shortProject(baseItem.qualified_name),
                    subtext: "",
                    variant: variant,
                    is_active: boolOrFalse(worktree.is_active) && baseItem.active_execution_mode === variant
                };
                Object.assign(entry, baseItem);
                entry.subtext = launcherProjectSubtitle(entry);
                entries.push(entry);
            }
        }

        return entries.filter(function (entry) {
            return launcherProjectMatches(entry, query);
        });
    }

    function panelWindowItems() {
        const items = [];
        const projects = arrayOrEmpty(dashboard.projects);

        const addGroup = function (sectionTitle, projectGroup, emphasize) {
            if (!projectGroup) {
                return;
            }

            const windows = arrayOrEmpty(projectGroup.windows);
            if (!windows.length) {
                return;
            }

            items.push({
                kind: "section",
                title: sectionTitle,
                project: stringOrEmpty(projectGroup.project),
                execution_mode: stringOrEmpty(projectGroup.execution_mode),
                focused: !!projectGroup.focused,
                window_count: Number(projectGroup.window_count || windows.length),
                visible_window_count: Number(projectGroup.visible_window_count || 0),
                hidden_window_count: Number(projectGroup.hidden_window_count || 0),
                ai_session_count: Number(projectGroup.ai_session_count || 0),
                emphasized: !!emphasize
            });

            for (let j = 0; j < windows.length; j += 1) {
                const windowData = windows[j];
                items.push({
                    kind: "window",
                    id: windowData.id,
                    title: windowData.title,
                    app_key: windowData.app_key,
                    app_name: windowData.app_name,
                    icon_path: windowData.icon_path,
                    project: windowData.project,
                    execution_mode: windowData.execution_mode,
                    connection_key: windowData.connection_key,
                    workspace: windowData.workspace,
                    output: windowData.output,
                    focused: !!windowData.focused,
                    visible: !!windowData.visible,
                    hidden: !!windowData.hidden,
                    floating: !!windowData.floating,
                    scope: windowData.scope,
                    sessions: arrayOrEmpty(windowData.sessions),
                    ai_session_count: Number(windowData.ai_session_count || 0)
                });
            }

            items.push({
                kind: "spacer"
            });
        };

        for (let i = 0; i < projects.length; i += 1) {
            const projectGroup = projects[i];
            if (!projectGroup) {
                continue;
            }
            const project = stringOrEmpty(projectGroup.project);
            addGroup(project === "global" ? "Shared Windows" : shortProject(project), projectGroup, !!projectGroup.is_active);
        }

        if (!items.length) {
            items.push({
                kind: "empty",
                title: "No tracked project windows"
            });
        } else if (items[items.length - 1].kind === "spacer") {
            items.pop();
        }

        return items;
    }

    function panelProjects() {
        const projects = arrayOrEmpty(dashboard.projects);
        const visibleProjects = [];
        for (let i = 0; i < projects.length; i += 1) {
            const projectGroup = projects[i];
            const windows = arrayOrEmpty(projectGroup && projectGroup.windows).filter(function(windowData) {
                return !windowIsCurrentTarget(windowData);
            });
            if (!windows.length) {
                continue;
            }
            visibleProjects.push(Object.assign({}, projectGroup, {
                windows: windows
            }));
        }
        return visibleProjects;
    }

    function panelWindowCount() {
        let count = 0;
        const projects = panelProjects();
        for (let i = 0; i < projects.length; i += 1) {
            count += arrayOrEmpty(projects[i].windows).length;
        }
        return count;
    }

    function runtimePanelDefaultExpandedSection() {
        if (panelSessions().length > 0) {
            return "sessions";
        }
        if (panelProjects().length > 0) {
            return "windows";
        }
        return "";
    }

    function runtimePanelExpandedSectionValue() {
        const requested = stringOrEmpty(runtimePanelExpandedSection);
        const hasSessions = panelSessions().length > 0;
        const hasWindows = panelProjects().length > 0;

        if (requested === "balanced" && hasSessions && hasWindows) {
            return "balanced";
        }
        if (requested === "sessions" && hasSessions) {
            return "sessions";
        }
        if (requested === "windows" && hasWindows) {
            return "windows";
        }
        return runtimePanelDefaultExpandedSection();
    }

    function runtimePanelSectionHasContent(section) {
        if (section === "sessions") {
            return panelSessions().length > 0;
        }
        if (section === "windows") {
            return panelProjects().length > 0;
        }
        return false;
    }

    function runtimePanelSectionExpanded(section) {
        if (!runtimePanelSectionHasContent(section)) {
            return false;
        }

        const activeSection = runtimePanelExpandedSectionValue();
        if (activeSection === "balanced") {
            return true;
        }
        return activeSection === section;
    }

    function runtimePanelSectionCollapsed(section) {
        if (!runtimePanelSectionHasContent(section)) {
            return false;
        }

        const activeSection = runtimePanelExpandedSectionValue();
        return activeSection.length > 0 && activeSection !== "balanced" && activeSection !== section;
    }

    function runtimePanelSectionCount(section) {
        if (section === "sessions") {
            return panelSessions().length;
        }
        if (section === "windows") {
            return panelWindowCount();
        }
        return 0;
    }

    function runtimePanelSectionSummary(section) {
        if (section === "sessions") {
            const hostCount = groupedSessionBands().length;
            const sessionCount = panelSessions().length;
            const bits = [];
            if (hostCount > 0) {
                bits.push(String(hostCount) + (hostCount === 1 ? " host" : " hosts"));
            }
            if (sessionCount > 0) {
                bits.push(String(sessionCount) + (sessionCount === 1 ? " session" : " sessions"));
            }
            return bits.join(" • ");
        }

        if (section === "windows") {
            const projectCount = panelProjects().length;
            const windowCount = panelWindowCount();
            const bits = [];
            if (projectCount > 0) {
                bits.push(String(projectCount) + (projectCount === 1 ? " project" : " projects"));
            }
            if (windowCount > 0) {
                bits.push(String(windowCount) + (windowCount === 1 ? " window" : " windows"));
            }
            return bits.join(" • ");
        }

        return "";
    }

    function runtimePanelSectionPreferredHeight(section) {
        if (!runtimePanelSectionHasContent(section)) {
            return 0;
        }

        const activeSection = runtimePanelExpandedSectionValue();
        if (activeSection === "balanced") {
            return section === "sessions" ? 320 : 220;
        }
        if (activeSection === section) {
            return section === "sessions" ? 360 : 320;
        }
        return 60;
    }

    function toggleRuntimePanelSection(section) {
        if (!runtimePanelSectionHasContent(section)) {
            return;
        }

        const activeSection = runtimePanelExpandedSectionValue();
        if (activeSection === section && runtimePanelSectionHasContent("sessions") && runtimePanelSectionHasContent("windows")) {
            runtimePanelExpandedSection = "balanced";
            return;
        }

        runtimePanelExpandedSection = section;
    }

    function ensureRuntimePanelExpandedSection() {
        runtimePanelExpandedSection = runtimePanelExpandedSectionValue();
    }

    function showRuntimePanelSection(section) {
        const requested = stringOrEmpty(section);
        showRuntimePanel();
        if (requested === "balanced") {
            runtimePanelExpandedSection = runtimePanelDefaultExpandedSection();
            if (runtimePanelSectionHasContent("sessions") && runtimePanelSectionHasContent("windows")) {
                runtimePanelExpandedSection = "balanced";
            }
            return;
        }
        if (runtimePanelSectionHasContent(requested)) {
            runtimePanelExpandedSection = requested;
            return;
        }
        ensureRuntimePanelExpandedSection();
    }

    function togglePanelVisibility() {
        if (panelVisible) {
            panelVisible = false;
            return;
        }
        if (panelSection === "assistant") {
            showAssistantPanel();
            return;
        }
        showRuntimePanel();
    }

    function currentSessionKey() {
        return stringOrEmpty(dashboard.current_ai_session_key);
    }

    function windowSectionSubtitle(item) {
        if (!item) {
            return "";
        }

        if (stringOrEmpty(item.project) === "global") {
            return "Shared across contexts";
        }

        const visibleCount = Number(item.visible_window_count || 0);
        const sessionCount = Number(item.ai_session_count || 0);
        const bits = [];
        bits.push(String(visibleCount) + (visibleCount === 1 ? " window" : " windows"));
        if (sessionCount > 0) {
            bits.push(String(sessionCount) + (sessionCount === 1 ? " session" : " sessions"));
        }
        return bits.join(" • ");
    }

    function worktreeDisplayName(item) {
        if (!item || stringOrEmpty(item.kind) === "global") {
            return "Global";
        }
        return shortProject(stringOrEmpty(item.qualified_name));
    }

    function worktreeSubtitle(item) {
        if (!item) {
            return "";
        }
        if (stringOrEmpty(item.kind) === "global") {
            return "Clear context and keep shared windows visible";
        }

        const bits = [];
        const branch = stringOrEmpty(item.branch);
        if (branch) {
            bits.push(branch);
        }
        if (Number(item.dirty_count || 0) > 0) {
            bits.push(String(Number(item.dirty_count || 0)) + " changed");
        }
        if (Number(item.ahead || 0) > 0) {
            bits.push("↑" + String(Number(item.ahead || 0)));
        }
        if (Number(item.behind || 0) > 0) {
            bits.push("↓" + String(Number(item.behind || 0)));
        }
        if (Number(item.visible_window_count || 0) > 0) {
            bits.push(String(Number(item.visible_window_count || 0)) + " visible");
        } else if (Number(item.scoped_window_count || 0) > 0) {
            bits.push(String(Number(item.scoped_window_count || 0)) + " scoped");
        }
        if (boolOrFalse(item.remote_available)) {
            bits.push("SSH ready");
        }
        return bits.join("  •  ");
    }

    function worktreeStatusLabel(item) {
        if (!item || stringOrEmpty(item.kind) === "global") {
            return "";
        }
        if (boolOrFalse(item.has_conflicts)) {
            return "Conflict";
        }
        if (!boolOrFalse(item.is_clean)) {
            return "Dirty";
        }
        if (boolOrFalse(item.is_stale)) {
            return "Stale";
        }
        return "Clean";
    }

    function worktreeStatusColor(item) {
        if (!item || stringOrEmpty(item.kind) === "global") {
            return colors.subtle;
        }
        if (boolOrFalse(item.has_conflicts)) {
            return colors.red;
        }
        if (!boolOrFalse(item.is_clean)) {
            return colors.amber;
        }
        if (boolOrFalse(item.is_stale)) {
            return colors.blue;
        }
        return colors.accent;
    }

    function stageColor(session) {
        const tool = stringOrEmpty(session.tool).toLowerCase();
        if (tool === "codex") {
            return colors.accent;
        }
        if (tool === "claude-code" || tool === "claude") {
            return colors.blue;
        }
        if (tool === "gemini") {
            return colors.amber;
        }
        return colors.violet;
    }

    function stageBackground(session) {
        const tool = stringOrEmpty(session.tool).toLowerCase();
        if (tool === "codex") {
            return colors.accentBg;
        }
        if (tool === "claude-code" || tool === "claude") {
            return colors.blueBg;
        }
        if (tool === "gemini") {
            return colors.amberBg;
        }
        return colors.violetBg;
    }

    function toolIconSource(session) {
        const tool = stringOrEmpty(session.tool).toLowerCase();
        if (tool === "codex") {
            return "file://" + shellConfig.codexIcon;
        }
        if (tool === "claude-code" || tool === "claude") {
            return "file://" + shellConfig.claudeIcon;
        }
        if (tool === "gemini") {
            return "file://" + shellConfig.geminiIcon;
        }
        return "file://" + shellConfig.aiFallbackIcon;
    }

    function modeAccentColor(mode) {
        return stringOrEmpty(mode).toLowerCase() === "ssh" ? colors.teal : colors.blueMuted;
    }

    function modeChipLabel(mode) {
        const value = stringOrEmpty(mode).toLowerCase();
        if (value === "ssh") {
            return "SSH";
        }
        if (value === "local") {
            return "Local";
        }
        return value ? value.toUpperCase() : "";
    }

    function modeSortRank(mode) {
        const value = stringOrEmpty(mode).toLowerCase();
        if (value === "local") {
            return 0;
        }
        if (value === "ssh") {
            return 1;
        }
        return 2;
    }

    function sessionProjectBadgeFill(projectGroup) {
        const project = stringOrEmpty(projectGroup && projectGroup.project_name);
        return project && project === activeContextProjectName() ? colors.blueBg : colors.cardAlt;
    }

    function sessionProjectBadgeText(projectGroup) {
        const project = stringOrEmpty(projectGroup && projectGroup.project_name);
        return project && project === activeContextProjectName() ? colors.text : colors.textDim;
    }

    function sessionGroupFill(group) {
        if (boolOrFalse(group && group.is_current_host)) {
            return colors.panelAlt;
        }
        return colors.cardAlt;
    }

    function sessionGroupHeaderFill(group, hovered, expanded) {
        if (boolOrFalse(group && group.is_current_host)) {
            return expanded ? colors.blueWash : "#13202d";
        }
        return hovered ? colors.card : (expanded ? colors.card : colors.bg);
    }

    function sessionGroupHeaderTextColor(group) {
        return boolOrFalse(group && group.is_current_host) ? colors.text : colors.textDim;
    }

    function sessionGroupChevronColor(group) {
        return boolOrFalse(group && group.is_current_host) ? colors.blue : colors.subtle;
    }

    function sessionGroupMetaLabel(group) {
        const projectCount = arrayOrEmpty(group && group.project_groups).length;
        if (projectCount <= 0) {
            return "";
        }
        return String(projectCount) + (projectCount === 1 ? " repo" : " repos");
    }

    function titleCaseWord(value) {
        const text = stringOrEmpty(value).trim();
        if (!text.length) {
            return "";
        }
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    function displayHostName(value) {
        const host = stringOrEmpty(value).trim().toLowerCase();
        if (!host.length) {
            return "";
        }

        const pieces = host.split(/[^a-z0-9]+/).filter(part => part.length > 0);
        if (!pieces.length) {
            return titleCaseWord(host);
        }
        return pieces.map(part => titleCaseWord(part)).join(" ");
    }

    function hostNameFromConnectionKey(value) {
        let key = stringOrEmpty(value).trim();
        if (!key.length) {
            return "";
        }

        const atIndex = key.lastIndexOf("@");
        if (atIndex >= 0 && atIndex < key.length - 1) {
            key = key.slice(atIndex + 1);
        }

        const slashIndex = key.indexOf("/");
        if (slashIndex > 0) {
            key = key.slice(0, slashIndex);
        }

        const colonIndex = key.lastIndexOf(":");
        if (colonIndex > 0 && /^[0-9]+$/.test(key.slice(colonIndex + 1))) {
            key = key.slice(0, colonIndex);
        }

        return displayHostName(key);
    }

    function localHostDisplayName() {
        return displayHostName(shellConfig.hostName) || "Local";
    }

    function resolveThemeIcon(candidates) {
        for (let i = 0; i < candidates.length; i += 1) {
            const candidate = stringOrEmpty(candidates[i]);
            if (!candidate.length) {
                continue;
            }
            const resolved = Quickshell.iconPath(candidate, true);
            if (resolved) {
                return resolved;
            }
        }
        return "";
    }

    function hostToken(mode, hostName, connectionKey) {
        const normalizedMode = stringOrEmpty(mode).toLowerCase() === "ssh" ? "ssh" : "local";
        const isRemote = normalizedMode === "ssh";
        const label = displayHostName(hostName) || hostNameFromConnectionKey(connectionKey) || (isRemote ? "Remote" : localHostDisplayName());
        const icon = isRemote ? ("file://" + shellConfig.tailscaleIcon) : resolveThemeIcon(["computer-symbolic", "computer-laptop-symbolic", "video-display-symbolic", "desktop-symbolic"]);

        return {
            label: label,
            icon: icon,
            is_remote: isRemote,
            foreground: isRemote ? colors.orange : colors.blue,
            background: isRemote ? colors.orangeBg : colors.blueWash,
            border: isRemote ? colors.orange : colors.blueMuted,
            monogram: label.length ? label.charAt(0).toUpperCase() : (isRemote ? "R" : "L")
        };
    }

    function sessionHostToken(session) {
        return hostToken(stringOrEmpty(session && session.execution_mode), stringOrEmpty(session && session.host_name), stringOrEmpty(session && session.connection_key));
    }

    function sessionHostGroupKey(session) {
        const token = sessionHostToken(session);
        const label = stringOrEmpty(token && token.label).trim().toLowerCase();
        if (label.length > 0) {
            return label;
        }

        const hostName = stringOrEmpty(session && session.host_name).trim().toLowerCase();
        if (hostName.length > 0) {
            return hostName;
        }

        const mode = stringOrEmpty(session && session.execution_mode).toLowerCase() === "ssh" ? "remote" : localHostDisplayName().trim().toLowerCase();
        return mode || "unknown";
    }

    function windowHostToken(windowData) {
        const sessions = arrayOrEmpty(windowData && windowData.sessions);
        let preferredSession = null;
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            if (!preferredSession) {
                preferredSession = session;
            }
            if (stringOrEmpty(session && session.execution_mode).toLowerCase() === "ssh") {
                preferredSession = session;
                break;
            }
        }

        if (preferredSession) {
            return sessionHostToken(preferredSession);
        }

        return hostToken(stringOrEmpty(windowData && windowData.execution_mode), "", stringOrEmpty(windowData && windowData.connection_key));
    }

    function projectCardFill(projectGroup) {
        const project = stringOrEmpty(projectGroup && projectGroup.project);
        const mode = stringOrEmpty(projectGroup && projectGroup.execution_mode).toLowerCase();
        const active = !!(projectGroup && projectGroup.is_active);

        if (project === "global") {
            return active ? colors.panelAlt : colors.cardAlt;
        }
        if (mode === "ssh") {
            return active ? "#101c24" : colors.cardAlt;
        }
        return active ? colors.panelAlt : colors.cardAlt;
    }

    function projectHeaderFill(projectGroup) {
        const project = stringOrEmpty(projectGroup && projectGroup.project);
        const mode = stringOrEmpty(projectGroup && projectGroup.execution_mode).toLowerCase();
        const active = !!(projectGroup && projectGroup.is_active);

        if (project === "global") {
            return active ? colors.blueWash : colors.panel;
        }
        if (mode === "ssh") {
            return active ? "#14232b" : colors.panel;
        }
        return active ? colors.blueWash : colors.panel;
    }

    function sessionPhase(session) {
        const phase = stringOrEmpty(session && session.session_phase).toLowerCase();
        if (phase.length > 0) {
            return phase;
        }
        const terminalState = stringOrEmpty(session && session.terminal_state).toLowerCase();
        if (boolOrFalse(session && session.llm_stopped) || terminalState === "explicit_complete") {
            return "stopped";
        }
        if (boolOrFalse(session && session.output_unseen) || boolOrFalse(session && session.review_pending) || boolOrFalse(session && session.needs_user_action)) {
            return "needs_attention";
        }
        if (boolOrFalse(session && session.output_ready)) {
            return sessionIsCurrent(session) ? "done" : "needs_attention";
        }
        if (boolOrFalse(session && session.remote_source_stale)) {
            return "stale";
        }
        if (stringOrEmpty(session && session.stage_visual_state) === "working") {
            return "working";
        }
        if (boolOrFalse(session && session.process_running)) {
            return "idle";
        }
        return "inactive";
    }

    function sessionAccentColor(session) {
        const phase = sessionPhase(session);
        if (phase === "needs_attention") {
            return colors.amber;
        }
        if (phase === "stopped") {
            return colors.blueMuted;
        }
        if (phase === "done") {
            return colors.accent;
        }
        if (phase === "working") {
            return stageColor(session);
        }
        if (phase === "tmux_missing") {
            return colors.orange;
        }
        if (phase === "stale" || phase === "stale_source") {
            return colors.subtle;
        }
        return colors.blueMuted;
    }

    function sessionTint(session) {
        const phase = sessionPhase(session);
        if (phase === "needs_attention") {
            return colors.amberBg;
        }
        if (phase === "stopped") {
            return colors.blueWash;
        }
        if (phase === "done") {
            return colors.accentBg;
        }
        if (phase === "working") {
            return stageBackground(session);
        }
        if (phase === "tmux_missing") {
            return colors.orangeBg;
        }
        return colors.panelAlt;
    }

    function boolOrFalse(value) {
        return value === true;
    }

    function stageState(session) {
        const stage = stringOrEmpty(session.stage).toLowerCase();
        if (stage === "attention") {
            return "attention";
        }
        if (stage === "waiting_input") {
            return "waiting";
        }
        if (stage === "output_ready") {
            return "ready";
        }
        return stringOrEmpty(session.stage_visual_state);
    }

    function sessionNeedsAttention(session) {
        return sessionPhase(session) === "needs_attention";
    }

    function sessionIsActivelyProcessing(session) {
        if (sessionPhase(session) === "working") {
            return true;
        }
        const stage = stringOrEmpty(session && session.stage).toLowerCase();
        const ageSeconds = Number(session && session.activity_age_seconds);
        const freshness = stringOrEmpty(session && session.activity_freshness).toLowerCase();
        const pendingTools = Number(session && session.pending_tools);
        const statusReason = stringOrEmpty(session && session.status_reason).toLowerCase();
        const lastActivityAt = stringOrEmpty(session && session.last_activity_at);

        if (boolOrFalse(session && session.needs_user_action) || boolOrFalse(session && session.output_ready) || boolOrFalse(session && session.output_unseen)) {
            return false;
        }
        if (boolOrFalse(session && session.remote_source_stale) || freshness === "stale") {
            return false;
        }
        if (boolOrFalse(session && session.pulse_working) || boolOrFalse(session && session.is_streaming) || (Number.isFinite(pendingTools) && pendingTools > 0)) {
            return true;
        }
        if (statusReason === "process_keepalive" && !lastActivityAt.length) {
            return false;
        }

        return ["starting", "thinking", "tool_running", "streaming"].indexOf(stage) >= 0 && (!Number.isFinite(ageSeconds) || ageSeconds <= 15) && freshness !== "stale";
    }

    function sessionHasMotion(session) {
        return sessionIsActivelyProcessing(session);
    }

    function sessionNeedsReview(session) {
        return sessionPhase(session) === "needs_attention";
    }

    function sessionBadgeState(session) {
        return sessionPhase(session);
    }

    function sessionBadgeColor(session) {
        const state = sessionBadgeState(session);
        if (state === "needs_attention") {
            return colors.amber;
        }
        if (state === "stopped") {
            return colors.violet;
        }
        if (state === "done") {
            return colors.accent;
        }
        if (state === "working") {
            return root.sessionAccentColor(session);
        }
        if (state === "tmux_missing") {
            return colors.orange;
        }
        if (state === "stale" || state === "stale_source") {
            return colors.subtle;
        }
        return colors.muted;
    }

    function sessionBadgeBackground(session) {
        const state = sessionBadgeState(session);
        if (state === "needs_attention") {
            return colors.amberBg;
        }
        if (state === "stopped") {
            return Qt.tint(colors.violetBg, Qt.rgba(1, 1, 1, 0.04));
        }
        if (state === "done") {
            return colors.accentBg;
        }
        if (state === "working") {
            return root.sessionIsCurrent(session) ? colors.bg : colors.cardAlt;
        }
        if (state === "tmux_missing") {
            return colors.orangeBg;
        }
        if (state === "stale" || state === "stale_source") {
            return colors.bg;
        }
        return colors.cardAlt;
    }

    function sessionBadgeBorderColor(session) {
        const state = sessionBadgeState(session);
        if (state === "stopped") {
            return Qt.tint(colors.violet, Qt.rgba(1, 1, 1, 0.16));
        }
        return "transparent";
    }

    function sessionAvailabilityState(session) {
        const explicit = stringOrEmpty(session && session.availability_state).toLowerCase();
        if (explicit.length > 0) {
            return explicit;
        }
        if (boolOrFalse(session && session.remote_source_stale)) {
            return "stale_source";
        }
        if (stringOrEmpty(session && session.session_phase).toLowerCase() === "tmux_missing") {
            return "tmux_missing";
        }
        if (Number(session && session.bridge_window_id) > 0) {
            return "remote_bridge_bound";
        }
        const focusMode = stringOrEmpty(session && session.focus_mode).toLowerCase();
        if (focusMode === "remote_bridge_bound") {
            return "remote_bridge_bound";
        }
        if (focusMode === "remote_bridge_attachable") {
            return "remote_bridge_attachable";
        }
        if (focusMode === "local_window") {
            return "local_window";
        }
        return "unavailable";
    }

    function sessionAvailabilityLabel(session) {
        const state = sessionAvailabilityState(session);
        if (state === "remote_bridge_bound") {
            return "Attached here";
        }
        if (state === "remote_bridge_attachable") {
            return "Attach here";
        }
        if (state === "stale_source") {
            return "Stale source";
        }
        if (state === "tmux_missing") {
            return "Tmux missing";
        }
        if (state === "unavailable") {
            return "Unavailable";
        }
        return "Available here";
    }

    function sessionAgeCompactLabel(session) {
        const ageSeconds = Number(session && session.activity_age_seconds);
        if (!Number.isFinite(ageSeconds) || ageSeconds < 0) {
            return "";
        }
        if (ageSeconds <= 1) {
            return "now";
        }
        if (ageSeconds < 60) {
            return String(Math.round(ageSeconds)) + "s";
        }
        if (ageSeconds < 3600) {
            return String(Math.floor(ageSeconds / 60)) + "m";
        }
        if (ageSeconds < 86400) {
            return String(Math.floor(ageSeconds / 3600)) + "h";
        }
        return String(Math.floor(ageSeconds / 86400)) + "d";
    }

    function sessionTurnOwner(session) {
        const explicitOwner = stringOrEmpty(session && session.turn_owner).toLowerCase();
        if (["llm", "user", "blocked", "unknown"].indexOf(explicitOwner) >= 0) {
            return explicitOwner;
        }
        if (boolOrFalse(session && session.needs_user_action)) {
            return "blocked";
        }
        if (boolOrFalse(session && session.output_ready) || boolOrFalse(session && session.output_unseen)) {
            return "user";
        }
        if (sessionPhase(session) === "working") {
            return "llm";
        }
        if (boolOrFalse(session && session.process_running)) {
            return "user";
        }
        return "unknown";
    }

    function sessionTurnOwnerLabel(session) {
        const owner = sessionTurnOwner(session);
        if (owner === "llm") {
            return "LLM";
        }
        if (owner === "user") {
            return "User";
        }
        if (owner === "blocked") {
            return "Blocked";
        }
        return "Unknown";
    }

    function sessionActivitySubstateLabel(session) {
        if (sessionBadgeState(session) === "stopped") {
            return "";
        }
        const explicit = stringOrEmpty(session && session.activity_substate_label);
        if (explicit.length > 0) {
            return explicit;
        }
        const stageLabel = stringOrEmpty(session && session.stage_label);
        if (stageLabel.length > 0) {
            return stageLabel;
        }
        return compactSessionStateLabel(session);
    }

    function sessionBadgeLabel(session) {
        const ownerLabel = sessionTurnOwnerLabel(session);
        const substateLabel = sessionActivitySubstateLabel(session);
        if (substateLabel.length > 0 && substateLabel !== ownerLabel) {
            return ownerLabel + " · " + substateLabel;
        }
        if (ownerLabel !== "Unknown") {
            return ownerLabel;
        }
        return sessionAgeCompactLabel(session);
    }

    function sessionActivityChipLabel(session) {
        const state = sessionBadgeState(session);
        const stage = stringOrEmpty(session && session.activity_substate).toLowerCase();
        const substateLabel = sessionActivitySubstateLabel(session);

        if (state === "needs_attention") {
            return substateLabel.length > 0 ? substateLabel : "Needs attention";
        }
        if (stage === "tool_running") {
            return "Tool";
        }
        if (stage === "streaming") {
            return "Streaming";
        }
        if (stage === "starting" || stage === "thinking") {
            return "Thinking";
        }
        if (state === "stopped") {
            return "";
        }
        if (state === "done") {
            return "Done";
        }
        if (substateLabel.length > 0) {
            return substateLabel;
        }
        return compactSessionStateLabel(session);
    }

    function sessionBadgeSymbol(session) {
        const stage = stringOrEmpty(session && session.activity_substate).toLowerCase();
        const owner = sessionTurnOwner(session);
        const state = sessionBadgeState(session);
        if (owner === "blocked" || state === "needs_attention") {
            return "!";
        }
        if (stage === "tool_running") {
            return "⚙";
        }
        if (stage === "streaming") {
            return "≈";
        }
        if (stage === "starting" || stage === "thinking") {
            return "◔";
        }
        if (state === "stopped") {
            return "●";
        }
        if (state === "done") {
            return "✓";
        }
        if (owner === "llm" || state === "working") {
            return "◔";
        }
        if (owner === "user") {
            return "⌨";
        }
        if (state === "stale") {
            return "◌";
        }
        return "•";
    }

    function sessionIdentityLabel(session) {
        const source = stringOrEmpty(session.identity_source).toLowerCase();
        if (source === "native") {
            return "N";
        }
        if (source === "pid") {
            return "PID";
        }
        if (source === "pane") {
            return "P";
        }
        return "H";
    }

    function sessionHostLabel(session) {
        const host = displayHostName(session && session.host_name);
        if (!host) {
            return root.modeLabel(session.execution_mode);
        }
        return host;
    }

    function hostMonogram(mode, hostName, connectionKey) {
        const token = hostToken(mode, hostName, connectionKey);
        const monogram = stringOrEmpty(token && token.monogram).trim().toUpperCase();
        return monogram.length > 0 ? monogram.charAt(0) : "";
    }

    function buildSessionAlias(monogram, paneId) {
        const prefix = stringOrEmpty(monogram).trim().toUpperCase();
        const pane = stringOrEmpty(paneId).trim();
        if (!prefix.length || !pane.length) {
            return "";
        }
        return prefix.charAt(0) + pane;
    }

    function sessionAlias(session) {
        return buildSessionAlias(
            hostMonogram(
                stringOrEmpty(session && session.execution_mode),
                stringOrEmpty(session && session.host_name),
                stringOrEmpty(session && session.connection_key)
            ),
            stringOrEmpty(session && session.tmux_pane)
        );
    }

    function sessionPaneLabel(session) {
        const label = stringOrEmpty(session.pane_label || session.pane_title || session.tmux_pane);
        if (label) {
            return label;
        }
        const surfaceKind = stringOrEmpty(session.surface_kind);
        if (surfaceKind === "tmux-pane") {
            return "Pane";
        }
        return "";
    }

    function sessionPidLabel(session) {
        const processPid = Number(session && session.pid);
        if (Number.isFinite(processPid) && processPid > 0) {
            return "PID " + String(Math.trunc(processPid));
        }
        const panePid = Number(session && session.pane_pid);
        if (Number.isFinite(panePid) && panePid > 0) {
            return "PID " + String(Math.trunc(panePid));
        }
        return "";
    }

    function sessionPaneLocatorLabel(session) {
        const paneId = stringOrEmpty(session && session.tmux_pane).trim();
        if (!paneId) {
            return "";
        }
        const pane = sessionPaneLabel(session);
        if (pane && pane.indexOf(paneId) >= 0) {
            return "";
        }
        return "Pane " + paneId;
    }

    function compactSessionStateLabel(session) {
        const badgeState = sessionBadgeState(session);
        if (badgeState === "needs_attention") {
            return "Needs attention";
        }
        if (badgeState === "stopped") {
            return "";
        }
        if (badgeState === "done") {
            return "Done";
        }
        if (badgeState === "quiet_alive") {
            return "Quiet";
        }
        if (badgeState === "working") {
            return "Working";
        }
        if (badgeState === "tmux_missing") {
            return "Tmux missing";
        }
        if (badgeState === "stale_source") {
            return "Stale source";
        }
        if (badgeState === "stale") {
            return "Stale";
        }
        if (badgeState === "inactive") {
            return "Inactive";
        }
        return "Idle";
    }

    function toolLabel(session) {
        const tool = stringOrEmpty(session.tool).toLowerCase();
        if (tool === "codex") {
            return "Codex";
        }
        if (tool === "claude-code" || tool === "claude") {
            return "Claude";
        }
        if (tool === "gemini") {
            return "Gemini";
        }
        return "AI";
    }

    function sessionCardFill(session) {
        if (sessionIsCurrent(session)) {
            return sessionTint(session);
        }
        return colors.panelAlt;
    }

    function sessionCardBorder(session) {
        return "transparent";
    }

    function sessionTextColor(session) {
        return sessionIsCurrent(session) ? colors.text : colors.textDim;
    }

    function sessionIsCurrent(session) {
        return currentSessionKey() === stringOrEmpty(session.session_key);
    }

    function sessionHasConflict(session) {
        return stringOrEmpty(session.conflict_state).length > 0;
    }

    function sessionPillLabel(session) {
        const alias = sessionAlias(session);
        if (alias.length > 0) {
            return alias;
        }
        const pane = sessionPaneLabel(session);
        if (pane) {
            return pane;
        }
        return compactSessionStateLabel(session);
    }

    function sessionPrimaryLabel(session) {
        const alias = sessionAlias(session);
        if (alias.length > 0) {
            return alias;
        }
        const pane = sessionPaneLabel(session);
        if (pane) {
            return pane;
        }
        const tool = toolLabel(session);
        return tool ? tool + " Session" : "AI Session";
    }

    function sessionSecondaryLabel(session) {
        const bits = [];
        const project = shortProject(stringOrEmpty(session && (session.project_name || session.project || "")));
        const availability = sessionAvailabilityLabel(session);
        const phase = compactSessionStateLabel(session);
        if (project.length > 0 && project !== "Global") {
            bits.push(project);
        }
        if (availability.length > 0 && sessionAvailabilityState(session) !== "local_window") {
            bits.push(availability);
        }
        if (phase.length > 0 && phase !== availability) {
            bits.push(phase);
        }

        if (bits.length === 0) {
            const paneLocator = sessionPaneLocatorLabel(session);
            const pid = sessionPidLabel(session);
            if (paneLocator) {
                bits.push(paneLocator);
            }
            if (pid) {
                bits.push(pid);
            }
        }

        return bits.join(" • ");
    }

    function findWindowById(windowId) {
        const target = Number(windowId || 0);
        if (target <= 0) {
            return null;
        }

        const projects = arrayOrEmpty(dashboard.projects);
        for (let i = 0; i < projects.length; i += 1) {
            const windows = arrayOrEmpty(projects[i].windows);
            for (let j = 0; j < windows.length; j += 1) {
                const windowData = windows[j];
                if (Number(windowData.id || 0) === target) {
                    return windowData;
                }
            }
        }
        return null;
    }

    function groupedSessionBands() {
        const sessions = panelSessions();
        const groups = [];
        const index = {};

        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            const project = stringOrEmpty(session.project_name || session.project || "global");
            const hostKey = sessionHostGroupKey(session);
            const groupKey = hostKey || "unknown";

            let group = index[groupKey];
            if (!group) {
                group = {
                    group_key: groupKey,
                    host_label: stringOrEmpty(sessionHostToken(session).label),
                    host_name: sessionHostLabel(session),
                    raw_host_name: stringOrEmpty(session.host_name),
                    execution_mode: stringOrEmpty(session.execution_mode),
                    is_current_host: sessionIsCurrentHost(session),
                    focus_mode: stringOrEmpty(session.focus_mode),
                    sessions: [],
                    project_groups: []
                };
                group.project_index = {};
                index[groupKey] = group;
                groups.push(group);
            }

            group.sessions.push(session);
            const projectKey = project || "global";
            let projectGroup = group.project_index[projectKey];
            if (!projectGroup) {
                const parentWindow = findWindowById(Number(session.window_id || 0));
                projectGroup = {
                    project_key: projectKey,
                    display_name: shortProject(project || "global"),
                    project_name: project,
                    execution_mode: stringOrEmpty(session.execution_mode),
                    is_current_host: sessionIsCurrentHost(session),
                    focus_mode: stringOrEmpty(session.focus_mode),
                    workspace_name: parentWindow ? stringOrEmpty(parentWindow.workspace) : "",
                    window_title: parentWindow ? stringOrEmpty(displayTitle(parentWindow)) : "",
                    sessions: []
                };
                group.project_index[projectKey] = projectGroup;
                group.project_groups.push(projectGroup);
            }
            projectGroup.sessions.push(session);
        }

        for (let i = 0; i < groups.length; i += 1) {
            groups[i].sessions = stableSortedSessions(groups[i].sessions);
            const projectGroups = arrayOrEmpty(groups[i].project_groups);
            for (let j = 0; j < projectGroups.length; j += 1) {
                projectGroups[j].sessions = stableSortedSessions(projectGroups[j].sessions);
            }
            projectGroups.sort((left, right) => {
                let result = compareAscending(modeSortRank(stringOrEmpty(left && left.execution_mode)), modeSortRank(stringOrEmpty(right && right.execution_mode)));
                if (result !== 0) {
                    return result;
                }

                result = compareAscending(stringOrEmpty(left && left.project_name), stringOrEmpty(right && right.project_name));
                if (result !== 0) {
                    return result;
                }

                result = compareAscending(stringOrEmpty(left && left.execution_mode), stringOrEmpty(right && right.execution_mode));
                if (result !== 0) {
                    return result;
                }

                return compareAscending(stringOrEmpty(left && left.project_key), stringOrEmpty(right && right.project_key));
            });
            delete groups[i].project_index;
        }

        groups.sort((left, right) => {
            let result = compareDescending(boolOrFalse(left && left.is_current_host) ? 1 : 0, boolOrFalse(right && right.is_current_host) ? 1 : 0);
            if (result !== 0) {
                return result;
            }

            result = compareAscending(modeSortRank(stringOrEmpty(left && left.execution_mode)), modeSortRank(stringOrEmpty(right && right.execution_mode)));
            if (result !== 0) {
                return result;
            }

            result = compareAscending(stringOrEmpty(left && left.host_label), stringOrEmpty(right && right.host_label));
            if (result !== 0) {
                return result;
            }

            result = compareAscending(stringOrEmpty(left && left.execution_mode), stringOrEmpty(right && right.execution_mode));
            if (result !== 0) {
                return result;
            }

            return compareAscending(stringOrEmpty(left && left.group_key), stringOrEmpty(right && right.group_key));
        });

        return groups;
    }

    function sessionGroupTitle(group) {
        return stringOrEmpty(group && group.host_label) || displayHostName(group.host_name || group.raw_host_name || "Unknown");
    }

    function sessionGroupExpanded(group) {
        const key = stringOrEmpty(group && group.group_key);
        if (!key.length) {
            return true;
        }
        if (expandedSessionGroups[key] !== undefined) {
            return !!expandedSessionGroups[key];
        }
        return boolOrFalse(group && group.is_current_host);
    }

    function toggleSessionGroup(group) {
        const key = stringOrEmpty(group && group.group_key);
        if (!key.length) {
            return;
        }
        const next = Object.assign({}, expandedSessionGroups);
        next[key] = !sessionGroupExpanded(group);
        expandedSessionGroups = next;
    }

    function windowSessionIcons(windowData) {
        return arrayOrEmpty(windowData.sessions).slice(0, 4);
    }

    function windowSessionOverflowCount(windowData) {
        return Math.max(0, arrayOrEmpty(windowData.sessions).length - 4);
    }

    function workspaceLabel(workspace) {
        return stringOrEmpty(workspace.name || workspace.number || workspace.num);
    }

    function workspaceSnapshot(workspaceName) {
        const outputs = arrayOrEmpty(dashboard.outputs);
        const target = stringOrEmpty(workspaceName);
        for (let i = 0; i < outputs.length; i += 1) {
            const workspaces = arrayOrEmpty(outputs[i].workspaces);
            for (let j = 0; j < workspaces.length; j += 1) {
                const workspace = workspaces[j];
                if (stringOrEmpty(workspace.name) === target) {
                    return workspace;
                }
            }
        }
        return null;
    }

    function workspaceWindowCount(workspaceName) {
        const workspace = workspaceSnapshot(workspaceName);
        const windows = arrayOrEmpty(workspace ? workspace.windows : []);
        return windows.length;
    }

    function workspaceIconSources(workspaceName) {
        const workspace = workspaceSnapshot(workspaceName);
        const windows = arrayOrEmpty(workspace ? workspace.windows : []);
        const icons = [];

        for (let i = 0; i < windows.length; i += 1) {
            const source = iconSourceFor(windows[i]);
            if (!source || icons.indexOf(source) >= 0) {
                continue;
            }
            icons.push(source);
            if (icons.length >= 2) {
                break;
            }
        }

        return icons;
    }

    function appLabel(windowData) {
        const appName = stringOrEmpty(windowData.app_name || windowData.app_key);
        if (!appName) {
            return "Window";
        }
        if (appName === "terminal") {
            return "Terminal";
        }
        if (appName === "scratchpad-terminal") {
            return "Scratchpad";
        }
        if (appName === "1password") {
            return "1Password";
        }
        return appName;
    }

    function displayTitle(windowData) {
        const title = stringOrEmpty(windowData.title);
        const label = appLabel(windowData);
        if (!title) {
            return label;
        }
        if (title === label || title === "Ghostty") {
            return shortProject(windowData.project);
        }
        return title;
    }

    function displayMeta(windowData) {
        const bits = [];
        const workspace = stringOrEmpty(windowData.workspace);

        if (workspace && workspace.indexOf("scratchpad") !== 0) {
            bits.push("WS " + workspace);
        }

        return bits.join(" • ");
    }

    function iconSourceFor(windowData) {
        const absolute = stringOrEmpty(windowData.icon_path);
        if (absolute) {
            return "file://" + absolute;
        }

        const candidates = [stringOrEmpty(windowData.app_key), stringOrEmpty(windowData.app_name), "application-x-executable"];

        for (let i = 0; i < candidates.length; i += 1) {
            const candidate = candidates[i];
            if (!candidate) {
                continue;
            }
            const resolved = Quickshell.iconPath(candidate, true);
            if (resolved) {
                return resolved;
            }
        }

        return "";
    }

    function launcherEntryAccentColor(entry) {
        const kind = stringOrEmpty(entry && entry.kind);
        const hostTokenData = entry && entry.host_token ? entry.host_token : null;
        if (kind === "session" || kind === "window") {
            return hostTokenData && hostTokenData.is_remote ? colors.orange : colors.blue;
        }
        if (kind === "url" || kind === "search") {
            return stringOrEmpty(entry && entry.matched_pwa_ulid) ? colors.teal : colors.blue;
        }
        if (kind === "runner") {
            return colors.orange;
        }
        if (kind === "file") {
            return colors.teal;
        }
        if (kind === "snippet") {
            return colors.teal;
        }
        return "transparent";
    }

    function launcherIconSource(entry) {
        const isOnePassword = stringOrEmpty(entry && entry.kind) === "onepassword";
        const isClipboard = stringOrEmpty(entry && entry.kind) === "clipboard";
        const isUrl = stringOrEmpty(entry && entry.kind) === "url" || stringOrEmpty(entry && entry.kind) === "search";
        const isRunner = stringOrEmpty(entry && entry.kind) === "runner";
        const isFile = stringOrEmpty(entry && entry.kind) === "file";
        const isSnippet = stringOrEmpty(entry && entry.kind) === "snippet";
        const icon = stringOrEmpty(entry && entry.icon);
        if (!icon) {
            if (isOnePassword) {
                return Quickshell.iconPath("dialog-password-symbolic", true) || ("file://" + shellConfig.onePasswordIcon);
            }
            if (isClipboard) {
                return Quickshell.iconPath("edit-paste", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            if (isUrl) {
                return Quickshell.iconPath("web-browser", true) || Quickshell.iconPath("internet-web-browser", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            if (isRunner) {
                return Quickshell.iconPath("utilities-terminal", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            if (isFile) {
                if (launcherFileIsDirectory(entry)) {
                    return Quickshell.iconPath("folder", true) || Quickshell.iconPath("folder-open", true) || Quickshell.iconPath("system-file-manager", true) || "";
                }
                return Quickshell.iconPath("text-x-generic", true) || Quickshell.iconPath("application-octet-stream", true) || Quickshell.iconPath("system-file-manager", true) || "";
            }
            if (isSnippet) {
                return Quickshell.iconPath("insert-text", true) || Quickshell.iconPath("application-x-executable", true) || "";
            }
            return Quickshell.iconPath("application-x-executable", true) || "";
        }

        if (icon.indexOf("/") === 0) {
            return "file://" + icon;
        }

        const resolved = Quickshell.iconPath(icon, true);
        if (resolved) {
            return resolved;
        }

        if (isOnePassword) {
            return Quickshell.iconPath("dialog-password-symbolic", true) || ("file://" + shellConfig.onePasswordIcon);
        }

        if (isClipboard) {
            return Quickshell.iconPath("edit-paste", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }
        if (isUrl) {
            return Quickshell.iconPath("web-browser", true) || Quickshell.iconPath("internet-web-browser", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }
        if (isRunner) {
            return Quickshell.iconPath("utilities-terminal", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }
        if (isFile) {
            if (launcherFileIsDirectory(entry)) {
                return Quickshell.iconPath("folder", true) || Quickshell.iconPath("folder-open", true) || Quickshell.iconPath("system-file-manager", true) || "";
            }
            return Quickshell.iconPath("text-x-generic", true) || Quickshell.iconPath("application-octet-stream", true) || Quickshell.iconPath("system-file-manager", true) || "";
        }
        if (isSnippet) {
            return Quickshell.iconPath("insert-text", true) || Quickshell.iconPath("application-x-executable", true) || "";
        }

        return Quickshell.iconPath("application-x-executable", true) || "";
    }

    function restartLauncherQuery() {
        if (!launcherVisible) {
            return;
        }

        launcherError = "";

        if (launcherQueryProcess.running) {
            launcherQueryProcess.running = false;
        }

        if (launcherMode === "projects") {
            launcherLoading = false;
            setLauncherEntries(projectLauncherEntries(launcherQuery));
            return;
        }

        if (launcherMode === "files") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.fileListBin, launcherQuery, "40", "20"];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "urls") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.urlListBin, launcherQuery, "30"];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "runner") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.runnerListBin, launcherQuery];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "snippets") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.snippetsListBin, launcherQuery, "40"];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "sessions") {
            launcherLoading = false;
            setLauncherEntries(launcherSessionSwitcherActive && launcherQuery === "" ? launcherSessionSwitcherEntries() : launcherSessionEntries(launcherQuery));
            return;
        }

        if (launcherMode === "windows") {
            launcherLoading = false;
            setLauncherEntries(launcherWindowEntries(launcherQuery));
            return;
        }

        if (launcherMode === "onepassword") {
            setLauncherEntries(onePasswordEntries(launcherQuery));
            launcherLoading = onePasswordEntriesCache.length === 0;
            launcherQueryProcess.command = [shellConfig.onePasswordListBin];
            launcherQueryProcess.running = true;
            return;
        }

        if (launcherMode === "clipboard") {
            launcherLoading = true;
            launcherQueryProcess.command = [shellConfig.clipboardListBin, launcherQuery, "30"];
            launcherQueryProcess.running = true;
            return;
        }

        launcherLoading = true;
        launcherQueryProcess.command = [shellConfig.launcherQueryBin, launcherQuery, "12", "20"];
        launcherQueryProcess.running = true;
    }

    function parseUrlResults(data) {
        if (launcherMode !== "urls" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load Chrome URL results";
            console.warn("launcher.urls.parse:", raw, error);
        }
    }

    function parseLauncherResults(data) {
        if (launcherMode !== "apps" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load app results";
            console.warn("launcher.query.parse:", raw, error);
        }
    }

    function parseFileResults(data) {
        if (launcherMode !== "files" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load file results";
            console.warn("launcher.files.parse:", raw, error);
        }
    }

    function parseRunnerResults(data) {
        if (launcherMode !== "runner" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to prepare command";
            console.warn("launcher.runner.parse:", raw, error);
        }
    }

    function parseSnippetResults(data) {
        if (launcherMode !== "snippets" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load curated commands";
            console.warn("launcher.snippets.parse:", raw, error);
        }
    }

    function parseOnePasswordResults(data) {
        if (launcherMode !== "onepassword" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            onePasswordEntriesCache = [];
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            onePasswordEntriesCache = Array.isArray(parsed) ? parsed : [];
            setLauncherEntries(onePasswordEntries(launcherQuery));
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            onePasswordEntriesCache = [];
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load 1Password items";
            console.warn("launcher.onepassword.parse:", raw, error);
        }
    }

    function parseClipboardResults(data) {
        if (launcherMode !== "clipboard" || !launcherVisible) {
            return;
        }

        const raw = stringOrEmpty(data).trim();
        if (!raw) {
            setLauncherEntries([]);
            launcherLoading = false;
            return;
        }

        try {
            const parsed = JSON.parse(raw);
            setLauncherEntries(Array.isArray(parsed) ? parsed : []);
            launcherLoading = false;
            launcherError = "";
        } catch (error) {
            setLauncherEntries([]);
            launcherLoading = false;
            launcherError = "Unable to load clipboard history";
            console.warn("launcher.clipboard.parse:", raw, error);
        }
    }

    function activeLauncherEntry() {
        const entries = arrayOrEmpty(launcherEntries);
        if (!entries.length) {
            return null;
        }
        if (launcherSelectedIndex < 0 || launcherSelectedIndex >= entries.length) {
            return entries[0];
        }
        return entries[launcherSelectedIndex];
    }

    function moveLauncherSelection(delta) {
        const entries = arrayOrEmpty(launcherEntries);
        if (!entries.length) {
            launcherSelectedIndex = 0;
            return;
        }

        launcherPointerSelectionEnabled = false;
        launcherSelectedIndex = (launcherSelectedIndex + delta + entries.length) % entries.length;
    }

    function updateLauncherPointerSelection(index) {
        const entryIndex = Number(index);
        if (isNaN(entryIndex) || entryIndex < 0 || entryIndex >= launcherEntries.length) {
            return;
        }

        launcherPointerSelectionEnabled = true;
        if (launcherSelectedIndex !== entryIndex) {
            launcherSelectedIndex = entryIndex;
        }
    }

    function syncLauncherListSelection() {
        if (!launcherVisible) {
            return;
        }

        const entries = arrayOrEmpty(launcherEntries);
        if (!entries.length || launcherSelectedIndex < 0) {
            if (launcherList) {
                launcherList.currentIndex = -1;
            }
            return;
        }

        const nextIndex = Math.max(0, Math.min(launcherSelectedIndex, entries.length - 1));
        if (!launcherList) {
            return;
        }

        launcherList.currentIndex = nextIndex;
        Qt.callLater(function() {
            if (!launcherVisible || !launcherList) {
                return;
            }

            const latestEntries = root.arrayOrEmpty(root.launcherEntries);
            if (!latestEntries.length || root.launcherSelectedIndex !== nextIndex || nextIndex >= latestEntries.length) {
                return;
            }

            launcherList.currentIndex = nextIndex;
            launcherList.positionViewAtIndex(nextIndex, ListView.Visible);
        });
    }

    function resetLauncherListViewport() {
        if (!launcherList) {
            return;
        }

        launcherList.currentIndex = -1;
        Qt.callLater(function() {
            if (!launcherList) {
                return;
            }
            launcherList.positionViewAtBeginning();
        });
    }

    function closeLauncher() {
        launcherVisible = false;
    }

    function activateLauncherEntry(entry, actionMode) {
        const kind = stringOrEmpty(entry && entry.kind);
        if (kind === "global") {
            closeLauncher();
            clearContext();
            return;
        }
        if (kind === "project") {
            closeLauncher();
            activateWorktree(entry, stringOrEmpty(entry && entry.variant) || "local");
            return;
        }
        if (kind === "session") {
            const sessionKey = stringOrEmpty(entry && entry.session_key);
            if (!sessionKey) {
                return;
            }

            closeLauncher();
            focusSession(entry);
            return;
        }
        if (kind === "window") {
            closeLauncher();
            if (stringOrEmpty(actionMode) === "close") {
                closeWindow(entry);
            } else {
                focusWindow(entry);
            }
            return;
        }
        if (kind === "onepassword") {
            const itemId = stringOrEmpty(entry && entry.identifier);
            const mode = stringOrEmpty(actionMode || "password") || "password";
            if (!itemId) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.onePasswordActionBin, mode, itemId]);
            return;
        }
        if (kind === "clipboard") {
            const identifier = stringOrEmpty(entry && entry.identifier);
            const action = stringOrEmpty(actionMode || "copy") || "copy";
            if (!identifier) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.clipboardActionBin, action, identifier]);
            return;
        }
        if (kind === "file") {
            const identifier = stringOrEmpty(entry && entry.identifier);
            const action = stringOrEmpty(actionMode || "open") || "open";
            if (!identifier) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.fileActionBin, action, identifier]);
            return;
        }
        if (kind === "url" || kind === "search") {
            const url = stringOrEmpty(entry && entry.url);
            const mode = stringOrEmpty(actionMode || "preferred") || "preferred";
            if (!url) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.urlOpenBin, mode, url]);
            return;
        }
        if (kind === "runner") {
            const command = stringOrEmpty(entry && (entry.command || entry.text || entry.identifier));
            const mode = stringOrEmpty(actionMode || "background") || "background";
            if (!command) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.launcherCommandActionBin, mode, command]);
            return;
        }
        if (kind === "snippet") {
            const command = stringOrEmpty(entry && (entry.command || entry.identifier || entry.text));
            const mode = stringOrEmpty(actionMode || "background") || "background";
            if (!command) {
                return;
            }

            closeLauncher();
            runDetached([shellConfig.launcherCommandActionBin, mode, command]);
            return;
        }

        const identifier = stringOrEmpty(entry && entry.identifier);
        if (!identifier) {
            return;
        }

        closeLauncher();
        runDetached([shellConfig.launcherLaunchBin, identifier]);
    }

    function activateSelectedLauncherEntry(actionMode) {
        activateLauncherEntry(activeLauncherEntry(), actionMode);
    }

    function runDetached(command) {
        if (!command || !command.length) {
            return;
        }
        Quickshell.execDetached(command);
    }

    function showRuntimePanel() {
        panelVisible = true;
        panelSection = "runtime";
        worktreePickerVisible = false;
        audioPopupVisible = false;
        bluetoothPopupVisible = false;
        ensureRuntimePanelExpandedSection();
    }

    function showAssistantPanel() {
        panelVisible = true;
        panelSection = "assistant";
        worktreePickerVisible = false;
        notificationCenterVisible = false;
        audioPopupVisible = false;
        bluetoothPopupVisible = false;
    }

    function toggleAssistantPanel() {
        if (panelVisible && panelSection === "assistant") {
            panelVisible = false;
            return;
        }
        showAssistantPanel();
    }

    function focusSession(sessionKey) {
        const sessionData = (typeof sessionKey === "object") ? sessionKey : null;
        const resolvedSessionKey = stringOrEmpty(sessionData && sessionData.session_key) || stringOrEmpty(sessionKey);
        if (!resolvedSessionKey) {
            return;
        }

        const current = currentSessionKey();
        if (current && current !== resolvedSessionKey) {
            lastFocusedSessionKey = current;
        }

        const target = sessionFocusTarget(sessionData || resolvedSessionKey);
        runFocusTarget(target);
    }

    function cycleSessions(direction) {
        const sessions = panelSessions();
        if (!sessions.length) {
            return;
        }

        const current = currentSessionKey();
        let index = sessions.findIndex(item => stringOrEmpty(item.session_key) === current);
        if (index < 0) {
            index = 0;
        }

        const delta = direction === "prev" ? -1 : 1;
        const nextIndex = (index + delta + sessions.length) % sessions.length;
        focusSession(sessions[nextIndex]);
    }

    function cycleLauncherSessions(direction) {
        const delta = direction === "prev" ? -1 : 1;
        const shouldOpenSwitcher = !launcherVisible || launcherMode !== "sessions" || launcherQuery !== "" || !launcherSessionSwitcherActive;
        if (shouldOpenSwitcher) {
            launcherSessionSwitcherActive = true;
            launcherSessionSwitcherPendingDelta = delta;
            showLauncher("sessions", "");
            launcherSessionSwitcherOpenTimer.restart();
            return;
        }

        launcherSessionSwitcherPendingDelta = 0;
        moveLauncherSelection(delta);
        launcherFocusTimer.restart();
    }

    function finalizeLauncherSessionSwitcherOpen() {
        if (!launcherVisible || launcherMode !== "sessions" || launcherSessionSwitcherPendingDelta === 0) {
            return;
        }

        const delta = launcherSessionSwitcherPendingDelta;
        launcherSessionSwitcherPendingDelta = 0;
        const entries = launcherSessionSwitcherEntries();
        setLauncherEntries(entries);
        if (!entries.length) {
            return;
        }

        const current = currentSessionKey();
        let index = entries.findIndex(item => stringOrEmpty(item.session_key) === current);
        if (index < 0) {
            index = 0;
        }

        launcherPointerSelectionEnabled = false;
        launcherSelectedIndex = (index + delta + entries.length) % entries.length;
    }

    function commitLauncherSessionSwitch() {
        if (!launcherVisible || launcherMode !== "sessions" || !launcherSessionSwitcherActive) {
            return;
        }

        const entry = activeLauncherSessionEntry();
        launcherSessionSwitcherActive = false;
        launcherSessionSwitcherPendingDelta = 0;
        if (!entry) {
            closeLauncher();
            return;
        }

        activateLauncherEntry(entry);
    }

    function focusLastSession() {
        if (lastFocusedSessionKey) {
            focusSession(lastFocusedSessionKey);
            return;
        }

        const sessions = panelSessions();
        if (sessions.length) {
            focusSession(sessions[0]);
        }
    }

    function plainJsonValue(value) {
        if (value === null || value === undefined) {
            return null;
        }

        if (Array.isArray(value)) {
            const items = [];
            for (let i = 0; i < value.length; i += 1) {
                items.push(plainJsonValue(value[i]));
            }
            return items;
        }

        if (typeof value === "object") {
            const plain = {};
            for (const key in value) {
                if (!Object.prototype.hasOwnProperty.call(value, key)) {
                    continue;
                }
                plain[String(key)] = plainJsonValue(value[key]);
            }
            return plain;
        }

        return value;
    }

    function normalizedFocusTarget(target) {
        if (!target) {
            return null;
        }

        const method = stringOrEmpty(target.method);
        if (!method) {
            return null;
        }

        return {
            method: method,
            params: plainJsonValue(target.params || {}) || {},
        };
    }

    function runDaemonCall(method, params) {
        const normalizedMethod = stringOrEmpty(method);
        if (!normalizedMethod) {
            return;
        }

        const command = [shellConfig.i3pmBin, "daemon", "call", normalizedMethod];
        const serializedParams = JSON.stringify(plainJsonValue(params || {}) || {});
        if (serializedParams) {
            command.push("--params-json", serializedParams);
        }
        command.push("--json");
        runDetached(command);
    }

    function runFocusTarget(target) {
        const normalizedTarget = normalizedFocusTarget(target);
        if (!normalizedTarget) {
            return;
        }

        runDaemonCall(normalizedTarget.method, normalizedTarget.params);
    }

    function sessionFocusTarget(sessionOrKey) {
        if (sessionOrKey && typeof sessionOrKey === "object") {
            const explicitTarget = normalizedFocusTarget(sessionOrKey.focus_target);
            if (explicitTarget) {
                return explicitTarget;
            }
            const explicitKey = stringOrEmpty(sessionOrKey.session_key);
            if (explicitKey) {
                return {
                    method: "session.focus",
                    params: {
                        session_key: explicitKey,
                    },
                };
            }
        }

        const sessionKey = stringOrEmpty(sessionOrKey);
        if (!sessionKey) {
            return null;
        }

        return {
            method: "session.focus",
            params: {
                session_key: sessionKey,
            },
        };
    }

    function windowFocusTarget(windowData) {
        if (!windowData) {
            return null;
        }

        const explicitTarget = normalizedFocusTarget(windowData.focus_target);
        if (explicitTarget) {
            return explicitTarget;
        }

        const windowId = Number(windowData.id || windowData.window_id || 0);
        if (!windowId) {
            return null;
        }

        return {
            method: "window.focus",
            params: {
                window_id: windowId,
                project_name: stringOrEmpty(windowData.project),
                target_variant: stringOrEmpty(windowData.execution_mode),
                connection_key: stringOrEmpty(windowData.connection_key),
            },
        };
    }

    function focusWindow(windowData) {
        const target = windowFocusTarget(windowData);
        if (!target) {
            return;
        }

        runFocusTarget(target);
    }

    function sessionClosableWindowId(session) {
        const bridgeWindowId = Number(session && session.bridge_window_id || 0);
        if (bridgeWindowId > 0) {
            return bridgeWindowId;
        }

        const windowId = Number(session && session.window_id || 0);
        if (windowId > 0) {
            return windowId;
        }

        return 0;
    }

    function sessionCloseKey(session) {
        return stringOrEmpty(session && session.session_key);
    }

    function sessionHasTmuxCloseTarget(session) {
        const terminalContext = (session && session.terminal_context) || {};
        const tmuxSession = stringOrEmpty(session && session.tmux_session) || stringOrEmpty(terminalContext.tmux_session);
        const tmuxPane = stringOrEmpty(session && session.tmux_pane) || stringOrEmpty(terminalContext.tmux_pane);
        return tmuxSession !== "" && tmuxPane !== "";
    }

    function markSessionClosePending(sessionKey) {
        const key = stringOrEmpty(sessionKey);
        if (!key) {
            return;
        }
        const next = Object.assign({}, sessionClosePendingMap);
        next[key] = Date.now();
        sessionClosePendingMap = next;
    }

    function clearSessionClosePending(sessionKey) {
        const key = stringOrEmpty(sessionKey);
        if (!key || !Object.prototype.hasOwnProperty.call(sessionClosePendingMap, key)) {
            return;
        }
        const next = Object.assign({}, sessionClosePendingMap);
        delete next[key];
        sessionClosePendingMap = next;
    }

    function sessionClosePending(session) {
        const key = sessionCloseKey(session);
        return key !== "" && Object.prototype.hasOwnProperty.call(sessionClosePendingMap, key);
    }

    function pruneSessionClosePending() {
        const next = {};
        const now = Date.now();
        const liveKeys = {};
        const sessions = activeSessions();
        for (let i = 0; i < sessions.length; i += 1) {
            const sessionKey = sessionCloseKey(sessions[i]);
            if (sessionKey) {
                liveKeys[sessionKey] = true;
            }
        }
        for (const key in sessionClosePendingMap) {
            if (!Object.prototype.hasOwnProperty.call(sessionClosePendingMap, key)) {
                continue;
            }
            const startedAt = Number(sessionClosePendingMap[key] || 0);
            if (liveKeys[key] && now - startedAt < 15000) {
                next[key] = startedAt;
            }
        }
        sessionClosePendingMap = next;
    }

    function sessionHasClosableSurface(session) {
        return sessionHasTmuxCloseTarget(session) || sessionClosableWindowId(session) > 0;
    }

    function closeSession(session) {
        if (!session) {
            return;
        }

        const sessionKey = sessionCloseKey(session);
        if (sessionClosePending(session)) {
            return;
        }

        if (sessionHasTmuxCloseTarget(session) && sessionKey) {
            if (sessionCloseProcess.running) {
                return;
            }
            markSessionClosePending(sessionKey);
            sessionCloseProcessTargetKey = sessionKey;
            sessionCloseProcessStdout = "";
            sessionCloseProcessStderr = "";
            sessionCloseProcess.command = [shellConfig.i3pmBin, "session", "close", sessionKey, "--json"];
            sessionCloseProcess.running = true;
            return;
        }

        const windowId = sessionClosableWindowId(session);
        if (!windowId) {
            return;
        }
        if (sessionKey) {
            markSessionClosePending(sessionKey);
        }

        closeWindow({
            id: windowId,
            window_id: windowId,
            project: stringOrEmpty(session.project_name || session.project),
            execution_mode: stringOrEmpty(session.execution_mode || session.focus_execution_mode),
            connection_key: stringOrEmpty(session.connection_key || session.focus_connection_key),
        });
    }

    function activateWorkspace(workspace) {
        if (!workspace) {
            return;
        }

        if (typeof workspace.activate === "function") {
            workspace.activate();
            return;
        }

        const workspaceName = stringOrEmpty(workspace.name || workspace.number || workspace.num);
        if (!workspaceName) {
            return;
        }

        runDetached([shellConfig.i3pmBin, "workspace", "focus", workspaceName]);
    }

    function closeWindow(windowData) {
        if (!windowData) {
            return;
        }

        const windowId = Number(windowData.id || windowData.window_id || 0);
        if (!windowId) {
            return;
        }

        const command = [shellConfig.i3pmBin, "window", "action", String(windowId), "close"];
        const project = stringOrEmpty(windowData.project);
        const variant = stringOrEmpty(windowData.execution_mode);

        if (project && project !== "global") {
            command.push("--project", project);
        }
        if (variant) {
            command.push("--variant", variant);
        }

        runDetached(command);
    }

    function clearContext() {
        root.worktreePickerVisible = false;
        runDetached([shellConfig.i3pmBin, "context", "clear"]);
    }

    function switchContext(projectName, variant) {
        const name = stringOrEmpty(projectName);
        const mode = stringOrEmpty(variant);
        if (!name || name === "global") {
            clearContext();
            return;
        }

        root.worktreePickerVisible = false;
        const command = [shellConfig.i3pmBin, "context", "ensure", name];
        if (mode) {
            command.push("--variant", mode);
        }
        runDetached(command);
    }

    function activateWorktree(item, variant) {
        if (!item) {
            return;
        }

        const kind = stringOrEmpty(item.kind);
        if (kind === "global") {
            if (!isGlobalContext()) {
                clearContext();
            }
            return;
        }

        const projectName = stringOrEmpty(item.qualified_name);
        const requestedMode = stringOrEmpty(variant || "local") || "local";
        const activeProject = activeContextProjectName();
        const activeMode = activeContextExecutionMode();

        if (projectName === activeProject && requestedMode === activeMode) {
            focusPreferredWindowForContext(projectName, requestedMode);
            return;
        }

        switchContext(projectName, requestedMode);
    }

    function cycleDisplayLayout() {
        runDetached([shellConfig.i3pmBin, "display", "cycle"]);
    }

    function triggerPowerAction(command) {
        root.powerMenuVisible = false;
        runDetached(command);
    }

    function emptyDashboardState(status, errorMessage) {
        return {
            status: stringOrEmpty(status) || "loading",
            error: stringOrEmpty(errorMessage),
            active_context: {},
            active_terminal: {},
            active_ai_sessions: [],
            active_ai_sessions_mru: [],
            current_ai_session_key: "",
            display_layout: {},
            outputs: [],
            projects: [],
            worktrees: [],
            scratchpad: {},
            state_health: {},
            total_windows: 0
        };
    }

    function resetDashboard(status, errorMessage) {
        dashboard = root.emptyDashboardState(status, errorMessage);
        if (launcherVisible && (launcherMode === "projects" || launcherMode === "sessions" || launcherMode === "windows")) {
            restartLauncherQuery();
        }
    }

    function handleDashboardWatchError(payload) {
        const message = stringOrEmpty(payload).trim();
        if (!message) {
            return;
        }
        console.warn("dashboard.watch:", message);
        if (message.indexOf("Bad resource ID") !== -1 || message.indexOf("Fatal error") !== -1) {
            root.resetDashboard("reconnecting", message);
            dashboardWatcher.running = false;
            dashboardRestartTimer.restart();
        }
    }

    function parseDashboard(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (!(raw.indexOf("{") === 0 || raw.indexOf("[") === 0)) {
            return;
        }

        try {
            dashboard = JSON.parse(raw);
            pruneSessionClosePending();
            const current = stringOrEmpty(dashboard.current_ai_session_key);
            if (current) {
                selectedSessionKey = current;
            }
            if (launcherVisible && (launcherMode === "projects" || launcherMode === "sessions" || launcherMode === "windows")) {
                restartLauncherQuery();
            }
        } catch (error) {
            console.warn("Failed to parse dashboard payload", error, raw);
        }
    }

    function parseNotification(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            notificationState = JSON.parse(raw);
        } catch (error) {
            console.warn("Failed to parse notification payload", error, raw);
        }
    }

    function parseNetwork(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            networkState = JSON.parse(raw);
        } catch (error) {
            console.warn("Failed to parse network payload", error, raw);
        }
    }

    function parseDaemonHealth(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw.indexOf("{") !== 0) {
            return;
        }
        try {
            daemonHealthState = Object.assign({}, daemonHealthState, JSON.parse(raw));
        } catch (error) {
            console.warn("Failed to parse daemon health payload", error, raw);
        }
    }

    function daemonHealthLabel() {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return "Daemon";
        if (status === "degraded") return "Daemon !";
        if (status === "unhealthy") return "Daemon !!";
        if (status === "dead" || status === "unreachable") return "Daemon X";
        return "Daemon ?";
    }

    function daemonHealthColor(hovered) {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return neutralChipFill(hovered);
        if (status === "degraded") return hovered ? Qt.lighter(colors.amberBg, 1.15) : colors.amberBg;
        return hovered ? Qt.lighter(colors.redBg, 1.15) : colors.redBg;
    }

    function daemonHealthBorderColor(hovered) {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return neutralChipBorder(hovered);
        if (status === "degraded") return colors.amber;
        return colors.red;
    }

    function daemonHealthTextColor(hovered) {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return neutralChipText(hovered);
        if (status === "degraded") return hovered ? colors.amber : colors.subtle;
        return hovered ? colors.red : colors.subtle;
    }

    function daemonHealthDotColor() {
        const status = stringOrEmpty(daemonHealthState.status);
        if (status === "healthy") return colors.green;
        if (status === "degraded") return colors.amber;
        if (status === "dead" || status === "unreachable") return colors.red;
        return colors.muted;
    }

    function daemonHealthTooltip() {
        const s = daemonHealthState;
        const bits = [
            "Status: " + stringOrEmpty(s.status),
            "Events: " + String(s.events || 0),
            "Errors: " + String(s.errors || 0),
            "Memory: " + String(s.memory_mb || 0) + " MB"
        ];
        if (s.last_error) {
            bits.push("Last error: " + String(s.last_error));
        }
        return bits.join("\n");
    }

    function parseSystemStats(payload) {
        const raw = stringOrEmpty(payload).trim();
        if (!raw || raw === "undefined" || raw === "null") {
            return;
        }
        if (raw.indexOf("{") !== 0) {
            return;
        }

        try {
            systemStatsState = Object.assign({}, systemStatsState, JSON.parse(raw));
        } catch (error) {
            console.warn("Failed to parse system stats payload", error, raw);
        }
    }

    Controllers.RuntimeServices {
        id: runtimeServices
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        assistantService: assistantService
    }


    Variants {
        model: Quickshell.screens
        delegate: Windows.TopBarWindow {
            shellRoot: shellRootRef
            runtimeConfig: shellConfig
            colors: shellRootRef.colors
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Windows.BottomBarWindow {
            shellRoot: shellRootRef
            runtimeConfig: shellConfig
            colors: shellRootRef.colors
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Windows.ToastWindow {
            shellRoot: shellRootRef
            runtimeConfig: shellConfig
            colors: shellRootRef.colors
        }
    }

    Windows.NotificationDetailWindow {
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.LauncherWindow {
        id: launcherWindow
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.SettingsWindow {
        id: settingsWindow
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
    }

    Windows.RuntimePanelWindow {
        shellRoot: shellRootRef
        runtimeConfig: shellConfig
        colors: shellRootRef.colors
        assistantService: assistantService
    }
}
