import QtQuick

// Omarchy's slider: a thin track with a foreground fill and no handle on
// text-style themes (a small one on chip-style). Drag, click, or scroll;
// `moved()` fires after `value` changes, so handlers can read `value`.
Item {
    id: slider
    property real from: 0
    property real to: 100
    property real value: 0
    property real step: 1
    property color trackColor: Theme.elevationStrong
    property color fillColor: Theme.textChips ? Theme.text : Theme.blue
    signal moved()

    implicitHeight: Theme.fs(18)
    readonly property real progress: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    function setFromX(x) {
        const ratio = Math.max(0, Math.min(1, x / width));
        let next = from + ratio * (to - from);
        if (step > 0) {
            next = Math.round(next / step) * step;
        }
        value = Math.max(from, Math.min(to, next));
        moved();
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: 4
        radius: 2
        color: slider.trackColor
    }

    Rectangle {
        anchors.verticalCenter: track.verticalCenter
        anchors.left: track.left
        width: track.width * slider.progress
        height: track.height
        radius: track.radius
        color: slider.fillColor
    }

    Rectangle {
        visible: !Theme.textChips
        width: Theme.fs(10)
        height: width
        radius: width / 2
        anchors.verticalCenter: track.verticalCenter
        x: Math.max(0, Math.min(track.width - width, track.width * slider.progress - width / 2))
        color: slider.fillColor
        border.color: Theme.panel
        border.width: 1
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: function (mouse) { slider.setFromX(mouse.x); }
        onPositionChanged: function (mouse) { if (pressed) slider.setFromX(mouse.x); }
        onWheel: function (wheel) {
            const delta = (wheel.angleDelta.y > 0 ? 1 : -1) * Math.max(slider.step, (slider.to - slider.from) / 20);
            slider.value = Math.max(slider.from, Math.min(slider.to, slider.value + delta));
            slider.moved();
        }
    }
}
