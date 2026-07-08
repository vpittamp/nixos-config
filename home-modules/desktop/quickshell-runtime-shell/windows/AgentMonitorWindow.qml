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

    property var sessions: []
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

    function refreshAgentSessions(preserveViewport) {
        const savedContentY = preserveViewport && monitorWindow.monitorReady ? Number(agentList.contentY || 0) : 0;
        sessions = root.panelSessions();
        if (preserveViewport && monitorWindow.monitorReady) {
            Qt.callLater(function() {
                monitorWindow.restoreAgentListContentY(savedContentY);
            });
        }
    }

    Component.onCompleted: {
        monitorReady = true;
        refreshAgentSessions(false);
    }

    onVisibleChanged: {
        if (visible) {
            refreshAgentSessions(false);
        }
    }

    Connections {
        target: root

        function onDashboardChanged() {
            monitorWindow.refreshAgentSessions(true);
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
                    text: monitorWindow.sessions.length
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
                values: monitorWindow.sessions
                objectProp: "modelData"
            }

            ListView {
                id: agentList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: monitorWindow.sessions.length > 0
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
                    width: agentList.width
                    rootObject: root
                    colorsObject: colors
                    session: modelData
                    selected: false
                    currentOverrideSet: true
                    currentOverride: root.sessionCurrentOverride(modelData)
                    interactive: true
                    compact: true
                    showHostToken: true
                    showCurrentChip: false
                    closePending: root.sessionClosePending(modelData)
                    onClicked: root.focusSession(modelData)
                    onCloseRequested: root.closeSession(modelData)
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: monitorWindow.sessions.length === 0

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
