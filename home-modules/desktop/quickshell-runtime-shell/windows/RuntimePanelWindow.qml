import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import ".." as RootComponents

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    required property QtObject assistantService
    id: panelWindow
    screen: root.primaryScreen
    visible: root.panelVisible
    color: "transparent"
    implicitWidth: runtimeConfig.panelWidth
    anchors.top: true
    anchors.bottom: true
    anchors.right: true
    exclusiveZone: root.dockedMode ? implicitWidth : 0
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 10
                    color: root.panelSection === "runtime" ? colors.blueBg : colors.cardAlt
                    border.color: root.panelSection === "runtime" ? colors.blue : colors.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Runtime"
                        color: root.panelSection === "runtime" ? colors.blue : colors.textDim
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showRuntimePanel()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 10
                    color: root.panelSection === "assistant" ? colors.accentBg : colors.cardAlt
                    border.color: root.panelSection === "assistant" ? colors.accent : colors.border
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "Agents"
                            color: root.panelSection === "assistant" ? colors.accent : colors.textDim
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            visible: assistantService.isGenerating
                            width: 7
                            height: 7
                            radius: 4
                            color: colors.accent
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showAssistantPanel()
                    }
                }
            }

            ColumnLayout {
                id: runtimePanelContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                visible: root.panelSection === "runtime"

                Rectangle {
                id: worktreeSummaryCard
                implicitHeight: 78
                Layout.preferredHeight: implicitHeight
                Layout.fillWidth: true
                radius: 12
                color: colors.panel
                border.color: colors.border
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
                                color: root.activeTerminalAvailable() ? colors.accentBg : (activeTerminalMouse.containsMouse ? colors.cardAlt : colors.card)
                                border.color: root.activeTerminalAvailable() ? colors.accent : (activeTerminalMouse.containsMouse ? colors.borderStrong : colors.border)
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

                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.notificationsBackendNative() || root.notificationFeed.length > 0

                Text {
                    text: "Notifications"
                    color: colors.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: notificationSectionCount.implicitWidth + 12
                    height: 20
                    radius: 6
                    color: root.notificationUnreadCount() > 0 ? colors.blueBg : colors.cardAlt
                    border.color: root.notificationUnreadCount() > 0 ? colors.blue : colors.lineSoft
                    border.width: 1

                    Text {
                        id: notificationSectionCount
                        anchors.centerIn: parent
                        text: root.notificationDisplayCount(root.notificationUnreadCount())
                        color: root.notificationUnreadCount() > 0 ? colors.blue : colors.muted
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    visible: root.notificationDnd
                    height: 20
                    radius: 6
                    color: colors.amberBg
                    border.color: colors.amber
                    border.width: 1
                    Layout.preferredWidth: notificationDndText.implicitWidth + 12

                    Text {
                        id: notificationDndText
                        anchors.centerIn: parent
                        text: "DND"
                        color: colors.amber
                        font.pixelSize: 8
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

                Rectangle {
                    height: 22
                    radius: 7
                    color: notificationToggleMouse.containsMouse ? colors.cardAlt : colors.card
                    border.color: notificationToggleMouse.containsMouse ? colors.borderStrong : colors.border
                    border.width: 1
                    Layout.preferredWidth: notificationToggleText.implicitWidth + 16

                    Text {
                        id: notificationToggleText
                        anchors.centerIn: parent
                        text: root.notificationCenterVisible ? "Hide" : "Show"
                        color: colors.text
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: notificationToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleNotifications()
                    }
                }

                Rectangle {
                    visible: root.notificationFeed.length > 0
                    height: 22
                    radius: 7
                    color: notificationClearMouse.containsMouse ? colors.redBg : colors.card
                    border.color: notificationClearMouse.containsMouse ? colors.red : colors.border
                    border.width: 1
                    Layout.preferredWidth: notificationClearText.implicitWidth + 16

                    Text {
                        id: notificationClearText
                        anchors.centerIn: parent
                        text: "Clear"
                        color: notificationClearMouse.containsMouse ? colors.red : colors.textDim
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: notificationClearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearNotifications()
                    }
                }
            }

            RootComponents.NotificationRailCard {
                Layout.fillWidth: true
                visible: root.notificationHeroItem() !== null
                rootObject: root
                colorsObject: colors
                itemData: root.notificationHeroItem()
                compact: !root.notificationCenterVisible
                onDismissRequested: root.dismissNotification(notificationId)
                onActionInvoked: root.invokeNotificationAction(notificationId, actionId)
                onMarkReadRequested: root.markNotificationRead(notificationId)
                onDetailRequested: root.showNotificationDetail(notificationId)
            }

            ScriptModel {
                id: notificationPanelModel
                values: root.notificationCenterVisible ? root.notificationPanelItems().slice(1) : []
                objectProp: "modelData"
            }

            ListView {
                id: notificationRailList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 288)
                visible: root.notificationCenterVisible && count > 0
                clip: true
                spacing: 8
                model: notificationPanelModel
                boundsBehavior: Flickable.StopAtBounds

                delegate: RootComponents.NotificationRailCard {
                    required property var modelData
                    width: notificationRailList.width
                    rootObject: root
                    colorsObject: colors
                    itemData: modelData
                    compact: false
                    onDismissRequested: root.dismissNotification(notificationId)
                    onActionInvoked: root.invokeNotificationAction(notificationId, actionId)
                    onMarkReadRequested: root.markNotificationRead(notificationId)
                    onDetailRequested: root.showNotificationDetail(notificationId)
                }
            }

            Rectangle {
                visible: root.panelSessions().length > 0 || root.herdrSpaces().length > 0
                Layout.fillWidth: true
                Layout.fillHeight: root.runtimePanelSectionExpanded("sessions")
                Layout.minimumHeight: root.runtimePanelSectionExpanded("sessions") ? 180 : 60
                Layout.preferredHeight: root.runtimePanelSectionPreferredHeight("sessions")
                radius: 12
                color: root.runtimePanelSectionExpanded("sessions") ? colors.panel : colors.cardAlt
                border.color: root.runtimePanelSectionExpanded("sessions") ? colors.lineSoft : colors.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 10
                        color: root.runtimePanelSectionExpanded("sessions") ? colors.blueWash : colors.card
                        border.color: colors.lineSoft
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: root.runtimePanelSectionExpanded("sessions") ? "▾" : "▸"
                                color: root.runtimePanelSectionExpanded("sessions") ? colors.blue : colors.textDim
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: "Herdr Monitor"
                                color: colors.text
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.runtimePanelSectionSummary("sessions")
                                color: colors.subtle
                                font.pixelSize: 8
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                width: sessionSectionCount.implicitWidth + 12
                                height: 20
                                radius: 6
                                color: colors.bg
                                border.color: "transparent"
                                border.width: 0

                                Text {
                                    id: sessionSectionCount
                                    anchors.centerIn: parent
                                    text: String(root.runtimePanelSectionCount("sessions"))
                                    color: colors.muted
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleRuntimePanelSection("sessions")
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.runtimePanelSectionCollapsed("sessions")
                        text: "spaces and agents"
                        color: colors.subtle
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        id: herdrSessionContent
                        readonly property int agentCount: root.panelSessions().length
                        readonly property int rowHeight: 48
                        readonly property int rowRadius: 7
                        readonly property int rowSpacing: 6
                        readonly property int chipHeight: 18
                        readonly property real spacesMaxFraction: agentCount <= 0 ? 0.86 : (agentCount <= 2 ? 0.68 : 0.52)
                        readonly property int spacesMaxHeight: Math.max(150, Math.floor(root.runtimePanelSectionPreferredHeight("sessions") * spacesMaxFraction))
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.runtimePanelSectionExpanded("sessions")
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "spaces"
                                color: colors.text
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                width: spacesCountText.implicitWidth + 10
                                height: 18
                                radius: 6
                                color: colors.bg
                                border.color: "transparent"
                                border.width: 0

                                Text {
                                    id: spacesCountText
                                    anchors.centerIn: parent
                                    text: String(root.visibleHerdrSpaces().length)
                                    color: colors.muted
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                radius: 1
                                color: colors.lineSoft
                            }
                        }

                        ScriptModel {
                            id: herdrSpacesModel
                            values: root.visibleHerdrSpaces()
                            objectProp: "modelData"
                        }

                        ListView {
                            id: herdrSpacesList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(contentHeight, herdrSessionContent.spacesMaxHeight)
                            Layout.maximumHeight: herdrSessionContent.spacesMaxHeight
                            Layout.minimumHeight: visible ? Math.min(contentHeight, 96) : 0
                            visible: count > 0
                            clip: true
                            spacing: herdrSessionContent.rowSpacing
                            model: herdrSpacesModel
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: 900

                            ScrollBar.vertical: ScrollBar {
                                policy: herdrSpacesList.contentHeight > herdrSpacesList.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                id: herdrSpaceRow
                                required property var modelData
                                readonly property var space: modelData
                                readonly property bool isGroupParent: root.boolOrFalse(space && space.is_group_parent)
                                readonly property string groupKey: root.herdrSpaceGroupKey(space)
                                readonly property bool groupCollapsed: root.herdrSpaceGroupCollapsed(groupKey)
                                readonly property bool canFocus: root.herdrSpaceFocusTarget(space) !== null
                                readonly property bool hovered: spaceMouse.containsMouse
                                width: herdrSpacesList.width
                                implicitHeight: herdrSessionContent.rowHeight
                                radius: herdrSessionContent.rowRadius
                                color: root.herdrSpaceFill(space, hovered)
                                border.color: root.herdrSpaceBorder(space, hovered)
                                border.width: 1

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: root.boolOrFalse(space.focused) ? 10 : 8
                                    width: root.boolOrFalse(space.focused) ? 3 : 2
                                    height: root.boolOrFalse(space.focused) ? 22 : (hovered ? 26 : 22)
                                    radius: 1
                                    color: root.herdrSpaceStatusColor(space)
                                    opacity: root.boolOrFalse(space.focused) ? 0.38 : (hovered ? 0.72 : 0.46)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16 + root.herdrSpaceIndent(space)
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        Layout.preferredWidth: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.herdrSpaceChevron(space)
                                        color: isGroupParent ? colors.textDim : "transparent"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: herdrSpaceRow.isGroupParent
                                            hoverEnabled: true
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: function(mouse) {
                                                mouse.accepted = true;
                                                root.toggleHerdrSpaceGroup(herdrSpaceRow.groupKey);
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.preferredWidth: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.herdrSpaceStatusDot(space)
                                        color: root.herdrSpaceStatusColor(space)
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.herdrSpaceTitle(space)
                                            color: root.boolOrFalse(space.focused) ? colors.text : colors.textDim
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.herdrSpaceMetaLabel(space)
                                            visible: text.length > 0
                                            color: colors.subtle
                                            font.pixelSize: 8
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: spaceMouse
                                    anchors.fill: parent
                                    enabled: herdrSpaceRow.canFocus
                                    hoverEnabled: true
                                    cursorShape: herdrSpaceRow.canFocus ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.focusHerdrSpace(space)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "agents"
                                color: colors.text
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                width: agentsCountText.implicitWidth + 10
                                height: 18
                                radius: 6
                                color: colors.bg
                                border.color: "transparent"
                                border.width: 0

                                Text {
                                    id: agentsCountText
                                    anchors.centerIn: parent
                                    text: String(root.panelSessions().length)
                                    color: colors.muted
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                radius: 1
                                color: colors.lineSoft
                            }
                        }

                        ScriptModel {
                            id: herdrAgentsModel
                            values: root.panelSessions()
                            objectProp: "modelData"
                        }

                        ListView {
                            id: herdrAgentsList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: visible ? Math.min(contentHeight, 96) : 0
                            visible: count > 0
                            clip: true
                            spacing: herdrSessionContent.rowSpacing
                            model: herdrAgentsModel
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: 1200

                            ScrollBar.vertical: ScrollBar {
                                policy: herdrAgentsList.contentHeight > herdrAgentsList.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            }

                            delegate: RootComponents.SessionRow {
                                required property var modelData
                                width: herdrAgentsList.width
                                rootObject: root
                                colorsObject: colors
                                session: modelData
                                selected: root.sessionMatchesKey(modelData, root.selectedSessionKey)
                                currentOverride: root.sessionMatchesKey(modelData, root.optimisticCurrentSessionKey)
                                interactive: true
                                compact: true
                                showHostToken: false
                                showProjectChip: false
                                showCurrentChip: false
                                closePending: root.sessionClosePending(modelData)
                                onClicked: root.focusSession(modelData)
                                onCloseRequested: root.closeSession(modelData)
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: root.panelProjects().length > 0 || root.panelSessions().length === 0
                Layout.fillWidth: true
                Layout.fillHeight: root.runtimePanelSectionExpanded("windows")
                Layout.minimumHeight: root.runtimePanelSectionExpanded("windows") ? 180 : 60
                Layout.preferredHeight: root.panelProjects().length > 0 ? root.runtimePanelSectionPreferredHeight("windows") : 72
                radius: 12
                color: root.runtimePanelSectionExpanded("windows") ? colors.panel : colors.cardAlt
                border.color: root.runtimePanelSectionExpanded("windows") ? colors.blueMuted : colors.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 10
                        color: root.runtimePanelSectionExpanded("windows") ? colors.blueWash : colors.card
                        border.color: root.runtimePanelSectionExpanded("windows") ? colors.blueMuted : colors.lineSoft
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: root.runtimePanelSectionExpanded("windows") ? "▾" : "▸"
                                color: root.runtimePanelSectionExpanded("windows") ? colors.blue : colors.textDim
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: "Windows"
                                color: colors.text
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.panelProjects().length > 0 ? root.runtimePanelSectionSummary("windows") : "No tracked project windows"
                                color: colors.subtle
                                font.pixelSize: 8
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                width: windowsSectionCount.implicitWidth + 12
                                height: 20
                                radius: 6
                                color: colors.bg
                                border.color: "transparent"
                                border.width: 0

                                Text {
                                    id: windowsSectionCount
                                    anchors.centerIn: parent
                                    text: String(root.runtimePanelSectionCount("windows"))
                                    color: colors.muted
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.panelProjects().length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: root.panelProjects().length > 0
                            onClicked: root.toggleRuntimePanelSection("windows")
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.panelProjects().length === 0
                        text: "No tracked project windows"
                        color: colors.subtle
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.panelProjects().length > 0 && root.runtimePanelSectionCollapsed("windows")
                        text: "Window groups stay available here while Herdr Monitor takes the full panel."
                        color: colors.subtle
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
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
                        visible: root.panelProjects().length > 0 && root.runtimePanelSectionExpanded("windows")

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
                                            color: root.stringOrEmpty(projectGroup.project) === "global" ? colors.card : (projectGroup.is_active ? colors.blueBg : colors.bg)
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(projectGroup.project) === "global" ? "G" : root.shortProject(projectGroup.project).slice(0, 1).toUpperCase()
                                                color: root.stringOrEmpty(projectGroup.project) === "global" ? colors.subtle : (projectGroup.is_active ? colors.blue : colors.muted)
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: root.stringOrEmpty(projectGroup.project) !== "global"
                                            width: visible ? projectModeText.implicitWidth + 12 : 0
                                            height: 18
                                            radius: 6
                                            color: root.stringOrEmpty(projectGroup.execution_mode) === "ssh" ? colors.tealBg : colors.blueBg
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
                                            text: root.stringOrEmpty(projectGroup.project) === "global" ? "Shared Windows" : root.shortProject(projectGroup.project)
                                            color: projectGroup.is_active ? (root.stringOrEmpty(projectGroup.execution_mode) === "ssh" ? colors.teal : colors.text) : colors.textDim
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            width: projectWindowCountText.implicitWidth + 12
                                            height: 18
                                            radius: 6
                                            color: colors.bg
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                id: projectWindowCountText
                                                anchors.centerIn: parent
                                                text: String(projectWindows.length)
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
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                id: projectSessionCountText
                                                anchors.centerIn: parent
                                                text: String(Number(projectGroup.ai_session_count || 0))
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
                                                        color: "transparent"
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
                                                            opacity: root.sessionCompactBadgeOpacity(session)
                                                        }

                                                        IconImage {
                                                            anchors.centerIn: parent
                                                            implicitSize: 13
                                                            source: root.toolIconSource(session)
                                                            mipmap: true
                                                            opacity: root.sessionCompactIconOpacity(session)
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                mouse.accepted = true;
                                                                root.focusSession(session);
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
                }
            }

            }

            RootComponents.AgentHarnessPanel {
                id: assistantPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.panelSection === "assistant"
                service: assistantService
                palette: colors
                contextLabel: root.worktreePickerSummaryTitle()
                contextDetails: root.activeContextSummaryLabel()
            }
        }
    }
}
