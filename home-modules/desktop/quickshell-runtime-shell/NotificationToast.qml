import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets

// One floating notification card. macOS-modeled behavior: slides in from the
// screen edge (the ListView transitions in ToastWindow own entry/exit/restack),
// hovering pauses the expiry countdown, a horizontal swipe flicks it away,
// clicking the body invokes the sender's default action, and senders that
// support it get an inline reply field without leaving the toast.
Rectangle {
    id: toast

    required property var rootObject
    required property var colorsObject
    required property var itemData
    property real preferredWidth: 380
    // Where a swipe-dismiss hands the card to the ListView remove transition.
    property real slideOutX: preferredWidth

    signal dismissRequested(int notificationId)
    signal expireRequested(int notificationId)
    signal actionInvoked(int notificationId, string actionId)
    signal defaultInvoked(int notificationId)
    signal detailRequested(int notificationId)
    signal replySubmitted(int notificationId, string text)
    signal replyStateChanged(int notificationId, bool active)

    readonly property int notificationId: Number(itemData && itemData.id || 0)
    readonly property bool critical: rootObject.notificationIsCritical(itemData)
    readonly property color accentColor: rootObject.notificationAccentColor(itemData)
    readonly property string iconSource: rootObject.notificationResolvedIcon(itemData)
    readonly property string imageSource: rootObject.notificationResolvedImage(itemData)
    readonly property var displayActions: rootObject.notificationDisplayActions(itemData)
    readonly property bool canReply: rootObject.boolOrFalse(itemData && itemData.has_inline_reply)
    readonly property int timeoutMs: rootObject.notificationTimeoutFor(itemData)
    // MultiEffect is shader-based; the software Quick backend (NVIDIA hosts)
    // would render a layered item as nothing at all, so the shadow is gated
    // and those hosts get the 1px dark halo below instead.
    readonly property bool shadowCapable: GraphicsInfo.api !== GraphicsInfo.Software

    property bool replyOpen: false
    readonly property bool countdownPaused: cardHover.hovered || replyOpen || dragArea.drag.active

    // Countdown state lives here (not in a bare Timer interval) so hovering
    // pauses with the remaining time intact and the progress hairline can
    // render it. It restarts only when the sender re-issues the notification
    // (same id, new timestamp), not when unrelated fields change.
    property real countdownTotal: 0
    property real remainingMs: 0
    property double seenTimestamp: -1

    function resetCountdown() {
        countdownTotal = timeoutMs > 0 ? timeoutMs : 0;
        remainingMs = countdownTotal;
    }

    function syncCountdown() {
        // replayed_at is set when a toast is restored after a shell restart or
        // replayed from history, so the countdown restarts without the
        // history timestamp (and the "N min ago" label) being rewritten.
        const ts = Number(itemData && (itemData.replayed_at || itemData.timestamp)) || 0;
        if (ts !== seenTimestamp) {
            seenTimestamp = ts;
            resetCountdown();
        }
    }

    onItemDataChanged: syncCountdown()
    Component.onCompleted: syncCountdown()
    Component.onDestruction: {
        if (replyOpen) {
            toast.replyStateChanged(notificationId, false);
        }
    }

    function setReplyOpen(open) {
        if (replyOpen === open) {
            return;
        }
        replyOpen = open;
        toast.replyStateChanged(notificationId, open);
        if (open) {
            Qt.callLater(function () {
                replyField.forceActiveFocus();
            });
        }
    }

    function submitReply() {
        const text = replyField.text.trim();
        if (!text) {
            return;
        }
        toast.replySubmitted(notificationId, text);
        replyField.text = "";
        setReplyOpen(false);
    }

    width: preferredWidth
    implicitWidth: preferredWidth
    implicitHeight: toastColumn.implicitHeight + 28
    radius: Theme.rad(16)
    color: Theme.toastGlass
    border.color: critical ? Qt.tint(colorsObject.red, Theme.shadowSoft) : (cardHover.hovered ? Theme.borderStrong : Theme.border)
    border.width: 1
    opacity: toast.x > 0 ? Math.max(0.15, 1 - toast.x / Math.max(1, toast.width)) : 1

    Behavior on border.color {
        ColorAnimation {
            duration: 160
        }
    }

    layer.enabled: shadowCapable
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 1.0
        shadowColor: Theme.shadow
        shadowVerticalOffset: 8
        shadowHorizontalOffset: 0
    }

    HoverHandler {
        id: cardHover
    }

    Timer {
        interval: 100
        repeat: true
        running: toast.countdownTotal > 0 && toast.remainingMs > 0 && !toast.countdownPaused && toast.visible
        onTriggered: {
            toast.remainingMs = Math.max(0, toast.remainingMs - 100);
            if (toast.remainingMs <= 0) {
                toast.expireRequested(toast.notificationId);
            }
        }
    }

    // Base layer: click = the sender's default action, horizontal drag =
    // swipe to dismiss. Interactive children sit above and win the press.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        drag.target: toast
        drag.axis: Drag.XAxis
        drag.minimumX: 0
        drag.maximumX: toast.slideOutX
        drag.threshold: 12
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: settleAnim.stop()
        // Right-click dismisses without invoking the sender's default action.
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                toast.dismissRequested(toast.notificationId);
                return;
            }
            toast.defaultInvoked(toast.notificationId);
        }
        onReleased: {
            if (toast.x > toast.width * 0.3) {
                toast.dismissRequested(toast.notificationId);
            } else {
                settleAnim.restart();
            }
        }
        onCanceled: settleAnim.restart()
    }

    NumberAnimation {
        id: settleAnim
        target: toast
        property: "x"
        to: 0
        duration: 320
        easing.type: Easing.OutBack
        easing.overshoot: 1.1
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

    // Critical urgency reads as a red-washed card, not just a colored line.
    Rectangle {
        visible: toast.critical
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: Theme.redWash
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.color: toast.critical ? Theme.edgeHighlight : Theme.elevationSoft
        border.width: 1
    }

    Rectangle {
        visible: toast.critical
        anchors.left: parent.left
        anchors.leftMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - 14
        width: 3
        radius: 2
        color: colorsObject.red
    }

    ColumnLayout {
        id: toastColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                radius: Theme.rad(6)
                color: toast.iconSource !== "" ? "transparent" : rootObject.notificationAvatarFill(itemData)
                border.color: toast.iconSource !== "" ? "transparent" : Theme.edgeHighlightSoft
                border.width: 1

                IconImage {
                    visible: toast.iconSource !== ""
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: toast.iconSource
                    mipmap: true
                }

                Text {
                    font.family: Theme.fontFamily
                    visible: toast.iconSource === ""
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
                color: toast.critical ? colorsObject.red : colorsObject.subtle
                font.pixelSize: Theme.fs(9)
                font.letterSpacing: 0.8
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.maximumWidth: toast.width * 0.5
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

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: Theme.rad(8)
                color: closeMouse.containsMouse ? colorsObject.redBg : Theme.elevationFaint
                border.color: closeMouse.containsMouse ? colorsObject.red : Theme.elevation
                border.width: 1
                opacity: cardHover.hovered || closeMouse.containsMouse ? 1 : 0.35

                Behavior on opacity {
                    NumberAnimation {
                        duration: 140
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    anchors.centerIn: parent
                    text: "×"
                    color: closeMouse.containsMouse ? colorsObject.red : colorsObject.subtle
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toast.dismissRequested(toast.notificationId)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 3

                Text {
                    font.family: Theme.fontFamily
                    Layout.fillWidth: true
                    text: rootObject.notificationHeadline(itemData)
                    color: colorsObject.text
                    font.pixelSize: Theme.fs(13)
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
                    font.pixelSize: Theme.fs(11)
                    lineHeight: 1.2
                    wrapMode: Text.Wrap
                    maximumLineCount: toast.imageSource !== "" ? 3 : 4
                    elide: Text.ElideRight
                    textFormat: rootObject.notificationBodyFormat()
                }
            }

            // macOS-style right-side thumbnail rather than a full-width banner:
            // the card keeps one silhouette whether or not an image arrived.
            Rectangle {
                visible: toast.imageSource !== ""
                Layout.preferredWidth: 54
                Layout.preferredHeight: 54
                Layout.alignment: Qt.AlignTop
                radius: Theme.rad(10)
                color: Theme.elevationFaint
                border.color: Theme.elevation
                border.width: 1
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: toast.imageSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
            }
        }

        RowLayout {
            visible: toast.replyOpen
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: Theme.rad(10)
                color: Theme.elevationFaint
                border.color: replyField.activeFocus ? colorsObject.blueMuted : Theme.elevation
                border.width: 1

                TextField {
                    font.family: Theme.fontFamily
                    id: replyField
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: colorsObject.text
                    placeholderText: rootObject.stringOrEmpty(itemData && itemData.inline_reply_placeholder) || "Reply…"
                    placeholderTextColor: colorsObject.subtle
                    font.pixelSize: Theme.fs(11)
                    background: null
                    padding: 0
                    onAccepted: toast.submitReply()
                    Keys.onEscapePressed: toast.setReplyOpen(false)
                }
            }

            Rectangle {
                Layout.preferredWidth: sendLabel.implicitWidth + 20
                Layout.preferredHeight: 30
                radius: Theme.rad(10)
                color: sendMouse.containsMouse ? colorsObject.blueBg : Theme.elevationFaint
                border.color: sendMouse.containsMouse ? colorsObject.blue : Theme.elevation
                border.width: 1
                scale: sendMouse.pressed ? 0.96 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 90
                        easing.type: Easing.OutQuad
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    id: sendLabel
                    anchors.centerIn: parent
                    text: "Send"
                    color: sendMouse.containsMouse ? colorsObject.blue : colorsObject.text
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: sendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toast.submitReply()
                }
            }
        }

        RowLayout {
            visible: toast.displayActions.length > 0 || toast.canReply
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 8

            Repeater {
                model: toast.displayActions

                delegate: Rectangle {
                    required property var modelData
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: pillLabel.implicitWidth + 22
                    radius: Theme.rad(9)
                    color: pillMouse.containsMouse ? Qt.tint(toast.accentColor, Theme.elevationStrong) : Theme.elevationSoft
                    border.color: pillMouse.containsMouse ? Qt.tint(toast.accentColor, Theme.elevationStrong) : Theme.elevation
                    border.width: 1
                    scale: pillMouse.pressed ? 0.96 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                            easing.type: Easing.OutQuad
                        }
                    }

                    Text {
                        font.family: Theme.fontFamily
                        id: pillLabel
                        anchors.centerIn: parent
                        text: rootObject.notificationActionText(modelData)
                        color: colorsObject.text
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: toast.actionInvoked(toast.notificationId, rootObject.notificationActionIdentifier(modelData))
                    }
                }
            }

            Rectangle {
                visible: toast.canReply && !toast.replyOpen
                Layout.preferredHeight: 26
                Layout.preferredWidth: replyPillLabel.implicitWidth + 22
                radius: Theme.rad(9)
                color: replyPillMouse.containsMouse ? colorsObject.blueBg : Theme.elevationSoft
                border.color: replyPillMouse.containsMouse ? colorsObject.blue : Theme.elevation
                border.width: 1
                scale: replyPillMouse.pressed ? 0.96 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 90
                        easing.type: Easing.OutQuad
                    }
                }

                Text {
                    font.family: Theme.fontFamily
                    id: replyPillLabel
                    anchors.centerIn: parent
                    text: "Reply"
                    color: replyPillMouse.containsMouse ? colorsObject.blue : colorsObject.text
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: replyPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toast.setReplyOpen(true)
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }

    // Expiry countdown hairline. It freezes while hovered — the visible pause
    // is what tells the user the toast will wait for them.
    Rectangle {
        visible: toast.countdownTotal > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.bottomMargin: 6
        height: 2
        radius: 1
        width: (toast.width - 28) * (toast.countdownTotal > 0 ? toast.remainingMs / toast.countdownTotal : 0)
        color: toast.accentColor
        opacity: toast.countdownPaused ? 0.2 : 0.45

        Behavior on width {
            NumberAnimation {
                duration: 110
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }
    }
}
