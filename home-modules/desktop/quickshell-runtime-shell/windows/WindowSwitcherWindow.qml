import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import ".." as RootComponents

// Full-screen window-switcher exposé. A responsive grid of large window tiles
// (app icon + title + workspace/project badge + focused ring) on the active
// monitor. Reuses shell.qml's window data + focus actions; see expose* state
// and functions there. Live thumbnails are not feasible on sway+Quickshell, so
// tiles are icon-based. Keyboard focus uses the same field-grab pattern as the
// app launcher (focus: root.exposeVisible) so Esc/arrows/Alt-release reach us.
PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    property alias gridRef: exposeGrid
    property alias focusItemRef: exposeField
    id: switcherWindow
    screen: root.activeScreen
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

    ScriptModel {
        id: exposeEntriesModel
        values: root.exposeEntries
        objectProp: "model_key"
    }

    // Heavy solid dim (no live blur on overlay layers — perf/flicker).
    Rectangle {
        anchors.fill: parent
        color: "#cc070b12"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.closeExpose()
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 120, 1800)
            height: Math.min(parent.height - 120, 1100)
            spacing: 16

            // Search/filter field. Doubles as the keyboard-focus owner: the
            // `focus: root.exposeVisible` binding claims the overlay's exclusive
            // keyboard when it opens, exactly like LauncherWindow's field.
            TextField {
                id: exposeField
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(520, parent.width - 40)
                focus: root.exposeVisible
                placeholderText: "Type to filter windows…"
                color: colors.text
                font.pixelSize: 15
                leftPadding: 16
                rightPadding: 16
                topPadding: 10
                bottomPadding: 10
                horizontalAlignment: TextInput.AlignHCenter

                background: Rectangle {
                    radius: 12
                    color: colors.card
                    border.color: exposeField.activeFocus ? colors.blue : colors.border
                    border.width: 1
                }

                onTextChanged: {
                    if (root.exposeQuery !== text) {
                        root.exposeQuery = text;
                        root.refreshExposeEntries();
                    }
                }

                // Clear + re-grab focus each time the exposé opens.
                Connections {
                    target: root
                    function onExposeVisibleChanged() {
                        if (root.exposeVisible) {
                            exposeField.text = "";
                            exposeField.forceActiveFocus();
                        }
                    }
                }

                // Navigation/commit keys are intercepted here (accepted=true) so
                // the field's cursor handling never swallows them; printable keys
                // and Backspace fall through to edit the filter text.
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

            // Count hint.
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: root.exposeEntries.length > 0
                text: root.exposeEntries.length + (root.exposeEntries.length === 1 ? " window" : " windows")
                color: colors.subtle
                font.pixelSize: 11
            }

            // Empty state.
            Text {
                visible: root.exposeEntries.length === 0
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                verticalAlignment: Text.AlignVCenter
                text: root.stringOrEmpty(root.exposeQuery) ? "No windows match “" + root.exposeQuery + "”" : "No open windows"
                color: colors.muted
                font.pixelSize: 16
            }

            GridView {
                id: exposeGrid
                visible: root.exposeEntries.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: exposeEntriesModel
                interactive: true
                keyNavigationEnabled: false
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 1200

                readonly property int itemCount: root.exposeEntries.length
                readonly property int colCount: Math.max(1, Math.min(itemCount, Math.floor(width / 280)))
                readonly property int rowCount: Math.max(1, Math.ceil(itemCount / colCount))
                cellWidth: Math.floor(width / colCount)
                cellHeight: Math.max(150, Math.min(230, Math.floor(height / rowCount)))

                onColCountChanged: root.exposeColumns = colCount
                Component.onCompleted: root.exposeColumns = colCount

                // Mouse wheel moves the SELECTION instead of scrolling — the core
                // ergonomics fix. accepted=true prevents the grid from flicking.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function (event) {
                        root.cycleExposeSelection(event.angleDelta.y < 0 ? 1 : -1);
                        event.accepted = true;
                    }
                }

                delegate: Item {
                    id: cell
                    required property int index
                    required property var modelData
                    readonly property var entry: modelData
                    readonly property bool selected: index === root.exposeSelectedIndex
                    readonly property bool focusedWindow: entry && entry.focused === true
                    readonly property color accentColor: root.launcherEntryAccentColor(entry)
                    width: exposeGrid.cellWidth
                    height: exposeGrid.cellHeight

                    // Accent glow behind the tile, kept inside the gutter so a
                    // scaled tile never clips against the GridView edge.
                    Rectangle {
                        anchors.fill: tile
                        anchors.margins: -3
                        radius: 18
                        color: cell.accentColor
                        opacity: cell.selected ? 0.28 : (tileMouse.containsMouse ? 0.14 : 0)
                        Behavior on opacity { NumberAnimation { duration: root.fastColorMs } }
                    }

                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 10
                        radius: 16
                        color: cell.selected ? colors.cardAlt : (tileMouse.containsMouse ? colors.panelAlt : colors.card)
                        border.width: (cell.focusedWindow || cell.selected) ? 2 : 1
                        border.color: cell.focusedWindow ? colors.green
                            : (cell.selected ? cell.accentColor : colors.border)
                        scale: (cell.selected || tileMouse.containsMouse) ? 1.05 : 1.0
                        transformOrigin: Item.Center

                        Behavior on color { ColorAnimation { duration: root.fastColorMs } }
                        Behavior on border.color { ColorAnimation { duration: root.fastColorMs } }
                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8

                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 4
                                implicitSize: 60
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
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }

                            Item { Layout.fillHeight: true }

                            // Workspace + project badges.
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6

                                Rectangle {
                                    visible: metaText.text.length > 0
                                    radius: 6
                                    color: colors.blueWash
                                    border.color: colors.blueMuted
                                    border.width: 1
                                    Layout.preferredHeight: 20
                                    Layout.preferredWidth: metaText.implicitWidth + 14
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
                                    Layout.preferredHeight: 20
                                    Layout.preferredWidth: projText.implicitWidth + 14
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

                        // "current" pill on the focused window.
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
                            onPositionChanged: root.updateExposePointerSelection(cell.index)
                            onEntered: root.updateExposePointerSelection(cell.index)
                            onClicked: function (mouse) {
                                if (mouse.button === Qt.MiddleButton) {
                                    root.closeExposeWindowEntry(cell.entry);
                                    return;
                                }
                                root.updateExposePointerSelection(cell.index);
                                root.activateExposeSelection();
                            }
                        }
                    }
                }
            }
        }

        // Small dictation toggle in the top-right corner — same action as the
        // bottom-bar button and the trackpad gesture. Closes the switcher first
        // so dictation operates on the underlying window, not this overlay.
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
