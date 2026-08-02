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
    property bool currentOverrideSet: false
    property bool hovered: false
    property bool rowHoverLatched: false
    property bool interactive: false
    property bool compact: false
    property bool closePending: false
    property bool showAccentRail: true
    property bool showHostToken: true
    property bool showCurrentChip: false
    property bool showCloseAction: interactive
    signal clicked
    signal closeRequested

    readonly property bool effectiveHovered: interactive ? rowHoverLatched : hovered
    readonly property bool isCurrent: currentOverrideSet ? currentOverride : rootObject.sessionIsCurrent(session)
    readonly property string primaryLabel: rootObject.sessionPrimaryLabel(session)
    readonly property string secondaryLabel: rootObject.sessionSecondaryLabel(session)
    readonly property string activityLabel: rootObject.sessionActivityChipLabel(session)
    readonly property string activitySymbol: rootObject.sessionBadgeSymbol(session)
    readonly property string activityState: rootObject.sessionBadgeState(session)
    readonly property string gitChipText: rootObject.sessionGitChipText(session)
    readonly property var hostTokenData: rootObject.sessionHostToken(session)
    readonly property color accentColor: rootObject.launcherEntryAccentColor(session)
    readonly property color currentAccentColor: colorsObject.blue
    // Canonical status color (sessionStatusStyle via the badge helpers): the
    // rail, dot, and chip must all carry the same hue for one state.
    readonly property color statusColor: rootObject.sessionBadgeColor(session)
    readonly property bool closableSurface: showCloseAction && rootObject.sessionHasClosableSurface(session)
    readonly property bool closeActionHovered: interactive
        && closableSurface
        && rowHoverLatched
        && pointInsideItem(Qt.point(sessionRowMouse.mouseX, sessionRowMouse.mouseY), closeActionHitbox)
    readonly property bool isIdle: rootObject.sessionIsIdle(session)
    readonly property bool isBlocked: activityState === "blocked"
    // Set false by hosts whose window is hidden: Item.visible follows the item
    // tree, not window visibility, so a delegate inside a closed PanelWindow
    // still reports visible and its infinite ping would burn wakeups forever.
    property bool surfaceVisible: true
    // Radar ping runs only while the row actually needs a human and is on
    // screen; an off-screen infinite animation would just burn wakeups.
    readonly property bool blockedPingActive: isBlocked && surfaceVisible && sessionRow.visible
    readonly property real idleRowOpacity: isIdle ? (isCurrent ? 0.9 : 0.76) : 1
    readonly property real idleTextOpacity: isIdle ? (isCurrent ? 0.86 : 0.72) : 1
    readonly property real idleChipOpacity: isIdle ? (isCurrent ? 0.9 : 0.76) : 1
    readonly property real toolIconOpacity: hasMotion ? 0.96 : (isIdle ? (isCurrent ? 0.64 : 0.5) : 0.92)
    property bool hasMotion: rootObject.sessionHasMotion(session)
    readonly property var activitySpinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    // Frame comes from the shell root's single shared spinner clock; a private
    // 95ms Timer per row multiplied wakeups across every visible session list.
    readonly property int activitySpinnerFrame: Number(rootObject.activitySpinnerFrame || 0) % activitySpinnerFrames.length
    readonly property int rowHeight: compact ? 48 : 62
    readonly property int railHeight: compact ? (selected ? 30 : 24) : (selected ? 38 : 30)
    readonly property int iconWrapSize: compact ? 28 : 34
    readonly property int iconGlyphSize: compact ? 14 : 16
    readonly property int chipHeight: compact ? 20 : 22
    readonly property int statusIconSize: compact ? 20 : 22
    readonly property bool stoppedNotification: activityState === "stopped"

    readonly property color baseRowColor: isCurrent
        ? (effectiveHovered ? Qt.tint(colorsObject.blueBg, Qt.rgba(1, 1, 1, 0.035)) : colorsObject.blueBg)
        : (selected ? colorsObject.blueBg : (effectiveHovered ? colorsObject.cardAlt : "transparent"))

    implicitHeight: rowHeight
    radius: rootObject.radiusControl
    // Blocked rows get a subtle wash toward redBg so the attention state reads
    // at the row level, not just on the badge.
    color: isBlocked ? Qt.tint(baseRowColor, Qt.rgba(0.99, 0.64, 0.69, 0.08)) : baseRowColor
    border.color: isCurrent
        ? (effectiveHovered ? colorsObject.blue : colorsObject.blueMuted)
        : (selected ? colorsObject.blue : (effectiveHovered ? colorsObject.borderStrong : "transparent"))
    border.width: 1
    opacity: (closePending ? 0.9 : 1) * idleRowOpacity

    Behavior on color {
        ColorAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 220
        }
    }

    Rectangle {
        visible: isCurrent
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: Qt.rgba(1, 1, 1, effectiveHovered ? 0.018 : 0.012)
        border.color: "transparent"
        border.width: 0
    }

    function resetMotionVisuals() {
        sessionToolIconWrap.opacity = toolIconOpacity;
        sessionToolIconWrap.scale = 1;
    }

    function pointInsideItem(point, item) {
        if (!item || !item.visible) {
            return false;
        }
        const localPoint = item.mapFromItem(sessionRow, point.x, point.y);
        return localPoint.x >= 0
            && localPoint.y >= 0
            && localPoint.x <= item.width
            && localPoint.y <= item.height;
    }

    onHasMotionChanged: resetMotionVisuals()
    onInteractiveChanged: {
        if (!interactive) {
            rowHoverLatched = false;
            hoverReleaseTimer.stop();
        }
    }
    Component.onCompleted: resetMotionVisuals()

    Timer {
        id: hoverReleaseTimer
        interval: 120
        repeat: false
        onTriggered: rowHoverLatched = false
    }

    // Status rail: carries the canonical status hue (not the launcher accent)
    // so the state reads at the row edge; idle recedes, active states stay hot.
    Rectangle {
        visible: showAccentRail
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: isCurrent ? (compact ? 22 : 28) : railHeight
        radius: 1
        color: statusColor
        opacity: isIdle ? 0.35 : 0.9

        Behavior on color {
            ColorAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }
        }

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
            radius: rootObject.radiusControl
            color: "transparent"
            border.color: "transparent"
            border.width: 0

            // Radar ping behind the tool icon: blocked is the state that needs
            // a human, so it gets the strongest motion cue (working rows spin).
            Rectangle {
                id: blockedPingRing1
                anchors.centerIn: parent
                width: iconWrapSize
                height: iconWrapSize
                radius: width / 2
                color: "transparent"
                border.color: colorsObject.red
                border.width: 2
                opacity: 0
                visible: sessionRow.blockedPingActive

                SequentialAnimation {
                    running: sessionRow.blockedPingActive
                    loops: Animation.Infinite

                    ParallelAnimation {
                        NumberAnimation {
                            target: blockedPingRing1
                            property: "scale"
                            from: 1.0
                            to: 1.8
                            duration: 1400
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: blockedPingRing1
                            property: "opacity"
                            from: 0.55
                            to: 0
                            duration: 1400
                        }
                    }
                }
            }

            Rectangle {
                id: blockedPingRing2
                anchors.centerIn: parent
                width: iconWrapSize
                height: iconWrapSize
                radius: width / 2
                color: "transparent"
                border.color: colorsObject.red
                border.width: 2
                opacity: 0
                visible: sessionRow.blockedPingActive

                SequentialAnimation {
                    running: sessionRow.blockedPingActive

                    // Offset the second ring so the pings alternate instead of
                    // overlapping into a single thick pulse.
                    PauseAnimation {
                        duration: 300
                    }

                    SequentialAnimation {
                        loops: Animation.Infinite

                        ParallelAnimation {
                            NumberAnimation {
                                target: blockedPingRing2
                                property: "scale"
                                from: 1.0
                                to: 1.8
                                duration: 1400
                                easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                target: blockedPingRing2
                                property: "opacity"
                                from: 0.55
                                to: 0
                                duration: 1400
                            }
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

            // Presence badge: ringed with the panel background so the status
            // dot punches out of whatever the row underneath is doing.
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 1
                anchors.bottomMargin: 1
                width: compact ? 9 : 10
                height: width
                radius: width / 2
                color: statusColor
                border.color: colorsObject.bg
                border.width: 2

                Behavior on color {
                    ColorAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: compact ? 1 : 2

            Text {
                Layout.fillWidth: true
                text: primaryLabel
                color: isCurrent ? colorsObject.text : (selected ? colorsObject.blue : colorsObject.text)
                font.pixelSize: rootObject.fontTitle
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                opacity: idleTextOpacity
            }

            Text {
                Layout.fillWidth: true
                text: secondaryLabel
                color: isCurrent ? colorsObject.textDim : (selected ? colorsObject.textDim : colorsObject.subtle)
                font.pixelSize: compact ? rootObject.fontCaption : rootObject.fontLabel
                elide: Text.ElideRight
                opacity: idleTextOpacity
            }
        }

        Rectangle {
            visible: showHostToken && hostTokenData && rootObject.stringOrEmpty(hostTokenData.label).length > 0
            height: chipHeight
            radius: rootObject.radiusBadge
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
                    width: compact ? 12 : 14
                    height: compact ? 12 : 14
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
                        font.pixelSize: rootObject.fontMicro
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.5
                        font.weight: Font.Bold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: hostTokenData ? rootObject.stringOrEmpty(hostTokenData.label) : ""
                    color: hostTokenData ? hostTokenData.foreground : colorsObject.textDim
                    font.pixelSize: rootObject.fontMicro
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.5
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            visible: showCurrentChip && isCurrent
            height: chipHeight
            radius: rootObject.radiusBadge
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
                font.pixelSize: rootObject.fontMicro
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            visible: rootObject.sessionGitChipVisible(session)
            height: chipHeight
            radius: rootObject.radiusBadge
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
                font.pixelSize: rootObject.fontCaption
                font.weight: Font.Medium
            }
        }

        Rectangle {
            visible: activityLabel.length > 0 || activitySymbol.length > 0
            height: stoppedNotification ? (compact ? 16 : 18) : Math.max(chipHeight, statusIconSize)
            radius: rootObject.radiusBadge
            // Doubled-up tint keeps the chip readable on near-black rows; the
            // status-alpha border ties it to the rail/dot hue.
            color: stoppedNotification
                ? Qt.tint(rootObject.sessionBadgeBackground(session), Qt.rgba(1, 1, 1, isCurrent ? 0.05 : 0.02))
                : Qt.tint(rootObject.sessionBadgeBackground(session), Qt.alpha(statusColor, 0.10))
            border.color: Qt.alpha(statusColor, 0.35)
            border.width: 1
            opacity: idleChipOpacity
            // implicitWidth (not Layout.preferredWidth) so the width driver can
            // carry a Behavior; the RowLayout tracks implicitWidth changes.
            implicitWidth: stoppedNotification
                ? (compact ? 22 : 24)
                : (activityLabel.length > 0
                    ? activityText.implicitWidth + statusIconSize + 15
                    : statusIconSize + 12)

            Behavior on color {
                ColorAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on border.color {
                ColorAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

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
                    font.pixelSize: compact ? rootObject.fontCaption : rootObject.fontLabel
                    font.letterSpacing: 0.4
                    font.weight: Font.DemiBold
                }
            }
        }

        Item {
            id: closeActionHitbox
            visible: closableSurface
            width: 28
            height: 28
            Layout.preferredWidth: width
            Layout.preferredHeight: height

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: rootObject.radiusBadge
                color: closePending ? colorsObject.redBg : (closeActionHovered ? colorsObject.redBg : colorsObject.bg)
                border.color: closePending ? colorsObject.red : (closeActionHovered ? colorsObject.red : colorsObject.lineSoft)
                border.width: 1
                scale: sessionRowMouse.pressed && closeActionHovered ? 0.96 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 90
                        easing.type: Easing.OutQuad
                    }
                }

                Text {
                    visible: !closePending
                    anchors.centerIn: parent
                    text: "×"
                    color: closeActionHovered ? colorsObject.red : (selected ? colorsObject.muted : colorsObject.subtle)
                    font.pixelSize: closeActionHovered ? rootObject.fontBody : rootObject.fontLabel
                    font.weight: closeActionHovered ? Font.Bold : Font.DemiBold
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

        }
    }

    MouseArea {
        id: sessionRowMouse
        z: 10
        anchors.fill: parent
        enabled: interactive
        acceptedButtons: Qt.LeftButton
        hoverEnabled: interactive
        preventStealing: true
        scrollGestureEnabled: false
        cursorShape: closeActionHovered || interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: {
            hoverReleaseTimer.stop();
            rowHoverLatched = true;
        }
        onExited: hoverReleaseTimer.restart()
        onCanceled: hoverReleaseTimer.restart()
        onClicked: function(mouse) {
            if (pointInsideItem(Qt.point(mouse.x, mouse.y), closeActionHitbox)) {
                if (!closePending) {
                    sessionRow.closeRequested();
                }
                return;
            }
            sessionRow.clicked();
        }
    }
}
