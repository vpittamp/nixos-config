import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".." as RootComponents

// Always-on-top AI-agents monitor strip. Designed to sit on the side of a
// fullscreen app (e.g. the YouTube / YouTube TV PWA) so agent progress can be
// watched WHILE the video plays. On the Overlay layer (renders above fullscreen
// windows), narrow, and exclusiveZone 0 so it reserves no space and leaves the
// rest of the screen — including the video — clickable.
//
// The strip is mouse-interactive (click a row to jump to that session, wheel to
// scroll), but it must not take keyboard focus from the terminal/video surface
// underneath. Pointer-only focus keeps Herdr selection and key routing stable.
PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: monitorWindow

    // Keep the ListView model keyed by stable session identity. The row content
    // still resolves live dashboard data by key, but status/focus ticks no longer
    // reset delegates under the pointer and drop click releases.
    readonly property int dashboardGeneration: root.dashboardGeneration(root.dashboard)
    property var sessionEntries: []
    property bool monitorReady: false

    function clampListContentY(list, value) {
        if (!list) {
            return;
        }
        const maxY = Math.max(0, Number(list.contentHeight || 0) - Number(list.height || 0));
        list.contentY = Math.max(0, Math.min(Number(value || 0), maxY));
    }

    function restoreAgentListContentY(value) {
        if (!monitorWindow.monitorReady) {
            return;
        }
        clampListContentY(agentList, value);
        Qt.callLater(function() {
            clampListContentY(agentList, value);
        });
    }

    function buildSessionEntries() {
        const sessions = root.panelSessions();
        const entries = [];
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            const key = root.sessionIdentityKey(session);
            if (!key) {
                continue;
            }
            entries.push({
                "identity_key": key,
                "session_key": root.stringOrEmpty(session && session.session_key),
                "snapshot": session,
            });
        }
        return entries;
    }

    function sameSessionEntries(left, right) {
        const a = root.arrayOrEmpty(left);
        const b = root.arrayOrEmpty(right);
        if (a.length !== b.length) {
            return false;
        }
        for (let i = 0; i < a.length; i += 1) {
            if (root.stringOrEmpty(a[i] && a[i].identity_key) !== root.stringOrEmpty(b[i] && b[i].identity_key)) {
                return false;
            }
        }
        return true;
    }

    function refreshSessionEntries(preserveViewport) {
        const savedContentY = preserveViewport && monitorWindow.monitorReady ? Number(agentList.contentY || 0) : 0;
        const next = buildSessionEntries();
        if (!sameSessionEntries(sessionEntries, next)) {
            sessionEntries = next;
        }
        if (preserveViewport && monitorWindow.monitorReady) {
            Qt.callLater(function() {
                monitorWindow.restoreAgentListContentY(savedContentY);
            });
        }
    }

    function liveSessionForEntry(entry, _generation) {
        const sessionKey = root.stringOrEmpty(entry && entry.session_key);
        if (sessionKey) {
            const session = root.sessionByKey(sessionKey);
            if (session) {
                return session;
            }
        }

        const identityKey = root.stringOrEmpty(entry && entry.identity_key);
        const sessions = root.panelSessions();
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            if (root.sessionIdentityKey(session) === identityKey) {
                return session;
            }
        }

        return entry && entry.snapshot ? entry.snapshot : null;
    }

    Component.onCompleted: {
        monitorReady = true;
        refreshSessionEntries(false);
    }

    onVisibleChanged: {
        if (visible) {
            refreshSessionEntries(false);
        }
    }

    Connections {
        target: root

        function onDashboardChanged() {
            monitorWindow.refreshSessionEntries(true);
        }
    }

    screen: root.findScreenByOutputName(root.agentMonitorOutputName) || root.activeScreen
    visible: root.agentMonitorVisible
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.right: true
    implicitWidth: 360
    exclusiveZone: 0
    focusable: false
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-agent-monitor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 14
        // Dark glass: agent text stays readable while the video shows faintly
        // through the strip (idle SessionRows are transparent).
        color: Qt.rgba(0.03, 0.05, 0.08, 0.82)
        border.color: colors.borderStrong
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "AI Agents"
                    color: colors.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: monitorWindow.sessionEntries.length
                    color: colors.muted
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    color: closeMouse.containsMouse ? colors.cardAlt : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: colors.muted
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeAgentMonitor()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: colors.lineSoft
            }

            ScriptModel {
                id: agentSessionsModel
                values: monitorWindow.sessionEntries
                objectProp: "modelData"
            }

            ListView {
                id: agentList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: monitorWindow.sessionEntries.length > 0
                clip: true
                spacing: 4
                model: agentSessionsModel
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 1200

                ScrollBar.vertical: ScrollBar {
                    policy: agentList.contentHeight > agentList.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                }

                delegate: RootComponents.SessionRow {
                    required property var modelData
                    readonly property var liveSession: monitorWindow.liveSessionForEntry(modelData, monitorWindow.dashboardGeneration)
                    width: agentList.width
                    rootObject: root
                    colorsObject: colors
                    session: liveSession
                    selected: false
                    currentOverrideSet: true
                    currentOverride: root.sessionCurrentOverride(liveSession)
                    interactive: true
                    compact: true
                    showHostToken: true
                    showCurrentChip: false
                    closePending: root.sessionClosePending(liveSession)
                    onClicked: root.focusSession(liveSession)
                    onCloseRequested: root.closeSession(liveSession)
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: monitorWindow.sessionEntries.length === 0

                Text {
                    anchors.centerIn: parent
                    text: "No active agents"
                    color: colors.subtle
                    font.pixelSize: 11
                }
            }
        }
    }
}
