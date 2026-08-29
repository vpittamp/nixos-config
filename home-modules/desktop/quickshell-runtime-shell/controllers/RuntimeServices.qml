import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland

Item {
    id: services
    visible: false

    required property QtObject shellRoot
    required property QtObject runtimeConfig

    property alias clockRef: clock
    property alias dashboardRestartTimerRef: dashboardRestartTimer
    property alias daemonActionRestartTimerRef: daemonActionRestartTimer
    property alias notificationRestartTimerRef: notificationRestartTimer
    property alias networkRefreshTimerRef: networkRefreshTimer
    property alias systemStatsRestartTimerRef: systemStatsRestartTimer
    property alias brightnessRestartTimerRef: brightnessRestartTimer
    property alias lidPolicyRestartTimerRef: lidPolicyRestartTimer
    property alias launcherFocusTimerRef: launcherFocusTimer
    property alias osdHideTimerRef: osdHideTimer
    property alias notificationStoreRef: notificationStore
    property alias agentUsageRefreshProcessRef: agentUsageRefreshProcess
    property alias notificationPersistTimerRef: notificationPersistTimer
    property alias launcherQueryDebounceRef: launcherQueryDebounce
    property alias launcherSessionSwitcherOpenTimerRef: launcherSessionSwitcherOpenTimer
    property alias launcherWindowSwitcherOpenTimerRef: launcherWindowSwitcherOpenTimer
    property alias launcherRunningSwitcherOpenTimerRef: launcherRunningSwitcherOpenTimer
    property alias exposeFocusTimerRef: exposeFocusTimer
    property alias exposeOpenTimerRef: exposeOpenTimer
    property alias exposeRefreshTimerRef: exposeRefreshTimer
    property alias sessionPreviewDebounceRef: sessionPreviewDebounce
    property alias sessionPreviewReaderRef: sessionPreviewReader
    property alias sessionPreviewPollTimerRef: sessionPreviewPollTimer
    property alias settingsFocusTimerRef: settingsFocusTimer
    property alias settingsCommandQueryDebounceRef: settingsCommandQueryDebounce
    property alias sessionClosePendingPruneTimerRef: sessionClosePendingPruneTimer
    property alias dashboardWatcherRef: dashboardWatcher
    property alias notificationWatcherRef: notificationWatcher
    property alias networkWatcherRef: networkWatcher
    property alias castWatcherRef: castWatcher
    property alias systemStatsWatcherRef: systemStatsWatcher
    property alias lidPolicyWatcherRef: lidPolicyWatcher
    property alias brightnessActionProcessRef: brightnessActionProcess
    property alias lidPolicyApplyProcessRef: lidPolicyApplyProcess
    property alias lidInhibitActionProcessRef: lidInhibitActionProcess
    property alias castActionProcessRef: castActionProcess
    property alias snippetEditorProcessRef: snippetEditorProcess
    property alias settingsCommandQueryProcessRef: settingsCommandQueryProcess
    property alias launcherQueryProcessRef: launcherQueryProcess
    property alias displayApplyProcessRef: displayApplyProcess
    property alias displayToggleOutputProcessRef: displayToggleOutputProcess
    property alias displayScaleProcessRef: displayScaleProcess
    property alias displayPresetProcessRef: displayPresetProcess
    property int daemonActionRequestId: 0
    // Actions requested while the bridge process is down; flushed on its next
    // start so a click during a bridge restart is delivered, not dropped.
    property var daemonActionQueue: []

    // Queued actions older than this are dropped rather than replayed: a focus
    // request that has been waiting seconds for the bridge to come back no
    // longer reflects where the user wants to be, and replaying it would yank
    // them to a workspace they left long ago.
    readonly property int daemonActionMaxQueueAgeMs: 2000

    function queueDaemonAction(method, params) {
        const next = daemonActionQueue.slice();
        next.push({ method: method, params: params || {}, queuedAt: Date.now() });
        while (next.length > 8) {
            next.shift();
        }
        daemonActionQueue = next;
    }

    function flushDaemonActionQueue() {
        if (!daemonActionBridge.running || daemonActionQueue.length === 0) {
            return;
        }
        const pending = daemonActionQueue;
        daemonActionQueue = [];
        const now = Date.now();
        for (let i = 0; i < pending.length; i += 1) {
            const entry = pending[i];
            const queuedAt = Number(entry.queuedAt || 0);
            if (queuedAt && now - queuedAt > daemonActionMaxQueueAgeMs) {
                continue;
            }
            sendDaemonAction(entry.method, entry.params);
        }
    }

    // Returns true only when the request was actually written to the bridge.
    // A queued request reports false so callers holding a real fallback (e.g.
    // closeWindow's `i3pm window action` CLI path) still reach it; pass
    // options.queue = false to skip queueing entirely and avoid running both.
    function sendDaemonAction(method, params, options) {
        const normalizedMethod = String(method || "").trim();
        if (!normalizedMethod || !runtimeConfig.daemonActionBin) {
            return false;
        }

        try {
            if (!daemonActionBridge.running) {
                if (!options || options.queue !== false) {
                    queueDaemonAction(normalizedMethod, params || {});
                }
                daemonActionBridge.running = true;
                return false;
            }
            daemonActionRequestId += 1;
            daemonActionBridge.write(JSON.stringify({
                id: daemonActionRequestId,
                method: normalizedMethod,
                params: params || {},
            }) + "\n");
            return true;
        } catch (error) {
            console.warn("daemon.action:", error);
            return false;
        }
    }

    Connections {
        target: shellRoot

        function onNotificationCenterVisibleChanged() {
            shellRoot.refreshNotificationState();
            if (shellRoot.notificationCenterVisible) {
                shellRoot.markAllNotificationsRead();
            }
        }

        function onLauncherVisibleChanged() {
            if (shellRoot.launcherVisible) {
                shellRoot.settingsVisible = false;
                shellRoot.displaySelectorVisible = false;
                const openingSessionSwitcher = shellRoot.launcherSessionSwitcherPendingDelta !== 0;
                const openingWindowSwitcher = shellRoot.launcherWindowSwitcherPendingDelta !== 0;
                shellRoot.launcherMode = openingSessionSwitcher ? "sessions" : (openingWindowSwitcher ? "windows" : "apps");
                shellRoot.launcherSessionSwitcherActive = openingSessionSwitcher;
                shellRoot.launcherWindowSwitcherActive = openingWindowSwitcher;
                shellRoot.launcherQuery = "";
                shellRoot.launcherError = "";
                shellRoot.launcherEntries = [];
                shellRoot.launcherSelectedIndex = 0;
                shellRoot.launcherAppFilter = "all";
                shellRoot.launcherPointerSelectionEnabled = true;
                shellRoot.launcherPointerInputReady = false;
                shellRoot.launcherSelectionMode = "initial";
                shellRoot.launcherViewportPrimed = false;
                shellRoot.launcherNormalizingInput = true;
                if (shellRoot.launcherField) {
                    shellRoot.launcherField.text = "";
                }
                shellRoot.launcherNormalizingInput = false;
                shellRoot.resetLauncherListViewport();
                launcherQueryDebounce.restart();
                launcherFocusTimer.restart();
                launcherPointerInputTimer.restart();
                sessionPreviewDebounce.restart();
                return;
            }

            shellRoot.launcherLoading = false;
            shellRoot.launcherError = "";
            shellRoot.launcherEntries = [];
            shellRoot.launcherSessionSwitcherActive = false;
            shellRoot.launcherSessionSwitcherPendingDelta = 0;
            shellRoot.launcherWindowSwitcherActive = false;
            shellRoot.launcherWindowSwitcherPendingDelta = 0;
            shellRoot.launcherAppFilter = "all";
            shellRoot.launcherSessionEntryOrder = [];
            shellRoot.launcherSelectedIndex = 0;
            shellRoot.launcherPointerSelectionEnabled = true;
            shellRoot.launcherPointerInputReady = true;
            shellRoot.launcherSelectionMode = "initial";
            shellRoot.launcherViewportPrimed = false;
            shellRoot.resetSnippetEditor();
            shellRoot.launcherNormalizingInput = true;
            if (shellRoot.launcherField) {
                shellRoot.launcherField.text = "";
            }
            shellRoot.launcherNormalizingInput = false;
            shellRoot.resetLauncherListViewport();
            shellRoot.clearSessionPreview();
            if (launcherQueryProcess.running) {
                launcherQueryProcess.running = false;
            }
        }

        function onLauncherModeChanged() {
            shellRoot.launcherError = "";
            shellRoot.launcherSelectedIndex = 0;
            shellRoot.launcherPointerSelectionEnabled = true;
            shellRoot.launcherPointerInputReady = false;
            if (shellRoot.launcherMode !== "sessions") {
                shellRoot.launcherSessionSwitcherActive = false;
                shellRoot.launcherSessionSwitcherPendingDelta = 0;
                shellRoot.launcherSessionEntryOrder = [];
                shellRoot.clearSessionPreview();
            }
            if (shellRoot.launcherMode !== "windows") {
                shellRoot.launcherWindowSwitcherActive = false;
                shellRoot.launcherWindowSwitcherPendingDelta = 0;
            }
            shellRoot.resetLauncherListViewport();
            if (shellRoot.launcherVisible) {
                launcherQueryDebounce.restart();
                launcherFocusTimer.restart();
                launcherPointerInputTimer.restart();
                if (shellRoot.launcherMode === "sessions") {
                    sessionPreviewDebounce.restart();
                }
            }
        }

        function onLauncherQueryChanged() {
            if (shellRoot.launcherSessionSwitcherActive && shellRoot.launcherQuery !== "") {
                shellRoot.launcherSessionSwitcherActive = false;
                shellRoot.launcherSessionSwitcherPendingDelta = 0;
            }
            if (shellRoot.launcherWindowSwitcherActive && shellRoot.launcherQuery !== "") {
                shellRoot.launcherWindowSwitcherActive = false;
                shellRoot.launcherWindowSwitcherPendingDelta = 0;
            }
            if (shellRoot.launcherVisible) {
                launcherQueryDebounce.restart();
            }
        }

        function onLauncherSelectedIndexChanged() {
            shellRoot.syncLauncherListSelection();
            if (shellRoot.launcherVisible && shellRoot.launcherMode === "sessions") {
                shellRoot.ensureSessionPreviewForSelection();
            }
        }

        function onSettingsVisibleChanged() {
            if (shellRoot.settingsVisible) {
                shellRoot.displaySelectorVisible = false;
                shellRoot.launcherVisible = false;
                shellRoot.settingsCommandQuery = "";
                shellRoot.settingsCommandNormalizingInput = true;
                if (shellRoot.settingsCommandQueryField) {
                    shellRoot.settingsCommandQueryField.text = "";
                }
                shellRoot.settingsCommandNormalizingInput = false;
                shellRoot.settingsCommandError = "";
                shellRoot.settingsCommandEntries = [];
                shellRoot.settingsCommandSelectedIndex = 0;
                shellRoot.resetSnippetEditor();
                settingsCommandQueryDebounce.restart();
                settingsFocusTimer.restart();
                return;
            }

            shellRoot.settingsCommandLoading = false;
            shellRoot.settingsCommandError = "";
            shellRoot.settingsCommandEntries = [];
            shellRoot.settingsCommandSelectedIndex = 0;
            shellRoot.resetSnippetEditor();
            shellRoot.settingsCommandNormalizingInput = true;
            if (shellRoot.settingsCommandQueryField) {
                shellRoot.settingsCommandQueryField.text = "";
            }
            shellRoot.settingsCommandNormalizingInput = false;
            if (settingsCommandQueryProcess.running) {
                settingsCommandQueryProcess.running = false;
            }
            if (snippetEditorProcess.running) {
                snippetEditorProcess.running = false;
            }
        }

        function onSettingsCommandQueryChanged() {
            if (shellRoot.settingsVisible && shellRoot.settingsSection === "commands") {
                settingsCommandQueryDebounce.restart();
            }
        }

        function onSettingsCommandSelectedIndexChanged() {
            if (shellRoot.settingsVisible && shellRoot.settingsCommandEntries.length && shellRoot.settingsCommandSelectedIndex >= 0 && shellRoot.settingsCommandsList) {
                shellRoot.settingsCommandsList.positionViewAtIndex(shellRoot.settingsCommandSelectedIndex, ListView.Contain);
            }
            if (shellRoot.settingsVisible && shellRoot.settingsSection === "commands") {
                shellRoot.syncSnippetEditorFromSelection();
            }
        }
    }

    Component {
        id: nativeNotificationServerComponent

        NotificationServer {
            keepOnReload: true
            persistenceSupported: false
            bodySupported: true
            bodyMarkupSupported: runtimeConfig.notificationMarkupEnabled
            bodyHyperlinksSupported: false
            bodyImagesSupported: runtimeConfig.notificationImagesEnabled
            actionsSupported: true
            actionIconsSupported: false
            imageSupported: runtimeConfig.notificationImagesEnabled
            inlineReplySupported: true
            onNotification: function (notification) {
                shellRoot.handleNativeNotification(notification);
            }
        }
    }

    Loader {
        active: shellRoot.notificationsBackendNative()
        sourceComponent: nativeNotificationServerComponent
    }

    SystemClock {
        id: clock
        precision: runtimeConfig.topBarShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Timer {
        id: dashboardRestartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            shellRoot.resetDashboard("loading", "");
            dashboardWatcher.running = true;
        }
    }

    Timer {
        id: daemonActionRestartTimer
        interval: 1000
        repeat: false
        onTriggered: daemonActionBridge.running = true
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

    Timer {
        id: castRefreshTimer
        interval: 10000
        repeat: false
        onTriggered: castWatcher.running = true
    }

    Timer {
        id: systemStatsRestartTimer
        interval: 2000
        repeat: false
        onTriggered: systemStatsWatcher.running = true
    }

    Timer {
        id: brightnessRestartTimer
        interval: 2000
        repeat: false
        onTriggered: brightnessWatcher.running = true
    }

    Timer {
        id: voxtypeRestartTimer
        interval: 2000
        repeat: false
        onTriggered: voxtypeWatcher.running = true
    }

    Timer {
        id: launcherFocusTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (!shellRoot.launcherField) {
                return;
            }
            shellRoot.launcherField.forceActiveFocus();
            shellRoot.launcherField.selectAll();
        }
    }

    // ----- Notification persistence -----
    FileView {
        id: notificationStore
        path: runtimeConfig.notificationStorePath
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    Timer {
        id: notificationPersistTimer
        interval: 400
        repeat: false
        onTriggered: shellRoot.persistNotifications()
    }

    Timer {
        id: notificationRestoreTimer
        interval: 250
        repeat: false
        running: true
        onTriggered: shellRoot.restoreNotifications()
    }

    // ----- Theme state -----
    // ~/.local/state/quickshell-runtime-shell/theme.json names the active
    // theme; runtime-theme writes it and the shell restyles without restart.
    FileView {
        id: themeStateView
        path: runtimeConfig.themeStatePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: shellRoot.applyThemeState(text())
        onLoadFailed: shellRoot.applyThemeState("")
    }

    // ----- Agent usage records -----
    // One watched file per known agent. A record that appears is an agent;
    // one that fails to load (not written yet, collector failed) is absent.
    Instantiator {
        model: runtimeConfig.agentUsageAgents
        delegate: FileView {
            required property string modelData
            path: runtimeConfig.agentUsageDir + "/" + modelData + ".json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: shellRoot.setAgentUsageRecord(modelData, text())
            onLoadFailed: shellRoot.setAgentUsageRecord(modelData, "")
        }
    }

    Process {
        id: agentUsageRefreshProcess
        command: [runtimeConfig.agentUsageUpdateBin, "--limits-only"]
        onExited: function () {
            shellRoot.agentUsageRefreshing = false;
        }
    }

    // ----- Idle -----
    // ext-idle-notify through the compositor, honouring app idle inhibitors
    // (video playback) and the shell's own idleInhibited (cast, lid inhibit).
    IdleMonitor {
        id: idleScreenOffMonitor
        enabled: runtimeConfig.idleScreenOffSeconds > 0 && !shellRoot.idleInhibited
        timeout: runtimeConfig.idleScreenOffSeconds
        respectInhibitors: true
        onIsIdleChanged: shellRoot.handleIdleScreen(isIdle)
    }

    IdleMonitor {
        id: idleLockMonitor
        enabled: runtimeConfig.idleLockSeconds > 0 && !shellRoot.idleInhibited && !shellRoot.sessionLocked
        timeout: runtimeConfig.idleLockSeconds
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) {
                shellRoot.lockSession();
            }
        }
    }

    Timer {
        id: osdHideTimer
        interval: 1400
        repeat: false
        onTriggered: shellRoot.osdVisible = false
    }

    Timer {
        id: osdArmTimer
        interval: 3000
        repeat: false
        running: true
        onTriggered: shellRoot.osdArmed = true
    }

    Timer {
        id: launcherPointerInputTimer
        interval: 220
        repeat: false
        onTriggered: shellRoot.launcherPointerInputReady = shellRoot.launcherVisible
    }

    Timer {
        id: launcherQueryDebounce
        interval: 90
        repeat: false
        onTriggered: shellRoot.restartLauncherQuery()
    }

    Timer {
        id: launcherSessionSwitcherOpenTimer
        interval: 0
        repeat: false
        onTriggered: shellRoot.finalizeLauncherSessionSwitcherOpen()
    }

    Timer {
        id: launcherWindowSwitcherOpenTimer
        interval: 0
        repeat: false
        onTriggered: shellRoot.finalizeLauncherWindowSwitcherOpen()
    }

    Timer {
        id: launcherRunningSwitcherOpenTimer
        interval: 0
        repeat: false
        onTriggered: shellRoot.finalizeLauncherRunningSwitcherOpen()
    }

    Timer {
        id: exposeFocusTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (shellRoot.windowSwitcherFocusItem) {
                shellRoot.windowSwitcherFocusItem.forceActiveFocus();
            }
        }
    }

    Timer {
        id: exposeOpenTimer
        interval: 0
        repeat: false
        onTriggered: shellRoot.finalizeExposeOpen()
    }

    Timer {
        id: exposeRefreshTimer
        interval: 250
        repeat: false
        onTriggered: shellRoot.refreshExposeEntries()
    }

    Timer {
        id: sessionPreviewDebounce
        interval: 75
        repeat: false
        onTriggered: shellRoot.restartSessionPreview()
    }

    Timer {
        id: settingsFocusTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (shellRoot.settingsSection !== "commands" || !shellRoot.settingsCommandQueryField) {
                return;
            }
            shellRoot.settingsCommandQueryField.forceActiveFocus();
            shellRoot.settingsCommandQueryField.selectAll();
        }
    }

    Timer {
        id: settingsCommandQueryDebounce
        interval: 90
        repeat: false
        onTriggered: shellRoot.restartSettingsCommandQuery()
    }

    // Touch-mode state feed. The script only emits on change, so this stays
    // idle until the mode is actually toggled — including when it is toggled by
    // the two-finger gesture or the CLI rather than by the bar chip, which is
    // why the chip reads a feed instead of tracking its own clicks.
    // Keyboard visibility feed — same pattern as the touch-mode watcher below:
    // the state lives in a runtime file only a script can own, and the shell
    // needs it live to reflow the launcher around the keys.
    Process {
        id: oskWatcher
        command: [runtimeConfig.oskStatusBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.oskVisible = (data || "").trim() === "visible";
            }
        }
        onExited: oskRestartTimer.restart()
    }

    Timer {
        id: oskRestartTimer
        interval: 3000
        repeat: false
        onTriggered: oskWatcher.running = true
    }

    Process {
        id: touchModeWatcher
        command: [runtimeConfig.touchModeStatusBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const value = (data || "").trim();
                if (value === "on" || value === "off" || value === "none") {
                    shellRoot.touchModeState = value;
                }
            }
        }
        onExited: touchModeRestartTimer.restart()
    }

    Timer {
        id: touchModeRestartTimer
        interval: 3000
        repeat: false
        onTriggered: touchModeWatcher.running = true
    }

    Process {
        id: dashboardWatcher
        command: [runtimeConfig.i3pmWatchBin, "dashboard", "watch"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseDashboard(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.handleDashboardWatchError(data);
            }
        }
        onExited: function () {
            shellRoot.resetDashboard("reconnecting", "dashboard watcher exited");
            dashboardRestartTimer.restart();
        }
    }

    Process {
        id: daemonActionBridge
        command: [runtimeConfig.daemonActionBin, "--jsonl"]
        running: true
        stdinEnabled: true
        onStarted: services.flushDaemonActionQueue()
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.handleDaemonActionResponse(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("daemon.action:", data);
                }
            }
        }
        onExited: function () {
            daemonActionRestartTimer.restart();
        }
    }

    Process {
        id: notificationWatcher
        command: [runtimeConfig.notificationMonitorBin]
        running: !shellRoot.notificationsBackendNative()
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseNotification(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("notification.watch:", data);
                }
            }
        }
        onExited: function () {
            notificationRestartTimer.restart();
        }
    }

    Process {
        id: sessionPreviewReader
        // One-shot read of a Herdr pane's visible viewport, re-run by
        // sessionPreviewPollTimer while the launcher's session preview is open.
        // Reading a pane does not focus it, which is the whole point: the user
        // watches an agent without leaving the window they are in.
        command: shellRoot.sessionPreviewCommand
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.appendSessionPreviewLine(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    shellRoot.noteSessionPreviewError(data);
                }
            }
        }
        onExited: function (exitCode) {
            shellRoot.finishSessionPreviewRead(exitCode);
        }
    }

    Timer {
        id: sessionPreviewPollTimer
        // Cheap enough to feel live: a read measured ~2ms, and this only runs
        // while the launcher is showing a Herdr session.
        interval: 750
        repeat: true
        running: false
        onTriggered: shellRoot.pollSessionPreview()
    }

    Process {
        id: networkWatcher
        command: [runtimeConfig.networkStatusBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseNetwork(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("network.watch:", data);
                }
            }
        }
        onExited: function () {
            networkRefreshTimer.restart();
        }
    }

    // One-shot cast (Chromecast / cast-extend) status probe — reruns on a slow
    // refresh cycle, and immediately after castActionProcess completes.
    Process {
        id: castWatcher
        command: [runtimeConfig.castStatusBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseCast(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("cast.watch:", data);
                }
            }
        }
        onExited: function () {
            castRefreshTimer.restart();
        }
    }

    // Voxtype dictation status stream (idle/recording/transcribing) -> bar chip.
    Process {
        id: voxtypeWatcher
        command: [runtimeConfig.voxtypeStatusBin, "status", "--follow", "--format", "json"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseVoxtype(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("voxtype.watch:", data);
                }
            }
        }
        onExited: function () {
            voxtypeRestartTimer.restart();
        }
    }

    // Live mic-level meter — runs ONLY while voxtype is listening, so the mic is
    // tapped only during dictation. Emits 0-100 per line; resets to 0 on stop.
    Process {
        id: dictationLevelWatcher
        command: [runtimeConfig.dictationLevelBin]
        running: shellRoot.voxtypeListening()
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseDictationLevel(data);
            }
        }
        onRunningChanged: {
            if (!running) {
                shellRoot.resetDictationLevel();
            }
        }
    }

    Process {
        id: daemonHealthWatcher
        command: [runtimeConfig.daemonHealthBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseDaemonHealth(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("daemon.health:", data);
                }
            }
        }
        onExited: function () {
            daemonHealthRestartTimer.restart();
        }
    }

    Timer {
        id: daemonHealthRestartTimer
        interval: 5000
        repeat: false
        onTriggered: daemonHealthWatcher.running = true
    }

    Process {
        id: systemStatsWatcher
        command: [runtimeConfig.systemStatsBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseSystemStats(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("system.stats:", data);
                }
            }
        }
        onExited: function () {
            systemStatsRestartTimer.restart();
        }
    }

    Process {
        id: brightnessWatcher
        command: [runtimeConfig.brightnessStatusBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseBrightness(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("brightness.watch:", data);
                }
            }
        }
        onExited: function () {
            brightnessRestartTimer.restart();
        }
    }

    Process {
        id: lidPolicyWatcher
        command: [runtimeConfig.lidPolicyStatusBin]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseLidPolicy(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("lid.policy.watch:", data);
                }
            }
        }
        onExited: function () {
            lidPolicyRestartTimer.restart();
        }
    }

    Process {
        id: snippetEditorProcess
        command: [runtimeConfig.snippetsManageBin, "upsert", "-1", "", "", ""]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.handleSnippetMutationResult(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (message) {
                    shellRoot.snippetEditorBusy = false;
                    shellRoot.snippetEditorError = message;
                    console.warn("settings.commands.manage:", message);
                }
            }
        }
        onExited: function () {
            shellRoot.snippetEditorBusy = false;
        }
    }

    Process {
        id: settingsCommandQueryProcess
        command: [runtimeConfig.snippetsListBin, "", "200"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseSettingsCommandResults(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (!shellRoot.settingsVisible || shellRoot.settingsSection !== "commands") {
                    return;
                }
                const message = data && data.trim();
                if (message) {
                    shellRoot.settingsCommandError = "Unable to load commands";
                    shellRoot.settingsCommandLoading = false;
                    console.warn("settings.commands.query:", message);
                }
            }
        }
        onExited: function () {
            shellRoot.settingsCommandLoading = false;
        }
    }

    Process {
        id: launcherQueryProcess
        command: [runtimeConfig.launcherQueryBin, "", "12", "20"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (shellRoot.launcherMode === "files") {
                    shellRoot.parseFileResults(data);
                    return;
                }
                if (shellRoot.launcherMode === "urls") {
                    shellRoot.parseUrlResults(data);
                    return;
                }
                if (shellRoot.launcherMode === "runner") {
                    shellRoot.parseRunnerResults(data);
                    return;
                }
                if (shellRoot.launcherMode === "snippets") {
                    shellRoot.parseSnippetResults(data);
                    return;
                }
                if (shellRoot.launcherMode === "onepassword") {
                    shellRoot.parseOnePasswordResults(data);
                    return;
                }
                if (shellRoot.launcherMode === "clipboard") {
                    shellRoot.parseClipboardResults(data);
                    return;
                }
                shellRoot.parseLauncherResults(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (!shellRoot.launcherVisible || (shellRoot.launcherMode !== "apps" && shellRoot.launcherMode !== "files" && shellRoot.launcherMode !== "urls" && shellRoot.launcherMode !== "runner" && shellRoot.launcherMode !== "snippets" && shellRoot.launcherMode !== "onepassword" && shellRoot.launcherMode !== "clipboard")) {
                    return;
                }
                const message = data && data.trim();
                if (message) {
                    if (shellRoot.launcherMode === "files") {
                        shellRoot.launcherError = "Unable to load file results";
                    } else if (shellRoot.launcherMode === "urls") {
                        shellRoot.launcherError = "Unable to load Chrome URL results";
                    } else if (shellRoot.launcherMode === "runner") {
                        shellRoot.launcherError = "Unable to prepare command";
                    } else if (shellRoot.launcherMode === "snippets") {
                        shellRoot.launcherError = "Unable to load curated commands";
                    } else if (shellRoot.launcherMode === "onepassword") {
                        shellRoot.launcherError = "Unable to load 1Password items";
                    } else if (shellRoot.launcherMode === "clipboard") {
                        shellRoot.launcherError = "Unable to load clipboard history";
                    } else {
                        shellRoot.launcherError = "Launcher query failed";
                    }
                    shellRoot.launcherLoading = false;
                    console.warn("launcher.query:", message);
                }
            }
        }
        onExited: function () {
            if (shellRoot.launcherMode === "apps" || shellRoot.launcherMode === "files" || shellRoot.launcherMode === "urls" || shellRoot.launcherMode === "runner" || shellRoot.launcherMode === "snippets" || shellRoot.launcherMode === "onepassword" || shellRoot.launcherMode === "clipboard") {
                shellRoot.launcherLoading = false;
            }
        }
    }

    Process {
        id: displayApplyProcess
        command: [runtimeConfig.i3pmBin, "display", "apply", ""]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.displayApplyStdout += data + "\n";
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (!message) {
                    return;
                }
                shellRoot.displayApplyStderr += message + "\n";
                console.warn("display.apply:", message);
            }
        }
        onExited: function () {
            const target = shellRoot.stringOrEmpty(shellRoot.displayApplyTarget);
            const raw = shellRoot.stringOrEmpty(shellRoot.displayApplyStdout).trim();
            let success = false;
            if (raw) {
                try {
                    const parsed = JSON.parse(raw);
                    success = !!(parsed && (parsed.applied || shellRoot.stringOrEmpty(parsed.current_layout) === target));
                } catch (error) {
                    console.warn("display.apply.parse:", raw, error);
                }
            }

            if (success) {
                shellRoot.clearDisplayApplyState();
                shellRoot.displaySelectorVisible = false;
                return;
            }

            const stderr = shellRoot.stringOrEmpty(shellRoot.displayApplyStderr).trim();
            shellRoot.displayApplyError = stderr || "Unable to apply display layout.";
            shellRoot.displayApplyStdout = "";
            shellRoot.displayApplyStderr = "";
        }
    }

    Process {
        id: displayPresetProcess
        // Applies a display preset by EDID role via lid-clamshell. The resulting
        // output changes push a fresh display_layout snapshot, so the map and the
        // active-preset highlight refresh on their own.
        command: [runtimeConfig.lidClamshellBin, "preset", ""]
        running: false
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (message) {
                    console.warn("display.preset:", message);
                }
            }
        }
        onExited: function () {
            shellRoot.displayPresetTarget = "";
        }
    }

    Process {
        id: displayToggleOutputProcess
        command: [runtimeConfig.i3pmBin, "display", "toggle-output", ""]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.displayToggleStdout += data + "\n";
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (!message) {
                    return;
                }
                shellRoot.displayToggleStderr += message + "\n";
                console.warn("display.toggle_output:", message);
            }
        }
        onExited: function () {
            const target = shellRoot.stringOrEmpty(shellRoot.displayToggleTarget);
            const raw = shellRoot.stringOrEmpty(shellRoot.displayToggleStdout).trim();
            let success = false;
            if (raw) {
                try {
                    const parsed = JSON.parse(raw);
                    success = !!(parsed && parsed.toggled_output === target);
                    if (success) {
                        shellRoot.updateDisplayLayoutFromSnapshot(parsed);
                    }
                } catch (error) {
                    console.warn("display.toggle_output.parse:", raw, error);
                }
            }

            if (!success) {
                const stderr = shellRoot.stringOrEmpty(shellRoot.displayToggleStderr).trim();
                if (stderr) {
                    console.warn("display.toggle_output failed:", stderr);
                }
            }
            shellRoot.displayToggleTarget = "";
            shellRoot.displayToggleStdout = "";
            shellRoot.displayToggleStderr = "";
        }
    }

    Process {
        id: displayScaleProcess
        command: [runtimeConfig.i3pmBin, "display", "set-scale", "", "1.0"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.displayScaleStdout += data + "\n";
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (!message) {
                    return;
                }
                shellRoot.displayScaleStderr += message + "\n";
                console.warn("display.set_scale:", message);
            }
        }
        onExited: function () {
            const target = shellRoot.stringOrEmpty(shellRoot.displayScaleTarget);
            const raw = shellRoot.stringOrEmpty(shellRoot.displayScaleStdout).trim();
            let success = false;
            if (raw) {
                try {
                    const parsed = JSON.parse(raw);
                    success = !!(parsed && parsed.scaled_output === target);
                    if (success) {
                        shellRoot.updateDisplayLayoutFromSnapshot(parsed);
                    }
                } catch (error) {
                    console.warn("display.set_scale.parse:", raw, error);
                }
            }

            if (!success) {
                const stderr = shellRoot.stringOrEmpty(shellRoot.displayScaleStderr).trim();
                if (stderr) {
                    console.warn("display.set_scale failed:", stderr);
                }
            }
            shellRoot.displayScaleTarget = "";
            shellRoot.displayScaleStdout = "";
            shellRoot.displayScaleStderr = "";
        }
    }

    // Cast toggle action (`cast toggle` — stops a live cast, otherwise extends
    // to the TV). Command is replaced by shellRoot.castToggle(); the probe
    // reruns on exit so the chip reflects the settled cast state.
    Process {
        id: castActionProcess
        command: [runtimeConfig.castExtendBin, "status"]
        running: false
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("cast.action:", data);
                }
            }
        }
        onExited: function () {
            castWatcher.running = true;
        }
    }

    Process {
        id: brightnessActionProcess
        command: [runtimeConfig.brightnessActionBin, "set", "display", "50"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.brightnessActionStdout += data + "\n";
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (!message) {
                    return;
                }
                shellRoot.brightnessActionStderr += message + "\n";
                shellRoot.brightnessActionError = message;
                console.warn("brightness.action:", message);
            }
        }
        onExited: function () {
            shellRoot.finishBrightnessAction();
        }
    }

    Process {
        id: lidPolicyApplyProcess
        command: [runtimeConfig.pkexecBin, runtimeConfig.lidPolicyApplyBin, "apply", "suspend", "lock", "ignore"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.lidPolicyApplyStdout += data + "\n";
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (!message) {
                    return;
                }
                shellRoot.lidPolicyApplyStderr += message + "\n";
                console.warn("lid.policy.apply:", message);
            }
        }
        onExited: function () {
            shellRoot.finishLidPolicyApply();
        }
    }

    Process {
        id: lidInhibitActionProcess
        command: [runtimeConfig.lidInhibitBin, "status"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.lidInhibitActionStdout += data + "\n";
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (!message) {
                    return;
                }
                shellRoot.lidInhibitActionStderr += message + "\n";
                console.warn("lid.inhibit:", message);
            }
        }
        onExited: function () {
            shellRoot.finishLidInhibitAction();
        }
    }

    Timer {
        id: sessionClosePendingPruneTimer
        interval: 1500
        repeat: true
        // Ticks only while there is something to prune; the dashboard-apply hook
        // already prunes on every snapshot, so an empty map needs no timer.
        running: Object.keys(shellRoot.sessionClosePendingMap).length > 0
        onTriggered: shellRoot.pruneSessionClosePending()
    }

    Timer {
        id: lidPolicyRestartTimer
        interval: 5000
        repeat: false
        onTriggered: lidPolicyWatcher.running = true
    }

    IpcHandler {
        target: "shell"

        // ----- Generic surface verbs -----
        // Every shell surface is addressable by id through these four calls
        // (see shellRoot.surfaceRegistry), so keybindings, hooks, and scripts
        // use `runtime-shell toggle <id> [json]` instead of one wrapper script
        // per function. The bespoke functions below stay as aliases.
        function ping(): string {
            return "ok";
        }

        function summon(id: string, payload: string): string {
            return shellRoot.summonSurface(id, payload);
        }

        function hide(id: string): string {
            return shellRoot.hideSurface(id);
        }

        function toggle(id: string, payload: string): string {
            return shellRoot.toggleSurface(id, payload);
        }

        function listSurfaces(): string {
            return shellRoot.listSurfaces();
        }

        function showKeybindings() {
            shellRoot.showLauncher("keys", "");
        }

        // `runtime-shell call showOsd brightness 55` / `... volume ""`.
        function showOsd(kind: string, level: string): string {
            return shellRoot.showOsdFromIpc(kind, level);
        }

        function lock(): string {
            return shellRoot.lockSession();
        }

        function refreshAgentUsage(): string {
            return shellRoot.refreshAgentUsage();
        }

        function setTheme(name: string): string {
            return shellRoot.setTheme(name);
        }

        function currentTheme(): string {
            return shellRoot.colors.name;
        }

        function nextAgentUsage(): string {
            return shellRoot.cycleAgentUsage();
        }

        // `runtime-shell call replayNotifications 3`
        function replayNotifications(count: string): string {
            return shellRoot.replayNotifications(count);
        }

        function toggleKeybindings() {
            shellRoot.toggleKeybindings();
        }

        function togglePanel() {
            shellRoot.togglePanelVisibility();
        }

        function toggleDockMode() {
            shellRoot.dockedMode = !shellRoot.dockedMode;
        }

        function showWindowsTab() {
            shellRoot.showRuntimePanelSection("windows");
        }

        function showSessionsTab() {
            shellRoot.showRuntimePanelSection("sessions");
        }

        function showHealthTab() {
            shellRoot.showRuntimePanelSection("balanced");
        }

        function nextSession() {
            shellRoot.cycleSessions("next");
        }

        function prevSession() {
            shellRoot.cycleSessions("prev");
        }

        function nextLauncherSession() {
            shellRoot.cycleLauncherSessions("next");
        }

        function prevLauncherSession() {
            shellRoot.cycleLauncherSessions("prev");
        }

        function commitLauncherSession() {
            shellRoot.commitLauncherSessionSwitch();
        }

        function nextLauncherWindow() {
            shellRoot.cycleExposeWindows("next");
        }

        function prevLauncherWindow() {
            shellRoot.cycleExposeWindows("prev");
        }

        function commitLauncherWindow() {
            shellRoot.commitExposeSwitch();
        }

        // Alt+Tab: MRU ring of RUNNING APPS (one entry per app), launcher-style.
        function nextLauncherRunning() {
            shellRoot.cycleLauncherRunning("next");
        }

        function prevLauncherRunning() {
            shellRoot.cycleLauncherRunning("prev");
        }

        function commitLauncherRunning() {
            shellRoot.commitLauncherRunningSwitch();
        }

        // Bound to sway's `--release Alt_L`: commits whichever Alt-held window
        // switcher is open (running-app ring or exposé). A no-op otherwise, so
        // firing on every Alt release is harmless.
        function commitWindowSwitch() {
            shellRoot.commitLauncherRunningSwitch();
            shellRoot.commitLauncherWindowSwitch();
            shellRoot.commitExposeSwitch();
        }

        // Silent (no UI) window actions, the window twins of nextSession /
        // focusLastSession.
        function nextAppWindow() {
            shellRoot.cycleFocusedAppWindows("next");
        }

        function prevAppWindow() {
            shellRoot.cycleFocusedAppWindows("prev");
        }

        function focusLastWindow() {
            shellRoot.focusLastWindow();
        }

        function openWindowSwitcher() {
            shellRoot.openExpose();
        }

        function toggleWindowSwitcher() {
            shellRoot.toggleExpose();
        }

        function toggleAgentMonitor() {
            shellRoot.toggleAgentMonitor("");
        }

        function focusLastSession() {
            shellRoot.focusLastSession();
        }

        function togglePowerMenu() {
            shellRoot.powerMenuVisible = !shellRoot.powerMenuVisible;
        }

        function toggleLauncher() {
            shellRoot.toggleLauncher();
        }

        function toggleSettings() {
            if (!shellRoot.settingsVisible) {
                shellRoot.openSettings("commands");
                return;
            }
            shellRoot.closeSettings();
        }

        function showSettings(section: string) {
            shellRoot.openSettings(section);
        }

        function toggleDisplaySelector() {
            if (shellRoot.displaySelectorVisible) {
                shellRoot.closeDisplaySelector();
                return;
            }
            shellRoot.openDisplaySelector("");
        }

        function toggleNotifications() {
            shellRoot.toggleNotifications();
        }

        function toggleNotificationDnd() {
            shellRoot.toggleNotificationDnd();
        }

        function clearNotifications() {
            shellRoot.clearNotifications();
        }
    }

}
