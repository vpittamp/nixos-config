import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property bool isActive: false
    property string statusText: "Off"

    // Check status every second
    Timer {
        id: statusTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: checkStatus()
    }

    function checkStatus() {
        executable.exec("pgrep -fc '\\.nerd-dictation-wrapped begin'")
    }

    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            var count = parseInt(data["stdout"]) || 0
            root.isActive = count > 0
            root.statusText = root.isActive ? "Recording" : "Off"
            disconnectSource(source)
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Tooltip
    toolTipMainText: "Speech-to-Text"
    toolTipSubText: statusText

    // Compact representation (system tray)
    compactRepresentation: Item {
        Layout.fillWidth: false
        Layout.fillHeight: false
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small

        Kirigami.Icon {
            id: icon
            anchors.fill: parent
            source: root.isActive ? "audio-input-microphone" : "microphone-sensitivity-muted"

            // Pulse animation when active
            SequentialAnimation on opacity {
                running: root.isActive
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.5; duration: 800 }
                NumberAnimation { from: 0.5; to: 1.0; duration: 800 }
            }

            // Color overlay for active state
            ColorOverlay {
                anchors.fill: parent
                source: icon
                color: root.isActive ? "#ff4444" : "transparent"
                opacity: root.isActive ? 0.3 : 0
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                executable.exec("/run/current-system/sw/bin/nerd-dictation-toggle")
            }
        }
    }

    // Full representation (when expanded)
    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        Layout.preferredHeight: Kirigami.Units.gridUnit * 8

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                source: root.isActive ? "audio-input-microphone" : "microphone-sensitivity-muted"
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.statusText
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.5
                font.bold: true
                color: root.isActive ? "#ff4444" : Kirigami.Theme.textColor
            }

            PlasmaComponents.Button {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                text: root.isActive ? "Stop Dictation" : "Start Dictation"
                icon.name: root.isActive ? "media-playback-stop" : "media-playback-start"
                onClicked: {
                    executable.exec("/run/current-system/sw/bin/nerd-dictation-toggle")
                }
            }

            Item {
                Layout.fillHeight: true
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Shortcut: Meta+Shift+Space"
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                opacity: 0.7
            }
        }
    }

    Component.onCompleted: {
        checkStatus()
    }
}
