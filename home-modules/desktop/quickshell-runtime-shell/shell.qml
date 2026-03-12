import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.I3
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    ShellConfig {
        id: shellConfig
    }

    property var dashboard: ({
        status: "loading",
        active_context: {},
        active_ai_sessions: [],
        active_ai_sessions_mru: [],
        current_ai_session_key: "",
        outputs: [],
        projects: [],
        scratchpad: {},
        state_health: {},
        total_windows: 0
    })
    property bool panelVisible: true
    property bool dockedMode: true
    property string lastFocusedSessionKey: ""
    property string selectedSessionKey: ""
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
        red: "#fda4af",
        redBg: "#3b1820",
        violet: "#c4b5fd",
        violetBg: "#241b43"
    })

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

    function activeSessions() {
        return arrayOrEmpty(dashboard.active_ai_sessions);
    }

    function sessionMru() {
        const mru = arrayOrEmpty(dashboard.active_ai_sessions_mru);
        return mru.length ? mru : activeSessions();
    }

    function compactSessions() {
        return sessionMru().slice(0, 10);
    }

    function primaryOutputCandidates() {
        return arrayOrEmpty(shellConfig.primaryOutputs).map((value) => stringOrEmpty(value)).filter((value) => value);
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

    function currentLayoutLabel() {
        const displayLayout = dashboard.display_layout || {};
        const layout = stringOrEmpty(displayLayout.current_layout);
        if (layout) {
            return layout;
        }
        return primaryOutputName || "Display";
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

    function flatWindowItems() {
        const items = [];
        const projects = arrayOrEmpty(dashboard.projects);

        for (let i = 0; i < projects.length; i += 1) {
            const projectGroup = projects[i];
            const windows = arrayOrEmpty(projectGroup.windows);

            if (i > 0) {
                items.push({ kind: "gap" });
            }

            items.push({
                kind: "project",
                project: projectGroup.project,
                execution_mode: projectGroup.execution_mode,
                focused: !!projectGroup.focused,
                window_count: Number(projectGroup.window_count || 0),
                has_windows: windows.length > 0
            });

            for (let j = 0; j < windows.length; j += 1) {
                const windowData = windows[j];
                items.push({
                    kind: "window",
                    group_project: projectGroup.project,
                    group_execution_mode: projectGroup.execution_mode,
                    group_focused: !!projectGroup.focused,
                    group_window_count: windows.length,
                    is_first_window: j === 0,
                    is_last_window: j === windows.length - 1,
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
                    hidden: !!windowData.hidden,
                    floating: !!windowData.floating,
                    scope: windowData.scope,
                    sessions: arrayOrEmpty(windowData.sessions),
                    ai_session_count: Number(windowData.ai_session_count || 0)
                });
            }
        }

        return items;
    }

    function currentSessionKey() {
        return stringOrEmpty(dashboard.current_ai_session_key || selectedSessionKey);
    }

    function projectDisplayName(projectName) {
        const project = stringOrEmpty(projectName);
        if (!project || project === "global") {
            return "Global Apps";
        }
        return shortProject(project);
    }

    function projectSubtitle(item) {
        if (!item) {
            return "";
        }

        const count = Number(item.window_count || 0);
        const countLabel = count === 1 ? "1 window" : String(count) + " windows";

        if (stringOrEmpty(item.project) === "global") {
            return "Shared across contexts";
        }

        return modeLabel(item.execution_mode) + "  " + countLabel;
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

    function sessionAccentColor(session) {
        if (sessionNeedsAttention(session)) {
            return stageState(session) === "attention" ? colors.red : colors.amber;
        }
        if (boolOrFalse(session.output_unseen) || boolOrFalse(session.output_ready)) {
            return colors.accent;
        }
        if (stringOrEmpty(session.stage_visual_state) === "working") {
            return stageColor(session);
        }
        if (boolOrFalse(session.remote_source_stale)) {
            return colors.subtle;
        }
        return colors.blueMuted;
    }

    function sessionTint(session) {
        if (sessionNeedsAttention(session)) {
            return stageState(session) === "attention" ? colors.redBg : colors.amberBg;
        }
        if (boolOrFalse(session.output_unseen) || boolOrFalse(session.output_ready)) {
            return colors.accentBg;
        }
        if (stringOrEmpty(session.stage_visual_state) === "working") {
            return stageBackground(session);
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
        return boolOrFalse(session.needs_user_action) || stageState(session) === "attention" || stageState(session) === "waiting";
    }

    function sessionHasMotion(session) {
        return stringOrEmpty(session.stage_visual_state) === "working";
    }

    function sessionGlyph(session) {
        const stage = stageState(session);
        if (stage === "attention") {
            return "!";
        }
        if (stage === "waiting") {
            return "⌨";
        }
        if (stage === "ready") {
            return "✓";
        }
        if (stringOrEmpty(session.stage).toLowerCase() === "streaming") {
            return "⋯";
        }
        if (stringOrEmpty(session.stage).toLowerCase() === "tool_running") {
            return "↺";
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
        const host = stringOrEmpty(session.host_name);
        if (!host) {
            return root.modeLabel(session.execution_mode);
        }
        return host;
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

    function sessionDetailLine(session) {
        const bits = [];
        const host = sessionHostLabel(session);
        const pane = sessionPaneLabel(session);
        const detail = stringOrEmpty(session.stage_detail);
        if (host) {
            bits.push(host);
        }
        if (pane) {
            bits.push(pane);
        }
        if (detail) {
            bits.push(detail);
        }
        return bits.join(" • ");
    }

    function metricMemoryLabel(session) {
        const raw = session.process_tree_rss_mb !== undefined && session.process_tree_rss_mb !== null
            ? session.process_tree_rss_mb
            : session.rss_mb;
        if (raw === undefined || raw === null) {
            return "RAM --";
        }
        const value = Number(raw);
        if (!isFinite(value) || value <= 0) {
            return "RAM --";
        }
        return "RAM " + Math.round(value) + "M";
    }

    function metricCpuLabel(session) {
        const raw = session.process_tree_cpu_percent !== undefined && session.process_tree_cpu_percent !== null
            ? session.process_tree_cpu_percent
            : session.cpu_percent;
        if (raw === undefined || raw === null) {
            return "CPU --";
        }
        const value = Number(raw);
        if (!isFinite(value) || value < 0) {
            return "CPU --";
        }
        return "CPU " + Math.round(value) + "%";
    }

    function metricProcessLabel(session) {
        const count = Number(session.process_count || 0);
        if (!count) {
            return "P --";
        }
        return "P " + String(count);
    }

    function sessionStageChipLabel(session) {
        const label = stringOrEmpty(session.stage_label);
        if (label) {
            return label;
        }
        return "Idle";
    }

    function sessionCardFill(session) {
        if (sessionIsCurrent(session)) {
            return sessionTint(session);
        }
        return colors.cardAlt;
    }

    function sessionCardBorder(session) {
        if (sessionIsCurrent(session)) {
            return sessionAccentColor(session);
        }
        if (sessionNeedsAttention(session)) {
            return colors.lineSoft;
        }
        return colors.border;
    }

    function sessionTextColor(session) {
        return sessionIsCurrent(session) ? colors.text : colors.textDim;
    }

    function sessionIsCurrent(session) {
        return (boolOrFalse(session.is_current_window) && boolOrFalse(session.pane_active))
            || currentSessionKey() === stringOrEmpty(session.session_key);
    }

    function sessionHasConflict(session) {
        return stringOrEmpty(session.conflict_state).length > 0;
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
        const project = stringOrEmpty(windowData.project);
        const workspace = stringOrEmpty(windowData.workspace);

        if (project && project !== "global") {
            bits.push(shortProject(project));
        }

        if (workspace && workspace.indexOf("scratchpad") !== 0) {
            bits.push("WS " + workspace);
        } else if (windowData.hidden) {
            bits.push("Hidden");
        }

        return bits.join(" • ");
    }

    function sessionBadge(windowData) {
        const sessions = arrayOrEmpty(windowData.sessions);
        if (!sessions.length) {
            return "";
        }

        const session = sessions[0];
        const tool = stringOrEmpty(session.display_tool || session.tool).toUpperCase();
        const stage = stringOrEmpty(session.stage_label || session.stage);
        return stage ? tool + " " + stage : tool;
    }

    function iconSourceFor(windowData) {
        const absolute = stringOrEmpty(windowData.icon_path);
        if (absolute) {
            return "file://" + absolute;
        }

        const candidates = [
            stringOrEmpty(windowData.app_key),
            stringOrEmpty(windowData.app_name),
            "application-x-executable"
        ];

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

    function runDetached(command) {
        if (!command || !command.length) {
            return;
        }
        Quickshell.execDetached(command);
    }

    function focusSession(sessionKey) {
        if (!sessionKey) {
            return;
        }

        const current = currentSessionKey();
        if (current && current !== sessionKey) {
            lastFocusedSessionKey = current;
        }

        selectedSessionKey = sessionKey;
        runDetached([shellConfig.i3pmBin, "session", "focus", sessionKey]);
    }

    function cycleSessions(direction) {
        const sessions = sessionMru();
        if (!sessions.length) {
            return;
        }

        const current = currentSessionKey();
        let index = sessions.findIndex((item) => stringOrEmpty(item.session_key) === current);
        if (index < 0) {
            index = 0;
        }

        const delta = direction === "prev" ? -1 : 1;
        const nextIndex = (index + delta + sessions.length) % sessions.length;
        focusSession(stringOrEmpty(sessions[nextIndex].session_key));
    }

    function focusLastSession() {
        if (lastFocusedSessionKey) {
            focusSession(lastFocusedSessionKey);
            return;
        }

        const sessions = sessionMru();
        if (sessions.length) {
            focusSession(stringOrEmpty(sessions[0].session_key));
        }
    }

    function focusWindow(windowData) {
        if (!windowData) {
            return;
        }

        const windowId = Number(windowData.id || windowData.window_id || 0);
        if (!windowId) {
            return;
        }

        const command = [shellConfig.i3pmBin, "window", "focus", String(windowId)];
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

    function ensureProject(projectName) {
        const name = stringOrEmpty(projectName);
        if (!name || name === "global") {
            runDetached([shellConfig.i3pmBin, "context", "clear"]);
            return;
        }
        runDetached([shellConfig.i3pmBin, "context", "ensure", name]);
    }

    function cycleDisplayLayout() {
        runDetached([shellConfig.i3pmBin, "display", "cycle"]);
    }

    function parseDashboard(payload) {
        if (!payload || !payload.trim()) {
            return;
        }

        try {
            dashboard = JSON.parse(payload);
            const current = stringOrEmpty(dashboard.current_ai_session_key);
            if (current) {
                selectedSessionKey = current;
            }
        } catch (error) {
            console.warn("Failed to parse dashboard payload", error, payload);
        }
    }

    Timer {
        id: dashboardRestartTimer
        interval: 1000
        repeat: false
        onTriggered: dashboardWatcher.running = true
    }

    Process {
        id: dashboardWatcher
        command: [shellConfig.i3pmBin, "dashboard", "watch", "--interval", String(shellConfig.dashboardHeartbeatMs)]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.parseDashboard(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (data && data.trim()) {
                    console.warn("dashboard.watch:", data);
                }
            }
        }
        onExited: function() {
            dashboardRestartTimer.restart();
        }
    }

    IpcHandler {
        target: "shell"

        function togglePanel() {
            root.panelVisible = !root.panelVisible;
        }

        function toggleDockMode() {
            root.dockedMode = !root.dockedMode;
        }

        function showWindowsTab() {
            root.panelVisible = true;
        }

        function showSessionsTab() {
            root.panelVisible = true;
        }

        function showHealthTab() {
            root.panelVisible = true;
        }

        function nextSession() {
            root.cycleSessions("next");
        }

        function prevSession() {
            root.cycleSessions("prev");
        }

        function focusLastSession() {
            root.focusLastSession();
        }
    }

    Component {
        id: perScreenBarWindow

        PanelWindow {
            required property var modelData
            readonly property var barScreen: modelData
            readonly property string barOutputName: root.screenOutputName(barScreen)

            screen: barScreen
            visible: shellConfig.perMonitorBars
            color: "transparent"
            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            implicitHeight: shellConfig.barHeight
            exclusiveZone: implicitHeight
            focusable: false
            aboveWindows: true
            WlrLayershell.namespace: "i3pm-runtime-bar-" + (barOutputName || "screen")
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: colors.bg
                border.color: colors.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 5
                    anchors.bottomMargin: 5
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 184
                        Layout.fillHeight: true
                        radius: 8
                        color: colors.card
                        border.color: colors.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Rectangle {
                                width: 7
                                height: 7
                                radius: 4
                                color: stringOrEmpty((dashboard.active_context || {}).execution_mode) === "ssh" ? colors.amber : colors.accent
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.currentContextTitle()
                                color: colors.text
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                text: barOutputName || root.modeLabel((dashboard.active_context || {}).execution_mode)
                                color: colors.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: workspaceRow.implicitWidth
                        contentHeight: workspaceRow.implicitHeight

                        Row {
                            id: workspaceRow
                            spacing: 6

                            Repeater {
                                model: root.workspacesForScreen(barScreen)

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var workspace: modelData
                                    readonly property var workspaceIcons: root.workspaceIconSources(root.workspaceLabel(workspace))
                                    readonly property int workspaceCount: root.workspaceWindowCount(root.workspaceLabel(workspace))
                                    width: Math.max(34, workspaceText.implicitWidth + (workspaceIcons.length ? 30 : 0) + (workspaceCount > 1 ? 14 : 0) + 12)
                                    height: 28
                                    radius: 8
                                    color: workspace.focused ? colors.blue : (workspace.active ? colors.card : colors.cardAlt)
                                    border.color: workspace.focused ? colors.blue : (workspace.urgent ? colors.red : colors.border)
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 5
                                        anchors.rightMargin: 5
                                        spacing: 2

                                        Row {
                                            spacing: -5
                                            visible: workspaceIcons.length > 0

                                            Repeater {
                                                model: workspaceIcons

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: 18
                                                    height: 18
                                                    radius: 6
                                                    color: colors.bg
                                                    border.color: workspace.focused ? colors.blue : colors.borderStrong
                                                    border.width: 1

                                                    IconImage {
                                                        anchors.centerIn: parent
                                                        implicitSize: 14
                                                        source: String(modelData)
                                                        visible: source !== ""
                                                        mipmap: true
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            id: workspaceText
                                            text: root.workspaceLabel(workspace)
                                            color: workspace.focused ? colors.bg : colors.text
                                            font.pixelSize: 11
                                            font.weight: workspace.focused ? Font.DemiBold : Font.Medium
                                        }

                                        Rectangle {
                                            visible: workspaceCount > 1
                                            width: 12
                                            height: 12
                                            radius: 4
                                            color: workspace.focused ? colors.bg : colors.card
                                            border.color: workspace.focused ? colors.bg : colors.border
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: String(workspaceCount)
                                                color: workspace.focused ? colors.blue : colors.muted
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: workspace.activate()
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 214
                        Layout.fillHeight: true
                        radius: 8
                        color: colors.card
                        border.color: colors.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: root.currentLayoutLabel()
                                color: colors.muted
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                width: 38
                                height: 24
                                radius: 7
                                color: colors.cardAlt
                                border.color: colors.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "Next"
                                    color: colors.text
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.cycleDisplayLayout()
                                }
                            }

                            Text {
                                text: String(root.activeSessions().length) + " AI"
                                color: colors.text
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 7
                                color: root.panelVisible ? colors.blue : colors.cardAlt
                                border.color: root.panelVisible ? colors.blue : colors.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: root.panelVisible ? "Hide" : "Open"
                                    color: root.panelVisible ? colors.bg : colors.text
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.panelVisible = !root.panelVisible
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: perScreenBarWindow
    }

    PanelWindow {
        id: panelWindow
        screen: root.primaryScreen
        visible: root.panelVisible && root.primaryScreen !== null
        color: "transparent"
        implicitWidth: shellConfig.panelWidth
        anchors.top: true
        anchors.bottom: true
        anchors.right: true
        exclusiveZone: root.dockedMode ? width : 0
        focusable: true
        aboveWindows: root.dockedMode
        WlrLayershell.namespace: "i3pm-runtime-panel"
        WlrLayershell.layer: root.dockedMode ? WlrLayer.Top : WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Rectangle {
            anchors.fill: parent
            color: colors.bg
            border.color: colors.border
            border.width: 1

            ColumnLayout {
                id: panelColumn
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 10

                Rectangle {
                    implicitHeight: headerContent.implicitHeight + 16
                    Layout.fillWidth: true
                    radius: 12
                    color: colors.panel
                    border.color: colors.border
                    border.width: 1

                    ColumnLayout {
                        id: headerContent
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        anchors.topMargin: 9
                        anchors.bottomMargin: 9
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: root.currentContextTitle()
                                    color: colors.text
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: shellConfig.hostName + "  " + root.modeLabel((dashboard.active_context || {}).execution_mode) + "  " + root.currentLayoutLabel()
                                    color: colors.muted
                                    font.pixelSize: 10
                                }
                            }

                            Rectangle {
                                width: 52
                                height: 24
                                radius: 7
                                color: colors.card
                                border.color: colors.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "Cycle"
                                    color: colors.text
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.cycleDisplayLayout()
                                }
                            }

                            Rectangle {
                                width: 58
                                height: 24
                                radius: 7
                                color: root.dockedMode ? colors.blueBg : colors.card
                                border.color: root.dockedMode ? colors.blue : colors.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: root.dockedMode ? "Dock" : "Float"
                                    color: root.dockedMode ? colors.blue : colors.text
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.dockedMode = !root.dockedMode
                                }
                            }

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 7
                                color: colors.card
                                border.color: colors.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: colors.text
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.panelVisible = false
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: [
                                    { label: "Projects", value: String(arrayOrEmpty(dashboard.projects).length) },
                                    { label: "Windows", value: String(Number(dashboard.total_windows || 0)) },
                                    { label: "AI", value: String(root.activeSessions().length) }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 8
                                    color: colors.card
                                    border.color: colors.border
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Text {
                                            text: modelData.value
                                            color: colors.text
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }

                                        Text {
                                            text: modelData.label
                                            color: colors.muted
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    readonly property int visibleSessionRows: Math.min(4, Math.max(1, root.compactSessions().length))
                    implicitHeight: 16 + (visibleSessionRows * 42) + (Math.max(0, visibleSessionRows - 1) * 6)
                    Layout.preferredHeight: implicitHeight
                    Layout.fillWidth: true
                    visible: root.compactSessions().length > 0
                    radius: 12
                    color: colors.panel
                    border.color: colors.border
                    border.width: 1

                    ScriptModel {
                        id: sessionCardsModel
                        values: root.compactSessions()
                        objectProp: "modelData"
                    }

                    ListView {
                        id: sessionGrid
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        clip: true
                        spacing: 6
                        model: sessionCardsModel
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var session: modelData
                            width: sessionGrid.width
                            height: 42
                            radius: 10
                            color: root.sessionCardFill(session)
                            border.color: root.sessionCardBorder(session)
                            border.width: 1
                            opacity: root.sessionIsCurrent(session) ? 1 : 0.92

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 7

                                Item {
                                    width: 24
                                    height: 24

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        radius: 7
                                        color: colors.bg
                                        border.color: root.sessionIsCurrent(session) ? root.sessionAccentColor(session) : colors.lineSoft
                                        border.width: 1
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        radius: 7
                                        color: "transparent"
                                        border.color: root.sessionAccentColor(session)
                                        border.width: 1
                                        opacity: root.sessionHasMotion(session) ? 0.24 : 0
                                        scale: root.sessionHasMotion(session) ? 0.92 : 1

                                        SequentialAnimation on scale {
                                            running: root.sessionHasMotion(session)
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.94; to: 1.08; duration: 900; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 1.08; to: 0.94; duration: 900; easing.type: Easing.InOutQuad }
                                        }

                                        SequentialAnimation on opacity {
                                            running: root.sessionHasMotion(session)
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.26; to: 0.08; duration: 900; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.08; to: 0.26; duration: 900; easing.type: Easing.InOutQuad }
                                        }
                                    }

                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: 13
                                        source: root.toolIconSource(session)
                                        mipmap: true
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.rightMargin: -1
                                        anchors.bottomMargin: -1
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: root.sessionAccentColor(session)
                                        border.color: colors.bg
                                        border.width: 1
                                        opacity: root.sessionHasMotion(session) ? 1 : 0.8
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.shortProject(session.project_name || session.project)
                                            color: root.sessionTextColor(session)
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            visible: root.sessionPaneLabel(session).length > 0
                                            height: 15
                                            radius: 5
                                            color: colors.bg
                                            border.color: colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: paneLabelText.implicitWidth + 10

                                            Text {
                                                id: paneLabelText
                                                anchors.centerIn: parent
                                                text: root.sessionPaneLabel(session)
                                                color: colors.subtle
                                                font.pixelSize: 7
                                                font.weight: Font.Medium
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.sessionDetailLine(session)
                                        color: root.sessionIsCurrent(session) ? colors.muted : colors.subtle
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    height: 16
                                    radius: 5
                                    color: root.sessionTint(session)
                                    border.color: root.sessionAccentColor(session)
                                    border.width: 1
                                    Layout.preferredWidth: stageChipText.implicitWidth + 12

                                    Text {
                                        id: stageChipText
                                        anchors.centerIn: parent
                                        text: root.sessionStageChipLabel(session)
                                        color: root.sessionAccentColor(session)
                                        font.pixelSize: 7
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Rectangle {
                                    height: 16
                                    radius: 5
                                    color: colors.bg
                                    border.color: colors.lineSoft
                                    border.width: 1
                                    Layout.preferredWidth: memChipText.implicitWidth + 12

                                    Text {
                                        id: memChipText
                                        anchors.centerIn: parent
                                        text: root.metricMemoryLabel(session)
                                        color: root.sessionIsCurrent(session) ? colors.textDim : colors.subtle
                                        font.pixelSize: 7
                                        font.weight: Font.Medium
                                    }
                                }

                                Rectangle {
                                    height: 16
                                    radius: 5
                                    color: colors.bg
                                    border.color: colors.lineSoft
                                    border.width: 1
                                    Layout.preferredWidth: cpuChipText.implicitWidth + 12

                                    Text {
                                        id: cpuChipText
                                        anchors.centerIn: parent
                                        text: root.metricCpuLabel(session)
                                        color: root.sessionIsCurrent(session) ? colors.textDim : colors.subtle
                                        font.pixelSize: 7
                                        font.weight: Font.Medium
                                    }
                                }

                                Rectangle {
                                    height: 16
                                    radius: 5
                                    color: colors.bg
                                    border.color: colors.lineSoft
                                    border.width: 1
                                    Layout.preferredWidth: procChipText.implicitWidth + 12

                                    Text {
                                        id: procChipText
                                        anchors.centerIn: parent
                                        text: root.metricProcessLabel(session)
                                        color: root.sessionIsCurrent(session) ? colors.textDim : colors.subtle
                                        font.pixelSize: 7
                                        font.weight: Font.Medium
                                    }
                                }

                                Rectangle {
                                    visible: root.sessionIsCurrent(session)
                                    width: visible ? currentSessionChip.implicitWidth + 10 : 0
                                    height: 16
                                    radius: 5
                                    color: colors.blueBg
                                    border.color: colors.blueMuted
                                    border.width: 1

                                    Text {
                                        id: currentSessionChip
                                        anchors.centerIn: parent
                                        text: "Now"
                                        color: colors.blue
                                        font.pixelSize: 7
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Rectangle {
                                    visible: root.sessionHasConflict(session)
                                    width: visible ? conflictChipText.implicitWidth + 10 : 0
                                    height: 16
                                    radius: 5
                                    color: colors.redBg
                                    border.color: colors.lineSoft
                                    border.width: 1

                                    Text {
                                        id: conflictChipText
                                        anchors.centerIn: parent
                                        text: "Conflict"
                                        color: colors.red
                                        font.pixelSize: 7
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Rectangle {
                                    visible: root.stringOrEmpty(session.execution_mode) === "ssh"
                                    width: visible ? sshChipText.implicitWidth + 10 : 0
                                    height: 16
                                    radius: 5
                                    color: colors.amberBg
                                    border.color: colors.lineSoft
                                    border.width: 1

                                    Text {
                                        id: sshChipText
                                        anchors.centerIn: parent
                                        text: "SSH"
                                        color: colors.amber
                                        font.pixelSize: 7
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.focusSession(root.stringOrEmpty(session.session_key))
                            }
                        }
                    }
                }

                ScriptModel {
                    id: windowItemsModel
                    values: root.flatWindowItems()
                    objectProp: "modelData"
                }

                ListView {
                    id: windowsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    model: windowItemsModel
                    cacheBuffer: 1200

                    delegate: Item {
                        required property var modelData
                        width: windowsList.width
                        height: modelData.kind === "gap" ? 14 : (modelData.kind === "project" ? 42 : 38)

                        Item {
                            visible: modelData.kind === "gap"
                            anchors.fill: parent
                        }

                        Rectangle {
                            visible: modelData.kind === "project"
                            anchors.fill: parent
                            radius: 12
                            color: modelData.focused ? colors.panelAlt : colors.cardAlt
                            border.color: modelData.focused ? colors.blueMuted : colors.lineSoft
                            border.width: 1
                            opacity: modelData.focused ? 1 : 0.9

                            Rectangle {
                                visible: !!modelData.focused
                                width: 3
                                radius: 2
                                color: colors.blue
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 6
                                anchors.topMargin: 6
                                anchors.bottomMargin: 6
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: modelData.focused ? 14 : 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Rectangle {
                                    visible: root.stringOrEmpty(modelData.project) !== "global"
                                    width: visible ? modeChipText.implicitWidth + 12 : 0
                                    height: 18
                                    radius: 6
                                    color: root.stringOrEmpty(modelData.execution_mode) === "ssh" ? colors.amberBg : colors.cardAlt
                                    border.color: root.stringOrEmpty(modelData.execution_mode) === "ssh" ? colors.amber : colors.lineSoft
                                    border.width: 1

                                    Text {
                                        id: modeChipText
                                        anchors.centerIn: parent
                                        text: root.modeLabel(modelData.execution_mode)
                                        color: root.stringOrEmpty(modelData.execution_mode) === "ssh" ? colors.amber : colors.subtle
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.projectDisplayName(modelData.project)
                                        color: modelData.focused ? colors.text : colors.textDim
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.stringOrEmpty(root.projectSubtitle(modelData))
                                        color: modelData.focused ? colors.muted : colors.subtle
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    visible: !!modelData.focused
                                    width: visible ? currentProjectText.implicitWidth + 14 : 0
                                    height: 17
                                    radius: 6
                                    color: colors.blueBg
                                    border.color: colors.blue
                                    border.width: 1

                                    Text {
                                        id: currentProjectText
                                        anchors.centerIn: parent
                                        text: "Current"
                                        color: colors.blue
                                        font.pixelSize: 8
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Rectangle {
                                    width: projectCountText.implicitWidth + 14
                                    height: 17
                                    radius: 6
                                    color: colors.bg
                                    border.color: colors.lineSoft
                                    border.width: 1

                                    Text {
                                        id: projectCountText
                                        anchors.centerIn: parent
                                        text: String(Number(modelData.window_count || 0))
                                        color: modelData.focused ? colors.muted : colors.subtle
                                        font.pixelSize: 8
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.ensureProject(modelData.project)
                            }
                        }

                        Item {
                            visible: modelData.kind === "window"
                            anchors.fill: parent

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.right: parent.right
                                anchors.rightMargin: 1
                                anchors.verticalCenter: parent.verticalCenter
                                height: 34
                                radius: 10
                                color: modelData.focused ? colors.blueWash : colors.cardAlt
                                border.color: modelData.focused ? colors.blueMuted : colors.lineSoft
                                border.width: 1
                                opacity: modelData.focused ? 1 : 0.82

                                Rectangle {
                                    visible: !!modelData.focused
                                    width: 2
                                    radius: 1
                                    color: colors.blue
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 6
                                    anchors.topMargin: 7
                                    anchors.bottomMargin: 7
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: modelData.focused ? 14 : 12
                                    anchors.rightMargin: 7
                                    spacing: 8

                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 7
                                        color: colors.bg
                                        border.color: modelData.focused ? colors.blueMuted : colors.lineSoft
                                        border.width: 1

                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: 16
                                            source: root.iconSourceFor(modelData)
                                            visible: source !== ""
                                            mipmap: true
                                            opacity: modelData.focused ? 1 : 0.9
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: root.iconSourceFor(modelData) === ""
                                            text: root.appLabel(modelData).slice(0, 1).toUpperCase()
                                            color: modelData.focused ? colors.text : colors.textDim
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayTitle(modelData)
                                            color: modelData.focused ? colors.text : colors.textDim
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayMeta(modelData)
                                            visible: text.length > 0
                                            color: modelData.focused ? colors.muted : colors.subtle
                                            font.pixelSize: 8
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        visible: Number(modelData.ai_session_count || 0) > 0
                                        width: visible ? Math.min(84, aiText.implicitWidth + 12) : 0
                                        height: 16
                                        radius: 6
                                        color: colors.violetBg
                                        border.color: modelData.focused ? colors.violet : colors.lineSoft
                                        border.width: 1

                                        Text {
                                            id: aiText
                                            anchors.centerIn: parent
                                            text: root.sessionBadge(modelData) || (String(Number(modelData.ai_session_count || 0)) + " AI")
                                            color: colors.violet
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        visible: root.stringOrEmpty(modelData.execution_mode) === "ssh"
                                        width: visible ? 30 : 0
                                        height: 16
                                        radius: 6
                                        color: colors.amberBg
                                        border.color: modelData.focused ? colors.amber : colors.lineSoft
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "SSH"
                                            color: colors.amber
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 6
                                        color: colors.bg
                                        border.color: colors.lineSoft
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            color: modelData.focused ? colors.muted : colors.subtle
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                mouse.accepted = true;
                                                root.closeWindow(modelData);
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.focusWindow(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
