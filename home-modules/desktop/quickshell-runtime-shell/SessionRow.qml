import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Rectangle {
    id: sessionRow

    required property var rootObject
    required property var colorsObject
    required property var session
    property bool selected: false
    property bool hovered: false
    property bool interactive: false
    property bool compact: false
    property bool closePending: false
    property bool showAccentRail: true
    property bool showHostToken: true
    property bool showProjectChip: true
    property bool showCurrentChip: true
    property bool showCloseAction: interactive
    signal clicked
    signal closeRequested

    readonly property bool effectiveHovered: interactive ? sessionRowMouse.containsMouse : hovered
    readonly property bool isCurrent: rootObject.sessionIsCurrent(session)
    readonly property string primaryLabel: rootObject.sessionPrimaryLabel(session)
    readonly property string secondaryLabel: rootObject.sessionSecondaryLabel(session)
    readonly property string activityLabel: rootObject.sessionActivityChipLabel(session)
    readonly property string activitySymbol: rootObject.sessionBadgeSymbol(session)
    readonly property string activityState: rootObject.sessionBadgeState(session)
    readonly property var hostTokenData: rootObject.sessionHostToken(session)
    readonly property color accentColor: rootObject.launcherEntryAccentColor(session)
    readonly property color currentAccentColor: colorsObject.textDim
    readonly property string projectLabel: rootObject.stringOrEmpty(session && (session.project_label || rootObject.shortProject(rootObject.stringOrEmpty(session.project_name || session.project || "global"))))
    readonly property bool closableSurface: showCloseAction && rootObject.sessionHasClosableSurface(session)
    property bool hasMotion: rootObject.sessionHasMotion(session)
    readonly property int rowHeight: compact ? 48 : 62
    readonly property int railHeight: compact ? (selected ? 30 : (effectiveHovered ? 26 : 22)) : (selected ? 38 : (effectiveHovered ? 32 : 28))
    readonly property int iconWrapSize: compact ? 28 : 34
    readonly property int iconGlyphSize: compact ? 14 : 16
    readonly property int chipHeight: compact ? 18 : 20
    readonly property bool stoppedNotification: activityState === "stopped"

    implicitHeight: rowHeight
    radius: compact ? 7 : 8
    color: isCurrent
        ? (selected
            ? Qt.tint(colorsObject.blueBg, Qt.rgba(0.40, 0.86, 0.92, 0.08))
            : Qt.tint(colorsObject.cardAlt, Qt.rgba(0.40, 0.86, 0.92, effectiveHovered ? 0.11 : 0.07)))
        : (selected ? colorsObject.blueBg : (effectiveHovered ? colorsObject.cardAlt : "transparent"))
    border.color: isCurrent
        ? (effectiveHovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
        : (selected ? colorsObject.blue : (effectiveHovered ? colorsObject.borderStrong : "transparent"))
    border.width: 1
    opacity: closePending ? 0.9 : 1

    Rectangle {
        visible: isCurrent
        anchors.fill: parent
        anchors.margins: 1
        radius: compact ? 6 : 7
        color: Qt.rgba(1, 1, 1, effectiveHovered ? 0.018 : 0.012)
        border.color: "transparent"
        border.width: 0
    }

    function resetMotionVisuals() {
        sessionToolIconWrap.opacity = 0.92;
        sessionToolIconWrap.scale = 1;
    }

    onHasMotionChanged: resetMotionVisuals()
    Component.onCompleted: resetMotionVisuals()

    Rectangle {
        visible: showAccentRail
        anchors.left: parent.left
        anchors.leftMargin: isCurrent ? 10 : 8
        anchors.verticalCenter: parent.verticalCenter
        width: isCurrent ? 3 : 2
        height: isCurrent ? (compact ? 22 : 28) : railHeight
        radius: 1
        color: isCurrent ? currentAccentColor : accentColor
        opacity: isCurrent ? 0.28 : (selected ? 0.92 : (effectiveHovered ? 0.72 : 0.46))

        Rectangle {
            visible: isCurrent
            anchors.centerIn: parent
            width: 1
            height: Math.max(10, parent.height - (compact ? 8 : 10))
            radius: 1
            color: colorsObject.text
            opacity: 0.72
        }
    }

        RowLayout {
            z: 1
            anchors.fill: parent
            anchors.leftMargin: compact ? 16 : 20
            anchors.rightMargin: compact ? 10 : 12
            spacing: compact ? 10 : 12

        Rectangle {
            width: iconWrapSize
            height: iconWrapSize
            radius: compact ? 7 : 8
            color: isCurrent
                ? Qt.tint(rootObject.sessionTint(session), Qt.rgba(0.42, 0.84, 0.9, 0.06))
                : (selected ? colorsObject.bg : rootObject.sessionTint(session))
            border.color: "transparent"
            border.width: 0

            Item {
                id: sessionToolIconWrap
                anchors.centerIn: parent
                width: compact ? 16 : 18
                height: compact ? 16 : 18
                scale: 1
                opacity: 0.92

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: iconGlyphSize
                    source: rootObject.toolIconSource(session)
                    mipmap: true
                    opacity: 1
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 1
                anchors.bottomMargin: 1
                width: compact ? 7 : 8
                height: compact ? 7 : 8
                radius: compact ? 3 : 4
                color: rootObject.sessionBadgeColor(session)
                opacity: 0.85
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: compact ? 1 : 2

            Text {
                Layout.fillWidth: true
                text: primaryLabel
                color: isCurrent ? colorsObject.text : (selected ? colorsObject.blue : colorsObject.text)
                font.pixelSize: compact ? 12 : 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: secondaryLabel
                color: isCurrent ? colorsObject.textDim : (selected ? colorsObject.textDim : colorsObject.subtle)
                font.pixelSize: compact ? 9 : 10
                elide: Text.ElideRight
            }
        }

        Rectangle {
            visible: showHostToken && hostTokenData && rootObject.stringOrEmpty(hostTokenData.label).length > 0
            height: chipHeight
            radius: 6
            color: hostTokenData ? hostTokenData.background : colorsObject.panelAlt
            border.color: hostTokenData ? hostTokenData.border : colorsObject.lineSoft
            border.width: 1
            Layout.preferredWidth: launcherHostTokenRow.implicitWidth + 16
            Layout.maximumWidth: 132

            RowLayout {
                id: launcherHostTokenRow
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 8
                spacing: compact ? 4 : 5

                Rectangle {
                    width: compact ? 10 : 12
                    height: compact ? 10 : 12
                    radius: 4
                    color: hostTokenData ? hostTokenData.border : colorsObject.lineSoft
                    border.color: "transparent"
                    border.width: 0

                    IconImage {
                        visible: hostTokenData && rootObject.stringOrEmpty(hostTokenData.icon).length > 0
                        anchors.centerIn: parent
                        implicitSize: compact ? 8 : 10
                        source: hostTokenData ? hostTokenData.icon : ""
                        mipmap: true
                    }

                    Text {
                        visible: !hostTokenData || rootObject.stringOrEmpty(hostTokenData.icon).length === 0
                        anchors.centerIn: parent
                        text: hostTokenData ? rootObject.stringOrEmpty(hostTokenData.monogram) : ""
                        color: colorsObject.bg
                        font.pixelSize: compact ? 6 : 7
                        font.weight: Font.Bold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: hostTokenData ? rootObject.stringOrEmpty(hostTokenData.label) : ""
                    color: hostTokenData ? hostTokenData.foreground : colorsObject.textDim
                    font.pixelSize: compact ? 7 : 8
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            visible: showProjectChip && projectLabel.length > 0
            height: chipHeight
            radius: 6
            color: isCurrent ? colorsObject.panelAlt : (selected ? colorsObject.bg : colorsObject.panelAlt)
            border.color: isCurrent ? colorsObject.lineSoft : (selected ? colorsObject.blue : colorsObject.lineSoft)
            border.width: 1
            Layout.preferredWidth: projectText.implicitWidth + 12

            Text {
                id: projectText
                anchors.centerIn: parent
                text: projectLabel
                color: isCurrent ? currentAccentColor : (selected ? colorsObject.blue : colorsObject.textDim)
                font.pixelSize: compact ? 7 : 8
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            visible: activityLabel.length > 0 || activitySymbol.length > 0
            height: stoppedNotification ? (compact ? 14 : 16) : chipHeight
            radius: stoppedNotification ? 5 : 6
            color: stoppedNotification
                ? Qt.tint(rootObject.sessionBadgeBackground(session), Qt.rgba(1, 1, 1, isCurrent ? 0.05 : 0.02))
                : rootObject.sessionBadgeBackground(session)
            border.color: rootObject.sessionBadgeBorderColor(session)
            border.width: border.color === "transparent" ? 0 : 1
            Layout.preferredWidth: stoppedNotification
                ? (compact ? 20 : 22)
                : (activityLabel.length > 0
                    ? activityText.implicitWidth + 16
                    : ((compact ? 18 : 20) + 12))

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: stoppedNotification ? 0 : 6
                anchors.rightMargin: stoppedNotification ? 0 : 8
                spacing: stoppedNotification ? 0 : (compact ? 3 : 4)

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    visible: stoppedNotification
                    width: compact ? 6 : 7
                    height: width
                    radius: width / 2
                    color: rootObject.sessionBadgeColor(session)
                }

                Text {
                    visible: !stoppedNotification && activitySymbol.length > 0
                    text: activitySymbol
                    color: rootObject.sessionBadgeColor(session)
                    font.pixelSize: compact ? 8 : 9
                    font.weight: Font.DemiBold
                }

                Text {
                    id: activityText
                    text: activityLabel
                    color: rootObject.sessionBadgeColor(session)
                    font.pixelSize: compact ? 7 : 8
                    font.weight: Font.DemiBold
                }
            }
        }

        Item {
            visible: closableSurface
            width: 28
            height: 28
            Layout.preferredWidth: width
            Layout.preferredHeight: height

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: 6
                color: closePending ? colorsObject.redBg : (closeMouse.containsMouse ? colorsObject.redBg : colorsObject.bg)
                border.color: closePending ? colorsObject.red : (closeMouse.containsMouse ? colorsObject.red : colorsObject.lineSoft)
                border.width: 1

                Text {
                    visible: !closePending
                    anchors.centerIn: parent
                    text: "×"
                    color: closeMouse.containsMouse ? colorsObject.red : (selected ? colorsObject.muted : colorsObject.subtle)
                    font.pixelSize: closeMouse.containsMouse ? 11 : 10
                    font.weight: closeMouse.containsMouse ? Font.Bold : Font.DemiBold
                }

                Text {
                    visible: closePending
                    anchors.centerIn: parent
                    text: "..."
                    color: colorsObject.red
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    opacity: closePending ? 0.75 : 0

                    SequentialAnimation on opacity {
                        running: closePending
                        loops: Animation.Infinite

                        OpacityAnimator {
                            from: 0.35
                            to: 0.95
                            duration: 500
                        }
                        OpacityAnimator {
                            from: 0.95
                            to: 0.35
                            duration: 500
                        }
                    }
                }
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                z: 2
                enabled: !closePending
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    mouse.accepted = true;
                    sessionRow.closeRequested();
                }
            }
        }
    }

    MouseArea {
        id: sessionRowMouse
        z: 0
        anchors.fill: parent
        enabled: interactive
        hoverEnabled: interactive
        cursorShape: interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: sessionRow.clicked()
    }
}
