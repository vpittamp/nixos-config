import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

// A notification card in the runtime-panel center. When it fronts a collapsed
// app group (stackCount > 0) it renders iOS-style: card edges peeking out
// below, and clicking expands the group instead of opening the detail view.
Item {
    id: card

    required property var rootObject
    required property var colorsObject
    required property var itemData
    property bool compact: false
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
        radius: 16
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
        radius: 16
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
        implicitHeight: compact ? 92 : detailsColumn.implicitHeight + 18
        height: implicitHeight
        radius: 16
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

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: 2
            color: card.accentColor
            opacity: card.critical ? 1 : 0.82
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

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            spacing: 12

            Rectangle {
                Layout.preferredWidth: compact ? 34 : 38
                Layout.preferredHeight: compact ? 34 : 38
                Layout.alignment: Qt.AlignTop
                radius: 12
                color: rootObject.notificationAvatarFill(itemData)
                border.color: Theme.edgeHighlight
                border.width: 1

                Item {
                    anchors.fill: parent

                    IconImage {
                        visible: rootObject.notificationResolvedIcon(itemData) !== ""
                        anchors.centerIn: parent
                        implicitSize: compact ? 16 : 18
                        source: rootObject.notificationResolvedIcon(itemData)
                        mipmap: true
                    }

                    Text {
                        visible: !parent.children[0].visible
                        anchors.centerIn: parent
                        text: rootObject.notificationAvatarText(itemData)
                        color: colorsObject.text
                        font.pixelSize: compact ? 11 : 12
                        font.weight: Font.DemiBold
                    }
                }
            }

            ColumnLayout {
                id: detailsColumn
                Layout.fillWidth: true
                spacing: compact ? 3 : 7

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: rootObject.notificationHeadline(itemData)
                        color: colorsObject.text
                        font.pixelSize: compact ? 11 : 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: card.stackCount > 0
                        text: "+" + card.stackCount
                        color: colorsObject.subtle
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        visible: rootObject.notificationUnread(itemData)
                        Layout.preferredWidth: 9
                        Layout.preferredHeight: 9
                        radius: 4
                        color: card.accentColor
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: rootObject.notificationAppLabel(itemData)
                        color: colorsObject.subtle
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        // Cap against the card, not the enclosing layout — a
                        // child sized from its own layout's width rearranges
                        // recursively.
                        Layout.maximumWidth: card.width * 0.6
                    }

                    Text {
                        text: rootObject.notificationRelativeTime(itemData)
                        color: colorsObject.subtle
                        font.pixelSize: 9
                        opacity: 0.8
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                Item {
                    Layout.fillWidth: true
                    visible: !compact && rootObject.notificationBody(itemData).length > 0
                    implicitHeight: railBodyText.implicitHeight

                    Text {
                        id: railBodyText
                        width: parent.width
                        text: rootObject.notificationBody(itemData)
                        color: colorsObject.textDim
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        textFormat: rootObject.notificationBodyFormat()
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
                }

                Rectangle {
                    visible: !compact && imageSource !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 128 : 0
                    radius: 12
                    color: Theme.elevationFaint
                    border.color: Theme.edgeHighlightSoft
                    border.width: 1
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: imageSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: rootObject.notificationMetaLabel(itemData)
                        color: card.critical ? colorsObject.red : colorsObject.subtle
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    Repeater {
                        model: card.displayActions

                        delegate: Rectangle {
                            required property var modelData
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: railActionText.implicitWidth + 18
                            radius: 9
                            opacity: card.actionable ? 1 : 0.4
                            color: railActionMouse.containsMouse ? Qt.tint(card.accentColor, Theme.elevationStrong) : Qt.tint(card.accentColor, Theme.shadow)
                            border.color: Qt.tint(card.accentColor, Theme.elevationStrong)
                            border.width: 1

                            Text {
                                id: railActionText
                                anchors.centerIn: parent
                                text: rootObject.notificationActionText(modelData)
                                color: colorsObject.text
                                font.pixelSize: 9
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

                    Rectangle {
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 26
                        radius: 9
                        color: dismissMouse.containsMouse ? colorsObject.redBg : Theme.elevationFaint
                        border.color: Theme.elevationSoft
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: dismissMouse.containsMouse ? colorsObject.red : colorsObject.subtle
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            id: dismissMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.dismissRequested(card.notificationId)
                        }
                    }
                }
            }
        }
    }
}
