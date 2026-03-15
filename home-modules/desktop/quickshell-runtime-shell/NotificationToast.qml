import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

Rectangle {
    id: toast

    required property var rootObject
    required property var colorsObject
    required property var itemData
    property real preferredWidth: 380

    signal dismissRequested(int notificationId)
    signal expireRequested(int notificationId)
    signal actionInvoked(int notificationId, string actionId)
    signal defaultInvoked(int notificationId)

    readonly property bool critical: rootObject.notificationIsCritical(itemData)
    readonly property color accentColor: rootObject.notificationAccentColor(itemData)
    readonly property string imageSource: rootObject.notificationResolvedImage(itemData)
    readonly property var primaryAction: rootObject.notificationPrimaryAction(itemData)
    readonly property int timeoutMs: rootObject.notificationTimeoutFor(itemData)

    width: preferredWidth
    implicitWidth: preferredWidth
    implicitHeight: toastColumn.implicitHeight + 20
    radius: 20
    color: Qt.rgba(0.055, 0.074, 0.11, critical ? 0.94 : 0.88)
    border.color: Qt.tint(accentColor, Qt.rgba(1, 1, 1, critical ? 0.22 : 0.1))
    border.width: 1

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.color: critical ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 5
        radius: 3
        color: accentColor
        opacity: critical ? 1 : 0.78
    }

    ColumnLayout {
        id: toastColumn
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 14
                color: rootObject.notificationAvatarFill(itemData)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                Item {
                    anchors.fill: parent

                    IconImage {
                        visible: rootObject.notificationResolvedIcon(itemData) !== ""
                        anchors.centerIn: parent
                        implicitSize: 22
                        source: rootObject.notificationResolvedIcon(itemData)
                        mipmap: true
                    }

                    Text {
                        visible: !parent.children[0].visible
                        anchors.centerIn: parent
                        text: rootObject.notificationAvatarText(itemData)
                        color: colorsObject.text
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: rootObject.notificationAppLabel(itemData)
                    color: colorsObject.textDim
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: rootObject.notificationHeadline(itemData)
                    color: colorsObject.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 10
                color: closeMouse.containsMouse ? colorsObject.redBg : Qt.rgba(1, 1, 1, 0.03)
                border.color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: closeMouse.containsMouse ? colorsObject.red : colorsObject.subtle
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toast.dismissRequested(Number(itemData.id || 0))
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: rootObject.notificationBody(itemData).length > 0
            text: rootObject.notificationBody(itemData)
            color: colorsObject.textDim
            font.pixelSize: 11
            wrapMode: Text.Wrap
            maximumLineCount: imageSource !== "" ? 4 : 6
            elide: Text.ElideRight
            textFormat: rootObject.notificationBodyFormat()
        }

        Rectangle {
            visible: imageSource !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 116 : 0
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.02)
            border.color: Qt.rgba(1, 1, 1, 0.06)
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
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Rectangle {
                visible: primaryAction !== null
                Layout.preferredHeight: 28
                Layout.preferredWidth: visible ? actionLabel.implicitWidth + 22 : 0
                radius: 10
                color: actionMouse.containsMouse ? Qt.tint(accentColor, Qt.rgba(1, 1, 1, 0.18)) : Qt.tint(accentColor, Qt.rgba(0, 0, 0, 0.58))
                border.color: Qt.tint(accentColor, Qt.rgba(1, 1, 1, 0.22))
                border.width: 1

                Text {
                    id: actionLabel
                    anchors.centerIn: parent
                    text: rootObject.notificationActionText(primaryAction)
                    color: colorsObject.text
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toast.actionInvoked(Number(itemData.id || 0), rootObject.notificationActionIdentifier(primaryAction))
                }
            }
        }
    }

    Timer {
        running: timeoutMs > 0
        repeat: false
        interval: timeoutMs
        onTriggered: toast.expireRequested(Number(itemData.id || 0))
    }
}
