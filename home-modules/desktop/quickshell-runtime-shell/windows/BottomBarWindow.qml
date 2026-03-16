import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    required property var modelData
    readonly property var barScreen: modelData
    readonly property string barOutputName: root.screenOutputName(barScreen)

    screen: barScreen
    visible: runtimeConfig.perMonitorBars
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    implicitHeight: runtimeConfig.barHeight
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
                        color: root.panelVisible ? (bottomPanelToggleMouse.containsMouse ? colors.blue : colors.blue) : (bottomPanelToggleMouse.containsMouse ? colors.card : colors.cardAlt)
                        border.color: root.panelVisible ? colors.blue : (bottomPanelToggleMouse.containsMouse ? colors.borderStrong : colors.border)
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
