import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot

    id: overlay
    visible: root.moonlightFullscreen
    color: "transparent"

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 32

    WlrLayershell.namespace: "i3pm-moonlight-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Pill button centered at top edge
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        width: pillRow.implicitWidth + 24
        height: 24
        radius: 12
        color: pillMouse.containsMouse ? colors.cardAlt : colors.bg
        border.color: pillMouse.containsMouse ? colors.blue : colors.border
        border.width: 1
        opacity: pillMouse.containsMouse ? 0.95 : 0.6

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "\uf066"
                color: pillMouse.containsMouse ? colors.blue : colors.muted
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "Exit Fullscreen"
                color: pillMouse.containsMouse ? colors.text : colors.muted
                font.pixelSize: 10
                font.weight: Font.DemiBold

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                exitFullscreenProc.running = true;
            }
        }
    }

    Process {
        id: exitFullscreenProc
        command: ["swaymsg", "[app_id=com.moonlight_stream.Moonlight]", "fullscreen", "disable"]
    }
}
