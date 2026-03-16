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

    screen: toastScreen
    visible: toastScreen !== null && root.notificationsBackendNative() && toastItems.length > 0
    color: "transparent"
    anchors.top: true
    anchors.right: true
    implicitWidth: toastContentWidth + toastRightInset + toastOuterMargin
    implicitHeight: toastTopInset + toastColumn.implicitHeight + toastOuterMargin
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-runtime-notifications-" + (toastOutputName || "screen")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        id: toastColumn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: toastWindow.toastTopInset
        anchors.rightMargin: toastWindow.toastRightInset
        spacing: 10

        Repeater {
            model: toastWindow.toastItems

            delegate: RootComponents.NotificationToast {
                required property var modelData
                rootObject: root
                colorsObject: colors
                itemData: modelData
                preferredWidth: toastWindow.toastContentWidth
                onDismissRequested: root.dismissNotification(notificationId)
                onExpireRequested: root.expireNotification(notificationId)
                onActionInvoked: root.invokeNotificationAction(notificationId, actionId)
                onDefaultInvoked: root.markNotificationRead(notificationId)
                onDetailRequested: root.showNotificationDetail(notificationId)
            }
        }
    }
}
