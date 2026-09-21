import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Why an agent session is showing the verdict it is showing, on hover.
//
// This replaced a drawer docked under the agent list, which was the wrong
// shape twice over: the herdr section hand-computes its own height
// reservations, so a drawer it does not know about gets pushed past the
// bottom of the panel; and a detail that has to be opened and then closed is
// state the reader has to manage while scanning a list.
//
// Hover has neither problem. There is nothing to dismiss, nothing moves, and
// which row the detail belongs to is unambiguous by construction — it is the
// one under the pointer.
//
// A PopupWindow rather than an inline Rectangle for the same two reasons
// BarTooltip is one: it is a real Wayland surface, so it escapes the panel's
// clipping and the ListView's, and it opens beside the row rather than over
// it, so it cannot steal the hover that summoned it and oscillate.
PopupWindow {
    id: tip

    required property var anchorWindow
    required property var anchorItem
    required property var colors
    required property var rootObject
    required property var session
    required property bool active

    // Long enough that sweeping down the list does not strobe, short enough
    // that stopping on a row feels like it answered.
    property int delayMs: 380

    property bool tipShown: false

    readonly property var verdict: rootObject ? rootObject.sessionJudgement(session) : null
    readonly property bool hasVerdict: verdict !== null && verdict !== undefined

    visible: tipShown && active && hasVerdict
    color: "transparent"
    implicitWidth: card.implicitWidth + 2
    implicitHeight: card.implicitHeight + 2

    // Reset on the hover ending, NOT on the delay timer's `running` going
    // false. A non-repeating Timer clears its own `running` the moment it
    // fires, so keying the reset to that cancels the tooltip in the same frame
    // it was shown — it appeared and vanished with nothing in between.
    onActiveChanged: if (!active) tipShown = false
    onHasVerdictChanged: if (!hasVerdict) tipShown = false

    onVisibleChanged: {
        if (visible) {
            enterAnim.restart();
        } else {
            enterAnim.stop();
        }
    }

    // The panel lives on the right edge of the screen, so the tooltip opens
    // leftward into the desktop rather than off the side of it.
    anchor.window: anchorWindow
    anchor.item: anchorItem
    // Fixed edges. A flip-upward for rows low in the panel was tried and
    // reverted: it stopped the tooltip appearing at all, and the overflow case
    // it guarded against was never actually observed. Unverified complexity
    // that breaks the verified path is a bad trade.
    anchor.edges: Edges.Left | Edges.Top
    anchor.gravity: Edges.Left | Edges.Bottom
    anchor.margins.right: 8

    Timer {
        interval: tip.delayMs
        repeat: false
        running: tip.active && tip.hasVerdict && !tip.tipShown
        onTriggered: tip.tipShown = true
    }

    Rectangle {
        id: card
        x: 1
        y: 1
        implicitWidth: 380
        implicitHeight: Math.min(360, body.implicitHeight + 18)
        radius: Theme.rad(8)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.panelAlt }
            GradientStop { position: 1.0; color: Theme.bg }
        }
        border.color: tip.colors.border
        border.width: 1

        // Pre-rendered depth, as BarTooltip does: a MultiEffect shadow needs
        // inset room, and growing the window back toward the row would
        // overlap it.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: parent.radius + 1
            color: "transparent"
            border.color: Theme.edgeShadow
            border.width: 1
        }

        ParallelAnimation {
            id: enterAnim
            NumberAnimation {
                target: card; property: "opacity"
                from: 0; to: 1; duration: 130; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: card; property: "x"
                from: 5; to: 1; duration: 130; easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 9
            spacing: 4

            // ---- what it wants, and how sure ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                Text {
                    font.family: Theme.glyphFamily
                    font.pixelSize: Theme.fs(12)
                    text: tip.rootObject.sessionAlarmGlyph(tip.session).length > 0
                        ? tip.rootObject.sessionAlarmGlyph(tip.session)
                        : tip.rootObject.sessionAskGlyph(tip.session)
                    color: tip.rootObject.sessionAlarmGlyph(tip.session).length > 0
                        ? tip.rootObject.sessionAlarmColor(tip.session)
                        : tip.colors.blue
                }

                Text {
                    Layout.fillWidth: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.DemiBold
                    text: tip.hasVerdict
                        ? (tip.rootObject.stringOrEmpty(tip.verdict.lede) || tip.verdict.ask_kind)
                        : ""
                    color: tip.rootObject.sessionAlarmGlyph(tip.session).length > 0
                        ? tip.rootObject.sessionAlarmColor(tip.session)
                        : tip.colors.text
                    elide: Text.ElideRight
                }
            }

            // ---- how it is going ----
            // The headline the whole battery exists to produce: not what this
            // session wants, but whether it is getting anywhere.
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fs(9)
                text: tip.rootObject.judgementHealthLine(tip.session)
                color: tip.rootObject.sessionCondition(tip.session) === "struggling"
                    ? tip.colors.amber
                    : tip.colors.textDim
                elide: Text.ElideRight
            }

            Repeater {
                model: tip.active ? tip.rootObject.judgementScoreRows(tip.session) : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 7

                    Rectangle {
                        implicitWidth: 68
                        implicitHeight: 4
                        radius: 2
                        color: tip.colors.lineSoft

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, modelData.fraction))
                            height: parent.height
                            radius: parent.radius
                            // The bottom of either scale is the bad end, so the
                            // bar itself carries the warning.
                            color: modelData.fraction < 0.4 ? tip.colors.amber : tip.colors.green
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fs(9)
                        text: modelData.label + "  (" + modelData.name + " "
                            + modelData.value.toFixed(1) + "/" + modelData.span
                            + ", conf " + modelData.confidence.toFixed(2) + ")"
                        color: tip.colors.textDim
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- the trajectory ----
            // One observation cannot show a trend, so the series is drawn.
            // This is the difference between "it is struggling now" and "it
            // has been sliding for twenty minutes".
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: tip.active && tip.rootObject.judgementHealthSeries(tip.session).length > 1
                spacing: 2

                Text {
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(8)
                    text: "health"
                    color: tip.colors.subtle
                }

                Row {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: tip.active ? tip.rootObject.judgementHealthSeries(tip.session) : []

                        delegate: Rectangle {
                            required property var modelData
                            width: 5
                            height: Math.max(2, Math.round(18 * Math.max(0, Math.min(1, modelData))))
                            y: 18 - height
                            radius: 1
                            color: modelData < 0.45 ? tip.colors.amber : tip.colors.green
                            opacity: 0.85
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fs(9)
                text: tip.rootObject.judgementCostLine(tip.session)
                color: tip.colors.subtle
                elide: Text.ElideRight
            }

            // ---- the runners-up, which are what make a number checkable ----
            Repeater {
                model: tip.active ? tip.rootObject.judgementAskRanking(tip.session) : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 7

                    Rectangle {
                        implicitWidth: 68
                        implicitHeight: 4
                        radius: 2
                        color: tip.colors.lineSoft

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, modelData.probability))
                            height: parent.height
                            radius: parent.radius
                            color: tip.colors.blueMuted
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fs(9)
                        text: modelData.probability.toFixed(2) + "  " + modelData.option
                        color: tip.colors.textDim
                        elide: Text.ElideRight
                    }
                }
            }

            Repeater {
                model: tip.active ? tip.rootObject.judgementFlagRows(tip.session) : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 7

                    Rectangle {
                        implicitWidth: 68
                        implicitHeight: 4
                        radius: 2
                        color: tip.colors.lineSoft

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, modelData.probability))
                            height: parent.height
                            radius: parent.radius
                            color: modelData.raised ? tip.colors.amber : tip.colors.subtle
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fs(9)
                        text: modelData.probability.toFixed(2) + "  " + modelData.name
                        color: modelData.raised ? tip.colors.amber : tip.colors.subtle
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- the line it was pointed at ----
            // The tooltip shows the one line rather than the whole screen: a
            // hover panel tall enough for fifteen lines covers the list it is
            // describing. `agent-judge explain` prints all of it.
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 3
                visible: text.length > 0
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fs(9)
                text: tip.rootObject.sessionJudgementEvidence(tip.session)
                color: tip.colors.text
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(8)
                text: "agent-judge explain " + (tip.hasVerdict ? tip.rootObject.stringOrEmpty(tip.verdict.key) : "")
                color: tip.colors.subtle
                elide: Text.ElideRight
            }
        }
    }
}
