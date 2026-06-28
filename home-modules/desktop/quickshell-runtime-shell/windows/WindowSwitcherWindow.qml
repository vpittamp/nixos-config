import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

import ".." as RootComponents

// Full-screen window-switcher exposé, GROUPED BY MONITOR. Windows are arranged
// into one panel per monitor, ordered left-to-right to match the physical
// monitor layout, so you can see at a glance where each window lives. Reuses
// shell.qml's window data + focus/move actions. Live thumbnails aren't feasible
// on sway+Quickshell, so tiles are icon-based. Keyboard focus uses the same
// field-grab pattern as the launcher (focus: root.exposeVisible).
PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    property alias focusItemRef: exposeField
    id: switcherWindow
    // Map on the monitor where the exposé was activated (falls back to the
    // focused/primary monitor when no output was captured). Mirrors RuntimePanelWindow.
    screen: root.findScreenByOutputName(root.exposeOutputName) || root.activeScreen
    visible: root.exposeVisible
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Read live monitor x-positions from sway when the exposé opens, so the
    // panels are ordered left-to-right to match the physical layout (the daemon
    // dashboard geometry is stale).
    Process {
        id: outputPosProc
        command: ["swaymsg", "-t", "get_outputs"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseExposeOutputX(this.text)
        }
    }

    Connections {
        target: root
        function onExposeVisibleChanged() {
            if (root.exposeVisible) {
                outputPosProc.running = true;
            }
        }
    }

    // One reusable window tile, used by every monitor panel's Flow. modelData is
    // a window entry; _gi is its global selection index across all panels.
    Component {
        id: windowTile

        Item {
            id: cell
            required property var modelData
            readonly property var entry: modelData
            readonly property int gi: Number((entry && entry._gi) || 0)
            readonly property bool selected: gi === root.exposeSelectedIndex
            readonly property bool focusedWindow: entry && entry.focused === true
            readonly property color accentColor: root.launcherEntryAccentColor(entry)
            readonly property var moveTargets: root.exposeMoveTargets(entry)
            width: 224
            height: 190
            // Staggered entrance (opacity + scale only — `y` is owned by the Flow
            // layout). Stagger is capped so large window counts stay snappy under
            // the software render backend.
            opacity: 0
            scale: 0.92
            transformOrigin: Item.Center
            SequentialAnimation {
                running: true
                PauseAnimation { duration: Math.min(cell.gi * 14, 200) }
                ParallelAnimation {
                    NumberAnimation { target: cell; property: "opacity"; to: 1; duration: 130; easing.type: Easing.OutCubic }
                    NumberAnimation { target: cell; property: "scale"; to: 1; duration: 150; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                anchors.fill: tile
                anchors.margins: -3
                radius: 18
                color: cell.accentColor
                opacity: cell.selected ? 0.30 : (tileMouse.containsMouse ? 0.15 : 0)
                Behavior on opacity { NumberAnimation { duration: root.fastColorMs } }
            }

            Rectangle {
                id: tile
                anchors.fill: parent
                anchors.margins: 7
                radius: 16
                color: cell.selected ? colors.cardAlt : (tileMouse.containsMouse ? colors.panelAlt : colors.card)
                border.width: (cell.focusedWindow || cell.selected) ? 2 : 1
                border.color: cell.focusedWindow ? colors.green
                    : (cell.selected ? cell.accentColor : colors.border)
                scale: (cell.selected || tileMouse.containsMouse) ? 1.04 : 1.0
                transformOrigin: Item.Center

                Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                // Accent top-strip emphasising the selected / focused tile (inset
                // past the corner radius so its ends stay on the flat top edge).
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 36
                    height: 3
                    radius: 2
                    visible: cell.selected || cell.focusedWindow
                    color: cell.focusedWindow ? colors.green : cell.accentColor
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    anchors.bottomMargin: cell.moveTargets.length > 0 && !root.exposeEntryIsRemote(cell.entry) ? 42 : 12
                    spacing: 6

                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        implicitSize: 52
                        source: root.iconSourceFor(cell.entry)
                        mipmap: true
                        asynchronous: true
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: root.displayTitle(cell.entry)
                        color: colors.text
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6

                        Rectangle {
                            visible: metaText.text.length > 0
                            radius: 6
                            color: colors.blueWash
                            border.color: colors.blueMuted
                            border.width: 1
                            Layout.preferredHeight: 19
                            Layout.preferredWidth: metaText.implicitWidth + 12
                            Text {
                                id: metaText
                                anchors.centerIn: parent
                                text: root.displayMeta(cell.entry)
                                color: colors.textDim
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }
                        }

                        Rectangle {
                            visible: projText.text.length > 0
                            radius: 6
                            color: Qt.rgba(0, 0, 0, 0.25)
                            border.color: cell.accentColor
                            border.width: 1
                            Layout.preferredHeight: 19
                            Layout.preferredWidth: projText.implicitWidth + 12
                            Text {
                                id: projText
                                anchors.centerIn: parent
                                text: root.shortProject(cell.entry && cell.entry.project)
                                color: cell.accentColor
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                Rectangle {
                    visible: cell.focusedWindow
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    radius: 6
                    height: 18
                    width: focusedText.implicitWidth + 12
                    color: colors.greenBg
                    border.color: colors.green
                    border.width: 1
                    Text {
                        id: focusedText
                        anchors.centerIn: parent
                        text: "current"
                        color: colors.green
                        font.pixelSize: 8
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.updateExposePointerSelection(cell.gi)
                    onEntered: root.updateExposePointerSelection(cell.gi)
                    onClicked: function (mouse) {
                        if (mouse.button === Qt.MiddleButton) {
                            root.closeExposeWindowEntry(cell.entry);
                            return;
                        }
                        root.updateExposePointerSelection(cell.gi);
                        root.activateExposeSelection();
                    }
                }

                // Close-window affordance (touch-reachable; middle-click also works).
                // Layered above tileMouse so its tap closes the window, not focuses it.
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 8
                    width: 24
                    height: 24
                    radius: 12
                    color: closeMouse.containsMouse ? colors.redBg : Qt.rgba(0, 0, 0, 0.45)
                    border.color: closeMouse.containsMouse ? colors.red : colors.border
                    border.width: 1
                    opacity: closeMouse.containsMouse ? 1.0 : (cell.selected ? 0.9 : 0.5)
                    Behavior on opacity { NumberAnimation { duration: root.fastColorMs } }
                    Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: closeMouse.containsMouse ? colors.red : colors.textDim
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeExposeWindowEntry(cell.entry)
                    }
                }

                // "Move to <other monitor>" chips, layered above tileMouse so a
                // chip click moves the window's whole workspace there. Hidden for
                // remote windows / single-monitor setups.
                Row {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 8
                    spacing: 4
                    visible: !root.exposeEntryIsRemote(cell.entry) && cell.moveTargets.length > 0

                    Repeater {
                        model: cell.moveTargets

                        delegate: Rectangle {
                            required property string modelData
                            readonly property string outName: modelData
                            height: 28
                            width: moveRow.implicitWidth + 18
                            radius: 8
                            color: moveMouse.containsMouse ? colors.blueBg : Qt.rgba(0, 0, 0, 0.4)
                            border.width: 1
                            border.color: moveMouse.containsMouse ? colors.blue : colors.border
                            Behavior on color { ColorAnimation { duration: root.fastColorMs } }

                            Row {
                                id: moveRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ""        // arrow-right-circle
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 11
                                    color: moveMouse.containsMouse ? colors.blue : colors.muted
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.exposeOutputLabel(outName)
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: moveMouse.containsMouse ? colors.blue : colors.textDim
                                }
                            }

                            MouseArea {
                                id: moveMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.moveExposeWindowToOutput(cell.entry, outName)
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#cc070b12"
        // Fade the dark backdrop in when the overlay maps (entrance-only; the
        // window unmaps immediately on close so there's no exit tween to show).
        opacity: root.exposeVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.closeExpose()
        }

        ColumnLayout {
            id: exposeStage
            anchors.centerIn: parent
            width: Math.min(parent.width - 100, 2200)
            height: Math.min(parent.height - 100, 1200)
            spacing: 14
            // Subtle scale-in of the whole overview as it appears.
            scale: root.exposeVisible ? 1 : 0.965
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            TextField {
                id: exposeField
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(520, parent.width - 40)
                focus: root.exposeVisible
                placeholderText: "Type to filter windows…"
                color: colors.text
                font.pixelSize: 15
                leftPadding: 16
                rightPadding: exposeField.text.length > 0 ? 40 : 16
                topPadding: 10
                bottomPadding: 10
                horizontalAlignment: TextInput.AlignHCenter

                background: Rectangle {
                    radius: 12
                    color: colors.card
                    border.color: exposeField.activeFocus ? colors.blue : colors.border
                    border.width: 1
                }

                // Clear-filter affordance (touch-friendly), shown when filtering.
                Rectangle {
                    visible: exposeField.text.length > 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 8
                    width: 24
                    height: 24
                    radius: 12
                    color: clearMouse.containsMouse ? colors.cardAlt : "transparent"
                    Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 12
                        color: clearMouse.containsMouse ? colors.text : colors.textDim
                    }
                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            exposeField.text = "";
                            exposeField.forceActiveFocus();
                        }
                    }
                }

                onTextChanged: {
                    if (root.exposeQuery !== text) {
                        root.exposeQuery = text;
                        root.refreshExposeEntries();
                    }
                }

                Connections {
                    target: root
                    function onExposeVisibleChanged() {
                        if (root.exposeVisible) {
                            exposeField.text = "";
                            exposeField.forceActiveFocus();
                        }
                    }
                }

                Keys.onPressed: function (event) {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        root.closeExpose();
                        event.accepted = true;
                        break;
                    case Qt.Key_Left:
                        root.moveExposeSelectionSpatial("left");
                        event.accepted = true;
                        break;
                    case Qt.Key_Right:
                        root.moveExposeSelectionSpatial("right");
                        event.accepted = true;
                        break;
                    case Qt.Key_Up:
                        root.moveExposeSelectionSpatial("up");
                        event.accepted = true;
                        break;
                    case Qt.Key_Down:
                        root.moveExposeSelectionSpatial("down");
                        event.accepted = true;
                        break;
                    case Qt.Key_Tab:
                        root.cycleExposeSelection((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        event.accepted = true;
                        break;
                    case Qt.Key_Backtab:
                        root.cycleExposeSelection(-1);
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.activateExposeSelection();
                        event.accepted = true;
                        break;
                    default:
                        break;
                    }
                }

                Keys.onReleased: function (event) {
                    switch (event.key) {
                    case Qt.Key_Alt:
                    case Qt.Key_AltGr:
                        if (root.exposeSwitcherActive) {
                            root.commitExposeSwitch();
                            event.accepted = true;
                        }
                        break;
                    default:
                        break;
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: root.exposeEntries.length > 0
                text: root.exposeEntries.length + (root.exposeEntries.length === 1 ? " window across "
                    : " windows across ") + root.exposePanelOutputs().length
                    + (root.exposePanelOutputs().length === 1 ? " monitor" : " monitors")
                color: colors.subtle
                font.pixelSize: 11
            }

            Text {
                visible: root.exposeEntries.length === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                verticalAlignment: Text.AlignVCenter
                text: root.stringOrEmpty(root.exposeQuery) ? "No windows match “" + root.exposeQuery + "”" : "No open windows"
                color: colors.muted
                font.pixelSize: 16
            }

            // One panel per monitor, ordered left-to-right by physical position.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.exposeEntries.length > 0
                spacing: 16

                Repeater {
                    model: root.exposePanelOutputs()

                    delegate: Rectangle {
                        required property string modelData
                        readonly property string panelOut: modelData
                        readonly property var panelWindows: root.exposeWindowsForOutput(panelOut)
                        // The monitor where the exposé was activated ("you are here").
                        readonly property bool activePanel: panelOut === root.stringOrEmpty(root.exposeOutputName)
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1     // equal share among panels
                        radius: 18
                        color: activePanel ? Qt.rgba(0.20, 0.52, 0.95, 0.08) : Qt.rgba(1, 1, 1, 0.025)
                        border.color: activePanel ? colors.blue : colors.border
                        border.width: activePanel ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }
                        Behavior on color { ColorAnimation { duration: root.fastColorMs } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            // Monitor header.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 9

                                Text {
                                    text: root.exposeOutputGlyph(panelOut)
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 18
                                    color: colors.blue
                                }
                                Text {
                                    text: root.exposeOutputLabel(panelOut)
                                    color: colors.text
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    radius: 9
                                    color: colors.panelAlt
                                    border.color: colors.border
                                    border.width: 1
                                    Layout.preferredHeight: 22
                                    Layout.preferredWidth: countText.implicitWidth + 16
                                    Text {
                                        id: countText
                                        anchors.centerIn: parent
                                        text: panelWindows.length
                                        color: colors.muted
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: colors.lineSoft
                            }

                            // Tiles for this monitor (wrap + scroll if many).
                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                contentHeight: tileFlow.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds

                                Flow {
                                    id: tileFlow
                                    width: parent.width
                                    spacing: 4

                                    Repeater {
                                        model: panelWindows
                                        delegate: windowTile
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Small dictation toggle in the top-right corner.
        Rectangle {
            id: exposeDictate
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 28
            height: 40
            implicitWidth: exposeDictateRow.implicitWidth + 24
            radius: 12
            color: root.voxtypeClass() === "recording" ? colors.redBg
                : (exposeDictateMouse.containsMouse ? colors.card : colors.cardAlt)
            border.width: root.voxtypeActive() ? 2 : 1
            border.color: root.voxtypeActive() ? root.voxtypeIconColor()
                : (exposeDictateMouse.containsMouse ? colors.borderStrong : colors.border)

            Behavior on color { ColorAnimation { duration: root.fastColorMs } }
            Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }

            RowLayout {
                id: exposeDictateRow
                anchors.centerIn: parent
                spacing: 7

                Text {
                    text: root.voxtypeIcon()
                    color: root.voxtypeActive() ? root.voxtypeIconColor() : colors.muted
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 15

                    SequentialAnimation on opacity {
                        running: root.voxtypeClass() === "recording"
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { from: 1.0; to: 0.3; duration: 600 }
                        NumberAnimation { from: 0.3; to: 1.0; duration: 600 }
                    }
                }

                Text {
                    text: root.voxtypeClass() === "recording" ? "Recording…"
                        : (root.voxtypeClass() === "transcribing" ? "Transcribing…" : "Dictate")
                    color: root.voxtypeActive() ? root.voxtypeIconColor() : colors.text
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            MouseArea {
                id: exposeDictateMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.closeExpose();
                    root.runDetached([runtimeConfig.dictationBin, "toggle"]);
                }
            }
        }
    }
}
