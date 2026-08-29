import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import ".." as RootComponents

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: topBarWindow
    required property var modelData
    property bool fallbackMode: false
    property string fallbackOutputName: ""
    readonly property var topBarScreen: fallbackMode ? null : modelData
    readonly property string topOutputName: fallbackMode ? root.stringOrEmpty(fallbackOutputName) : root.screenOutputName(topBarScreen)
    readonly property bool isPrimaryBar: root.isPrimaryOutput(topOutputName)
    readonly property bool isFocusedBar: root.isFocusedOutput(topOutputName)

    screen: topBarScreen
    visible: fallbackMode || topBarScreen !== null
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    implicitHeight: runtimeConfig.topBarHeight
    exclusiveZone: implicitHeight
    focusable: false
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-runtime-top-bar-" + (topOutputName || "screen")
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: topBarBackground
        anchors.fill: parent
        color: topBarWindow.isFocusedBar ? colors.panel : colors.bg
        border.color: topBarWindow.isFocusedBar ? colors.blueMuted : colors.border
        border.width: 1

        // The three sections are ANCHORED, not cells of a RowLayout. A RowLayout
        // with two fillWidth siblings splits the leftover space in equal shares,
        // so the "centred" block only lands on the midpoint when the left and
        // right clusters happen to be the same width — they never are, and the
        // clock sat ~430px left of centre on a 1920px output. Worse, every width
        // change on either side dragged it sideways: a percentage gaining a
        // digit nudged it, and a focus change (which used to add or remove the
        // tray, cast and power chips) threw it 75px while the right cluster
        // jumped 153px. Anchoring pins each section to its own edge, so nothing
        // any section does can move the other two.
        Item {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 4
            anchors.bottomMargin: 4

            RowLayout {
                id: leftCluster
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 6

                Rectangle {
                    id: panelToggleChip
                    radius: root.radiusControl
                    color: root.stateChipFill(root.panelVisible, panelToggleMouse.containsMouse, colors.blueBg)
                    border.color: root.stateChipBorder(root.panelVisible, panelToggleMouse.containsMouse, colors.blue)
                    border.width: 1
                    implicitWidth: panelToggleLabel.implicitWidth + 20
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: panelToggleLabel
                        anchors.centerIn: parent
                        text: "AI Panel"
                        color: root.stateChipText(root.panelVisible, panelToggleMouse.containsMouse, colors.blue)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: panelToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePanelVisibility(topBarWindow.topOutputName)
                    }
                }

                // Toggle the translucent AI-agents overlay (the see-through strip
                // for watching agents over a fullscreen video). Same action as
                // Mod+Shift+A; opens on this bar's monitor. The dot reflects the
                // worst current agent status so it's a live indicator even closed.
                Rectangle {
                    id: agentMonitorChip
                    readonly property var agentSessionsList: root.activeSessions()
                    readonly property int agentSessionsCount: agentSessionsList.length
                    readonly property bool anyBlocked: agentSessionsList.some(function (s) { return root.sessionPhase(s) === "blocked"; })
                    readonly property bool anyDone: agentSessionsList.some(function (s) { return root.sessionPhase(s) === "done"; })
                    readonly property bool anyWorking: agentSessionsList.some(function (s) { return root.sessionPhase(s) === "working"; })
                    // Distinct herdr hosts with live agents, in session order
                    // (local first — sessions arrive stableSessionCompare-sorted).
                    readonly property var agentHostKeys: {
                        const seen = [];
                        const sessions = agentSessionsList;
                        for (let i = 0; i < sessions.length; i += 1) {
                            const key = root.sessionHostKey(sessions[i]);
                            if (key.length > 0 && seen.indexOf(key) === -1) {
                                seen.push(key);
                            }
                        }
                        return seen;
                    }
                    radius: root.radiusControl
                    color: root.stateChipFill(root.agentMonitorVisible, agentMonitorMouse.containsMouse, colors.blueBg)
                    border.color: agentMonitorChip.anyBlocked && !root.dashboardStale
                        ? colors.red
                        : root.stateChipBorder(root.agentMonitorVisible, agentMonitorMouse.containsMouse, colors.blue)
                    border.width: 1
                    implicitWidth: agentMonitorRow.implicitWidth + 20
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    RowLayout {
                        id: agentMonitorRow
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            visible: agentMonitorChip.agentSessionsCount > 0
                            width: 7
                            height: 7
                            radius: 4
                            // Canonical status map, priority blocked > working > done
                            // > idle. Stale dashboard data gets no live colors: the
                            // dot drops to muted slate until the stream reconnects.
                            color: {
                                if (root.dashboardStale) {
                                    return colors.subtle;
                                }
                                if (agentMonitorChip.anyBlocked) {
                                    return root.sessionStatusStyle("blocked").color;
                                }
                                if (agentMonitorChip.anyWorking) {
                                    return root.sessionStatusStyle("working").color;
                                }
                                if (agentMonitorChip.anyDone) {
                                    return root.sessionStatusStyle("done").color;
                                }
                                return root.sessionStatusStyle("idle").color;
                            }
                            // Working carries no motion: the dot's color already
                            // says "busy", and an infinite opacity animation here
                            // repainted every top bar on every output at 60fps for
                            // as long as any agent ran — under the software render
                            // backend that was the shell's largest idle cost.
                            // Blocked still blinks, because it means a session is
                            // waiting on a human, but it steps off the shell-wide
                            // attention clock instead of animating per frame. A
                            // plain binding also removes the two-animations-on-one-
                            // property hazard the pair of SequentialAnimations had.
                            opacity: agentMonitorChip.anyBlocked && !root.dashboardStale && !root.attentionBlinkOn
                                ? 0.3
                                : 1.0
                        }

                        // Per-host presence dots (only when agents actually span
                        // hosts — a single-host fleet needs no legend). Colors
                        // match the panel's host group headers via hostColorFor.
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            visible: agentMonitorChip.agentHostKeys.length > 1 && !root.dashboardStale
                            spacing: 3

                            Repeater {
                                model: agentMonitorChip.agentHostKeys.slice(0, 3)

                                delegate: Rectangle {
                                    required property var modelData
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.hostColorFor(String(modelData))
                                    border.color: colors.border
                                    border.width: 1
                                }
                            }
                        }

                        Text {
                            id: agentMonitorLabel
                            text: agentMonitorChip.agentSessionsCount > 0
                                ? ("Agents " + agentMonitorChip.agentSessionsCount)
                                : "Agents"
                            color: root.stateChipText(root.agentMonitorVisible, agentMonitorMouse.containsMouse, colors.blue)
                            font.pixelSize: root.fontLabel
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: agentMonitorMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleAgentMonitor(topBarWindow.topOutputName)
                    }

                    RootComponents.BarTooltip {
                        anchorWindow: topBarWindow
                        anchorItem: agentMonitorMouse
                        active: agentMonitorMouse.containsMouse
                        text: "AI agents overlay · Mod+Shift+A"
                        colors: topBarWindow.colors
                    }
                }
            }

            Rectangle {
                id: centerCluster
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: root.radiusControl
                color: colors.card
                border.color: colors.border
                border.width: 1
                implicitWidth: centerRow.implicitWidth + 20

                // The span actually free between the two side clusters. Both
                // ends are read off the side clusters, which know nothing about
                // this block, so none of it can feed back into itself.
                readonly property real gapStart: leftCluster.width + 8
                readonly property real gapEnd: parent.width - rightCluster.width - 8
                readonly property real freeSpan: Math.max(0, gapEnd - gapStart)

                // Sit on the output's centre whenever that clears both clusters,
                // and slide only as far as it must when it does not. Hiding on a
                // collision — which is what this used to do — took the clock out
                // with it on every output narrower than ~1700 logical px, i.e.
                // the ThinkPad panel (1536 at scale 1.25) and both Surfaces
                // (1504 / 1440 at 1.5); ryzen's 1920 cleared it by only 107px.
                // A bar has room for the clock long before it has room to centre
                // it, so position gives way first and visibility last.
                width: Math.min(implicitWidth, freeSpan)
                x: Math.max(gapStart, Math.min((parent.width - width) / 2, gapEnd - width))
                visible: freeSpan >= 24
                clip: true

                RowLayout {
                    id: centerRow
                    // Right-anchored, not centred: at full width this is the
                    // same 10px on either side, but on a bar too narrow to hold
                    // the whole block the clipping then falls on the host label
                    // rather than on the clock.
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: runtimeConfig.hostName === "ryzen" ? "\uf4bc"
                            : runtimeConfig.hostName === "thinkpad" ? "\uf489"
                            : "\uf108"
                        color: topBarWindow.isFocusedBar ? colors.blue : colors.muted
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        id: outputLabel
                        text: runtimeConfig.hostName + (topBarWindow.topOutputName ? " · " + topBarWindow.topOutputName : "")
                        color: colors.text
                        font.pixelSize: root.fontLabel
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "│"
                        color: colors.subtle
                        font.pixelSize: root.fontLabel
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        id: clockLabel
                        text: root.topBarTimeText()
                        color: colors.text
                        font.pixelSize: root.fontLabel
                        font.weight: Font.DemiBold
                    }
                }
            }

            RowLayout {
                id: rightCluster
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 6

                Rectangle {
                    id: daemonHealthChip
                    radius: root.radiusControl
                    color: root.daemonHealthColor(daemonHealthMouse.containsMouse)
                    border.color: root.daemonHealthBorderColor(daemonHealthMouse.containsMouse)
                    border.width: 1
                    implicitWidth: daemonHealthRow.implicitWidth + 18
                    Layout.fillHeight: true
                    visible: root.daemonHealthState.status === "degraded"
                        || root.daemonHealthState.status === "unhealthy"
                        || root.daemonHealthState.status === "critical"
                        || root.daemonHealthState.status === "dead"
                        || root.daemonHealthState.status === "unreachable"

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    RowLayout {
                        id: daemonHealthRow
                        anchors.centerIn: parent
                        spacing: 5

                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: root.daemonHealthDotColor()
                        }

                        Text {
                            text: root.daemonHealthLabel()
                            color: root.daemonHealthTextColor(daemonHealthMouse.containsMouse)
                            font.pixelSize: root.fontLabel
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: daemonHealthMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    RootComponents.BarTooltip {
                        anchorWindow: topBarWindow
                        anchorItem: daemonHealthMouse
                        active: daemonHealthMouse.containsMouse
                        text: root.daemonHealthTooltip()
                        colors: topBarWindow.colors
                    }
                }

                Rectangle {
                    id: generationChip
                    radius: root.radiusControl
                    color: root.neutralChipFill(generationMouse.containsMouse)
                    border.color: root.neutralChipBorder(generationMouse.containsMouse)
                    border.width: 1
                    implicitWidth: generationLabel.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: generationLabel
                        anchors.centerIn: parent
                        text: root.systemGenerationLabel()
                        color: root.neutralChipText(generationMouse.containsMouse)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: generationMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }

                Rectangle {
                    id: memoryChip
                    radius: root.radiusControl
                    color: root.neutralChipFill(memoryMouse.containsMouse)
                    border.color: root.neutralChipBorder(memoryMouse.containsMouse)
                    border.width: 1
                    // Sized for the widest reading it can ever hold, not for the
                    // current one. The percentage moves on every stats poll and
                    // proportional digits are not the same width, so binding to
                    // the live label shuffled every chip to its left a pixel or
                    // two, several times a minute.
                    implicitWidth: Math.ceil(memoryMetrics.width) + 18

                    TextMetrics {
                        id: memoryMetrics
                        font: memoryLabel.font
                        text: "Mem 100%"
                    }
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: memoryLabel
                        anchors.centerIn: parent
                        text: root.systemStatsMemoryLabel()
                        color: root.neutralChipText(memoryMouse.containsMouse)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: memoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }

                Rectangle {
                    id: diskChip
                    radius: root.radiusControl
                    color: root.diskChipFill(diskMouse.containsMouse)
                    border.color: root.diskChipBorder(diskMouse.containsMouse)
                    border.width: 1
                    implicitWidth: Math.ceil(diskMetrics.width) + 18

                    TextMetrics {
                        id: diskMetrics
                        font: diskLabel.font
                        text: "Disk 100%"
                    }
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: diskLabel
                        anchors.centerIn: parent
                        text: root.systemStatsDiskLabel()
                        color: root.diskChipText(diskMouse.containsMouse)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: diskMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    RootComponents.BarTooltip {
                        anchorWindow: topBarWindow
                        anchorItem: diskMouse
                        active: diskMouse.containsMouse
                        text: root.systemStatsDiskTooltip()
                        colors: topBarWindow.colors
                    }
                }

                Rectangle {
                    id: layoutChip
                    radius: root.radiusControl
                    readonly property bool displaySettingsActive: root.settingsVisible && root.stringOrEmpty(root.settingsSection) === "displays"
                    color: root.stateChipFill(displaySettingsActive, layoutMouse.containsMouse, colors.blueBg)
                    border.color: root.stateChipBorder(displaySettingsActive, layoutMouse.containsMouse, colors.blue)
                    border.width: 1
                    implicitWidth: layoutLabel.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: layoutLabel
                        anchors.centerIn: parent
                        text: "Displays ▾"
                        color: root.stateChipText(layoutChip.displaySettingsActive, layoutMouse.containsMouse, colors.blue)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: layoutMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Open the display selector popup on this bar's own monitor
                        // (the popup is gated to topOutputName). The popup's
                        // "Displays" button still drops into full Settings.
                        onClicked: root.openDisplaySelector(topBarWindow.topOutputName)
                    }

                }

                Rectangle {
                    id: moonlightChip
                    radius: root.radiusControl
                    color: root.moonlightChipFill(false)
                    border.color: root.moonlightChipBorder(false)
                    border.width: 1
                    implicitWidth: moonlightLabel.implicitWidth + 18
                    Layout.fillHeight: true
                    visible: root.boolOrFalse(root.moonlightStatus() && root.moonlightStatus().present)

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: moonlightLabel
                        anchors.centerIn: parent
                        text: root.moonlightChipLabel()
                        color: root.moonlightChipText(false)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: moonlightMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    RootComponents.BarTooltip {
                        anchorWindow: topBarWindow
                        anchorItem: moonlightMouse
                        active: moonlightMouse.containsMouse
                        text: root.moonlightChipTooltip()
                        colors: topBarWindow.colors
                    }
                }

                Rectangle {
                    id: networkChip
                    radius: root.radiusControl
                    color: root.neutralChipFill(networkMouse.containsMouse)
                    border.color: root.neutralChipBorder(networkMouse.containsMouse)
                    border.width: 1
                    implicitWidth: networkLabel.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: networkLabel
                        anchors.centerIn: parent
                        text: root.networkLabel()
                        color: root.networkChipText(networkMouse.containsMouse)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: networkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                root.runDetached(["nm-connection-editor"]);
                                return;
                            }
                            root.openSettings("devices");
                        }
                    }
                }

                Rectangle {
                    id: notificationChip
                    radius: root.radiusControl
                    color: root.notificationChipFill(notificationMouse.containsMouse)
                    border.color: root.notificationChipBorder(notificationMouse.containsMouse)
                    border.width: 1
                    implicitWidth: notificationLabel.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: notificationLabel
                        anchors.centerIn: parent
                        text: root.notificationLabel()
                        color: root.notificationChipText(notificationMouse.containsMouse)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: notificationMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function (mouse) {
                            if (root.notificationsBackendNative()) {
                                if (mouse.button === Qt.RightButton) {
                                    root.toggleNotificationDnd();
                                    return;
                                }
                                root.toggleNotifications();
                                return;
                            }
                            if (mouse.button === Qt.RightButton) {
                                root.runDetached(["swaync-client", "-d", "-sw"]);
                                return;
                            }
                            root.runDetached(["toggle-swaync"]);
                        }
                    }
                }

                Rectangle {
                    id: audioChip
                    radius: root.radiusControl
                    color: root.neutralChipFill(audioMouse.containsMouse)
                    border.color: root.audioChipBorder(audioMouse.containsMouse)
                    border.width: 1
                    implicitWidth: audioRow.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    RowLayout {
                        id: audioRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uf028"
                            color: root.audioChipText(audioMouse.containsMouse)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
                        }

                        Text {
                            id: audioLabel
                            Layout.alignment: Qt.AlignVCenter
                            text: root.audioLabel() + " ▾"
                            color: root.audioChipText(audioMouse.containsMouse)
                            font.pixelSize: root.fontLabel
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: audioMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                root.toggleMute();
                                return;
                            }
                            root.displaySelectorVisible = false;
                            root.bluetoothPopupVisible = false;
                            root.barPopupOutputName = topBarWindow.topOutputName;
                            root.audioPopupVisible = !root.audioPopupVisible;
                        }
                        onWheel: function (wheel) {
                            root.changeVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
                        }
                    }
                }

                Rectangle {
                    id: bluetoothChip
                    radius: root.radiusControl
                    color: root.neutralChipFill(bluetoothMouse.containsMouse)
                    border.color: root.neutralChipBorder(bluetoothMouse.containsMouse)
                    border.width: 1
                    implicitWidth: bluetoothRow.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    RowLayout {
                        id: bluetoothRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uf294"
                            color: root.neutralChipText(bluetoothMouse.containsMouse)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
                        }

                        Text {
                            id: bluetoothLabel
                            Layout.alignment: Qt.AlignVCenter
                            text: root.bluetoothLabel() + " ▾"
                            color: root.neutralChipText(bluetoothMouse.containsMouse)
                            font.pixelSize: root.fontLabel
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: bluetoothMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                root.toggleBluetoothEnabled();
                                return;
                            }
                            root.displaySelectorVisible = false;
                            root.audioPopupVisible = false;
                            root.barPopupOutputName = topBarWindow.topOutputName;
                            root.bluetoothPopupVisible = !root.bluetoothPopupVisible;
                        }
                    }
                }

                Rectangle {
                    id: batteryChip
                    visible: root.batteryReady()
                    Layout.preferredWidth: implicitWidth
                    Layout.minimumWidth: implicitWidth
                    radius: root.radiusControl
                    color: root.neutralChipFill(batteryMouse.containsMouse)
                    border.color: root.batteryChipBorder(batteryMouse.containsMouse)
                    border.width: 1
                    implicitWidth: batteryRow.implicitWidth + 16
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    RowLayout {
                        id: batteryRow
                        anchors.centerIn: parent
                        spacing: 5

                        IconImage {
                            implicitSize: 14
                            source: root.batteryIconSource()
                            visible: source !== ""
                            mipmap: true
                        }

                        Text {
                            text: root.batteryLabel()
                            color: root.batteryChipText(batteryMouse.containsMouse)
                            font.pixelSize: root.fontLabel
                            font.weight: Font.Medium
                            wrapMode: Text.NoWrap
                        }
                    }

                    MouseArea {
                        id: batteryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }

                RowLayout {
                    id: systemTrayRow
                    // On every bar, not just the focused one. Following focus
                    // meant the tray appeared and vanished on two bars at once
                    // every time the pointer crossed a monitor, and since it is
                    // the widest thing on the right it re-laid out the whole
                    // cluster each time. Duplicating the icons per monitor is
                    // what every other multi-head bar does, and it serves the
                    // original intent — reachable on whatever screen you are
                    // looking at — better than chasing focus did.
                    visible: root.arrayOrEmpty(SystemTray.items ? SystemTray.items.values : []).length > 0
                    spacing: 4

                    // Tray items that should always be visible even when Status.Passive
                    readonly property var pinnedTrayIds: ["rustdesk"]

                    Repeater {
                        model: SystemTray.items

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var trayItem: modelData
                            visible: trayItem.status !== Status.Passive || systemTrayRow.pinnedTrayIds.indexOf(root.stringOrEmpty(trayItem.id).toLowerCase()) !== -1
                            width: 24
                            height: 22
                            radius: root.radiusControl - 1
                            color: root.neutralChipFill(trayMouse.containsMouse)
                            border.color: root.neutralChipBorder(trayMouse.containsMouse)
                            border.width: 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: root.fastColorMs
                                }
                            }

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: root.fastColorMs
                                }
                            }

                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 14
                                source: {
                                    const iconName = root.stringOrEmpty(trayItem.icon);
                                    return iconName ? Quickshell.iconPath(iconName, true) : "";
                                }
                                visible: source !== ""
                                mipmap: true
                            }

                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: function (mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        trayItem.secondaryActivate();
                                        return;
                                    }

                                    if (trayItem.onlyMenu || trayItem.hasMenu) {
                                        const point = parent.mapToItem(topBarBackground, parent.width / 2, parent.height);
                                        trayItem.display(topBarWindow, point.x, point.y);
                                        return;
                                    }

                                    trayItem.activate();
                                }
                                onWheel: function (wheel) {
                                    trayItem.scroll(wheel.angleDelta.y > 0 ? 1 : -1, false);
                                }
                            }

                        }
                    }
                }

                Rectangle {
                    id: castChip
                    // Chromecast "extended display" via cast-extend; every Sway
                    // host can cast through Chrome, so show it on every bar.
                    // Gating on focus only made the right cluster reflow.
                    radius: root.radiusControl
                    color: root.castChipFill(castMouse.containsMouse)
                    border.color: root.castChipBorder(castMouse.containsMouse)
                    border.width: 1
                    implicitWidth: castGlyph.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: castGlyph
                        anchors.centerIn: parent
                        text: "\u{F0118}"
                        color: root.castChipText(castMouse.containsMouse)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: castMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.powerMenuVisible = false;
                            root.audioPopupVisible = false;
                            root.bluetoothPopupVisible = false;
                            root.displaySelectorVisible = false;
                            root.barPopupOutputName = topBarWindow.topOutputName;
                            root.castPopupVisible = !root.castPopupVisible;
                            if (root.castWatcherProcess && !root.castWatcherProcess.running) {
                                root.castWatcherProcess.running = true;
                            }
                        }
                    }
                }

                Rectangle {
                    id: powerChip
                    // On every bar. The popup already scopes itself to the bar
                    // it was opened from via barPopupOutputName, so there is
                    // nothing focus-specific left to gate on.
                    radius: root.radiusControl
                    color: root.powerChipFill(powerMouse.containsMouse)
                    border.color: root.powerChipBorder(powerMouse.containsMouse)
                    border.width: 1
                    implicitWidth: powerLabel.implicitWidth + 18
                    Layout.fillHeight: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: root.fastColorMs
                        }
                    }

                    Text {
                        id: powerLabel
                        anchors.centerIn: parent
                        text: "Power ▾"
                        color: root.powerChipText(powerMouse.containsMouse)
                        font.pixelSize: root.fontLabel
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.displaySelectorVisible = false;
                            root.barPopupOutputName = topBarWindow.topOutputName;
                            root.powerMenuVisible = !root.powerMenuVisible;
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        visible: root.displaySelectorVisible && root.stringOrEmpty(root.displaySelectorOutputName) === topBarWindow.topOutputName
        color: "transparent"
        implicitWidth: 320
        implicitHeight: displaySelectorCard.implicitHeight + 16
        anchor.window: topBarWindow
        anchor.item: layoutChip
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 6

        Rectangle {
            id: displaySelectorCard
            implicitWidth: 320
            implicitHeight: displaySelectorColumn.implicitHeight + 20
            radius: 12
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            ColumnLayout {
                id: displaySelectorColumn
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Displays"
                            color: colors.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.displayApplyStatusText()
                            color: root.displayApplyError ? colors.red : colors.subtle
                            font.pixelSize: 9
                            wrapMode: Text.WordWrap
                        }
                    }

                    Button {
                        text: "Displays"
                        onClicked: root.openSettings("displays")
                    }
                }

                // Quick configuration presets (role-based, resolved by EDID).
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.displayPresets()

                        delegate: Rectangle {
                            required property var modelData
                            readonly property string presetId: root.stringOrEmpty(modelData && modelData.id)
                            readonly property bool current: root.activeDisplayPresetId() === presetId
                            readonly property bool available: root.displayPresetAvailable(presetId)
                            readonly property bool pending: root.displayPresetPending(presetId)
                            visible: available
                            radius: 7
                            color: current ? colors.blueBg : colors.cardAlt
                            border.color: current ? colors.blue : colors.border
                            border.width: 1
                            implicitWidth: presetLabel.implicitWidth + 16
                            implicitHeight: presetLabel.implicitHeight + 10

                            Text {
                                id: presetLabel
                                anchors.centerIn: parent
                                text: pending ? "..." : root.stringOrEmpty(modelData && modelData.label)
                                color: current ? colors.blue : colors.text
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !current && !pending
                                onClicked: root.applyDisplayPreset(presetId)
                            }
                        }
                    }
                }

                // Live visual map of the physical arrangement (real rect geometry).
                Rectangle {
                    id: displayMapArea
                    Layout.fillWidth: true
                    implicitHeight: 124
                    radius: 8
                    color: colors.bg
                    border.color: colors.lineSoft
                    border.width: 1

                    Repeater {
                        model: root.displayMapBoxes(displayMapArea.width, displayMapArea.height)

                        delegate: Rectangle {
                            required property var modelData
                            x: modelData.x
                            y: modelData.y
                            width: modelData.w
                            height: modelData.h
                            radius: 5
                            // Every box in the map is an enabled/active display, so
                            // all get an "on" highlight; the primary (focused) output
                            // is distinguished in blue, the rest in teal.
                            color: modelData.primary ? colors.blueBg : colors.tealBg
                            border.color: modelData.primary ? colors.blue : colors.teal
                            border.width: 2

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.stringOrEmpty(modelData.label)
                                    color: modelData.primary ? colors.blue : colors.teal
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: modelData.h > 30
                                    text: root.stringOrEmpty(modelData.resolution)
                                    color: colors.subtle
                                    font.pixelSize: 8
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: modelData.h > 44
                                    text: modelData.primary ? "● primary" : "● on"
                                    color: modelData.primary ? colors.blue : colors.teal
                                    font.pixelSize: 7
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.enabledDisplayCount() > 1 && !root.displayTogglePending(modelData.name)
                                onClicked: root.toggleDisplayOutput(modelData.name)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.displayMapOutputs().length === 0
                        text: "No active displays"
                        color: colors.subtle
                        font.pixelSize: 10
                    }
                }

                // Connected-but-off displays — tap to turn back on.
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.displayOffOutputs().length > 0

                    Repeater {
                        model: root.displayOffOutputs()

                        delegate: Rectangle {
                            required property var modelData
                            readonly property string outName: root.stringOrEmpty(modelData && modelData.name)
                            readonly property bool pending: root.displayTogglePending(outName)
                            radius: 7
                            color: colors.panel
                            border.color: colors.lineSoft
                            border.width: 1
                            opacity: 0.75
                            implicitWidth: offChipRow.implicitWidth + 14
                            implicitHeight: offChipRow.implicitHeight + 8

                            Row {
                                id: offChipRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.displayFriendlyName(modelData)
                                    color: colors.subtle
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    font.strikeout: true
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pending ? "..." : "OFF"
                                    color: pending ? colors.subtle : colors.red
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleDisplayOutput(outName)
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Tap a screen to turn it off; tap an off chip to turn it on. Presets pick which externals are active."
                    color: colors.subtle
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    PopupWindow {
        visible: root.audioPopupVisible && root.stringOrEmpty(root.barPopupOutputName) === topBarWindow.topOutputName
        color: "transparent"
        implicitWidth: 340
        implicitHeight: audioPopupCard.implicitHeight + 16
        anchor.window: topBarWindow
        anchor.item: audioChip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 6

        Rectangle {
            id: audioPopupCard
            implicitWidth: 340
            implicitHeight: audioPopupColumn.implicitHeight + 20
            radius: 12
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            ColumnLayout {
                id: audioPopupColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Audio"
                            color: colors.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.audioDetail()
                            color: colors.subtle
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Button {
                        text: root.audioMuted() ? "Unmute" : "Mute"
                        onClicked: root.toggleMute()
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 150
                    value: root.volumePercent()
                    onMoved: {
                        const node = root.audioNode();
                        if (node && node.audio) {
                            node.audio.volume = Math.max(0, Math.min(1.5, value / 100));
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        text: "-5%"
                        onClicked: root.changeVolume(-0.05)
                    }

                    Button {
                        text: "+5%"
                        onClicked: root.changeVolume(0.05)
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Mixer"
                        onClicked: root.runDetached(["pavucontrol"])
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: colors.lineSoft
                }

                Text {
                    text: "Outputs"
                    color: colors.text
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: root.audioNodes()

                    delegate: Rectangle {
                        required property var modelData
                        readonly property var sink: modelData
                        readonly property bool activeSink: root.audioSinkIsActive(sink)
                        readonly property string sinkKind: root.audioSinkKind(sink)
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 8
                        color: activeSink ? colors.blueBg : (rowHover.containsMouse ? colors.cardAlt : colors.card)
                        border.color: activeSink ? colors.blue : colors.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: root.fastColorMs } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 9

                            // Selection dot — clear active vs inactive at a glance.
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 9
                                height: 9
                                radius: 5
                                color: activeSink ? colors.blue : colors.muted
                                opacity: activeSink ? 1.0 : 0.3
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: root.audioSinkLabel(sink)
                                    color: activeSink ? colors.blue : colors.text
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: sinkKind !== ""
                                    text: sinkKind
                                    color: colors.subtle
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                visible: activeSink
                                text: "Active"
                                color: colors.blue
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setPreferredAudioSink(sink)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: colors.lineSoft
                }

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Input"
                            color: colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.audioInputDetail()
                            color: colors.subtle
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Button {
                        text: root.audioInputMuted() ? "Unmute" : "Mute"
                        onClicked: root.toggleInputMute()
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 150
                    value: root.inputVolumePercent()
                    onMoved: root.setInputVolumePercent(value)
                }

                Repeater {
                    model: root.audioSourceNodes()

                    delegate: Rectangle {
                        required property var modelData
                        readonly property var source: modelData
                        readonly property bool activeSource: root.audioSourceIsActive(source)
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 8
                        color: activeSource ? colors.blueBg : colors.cardAlt
                        border.color: activeSource ? colors.blue : colors.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: root.audioSourceLabel(source)
                                color: activeSource ? colors.blue : colors.text
                                font.pixelSize: 9
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: activeSource
                                text: "Live"
                                color: colors.blue
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setPreferredAudioSource(source)
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        visible: root.bluetoothPopupVisible && root.stringOrEmpty(root.barPopupOutputName) === topBarWindow.topOutputName
        color: "transparent"
        implicitWidth: 300
        implicitHeight: bluetoothPopupCard.implicitHeight + 16
        anchor.window: topBarWindow
        anchor.item: bluetoothChip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 6

        Rectangle {
            id: bluetoothPopupCard
            implicitWidth: 300
            implicitHeight: bluetoothPopupColumn.implicitHeight + 20
            radius: 12
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            ColumnLayout {
                id: bluetoothPopupColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Bluetooth"
                            color: colors.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.bluetoothDetail()
                            color: colors.subtle
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Button {
                        text: root.bluetoothEnabled() ? "Turn Off" : "Turn On"
                        enabled: root.bluetoothAvailable()
                        onClicked: root.toggleBluetoothEnabled()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.networkDetail()
                        color: colors.subtle
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Manager"
                        onClicked: root.runDetached(["blueman-manager"])
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: colors.lineSoft
                }

                Text {
                    visible: root.bluetoothAvailable() && root.bluetoothDevices().length > 0
                    text: "Devices"
                    color: colors.text
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: root.bluetoothDevices()

                    delegate: Rectangle {
                        required property var modelData
                        readonly property var device: modelData
                        readonly property bool connected: !!(device && device.connected)
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 8
                        color: connected ? colors.tealBg : colors.cardAlt
                        border.color: connected ? colors.teal : colors.border
                        border.width: 1
                        visible: device !== null

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: root.stringOrEmpty(device && device.name) || "Bluetooth device"
                                color: connected ? colors.teal : colors.text
                                font.pixelSize: 9
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                text: connected ? "Disconnect" : "Connect"
                                color: connected ? colors.teal : colors.subtle
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.bluetoothEnabled()
                            onClicked: root.toggleBluetoothDevice(device)
                        }
                    }
                }

                Text {
                    visible: !root.bluetoothAvailable()
                    text: "No Bluetooth adapter detected on this host."
                    color: colors.subtle
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    PopupWindow {
        visible: root.powerMenuVisible && root.stringOrEmpty(root.barPopupOutputName) === topBarWindow.topOutputName
        color: "transparent"
        implicitWidth: 188
        implicitHeight: powerMenuContent.implicitHeight + 16
        anchor.window: topBarWindow
        anchor.item: powerChip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 6

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            ColumnLayout {
                id: powerMenuContent
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 6

                Repeater {
                    model: [
                        {
                            label: "Lock",
                            command: ["lock-session"]
                        },
                        {
                            label: "Suspend",
                            command: ["systemctl", "suspend"]
                        },
                        {
                            label: "Exit Sway",
                            command: ["swaymsg", "exit"]
                        },
                        {
                            label: "Reboot",
                            command: ["systemctl", "reboot"]
                        },
                        {
                            label: "Shutdown",
                            command: ["systemctl", "poweroff"]
                        }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: root.neutralChipFill(powerActionMouse.containsMouse)
                        border.color: root.neutralChipBorder(powerActionMouse.containsMouse)
                        border.width: 1

                        Behavior on color {
                            ColorAnimation {
                                duration: root.fastColorMs
                            }
                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: root.fastColorMs
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.neutralChipText(powerActionMouse.containsMouse)
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: powerActionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerPowerAction(modelData.command)
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        visible: root.castPopupVisible && root.stringOrEmpty(root.barPopupOutputName) === topBarWindow.topOutputName
        color: "transparent"
        implicitWidth: 260
        implicitHeight: castPopupCard.implicitHeight + 16
        anchor.window: topBarWindow
        anchor.item: castChip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 6

        Rectangle {
            id: castPopupCard
            implicitWidth: 260
            implicitHeight: castPopupColumn.implicitHeight + 20
            radius: 12
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            ColumnLayout {
                id: castPopupColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Cast (Chromecast)"
                        color: colors.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.stringOrEmpty(root.castState.detail)
                        color: colors.subtle
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Extend: the TV becomes its own display — the TV output is picked automatically; move windows with cast-extend send.\nMirror: cast start — casts the focused screen.\nMenu: ;c in the launcher."
                        color: colors.subtle
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        text: root.boolOrFalse(root.castState.active) ? "Stop casting" : "Cast to TV"
                        onClicked: root.castToggle()
                    }
                }
            }
        }
    }
}
