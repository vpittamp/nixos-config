import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Rectangle {
    id: sessionRow

    required property var rootObject
    required property var colorsObject
    required property var session
    property bool selected: false
    property bool currentOverride: false
    property bool hovered: false
    property bool interactive: false
    property bool compact: false
    property bool closePending: false
    property bool showAccentRail: true
    property bool showHostToken: true
    property bool showProjectChip: true
    property bool showCurrentChip: false
    property bool showCloseAction: interactive
    signal clicked
    signal closeRequested

    readonly property bool effectiveHovered: interactive ? sessionRowMouse.containsMouse : hovered
    readonly property bool isCurrent: currentOverride || rootObject.sessionIsCurrent(session)
    readonly property string primaryLabel: rootObject.sessionPrimaryLabel(session)
    readonly property string secondaryLabel: rootObject.sessionSecondaryLabel(session)
    readonly property string activityLabel: rootObject.sessionActivityChipLabel(session)
    readonly property string activitySymbol: rootObject.sessionBadgeSymbol(session)
    readonly property string activityState: rootObject.sessionBadgeState(session)
    readonly property string gitChipText: rootObject.sessionGitChipText(session)
    readonly property var hostTokenData: rootObject.sessionHostToken(session)
    readonly property color accentColor: rootObject.launcherEntryAccentColor(session)
    readonly property color currentAccentColor: colorsObject.blue
    readonly property string projectLabel: rootObject.stringOrEmpty(session && (session.project_label || rootObject.shortProject(rootObject.stringOrEmpty(session.project_name || session.project || "global"))))
    readonly property bool closableSurface: showCloseAction && rootObject.sessionHasClosableSurface(session)
    readonly property bool isIdle: rootObject.sessionIsIdle(session)
    readonly property real idleRowOpacity: isIdle ? (isCurrent ? 0.9 : 0.76) : 1
    readonly property real idleTextOpacity: isIdle ? (isCurrent ? 0.86 : 0.72) : 1
    readonly property real idleChipOpacity: isIdle ? (isCurrent ? 0.9 : 0.76) : 1
    readonly property real toolIconOpacity: hasMotion ? 0.96 : (isIdle ? (isCurrent ? 0.64 : 0.5) : 0.92)
    property bool hasMotion: rootObject.sessionHasMotion(session)
    property int activitySpinnerFrame: 0
    readonly property var activitySpinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    readonly property int rowHeight: compact ? 48 : 62
    readonly property int railHeight: compact ? (selected ? 30 : (effectiveHovered ? 26 : 22)) : (selected ? 38 : (effectiveHovered ? 32 : 28))
    readonly property int iconWrapSize: compact ? 28 : 34
    readonly property int iconGlyphSize: compact ? 14 : 16
    readonly property int chipHeight: compact ? 18 : 20
    readonly property int statusIconSize: compact ? 20 : 22
    readonly property bool stoppedNotification: activityState === "stopped"

    implicitHeight: rowHeight
    radius: compact ? 7 : 8
    color: isCurrent
        ? (effectiveHovered ? Qt.tint(colorsObject.blueBg, Qt.rgba(1, 1, 1, 0.035)) : colorsObject.blueBg)
        : (selected ? colorsObject.blueBg : (effectiveHovered ? colorsObject.cardAlt : "transparent"))
    border.color: isCurrent
        ? (effectiveHovered ? colorsObject.blue : colorsObject.blueMuted)
        : (selected ? colorsObject.blue : (effectiveHovered ? colorsObject.borderStrong : "transparent"))
    border.width: 1
    opacity: (closePending ? 0.9 : 1) * idleRowOpacity

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
        sessionToolIconWrap.opacity = toolIconOpacity;
        sessionToolIconWrap.scale = 1;
    }

    onHasMotionChanged: resetMotionVisuals()
    Component.onCompleted: resetMotionVisuals()

    Timer {
        running: hasMotion
        repeat: true
        interval: 95
        onTriggered: activitySpinnerFrame = (activitySpinnerFrame + 1) % activitySpinnerFrames.length
    }

    Rectangle {
        visible: showAccentRail
        anchors.left: parent.left
        anchors.leftMargin: isCurrent ? 10 : 8
        anchors.verticalCenter: parent.verticalCenter
        width: isCurrent ? 3 : 2
        height: isCurrent ? (compact ? 22 : 28) : railHeight
        radius: 1
        color: isCurrent ? currentAccentColor : accentColor
        opacity: (isCurrent ? 0.92 : (selected ? 0.92 : (effectiveHovered ? 0.72 : 0.46))) * idleTextOpacity

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
            color: "transparent"
            border.color: "transparent"
            border.width: 0

            Item {
                id: sessionToolIconWrap
                anchors.centerIn: parent
                width: compact ? 16 : 18
                height: compact ? 16 : 18
                scale: 1
                opacity: toolIconOpacity

                ParallelAnimation {
                    running: hasMotion
                    loops: Animation.Infinite

                    SequentialAnimation {
                        ScaleAnimator {
                            target: sessionToolIconWrap
                            from: 0.94
                            to: 1.12
                            duration: 800
                        }
                        ScaleAnimator {
                            target: sessionToolIconWrap
                            from: 1.12
                            to: 0.94
                            duration: 800
                        }
                    }

                    SequentialAnimation {
                        OpacityAnimator {
                            target: sessionToolIconWrap
                            from: 0.82
                            to: 1
                            duration: 800
                        }
                        OpacityAnimator {
                            target: sessionToolIconWrap
                            from: 1
                            to: 0.82
                            duration: 800
                        }
                    }
                }

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
                opacity: idleTextOpacity
            }

            Text {
                Layout.fillWidth: true
                text: secondaryLabel
                color: isCurrent ? colorsObject.textDim : (selected ? colorsObject.textDim : colorsObject.subtle)
                font.pixelSize: compact ? 9 : 10
                elide: Text.ElideRight
                opacity: idleTextOpacity
            }
        }

        Rectangle {
            visible: showHostToken && hostTokenData && rootObject.stringOrEmpty(hostTokenData.label).length > 0
            height: chipHeight
            radius: 6
            color: hostTokenData ? hostTokenData.background : colorsObject.panelAlt
            border.color: colorsObject.lineSoft
            border.width: 1
            Layout.preferredWidth: launcherHostTokenRow.implicitWidth + 16
            Layout.maximumWidth: 132
            opacity: idleChipOpacity

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
            visible: showCurrentChip && isCurrent
            height: chipHeight
            radius: 6
            color: colorsObject.panelAlt
            border.color: colorsObject.lineSoft
            border.width: 1
            opacity: idleChipOpacity
            Layout.preferredWidth: currentChipText.implicitWidth + 12

            Text {
                id: currentChipText
                anchors.centerIn: parent
                text: "Current"
                color: currentAccentColor
                font.pixelSize: compact ? 7 : 8
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            visible: showProjectChip && projectLabel.length > 0
            height: chipHeight
            radius: 6
            color: isCurrent ? colorsObject.panelAlt : (selected ? colorsObject.bg : colorsObject.panelAlt)
            border.color: colorsObject.lineSoft
            border.width: 1
            Layout.preferredWidth: projectText.implicitWidth + 12
            opacity: idleChipOpacity

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
            visible: rootObject.sessionGitChipVisible(session)
            height: chipHeight
            radius: 6
            color: rootObject.sessionGitChipBackground(session)
            border.color: "transparent"
            border.width: 0
            opacity: idleChipOpacity * 0.84
            Layout.preferredWidth: gitText.implicitWidth + 12

            Text {
                id: gitText
                anchors.centerIn: parent
                text: gitChipText
                color: rootObject.sessionGitChipForeground(session)
                font.pixelSize: compact ? 7 : 8
                font.weight: Font.Medium
            }
        }

        Rectangle {
            visible: activityLabel.length > 0 || activitySymbol.length > 0
            height: stoppedNotification ? (compact ? 16 : 18) : Math.max(chipHeight, statusIconSize)
            radius: stoppedNotification ? 5 : 6
            color: stoppedNotification
                ? Qt.tint(rootObject.sessionBadgeBackground(session), Qt.rgba(1, 1, 1, isCurrent ? 0.05 : 0.02))
                : rootObject.sessionBadgeBackground(session)
            border.color: rootObject.sessionBadgeBorderColor(session)
            border.width: border.color === "transparent" ? 0 : 1
            opacity: idleChipOpacity
            Layout.preferredWidth: stoppedNotification
                ? (compact ? 22 : 24)
                : (activityLabel.length > 0
                    ? activityText.implicitWidth + statusIconSize + 15
                    : statusIconSize + 12)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: stoppedNotification ? 0 : 6
                anchors.rightMargin: stoppedNotification ? 0 : 8
                spacing: stoppedNotification ? 0 : (compact ? 3 : 4)

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    visible: stoppedNotification
                    width: compact ? 8 : 9
                    height: width
                    radius: width / 2
                    color: rootObject.sessionBadgeColor(session)
                }

                Text {
                    id: activitySpinner
                    Layout.preferredWidth: statusIconSize
                    visible: !stoppedNotification && hasMotion
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: activitySpinnerFrames[activitySpinnerFrame]
                    color: rootObject.sessionBadgeColor(session)
                    font.pixelSize: compact ? 15 : 17
                    font.weight: Font.DemiBold
                }

                Text {
                    id: activitySymbolText
                    visible: !stoppedNotification && !hasMotion && activitySymbol.length > 0
                    text: activitySymbol
                    color: rootObject.sessionBadgeColor(session)
                    font.pixelSize: compact ? 13 : 15
                    font.weight: Font.DemiBold
                }

                Text {
                    id: activityText
                    text: activityLabel
                    color: rootObject.sessionBadgeColor(session)
                    font.pixelSize: compact ? 8 : 9
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
