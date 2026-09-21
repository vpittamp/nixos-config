import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import "root:/"

// The natural-language command bar: one line of text (typed or spoken) goes to
// `jev`, which routes it to one of this desktop's own commands and fills that
// command's arguments from closed sets (home-modules/desktop/jev-commands).
//
// Three things this window is careful about:
//
//   Confidence is shown, not hidden. A call the dispatcher is sure of runs on
//   Enter and the bar reports what it did; a shaky one stops and shows the
//   resolved call, so the decision to run it is the user's. Nothing about
//   "0.62" is meaningful without the runner-up, which is what debug mode is
//   for.
//
//   Voice does not type. While dictation is armed the field is read-only and
//   mirrors voxtype's transcript file instead — voxtype types into whatever
//   holds keyboard focus, which is this window, and a read-only field is what
//   keeps the spoken words from arriving twice.
//
//   Debug mode re-plans as you type (plan never executes anything), so the
//   routing distribution moves while a sentence is being written. That is the
//   only way to see *why* a phrasing lands where it does.
PanelWindow {
    id: commandBar
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    property alias commandFieldRef: commandField

    readonly property bool thinking: root.commandStatus === "thinking"
    readonly property var plan: root.commandPlan
    readonly property bool hasPlan: plan !== null && plan !== undefined
    readonly property bool awaitingConfirmation: hasPlan && root.stringOrEmpty(plan.status) === "confirm"
    readonly property bool listening: root.commandVoice && root.voxtypeListening()

    screen: root.activeScreen
    visible: root.commandBarVisible
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-command-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // The mic and reasoning toggles. An inline component rather than a
    // Repeater over an array literal: the array would be rebuilt — and both
    // delegates destroyed and recreated — every time either chip flips.
    //
    // Everything it needs is passed in. An inline component is its own type and
    // cannot see the ids of the document around it, so reaching for
    // `commandBar.colors` here would resolve to nothing at runtime.
    component ChipButton: Rectangle {
        id: chip
        required property var palette
        property string glyph: ""
        property bool on: false
        property color accent: chip.palette.blue
        property bool large: false
        property bool hovered: false
        signal pressed()

        implicitWidth: chip.large ? 40 : 32
        implicitHeight: chip.large ? 40 : 32
        radius: Theme.rad(8)
        color: chip.on
            ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.16)
            : (chip.hovered ? chip.palette.cardAlt : "transparent")
        border.width: 1
        border.color: chip.on ? chip.accent : chip.palette.border

        Text {
            anchors.centerIn: parent
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(14)
            text: chip.glyph
            color: chip.on ? chip.accent : chip.palette.muted
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: chip.hovered = true
            onExited: chip.hovered = false
            onClicked: chip.pressed()
        }
    }

    function confidenceColor(value) {
        if (value >= root.commandAutoThreshold) {
            return colors.green;
        }
        return value >= 0.4 ? colors.amber : colors.red;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeCommandBar()
        }

        Rectangle {
            id: card
            readonly property int oskReserve: root.oskVisible ? 260 : 0
            anchors.horizontalCenter: parent.horizontalCenter
            // Sat near the top rather than centred: the bar is a thing you
            // reach past, and the result it prints should not cover the window
            // the command is about.
            y: Math.max(24, Math.round((parent.height - oskReserve) * 0.12))
            width: Math.min(820, parent.width - 96)
            height: layout.implicitHeight + 32
            radius: Theme.rad(12)
            color: colors.panel
            border.color: listening ? colors.red : colors.borderStrong
            border.width: 1

            Behavior on height {
                NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: function (mouse) { mouse.accepted = true; }
            }

            ColumnLayout {
                id: layout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 10

                // ---- the input row ----------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        font.family: Theme.glyphFamily
                        font.pixelSize: Theme.fs(18)
                        // A microphone while dictating, an hourglass while the
                        // dispatcher is out, a prompt otherwise.
                        text: listening ? "" : (thinking ? "" : "")
                        color: listening ? colors.red : (thinking ? colors.amber : colors.blue)
                    }

                    TextField {
                        id: commandField
                        Layout.fillWidth: true
                        focus: root.commandBarVisible
                        // Voice writes through the transcript mirror, never
                        // through the keyboard: voxtype's synthetic keystrokes
                        // land here too, and read-only is what drops them.
                        readOnly: root.commandVoice
                        placeholderText: listening
                            ? "listening…"
                            : (root.commandVoice ? "press the mic, or Ctrl+Space, and speak" : "what do you want the desktop to do?")
                        color: colors.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(18)
                        // No `text:` binding on purpose. The first keystroke
                        // would break it, and then the voice transcript — which
                        // arrives by assignment — would stop reaching the field.
                        // shellRoot.setCommandText writes here directly, the way
                        // the launcher's query field is driven.

                        TapHandler {
                            acceptedDevices: PointerDevice.TouchScreen
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: root.oskFieldTouched()
                        }

                        background: Rectangle {
                            radius: Theme.rad(8)
                            color: colors.cardAlt
                            border.color: commandField.activeFocus ? colors.blue : colors.border
                            border.width: 1
                        }

                        leftPadding: 14
                        rightPadding: 14
                        topPadding: 12
                        bottomPadding: 12

                        onTextChanged: {
                            if (!root.commandNormalizing) {
                                root.updateCommandInput(text);
                            }
                        }

                        Keys.onPressed: function (event) {
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_D) {
                                root.toggleCommandDebug();
                                event.accepted = true;
                                return;
                            }
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Space) {
                                root.toggleCommandVoice();
                                event.accepted = true;
                                return;
                            }
                            switch (event.key) {
                            case Qt.Key_Escape:
                                root.escapeCommandBar();
                                event.accepted = true;
                                return;
                            case Qt.Key_Return:
                            case Qt.Key_Enter:
                                root.submitCommandBar();
                                event.accepted = true;
                                return;
                            }
                        }
                    }

                    ChipButton {
                        palette: colors
                        large: root.touchModeActive
                        glyph: ""
                        on: root.commandVoice
                        accent: colors.red
                        onPressed: root.toggleCommandVoice()
                    }

                    ChipButton {
                        palette: colors
                        large: root.touchModeActive
                        glyph: ""
                        on: root.commandDebug
                        accent: colors.violet
                        onPressed: root.toggleCommandDebug()
                    }
                }

                // ---- live capture meter, only while the mic is open --------
                Row {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    visible: listening
                    spacing: 3

                    Repeater {
                        model: 40

                        delegate: Rectangle {
                            required property int index
                            // Bell-weighted around the centre and driven by the
                            // live input level, so silence is visibly silence —
                            // a dictation that hears nothing is the failure
                            // this meter exists to make obvious.
                            readonly property real weight: 1.0 - 0.55 * Math.abs(index - 19.5) / 19.5
                            width: 4
                            radius: 2
                            height: Math.max(3, 14 * Math.min(1, (root.dictationLevel / 100) * weight))
                            anchors.verticalCenter: parent.verticalCenter
                            color: colors.red
                            opacity: 0.35 + 0.65 * (root.dictationLevel / 100)

                            Behavior on height {
                                NumberAnimation { duration: 70 }
                            }
                        }
                    }
                }

                // ---- what happened ----------------------------------------
                Text {
                    Layout.fillWidth: true
                    visible: root.commandError !== ""
                    text: root.commandError
                    color: colors.red
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                }

                Text {
                    Layout.fillWidth: true
                    visible: thinking
                    text: "asking jev…"
                    color: colors.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: verdict.implicitHeight + 20
                    visible: hasPlan && !thinking
                    radius: Theme.rad(8)
                    color: colors.cardAlt
                    border.width: 1
                    border.color: awaitingConfirmation ? colors.amber : colors.border

                    ColumnLayout {
                        id: verdict
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                Layout.fillWidth: true
                                text: root.commandVerdictLine()
                                color: colors.text
                                elide: Text.ElideRight
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fs(13)
                            }

                            // The confidence as a number *and* as a bar: the bar
                            // is read at a glance, the number is what the gate
                            // actually compares.
                            Rectangle {
                                implicitWidth: 64
                                implicitHeight: 6
                                radius: 3
                                color: colors.lineSoft

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, root.commandConfidence()))
                                    height: parent.height
                                    radius: parent.radius
                                    color: confidenceColor(root.commandConfidence())
                                }
                            }

                            Text {
                                text: root.commandConfidence().toFixed(2)
                                color: confidenceColor(root.commandConfidence())
                                font.family: Theme.monoFamily
                                font.pixelSize: Theme.fs(12)
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.commandHintLine()
                            color: awaitingConfirmation ? colors.amber : colors.muted
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                        }
                    }
                }

                // ---- debug: the whole judgement ----------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: debugColumn.implicitHeight + 20
                    visible: root.commandDebug && hasPlan
                    radius: Theme.rad(8)
                    color: Theme.elevationSoft
                    border.width: 1
                    border.color: Qt.rgba(colors.violet.r, colors.violet.g, colors.violet.b, 0.35)

                    ColumnLayout {
                        id: debugColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            text: root.commandTraceCostLine()
                            color: colors.violet
                            font.family: Theme.monoFamily
                            font.pixelSize: Theme.fs(10)
                        }

                        Text {
                            text: "which action"
                            color: colors.subtle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.commandCandidates()

                            delegate: RowLayout {
                                required property var modelData
                                readonly property bool picked: modelData.function === root.stringOrEmpty(plan && plan.function)
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    implicitWidth: 90
                                    implicitHeight: 5
                                    radius: 2
                                    color: colors.lineSoft

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1, modelData.probability))
                                        height: parent.height
                                        radius: parent.radius
                                        color: picked ? colors.violet : colors.blueMuted
                                    }
                                }

                                Text {
                                    text: modelData.probability.toFixed(2)
                                    color: picked ? colors.text : colors.muted
                                    font.family: Theme.monoFamily
                                    font.pixelSize: Theme.fs(10)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.function + "  —  " + root.stringOrEmpty(modelData.summary)
                                    color: picked ? colors.text : colors.subtle
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                }
                            }
                        }

                        Text {
                            visible: root.commandArguments().length > 0
                            text: "and its arguments"
                            color: colors.subtle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.commandArguments()

                            delegate: ColumnLayout {
                                required property var modelData
                                // Named, because the nested Repeater's own
                                // delegate declares a `modelData` of its own
                                // and reading the outer one through a shadow
                                // is a bug waiting for an edit.
                                readonly property var argument: modelData
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: root.commandArgumentLine(argument)
                                    color: argument.omitted ? colors.subtle : colors.textDim
                                    elide: Text.ElideRight
                                    font.family: Theme.monoFamily
                                    font.pixelSize: Theme.fs(10)
                                }

                                Repeater {
                                    model: root.commandArgumentOptions(argument)

                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 14
                                        spacing: 8

                                        Rectangle {
                                            implicitWidth: 60
                                            implicitHeight: 4
                                            radius: 2
                                            color: colors.lineSoft

                                            Rectangle {
                                                width: parent.width * Math.max(0, Math.min(1, modelData.probability))
                                                height: parent.height
                                                radius: parent.radius
                                                color: colors.teal
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.probability.toFixed(2) + "  " + modelData.option
                                            color: colors.subtle
                                            elide: Text.ElideRight
                                            font.family: Theme.monoFamily
                                            font.pixelSize: Theme.fs(10)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- key legend -------------------------------------------
                Text {
                    Layout.fillWidth: true
                    text: root.commandLegendLine()
                    color: colors.subtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                }
            }
        }
    }
}
