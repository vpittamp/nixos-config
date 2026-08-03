import QtQuick
import QtQuick.Controls
import QtQuick.Effects
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
    signal detailRequested(int notificationId)

    readonly property bool critical: rootObject.notificationIsCritical(itemData)
    readonly property color accentColor: rootObject.notificationAccentColor(itemData)
    readonly property string imageSource: rootObject.notificationResolvedImage(itemData)
    readonly property var primaryAction: rootObject.notificationPrimaryAction(itemData)
    readonly property int timeoutMs: rootObject.notificationTimeoutFor(itemData)
    // MultiEffect is shader-based; the software Quick backend (NVIDIA hosts)
    // would render a layered item as nothing at all, so the shadow is gated
    // and those hosts get the 1px dark halo below instead.
    readonly property bool shadowCapable: GraphicsInfo.api !== GraphicsInfo.Software

    width: preferredWidth
    implicitWidth: preferredWidth
    implicitHeight: toastColumn.implicitHeight + 20
    radius: rootObject.radiusFloat
    color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, critical ? 0.94 : 0.88)
    border.color: Qt.tint(accentColor, (critical ? Theme.elevationStrong : Theme.elevation))
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
        visible: !toast.shadowCapable
        anchors.fill: parent
        anchors.margins: -1
        radius: parent.radius + 1
        color: "transparent"
        border.color: Theme.edgeShadow
        border.width: 1
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.color: critical ? Theme.edgeHighlight : Theme.elevationSoft
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
                radius: rootObject.radiusCard
                color: rootObject.notificationAvatarFill(itemData)
                border.color: Theme.edgeHighlight
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
                    lineHeight: 1.08
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: rootObject.radiusControl
                color: closeMouse.containsMouse ? colorsObject.redBg : Theme.elevationFaint
                border.color: Theme.elevation
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

        Item {
            Layout.fillWidth: true
            visible: rootObject.notificationBody(itemData).length > 0
            implicitHeight: bodyText.implicitHeight

            Text {
                id: bodyText
                width: parent.width
                text: rootObject.notificationBody(itemData)
                color: colorsObject.textDim
                font.pixelSize: 11
                lineHeight: 1.1
                wrapMode: Text.Wrap
                maximumLineCount: imageSource !== "" ? 4 : 6
                elide: Text.ElideRight
                textFormat: rootObject.notificationBodyFormat()
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: toast.detailRequested(Number(itemData.id || 0))
            }
        }

        Rectangle {
            visible: imageSource !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 116 : 0
            radius: rootObject.radiusCard
            color: Theme.elevationFaint
            border.color: Theme.elevation
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
                radius: rootObject.radiusControl
                color: actionMouse.containsMouse ? Qt.tint(accentColor, Theme.elevationStrong) : Qt.tint(accentColor, Theme.shadow)
                border.color: Qt.tint(accentColor, Theme.elevationStrong)
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
