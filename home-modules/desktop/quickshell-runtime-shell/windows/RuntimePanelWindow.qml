import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import "." as WindowComponents
import ".." as RootComponents

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: panelWindow
    property var runtimeSessions: []
    property var runtimeHerdrSpaces: []
    screen: root.primaryScreen
    visible: root.panelVisible
    onVisibleChanged: {
        if (visible) {
            refreshRuntimePanelData();
        }
    }
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

    function refreshRuntimePanelData() {
        runtimeSessions = root.panelSessions();
        runtimeHerdrSpaces = root.herdrSpaces();
    }

    Component.onCompleted: refreshRuntimePanelData()

    Connections {
        target: root

        function onDashboardChanged() {
            if (panelWindow.visible) {
                refreshRuntimePanelData();
            }
        }
    }

    function runtimePanelHasSessions() {
        return runtimeSessions.length > 0 || runtimeHerdrSpaces.length > 0;
    }

    function runtimeVisibleHerdrSpaces() {
        const visibleSpaces = [];
        for (let i = 0; i < runtimeHerdrSpaces.length; i += 1) {
            const space = runtimeHerdrSpaces[i];
            const groupKey = root.herdrSpaceGroupKey(space);
            if (!root.boolOrFalse(space && space.is_linked_worktree) || !root.herdrSpaceGroupCollapsed(groupKey) || root.herdrSpaceIsFocused(space)) {
                visibleSpaces.push(space);
            }
        }
        return visibleSpaces;
    }

    function runtimePanelSessionSummary() {
        const bits = [];
        const visibleSpaces = runtimeVisibleHerdrSpaces();
        if (visibleSpaces.length > 0) {
            bits.push(String(visibleSpaces.length) + (visibleSpaces.length === 1 ? " space" : " spaces"));
        }
        if (runtimeSessions.length > 0) {
            bits.push(String(runtimeSessions.length) + (runtimeSessions.length === 1 ? " agent" : " agents"));
        }
        return bits.join(" • ");
    }

    function runtimePanelLocalExpanded(section) {
        if (section === "sessions") {
            return runtimePanelHasSessions();
        }
        return false;
    }

    function runtimePanelLocalCollapsed(section) {
        if (section === "sessions" && !runtimePanelHasSessions()) {
            return false;
        }
        return !runtimePanelLocalExpanded(section);
    }

    function runtimePanelLocalPreferredHeight(section) {
        if (section === "sessions" && !runtimePanelHasSessions()) {
            return 0;
        }
        if (runtimePanelLocalExpanded(section)) {
            return Math.max(640, panelWindow.height - 112);
        }
        return 60;
    }

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
                id: sessionsSection
                visible: panelWindow.runtimePanelHasSessions()
                Layout.fillWidth: true
                Layout.fillHeight: panelWindow.runtimePanelLocalExpanded("sessions")
                Layout.minimumHeight: panelWindow.runtimePanelLocalExpanded("sessions") ? 180 : 60
                Layout.preferredHeight: panelWindow.runtimePanelLocalPreferredHeight("sessions")
                radius: 12
                color: panelWindow.runtimePanelLocalExpanded("sessions") ? colors.panel : colors.cardAlt
                border.color: panelWindow.runtimePanelLocalExpanded("sessions") ? colors.lineSoft : colors.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 8

                    WindowComponents.RuntimePanelSectionHeader {
                        colorsObject: colors
                        title: "Herdr Monitor"
                        summary: panelWindow.runtimePanelSessionSummary()
                        count: panelWindow.runtimeSessions.length
                        expanded: panelWindow.runtimePanelLocalExpanded("sessions")
                        onClicked: root.toggleRuntimePanelSection("sessions")
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: panelWindow.runtimePanelLocalCollapsed("sessions")
                        text: "spaces and agents"
                        color: colors.subtle
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        id: herdrSessionContent
                        readonly property int agentCount: panelWindow.runtimeSessions.length
                        readonly property int spaceCount: panelWindow.runtimeVisibleHerdrSpaces().length
                        readonly property int rowHeight: 48
                        readonly property int rowRadius: 7
                        readonly property int rowSpacing: 6
                        readonly property int chipHeight: 18
                        readonly property int sectionHeaderHeight: 28
                        readonly property int sectionSpacing: 10
                        readonly property int spacesContentHeight: spaceCount <= 0 ? 0 : (spaceCount * rowHeight) + ((spaceCount - 1) * rowSpacing)
                        readonly property int agentsContentHeight: agentCount <= 0 ? 0 : (agentCount * rowHeight) + ((agentCount - 1) * rowSpacing)
                        readonly property int agentsReservedHeight: agentCount <= 0 ? 0 : Math.min(agentsContentHeight, 220) + sectionHeaderHeight + sectionSpacing
                        readonly property int availableContentHeight: Math.max(260, height - sectionHeaderHeight - sectionSpacing - agentsReservedHeight)
                        readonly property int spacesMaxHeight: Math.max(240, availableContentHeight)
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: panelWindow.runtimePanelLocalExpanded("sessions")
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
                                    text: String(panelWindow.runtimeVisibleHerdrSpaces().length)
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
                            values: panelWindow.runtimeVisibleHerdrSpaces()
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
                                readonly property bool spaceFocused: root.herdrSpaceIsFocused(space)
                                readonly property bool hovered: spaceMouse.containsMouse
                                readonly property bool hasStatusMotion: root.herdrSpaceEffectiveStatus(space) === "working"
                                readonly property string metaLabel: root.herdrSpaceMetaLabel(space)
                                readonly property string gitChipText: root.herdrSpaceGitChipText(space)
                                readonly property string gitTooltip: root.herdrSpaceGitTooltip(space)
                                property int statusSpinnerFrame: 0
                                width: herdrSpacesList.width
                                implicitHeight: herdrSessionContent.rowHeight
                                radius: herdrSessionContent.rowRadius
                                color: root.herdrSpaceFill(space, hovered)
                                border.color: root.herdrSpaceBorder(space, hovered)
                                border.width: 1

                                Timer {
                                    running: herdrSpaceRow.hasStatusMotion
                                    repeat: true
                                    interval: 95
                                    onTriggered: herdrSpaceRow.statusSpinnerFrame = (herdrSpaceRow.statusSpinnerFrame + 1) % 10
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: herdrSpaceRow.spaceFocused ? 10 : 8
                                    width: herdrSpaceRow.spaceFocused ? 3 : 2
                                    height: herdrSpaceRow.spaceFocused ? 22 : (hovered ? 26 : 22)
                                    radius: 1
                                    color: root.herdrSpaceStatusColor(space)
                                    opacity: herdrSpaceRow.spaceFocused ? 0.38 : (hovered ? 0.72 : 0.46)
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
                                        text: root.herdrSpaceStatusDot(space, herdrSpaceRow.statusSpinnerFrame)
                                        color: root.herdrSpaceStatusColor(space)
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    // Host (local vs remote) badge — monogram of the herdr host,
                                    // local/remote color so each space shows where it lives.
                                    Rectangle {
                                        id: spaceHostChip
                                        readonly property var hostTok: root.spaceHostToken(space)
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 14
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: 4
                                        color: spaceHostChip.hostTok.background
                                        border.color: spaceHostChip.hostTok.border
                                        border.width: 1
                                        opacity: herdrSpaceRow.spaceFocused ? 1.0 : 0.85

                                        Text {
                                            anchors.centerIn: parent
                                            text: spaceHostChip.hostTok.monogram
                                            color: spaceHostChip.hostTok.foreground
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }

                                        MouseArea { id: spaceHostChipMouse; anchors.fill: parent; hoverEnabled: true }
                                        ToolTip {
                                            visible: spaceHostChipMouse.containsMouse
                                            text: (spaceHostChip.hostTok.is_remote ? "remote · " : "local · ") + spaceHostChip.hostTok.label
                                            delay: 400
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.herdrSpaceTitle(space)
                                            color: herdrSpaceRow.spaceFocused ? colors.text : colors.textDim
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: herdrSpaceRow.metaLabel.length > 0 || root.herdrSpaceGitChipVisible(space)
                                            spacing: 5

                                            Text {
                                                Layout.fillWidth: true
                                                text: herdrSpaceRow.metaLabel
                                                visible: text.length > 0
                                                color: colors.subtle
                                                font.pixelSize: 8
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                visible: root.herdrSpaceGitChipVisible(space)
                                                height: 14
                                                radius: 5
                                                color: root.herdrSpaceGitChipBackground(space)
                                                border.color: "transparent"
                                                border.width: 0
                                                Layout.preferredWidth: herdrSpaceGitText.implicitWidth + 10

                                                Text {
                                                    id: herdrSpaceGitText
                                                    anchors.centerIn: parent
                                                    text: herdrSpaceRow.gitChipText
                                                    color: root.herdrSpaceGitChipForeground(space)
                                                    font.pixelSize: 8
                                                    font.weight: Font.Medium
                                                }
                                            }
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

                                ToolTip {
                                    visible: spaceMouse.containsMouse && herdrSpaceRow.gitTooltip.length > 0
                                    text: herdrSpaceRow.gitTooltip
                                    delay: 500
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
                                    text: String(panelWindow.runtimeSessions.length)
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
                            values: panelWindow.runtimeSessions
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
                    }
                }
            }

            }
        }
    }
}
