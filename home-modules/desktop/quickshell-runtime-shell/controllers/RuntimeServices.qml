import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Item {
    id: services
    visible: false

    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property QtObject assistantService

    property alias clockRef: clock
    property alias dashboardRestartTimerRef: dashboardRestartTimer
    property alias notificationRestartTimerRef: notificationRestartTimer
    property alias networkRefreshTimerRef: networkRefreshTimer
    property alias systemStatsRestartTimerRef: systemStatsRestartTimer
    property alias launcherFocusTimerRef: launcherFocusTimer
    property alias launcherQueryDebounceRef: launcherQueryDebounce
    property alias launcherSessionSwitcherOpenTimerRef: launcherSessionSwitcherOpenTimer
    property alias sessionPreviewDebounceRef: sessionPreviewDebounce
    property alias sessionPreviewFollowTimerRef: sessionPreviewFollowTimer
    property alias settingsFocusTimerRef: settingsFocusTimer
    property alias settingsCommandQueryDebounceRef: settingsCommandQueryDebounce
    property alias sessionClosePendingPruneTimerRef: sessionClosePendingPruneTimer
    property alias dashboardWatcherRef: dashboardWatcher
    property alias notificationWatcherRef: notificationWatcher
    property alias networkWatcherRef: networkWatcher
    property alias systemStatsWatcherRef: systemStatsWatcher
    property alias snippetEditorProcessRef: snippetEditorProcess
    property alias settingsCommandQueryProcessRef: settingsCommandQueryProcess
    property alias launcherQueryProcessRef: launcherQueryProcess
    property alias sessionPreviewProcessRef: sessionPreviewProcess
    property alias sessionCloseProcessRef: sessionCloseProcess

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
                const openingSessionSwitcher = shellRoot.launcherSessionSwitcherPendingDelta !== 0;
                shellRoot.launcherMode = openingSessionSwitcher ? "sessions" : "apps";
                shellRoot.launcherSessionSwitcherActive = openingSessionSwitcher;
                shellRoot.launcherQuery = "";
                shellRoot.launcherError = "";
                shellRoot.launcherEntries = [];
                shellRoot.launcherSelectedIndex = 0;
                shellRoot.launcherPointerSelectionEnabled = true;
                shellRoot.launcherNormalizingInput = true;
                if (shellRoot.launcherField) {
                    shellRoot.launcherField.text = "";
                }
                shellRoot.launcherNormalizingInput = false;
                shellRoot.resetLauncherListViewport();
                launcherQueryDebounce.restart();
                launcherFocusTimer.restart();
                sessionPreviewDebounce.restart();
                return;
            }

            shellRoot.launcherLoading = false;
            shellRoot.launcherError = "";
            shellRoot.launcherEntries = [];
            shellRoot.launcherSessionSwitcherActive = false;
            shellRoot.launcherSessionSwitcherPendingDelta = 0;
            shellRoot.launcherSessionEntryOrder = [];
            shellRoot.launcherSelectedIndex = 0;
            shellRoot.launcherPointerSelectionEnabled = true;
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
            if (shellRoot.launcherMode !== "sessions") {
                shellRoot.launcherSessionSwitcherActive = false;
                shellRoot.launcherSessionSwitcherPendingDelta = 0;
                shellRoot.launcherSessionEntryOrder = [];
                shellRoot.clearSessionPreview();
            }
            shellRoot.resetLauncherListViewport();
            if (shellRoot.launcherVisible) {
                launcherQueryDebounce.restart();
                launcherFocusTimer.restart();
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
            inlineReplySupported: false
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
        id: systemStatsRestartTimer
        interval: 2000
        repeat: false
        onTriggered: systemStatsWatcher.running = true
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
        id: sessionPreviewDebounce
        interval: 75
        repeat: false
        onTriggered: shellRoot.restartSessionPreview()
    }

    Timer {
        id: sessionPreviewFollowTimer
        interval: 16
        repeat: false
        onTriggered: shellRoot.sessionPreviewScrollToBottom()
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

    Process {
        id: dashboardWatcher
        command: [runtimeConfig.i3pmBin, "dashboard", "watch", "--interval", String(runtimeConfig.dashboardHeartbeatMs)]
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
        id: sessionPreviewProcess
        command: [runtimeConfig.i3pmBin, "session", "preview", "", "--follow", "--jsonl", "--lines", "100"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.parseSessionPreview(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                if (data && data.trim()) {
                    console.warn("session.preview:", data);
                }
            }
        }
        onExited: function () {
            if (shellRoot.sessionPreviewStopExpected) {
                shellRoot.sessionPreviewStopExpected = false;
                return;
            }
            if (shellRoot.launcherVisible && shellRoot.launcherMode === "sessions" && shellRoot.activeLauncherSessionEntry() !== null && shellRoot.stringOrEmpty(shellRoot.sessionPreview.status) === "loading") {
                shellRoot.sessionPreview = Object.assign(shellRoot.emptySessionPreview(), {
                    status: "error",
                    kind: "error",
                    session_key: shellRoot.stringOrEmpty(shellRoot.activeLauncherSessionEntry().session_key || shellRoot.activeLauncherSessionEntry().identifier),
                    message: "Unable to start session preview."
                });
            }
        }
    }

    Process {
        id: sessionCloseProcess
        command: [runtimeConfig.i3pmBin, "session", "close", "", "--json"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                shellRoot.sessionCloseProcessStdout += data + "\n";
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                const message = data && data.trim();
                if (!message) {
                    return;
                }
                shellRoot.sessionCloseProcessStderr += message + "\n";
                console.warn("session.close:", message);
            }
        }
        onExited: function () {
            const targetKey = shellRoot.stringOrEmpty(shellRoot.sessionCloseProcessTargetKey);
            let success = false;
            const raw = shellRoot.stringOrEmpty(shellRoot.sessionCloseProcessStdout).trim();
            if (raw) {
                try {
                    const parsed = JSON.parse(raw);
                    success = !!(parsed && parsed.success);
                } catch (error) {
                    console.warn("session.close.parse:", raw, error);
                }
            }
            if (!success) {
                shellRoot.clearSessionClosePending(targetKey);
            }
            shellRoot.sessionCloseProcessTargetKey = "";
            shellRoot.sessionCloseProcessStdout = "";
            shellRoot.sessionCloseProcessStderr = "";
            shellRoot.pruneSessionClosePending();
        }
    }

    Timer {
        id: sessionClosePendingPruneTimer
        interval: 1500
        repeat: true
        running: true
        onTriggered: shellRoot.pruneSessionClosePending()
    }

    IpcHandler {
        target: "shell"

        function togglePanel() {
            shellRoot.panelVisible = !shellRoot.panelVisible;
        }

        function toggleDockMode() {
            shellRoot.dockedMode = !shellRoot.dockedMode;
        }

        function showWindowsTab() {
            shellRoot.showRuntimePanel();
        }

        function showSessionsTab() {
            shellRoot.showRuntimePanel();
        }

        function showHealthTab() {
            shellRoot.showRuntimePanel();
        }

        function showAssistant() {
            shellRoot.showAssistantPanel();
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

        function focusLastSession() {
            shellRoot.focusLastSession();
        }

        function togglePowerMenu() {
            shellRoot.powerMenuVisible = !shellRoot.powerMenuVisible;
        }

        function toggleLauncher() {
            if (!shellRoot.launcherVisible) {
                shellRoot.settingsVisible = false;
            }
            shellRoot.launcherVisible = !shellRoot.launcherVisible;
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

    IpcHandler {
        target: "assistant"

        function toggle() {
            shellRoot.toggleAssistantPanel();
        }

        function open() {
            shellRoot.showAssistantPanel();
        }

        function close() {
            shellRoot.panelVisible = false;
        }

        function send(message: string) {
            shellRoot.showAssistantPanel();
            assistantService.sendMessage(message);
        }

        function newChat() {
            shellRoot.showAssistantPanel();
            assistantService.newChat();
        }

        function setProvider(provider: string) {
            assistantService.setProvider(provider);
        }

        function setModel(model: string) {
            assistantService.setModel(model);
        }

        function translateText(text: string, targetLang: string) {
            shellRoot.showAssistantPanel();
            assistantService.activeTab = "translate";
            assistantService.translate(text, targetLang || assistantService.targetLanguage, assistantService.sourceLanguage);
        }
    }
}
