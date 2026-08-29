import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "root:/"

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: notificationDetailWindow
    // notificationDetailItem is a snapshot taken when the detail opened; the
    // feed carries the live closed flag, so resolve it by id. Closed items no
    // longer have a runtime entry and invoking an action would silently no-op.
    readonly property bool detailActionable: {
        const item = root.notificationDetailItem;
        if (!item) {
            return false;
        }
        const feed = root.arrayOrEmpty(root.notificationFeed);
        for (let i = 0; i < feed.length; i += 1) {
            if (Number(feed[i] && feed[i].id) === Number(item.id || 0)) {
                return !root.notificationClosed(feed[i]);
            }
        }
        return !root.notificationClosed(item);
    }
    screen: root.activeScreen
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

    onVisibleChanged: {
        if (visible) {
            detailEnterAnim.restart();
        }
    }

    ParallelAnimation {
        id: detailEnterAnim

        NumberAnimation {
            target: detailScrim
            property: "opacity"
            from: 0
            to: 1
            duration: 180
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: detailCard
            property: "scale"
            from: 0.96
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: detailScrim
        anchors.fill: parent
        color: Theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.hideNotificationDetail()
        }

        Rectangle {
            id: detailCard
            // MultiEffect is shader-based; the software Quick backend (NVIDIA
            // hosts) would render a layered item as nothing at all, so the
            // shadow is gated and those hosts get the 1px dark halo instead.
            readonly property bool shadowCapable: GraphicsInfo.api !== GraphicsInfo.Software
            anchors.centerIn: parent
            width: Math.min(520, parent.width - 80)
            height: Math.min(detailContent.implicitHeight + 40, parent.height - 80)
            radius: root.radiusFloat
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1
            layer.enabled: shadowCapable
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 1.0
                shadowColor: Theme.shadow
                shadowVerticalOffset: 6
                shadowHorizontalOffset: 0
            }

            Rectangle {
                visible: !detailCard.shadowCapable
                anchors.fill: parent
                anchors.margins: -1
                radius: parent.radius + 1
                color: "transparent"
                border.color: Theme.edgeShadow
                border.width: 1
            }

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
                        radius: Theme.rad(12)
                        color: root.notificationDetailItem ? root.notificationAvatarFill(root.notificationDetailItem) : colors.card
                        border.color: Theme.edgeHighlight
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
                                font.family: Theme.fontFamily
                                visible: !parent.children[0].visible
                                anchors.centerIn: parent
                                text: root.notificationDetailItem ? root.notificationAvatarText(root.notificationDetailItem) : ""
                                color: colors.text
                                font.pixelSize: Theme.fs(12)
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            font.family: Theme.fontFamily
                            Layout.fillWidth: true
                            text: {
                                const item = root.notificationDetailItem;
                                if (!item) {
                                    return "";
                                }
                                const relative = root.notificationRelativeTime(item);
                                return root.notificationAppLabel(item) + (relative ? " · " + relative : "");
                            }
                            color: colors.textDim
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            font.family: Theme.fontFamily
                            Layout.fillWidth: true
                            text: root.notificationDetailItem ? root.notificationHeadline(root.notificationDetailItem) : ""
                            color: colors.text
                            font.pixelSize: Theme.fs(14)
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: Theme.rad(10)
                        color: detailCloseMouse.containsMouse ? colors.redBg : Theme.elevationFaint
                        border.color: Theme.elevation
                        border.width: 1

                        Text {
                            font.family: Theme.fontFamily
                            anchors.centerIn: parent
                            text: "×"
                            color: detailCloseMouse.containsMouse ? colors.red : colors.subtle
                            font.pixelSize: Theme.fs(12)
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
                        font.pixelSize: Theme.fs(12)
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
                        radius: Theme.rad(10)
                        color: copyMouse.containsMouse ? colors.blueBg : colors.card
                        border.color: copyMouse.containsMouse ? colors.blue : colors.border
                        border.width: 1

                        Text {
                            font.family: Theme.fontFamily
                            id: copyLabel
                            anchors.centerIn: parent
                            text: "Copy"
                            color: copyMouse.containsMouse ? colors.blue : colors.text
                            font.pixelSize: Theme.fs(10)
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
                            radius: Theme.rad(10)
                            opacity: notificationDetailWindow.detailActionable ? 1 : 0.4
                            color: detailActionMouse.containsMouse ? colors.tealBg : colors.card
                            border.color: detailActionMouse.containsMouse ? colors.teal : colors.border
                            border.width: 1

                            Text {
                                font.family: Theme.fontFamily
                                id: detailActionLabel
                                anchors.centerIn: parent
                                text: root.notificationActionText(modelData)
                                color: detailActionMouse.containsMouse ? colors.teal : colors.text
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: detailActionMouse
                                anchors.fill: parent
                                enabled: notificationDetailWindow.detailActionable
                                hoverEnabled: notificationDetailWindow.detailActionable
                                cursorShape: notificationDetailWindow.detailActionable ? Qt.PointingHandCursor : Qt.ArrowCursor
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
