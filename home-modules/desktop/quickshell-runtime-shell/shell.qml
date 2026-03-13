import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.I3
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
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
    property var networkState: ({
        connected: false,
        kind: "offline",
        label: "Offline",
        signal: null
    })
    property bool panelVisible: true
    property bool dockedMode: true
    property bool powerMenuVisible: false
    property bool worktreePickerVisible: false
    property var expandedSessionGroups: ({})
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
            return stringOrEmpty(
                remote.host_alias
                || remote.host
                || context.host_alias
                || context.connection_key
            );
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
        return stableSortedSessions(activeSessions().filter((session) => sessionIsDisplayEligible(session)));
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

        return [
            stringOrEmpty(session && session.tool),
            stringOrEmpty(session && session.connection_key),
            stringOrEmpty(session && session.context_key),
            String(Number(session && session.window_id || 0)),
            String(Number(session && session.pid || 0)),
            String(Number(session && session.pane_pid || 0)),
            stringOrEmpty(session && session.pane_label)
        ].join("::");
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
        return firstNumber(
            session && session.tmux_pane,
            firstNumber(session && session.pane_label, 1000000)
        );
    }

    function sessionIsCurrentHost(session) {
        return boolOrFalse(session && session.is_current_host);
    }

    function sessionIsDisplayEligible(session) {
        if (!session || typeof session !== "object") {
            return false;
        }

        const terminalAnchor = stringOrEmpty(session.terminal_anchor_id);
        const hasTmuxIdentity = stringOrEmpty(session.tmux_session)
            && stringOrEmpty(session.tmux_window)
            && stringOrEmpty(session.tmux_pane);
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

    function stableSessionCompare(left, right) {
        let result = compareDescending(sessionIsCurrentHost(left) ? 1 : 0, sessionIsCurrentHost(right) ? 1 : 0);
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

        result = compareAscending(stringOrEmpty(left && left.tmux_session), stringOrEmpty(right && right.tmux_session));
        if (result !== 0) {
            return result;
        }

        result = compareAscending(stringOrEmpty(left && left.host_name), stringOrEmpty(right && right.host_name));
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

        return projects.find((projectGroup) =>
            stringOrEmpty(projectGroup.project) === project
            && stringOrEmpty(projectGroup.execution_mode || "local") === mode
        ) || null;
    }

    function focusPreferredWindowForContext(projectName, executionMode) {
        const projectGroup = projectGroupFor(projectName, executionMode);
        if (!projectGroup) {
            return false;
        }

        const windows = arrayOrEmpty(projectGroup.windows).filter((windowData) => !boolOrFalse(windowData.hidden));
        if (!windows.length) {
            return false;
        }

        const focusedWindow = windows.find((windowData) => boolOrFalse(windowData.focused));
        focusWindow(focusedWindow || windows[0]);
        return true;
    }

    function compactSessions() {
        return panelSessions().slice(0, 10);
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
        const nativeWorkspaces = workspacesForScreen(findScreenByOutputName(outputName));
        if (nativeWorkspaces.length > 0) {
            return nativeWorkspaces;
        }
        return dashboardWorkspacesForOutput(outputName);
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

    function topBarTimeText() {
        return Qt.formatDateTime(
            clock.date,
            shellConfig.topBarShowSeconds ? "ddd MMM d  h:mm:ss AP" : "ddd MMM d  h:mm AP"
        );
    }

    function neutralChipFill(hovered) {
        return hovered ? colors.card : colors.cardAlt;
    }

    function neutralChipBorder(hovered) {
        return hovered ? colors.borderStrong : colors.border;
    }

    function neutralChipText(hovered) {
        return hovered ? colors.text : colors.textDim;
    }

    function stateChipFill(active, hovered, activeFill) {
        return active ? activeFill : neutralChipFill(hovered);
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
        return stringOrEmpty(node.description || node.nickname || node.name || "Default audio");
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

    function batteryDevice() {
        return UPower.displayDevice;
    }

    function batteryReady() {
        const device = batteryDevice();
        return !!(device && device.ready && device.isPresent && device.isLaptopBattery);
    }

    function batteryLabel() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return "";
        }

        const percentage = Math.round(Number(device.percentage || 0));
        if (device.state === UPowerDeviceState.Charging) {
            return "Charging " + String(percentage) + "%";
        }
        if (device.state === UPowerDeviceState.FullyCharged) {
            return "Full " + String(percentage) + "%";
        }
        return "Battery " + String(percentage) + "%";
    }

    function batteryPercentValue() {
        const device = batteryDevice();
        if (!batteryReady()) {
            return 0;
        }
        return Math.round(Number(device.percentage || 0));
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
        if (Number(device.timeToEmpty || 0) > 0 && device.state === UPowerDeviceState.Discharging) {
            bits.push(Math.round(Number(device.timeToEmpty || 0) / 60) + " min left");
        } else if (Number(device.timeToFull || 0) > 0 && device.state === UPowerDeviceState.Charging) {
            bits.push(Math.round(Number(device.timeToFull || 0) / 60) + " min to full");
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
        const items = [{
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
        }];

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

    function panelWindowItems() {
        const items = [];
        const projects = arrayOrEmpty(dashboard.projects);

        const addGroup = function(sectionTitle, projectGroup, emphasize) {
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
            addGroup(
                project === "global" ? "Shared Windows" : shortProject(project),
                projectGroup,
                !!projectGroup.is_active
            );
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
        return projects.filter((projectGroup) => arrayOrEmpty(projectGroup && projectGroup.windows).length > 0);
    }

    function panelWindowCount() {
        let count = 0;
        const projects = panelProjects();
        for (let i = 0; i < projects.length; i += 1) {
            count += arrayOrEmpty(projects[i].windows).length;
        }
        return count;
    }

    function currentSessionKey() {
        return stringOrEmpty(dashboard.current_ai_session_key || selectedSessionKey);
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

        const pieces = host.split(/[^a-z0-9]+/).filter((part) => part.length > 0);
        if (!pieces.length) {
            return titleCaseWord(host);
        }
        return pieces.map((part) => titleCaseWord(part)).join(" ");
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
            if (phase === "done" && !sessionIsCurrent(session)) {
                return "needs_attention";
            }
            return phase;
        }
        if (boolOrFalse(session && session.output_unseen)
            || boolOrFalse(session && session.review_pending)
            || boolOrFalse(session && session.needs_user_action)) {
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
        if (phase === "done") {
            return colors.accent;
        }
        if (phase === "working") {
            return stageColor(session);
        }
        if (phase === "stale") {
            return colors.subtle;
        }
        return colors.blueMuted;
    }

    function sessionTint(session) {
        const phase = sessionPhase(session);
        if (phase === "needs_attention") {
            return colors.amberBg;
        }
        if (phase === "done") {
            return colors.accentBg;
        }
        if (phase === "working") {
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

        if (boolOrFalse(session && session.needs_user_action)
            || boolOrFalse(session && session.output_ready)
            || boolOrFalse(session && session.output_unseen)) {
            return false;
        }
        if (boolOrFalse(session && session.remote_source_stale) || freshness === "stale") {
            return false;
        }
        if (boolOrFalse(session && session.pulse_working)
            || boolOrFalse(session && session.is_streaming)
            || (Number.isFinite(pendingTools) && pendingTools > 0)) {
            return true;
        }
        if (statusReason === "process_keepalive" && !lastActivityAt.length) {
            return false;
        }

        return ["starting", "thinking", "tool_running", "streaming"].indexOf(stage) >= 0
            && (!Number.isFinite(ageSeconds) || ageSeconds <= 15)
            && freshness !== "stale";
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
        if (state === "done") {
            return colors.accent;
        }
        if (state === "working") {
            return root.sessionAccentColor(session);
        }
        if (state === "stale") {
            return colors.subtle;
        }
        return colors.muted;
    }

    function sessionBadgeBackground(session) {
        const state = sessionBadgeState(session);
        if (state === "needs_attention") {
            return colors.amberBg;
        }
        if (state === "done") {
            return colors.accentBg;
        }
        if (state === "working") {
            return root.sessionIsCurrent(session) ? colors.bg : colors.cardAlt;
        }
        if (state === "stale") {
            return colors.bg;
        }
        return colors.cardAlt;
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

    function sessionBadgeLabel(session) {
        const state = sessionBadgeState(session);
        if (state === "working") {
            return "Working";
        }
        if (state === "needs_attention") {
            return "Needs attention";
        }
        if (state === "done") {
            return "Done";
        }
        return sessionAgeCompactLabel(session);
    }

    function sessionBadgeSymbol(session) {
        const state = sessionBadgeState(session);
        if (state === "needs_attention") {
            return "!";
        }
        if (state === "done") {
            return "✓";
        }
        if (state === "working") {
            return "◔";
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
        if (badgeState === "done") {
            return "Done";
        }
        if (badgeState === "working") {
            return "Working";
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
        return (boolOrFalse(session.is_current_window) && boolOrFalse(session.pane_active))
            || currentSessionKey() === stringOrEmpty(session.session_key);
    }

    function sessionHasConflict(session) {
        return stringOrEmpty(session.conflict_state).length > 0;
    }

    function sessionPillLabel(session) {
        const pane = sessionPaneLabel(session);
        if (pane) {
            return pane;
        }
        return compactSessionStateLabel(session);
    }

    function sessionPrimaryLabel(session) {
        const pane = sessionPaneLabel(session);
        if (pane) {
            return pane;
        }
        const tool = toolLabel(session);
        return tool ? tool + " Session" : "AI Session";
    }

    function sessionSecondaryLabel(session) {
        const bits = [];
        const pane = sessionPaneLabel(session);
        const paneLocator = sessionPaneLocatorLabel(session);
        const pid = sessionPidLabel(session);

        if (!pane) {
            const tool = toolLabel(session);
            if (tool) {
                bits.push(tool);
            }
        }
        if (paneLocator) {
            bits.push(paneLocator);
        }
        if (pid) {
            bits.push(pid);
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
            const hostKey = stringOrEmpty(session.connection_key || session.host_name || "unknown");
            const groupKey = hostKey || "unknown";

            let group = index[groupKey];
            if (!group) {
                group = {
                    group_key: groupKey,
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
                let result = compareAscending(stringOrEmpty(left && left.project_name), stringOrEmpty(right && right.project_name));
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

            result = compareAscending(stringOrEmpty(left && left.host_name), stringOrEmpty(right && right.host_name));
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
        return displayHostName(group.host_name || group.raw_host_name || "Unknown");
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
        const sessions = panelSessions();
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

        const sessions = panelSessions();
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
            const current = stringOrEmpty(dashboard.current_ai_session_key);
            if (current) {
                selectedSessionKey = current;
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

    SystemClock {
        id: clock
        precision: shellConfig.topBarShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Timer {
        id: dashboardRestartTimer
        interval: 1000
        repeat: false
        onTriggered: dashboardWatcher.running = true
    }

    Timer {
        id: notificationRestartTimer
        interval: 2000
        repeat: false
        onTriggered: notificationWatcher.running = true
    }

    Timer {
        id: networkRefreshTimer
        interval: 15000
        repeat: false
        onTriggered: networkWatcher.running = true
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

    Process {
        id: notificationWatcher
        command: [shellConfig.notificationMonitorBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.parseNotification(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (data && data.trim()) {
                    console.warn("notification.watch:", data);
                }
            }
        }
        onExited: function() {
            notificationRestartTimer.restart();
        }
    }

    Process {
        id: networkWatcher
        command: [shellConfig.networkStatusBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.parseNetwork(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (data && data.trim()) {
                    console.warn("network.watch:", data);
                }
            }
        }
        onExited: function() {
            networkRefreshTimer.restart();
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

        function togglePowerMenu() {
            root.powerMenuVisible = !root.powerMenuVisible;
        }
    }

    Component {
        id: perScreenTopBarWindow

        PanelWindow {
            id: topBarWindow
            required property var modelData
            readonly property var topBarScreen: modelData
            readonly property string topOutputName: root.screenOutputName(topBarScreen)
            readonly property bool isPrimaryBar: root.isPrimaryOutput(topOutputName)
            readonly property bool isFocusedBar: root.isFocusedOutput(topOutputName)

            screen: topBarScreen
            visible: topBarScreen !== null
            color: "transparent"
            anchors.left: true
            anchors.right: true
            anchors.top: true
            implicitHeight: shellConfig.topBarHeight
            exclusiveZone: implicitHeight
            focusable: false
            aboveWindows: true
            WlrLayershell.namespace: "i3pm-runtime-top-bar-" + (topOutputName || "screen")
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: topBarBackground
                anchors.fill: parent
                color: topBarWindow.isFocusedBar ? colors.panel : colors.bg
                border.color: topBarWindow.isFocusedBar ? colors.blueMuted : colors.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            radius: 8
                            color: colors.card
                            border.color: topBarWindow.isFocusedBar ? colors.blueMuted : colors.border
                            border.width: 1
                            implicitWidth: outputLabel.implicitWidth + 16
                            implicitHeight: parent.height

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: topBarWindow.isFocusedBar ? colors.blue : colors.muted
                                }

                                Text {
                                    id: outputLabel
                                    text: topBarWindow.topOutputName || shellConfig.hostName
                                    color: colors.text
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Rectangle {
                            id: layoutChip
                            radius: 8
                            color: root.neutralChipFill(layoutMouse.containsMouse)
                            border.color: root.neutralChipBorder(layoutMouse.containsMouse)
                            border.width: 1
                            implicitWidth: layoutLabel.implicitWidth + 20
                            implicitHeight: parent.height

                            Behavior on color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Text {
                                id: layoutLabel
                                anchors.centerIn: parent
                                text: root.currentLayoutLabel()
                                color: root.neutralChipText(layoutMouse.containsMouse)
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: layoutMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cycleDisplayLayout()
                            }
                        }

                        Rectangle {
                            id: panelToggleChip
                            radius: 8
                            color: root.stateChipFill(root.panelVisible, panelToggleMouse.containsMouse, colors.blueBg)
                            border.color: root.stateChipBorder(root.panelVisible, panelToggleMouse.containsMouse, colors.blue)
                            border.width: 1
                            implicitWidth: panelToggleLabel.implicitWidth + 20
                            implicitHeight: parent.height

                            Behavior on color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Text {
                                id: panelToggleLabel
                                anchors.centerIn: parent
                                text: root.panelVisible ? "Hide Panel" : "Show Panel"
                                color: root.stateChipText(root.panelVisible, panelToggleMouse.containsMouse, colors.blue)
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: panelToggleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.panelVisible = !root.panelVisible
                            }
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        radius: 9
                        color: colors.card
                        border.color: colors.border
                        border.width: 1
                        implicitWidth: clockLabel.implicitWidth + 26
                        implicitHeight: parent.height

                        Text {
                            id: clockLabel
                            anchors.centerIn: parent
                            text: root.topBarTimeText()
                            color: colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        spacing: 6

                        Rectangle {
                            id: networkChip
                            radius: 8
                            color: root.neutralChipFill(networkMouse.containsMouse)
                            border.color: root.neutralChipBorder(networkMouse.containsMouse)
                            border.width: 1
                            implicitWidth: networkLabel.implicitWidth + 18
                            implicitHeight: parent.height

                            Behavior on color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Text {
                                id: networkLabel
                                anchors.centerIn: parent
                                text: root.networkLabel()
                                color: root.networkChipText(networkMouse.containsMouse)
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }

                            ToolTip.visible: networkMouse.containsMouse
                            ToolTip.text: root.networkDetail()

                            MouseArea {
                                id: networkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runDetached(["toggle-quick-panel"])
                            }
                        }

                        Rectangle {
                            id: notificationChip
                            radius: 8
                            color: root.notificationChipFill(notificationMouse.containsMouse)
                            border.color: root.notificationChipBorder(notificationMouse.containsMouse)
                            border.width: 1
                            implicitWidth: notificationLabel.implicitWidth + 18
                            implicitHeight: parent.height

                            Behavior on color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Text {
                                id: notificationLabel
                                anchors.centerIn: parent
                                text: root.notificationLabel()
                                color: root.notificationChipText(notificationMouse.containsMouse)
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }

                            ToolTip.visible: notificationMouse.containsMouse
                            ToolTip.text: root.notificationDetail()

                            MouseArea {
                                id: notificationMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        root.runDetached(["swaync-client", "-d", "-sw"]);
                                        return;
                                    }
                                    root.runDetached(["toggle-swaync"]);
                                }
                            }
                        }

                        Rectangle {
                            id: audioChip
                            radius: 8
                            color: root.neutralChipFill(audioMouse.containsMouse)
                            border.color: root.audioChipBorder(audioMouse.containsMouse)
                            border.width: 1
                            implicitWidth: audioLabel.implicitWidth + 18
                            implicitHeight: parent.height

                            Behavior on color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Text {
                                id: audioLabel
                                anchors.centerIn: parent
                                text: root.audioLabel()
                                color: root.audioChipText(audioMouse.containsMouse)
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }

                            ToolTip.visible: audioMouse.containsMouse
                            ToolTip.text: root.audioDetail()

                            MouseArea {
                                id: audioMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                onClicked: root.toggleMute()
                                onWheel: function(wheel) {
                                    root.changeVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
                                }
                            }
                        }

                        Rectangle {
                            id: batteryChip
                            visible: root.batteryReady()
                            radius: 8
                            color: root.neutralChipFill(batteryMouse.containsMouse)
                            border.color: root.batteryChipBorder(batteryMouse.containsMouse)
                            border.width: 1
                            implicitWidth: batteryRow.implicitWidth + 16
                            implicitHeight: parent.height

                            Behavior on color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            RowLayout {
                                id: batteryRow
                                anchors.centerIn: parent
                                spacing: 5

                                IconImage {
                                    implicitSize: 14
                                    source: root.batteryIconSource()
                                    visible: source !== ""
                                    mipmap: true
                                }

                                Text {
                                    text: root.batteryLabel()
                                    color: root.batteryChipText(batteryMouse.containsMouse)
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                            }

                            ToolTip.visible: batteryMouse.containsMouse
                            ToolTip.text: root.batteryTooltip()

                            MouseArea {
                                id: batteryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }

                        RowLayout {
                            visible: topBarWindow.isPrimaryBar && root.arrayOrEmpty(SystemTray.items ? SystemTray.items.values : []).length > 0
                            spacing: 4

                            Repeater {
                                model: SystemTray.items

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var trayItem: modelData
                                    visible: trayItem.status !== Status.Passive
                                    width: 24
                                    height: 22
                                    radius: 7
                                    color: root.neutralChipFill(trayMouse.containsMouse)
                                    border.color: root.neutralChipBorder(trayMouse.containsMouse)
                                    border.width: 1

                                    Behavior on color {
                                        ColorAnimation { duration: root.fastColorMs }
                                    }

                                    Behavior on border.color {
                                        ColorAnimation { duration: root.fastColorMs }
                                    }

                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: 14
                                        source: {
                                            const iconName = root.stringOrEmpty(trayItem.icon);
                                            return iconName ? Quickshell.iconPath(iconName, true) : "";
                                        }
                                        visible: source !== ""
                                        mipmap: true
                                    }

                                    MouseArea {
                                        id: trayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                trayItem.secondaryActivate();
                                                return;
                                            }

                                            if (trayItem.onlyMenu || trayItem.hasMenu) {
                                                const point = parent.mapToItem(topBarBackground, parent.width / 2, parent.height);
                                                trayItem.display(topBarWindow, point.x, point.y);
                                                return;
                                            }

                                            trayItem.activate();
                                        }
                                        onWheel: function(wheel) {
                                            trayItem.scroll(wheel.angleDelta.y > 0 ? 1 : -1, false);
                                        }
                                    }

                                    ToolTip.visible: trayMouse.containsMouse
                                    ToolTip.text: root.stringOrEmpty(trayItem.tooltipTitle || trayItem.title || trayItem.id)
                                }
                            }
                        }

                        Rectangle {
                            id: powerChip
                            visible: topBarWindow.isPrimaryBar
                            radius: 8
                            color: root.powerChipFill(powerMouse.containsMouse)
                            border.color: root.powerChipBorder(powerMouse.containsMouse)
                            border.width: 1
                            implicitWidth: powerLabel.implicitWidth + 18
                            implicitHeight: parent.height

                            Behavior on color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: root.fastColorMs }
                            }

                            Text {
                                id: powerLabel
                                anchors.centerIn: parent
                                text: "Power"
                                color: root.powerChipText(powerMouse.containsMouse)
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: powerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.powerMenuVisible = !root.powerMenuVisible
                            }
                        }
                    }
                }
            }

            PopupWindow {
                visible: topBarWindow.isPrimaryBar && root.powerMenuVisible
                color: "transparent"
                implicitWidth: 188
                implicitHeight: powerMenuContent.implicitHeight + 16
                anchor.window: topBarWindow
                anchor.item: powerChip
                anchor.edges: Edges.Bottom | Edges.Right
                anchor.gravity: Edges.Bottom | Edges.Left
                anchor.margins.top: 6

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: colors.panel
                    border.color: colors.borderStrong
                    border.width: 1

                    ColumnLayout {
                        id: powerMenuContent
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "Lock", command: ["swaylock", "-f"] },
                                { label: "Suspend", command: ["systemctl", "suspend"] },
                                { label: "Exit Sway", command: ["swaymsg", "exit"] },
                                { label: "Reboot", command: ["systemctl", "reboot"] },
                                { label: "Shutdown", command: ["systemctl", "poweroff"] }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 8
                                color: root.neutralChipFill(powerActionMouse.containsMouse)
                                border.color: root.neutralChipBorder(powerActionMouse.containsMouse)
                                border.width: 1

                                Behavior on color {
                                    ColorAnimation { duration: root.fastColorMs }
                                }

                                Behavior on border.color {
                                    ColorAnimation { duration: root.fastColorMs }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: root.neutralChipText(powerActionMouse.containsMouse)
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: powerActionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.triggerPowerAction(modelData.command)
                                }
                            }
                        }
                    }
                }
            }
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
                                color: stringOrEmpty((dashboard.active_context || {}).execution_mode) === "ssh" ? colors.teal : colors.accent
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

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Flickable {
                            anchors.fill: parent
                            clip: true
                            contentWidth: workspaceRow.implicitWidth
                            contentHeight: workspaceRow.implicitHeight

                                Row {
                                    id: workspaceRow
                                    spacing: 6

                                Repeater {
                                    model: root.barWorkspacesForOutput(barOutputName)

                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property var workspace: modelData
                                        readonly property var workspaceIcons: root.workspaceIconSources(root.workspaceLabel(workspace))
                                        readonly property int workspaceCount: root.workspaceWindowCount(root.workspaceLabel(workspace))
                                        width: Math.max(34, workspaceText.implicitWidth + (workspaceIcons.length ? 30 : 0) + (workspaceCount > 1 ? 14 : 0) + 12)
                                        height: 28
                                        radius: 8
                                        color: root.workspaceChipFill(workspace, workspaceMouse.containsMouse)
                                        border.color: root.workspaceChipBorder(workspace, workspaceMouse.containsMouse)
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
                                                        border.color: workspace.focused ? colors.blue : (workspaceMouse.containsMouse ? colors.borderStrong : colors.borderStrong)
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
                                                color: root.workspaceChipText(workspace, workspaceMouse.containsMouse)
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
                                            id: workspaceMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.activateWorkspace(workspace)
                                        }
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
                                id: cycleLayoutButton
                                width: 38
                                height: 24
                                radius: 7
                                color: cycleLayoutMouse.containsMouse ? colors.card : colors.cardAlt
                                border.color: cycleLayoutMouse.containsMouse ? colors.borderStrong : colors.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "Next"
                                    color: colors.text
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: cycleLayoutMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
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
                                color: root.panelVisible
                                    ? (bottomPanelToggleMouse.containsMouse ? colors.blue : colors.blue)
                                    : (bottomPanelToggleMouse.containsMouse ? colors.card : colors.cardAlt)
                                border.color: root.panelVisible
                                    ? colors.blue
                                    : (bottomPanelToggleMouse.containsMouse ? colors.borderStrong : colors.border)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: root.panelVisible ? "Hide" : "Open"
                                    color: root.panelVisible ? colors.bg : colors.text
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: bottomPanelToggleMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
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
        delegate: perScreenTopBarWindow
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
                    id: worktreeSummaryCard
                    implicitHeight: 78
                    Layout.preferredHeight: implicitHeight
                    Layout.fillWidth: true
                    radius: 12
                    color: colors.panel
                    border.color: root.worktreePickerVisible ? colors.blueMuted : colors.border
                    border.width: 1

                    ScriptModel {
                        id: worktreeItemsModel
                        values: root.worktreeItems()
                        objectProp: "modelData"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 8
                            color: root.isGlobalContext() ? colors.bg : colors.blueBg
                            border.color: root.isGlobalContext() ? colors.lineSoft : colors.blue
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.isGlobalContext() ? "G" : root.worktreePickerSummaryTitle().slice(0, 1).toUpperCase()
                                color: root.isGlobalContext() ? colors.textDim : colors.blue
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: root.activeContextSummaryLabel()
                                color: colors.subtle
                                font.pixelSize: 8
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    Layout.fillWidth: true
                                    text: root.worktreePickerSummaryTitle()
                                    color: colors.text
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    visible: !root.isGlobalContext()
                                    height: 16
                                    radius: 5
                                    color: colors.blueBg
                                    border.color: colors.blue
                                    border.width: 1
                                    Layout.preferredWidth: activeContextModeText.implicitWidth + 10

                                    Text {
                                        id: activeContextModeText
                                        anchors.centerIn: parent
                                        text: root.modeLabel(root.activeContextExecutionMode())
                                        color: colors.blue
                                        font.pixelSize: 7
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: !root.isGlobalContext()

                                Rectangle {
                                    height: 18
                                    radius: 6
                                    color: root.activeTerminalAvailable()
                                        ? colors.accentBg
                                        : (activeTerminalMouse.containsMouse ? colors.cardAlt : colors.card)
                                    border.color: root.activeTerminalAvailable()
                                        ? colors.accent
                                        : (activeTerminalMouse.containsMouse ? colors.borderStrong : colors.border)
                                    border.width: 1
                                    Layout.preferredWidth: shellStatusText.implicitWidth + 14

                                    Text {
                                        id: shellStatusText
                                        anchors.centerIn: parent
                                        text: root.activeTerminalChipLabel()
                                        color: root.activeTerminalAvailable() ? colors.accent : colors.text
                                        font.pixelSize: 8
                                        font.weight: Font.DemiBold
                                    }

                                    MouseArea {
                                        id: activeTerminalMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openActiveTerminal()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.activeTerminalMetaLabel()
                                    color: colors.muted
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            id: worktreeBrowseChip
                            height: 24
                            radius: 7
                            color: root.worktreePickerVisible
                                ? colors.blueBg
                                : (worktreeBrowseMouse.containsMouse ? colors.cardAlt : colors.card)
                            border.color: root.worktreePickerVisible
                                ? colors.blue
                                : (worktreeBrowseMouse.containsMouse ? colors.borderStrong : colors.border)
                            border.width: 1
                            Layout.preferredWidth: worktreeBrowseText.implicitWidth + 18

                            Text {
                                id: worktreeBrowseText
                                anchors.centerIn: parent
                                text: root.worktreePickerVisible ? "Close" : "Browse"
                                color: root.worktreePickerVisible ? colors.blue : colors.text
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: worktreeBrowseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.worktreePickerVisible = !root.worktreePickerVisible
                            }
                        }
                    }

                    MouseArea {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: worktreeBrowseChip.width + 8
                        acceptedButtons: Qt.LeftButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.worktreePickerVisible = !root.worktreePickerVisible
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.panelSessions().length > 0
                    spacing: 8

                    Text {
                        text: "AI Sessions"
                        color: colors.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        width: sessionSectionCount.implicitWidth + 12
                        height: 20
                        radius: 6
                        color: colors.cardAlt
                        border.color: colors.lineSoft
                        border.width: 1

                        Text {
                            id: sessionSectionCount
                            anchors.centerIn: parent
                            text: String(root.panelSessions().length)
                            color: colors.muted
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        radius: 1
                        color: colors.lineSoft
                        opacity: 0.9
                    }
                }

                Rectangle {
                    readonly property int visibleGroupRows: Math.min(4, Math.max(1, root.groupedSessionBands().length))
                    implicitHeight: 18 + (visibleGroupRows * 146) + (Math.max(0, visibleGroupRows - 1) * 10)
                    Layout.preferredHeight: implicitHeight
                    Layout.fillWidth: true
                    visible: root.panelSessions().length > 0
                    radius: 12
                    color: colors.panel
                    border.color: colors.border
                    border.width: 1

                    ScriptModel {
                        id: sessionGroupsModel
                        values: root.groupedSessionBands()
                        objectProp: "modelData"
                    }

                    ListView {
                        id: sessionGroupList
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        clip: true
                        spacing: 8
                        model: sessionGroupsModel
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: sessionGroupCard
                            required property var modelData
                            readonly property var group: modelData
                            readonly property bool expanded: root.sessionGroupExpanded(group)
                            width: sessionGroupList.width
                            implicitHeight: groupCardContent.implicitHeight + 16
                            height: implicitHeight
                            radius: 12
                            color: root.sessionGroupFill(group)
                            border.color: "transparent"
                            border.width: 0

                            ColumnLayout {
                                id: groupCardContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.topMargin: 8
                                spacing: 8

                                Rectangle {
                                    id: groupHeaderSurface
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radius: 9
                                    color: root.sessionGroupHeaderFill(group, groupHeaderMouse.containsMouse, sessionGroupCard.expanded)
                                    border.color: "transparent"
                                    border.width: 0

                                    RowLayout {
                                        id: groupHeaderRow
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: sessionGroupCard.expanded ? "▾" : "▸"
                                            color: root.sessionGroupChevronColor(group)
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.sessionGroupTitle(group)
                                            color: root.sessionGroupHeaderTextColor(group)
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: !sessionGroupCard.expanded && root.sessionGroupMetaLabel(group).length > 0
                                            text: root.sessionGroupMetaLabel(group)
                                            color: colors.subtle
                                            font.pixelSize: 8
                                            font.weight: Font.Medium
                                        }

                                        Rectangle {
                                            width: sessionGroupCountText.implicitWidth + 10
                                            height: 18
                                            radius: 6
                                            color: colors.bg
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                id: sessionGroupCountText
                                                anchors.centerIn: parent
                                                text: String(root.arrayOrEmpty(group.sessions).length)
                                                color: colors.muted
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: groupHeaderMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleSessionGroup(group)
                                    }
                                }

                                ColumnLayout {
                                    visible: sessionGroupCard.expanded
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: root.arrayOrEmpty(group.project_groups)

                                        delegate: ColumnLayout {
                                            required property var modelData
                                            readonly property var projectGroup: modelData
                                            Layout.fillWidth: true
                                            spacing: 6

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Rectangle {
                                                    height: 18
                                                    radius: 6
                                                    color: root.sessionProjectBadgeFill(projectGroup)
                                                    border.width: 0
                                                    Layout.preferredWidth: projectGroupLabel.implicitWidth + 12

                                                    Text {
                                                        id: projectGroupLabel
                                                        anchors.centerIn: parent
                                                        text: root.stringOrEmpty(projectGroup.display_name) || "Global"
                                                        color: root.sessionProjectBadgeText(projectGroup)
                                                        font.pixelSize: 9
                                                        font.weight: Font.DemiBold
                                                    }
                                                }

                                                Rectangle {
                                                    visible: root.stringOrEmpty(projectGroup.execution_mode).toLowerCase() === "ssh"
                                                    height: 18
                                                    radius: 6
                                                    color: colors.tealBg
                                                    border.color: colors.lineSoft
                                                    border.width: 1
                                                    Layout.preferredWidth: sessionProjectModeText.implicitWidth + 12

                                                    Text {
                                                        id: sessionProjectModeText
                                                        anchors.centerIn: parent
                                                        text: "SSH"
                                                        color: colors.teal
                                                        font.pixelSize: 8
                                                        font.weight: Font.DemiBold
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: root.stringOrEmpty(projectGroup.window_title).length > 0
                                                    text: root.stringOrEmpty(projectGroup.window_title)
                                                    color: colors.subtle
                                                    font.pixelSize: 8
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }

                                                Rectangle {
                                                    height: 18
                                                    radius: 6
                                                    color: colors.bg
                                                    border.color: colors.lineSoft
                                                    border.width: 1
                                                    Layout.preferredWidth: sessionProjectCountText.implicitWidth + 10

                                                    Text {
                                                        id: sessionProjectCountText
                                                        anchors.centerIn: parent
                                                        text: String(root.arrayOrEmpty(projectGroup.sessions).length)
                                                        color: colors.muted
                                                        font.pixelSize: 8
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }

                                            ListView {
                                                id: groupedSessionRow
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                orientation: ListView.Horizontal
                                                spacing: 8
                                                clip: true
                                                interactive: contentWidth > width
                                                boundsBehavior: Flickable.StopAtBounds
                                                model: root.arrayOrEmpty(projectGroup.sessions)

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var session: modelData
                                                    readonly property string primaryLabel: root.sessionPrimaryLabel(session)
                                                    readonly property string secondaryLabel: root.sessionSecondaryLabel(session)
                                                    readonly property string activityLabel: root.sessionBadgeLabel(session)
                                                    property bool hasMotion: root.sessionHasMotion(session)
                                                    readonly property real contentWidth: Math.max(primaryText.implicitWidth, secondaryText.implicitWidth) + trailingBadges.implicitWidth + 84
                                                    readonly property real maxPillWidth: Math.max(176, groupedSessionRow.width - 18)
                                                    width: Math.max(172, Math.min(contentWidth, maxPillWidth))
                                                    height: 40
                                                    radius: 10
                                                    color: sessionPillMouse.containsMouse && !root.sessionIsCurrent(session)
                                                        ? colors.cardAlt
                                                        : root.sessionCardFill(session)
                                                    border.color: root.sessionCardBorder(session)
                                                    border.width: 0

                                                    function resetMotionVisuals() {
                                                        workingHalo.opacity = hasMotion ? 0.05 : 0;
                                                        workingHalo.scale = 1;
                                                        toolIconWrap.opacity = hasMotion ? 0.96 : 0.92;
                                                        toolIconWrap.scale = 1;
                                                    }

                                                    onHasMotionChanged: resetMotionVisuals()
                                                    Component.onCompleted: resetMotionVisuals()

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 8

                                                        Item {
                                                            width: 24
                                                            height: 24

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: 20
                                                                height: 20
                                                                radius: 7
                                                                color: root.sessionIsCurrent(session) ? colors.bg : colors.cardAlt
                                                                border.color: "transparent"
                                                                border.width: 0
                                                            }

                                                            Rectangle {
                                                                id: workingHalo
                                                                anchors.centerIn: parent
                                                                width: 24
                                                                height: 24
                                                                radius: 8
                                                                color: root.sessionAccentColor(session)
                                                                border.color: "transparent"
                                                                border.width: 0
                                                                visible: hasMotion
                                                                opacity: hasMotion ? 0.05 : 0
                                                                scale: 1

                                                                ParallelAnimation {
                                                                    running: hasMotion
                                                                    loops: Animation.Infinite

                                                                    SequentialAnimation {
                                                                        OpacityAnimator {
                                                                            target: workingHalo
                                                                            from: 0.03
                                                                            to: 0.08
                                                                            duration: 800
                                                                        }
                                                                        OpacityAnimator {
                                                                            target: workingHalo
                                                                            from: 0.08
                                                                            to: 0.03
                                                                            duration: 800
                                                                        }
                                                                    }

                                                                    SequentialAnimation {
                                                                        ScaleAnimator {
                                                                            target: workingHalo
                                                                            from: 0.96
                                                                            to: 1.05
                                                                            duration: 800
                                                                        }
                                                                        ScaleAnimator {
                                                                            target: workingHalo
                                                                            from: 1.05
                                                                            to: 0.96
                                                                            duration: 800
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            Item {
                                                                id: toolIconWrap
                                                                anchors.centerIn: parent
                                                                width: 15
                                                                height: 15
                                                                scale: 1
                                                                opacity: hasMotion ? 0.96 : 0.92

                                                                ParallelAnimation {
                                                                    running: hasMotion
                                                                    loops: Animation.Infinite

                                                                    SequentialAnimation {
                                                                        ScaleAnimator {
                                                                            target: toolIconWrap
                                                                            from: 0.94
                                                                            to: 1.12
                                                                            duration: 800
                                                                        }
                                                                        ScaleAnimator {
                                                                            target: toolIconWrap
                                                                            from: 1.12
                                                                            to: 0.94
                                                                            duration: 800
                                                                        }
                                                                    }

                                                                    SequentialAnimation {
                                                                        OpacityAnimator {
                                                                            target: toolIconWrap
                                                                            from: 0.82
                                                                            to: 1
                                                                            duration: 800
                                                                        }
                                                                        OpacityAnimator {
                                                                            target: toolIconWrap
                                                                            from: 1
                                                                            to: 0.82
                                                                            duration: 800
                                                                        }
                                                                    }
                                                                }

                                                                IconImage {
                                                                    anchors.centerIn: parent
                                                                    implicitSize: 15
                                                                    source: root.toolIconSource(session)
                                                                    mipmap: true
                                                                    opacity: 1
                                                                }
                                                            }

                                                            Rectangle {
                                                                anchors.right: parent.right
                                                                anchors.bottom: parent.bottom
                                                                width: 6
                                                                height: 6
                                                                radius: 3
                                                                color: root.sessionBadgeColor(session)
                                                                opacity: 0.8
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 1

                                                            Text {
                                                                id: primaryText
                                                                Layout.fillWidth: true
                                                                text: primaryLabel
                                                                color: colors.text
                                                                font.pixelSize: 10
                                                                font.weight: Font.DemiBold
                                                                elide: Text.ElideRight
                                                            }

                                                            Text {
                                                                id: secondaryText
                                                                Layout.fillWidth: true
                                                                text: secondaryLabel
                                                                color: root.sessionTextColor(session)
                                                                font.pixelSize: 8
                                                                font.weight: Font.Medium
                                                                elide: Text.ElideRight
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            id: trailingBadges
                                                            spacing: 3

                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignRight
                                                                width: 24
                                                                height: 24
                                                                radius: 8
                                                                color: root.sessionBadgeBackground(session)
                                                                border.color: "transparent"
                                                                border.width: 0

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: root.sessionBadgeSymbol(session)
                                                                    color: root.sessionBadgeColor(session)
                                                                    font.pixelSize: 14
                                                                    font.weight: Font.DemiBold
                                                                }
                                                            }

                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignRight
                                                                visible: activityLabel.length > 0
                                                                width: visible ? activityText.implicitWidth + 12 : 0
                                                                height: 16
                                                                radius: 6
                                                                color: root.sessionBadgeBackground(session)
                                                                border.color: "transparent"
                                                                border.width: 0

                                                                RowLayout {
                                                                    anchors.fill: parent
                                                                    anchors.leftMargin: 5
                                                                    anchors.rightMargin: 5
                                                                    spacing: 4

                                                                    Rectangle {
                                                                        width: 5
                                                                        height: 5
                                                                        radius: 3
                                                                        color: root.sessionBadgeColor(session)
                                                                    }

                                                                    Text {
                                                                        id: activityText
                                                                        text: activityLabel
                                                                        color: root.sessionBadgeColor(session)
                                                                        font.pixelSize: 7
                                                                        font.weight: Font.DemiBold
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: sessionPillMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.focusSession(root.stringOrEmpty(session.session_key))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Windows"
                        color: colors.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        width: windowsSectionCount.implicitWidth + 12
                        height: 20
                        radius: 6
                        color: colors.cardAlt
                        border.color: colors.lineSoft
                        border.width: 1

                        Text {
                            id: windowsSectionCount
                            anchors.centerIn: parent
                            text: String(Number(dashboard.total_windows || 0))
                            color: colors.muted
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        radius: 1
                        color: colors.lineSoft
                        opacity: 0.9
                    }
                }

                ScriptModel {
                    id: windowProjectsModel
                    values: root.panelProjects()
                    objectProp: "modelData"
                }

                ListView {
                    id: windowsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    model: windowProjectsModel
                    cacheBuffer: 1200
                    visible: root.panelProjects().length > 0

                    delegate: Rectangle {
                        required property var modelData
                        readonly property var projectGroup: modelData
                        readonly property var projectWindows: root.arrayOrEmpty(projectGroup.windows)
                        width: windowsList.width
                        implicitHeight: 52 + (projectWindows.length * 44) + (Math.max(0, projectWindows.length - 1) * 6) + 10
                        radius: 12
                        color: root.projectCardFill(projectGroup)
                        border.color: "transparent"
                        border.width: 0

                        Rectangle {
                            visible: root.stringOrEmpty(projectGroup.project) !== "global"
                            width: 3
                            radius: 1
                            color: root.modeAccentColor(projectGroup.execution_mode)
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 2
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            opacity: projectGroup.is_active ? 0.95 : 0.72
                        }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radius: 10
                                    color: root.projectHeaderFill(projectGroup)
                                    border.color: "transparent"
                                    border.width: 0

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Rectangle {
                                            width: 20
                                            height: 20
                                            radius: 7
                                            color: root.stringOrEmpty(projectGroup.project) === "global"
                                                ? colors.card
                                                : (projectGroup.is_active ? colors.blueBg : colors.bg)
                                        border.color: "transparent"
                                        border.width: 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(projectGroup.project) === "global"
                                                    ? "G"
                                                : root.shortProject(projectGroup.project).slice(0, 1).toUpperCase()
                                                color: root.stringOrEmpty(projectGroup.project) === "global"
                                                    ? colors.subtle
                                                    : (projectGroup.is_active ? colors.blue : colors.muted)
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: root.stringOrEmpty(projectGroup.project) !== "global"
                                            width: visible ? projectModeText.implicitWidth + 12 : 0
                                            height: 18
                                            radius: 6
                                            color: root.stringOrEmpty(projectGroup.execution_mode) === "ssh"
                                                ? colors.tealBg
                                                : colors.blueBg
                                            border.color: root.modeAccentColor(projectGroup.execution_mode)
                                            border.width: 1

                                            Text {
                                                id: projectModeText
                                                anchors.centerIn: parent
                                                text: root.modeChipLabel(projectGroup.execution_mode)
                                                color: root.modeAccentColor(projectGroup.execution_mode)
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.stringOrEmpty(projectGroup.project) === "global"
                                                ? "Shared Windows"
                                                : root.shortProject(projectGroup.project)
                                            color: projectGroup.is_active
                                                ? (root.stringOrEmpty(projectGroup.execution_mode) === "ssh" ? colors.teal : colors.text)
                                                : colors.textDim
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            width: projectWindowCountText.implicitWidth + 12
                                            height: 18
                                            radius: 6
                                            color: colors.bg
                                            border.color: colors.lineSoft
                                            border.width: 1

                                            Text {
                                                id: projectWindowCountText
                                                anchors.centerIn: parent
                                                text: String(projectWindows.length) + (projectWindows.length === 1 ? " window" : " windows")
                                                color: colors.muted
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: Number(projectGroup.ai_session_count || 0) > 0
                                            width: visible ? projectSessionCountText.implicitWidth + 12 : 0
                                            height: 18
                                            radius: 6
                                            color: colors.cardAlt
                                            border.color: colors.lineSoft
                                            border.width: 1

                                            Text {
                                                id: projectSessionCountText
                                                anchors.centerIn: parent
                                                text: String(Number(projectGroup.ai_session_count || 0)) + " AI"
                                                color: colors.subtle
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }

                            Repeater {
                                model: projectWindows

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var windowData: modelData
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 12
                                    Layout.rightMargin: 2
                                    implicitHeight: 44
                                    radius: 8
                                    color: root.sidebarRowFill(windowData, windowMouse.containsMouse)
                                    border.color: "transparent"
                                    border.width: 0
                                    opacity: windowData.focused ? 1 : (windowData.hidden ? 0.72 : 0.94)

                                    Rectangle {
                                        visible: !!windowData.focused
                                        width: 3
                                        radius: 1
                                        color: colors.blue
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 5
                                        anchors.topMargin: 7
                                        anchors.bottomMargin: 7
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: windowData.focused ? 16 : 12
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Rectangle {
                                            width: 28
                                            height: 28
                                            radius: 7
                                            color: colors.bg
                                            border.color: "transparent"
                                            border.width: 0

                                            IconImage {
                                                anchors.centerIn: parent
                                                implicitSize: 20
                                                source: root.iconSourceFor(windowData)
                                                visible: source !== ""
                                                mipmap: true
                                                opacity: windowData.focused ? 1 : 0.9
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: root.iconSourceFor(windowData) === ""
                                                text: root.appLabel(windowData).slice(0, 1).toUpperCase()
                                                color: windowData.focused ? colors.text : colors.textDim
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayTitle(windowData)
                                            color: root.sidebarRowText(windowData, windowMouse.containsMouse)
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        RowLayout {
                                            visible: Number(windowData.ai_session_count || 0) > 0
                                            spacing: 4

                                            Repeater {
                                                model: root.windowSessionIcons(windowData)

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var session: modelData
                                                    width: 20
                                                    height: 20
                                                    radius: 6
                                                    color: root.sessionTint(session)
                                                    border.color: "transparent"
                                                    border.width: 0

                                                    Rectangle {
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.rightMargin: -1
                                                        anchors.bottomMargin: -1
                                                        width: 9
                                                        height: 9
                                                        radius: 5
                                                        color: root.sessionAccentColor(session)
                                                        border.color: "transparent"
                                                        border.width: 0
                                                        opacity: root.sessionHasMotion(session) ? 1 : 0.85
                                                    }

                                                    IconImage {
                                                        anchors.centerIn: parent
                                                        implicitSize: 13
                                                        source: root.toolIconSource(session)
                                                        mipmap: true
                                                        opacity: root.sessionIsCurrent(session) ? 1 : 0.94
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            mouse.accepted = true;
                                                            root.focusSession(root.stringOrEmpty(session.session_key));
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                visible: root.windowSessionOverflowCount(windowData) > 0
                                                width: visible ? overflowText.implicitWidth + 10 : 0
                                                height: 18
                                                radius: 6
                                                color: colors.bg
                                                border.color: "transparent"
                                                border.width: 0

                                                Text {
                                                    id: overflowText
                                                    anchors.centerIn: parent
                                                    text: "+" + String(root.windowSessionOverflowCount(windowData))
                                                    color: colors.subtle
                                                    font.pixelSize: 8
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: 18
                                            height: 18
                                            radius: 6
                                            color: closeMouse.containsMouse ? colors.redBg : colors.bg
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: "×"
                                                color: closeMouse.containsMouse ? colors.red : (windowData.focused ? colors.muted : colors.subtle)
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: closeMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    mouse.accepted = true;
                                                    root.closeWindow(windowData);
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: windowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.focusWindow(windowData)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.panelProjects().length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: colors.cardAlt
                    border.color: "transparent"
                    border.width: 0

                    Text {
                        anchors.centerIn: parent
                        text: "No tracked project windows"
                        color: colors.subtle
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }
            }

            Rectangle {
                id: worktreePickerOverlay
                visible: root.worktreePickerVisible
                z: 20
                x: panelColumn.x
                y: panelColumn.y + worktreeSummaryCard.y + worktreeSummaryCard.height + 8
                width: panelColumn.width
                readonly property int listRows: Math.min(6, Math.max(1, root.inactiveWorktreeItems().length))
                height: Math.min(
                    372,
                    Math.max(
                        176,
                        parent.height - y - 12
                    )
                )
                radius: 12
                color: colors.card
                border.color: colors.blueMuted
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Switch Context"
                                color: colors.text
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: "Recent worktrees and variants"
                                color: colors.subtle
                                font.pixelSize: 8
                            }
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 6
                            color: chooserCloseMouse.containsMouse ? colors.card : colors.bg
                            border.color: chooserCloseMouse.containsMouse ? colors.borderStrong : colors.lineSoft
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: colors.textDim
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: chooserCloseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.worktreePickerVisible = false
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 10
                        color: colors.panelAlt
                        border.color: colors.blueMuted
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8

                            Rectangle {
                                width: 22
                                height: 22
                                radius: 7
                                color: root.isGlobalContext() ? colors.bg : colors.blueBg
                                border.color: root.isGlobalContext() ? colors.lineSoft : colors.blue
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: root.isGlobalContext() ? "G" : root.worktreePickerSummaryTitle().slice(0, 1).toUpperCase()
                                    color: root.isGlobalContext() ? colors.textDim : colors.blue
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: root.worktreePickerSummaryTitle()
                                    color: colors.text
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.activeContextSummaryLabel()
                                    color: colors.muted
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                visible: !root.isGlobalContext()
                                height: 18
                                radius: 6
                                color: colors.blueBg
                                border.color: colors.blue
                                border.width: 1
                                Layout.preferredWidth: currentBadgeText.implicitWidth + 12

                                Text {
                                    id: currentBadgeText
                                    anchors.centerIn: parent
                                    text: "Current"
                                    color: colors.blue
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    ScriptModel {
                        id: chooserWorktreeItemsModel
                        values: root.inactiveWorktreeItems()
                        objectProp: "modelData"
                    }

                    ListView {
                        id: worktreeList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: (worktreePickerOverlay.listRows * 42) + (Math.max(0, worktreePickerOverlay.listRows - 1) * 6)
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: chooserWorktreeItemsModel

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool hasRemoteVariant: !!modelData.remote_available
                            width: worktreeList.width
                            height: 42
                            radius: 10
                            color: root.chooserRowFill(chooserRowMouse.containsMouse)
                            border.color: root.chooserRowBorder(chooserRowMouse.containsMouse)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 7
                                    color: colors.bg
                                    border.color: colors.lineSoft
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.worktreeDisplayName(modelData).slice(0, 1).toUpperCase()
                                        color: colors.textDim
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
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
                                            text: root.worktreeDisplayName(modelData)
                                            color: colors.textDim
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            height: 16
                                            radius: 5
                                            color: colors.bg
                                            border.color: root.worktreeStatusColor(modelData)
                                            border.width: 1
                                            Layout.preferredWidth: chooserWorktreeStatusText.implicitWidth + 10

                                            Text {
                                                id: chooserWorktreeStatusText
                                                anchors.centerIn: parent
                                                text: root.worktreeStatusLabel(modelData)
                                                color: root.worktreeStatusColor(modelData)
                                                font.pixelSize: 7
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.worktreeSubtitle(modelData)
                                        color: colors.subtle
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    visible: hasRemoteVariant
                                    height: 18
                                    radius: 6
                                    color: colors.tealBg
                                    border.color: colors.teal
                                    border.width: 1
                                    Layout.preferredWidth: chooserSshVariantText.implicitWidth + 12

                                    Text {
                                        id: chooserSshVariantText
                                        anchors.centerIn: parent
                                        text: "SSH"
                                        color: colors.teal
                                        font.pixelSize: 8
                                        font.weight: Font.DemiBold
                                    }

                                    MouseArea {
                                        id: chooserSshMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activateWorktree(modelData, "ssh")
                                    }
                                }
                            }

                            MouseArea {
                                id: chooserRowMouse
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.rightMargin: hasRemoteVariant ? 42 : 0
                                acceptedButtons: Qt.LeftButton
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activateWorktree(modelData, "local")
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 9
                        color: colors.bg
                        border.color: clearContextMouse.containsMouse && !root.isGlobalContext() ? colors.borderStrong : colors.lineSoft
                        border.width: 1
                        opacity: root.isGlobalContext() ? 0.78 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "Clear to Global"
                                color: colors.textDim
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: "Shared windows only"
                                color: colors.subtle
                                font.pixelSize: 8
                            }
                        }

                        MouseArea {
                            id: clearContextMouse
                            anchors.fill: parent
                            enabled: !root.isGlobalContext()
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.clearContext()
                        }
                    }
                }
            }
        }
    }
}
