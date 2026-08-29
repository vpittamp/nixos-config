import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

// A notification card in the runtime-panel center. Deliberately the same
// anatomy as NotificationToast — icon + APP caps + relative time header,
// headline/body, right-side thumbnail, action pills — so a notification looks
// like the same object whether it is floating on the desktop or resting in
// history. When it fronts a collapsed app group (stackCount > 0) it renders
// iOS-stack style: card edges peeking out below, and clicking expands the
// group instead of opening the detail view.
Item {
    id: card

    required property var rootObject
    required property var colorsObject
    required property var itemData
    property int stackCount: 0

    signal dismissRequested(int notificationId)
    signal actionInvoked(int notificationId, string actionId)
    signal markReadRequested(int notificationId)
    signal detailRequested(int notificationId)
    signal expandRequested()

    readonly property int notificationId: Number(itemData && itemData.id || 0)
    readonly property bool critical: rootObject.notificationIsCritical(itemData)
    // Closed notifications no longer have a runtime entry, so invoking an
    // action would be a silent no-op — render the button inert instead.
    readonly property bool actionable: !rootObject.notificationClosed(itemData)
    readonly property var displayActions: rootObject.notificationDisplayActions(itemData).slice(0, 2)
    readonly property string iconSource: rootObject.notificationResolvedIcon(itemData)
    readonly property string imageSource: rootObject.notificationResolvedImage(itemData)
    readonly property color accentColor: rootObject.notificationAccentColor(itemData)
    readonly property real stackReveal: stackCount > 0 ? (stackCount > 1 ? 10 : 5) : 0

    implicitHeight: cardBody.implicitHeight + stackReveal

    Rectangle {
        visible: card.stackCount > 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: cardBody.bottom
        anchors.topMargin: -cardBody.height + 10
        width: parent.width * 0.88
        height: cardBody.height
        radius: Theme.rad(16)
        color: colorsObject.cardAlt
        border.color: colorsObject.lineSoft
        border.width: 1
        opacity: 0.55
    }

    Rectangle {
        visible: card.stackCount > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: cardBody.bottom
        anchors.topMargin: -cardBody.height + 5
        width: parent.width * 0.94
        height: cardBody.height
        radius: Theme.rad(16)
        color: colorsObject.cardAlt
        border.color: colorsObject.border
        border.width: 1
        opacity: 0.8
    }

    Rectangle {
        id: cardBody
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: cardColumn.implicitHeight + 24
        height: implicitHeight
        radius: Theme.rad(16)
        color: rootObject.notificationCardFill(itemData)
        border.color: cardHover.hovered ? colorsObject.borderStrong : rootObject.notificationCardBorder(itemData)
        border.width: 1
        clip: true

        Behavior on border.color {
            ColorAnimation {
                duration: 140
            }
        }

        HoverHandler {
            id: cardHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (card.stackCount > 0) {
                    card.expandRequested();
                } else {
                    card.detailRequested(card.notificationId);
                }
            }
        }

        Rectangle {
            visible: card.critical
            anchors.left: parent.left
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 12
            width: 3
            radius: 2
            color: colorsObject.red
        }

        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: Theme.rad(6)
                    color: card.iconSource !== "" ? "transparent" : rootObject.notificationAvatarFill(itemData)
                    border.color: card.iconSource !== "" ? "transparent" : Theme.edgeHighlightSoft
                    border.width: 1

                    IconImage {
                        visible: card.iconSource !== ""
                        anchors.centerIn: parent
                        implicitSize: 18
                        source: card.iconSource
                        mipmap: true
                    }

                    Text {
                        font.family: Theme.fontFamily
                        visible: card.iconSource === ""
                        anchors.centerIn: parent
                        text: rootObject.notificationAvatarText(itemData)
                        color: colorsObject.textDim
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    text: rootObject.notificationAppLabel(itemData).toUpperCase()
                    color: card.critical ? colorsObject.red : colorsObject.subtle
                    font.pixelSize: Theme.fs(9)
                    font.letterSpacing: 0.8
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.maximumWidth: card.width * 0.45
                }

                Text {
                    font.family: Theme.fontFamily
                    text: rootObject.notificationRelativeTime(itemData)
                    color: colorsObject.subtle
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Medium
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    font.family: Theme.fontFamily
                    visible: card.stackCount > 0
                    text: "+" + card.stackCount
                    color: colorsObject.subtle
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    visible: rootObject.notificationUnread(itemData)
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: card.accentColor
                }

                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: Theme.rad(8)
                    color: railDismissMouse.containsMouse ? colorsObject.redBg : Theme.elevationFaint
                    border.color: railDismissMouse.containsMouse ? colorsObject.red : Theme.elevation
                    border.width: 1
                    opacity: cardHover.hovered || railDismissMouse.containsMouse ? 1 : 0.35

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                        }
                    }

                    Text {
                        font.family: Theme.fontFamily
                        anchors.centerIn: parent
                        text: "×"
                        color: railDismissMouse.containsMouse ? colorsObject.red : colorsObject.subtle
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: railDismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.dismissRequested(card.notificationId)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 3

                    Text {
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                        text: rootObject.notificationHeadline(itemData)
                        color: colorsObject.text
                        font.pixelSize: Theme.fs(12)
                        lineHeight: 1.15
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                        visible: rootObject.notificationBody(itemData).length > 0
                        text: rootObject.notificationBody(itemData)
                        color: colorsObject.textDim
                        font.pixelSize: Theme.fs(10)
                        lineHeight: 1.2
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        textFormat: rootObject.notificationBodyFormat()
                    }
                }

                Rectangle {
                    visible: card.imageSource !== ""
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    Layout.alignment: Qt.AlignTop
                    radius: Theme.rad(10)
                    color: Theme.elevationFaint
                    border.color: Theme.elevation
                    border.width: 1
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: card.imageSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }
                }
            }

            RowLayout {
                visible: card.displayActions.length > 0 || rootObject.notificationMetaLabel(itemData).length > 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                Repeater {
                    model: card.displayActions

                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: railActionText.implicitWidth + 20
                        radius: Theme.rad(9)
                        opacity: card.actionable ? 1 : 0.4
                        color: railActionMouse.containsMouse ? Qt.tint(card.accentColor, Theme.elevationStrong) : Theme.elevationSoft
                        border.color: railActionMouse.containsMouse ? Qt.tint(card.accentColor, Theme.elevationStrong) : Theme.elevation
                        border.width: 1
                        scale: railActionMouse.pressed ? 0.96 : 1.0

                        Behavior on scale {
                            NumberAnimation {
                                duration: 90
                                easing.type: Easing.OutQuad
                            }
                        }

                        Text {
                            font.family: Theme.fontFamily
                            id: railActionText
                            anchors.centerIn: parent
                            text: rootObject.notificationActionText(modelData)
                            color: colorsObject.text
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: railActionMouse
                            anchors.fill: parent
                            enabled: card.actionable
                            hoverEnabled: card.actionable
                            cursorShape: card.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: card.actionInvoked(card.notificationId, rootObject.notificationActionIdentifier(modelData))
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    font.family: Theme.fontFamily
                    text: rootObject.notificationMetaLabel(itemData)
                    color: card.critical ? colorsObject.red : colorsObject.subtle
                    font.pixelSize: Theme.fs(9)
                    elide: Text.ElideRight
                    Layout.maximumWidth: card.width * 0.4
                }
            }
        }
    }
}
