import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: notificationDetailWindow
    screen: root.primaryScreen
    visible: root.notificationDetailVisible && root.notificationDetailItem !== null && root.primaryScreen !== null
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-notification-detail"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
        anchors.fill: parent
        color: "#66070b12"

        MouseArea {
            anchors.fill: parent
            onClicked: root.hideNotificationDetail()
        }

        Rectangle {
            id: detailCard
            anchors.centerIn: parent
            width: Math.min(520, parent.width - 80)
            height: Math.min(detailContent.implicitHeight + 40, parent.height - 80)
            radius: 14
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            MouseArea {
                anchors.fill: parent
                onClicked: function (mouse) {
                    mouse.accepted = true;
                }
            }

            ColumnLayout {
                id: detailContent
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                focus: true

                Keys.onPressed: function (event) {
                    if (event.key === Qt.Key_Escape) {
                        root.hideNotificationDetail();
                        event.accepted = true;
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 12
                        color: root.notificationDetailItem ? root.notificationAvatarFill(root.notificationDetailItem) : colors.card
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        Item {
                            anchors.fill: parent

                            IconImage {
                                visible: root.notificationDetailItem ? root.notificationResolvedIcon(root.notificationDetailItem) !== "" : false
                                anchors.centerIn: parent
                                implicitSize: 20
                                source: root.notificationDetailItem ? root.notificationResolvedIcon(root.notificationDetailItem) : ""
                                mipmap: true
                            }

                            Text {
                                visible: !parent.children[0].visible
                                anchors.centerIn: parent
                                text: root.notificationDetailItem ? root.notificationAvatarText(root.notificationDetailItem) : ""
                                color: colors.text
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: root.notificationDetailItem ? root.notificationAppLabel(root.notificationDetailItem) : ""
                            color: colors.textDim
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.notificationDetailItem ? root.notificationHeadline(root.notificationDetailItem) : ""
                            color: colors.text
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 10
                        color: detailCloseMouse.containsMouse ? colors.redBg : Qt.rgba(1, 1, 1, 0.03)
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: detailCloseMouse.containsMouse ? colors.red : colors.subtle
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: detailCloseMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.hideNotificationDetail()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: colors.lineSoft
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    Layout.maximumHeight: 400
                    clip: true

                    TextArea {
                        id: detailBodyText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: root.notificationDetailItem ? root.notificationBody(root.notificationDetailItem) : ""
                        color: colors.textDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        background: null
                        leftPadding: 0
                        rightPadding: 0
                        topPadding: 0
                        bottomPadding: 0
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: copyLabel.implicitWidth + 24
                        radius: 10
                        color: copyMouse.containsMouse ? colors.blueBg : colors.card
                        border.color: copyMouse.containsMouse ? colors.blue : colors.border
                        border.width: 1

                        Text {
                            id: copyLabel
                            anchors.centerIn: parent
                            text: "Copy"
                            color: copyMouse.containsMouse ? colors.blue : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: copyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                detailCopyProcess.command = ["wl-copy", "--type", "text/plain", root.notificationDetailItem ? root.notificationBody(root.notificationDetailItem) : ""];
                                detailCopyProcess.running = true;
                            }
                        }
                    }

                    Repeater {
                        model: {
                            var actions = root.notificationDetailItem ? root.arrayOrEmpty(root.notificationDetailItem.actions) : [];
                            return actions.filter(function (a) {
                                var id = root.notificationActionIdentifier(a).toLowerCase();
                                var text = root.notificationActionText(a).toLowerCase();
                                return id !== "copy" && text !== "copy";
                            });
                        }

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: detailActionLabel.implicitWidth + 24
                            radius: 10
                            color: detailActionMouse.containsMouse ? colors.tealBg : colors.card
                            border.color: detailActionMouse.containsMouse ? colors.teal : colors.border
                            border.width: 1

                            Text {
                                id: detailActionLabel
                                anchors.centerIn: parent
                                text: root.notificationActionText(modelData)
                                color: detailActionMouse.containsMouse ? colors.teal : colors.text
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: detailActionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var itemId = root.notificationDetailItem ? Number(root.notificationDetailItem.id || 0) : 0;
                                    root.invokeNotificationAction(itemId, root.notificationActionIdentifier(modelData));
                                    root.hideNotificationDetail();
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    Process {
        id: detailCopyProcess
        command: ["wl-copy", "--type", "text/plain", ""]
        running: false
    }
}
