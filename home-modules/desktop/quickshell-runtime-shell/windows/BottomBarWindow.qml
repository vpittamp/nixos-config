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
    property bool fallbackMode: false
    property string fallbackOutputName: ""
    readonly property var barScreen: fallbackMode ? null : modelData
    readonly property string barOutputName: fallbackMode ? root.stringOrEmpty(fallbackOutputName) : root.screenOutputName(barScreen)
    property var barWorkspaces: []

    function refreshBarWorkspaces() {
        barWorkspaces = root.barWorkspacesForOutput(barOutputName);
    }

    onBarOutputNameChanged: refreshBarWorkspaces()
    Component.onCompleted: refreshBarWorkspaces()

    Connections {
        target: root

        function onDashboardChanged() {
            refreshBarWorkspaces();
        }
    }

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
                Layout.preferredWidth: Math.max(184, contextTitleText.implicitWidth + contextOutputText.implicitWidth + (contextGitChip.visible ? contextGitText.implicitWidth + 18 : 0) + 40)
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
                        color: root.currentContextExecutionMode() === "ssh" ? colors.teal : colors.accent
                    }

                    Text {
                        id: contextTitleText
                        Layout.fillWidth: true
                        text: root.currentContextTitle()
                        color: colors.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: contextGitChip
                        visible: root.currentContextGitChipVisible()
                        width: contextGitText.implicitWidth + 10
                        height: 16
                        radius: 5
                        color: root.currentContextGitChipBackground()
                        border.color: "transparent"
                        border.width: 0

                        Text {
                            id: contextGitText
                            anchors.centerIn: parent
                            text: root.currentContextGitChipText()
                            color: root.currentContextGitChipForeground()
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        id: contextOutputText
                        text: barOutputName || root.modeLabel((dashboard.active_context || {}).execution_mode)
                        color: colors.muted
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: contextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                ToolTip {
                    visible: contextMouse.containsMouse && root.currentContextGitTooltip().length > 0
                    text: root.currentContextGitTooltip()
                    delay: 500
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
                            model: barWorkspaces

                            delegate: Rectangle {
                                required property var modelData
                                readonly property var workspace: modelData
                                readonly property string workspaceLabelValue: root.workspaceLabel(workspace)
                                readonly property bool workspaceFocused: root.workspaceIsFocused(workspace)
                                readonly property bool workspaceHovered: workspaceMouse.containsMouse
                                readonly property var workspaceIcons: root.arrayOrEmpty(workspace && workspace.icon_sources)
                                readonly property int workspaceCount: Number(workspace && workspace.window_count || 0)
                                width: Math.max(34, workspaceText.implicitWidth + (workspaceIcons.length ? 30 : 0) + (workspaceCount > 1 ? 14 : 0) + 12)
                                height: 28
                                radius: 8
                                color: workspaceFocused ? colors.blue : (workspaceHovered ? colors.card : (root.boolOrFalse(workspace && workspace.active) ? colors.card : colors.cardAlt))
                                border.color: workspaceFocused ? colors.blue : (root.boolOrFalse(workspace && workspace.urgent) ? colors.red : (workspaceHovered ? colors.borderStrong : colors.border))
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
                                                border.color: workspaceFocused ? colors.blue : colors.borderStrong
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
                                        text: workspaceLabelValue
                                        color: workspaceFocused ? colors.bg : (workspaceHovered ? colors.text : colors.textDim)
                                        font.pixelSize: 11
                                        font.weight: workspaceFocused ? Font.DemiBold : Font.Medium
                                    }

                                    Rectangle {
                                        visible: workspaceCount > 1
                                        width: 12
                                        height: 12
                                        radius: 4
                                        color: workspaceFocused ? colors.bg : colors.card
                                        border.color: workspaceFocused ? colors.bg : colors.border
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: String(workspaceCount)
                                            color: workspaceFocused ? colors.blue : colors.muted
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                MouseArea {
                                    id: workspaceMouse
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: root.activateWorkspace(workspace)
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
                            onClicked: root.togglePanelVisibility()
                        }
                    }
                }
            }
        }
    }
}
