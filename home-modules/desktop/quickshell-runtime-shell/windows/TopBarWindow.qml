import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

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
    height: runtimeConfig.topBarHeight
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

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    id: panelToggleChip
                    radius: 8
                    color: root.stateChipFill(root.panelVisible, panelToggleMouse.containsMouse, colors.blueBg)
                    border.color: root.stateChipBorder(root.panelVisible, panelToggleMouse.containsMouse, colors.blue)
                    border.width: 1
                    implicitWidth: panelToggleLabel.implicitWidth + 20
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: panelToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePanelVisibility()
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                radius: 9
                color: colors.card
                border.color: colors.border
                border.width: 1
                implicitWidth: centerRow.implicitWidth + 20
                implicitHeight: parent.height

                RowLayout {
                    id: centerRow
                    anchors.centerIn: parent
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
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "│"
                        color: colors.subtle
                        font.pixelSize: 10
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        id: clockLabel
                        text: root.topBarTimeText()
                        color: colors.text
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: 6

                Rectangle {
                    id: daemonHealthChip
                    radius: 8
                    color: root.daemonHealthColor(daemonHealthMouse.containsMouse)
                    border.color: root.daemonHealthBorderColor(daemonHealthMouse.containsMouse)
                    border.width: 1
                    implicitWidth: daemonHealthRow.implicitWidth + 18
                    implicitHeight: parent.height
                    visible: root.daemonHealthState.status !== "healthy"

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
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: daemonHealthMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ToolTip {
                        visible: daemonHealthMouse.containsMouse
                        text: root.daemonHealthTooltip()
                        delay: 500
                    }
                }

                Rectangle {
                    id: generationChip
                    radius: 8
                    color: root.neutralChipFill(generationMouse.containsMouse)
                    border.color: root.neutralChipBorder(generationMouse.containsMouse)
                    border.width: 1
                    implicitWidth: generationLabel.implicitWidth + 18
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
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
                    radius: 8
                    color: root.neutralChipFill(memoryMouse.containsMouse)
                    border.color: root.neutralChipBorder(memoryMouse.containsMouse)
                    border.width: 1
                    implicitWidth: memoryLabel.implicitWidth + 18
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
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
                    radius: 8
                    color: root.diskChipFill(diskMouse.containsMouse)
                    border.color: root.diskChipBorder(diskMouse.containsMouse)
                    border.width: 1
                    implicitWidth: diskLabel.implicitWidth + 18
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: diskMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ToolTip {
                        visible: diskMouse.containsMouse
                        text: root.systemStatsDiskTooltip()
                        delay: 400
                    }
                }

                Rectangle {
                    id: layoutChip
                    radius: 8
                    readonly property bool displaySettingsActive: root.settingsVisible && root.stringOrEmpty(root.settingsSection) === "displays"
                    color: root.stateChipFill(displaySettingsActive, layoutMouse.containsMouse, colors.blueBg)
                    border.color: root.stateChipBorder(displaySettingsActive, layoutMouse.containsMouse, colors.blue)
                    border.width: 1
                    implicitWidth: layoutLabel.implicitWidth + 18
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: layoutMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openSettings("displays")
                    }

                }

                Rectangle {
                    id: moonlightChip
                    radius: 8
                    color: root.moonlightChipFill(moonlightMouse.containsMouse)
                    border.color: root.moonlightChipBorder(moonlightMouse.containsMouse)
                    border.width: 1
                    implicitWidth: moonlightLabel.implicitWidth + 18
                    implicitHeight: parent.height
                    visible: root.boolOrFalse(root.moonlightStatusState && root.moonlightStatusState.present)

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
                        color: root.moonlightChipText(moonlightMouse.containsMouse)
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: moonlightMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ToolTip {
                        visible: moonlightMouse.containsMouse
                        text: root.moonlightChipTooltip()
                        delay: 400
                    }
                }

                Rectangle {
                    id: networkChip
                    radius: 8
                    color: root.neutralChipFill(networkMouse.containsMouse)
                    border.color: root.neutralChipBorder(networkMouse.containsMouse)
                    border.width: 1
                    implicitWidth: networkLabel.implicitWidth + 18
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
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
                    radius: 8
                    color: root.notificationChipFill(notificationMouse.containsMouse)
                    border.color: root.notificationChipBorder(notificationMouse.containsMouse)
                    border.width: 1
                    implicitWidth: notificationLabel.implicitWidth + 18
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
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
                    radius: 8
                    color: root.neutralChipFill(audioMouse.containsMouse)
                    border.color: root.audioChipBorder(audioMouse.containsMouse)
                    border.width: 1
                    implicitWidth: audioRow.implicitWidth + 18
                    implicitHeight: parent.height

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
                            font.pixelSize: 10
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
                            root.audioPopupVisible = !root.audioPopupVisible;
                        }
                        onWheel: function (wheel) {
                            root.changeVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
                        }
                    }
                }

                Rectangle {
                    id: bluetoothChip
                    radius: 8
                    color: root.neutralChipFill(bluetoothMouse.containsMouse)
                    border.color: root.neutralChipBorder(bluetoothMouse.containsMouse)
                    border.width: 1
                    implicitWidth: bluetoothRow.implicitWidth + 18
                    implicitHeight: parent.height

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
                            font.pixelSize: 10
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
                            root.bluetoothPopupVisible = !root.bluetoothPopupVisible;
                        }
                    }
                }

                Rectangle {
                    id: batteryChip
                    visible: root.batteryReady()
                    Layout.preferredWidth: implicitWidth
                    Layout.minimumWidth: implicitWidth
                    radius: 8
                    color: root.neutralChipFill(batteryMouse.containsMouse)
                    border.color: root.batteryChipBorder(batteryMouse.containsMouse)
                    border.width: 1
                    implicitWidth: batteryRow.implicitWidth + 16
                    implicitHeight: parent.height

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
                            font.pixelSize: 10
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
                    visible: topBarWindow.isPrimaryBar && root.arrayOrEmpty(SystemTray.items ? SystemTray.items.values : []).length > 0
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
                            radius: 7
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
                    id: powerChip
                    visible: topBarWindow.isPrimaryBar
                    radius: 8
                    color: root.powerChipFill(powerMouse.containsMouse)
                    border.color: root.powerChipBorder(powerMouse.containsMouse)
                    border.width: 1
                    implicitWidth: powerLabel.implicitWidth + 18
                    implicitHeight: parent.height

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
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.displaySelectorVisible = false;
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

                Text {
                    Layout.fillWidth: true
                    text: "Outputs: " + root.activeDisplaySummary()
                    color: colors.subtle
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.allDisplayOutputs().length > 0

                    Repeater {
                        model: root.allDisplayOutputs()

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var output: modelData
                            readonly property bool outputEnabled: !!(output && output.enabled !== false)
                            readonly property bool pending: root.displayTogglePending(root.stringOrEmpty(output && output.name))
                            radius: 7
                            color: output && output.primary ? colors.blueBg : (outputEnabled ? colors.cardAlt : colors.panel)
                            border.color: output && output.primary ? colors.blue : (outputEnabled ? colors.border : colors.lineSoft)
                            border.width: 1
                            opacity: outputEnabled ? 1.0 : 0.5
                            implicitWidth: outputToggleRow.implicitWidth + 14
                            implicitHeight: outputToggleRow.implicitHeight + 8

                            Row {
                                id: outputToggleRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.stringOrEmpty(output && output.name)
                                    color: output && output.primary ? colors.blue : colors.text
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    font.strikeout: !outputEnabled
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pending ? "..." : (outputEnabled ? "ON" : "OFF")
                                    color: pending ? colors.subtle : (outputEnabled ? colors.teal : colors.red)
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleDisplayOutput(root.stringOrEmpty(output && output.name))
                            }
                        }
                    }
                }

                Repeater {
                    model: root.displayLayoutOptions()

                    delegate: Rectangle {
                        required property var modelData
                        readonly property string layoutName: root.displayOptionName(modelData)
                        readonly property bool current: !!(modelData && modelData.current)
                        readonly property bool pending: root.displayApplyPending(layoutName)
                        readonly property var outputNames: root.displayOptionOutputs(modelData)
                        Layout.fillWidth: true
                        implicitHeight: layoutOptionColumn.implicitHeight + 20
                        radius: 10
                        color: current ? colors.blueBg : colors.cardAlt
                        border.color: current ? colors.blue : colors.lineSoft
                        border.width: 1

                        // Keep pointer handling on the MouseArea. A direct Rectangle cursor
                        // property can make the entire TopBarWindow fail to load on some hosts.
                        ColumnLayout {
                            id: layoutOptionColumn
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: root.displayOptionLabel(modelData)
                                        color: current ? colors.blue : colors.text
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: root.displayOptionDescription(modelData)
                                        color: colors.subtle
                                        font.pixelSize: 9
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Rectangle {
                                    visible: current
                                    radius: 7
                                    color: colors.panel
                                    border.color: colors.blue
                                    border.width: 1
                                    implicitWidth: currentBadgeText.implicitWidth + 12
                                    implicitHeight: currentBadgeText.implicitHeight + 8

                                    Text {
                                        id: currentBadgeText
                                        anchors.centerIn: parent
                                        text: "Current"
                                        color: colors.blue
                                        font.pixelSize: 8
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Button {
                                    text: pending ? "Applying" : (current ? "Active" : "Apply")
                                    enabled: !pending && !current && !(root.displayApplyProcess && root.displayApplyProcess.running)
                                    onClicked: root.applyDisplayLayout(layoutName)
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: outputNames.length > 0
                                text: outputNames.join("  •  ")
                                color: colors.subtle
                                font.pixelSize: 9
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.displayLayoutOptions().length === 0
                    text: "No daemon-backed display layouts are configured for this host yet."
                    color: colors.subtle
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    PopupWindow {
        visible: topBarWindow.isPrimaryBar && root.audioPopupVisible
        color: "transparent"
        implicitWidth: 280
        implicitHeight: audioPopupCard.implicitHeight + 16
        anchor.window: topBarWindow
        anchor.item: audioChip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 6

        Rectangle {
            id: audioPopupCard
            implicitWidth: 280
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
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 8
                        color: activeSink ? colors.blueBg : colors.cardAlt
                        border.color: activeSink ? colors.blue : colors.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: root.audioSinkLabel(sink)
                                color: activeSink ? colors.blue : colors.text
                                font.pixelSize: 9
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: activeSink
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
        visible: topBarWindow.isPrimaryBar && root.bluetoothPopupVisible
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
        visible: topBarWindow.isPrimaryBar && root.powerMenuVisible
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
                            command: ["swaylock", "-f"]
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
}
