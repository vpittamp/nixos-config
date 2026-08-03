import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import "." as WindowComponents
import ".." as RootComponents
import "root:/"

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: panelWindow

    // Keep both ListView models keyed by stable identity (same pattern as
    // AgentMonitorWindow): the row content resolves live dashboard data by key,
    // but status/focus ticks no longer reset delegates under the pointer and
    // drop click releases.
    readonly property int dashboardGeneration: root.dashboardGeneration(root.dashboard)
    property var sessionEntries: []
    property var spaceEntries: []
    property bool panelReady: false
    property bool herdrSpacesExpanded: false
    screen: root.findScreenByOutputName(root.panelOutputName) || root.activeScreen
    visible: root.panelVisible
    color: "transparent"
    implicitWidth: runtimeConfig.panelWidth
    anchors.top: true
    anchors.bottom: true
    anchors.right: true
    exclusiveZone: root.dockedMode ? implicitWidth : 0
    // Overlay mode insets the content so the drop shadow has room; without a
    // mask that transparent band would still swallow clicks meant for the
    // window underneath (layer-shell input covers the whole surface).
    mask: Region { item: panelContentRoot }
    focusable: false
    aboveWindows: root.dockedMode
    WlrLayershell.namespace: "i3pm-runtime-panel"
    WlrLayershell.layer: root.dockedMode ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function runtimePanelHasSessions() {
        return sessionEntries.length > 0 || spaceEntries.length > 0;
    }

    function runtimeVisibleHerdrSpacesForState(spaces) {
        const visibleSpaces = [];
        const sourceSpaces = root.arrayOrEmpty(spaces);
        for (let i = 0; i < sourceSpaces.length; i += 1) {
            const space = sourceSpaces[i];
            const groupKey = root.herdrSpaceGroupKey(space);
            if (!root.boolOrFalse(space && space.is_linked_worktree) || !root.herdrSpaceGroupCollapsed(groupKey) || root.herdrSpaceIsFocused(space)) {
                visibleSpaces.push(space);
            }
        }
        return visibleSpaces;
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

    function buildSpaceEntries() {
        const spaces = runtimeVisibleHerdrSpacesForState(root.herdrSpaces());
        const entries = [];
        for (let i = 0; i < spaces.length; i += 1) {
            const space = spaces[i];
            const key = root.herdrSpaceKey(space);
            if (!key) {
                continue;
            }
            entries.push({
                "identity_key": key,
                "snapshot": space,
            });
        }
        return entries;
    }

    function sameEntries(left, right) {
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

    function liveSpaceForEntry(entry, _generation) {
        const identityKey = root.stringOrEmpty(entry && entry.identity_key);
        if (identityKey) {
            const spaces = root.herdrSpaces();
            for (let i = 0; i < spaces.length; i += 1) {
                if (root.herdrSpaceKey(spaces[i]) === identityKey) {
                    return spaces[i];
                }
            }
        }
        return entry && entry.snapshot ? entry.snapshot : null;
    }

    function clampListContentY(list, value) {
        if (!list) {
            return;
        }
        const maxY = Math.max(0, Number(list.contentHeight || 0) - Number(list.height || 0));
        list.contentY = Math.max(0, Math.min(Number(value || 0), maxY));
    }

    function restoreRuntimeListContentY(saved) {
        if (!panelWindow.panelReady || !saved) {
            return;
        }
        clampListContentY(herdrSpacesList, saved.spaces);
        clampListContentY(herdrAgentsList, saved.agents);
        Qt.callLater(function() {
            clampListContentY(herdrSpacesList, saved.spaces);
            clampListContentY(herdrAgentsList, saved.agents);
        });
    }

    function refreshRuntimePanelData(preserveViewport) {
        const saved = preserveViewport && panelWindow.panelReady ? ({
            spaces: Number(herdrSpacesList.contentY || 0),
            agents: Number(herdrAgentsList.contentY || 0)
        }) : null;
        let membershipChanged = false;
        const nextSpaces = buildSpaceEntries();
        if (!sameEntries(spaceEntries, nextSpaces)) {
            spaceEntries = nextSpaces;
            membershipChanged = true;
        }
        const nextSessions = buildSessionEntries();
        if (!sameEntries(sessionEntries, nextSessions)) {
            sessionEntries = nextSessions;
            membershipChanged = true;
        }
        // Only a membership change can reset the viewport. Restoring on every
        // status tick would fight the user mid-scroll, since the identity model
        // leaves the delegates (and contentY) untouched otherwise.
        if (saved && membershipChanged
            && !herdrSpacesList.dragging && !herdrSpacesList.flicking
            && !herdrAgentsList.dragging && !herdrAgentsList.flicking) {
            Qt.callLater(function() {
                panelWindow.restoreRuntimeListContentY(saved);
            });
        }
    }

    Component.onCompleted: {
        panelReady = true;
        refreshRuntimePanelData(false);
    }

    onVisibleChanged: {
        if (visible) {
            refreshRuntimePanelData(false);
            // Overlay mode slides the content in from the right edge; docked
            // mode only fades — reserved space must not appear to slide, and
            // close stays instant (visible hard-toggles the surface away).
            panelOverlayEnterAnim.stop();
            panelDockedEnterAnim.stop();
            panelContentSlide.x = 0;
            panelContentRoot.opacity = 1;
            if (root.dockedMode) {
                panelDockedEnterAnim.restart();
            } else {
                panelOverlayEnterAnim.restart();
            }
        }
    }

    Connections {
        target: root
        // A hidden panel does not need per-event refreshes; onVisibleChanged
        // rebuilds the entries when it opens.
        enabled: panelWindow.visible

        function onDashboardChanged() {
            panelWindow.refreshRuntimePanelData(true);
        }

        function onCollapsedHerdrSpaceGroupsChanged() {
            panelWindow.refreshRuntimePanelData(true);
        }
    }

    function runtimePanelSessionSummary() {
        const bits = [];
        if (spaceEntries.length > 0) {
            bits.push(String(spaceEntries.length) + (spaceEntries.length === 1 ? " space" : " spaces"));
        }
        if (sessionEntries.length > 0) {
            bits.push(String(sessionEntries.length) + (sessionEntries.length === 1 ? " agent" : " agents"));
        }
        // Reflect the "nothing focused" state explicitly: when sway focus is not
        // on any herdr pane the daemon reports an empty current_session_key, so no
        // row is highlighted — call that out rather than leaving it ambiguous.
        if (runtimePanelHasSessions()
            && !root.stringOrEmpty((root.dashboard.focus_state || {}).current_session_key)) {
            bits.push("no session focused");
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
        id: panelContentRoot
        // MultiEffect is shader-based; the software Quick backend (NVIDIA
        // hosts) would render a layered item as nothing at all, so the shadow
        // is gated and those hosts get the 1px dark halo below instead.
        readonly property bool shadowCapable: GraphicsInfo.api !== GraphicsInfo.Software
        anchors.fill: parent
        // Overlay mode floats the panel: inset so the drop shadow has room
        // inside the layer-shell window (shadows clip at the window edge).
        // Docked mode reserves real screen space, so it stays flush + square.
        anchors.margins: root.dockedMode ? 0 : 10
        radius: root.dockedMode ? 0 : root.radiusFloat
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Theme.panelAlt
            }
            GradientStop {
                position: 1.0
                color: Theme.bg
            }
        }
        border.color: colors.border
        border.width: 1
        layer.enabled: !root.dockedMode && shadowCapable
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1.0
            shadowColor: Theme.shadow
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }
        // Entry motion target: a Translate transform slides the content without
        // fighting the anchors, and input stays live throughout (no gating).
        transform: Translate {
            id: panelContentSlide
            x: 0
        }

        Rectangle {
            visible: !root.dockedMode && !panelContentRoot.shadowCapable
            anchors.fill: parent
            anchors.margins: -1
            radius: parent.radius + 1
            color: "transparent"
            border.color: Theme.edgeShadow
            border.width: 1
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius > 0 ? parent.radius - 1 : 0
            color: "transparent"
            border.color: Theme.edgeHighlightSoft
            border.width: 1
        }

        ParallelAnimation {
            id: panelOverlayEnterAnim

            NumberAnimation {
                target: panelContentSlide
                property: "x"
                from: panelWindow.width
                to: 0
                duration: 260
                easing.type: Easing.OutQuint
            }
            NumberAnimation {
                target: panelContentRoot
                property: "opacity"
                from: 0
                to: 1
                duration: 260
                easing.type: Easing.OutQuint
            }
        }

        NumberAnimation {
            id: panelDockedEnterAnim
            target: panelContentRoot
            property: "opacity"
            from: 0
            to: 1
            duration: 140
        }

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
                    radius: root.radiusControl
                    color: root.panelSection === "runtime" ? colors.blueBg : colors.cardAlt
                    border.color: root.panelSection === "runtime" ? colors.blue : colors.border
                    border.width: 1
                    scale: runtimeTabMouse.pressed ? 0.96 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutQuad
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Runtime"
                        color: root.panelSection === "runtime" ? colors.blue : colors.textDim
                        font.pixelSize: root.fontLabel
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: runtimeTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showRuntimePanel(panelWindow.screen ? panelWindow.screen.name : "")
                    }
                }

                // Stale marker: the watch stream is disconnected and everything
                // below is last-known data, not live truth.
                Rectangle {
                    visible: root.dashboardStale
                    implicitHeight: 20
                    radius: root.radiusBadge
                    color: colors.amberBg
                    border.color: "transparent"
                    border.width: 0
                    Layout.preferredWidth: stalePillText.implicitWidth + 14

                    Text {
                        id: stalePillText
                        anchors.centerIn: parent
                        text: "reconnecting…"
                        color: colors.amber
                        font.pixelSize: root.fontCaption
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                    }
                }

            }

            ColumnLayout {
                id: runtimePanelContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                visible: root.panelSection === "runtime"


            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.notificationsBackendNative() || root.notificationFeed.length > 0

                Text {
                    text: "Notifications"
                    color: colors.text
                    font.pixelSize: root.fontTitle
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: notificationSectionCount.implicitWidth + 12
                    height: 20
                    radius: root.radiusBadge
                    color: root.notificationUnreadCount() > 0 ? colors.blueBg : colors.cardAlt
                    border.color: root.notificationUnreadCount() > 0 ? colors.blue : colors.lineSoft
                    border.width: 1

                    Text {
                        id: notificationSectionCount
                        anchors.centerIn: parent
                        text: root.notificationDisplayCount(root.notificationUnreadCount())
                        color: root.notificationUnreadCount() > 0 ? colors.blue : colors.muted
                        font.pixelSize: root.fontCaption
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    visible: root.notificationDnd
                    height: 20
                    radius: root.radiusBadge
                    color: colors.amberBg
                    border.color: colors.amber
                    border.width: 1
                    Layout.preferredWidth: notificationDndText.implicitWidth + 12

                    Text {
                        id: notificationDndText
                        anchors.centerIn: parent
                        text: "DND"
                        color: colors.amber
                        font.pixelSize: root.fontMicro
                        font.letterSpacing: 0.5
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
                    radius: root.radiusControl
                    color: notificationToggleMouse.containsMouse ? colors.cardAlt : colors.card
                    border.color: notificationToggleMouse.containsMouse ? colors.borderStrong : colors.border
                    border.width: 1
                    scale: notificationToggleMouse.pressed ? 0.96 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutQuad
                        }
                    }
                    Layout.preferredWidth: notificationToggleText.implicitWidth + 16

                    Text {
                        id: notificationToggleText
                        anchors.centerIn: parent
                        text: root.notificationCenterVisible ? "Hide" : "Show"
                        color: colors.text
                        font.pixelSize: root.fontCaption
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
                    radius: root.radiusControl
                    color: notificationClearMouse.containsMouse ? colors.redBg : colors.card
                    border.color: notificationClearMouse.containsMouse ? colors.red : colors.border
                    border.width: 1
                    scale: notificationClearMouse.pressed ? 0.96 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutQuad
                        }
                    }
                    Layout.preferredWidth: notificationClearText.implicitWidth + 16

                    Text {
                        id: notificationClearText
                        anchors.centerIn: parent
                        text: "Clear"
                        color: notificationClearMouse.containsMouse ? colors.red : colors.textDim
                        font.pixelSize: root.fontCaption
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
                onDismissRequested: (notificationId) => root.dismissNotification(notificationId)
                onActionInvoked: (notificationId, actionId) => root.invokeNotificationAction(notificationId, actionId)
                onMarkReadRequested: (notificationId) => root.markNotificationRead(notificationId)
                onDetailRequested: (notificationId) => root.showNotificationDetail(notificationId)
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
                    onDismissRequested: (notificationId) => root.dismissNotification(notificationId)
                    onActionInvoked: (notificationId, actionId) => root.invokeNotificationAction(notificationId, actionId)
                    onMarkReadRequested: (notificationId) => root.markNotificationRead(notificationId)
                    onDetailRequested: (notificationId) => root.showNotificationDetail(notificationId)
                }
            }

            Rectangle {
                id: sessionsSection
                visible: panelWindow.runtimePanelHasSessions()
                Layout.fillWidth: true
                Layout.fillHeight: panelWindow.runtimePanelLocalExpanded("sessions")
                Layout.minimumHeight: panelWindow.runtimePanelLocalExpanded("sessions") ? 180 : 60
                Layout.preferredHeight: panelWindow.runtimePanelLocalPreferredHeight("sessions")
                radius: root.radiusCard
                color: panelWindow.runtimePanelLocalExpanded("sessions") ? colors.panel : colors.cardAlt
                border.color: panelWindow.runtimePanelLocalExpanded("sessions") ? colors.lineSoft : colors.border
                border.width: 1
                // Dim last-known session data while the watch stream reconnects.
                opacity: root.dashboardStale ? 0.7 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 8

                    WindowComponents.RuntimePanelSectionHeader {
                        rootObject: root
                        colorsObject: colors
                        title: "Herdr Monitor"
                        summary: panelWindow.runtimePanelSessionSummary()
                        count: panelWindow.sessionEntries.length
                        expanded: panelWindow.runtimePanelLocalExpanded("sessions")
                        onClicked: root.toggleRuntimePanelSection("sessions")
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: panelWindow.runtimePanelLocalCollapsed("sessions")
                        text: "spaces and agents"
                        color: colors.subtle
                        font.pixelSize: root.fontCaption
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        id: herdrSessionContent
                        readonly property int agentCount: panelWindow.sessionEntries.length
                        readonly property int spaceCount: panelWindow.spaceEntries.length
                        readonly property int rowHeight: 48
                        readonly property int rowRadius: root.radiusControl
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

                        Rectangle {
                            id: herdrSpacesHeader
                            Layout.fillWidth: true
                            visible: herdrSessionContent.spaceCount > 0
                            Layout.preferredHeight: 24
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Text {
                                    Layout.preferredWidth: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    text: panelWindow.herdrSpacesExpanded ? "▾" : "▸"
                                    color: colors.textDim
                                    font.pixelSize: root.fontBody
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: "spaces"
                                    color: colors.text
                                    font.pixelSize: root.fontBody
                                    font.weight: Font.DemiBold
                                }

                                Rectangle {
                                    width: spacesCountText.implicitWidth + 10
                                    height: 18
                                    radius: root.radiusBadge
                                    color: colors.bg
                                    border.color: "transparent"
                                    border.width: 0

                                    Text {
                                        id: spacesCountText
                                        anchors.centerIn: parent
                                        text: String(panelWindow.spaceEntries.length)
                                        color: colors.muted
                                        font.pixelSize: root.fontCaption
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

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panelWindow.herdrSpacesExpanded = !panelWindow.herdrSpacesExpanded
                            }
                        }

                        ScriptModel {
                            id: herdrSpacesModel
                            values: panelWindow.spaceEntries
                            objectProp: "modelData"
                        }

                        ListView {
                            id: herdrSpacesList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(contentHeight, herdrSessionContent.spacesMaxHeight)
                            Layout.maximumHeight: herdrSessionContent.spacesMaxHeight
                            Layout.minimumHeight: visible ? Math.min(contentHeight, 96) : 0
                            clip: true
                            spacing: herdrSessionContent.rowSpacing
                            model: herdrSpacesModel
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: 900
                            visible: count > 0 && panelWindow.herdrSpacesExpanded

                            // The model is keyed by stable identity, so these
                            // fire on membership change only — not status ticks.
                            add: Transition {
                                NumberAnimation {
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    property: "x"
                                    from: 16
                                    to: 0
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                            }
                            displaced: Transition {
                                NumberAnimation {
                                    property: "y"
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: herdrSpacesList.contentHeight > herdrSpacesList.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                id: herdrSpaceRow
                                required property var modelData
                                readonly property var space: panelWindow.liveSpaceForEntry(modelData, panelWindow.dashboardGeneration)
                                readonly property bool isGroupParent: root.boolOrFalse(space && space.is_group_parent)
                                readonly property string groupKey: root.herdrSpaceGroupKey(space)
                                readonly property bool groupCollapsed: root.herdrSpaceGroupCollapsed(groupKey)
                                readonly property bool canFocus: root.herdrSpaceFocusTarget(space) !== null
                                readonly property bool spaceFocused: root.herdrSpaceIsFocused(space)
                                readonly property bool hovered: spaceMouse.containsMouse
                                readonly property string metaLabel: root.herdrSpaceMetaLabel(space)
                                readonly property string gitChipText: root.herdrSpaceGitChipText(space)
                                readonly property string gitTooltip: root.herdrSpaceGitTooltip(space)
                                width: herdrSpacesList.width
                                implicitHeight: herdrSessionContent.rowHeight
                                radius: herdrSessionContent.rowRadius
                                color: root.herdrSpaceFill(space, hovered)
                                border.color: root.herdrSpaceBorder(space, hovered)
                                border.width: 1

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
                                        font.pixelSize: root.fontBody
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
                                            font.pixelSize: root.fontCaption
                                            font.weight: Font.Bold
                                        }

                                        // No hover ToolTip here: a QtQuick.Controls
                                        // ToolTip is a Popup whose overlay grabbed the
                                        // pointer, flipping containsMouse on/off so the
                                        // row "pulsated" and ate clicks (needed a
                                        // double-click to register). The host
                                        // monogram already shows local/remote at a
                                        // glance. The previous hover-only MouseArea was
                                        // also removed so clicks on the chip fall through
                                        // to the row (focus the space).
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.herdrSpaceTitle(space)
                                            color: herdrSpaceRow.spaceFocused ? colors.text : colors.textDim
                                            font.pixelSize: root.fontTitle
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
                                                font.pixelSize: root.fontCaption
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                visible: root.herdrSpaceGitChipVisible(space)
                                                height: 15
                                                radius: root.radiusBadge
                                                color: root.herdrSpaceGitChipBackground(space)
                                                border.color: "transparent"
                                                border.width: 0
                                                Layout.preferredWidth: herdrSpaceGitText.implicitWidth + 10

                                                Text {
                                                    id: herdrSpaceGitText
                                                    anchors.centerIn: parent
                                                    text: herdrSpaceRow.gitChipText
                                                    color: root.herdrSpaceGitChipForeground(space)
                                                    font.pixelSize: root.fontCaption
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

                                // No hover ToolTip here: a QtQuick.Controls ToolTip is a
                                // Popup whose overlay grabbed the pointer inside this
                                // panel, flipping spaceMouse.containsMouse on/off
                                // so the row "pulsated as if clicked" and ate real clicks
                                // (focusHerdrSpace only landed on a double-click). The git
                                // chip in the row already shows the status; the full
                                // tooltip detail is dropped to keep the row reliably
                                // clickable.
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "agents"
                                color: colors.text
                                font.pixelSize: root.fontBody
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                width: agentsCountText.implicitWidth + 10
                                height: 18
                                radius: root.radiusBadge
                                color: colors.bg
                                border.color: "transparent"
                                border.width: 0

                                Text {
                                    id: agentsCountText
                                    anchors.centerIn: parent
                                    text: String(panelWindow.sessionEntries.length)
                                    color: colors.muted
                                    font.pixelSize: root.fontCaption
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
                            values: panelWindow.sessionEntries
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

                            // The model is keyed by stable identity, so these
                            // fire on membership change only — not status ticks.
                            add: Transition {
                                // Scale, not opacity: SessionRow binds opacity
                                // (idle rows sit at 0.76), and an animation
                                // would pin it at 1 until the next tick.
                                NumberAnimation {
                                    property: "scale"
                                    from: 0.96
                                    to: 1
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    property: "x"
                                    from: 16
                                    to: 0
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                            }
                            displaced: Transition {
                                NumberAnimation {
                                    property: "y"
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: herdrAgentsList.contentHeight > herdrAgentsList.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            }

                            delegate: RootComponents.SessionRow {
                                required property var modelData
                                readonly property var liveSession: panelWindow.liveSessionForEntry(modelData, panelWindow.dashboardGeneration)
                                width: herdrAgentsList.width
                                rootObject: root
                                colorsObject: colors
                                surfaceVisible: root.panelVisible
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
                    }
                }
            }

            }
        }
    }
}
