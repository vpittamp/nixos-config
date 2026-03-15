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
    property bool showAccentRail: true
    property bool showHostToken: true
    property bool showProjectChip: true
    property bool showCurrentChip: true
    signal clicked

    readonly property bool effectiveHovered: interactive ? sessionRowMouse.containsMouse : hovered
    readonly property string primaryLabel: rootObject.sessionPrimaryLabel(session)
    readonly property string secondaryLabel: rootObject.sessionSecondaryLabel(session)
    readonly property string activityLabel: rootObject.sessionBadgeLabel(session)
    readonly property var hostTokenData: rootObject.sessionHostToken(session)
    readonly property color accentColor: rootObject.launcherEntryAccentColor(session)
    readonly property string projectLabel: rootObject.stringOrEmpty(session && (session.project_label || rootObject.shortProject(rootObject.stringOrEmpty(session.project_name || session.project || "global"))))
    property bool hasMotion: rootObject.sessionHasMotion(session)
    readonly property int rowHeight: compact ? 48 : 62
    readonly property int railHeight: compact ? (selected ? 30 : (effectiveHovered ? 26 : 22)) : (selected ? 38 : (effectiveHovered ? 32 : 28))
    readonly property int iconWrapSize: compact ? 28 : 34
    readonly property int iconGlyphSize: compact ? 14 : 16
    readonly property int chipHeight: compact ? 18 : 20

    implicitHeight: rowHeight
    radius: compact ? 7 : 8
    color: selected ? colorsObject.blueBg : (effectiveHovered ? colorsObject.cardAlt : "transparent")
    border.color: selected ? colorsObject.blue : (effectiveHovered ? colorsObject.borderStrong : "transparent")
    border.width: 1

    function resetMotionVisuals() {
        sessionWorkingHalo.opacity = hasMotion ? 0.05 : 0;
        sessionWorkingHalo.scale = 1;
        sessionToolIconWrap.opacity = hasMotion ? 0.96 : 0.92;
        sessionToolIconWrap.scale = 1;
    }

    onHasMotionChanged: resetMotionVisuals()
    Component.onCompleted: resetMotionVisuals()

    Rectangle {
        visible: showAccentRail
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: railHeight
        radius: 3
        color: accentColor
        opacity: selected ? 1 : (effectiveHovered ? 0.75 : 0.5)
    }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: compact ? 12 : 16
            anchors.rightMargin: compact ? 10 : 12
            spacing: compact ? 10 : 12

        Rectangle {
            width: iconWrapSize
            height: iconWrapSize
            radius: compact ? 7 : 8
            color: selected ? colorsObject.bg : rootObject.sessionTint(session)
            border.color: selected ? colorsObject.blueMuted : "transparent"
            border.width: 1

            Rectangle {
                id: sessionWorkingHalo
                visible: hasMotion
                anchors.centerIn: parent
                width: compact ? 24 : 30
                height: compact ? 24 : 30
                radius: compact ? 7 : 9
                color: rootObject.sessionAccentColor(session)
                border.color: "transparent"
                border.width: 0
                opacity: hasMotion ? 0.05 : 0
                scale: 1

                ParallelAnimation {
                    running: hasMotion
                    loops: Animation.Infinite

                    SequentialAnimation {
                        OpacityAnimator {
                            target: sessionWorkingHalo
                            from: 0.03
                            to: 0.08
                            duration: 800
                        }
                        OpacityAnimator {
                            target: sessionWorkingHalo
                            from: 0.08
                            to: 0.03
                            duration: 800
                        }
                    }

                    SequentialAnimation {
                        ScaleAnimator {
                            target: sessionWorkingHalo
                            from: 0.96
                            to: 1.05
                            duration: 800
                        }
                        ScaleAnimator {
                            target: sessionWorkingHalo
                            from: 1.05
                            to: 0.96
                            duration: 800
                        }
                    }
                }
            }

            Item {
                id: sessionToolIconWrap
                anchors.centerIn: parent
                width: compact ? 16 : 18
                height: compact ? 16 : 18
                scale: 1
                opacity: hasMotion ? 0.96 : 0.92

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
                color: selected ? colorsObject.blue : colorsObject.text
                font.pixelSize: compact ? 12 : 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: secondaryLabel
                color: selected ? colorsObject.textDim : colorsObject.subtle
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
            color: selected ? colorsObject.bg : colorsObject.panelAlt
            border.color: selected ? colorsObject.blue : colorsObject.lineSoft
            border.width: 1
            Layout.preferredWidth: projectText.implicitWidth + 12

            Text {
                id: projectText
                anchors.centerIn: parent
                text: projectLabel
                color: selected ? colorsObject.blue : colorsObject.textDim
                font.pixelSize: compact ? 7 : 8
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            visible: showCurrentChip && !!rootObject.sessionIsCurrent(session)
            height: chipHeight
            radius: 6
            color: colorsObject.accentBg
            border.color: colorsObject.accent
            border.width: 1
            Layout.preferredWidth: currentText.implicitWidth + 12

            Text {
                id: currentText
                anchors.centerIn: parent
                text: "Current"
                color: colorsObject.accent
                font.pixelSize: compact ? 7 : 8
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            visible: activityLabel.length > 0
            height: chipHeight
            radius: 6
            color: rootObject.sessionBadgeBackground(session)
            border.color: "transparent"
            border.width: 0
            Layout.preferredWidth: activityText.implicitWidth + 16

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 8
                spacing: compact ? 3 : 4

                Rectangle {
                    width: compact ? 5 : 6
                    height: compact ? 5 : 6
                    radius: compact ? 2 : 3
                    color: rootObject.sessionBadgeColor(session)
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
    }

    MouseArea {
        id: sessionRowMouse
        anchors.fill: parent
        enabled: interactive
        hoverEnabled: interactive
        cursorShape: interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: sessionRow.clicked()
    }
}
