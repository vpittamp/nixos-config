import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Minimalist always-on-top AI-agents monitor strip. Designed to sit on the side
// of a fullscreen app (e.g. the YouTube TV PWA) so agent progress can be watched
// without switching apps. On the Overlay layer (renders above fullscreen
// windows), narrow, and NON-focusable + exclusiveZone 0 so the underlying app
// keeps keyboard focus and the rest of the screen.
PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: monitorWindow

    readonly property var sessions: root.activeSessions()

    function statusColor(s) {
        const st = root.stringOrEmpty(s && s.agent_status);
        if (st === "working") {
            return colors.teal;
        }
        if (st === "blocked") {
            return colors.red;
        }
        if (st === "done") {
            return colors.green;
        }
        return colors.muted;
    }

    function statusLabel(s) {
        const st = root.stringOrEmpty(s && s.agent_status);
        if (st === "working") {
            return "Working";
        }
        if (st === "blocked") {
            return "Blocked";
        }
        if (st === "done") {
            return "Done";
        }
        if (st === "idle") {
            return "Idle";
        }
        return st ? st : "—";
    }

    screen: root.findScreenByOutputName(root.agentMonitorOutputName) || root.activeScreen
    visible: root.agentMonitorVisible
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.right: true
    implicitWidth: 300
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
        // Semi-transparent so the TV faintly shows through the strip edges.
        color: Qt.rgba(0.03, 0.05, 0.08, 0.80)
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

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: rowsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: rowsCol
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: monitorWindow.sessions

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var session: modelData
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 9
                            color: rowMouse.containsMouse ? colors.cardAlt : Qt.rgba(1, 1, 1, 0.02)
                            Behavior on color { ColorAnimation { duration: root.fastColorMs } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 9

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 9
                                    height: 9
                                    radius: 5
                                    color: monitorWindow.statusColor(session)
                                    // Pulse while the agent is actively working.
                                    SequentialAnimation on opacity {
                                        running: root.stringOrEmpty(session && session.agent_status) === "working"
                                        loops: Animation.Infinite
                                        alwaysRunToEnd: true
                                        NumberAnimation { from: 1.0; to: 0.35; duration: 700 }
                                        NumberAnimation { from: 0.35; to: 1.0; duration: 700 }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.sessionPrimaryLabel(session)
                                        color: colors.text
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.sessionSecondaryLabel(session)
                                        color: colors.subtle
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: monitorWindow.statusLabel(session)
                                    color: monitorWindow.statusColor(session)
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.focusSession(session)
                            }
                        }
                    }
                }
            }

            Text {
                visible: monitorWindow.sessions.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                horizontalAlignment: Text.AlignHCenter
                text: "No active agents"
                color: colors.subtle
                font.pixelSize: 11
            }
        }
    }
}
