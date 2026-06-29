import QtQuick
import Quickshell
import Quickshell.Wayland

// Hover tooltip for the bars.
//
// This uses a Quickshell PopupWindow (a real Wayland surface that opens beside
// the bar) instead of a QtQuick.Controls ToolTip. A Controls ToolTip is a
// Popup whose overlay grabs the pointer when it appears, which flips the
// hovered chip's MouseArea.containsMouse on/off — the chip "pulsated as if
// rapidly clicked" and swallowed real clicks. A PopupWindow opens above/below
// the bar and never overlaps the chip, so it cannot steal the chip's hover and
// the oscillation can't happen. It also escapes the thin bar window, which a
// plain inline Rectangle could not (it would be clipped).
PopupWindow {
    id: barTooltip

    // The bar PanelWindow to anchor within, and the hovered chip (or its
    // MouseArea — same geometry) to point at.
    required property var anchorWindow
    required property var anchorItem
    required property string text
    required property bool active
    required property var colors
    // Top bar opens the tooltip below the bar; the bottom bar opens it above.
    property bool above: false
    property int delayMs: 450

    property bool tipShown: false

    visible: tipShown && active && text.length > 0
    color: "transparent"
    implicitWidth: tipCard.implicitWidth
    implicitHeight: tipCard.implicitHeight

    anchor.window: anchorWindow
    anchor.item: anchorItem
    anchor.edges: above ? (Edges.Top | Edges.Left) : (Edges.Bottom | Edges.Left)
    anchor.gravity: above ? (Edges.Top | Edges.Right) : (Edges.Bottom | Edges.Right)
    anchor.margins.top: above ? 0 : 6
    anchor.margins.bottom: above ? 6 : 0

    // Match the old ToolTip delay so it only appears after a short, intentional
    // hover. Resets whenever the hover ends.
    Timer {
        id: tipDelay
        interval: barTooltip.delayMs
        running: barTooltip.active && barTooltip.text.length > 0
        onRunningChanged: if (!running) barTooltip.tipShown = false
        onTriggered: barTooltip.tipShown = true
    }

    Rectangle {
        id: tipCard
        implicitWidth: Math.min(380, tipText.implicitWidth + 16)
        implicitHeight: tipText.implicitHeight + 10
        radius: 6
        color: barTooltip.colors.panel
        border.color: barTooltip.colors.border
        border.width: 1

        Text {
            id: tipText
            anchors.fill: parent
            anchors.margins: 8
            text: barTooltip.text
            color: barTooltip.colors.text
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
