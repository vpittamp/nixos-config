import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

Rectangle {
    id: card

    required property var rootObject
    required property var colorsObject
    required property var itemData
    property bool compact: false

    signal dismissRequested(int notificationId)
    signal actionInvoked(int notificationId, string actionId)
    signal markReadRequested(int notificationId)

    readonly property bool critical: rootObject.notificationIsCritical(itemData)
    readonly property var primaryAction: rootObject.notificationPrimaryAction(itemData)
    readonly property string imageSource: rootObject.notificationResolvedImage(itemData)
    readonly property color accentColor: rootObject.notificationAccentColor(itemData)

    implicitHeight: compact ? 92 : detailsColumn.implicitHeight + 18
    radius: 16
    color: rootObject.notificationCardFill(itemData)
    border.color: rootObject.notificationCardBorder(itemData)
    border.width: 1
    clip: true

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        radius: 2
        color: accentColor
        opacity: critical ? 1 : 0.82
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
            radius: 12
            color: rootObject.notificationAvatarFill(itemData)
            border.color: Qt.rgba(1, 1, 1, 0.08)
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

                Rectangle {
                    visible: rootObject.notificationUnread(itemData)
                    Layout.preferredWidth: 9
                    Layout.preferredHeight: 9
                    radius: 4
                    color: accentColor
                }
            }

            Text {
                Layout.fillWidth: true
                text: rootObject.notificationAppLabel(itemData)
                color: colorsObject.subtle
                font.pixelSize: 9
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Text {
                visible: !compact && rootObject.notificationBody(itemData).length > 0
                Layout.fillWidth: true
                text: rootObject.notificationBody(itemData)
                color: colorsObject.textDim
                font.pixelSize: 10
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                textFormat: rootObject.notificationBodyFormat()
            }

            Rectangle {
                visible: !compact && imageSource !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 128 : 0
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.02)
                border.color: Qt.rgba(1, 1, 1, 0.05)
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
                    color: critical ? colorsObject.red : colorsObject.subtle
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: primaryAction !== null
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: visible ? actionText.implicitWidth + 18 : 0
                    radius: 9
                    color: actionMouse.containsMouse ? Qt.tint(accentColor, Qt.rgba(1, 1, 1, 0.16)) : Qt.tint(accentColor, Qt.rgba(0, 0, 0, 0.58))
                    border.color: Qt.tint(accentColor, Qt.rgba(1, 1, 1, 0.16))
                    border.width: 1

                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: rootObject.notificationActionText(primaryAction)
                        color: colorsObject.text
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.actionInvoked(Number(itemData.id || 0), rootObject.notificationActionIdentifier(primaryAction))
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: 26
                    radius: 9
                    color: dismissMouse.containsMouse ? colorsObject.redBg : Qt.rgba(1, 1, 1, 0.02)
                    border.color: Qt.rgba(1, 1, 1, 0.04)
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
                        onClicked: card.dismissRequested(Number(itemData.id || 0))
                    }
                }
            }
        }
    }

}
