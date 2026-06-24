import QtQuick
import Quickshell
import Quickshell.Wayland

// Prominent on-screen dictation feedback. Appears only while voxtype is
// recording or transcribing, on the active monitor (clamshell-correct). While
// recording it shows a LIVE input-level meter driven by shellRoot.dictationLevel
// so you can see the mic is actually hearing speech — bars jump when you talk,
// sit flat on silence. If recording stays silent it surfaces a "no audio" hint,
// which is the real reliability failure mode (wrong/muted mic).
PanelWindow {
    id: overlay
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot

    readonly property string vclass: root.voxtypeClass()
    readonly property bool recording: vclass === "recording"
    readonly property bool transcribing: vclass === "transcribing"
    readonly property color accent: recording ? colors.red : colors.amber

    readonly property int barCount: 21
    readonly property real minBar: 4
    readonly property real maxBar: 46
    property real phase: 0
    property real lowMs: 0
    readonly property bool noAudio: recording && lowMs > 2500

    screen: root.activeScreen
    visible: root.voxtypeActive()
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    implicitHeight: 120
    exclusiveZone: 0
    focusable: false
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-dictation-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The overlay window is full-width (so the pill is easy to centre), but only
    // the pill itself should be interactive — restrict the input mask to the pill
    // so everything else (the bar tabs / windows below the transparent area)
    // stays clickable. (An *empty* Region suppresses rendering, so we mask to the
    // pill rather than to nothing.)
    mask: Region { item: pill }

    // Per-bar height: bell-weighted (taller in the centre) and scaled by the live
    // level, with a small level-proportional shimmer so speech looks organic.
    // Transcribing has no live audio, so it shows a travelling sweep instead.
    function barHeight(i) {
        const center = (barCount - 1) / 2;
        const dist = Math.abs(i - center) / center;
        const weight = 1.0 - 0.6 * dist;
        if (transcribing) {
            const sweep = 0.5 + 0.5 * Math.sin(phase * 0.6 + i * 0.7);
            return minBar + sweep * (maxBar - minBar) * 0.55;
        }
        const lvl = root.dictationLevel / 100;
        const shimmer = lvl * (0.18 + 0.18 * Math.sin(phase * 0.5 + i * 0.9));
        const dyn = Math.max(0, lvl * weight + shimmer);
        return minBar + Math.min(1, dyn) * (maxBar - minBar);
    }

    // Animate the meter and track sustained silence for the no-audio hint.
    Timer {
        interval: 55
        repeat: true
        running: overlay.visible
        onTriggered: {
            overlay.phase += 1;
            if (overlay.recording) {
                overlay.lowMs = root.dictationLevel < 6 ? overlay.lowMs + interval : 0;
            } else {
                overlay.lowMs = 0;
            }
        }
    }

    // Centred pill, floating above the bottom bar.
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: runtimeConfig.barHeight + 16
        height: 64
        width: contentRow.implicitWidth + 36
        radius: 16
        color: Qt.rgba(0.05, 0.07, 0.09, 0.93)
        border.width: 1.5
        border.color: overlay.accent
        opacity: overlay.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        // Soft accent glow ring.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 2
            border.color: overlay.accent
            opacity: 0.18
            z: -1
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 14

            // State icon (mic / hourglass), pulsing while recording.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.voxtypeIcon()
                color: overlay.accent
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 22
                SequentialAnimation on opacity {
                    running: overlay.recording
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { from: 1.0; to: 0.35; duration: 600 }
                    NumberAnimation { from: 0.35; to: 1.0; duration: 600 }
                }
            }

            // Live level meter.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater {
                    model: overlay.barCount
                    delegate: Rectangle {
                        width: 4
                        radius: 2
                        height: overlay.barHeight(index)
                        anchors.verticalCenter: parent.verticalCenter
                        color: overlay.noAudio ? colors.muted : overlay.accent
                        opacity: overlay.transcribing ? 0.85
                            : (0.45 + 0.55 * Math.min(1, root.dictationLevel / 60))
                        Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }

            // Status / hint text.
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: overlay.recording ? "Listening…"
                        : (overlay.transcribing ? "Transcribing…" : "")
                    color: colors.text
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: overlay.noAudio
                    text: "No audio — check mic"
                    color: colors.amber
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }
            }
        }
    }
}
