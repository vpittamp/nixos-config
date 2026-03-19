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
    property alias launcherFieldRef: launcherField
    property alias launcherListRef: launcherList
    id: launcherWindow
    screen: root.primaryScreen
    visible: root.launcherVisible && root.primaryScreen !== null
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-app-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Launchers need deterministic keyboard capture on open.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
        anchors.fill: parent
        color: "#66070b12"

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeLauncher()
        }

        Rectangle {
            id: launcherCard
            anchors.centerIn: parent
            width: Math.min(root.launcherMode === "sessions" && root.activeLauncherSessionEntry() !== null ? 980 : 760, parent.width - 96)
            height: Math.min(560, parent.height - 96)
            radius: 12
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            MouseArea {
                anchors.fill: parent
                onClicked: function (mouse) {
                    mouse.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                anchors.bottomMargin: 16
                spacing: 12

                Text {
                    text: root.launcherTitle()
                    color: colors.text
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: launcherAppsModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "apps" ? colors.blueBg : (launcherAppsModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "apps" ? colors.blue : (launcherAppsModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherAppsModeLabel
                            anchors.centerIn: parent
                            text: "Apps"
                            color: root.launcherMode === "apps" ? colors.blue : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherAppsModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("apps")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherFilesModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "files" ? colors.tealBg : (launcherFilesModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "files" ? colors.teal : (launcherFilesModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherFilesModeLabel
                            anchors.centerIn: parent
                            text: "Files"
                            color: root.launcherMode === "files" ? colors.teal : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherFilesModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("files")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherUrlsModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "urls" ? colors.tealBg : (launcherUrlsModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "urls" ? colors.teal : (launcherUrlsModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherUrlsModeLabel
                            anchors.centerIn: parent
                            text: "URLs"
                            color: root.launcherMode === "urls" ? colors.teal : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherUrlsModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("urls")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherProjectsModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "projects" ? colors.tealBg : (launcherProjectsModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "projects" ? colors.teal : (launcherProjectsModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherProjectsModeLabel
                            anchors.centerIn: parent
                            text: "Projects"
                            color: root.launcherMode === "projects" ? colors.teal : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherProjectsModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("projects")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherRunnerModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "runner" ? colors.orangeBg : (launcherRunnerModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "runner" ? colors.orange : (launcherRunnerModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherRunnerModeLabel
                            anchors.centerIn: parent
                            text: "Runner"
                            color: root.launcherMode === "runner" ? colors.orange : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherRunnerModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("runner")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherSnippetsModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "snippets" ? colors.tealBg : (launcherSnippetsModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "snippets" ? colors.teal : (launcherSnippetsModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherSnippetsModeLabel
                            anchors.centerIn: parent
                            text: "Commands"
                            color: root.launcherMode === "snippets" ? colors.teal : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherSnippetsModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("snippets")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherOnePasswordModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "onepassword" ? colors.accentBg : (launcherOnePasswordModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "onepassword" ? colors.accent : (launcherOnePasswordModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherOnePasswordModeLabel
                            anchors.centerIn: parent
                            text: "1Password"
                            color: root.launcherMode === "onepassword" ? colors.accent : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherOnePasswordModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("onepassword")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherClipboardModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "clipboard" ? colors.amberBg : (launcherClipboardModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "clipboard" ? colors.amber : (launcherClipboardModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherClipboardModeLabel
                            anchors.centerIn: parent
                            text: "Clipboard"
                            color: root.launcherMode === "clipboard" ? colors.amber : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherClipboardModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("clipboard")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherSessionsModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "sessions" ? colors.violetBg : (launcherSessionsModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "sessions" ? colors.violet : (launcherSessionsModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherSessionsModeLabel
                            anchors.centerIn: parent
                            text: "AI Sessions"
                            color: root.launcherMode === "sessions" ? colors.violet : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherSessionsModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("sessions")
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: launcherWindowsModeLabel.implicitWidth + 18
                        height: 26
                        radius: 6
                        color: root.launcherMode === "windows" ? colors.blueWash : (launcherWindowsModeMouse.containsMouse ? colors.cardAlt : colors.card)
                        border.color: root.launcherMode === "windows" ? colors.blueMuted : (launcherWindowsModeMouse.containsMouse ? colors.borderStrong : colors.border)
                        border.width: 1

                        Text {
                            id: launcherWindowsModeLabel
                            anchors.centerIn: parent
                            text: "Windows"
                            color: root.launcherMode === "windows" ? colors.blue : colors.text
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: launcherWindowsModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLauncherMode("windows")
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                TextField {
                    id: launcherField
                    Layout.fillWidth: true
                    focus: root.launcherVisible
                    placeholderText: root.launcherPlaceholderText()
                    color: colors.text
                    font.pixelSize: 18

                    background: Rectangle {
                        radius: 8
                        color: colors.cardAlt
                        border.color: launcherField.activeFocus ? colors.blue : colors.border
                        border.width: 1
                    }

                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 12
                    bottomPadding: 12

                    onTextChanged: {
                        if (!root.launcherNormalizingInput) {
                            root.updateLauncherInput(text);
                        }
                    }

                    Keys.onPressed: function (event) {
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_2) {
                            root.setLauncherMode("urls");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_0) {
                            root.setLauncherMode("files");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_7) {
                            root.setLauncherMode("clipboard");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_8) {
                            root.setLauncherMode("runner");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_9) {
                            root.setLauncherMode("snippets");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_3) {
                            root.setLauncherMode("projects");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_4) {
                            root.setLauncherMode("onepassword");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_5) {
                            root.setLauncherMode("sessions");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_6) {
                            root.setLauncherMode("windows");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_1) {
                            root.setLauncherMode("apps");
                            event.accepted = true;
                            return;
                        }

                        switch (event.key) {
                        case Qt.Key_Escape:
                            root.closeLauncher();
                            event.accepted = true;
                            break;
                        case Qt.Key_Down:
                            root.moveLauncherSelection(1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Up:
                            root.moveLauncherSelection(-1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Tab:
                            root.cycleLauncherMode((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                            event.accepted = true;
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            if (root.launcherMode === "onepassword") {
                                if (event.modifiers & Qt.ControlModifier) {
                                    root.activateSelectedLauncherEntry("otp");
                                } else if (event.modifiers & Qt.ShiftModifier) {
                                    root.activateSelectedLauncherEntry("username");
                                } else {
                                    root.activateSelectedLauncherEntry("password");
                                }
                            } else if (root.launcherMode === "files") {
                                if (event.modifiers & Qt.ControlModifier) {
                                    root.activateSelectedLauncherEntry("opendir");
                                } else {
                                    root.activateSelectedLauncherEntry("open");
                                }
                            } else if (root.launcherMode === "urls") {
                                if (event.modifiers & Qt.ControlModifier) {
                                    root.activateSelectedLauncherEntry("copy");
                                } else if (event.modifiers & Qt.ShiftModifier) {
                                    root.activateSelectedLauncherEntry("browser");
                                } else {
                                    root.activateSelectedLauncherEntry("preferred");
                                }
                            } else if (root.launcherMode === "runner" || root.launcherMode === "snippets") {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    root.activateSelectedLauncherEntry("terminal");
                                } else {
                                    root.activateSelectedLauncherEntry("background");
                                }
                            } else if (root.launcherMode === "clipboard") {
                                root.activateSelectedLauncherEntry("copy");
                            } else {
                                root.activateSelectedLauncherEntry();
                            }
                            event.accepted = true;
                            break;
                        case Qt.Key_D:
                            if (root.launcherMode === "clipboard" && (event.modifiers & Qt.ControlModifier)) {
                                root.activateSelectedLauncherEntry("remove");
                                event.accepted = true;
                            }
                            break;
                        case Qt.Key_W:
                            if (root.launcherMode === "windows" && (event.modifiers & Qt.ControlModifier)) {
                                root.activateSelectedLauncherEntry("close");
                                event.accepted = true;
                            }
                            break;
                        default:
                            break;
                        }
                    }

                    Keys.onReleased: function (event) {
                        switch (event.key) {
                        case Qt.Key_Meta:
                        case Qt.Key_Super_L:
                        case Qt.Key_Super_R:
                            if (root.launcherMode === "sessions" && root.launcherSessionSwitcherActive) {
                                root.commitLauncherSessionSwitch();
                                event.accepted = true;
                            }
                            break;
                        default:
                            break;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.launcherStatusText()
                        color: root.launcherError ? colors.red : colors.subtle
                        font.pixelSize: 10
                    }

                    Text {
                        text: root.launcherHelpText()
                        color: colors.muted
                        font.pixelSize: 10
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: colors.card
                    border.color: colors.border
                    border.width: 1

                    ScriptModel {
                        id: launcherEntriesModel
                        values: root.launcherEntries
                        objectProp: "model_key"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Rectangle {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            Layout.minimumWidth: ((root.launcherMode === "clipboard") || (root.launcherMode === "sessions" && root.activeLauncherSessionEntry() !== null)) && root.launcherEntries.length > 0 ? 280 : 0
                            Layout.preferredWidth: root.launcherMode === "clipboard" && root.launcherEntries.length > 0 ? 340 : (root.launcherMode === "sessions" && root.activeLauncherSessionEntry() !== null ? 360 : -1)
                            radius: 8
                            color: "transparent"
                            border.width: 0

                            ListView {
                                id: launcherList
                                anchors.fill: parent
                                clip: true
                                spacing: 6
                                cacheBuffer: 480
                                preferredHighlightBegin: 6
                                preferredHighlightEnd: Math.max(6, height - 68)
                                highlightRangeMode: ListView.StrictlyEnforceRange
                                highlightMoveDuration: 0
                                model: launcherEntriesModel

                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData
                                    readonly property var entry: modelData
                                    readonly property int itemIndex: index
                                    readonly property bool selected: itemIndex === root.launcherSelectedIndex
                                    readonly property bool projectEntry: root.stringOrEmpty(entry && entry.kind) === "project" || root.stringOrEmpty(entry && entry.kind) === "global"
                                    readonly property bool sessionEntry: root.stringOrEmpty(entry && entry.kind) === "session"
                                    readonly property bool windowEntry: root.stringOrEmpty(entry && entry.kind) === "window"
                                    readonly property bool urlEntry: root.stringOrEmpty(entry && entry.kind) === "url" || root.stringOrEmpty(entry && entry.kind) === "search"
                                    readonly property bool fileEntry: root.stringOrEmpty(entry && entry.kind) === "file"
                                    readonly property bool snippetEntry: root.stringOrEmpty(entry && entry.kind) === "snippet"
                                    readonly property bool onePasswordEntry: root.stringOrEmpty(entry && entry.kind) === "onepassword"
                                    readonly property bool clipboardEntry: root.stringOrEmpty(entry && entry.kind) === "clipboard"
                                    readonly property bool clipboardImageEntry: root.clipboardEntryHasImagePreview(entry)
                                    readonly property string clipboardThumbnailSource: root.clipboardImageSource(entry)
                                    readonly property string activityLabel: sessionEntry ? root.sessionBadgeLabel(entry) : ""
                                    readonly property var hostTokenData: (sessionEntry || windowEntry) ? (entry && entry.host_token ? entry.host_token : null) : null
                                    readonly property color accentColor: root.launcherEntryAccentColor(entry)
                                    property bool hasMotion: sessionEntry ? root.sessionHasMotion(entry) : false

                                    function resetMotionVisuals() {
                                        if (!sessionEntry) {
                                            return;
                                        }
                                        sessionToolIconWrap.opacity = hasMotion ? 0.96 : 0.92;
                                        sessionToolIconWrap.scale = 1;
                                    }

                                    onHasMotionChanged: resetMotionVisuals()
                                    Component.onCompleted: resetMotionVisuals()

                                    width: launcherList.width
                                    height: sessionEntry || projectEntry || windowEntry || clipboardImageEntry || snippetEntry || urlEntry || fileEntry ? 62 : 56
                                    radius: 8
                                    color: sessionEntry ? "transparent" : (selected ? colors.blueBg : (entryMouse.containsMouse ? colors.cardAlt : "transparent"))
                                    border.color: sessionEntry ? "transparent" : (selected ? colors.blue : (entryMouse.containsMouse ? colors.borderStrong : "transparent"))
                                    border.width: sessionEntry ? 0 : 1

                                    RootComponents.SessionRow {
                                        visible: sessionEntry
                                        anchors.fill: parent
                                        rootObject: root
                                        colorsObject: colors
                                        session: entry
                                        selected: parent.selected
                                        hovered: entryMouse.containsMouse
                                        interactive: false
                                        showHostToken: false
                                    }

                                    Rectangle {
                                        visible: !sessionEntry
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 4
                                        height: selected ? 38 : (entryMouse.containsMouse ? 32 : 28)
                                        radius: 3
                                        color: accentColor
                                        opacity: selected ? 1 : (entryMouse.containsMouse ? 0.75 : 0.5)
                                    }

                                    RowLayout {
                                        visible: !sessionEntry
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 8
                                            color: sessionEntry ? (selected ? colors.bg : root.sessionTint(entry)) : (selected ? colors.bg : colors.panelAlt)
                                            border.color: (sessionEntry || windowEntry) ? (selected ? colors.blueMuted : "transparent") : (selected ? colors.blueMuted : colors.lineSoft)
                                            border.width: 1

                                            Image {
                                                visible: clipboardImageEntry && clipboardThumbnailSource !== ""
                                                anchors.fill: parent
                                                anchors.margins: 3
                                                source: clipboardThumbnailSource
                                                fillMode: Image.PreserveAspectCrop
                                                smooth: true
                                                asynchronous: true
                                                cache: false
                                            }

                                            Item {
                                                id: sessionToolIconWrap
                                                visible: sessionEntry
                                                anchors.centerIn: parent
                                                width: 18
                                                height: 18
                                                scale: 1
                                                opacity: hasMotion ? 0.96 : 0.92

                                                ParallelAnimation {
                                                    running: sessionEntry && hasMotion
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
                                                    implicitSize: 16
                                                    source: root.toolIconSource(entry)
                                                    mipmap: true
                                                    opacity: 1
                                                }
                                            }

                                            Image {
                                                visible: !sessionEntry && !projectEntry && !clipboardImageEntry && !windowEntry
                                                anchors.centerIn: parent
                                                width: 20
                                                height: 20
                                                source: root.launcherIconSource(entry)
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                asynchronous: true
                                            }

                                            IconImage {
                                                visible: windowEntry && root.iconSourceFor(entry) !== ""
                                                anchors.centerIn: parent
                                                implicitSize: 20
                                                source: root.iconSourceFor(entry)
                                                mipmap: true
                                                opacity: 0.96
                                            }

                                            Text {
                                                visible: projectEntry || (windowEntry && root.iconSourceFor(entry) === "")
                                                anchors.centerIn: parent
                                                text: projectEntry ? (root.stringOrEmpty(entry && entry.kind) === "global" ? "G" : root.stringOrEmpty(entry && entry.text).slice(0, 1).toUpperCase()) : root.appLabel(entry).slice(0, 1).toUpperCase()
                                                color: selected ? colors.blue : (projectEntry && root.stringOrEmpty(entry && entry.variant) === "ssh" ? colors.orange : colors.textDim)
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                            }

                                            Rectangle {
                                                visible: sessionEntry
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                anchors.rightMargin: 1
                                                anchors.bottomMargin: 1
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: root.sessionBadgeColor(entry)
                                                opacity: 0.85
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                Layout.fillWidth: true
                                                text: clipboardEntry ? root.clipboardEntryTitle(entry) : root.stringOrEmpty(entry && entry.text)
                                                color: selected ? colors.blue : colors.text
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: clipboardEntry ? root.clipboardEntrySubtitle(entry) : (root.stringOrEmpty(entry && entry.subtext) || root.stringOrEmpty(entry && entry.identifier))
                                                color: selected ? colors.textDim : colors.subtle
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            visible: urlEntry
                                            height: 20
                                            radius: 6
                                            color: colors.blueBg
                                            border.color: colors.blue
                                            border.width: 1
                                            Layout.preferredWidth: urlSourceChipText.implicitWidth + 12

                                            Text {
                                                id: urlSourceChipText
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(entry && entry.source).toUpperCase()
                                                color: colors.blue
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: urlEntry && root.stringOrEmpty(entry && entry.matched_pwa_name).length > 0
                                            height: 20
                                            radius: 6
                                            color: colors.tealBg
                                            border.color: colors.teal
                                            border.width: 1
                                            Layout.preferredWidth: urlPwaChipText.implicitWidth + 12

                                            Text {
                                                id: urlPwaChipText
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(entry && entry.matched_pwa_name)
                                                color: colors.teal
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            visible: snippetEntry
                                            height: 20
                                            radius: 6
                                            color: colors.tealBg
                                            border.color: colors.teal
                                            border.width: 1
                                            Layout.preferredWidth: snippetCommandChipText.implicitWidth + 12

                                            Text {
                                                id: snippetCommandChipText
                                                anchors.centerIn: parent
                                                text: "Command"
                                                color: colors.teal
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: snippetEntry && selected
                                            height: 20
                                            radius: 6
                                            color: colors.blueBg
                                            border.color: colors.blue
                                            border.width: 1
                                            Layout.preferredWidth: snippetSelectedChipText.implicitWidth + 12

                                            Text {
                                                id: snippetSelectedChipText
                                                anchors.centerIn: parent
                                                text: "Editing"
                                                color: colors.blue
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: windowEntry && root.stringOrEmpty(entry && entry.project).length > 0
                                            height: 20
                                            radius: 6
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.blue : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: launcherWindowProjectChipText.implicitWidth + 12

                                            Text {
                                                id: launcherWindowProjectChipText
                                                anchors.centerIn: parent
                                                text: root.shortProject(root.stringOrEmpty(entry && entry.project))
                                                color: selected ? colors.blue : colors.textDim
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: windowEntry && !!entry.focused
                                            height: 20
                                            radius: 6
                                            color: colors.accentBg
                                            border.color: colors.accent
                                            border.width: 1
                                            Layout.preferredWidth: launcherWindowFocusedText.implicitWidth + 12

                                            Text {
                                                id: launcherWindowFocusedText
                                                anchors.centerIn: parent
                                                text: "Focused"
                                                color: colors.accent
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry && root.stringOrEmpty(entry && entry.project_label).length > 0
                                            height: 20
                                            radius: 6
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.blue : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: launcherSessionProjectText.implicitWidth + 12

                                            Text {
                                                id: launcherSessionProjectText
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(entry && entry.project_label)
                                                color: selected ? colors.blue : colors.textDim
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry && !!root.sessionIsCurrent(entry)
                                            height: 20
                                            radius: 6
                                            color: colors.accentBg
                                            border.color: colors.accent
                                            border.width: 1
                                            Layout.preferredWidth: launcherSessionCurrentText.implicitWidth + 12

                                            Text {
                                                id: launcherSessionCurrentText
                                                anchors.centerIn: parent
                                                text: "Current"
                                                color: colors.accent
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: projectEntry && root.stringOrEmpty(entry && entry.kind) !== "global"
                                            height: 20
                                            radius: 6
                                            color: root.stringOrEmpty(entry && entry.variant) === "ssh" ? colors.orangeBg : colors.blueWash
                                            border.color: root.stringOrEmpty(entry && entry.variant) === "ssh" ? colors.orange : colors.blueMuted
                                            border.width: 1
                                            Layout.preferredWidth: launcherVariantText.implicitWidth + 12

                                            Text {
                                                id: launcherVariantText
                                                anchors.centerIn: parent
                                                text: root.modeChipLabel(root.stringOrEmpty(entry && entry.variant)).toUpperCase()
                                                color: root.stringOrEmpty(entry && entry.variant) === "ssh" ? colors.orange : colors.blue
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: projectEntry && root.stringOrEmpty(entry && entry.kind) !== "global"
                                            height: 20
                                            radius: 6
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: root.worktreeStatusColor(entry)
                                            border.width: 1
                                            Layout.preferredWidth: launcherProjectStatusText.implicitWidth + 12

                                            Text {
                                                id: launcherProjectStatusText
                                                anchors.centerIn: parent
                                                text: root.worktreeStatusLabel(entry)
                                                color: root.worktreeStatusColor(entry)
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: projectEntry && !!entry.is_active
                                            height: 20
                                            radius: 6
                                            color: colors.accentBg
                                            border.color: colors.accent
                                            border.width: 1
                                            Layout.preferredWidth: launcherCurrentText.implicitWidth + 12

                                            Text {
                                                id: launcherCurrentText
                                                anchors.centerIn: parent
                                                text: "Current"
                                                color: colors.accent
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: onePasswordEntry
                                            height: 20
                                            radius: 6
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.accent : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: onePasswordCategoryText.implicitWidth + 12

                                            Text {
                                                id: onePasswordCategoryText
                                                anchors.centerIn: parent
                                                text: root.onePasswordCategoryLabel(root.stringOrEmpty(entry && entry.category))
                                                color: selected ? colors.accent : colors.textDim
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry
                                            width: 24
                                            height: 24
                                            radius: 8
                                            color: root.sessionBadgeBackground(entry)
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.sessionBadgeSymbol(entry)
                                                color: root.sessionBadgeColor(entry)
                                                font.pixelSize: 14
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry && activityLabel.length > 0
                                            height: 18
                                            radius: 6
                                            color: root.sessionBadgeBackground(entry)
                                            border.color: "transparent"
                                            border.width: 0
                                            Layout.preferredWidth: launcherSessionActivityText.implicitWidth + 14

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 5
                                                anchors.rightMargin: 5
                                                spacing: 4

                                                Rectangle {
                                                    width: 5
                                                    height: 5
                                                    radius: 3
                                                    color: root.sessionBadgeColor(entry)
                                                }

                                                Text {
                                                    id: launcherSessionActivityText
                                                    text: activityLabel
                                                    color: root.sessionBadgeColor(entry)
                                                    font.pixelSize: 7
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        Rectangle {
                                            visible: clipboardEntry && root.launcherEntryHasState(entry, "pinned")
                                            height: 20
                                            radius: 6
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.amber : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: clipboardPinnedText.implicitWidth + 12

                                            Text {
                                                id: clipboardPinnedText
                                                anchors.centerIn: parent
                                                text: "Pinned"
                                                color: selected ? colors.amber : colors.textDim
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        RowLayout {
                                            visible: windowEntry && Number(entry.ai_session_count || 0) > 0
                                            spacing: 4

                                            Repeater {
                                                model: root.windowSessionIcons(entry)

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var session: modelData
                                                    width: 20
                                                    height: 20
                                                    radius: 6
                                                    color: root.sessionTint(session)
                                                    border.color: "transparent"
                                                    border.width: 0

                                                    Rectangle {
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.rightMargin: -1
                                                        anchors.bottomMargin: -1
                                                        width: 9
                                                        height: 9
                                                        radius: 5
                                                        color: root.sessionAccentColor(session)
                                                        border.color: "transparent"
                                                        border.width: 0
                                                        opacity: root.sessionHasMotion(session) ? 1 : 0.85
                                                    }

                                                    IconImage {
                                                        anchors.centerIn: parent
                                                        implicitSize: 13
                                                        source: root.toolIconSource(session)
                                                        mipmap: true
                                                        opacity: root.sessionIsCurrent(session) ? 1 : 0.94
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            mouse.accepted = true;
                                                            root.focusSession(session);
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                visible: root.windowSessionOverflowCount(entry) > 0
                                                width: visible ? launcherWindowOverflowText.implicitWidth + 10 : 0
                                                height: 18
                                                radius: 6
                                                color: colors.bg
                                                border.color: "transparent"
                                                border.width: 0

                                                Text {
                                                    id: launcherWindowOverflowText
                                                    anchors.centerIn: parent
                                                    text: "+" + String(root.windowSessionOverflowCount(entry))
                                                    color: colors.subtle
                                                    font.pixelSize: 8
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        Rectangle {
                                            visible: windowEntry
                                            width: 18
                                            height: 18
                                            radius: 6
                                            color: launcherWindowCloseMouse.containsMouse ? colors.redBg : colors.bg
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                anchors.centerIn: parent
                                                text: "×"
                                                color: launcherWindowCloseMouse.containsMouse ? colors.red : (entry.focused ? colors.muted : colors.subtle)
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: launcherWindowCloseMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    mouse.accepted = true;
                                                    if (itemIndex >= 0) {
                                                        root.updateLauncherPointerSelection(itemIndex);
                                                        root.activateLauncherEntry(root.launcherEntries[itemIndex], "close");
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: entryMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onPositionChanged: root.updateLauncherPointerSelection(itemIndex)
                                        onEntered: {
                                            if (root.launcherPointerSelectionEnabled) {
                                                root.updateLauncherPointerSelection(itemIndex);
                                            }
                                        }
                                        onClicked: {
                                            root.updateLauncherPointerSelection(itemIndex);
                                            root.activateLauncherEntry(entry);
                                        }
                                    }
                                }

                                onCountChanged: {
                                    if (count > 0 && root.launcherSelectedIndex >= count) {
                                        root.launcherSelectedIndex = count - 1;
                                        return;
                                    }
                                    root.syncLauncherListSelection();
                                }
                            }
                        }

                        Rectangle {
                            id: launcherSessionPreviewPane
                            visible: root.launcherMode === "sessions" && root.activeLauncherSessionEntry() !== null
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            Layout.minimumWidth: 320
                            radius: 8
                            color: colors.cardAlt
                            border.color: colors.lineSoft
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 14
                                anchors.bottomMargin: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.sessionPreviewTitle()
                                        color: colors.text
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        height: 20
                                        radius: 6
                                        color: boolOrFalse(root.sessionPreview.is_live) ? colors.accentBg : (boolOrFalse(root.sessionPreview.is_remote) ? colors.orangeBg : (root.stringOrEmpty(root.sessionPreview.status) === "error" ? colors.redBg : colors.panelAlt))
                                        border.color: boolOrFalse(root.sessionPreview.is_live) ? colors.accent : (boolOrFalse(root.sessionPreview.is_remote) ? colors.orange : (root.stringOrEmpty(root.sessionPreview.status) === "error" ? colors.red : colors.border))
                                        border.width: 1
                                        Layout.preferredWidth: previewSessionBadgeText.implicitWidth + 12

                                        Text {
                                            id: previewSessionBadgeText
                                            anchors.centerIn: parent
                                            text: root.sessionPreviewBadgeText()
                                            color: boolOrFalse(root.sessionPreview.is_live) ? colors.accent : (boolOrFalse(root.sessionPreview.is_remote) ? colors.orange : (root.stringOrEmpty(root.sessionPreview.status) === "error" ? colors.red : colors.textDim))
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.sessionPreviewSubtitle()
                                    color: colors.subtle
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        visible: root.stringOrEmpty(root.sessionPreview.session_phase_label || root.sessionPreview.session_phase).length > 0
                                        height: 20
                                        radius: 6
                                        color: colors.panelAlt
                                        border.color: colors.border
                                        border.width: 1
                                        Layout.preferredWidth: previewPhaseText.implicitWidth + 12

                                        Text {
                                            id: previewPhaseText
                                            anchors.centerIn: parent
                                            text: root.stringOrEmpty(root.sessionPreview.session_phase_label || root.sessionPreview.session_phase)
                                            color: colors.textDim
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        visible: root.stringOrEmpty(root.sessionPreview.turn_owner_label || root.sessionPreview.turn_owner).length > 0
                                        height: 20
                                        radius: 6
                                        color: root.sessionPreviewOwnerChipBackground()
                                        border.color: root.sessionPreviewOwnerChipBorder()
                                        border.width: 1
                                        Layout.preferredWidth: previewOwnerText.implicitWidth + 12

                                        Text {
                                            id: previewOwnerText
                                            anchors.centerIn: parent
                                            text: root.stringOrEmpty(root.sessionPreview.turn_owner_label || root.sessionPreview.turn_owner)
                                            color: root.sessionPreviewOwnerChipColor()
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        visible: root.stringOrEmpty(root.sessionPreview.activity_substate_label || root.sessionPreview.activity_substate).length > 0
                                        height: 20
                                        radius: 6
                                        color: colors.panelAlt
                                        border.color: colors.lineSoft
                                        border.width: 1
                                        Layout.preferredWidth: previewSubstateText.implicitWidth + 12

                                        Text {
                                            id: previewSubstateText
                                            anchors.centerIn: parent
                                            text: root.stringOrEmpty(root.sessionPreview.activity_substate_label || root.sessionPreview.activity_substate)
                                            color: colors.textDim
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        visible: root.sessionPreviewFollowChipVisible()
                                        height: 20
                                        radius: 6
                                        color: root.sessionPreviewFollowChipBackground()
                                        border.color: root.sessionPreviewFollowChipColor()
                                        border.width: 1
                                        Layout.preferredWidth: previewFollowText.implicitWidth + 14

                                        Text {
                                            id: previewFollowText
                                            anchors.centerIn: parent
                                            text: root.sessionPreviewFollowChipText()
                                            color: root.sessionPreviewFollowChipColor()
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: root.sessionPreviewFollowChipVisible() && (!root.sessionPreviewAutoFollow || root.sessionPreviewHasUnseenOutput)
                                            hoverEnabled: enabled
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.resumeSessionPreviewFollow()
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: colors.panel
                                    border.color: colors.border
                                    border.width: 1

                                    Flickable {
                                        id: sessionPreviewFlick
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        clip: true
                                        contentWidth: width
                                        contentHeight: Math.max(height, sessionPreviewText.paintedHeight + 4)
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: contentHeight > height
                                        onContentYChanged: {
                                            if (root.sessionPreviewProgrammaticScroll) {
                                                return;
                                            }
                                            const nearEnd = contentY >= Math.max(0, contentHeight - height - 24);
                                            root.sessionPreviewAutoFollow = nearEnd || contentHeight <= height + 4;
                                            if (root.sessionPreviewAutoFollow) {
                                                root.sessionPreviewHasUnseenOutput = false;
                                            }
                                        }

                                        ScrollBar.vertical: ScrollBar {
                                            policy: ScrollBar.AsNeeded
                                        }

                                        TextEdit {
                                            id: sessionPreviewText
                                            width: sessionPreviewFlick.width
                                            height: Math.max(sessionPreviewFlick.height, paintedHeight + 4)
                                            readOnly: true
                                            selectByMouse: true
                                            textFormat: TextEdit.PlainText
                                            text: root.sessionPreviewBody()
                                            wrapMode: TextEdit.NoWrap
                                            color: root.stringOrEmpty(root.sessionPreview.status) === "error" ? colors.red : colors.text
                                            selectionColor: colors.blueWash
                                            selectedTextColor: colors.text
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: launcherClipboardPreviewPane
                            readonly property var previewEntry: root.activeClipboardEntry()
                            readonly property string previewType: root.stringOrEmpty(previewEntry && previewEntry.preview_type).toLowerCase()
                            readonly property string previewImageSource: root.clipboardImageSource(previewEntry)
                            readonly property string previewBody: root.clipboardPreviewBody(previewEntry)
                            visible: root.launcherMode === "clipboard" && previewEntry !== null
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            Layout.minimumWidth: 260
                            radius: 8
                            color: colors.cardAlt
                            border.color: colors.lineSoft
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 14
                                anchors.bottomMargin: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.clipboardPreviewTitle(launcherClipboardPreviewPane.previewEntry)
                                        color: colors.text
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: root.launcherEntryHasState(launcherClipboardPreviewPane.previewEntry, "pinned")
                                        height: 20
                                        radius: 6
                                        color: colors.panelAlt
                                        border.color: colors.amber
                                        border.width: 1
                                        Layout.preferredWidth: previewPinnedText.implicitWidth + 12

                                        Text {
                                            id: previewPinnedText
                                            anchors.centerIn: parent
                                            text: "Pinned"
                                            color: colors.amber
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.clipboardEntrySubtitle(launcherClipboardPreviewPane.previewEntry)
                                    color: colors.subtle
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: colors.panel
                                    border.color: colors.border
                                    border.width: 1

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: 10

                                        Image {
                                            visible: launcherClipboardPreviewPane.previewImageSource !== ""
                                            anchors.fill: parent
                                            source: launcherClipboardPreviewPane.previewImageSource
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            asynchronous: true
                                            cache: false
                                        }

                                        ScrollView {
                                            visible: launcherClipboardPreviewPane.previewImageSource === "" && launcherClipboardPreviewPane.previewBody !== ""
                                            anchors.fill: parent
                                            clip: true

                                            TextArea {
                                                readOnly: true
                                                selectByMouse: true
                                                wrapMode: TextEdit.Wrap
                                                text: launcherClipboardPreviewPane.previewBody
                                                color: colors.text
                                                selectionColor: colors.blueWash
                                                selectedTextColor: colors.text
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 11
                                                background: null
                                            }
                                        }

                                        Text {
                                            visible: launcherClipboardPreviewPane.previewImageSource === "" && launcherClipboardPreviewPane.previewBody === ""
                                            anchors.centerIn: parent
                                            text: "No preview available"
                                            color: colors.subtle
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: !root.launcherLoading && root.launcherEntries.length === 0
                        width: parent.width - 40
                        height: 72
                        radius: 12
                        color: colors.cardAlt
                        border.color: colors.lineSoft
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.launcherEmptyText()
                            color: root.launcherError ? colors.red : colors.subtle
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
