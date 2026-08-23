import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import ".." as RootComponents

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    id: toastWindow
    required property var modelData
    readonly property var toastScreen: modelData
    readonly property string toastOutputName: root.screenOutputName(toastScreen)
    readonly property var toastItems: root.toastItemsForOutput(toastOutputName)
    readonly property real toastOuterMargin: root.notificationToastOuterMargin()
    readonly property real toastTopInset: root.notificationToastTopInset()
    readonly property real toastRightInset: root.notificationToastRightInset(toastOutputName)
    readonly property real toastContentWidth: root.notificationToastWidthForScreen(toastScreen, toastOutputName)

    // Distance that carries a delegate fully past the window's right edge.
    readonly property real slideOffscreenX: toastContentWidth + toastRightInset

    // The id of the toast whose inline-reply field is open, if any. Keyboard
    // focus is only requested from the compositor while a reply is active —
    // a passive toast must never steal typing from the focused window.
    property int activeReplyId: 0

    readonly property bool shouldShow: toastScreen !== null && root.notificationsBackendNative() && toastItems.length > 0

    // The window is full-height with an input mask over just the toast stack,
    // so it never resizes mid-animation and exit transitions get room to play.
    // The grace timer keeps it mapped long enough for the last exit to finish.
    screen: toastScreen
    visible: shouldShow || exitGrace.running
    onShouldShowChanged: {
        if (!shouldShow) {
            exitGrace.restart();
        }
    }
    color: "transparent"
    anchors.top: true
    anchors.right: true
    anchors.bottom: true
    implicitWidth: toastContentWidth + toastRightInset + toastOuterMargin
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    focusable: activeReplyId !== 0
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-runtime-notifications-" + (toastOutputName || "screen")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: activeReplyId !== 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: toastList
    }

    Timer {
        id: exitGrace
        interval: 400
        repeat: false
    }

    ScriptModel {
        id: toastModel
        // Diffing by id keeps delegates alive across feed rebuilds: countdown
        // timers, hover state, and in-flight animations survive unrelated
        // notifications arriving, and an app replacing a notification by id
        // updates the existing card in place instead of respawning it.
        objectProp: "id"
        values: toastWindow.toastItems
    }

    ListView {
        id: toastList
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: toastWindow.toastTopInset
        anchors.rightMargin: toastWindow.toastRightInset
        width: toastWindow.toastContentWidth
        height: Math.min(contentHeight, toastWindow.height - toastWindow.toastTopInset - toastWindow.toastOuterMargin)
        spacing: 10
        interactive: false
        clip: false
        model: toastModel

        add: Transition {
            NumberAnimation {
                properties: "x"
                from: toastWindow.slideOffscreenX
                duration: 420
                easing.type: Easing.OutExpo
            }
        }

        populate: Transition {
            NumberAnimation {
                properties: "x"
                from: toastWindow.slideOffscreenX
                duration: 420
                easing.type: Easing.OutExpo
            }
        }

        remove: Transition {
            NumberAnimation {
                properties: "x"
                to: toastWindow.slideOffscreenX
                duration: 260
                easing.type: Easing.InCubic
            }
        }

        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: 340
                easing.type: Easing.OutCubic
            }
        }

        delegate: RootComponents.NotificationToast {
            required property var modelData
            rootObject: root
            colorsObject: colors
            itemData: modelData
            preferredWidth: toastWindow.toastContentWidth
            slideOutX: toastWindow.slideOffscreenX
            onDismissRequested: (notificationId) => root.dismissNotification(notificationId)
            onExpireRequested: (notificationId) => root.expireNotification(notificationId)
            onActionInvoked: (notificationId, actionId) => root.invokeNotificationAction(notificationId, actionId)
            onDefaultInvoked: (notificationId) => root.invokeNotificationDefault(notificationId)
            onDetailRequested: (notificationId) => root.showNotificationDetail(notificationId)
            onReplySubmitted: (notificationId, text) => root.sendNotificationReply(notificationId, text)
            onReplyStateChanged: (notificationId, active) => {
                if (active) {
                    toastWindow.activeReplyId = notificationId;
                } else if (toastWindow.activeReplyId === notificationId) {
                    toastWindow.activeReplyId = 0;
                }
            }
        }
    }
}
