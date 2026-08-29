import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "root:/"

// Transient on-screen display for volume, microphone, brightness and display
// scale changes. Sits bottom-centre of the output that had focus when the
// change happened, above the bottom bar, for ~1.4s and then fades. All state
// comes from shellRoot.osd* (set by showOsd()); the window itself is inert —
// no keyboard focus, no exclusive zone — and masked to the pill so the
// transparent rest of the window never swallows a click.
PanelWindow {
    id: osd
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot

    readonly property string kind: root.osdKind
    readonly property int level: Math.max(0, Math.min(100, Math.round(root.osdLevel)))
    readonly property bool muted: root.osdMuted
    readonly property color accent: muted ? colors.subtle
        : kind === "brightness" ? colors.amber
        : kind === "mic" ? colors.teal
        : kind === "scale" ? colors.violet
        : colors.blue

    function glyph() {
        if (kind === "mic") {
            return muted ? "󰍭" : "󰍬"; // 󰍭 / 󰍬
        }
        if (kind === "brightness") {
            return "󰃟"; // 󰃟
        }
        if (kind === "scale") {
            return "󰍹"; // 󰍹
        }
        if (muted || level === 0) {
            return "󰖁"; // 󰖁
        }
        return level < 40 ? "󰕿" : "󰕾"; // 󰕿 / 󰕾
    }

    function label() {
        if (kind === "mic") {
            return muted ? "Microphone muted" : "Microphone " + level + "%";
        }
        if (kind === "brightness") {
            return "Brightness " + level + "%";
        }
        if (kind === "scale") {
            return root.osdText || ("Scale " + level + "%");
        }
        return muted ? "Muted" : "Volume " + level + "%";
    }

    screen: root.osdScreen
    visible: root.osdVisible
    color: "transparent"
    anchors.bottom: true
    margins.bottom: runtimeConfig.barHeight + 28
    implicitWidth: 340
    implicitHeight: 64
    exclusiveZone: 0
    focusable: false
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: pill }

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: 16
        color: colors.toastGlass
        border.color: colors.border
        border.width: 1
        opacity: root.osdVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: 14

            Text {
                text: osd.glyph()
                color: osd.accent
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 24
                Layout.preferredWidth: 28
                horizontalAlignment: Text.AlignHCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 7

                Text {
                    text: osd.label()
                    color: colors.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 5
                    radius: 3
                    color: colors.elevationStrong

                    Rectangle {
                        width: parent.width * (osd.muted ? 0 : osd.level / 100)
                        height: parent.height
                        radius: parent.radius
                        color: osd.accent
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                }
            }

            Text {
                text: osd.muted ? "--" : String(osd.level)
                color: colors.muted
                font.pixelSize: 12
                font.family: "FiraCode Nerd Font"
                Layout.preferredWidth: 26
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
