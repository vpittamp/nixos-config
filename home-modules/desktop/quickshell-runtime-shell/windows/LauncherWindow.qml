import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import ".." as RootComponents
import "root:/"

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    property alias launcherFieldRef: launcherField
    property alias launcherListRef: launcherList
    property alias sessionPreviewFlickRef: sessionPreviewFlick
    id: launcherWindow
    screen: root.activeScreen
    visible: root.launcherVisible
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
        color: Theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeLauncher()
        }

        Rectangle {
            id: launcherCard
            // The space the on-screen keyboard is NOT using. Keyed to the live
            // keyboard state rather than to touch mode: the keyboard only
            // appears when a finger asks for it (field tap, chip, gesture), and
            // while it is down the card gets the full screen back. wvkbd claims
            // the bottom 260 logical px when up.
            readonly property int oskReserve: root.oskVisible ? 260 : 0
            readonly property int availableHeight: parent.height - oskReserve
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Math.round(oskReserve / 2)
            width: Math.min(root.launcherMode === "sessions" && root.activeLauncherSessionEntry() !== null ? 980 : 760, parent.width - 96)
            // The 96px breathing margin is a luxury of large screens; with the
            // keyboard up on a small logical desktop it is the difference
            // between showing results and showing less than one, so it shrinks
            // to 32 before the results do.
            height: Math.min(560, availableHeight - (availableHeight > 656 ? 96 : 32))

            Behavior on height {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }
            radius: Theme.rad(12)
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
                    font.family: Theme.fontFamily
                    text: root.launcherTitle()
                    color: colors.text
                    font.pixelSize: Theme.fs(16)
                    font.weight: Font.DemiBold
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.launcherVisibleModesModel

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var meta: modelData
                            readonly property bool selected: root.launcherMode === root.stringOrEmpty(meta && meta.id)
                            property bool hovered: false
                            readonly property string iconSrc: root.iconSource(root.stringOrEmpty(meta && meta.icon), root.stringOrEmpty(meta && meta.iconFile))

                            // Touch mode: 26 logical is ~5mm even after the
                            // scale bump — a chip you tap to change modes has
                            // to take a fingertip.
                            width: modePillRow.implicitWidth + (root.touchModeActive ? 24 : 18)
                            height: root.touchModeActive ? 34 : 26
                            radius: Theme.rad(6)
                            color: selected ? root.themeColor(root.stringOrEmpty(meta && meta.accentBgKey), colors.cardAlt) : (hovered ? colors.cardAlt : colors.card)
                            border.color: selected ? root.themeColor(root.stringOrEmpty(meta && meta.accentColorKey), colors.borderStrong) : (hovered ? colors.borderStrong : colors.border)
                            border.width: 1

                            RowLayout {
                                id: modePillRow
                                anchors.centerIn: parent
                                spacing: 6

                                IconImage {
                                    visible: iconSrc !== ""
                                    implicitSize: 12
                                    source: iconSrc
                                    mipmap: true
                                    opacity: selected ? 1 : 0.92
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    visible: iconSrc === ""
                                    text: root.stringOrEmpty(meta && meta.fallbackGlyph)
                                    color: selected ? root.themeColor(root.stringOrEmpty(meta && meta.accentColorKey), colors.text) : colors.textDim
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.Bold
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    text: root.stringOrEmpty(meta && meta.label)
                                    color: selected ? root.themeColor(root.stringOrEmpty(meta && meta.accentColorKey), colors.text) : colors.text
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: parent.hovered = true
                                onExited: parent.hovered = false
                                onClicked: root.setLauncherMode(root.stringOrEmpty(meta && meta.id))
                            }
                        }
                    }
                }

                TextField {
                    font.family: Theme.fontFamily
                    id: launcherField
                    Layout.fillWidth: true
                    focus: root.launcherVisible
                    placeholderText: root.launcherPlaceholderText()
                    color: colors.text
                    font.pixelSize: Theme.fs(18)

                    // A finger tapping the text bar is the request for a
                    // keyboard — the tablet convention. Touch-only, so Meta+D
                    // plus physical typing never sees the OSK; the field is
                    // focused either way, which is why focus alone cannot be
                    // the trigger.
                    TapHandler {
                        acceptedDevices: PointerDevice.TouchScreen
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.oskFieldTouched()
                    }

                    background: Rectangle {
                        radius: Theme.rad(8)
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
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_6) {
                            root.setLauncherMode("keys");
                            event.accepted = true;
                            return;
                        }
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_3) {
                            root.setLauncherMode("themes");
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
                            if ((root.launcherMode === "windows" || root.launcherMode === "running") && (event.modifiers & Qt.ControlModifier)) {
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
                        case Qt.Key_Alt:
                        case Qt.Key_AltGr:
                            if (root.launcherMode === "windows" && root.launcherWindowSwitcherActive) {
                                root.commitLauncherWindowSwitch();
                                event.accepted = true;
                            } else if (root.launcherMode === "running" && root.launcherRunningSwitcherActive) {
                                root.commitLauncherRunningSwitch();
                                event.accepted = true;
                            }
                            break;
                        default:
                            break;
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? implicitHeight : 0
                    width: parent.width
                    spacing: 8
                    visible: root.launcherMode === "apps"

                    Repeater {
                        model: root.launcherAppFiltersModel

                        delegate: Rectangle {
                            required property var modelData
                            readonly property var filterMeta: modelData
                            readonly property bool selected: root.launcherAppFilter === root.stringOrEmpty(filterMeta && filterMeta.id)
                            property bool hovered: false
                            readonly property string iconSrc: root.iconSource(root.stringOrEmpty(filterMeta && filterMeta.icon), "")

                            height: root.touchModeActive ? 32 : 24
                            radius: Theme.rad(6)
                            color: selected ? colors.blueBg : (hovered ? colors.cardAlt : colors.card)
                            border.color: selected ? colors.blue : (hovered ? colors.borderStrong : colors.border)
                            border.width: 1
                            width: filterChipRow.implicitWidth + 14

                            RowLayout {
                                id: filterChipRow
                                anchors.centerIn: parent
                                spacing: 5

                                IconImage {
                                    visible: iconSrc !== ""
                                    implicitSize: 11
                                    source: iconSrc
                                    mipmap: true
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    visible: iconSrc === ""
                                    text: root.stringOrEmpty(filterMeta && filterMeta.fallbackGlyph)
                                    color: selected ? colors.blue : colors.textDim
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.Bold
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    text: root.stringOrEmpty(filterMeta && filterMeta.label)
                                    color: selected ? colors.blue : colors.text
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: parent.hovered = true
                                onExited: parent.hovered = false
                                onClicked: root.setLauncherAppFilter(root.stringOrEmpty(filterMeta && filterMeta.id))
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                        text: root.launcherStatusText()
                        color: root.launcherError ? colors.red : colors.subtle
                        font.pixelSize: Theme.fs(10)
                    }

                    Text {
                        font.family: Theme.fontFamily
                        text: root.launcherHelpText()
                        color: colors.muted
                        font.pixelSize: Theme.fs(10)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.rad(10)
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
                            radius: Theme.rad(8)
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
                                highlightRangeMode: root.launcherSelectionMode === "initial" ? ListView.NoHighlightRange : ListView.StrictlyEnforceRange
                                highlightMoveDuration: 0
                                interactive: root.launcherPointerInputReady
                                model: launcherEntriesModel

                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData
                                    readonly property var entry: modelData
                                    readonly property int itemIndex: index
                                    readonly property bool selected: itemIndex === root.launcherSelectedIndex
                                    readonly property bool sessionEntry: root.stringOrEmpty(entry && entry.kind) === "session"
                                    readonly property bool windowEntry: root.stringOrEmpty(entry && entry.kind) === "window"
                                    readonly property bool urlEntry: root.stringOrEmpty(entry && entry.kind) === "url" || root.stringOrEmpty(entry && entry.kind) === "search"
                                    readonly property bool fileEntry: root.stringOrEmpty(entry && entry.kind) === "file"
                                    readonly property bool snippetEntry: root.stringOrEmpty(entry && entry.kind) === "snippet"
                                    readonly property bool onePasswordEntry: root.stringOrEmpty(entry && entry.kind) === "onepassword"
                                    readonly property bool clipboardEntry: root.stringOrEmpty(entry && entry.kind) === "clipboard"
                                    readonly property bool appEntry: root.stringOrEmpty(entry && entry.kind) === "app"
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
                                        sessionToolIconWrap.opacity = 0.92;
                                        sessionToolIconWrap.scale = 1;
                                    }

                                    onHasMotionChanged: resetMotionVisuals()
                                    Component.onCompleted: resetMotionVisuals()

                                    width: launcherList.width
                                    height: sessionEntry || windowEntry || clipboardImageEntry || snippetEntry || urlEntry || fileEntry ? 62 : 56
                                    radius: Theme.rad(8)
                                    clip: true
                                    color: sessionEntry ? "transparent" : (selected ? colors.blueBg : (entryMouse.containsMouse ? colors.cardAlt : "transparent"))
                                    border.color: sessionEntry ? "transparent" : (selected ? colors.blue : (entryMouse.containsMouse ? colors.borderStrong : "transparent"))
                                    border.width: sessionEntry ? 0 : 1

                                    RootComponents.SessionRow {
                                        visible: sessionEntry
                                        anchors.fill: parent
                                        rootObject: root
                                        colorsObject: colors
                                        surfaceVisible: root.launcherVisible
                                        session: entry
                                        selected: parent.selected
                                        hovered: entryMouse.containsMouse
                                        currentOverrideSet: true
                                        currentOverride: root.boolOrFalse(entry && entry.row_current)
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
                                        id: contentRow
                                        visible: !sessionEntry
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 16
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: Theme.rad(8)
                                            color: sessionEntry ? "transparent" : (selected ? colors.bg : colors.panelAlt)
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
                                                opacity: 0.92

                                                IconImage {
                                                    anchors.centerIn: parent
                                                    implicitSize: 16
                                                    source: root.toolIconSource(entry)
                                                    mipmap: true
                                                    opacity: 1
                                                }
                                            }

                                            IconImage {
                                                visible: !sessionEntry && !clipboardImageEntry && !windowEntry
                                                anchors.centerIn: parent
                                                implicitSize: 20
                                                source: root.launcherIconSource(entry)
                                                mipmap: true
                                                opacity: 0.96
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
                                                font.family: Theme.fontFamily
                                                visible: windowEntry && root.iconSourceFor(entry) === ""
                                                anchors.centerIn: parent
                                                text: root.appLabel(entry).slice(0, 1).toUpperCase()
                                                color: selected ? colors.blue : colors.textDim
                                                font.pixelSize: Theme.fs(11)
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
                                                font.family: Theme.fontFamily
                                                Layout.fillWidth: true
                                                text: clipboardEntry ? root.clipboardEntryTitle(entry) : root.stringOrEmpty(entry && entry.text)
                                                color: selected ? colors.blue : colors.text
                                                font.pixelSize: Theme.fs(13)
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                font.family: Theme.fontFamily
                                                Layout.fillWidth: true
                                                text: clipboardEntry ? root.clipboardEntrySubtitle(entry) : (root.stringOrEmpty(entry && entry.subtext) || root.stringOrEmpty(entry && entry.identifier))
                                                color: selected ? colors.textDim : colors.subtle
                                                font.pixelSize: Theme.fs(10)
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            visible: urlEntry
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: colors.blueBg
                                            border.color: colors.blue
                                            border.width: 1
                                            Layout.preferredWidth: urlSourceChipText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: urlSourceChipText
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(entry && entry.source).toUpperCase()
                                                color: colors.blue
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: urlEntry && root.stringOrEmpty(entry && entry.matched_pwa_name).length > 0
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: colors.tealBg
                                            border.color: colors.teal
                                            border.width: 1
                                            Layout.preferredWidth: urlPwaChipText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: urlPwaChipText
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(entry && entry.matched_pwa_name)
                                                color: colors.teal
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            visible: snippetEntry
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: colors.tealBg
                                            border.color: colors.teal
                                            border.width: 1
                                            Layout.preferredWidth: snippetCommandChipText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: snippetCommandChipText
                                                anchors.centerIn: parent
                                                text: "Command"
                                                color: colors.teal
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: snippetEntry && selected
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: colors.blueBg
                                            border.color: colors.blue
                                            border.width: 1
                                            Layout.preferredWidth: snippetSelectedChipText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: snippetSelectedChipText
                                                anchors.centerIn: parent
                                                text: "Editing"
                                                color: colors.blue
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: windowEntry && root.stringOrEmpty(entry && entry.project).length > 0
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.blue : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: launcherWindowProjectChipText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: launcherWindowProjectChipText
                                                anchors.centerIn: parent
                                                text: root.shortProject(root.stringOrEmpty(entry && entry.project))
                                                color: selected ? colors.blue : colors.textDim
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: windowEntry && !!entry.focused
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: colors.accentBg
                                            border.color: colors.accent
                                            border.width: 1
                                            Layout.preferredWidth: launcherWindowFocusedText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: launcherWindowFocusedText
                                                anchors.centerIn: parent
                                                text: "Focused"
                                                color: colors.accent
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry && root.stringOrEmpty(entry && entry.project_label).length > 0
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.blue : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: launcherSessionProjectText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: launcherSessionProjectText
                                                anchors.centerIn: parent
                                                text: root.stringOrEmpty(entry && entry.project_label)
                                                color: selected ? colors.blue : colors.textDim
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry && !!root.sessionIsCurrent(entry)
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: colors.accentBg
                                            border.color: colors.accent
                                            border.width: 1
                                            Layout.preferredWidth: launcherSessionCurrentText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: launcherSessionCurrentText
                                                anchors.centerIn: parent
                                                text: "Current"
                                                color: colors.accent
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: onePasswordEntry
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.accent : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: onePasswordCategoryText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: onePasswordCategoryText
                                                anchors.centerIn: parent
                                                text: root.onePasswordCategoryLabel(root.stringOrEmpty(entry && entry.category))
                                                color: selected ? colors.accent : colors.textDim
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry
                                            width: 24
                                            height: 24
                                            radius: Theme.rad(8)
                                            color: root.sessionBadgeBackground(entry)
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                font.family: Theme.fontFamily
                                                anchors.centerIn: parent
                                                text: root.sessionBadgeSymbol(entry)
                                                color: root.sessionBadgeColor(entry)
                                                font.pixelSize: Theme.fs(14)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: sessionEntry && activityLabel.length > 0
                                            height: 18
                                            radius: Theme.rad(6)
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
                                                    font.family: Theme.fontFamily
                                                    id: launcherSessionActivityText
                                                    text: activityLabel
                                                    color: root.sessionBadgeColor(entry)
                                                    font.pixelSize: Theme.fs(7)
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        Rectangle {
                                            visible: clipboardEntry && root.launcherEntryHasState(entry, "pinned")
                                            height: 20
                                            radius: Theme.rad(6)
                                            color: selected ? colors.bg : colors.panelAlt
                                            border.color: selected ? colors.amber : colors.lineSoft
                                            border.width: 1
                                            Layout.preferredWidth: clipboardPinnedText.implicitWidth + 12

                                            Text {
                                                font.family: Theme.fontFamily
                                                id: clipboardPinnedText
                                                anchors.centerIn: parent
                                                text: "Pinned"
                                                color: selected ? colors.amber : colors.textDim
                                                font.pixelSize: Theme.fs(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Rectangle {
                                            visible: windowEntry
                                            width: 18
                                            height: 18
                                            radius: Theme.rad(6)
                                            color: launcherWindowCloseMouse.containsMouse ? colors.redBg : colors.bg
                                            border.color: "transparent"
                                            border.width: 0

                                            Text {
                                                font.family: Theme.fontFamily
                                                anchors.centerIn: parent
                                                text: "×"
                                                color: launcherWindowCloseMouse.containsMouse ? colors.red : (entry.focused ? colors.muted : colors.subtle)
                                                font.pixelSize: Theme.fs(10)
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

                                            TapHandler {
                                                acceptedDevices: PointerDevice.TouchScreen
                                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                                onTapped: {
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
                                        // preventStealing protects a mouse press
                                        // from the ListView, but on a touchscreen
                                        // it pins finger-drags to the row — and
                                        // rows tile the list, so the results
                                        // could not be scrolled by touch at all.
                                        // The TapHandler below keeps taps landing.
                                        preventStealing: !root.touchModeAvailable
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: {
                                            if (root.launcherPointerInputReady && root.launcherPointerSelectionEnabled) {
                                                root.updateLauncherPointerSelection(itemIndex);
                                            }
                                        }
                                        onClicked: {
                                            root.updateLauncherPointerSelection(itemIndex);
                                            root.activateLauncherEntry(entry);
                                        }
                                    }

                                    // Touch path: claims a tap the ListView is
                                    // still weighing as a flick; MouseArea on
                                    // the legacy path just loses that grab and
                                    // the tap goes nowhere. A real drag still
                                    // scrolls (ReleaseWithinBounds).
                                    TapHandler {
                                        acceptedDevices: PointerDevice.TouchScreen
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        onTapped: {
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
                            radius: Theme.rad(8)
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
                                        font.family: Theme.fontFamily
                                        Layout.fillWidth: true
                                        text: root.sessionPreviewTitle()
                                        color: colors.text
                                        font.pixelSize: Theme.fs(13)
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        height: 20
                                        radius: Theme.rad(6)
                                        // A live preview colours the badge by the AGENT's state
                                        // (same canonical map as the panel chips), so "Working"
                                        // here is the same amber as a working row. Non-live keeps
                                        // the old remote/error/neutral treatment.
                                        color: boolOrFalse(root.sessionPreview.is_live) ? root.sessionPreviewBadgeFill() : (boolOrFalse(root.sessionPreview.is_remote) ? colors.orangeBg : (root.stringOrEmpty(root.sessionPreview.status) === "error" ? colors.redBg : colors.panelAlt))
                                        border.color: boolOrFalse(root.sessionPreview.is_live) ? root.sessionPreviewBadgeAccent() : (boolOrFalse(root.sessionPreview.is_remote) ? colors.orange : (root.stringOrEmpty(root.sessionPreview.status) === "error" ? colors.red : colors.border))
                                        border.width: 1
                                        Layout.preferredWidth: previewSessionBadgeText.implicitWidth + 12

                                        Text {
                                            font.family: Theme.fontFamily
                                            id: previewSessionBadgeText
                                            anchors.centerIn: parent
                                            text: root.sessionPreviewBadgeText()
                                            color: boolOrFalse(root.sessionPreview.is_live) ? root.sessionPreviewBadgeAccent() : (boolOrFalse(root.sessionPreview.is_remote) ? colors.orange : (root.stringOrEmpty(root.sessionPreview.status) === "error" ? colors.red : colors.textDim))
                                            font.pixelSize: Theme.fs(8)
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    Layout.fillWidth: true
                                    text: root.sessionPreviewSubtitle()
                                    color: colors.subtle
                                    font.pixelSize: Theme.fs(10)
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        visible: root.sessionPreviewStatusText().length > 0
                                        height: 20
                                        radius: Theme.rad(6)
                                        color: colors.panelAlt
                                        border.color: colors.border
                                        border.width: 1
                                        Layout.preferredWidth: previewPhaseText.implicitWidth + 12

                                        Text {
                                            font.family: Theme.fontFamily
                                            id: previewPhaseText
                                            anchors.centerIn: parent
                                            text: root.sessionPreviewStatusText()
                                            color: colors.textDim
                                            font.pixelSize: Theme.fs(8)
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.rad(8)
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
                                        interactive: root.launcherPointerInputReady && contentHeight > height
                                        ScrollBar.vertical: ScrollBar {
                                            policy: ScrollBar.AsNeeded
                                        }

                                        // Tail like a terminal. contentHeight is bound to the
                                        // TextEdit's paintedHeight, which only settles after the
                                        // re-layout — so a deferred scroll from the shell computed
                                        // the OLD bottom and always fell short. Reacting to the
                                        // layout change itself is exact.
                                        onContentHeightChanged: {
                                            if (root.sessionPreviewStickToBottom) {
                                                contentY = Math.max(0, contentHeight - height);
                                            }
                                        }
                                        // Scrolling away stops the tail so reading back is not
                                        // yanked by the next poll; returning to the end resumes it.
                                        onMovementEnded: root.sessionPreviewStickToBottom = atYEnd

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
                                            font.pixelSize: Theme.fs(11)
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
                            radius: Theme.rad(8)
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
                                        font.family: Theme.fontFamily
                                        Layout.fillWidth: true
                                        text: root.clipboardPreviewTitle(launcherClipboardPreviewPane.previewEntry)
                                        color: colors.text
                                        font.pixelSize: Theme.fs(13)
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: root.launcherEntryHasState(launcherClipboardPreviewPane.previewEntry, "pinned")
                                        height: 20
                                        radius: Theme.rad(6)
                                        color: colors.panelAlt
                                        border.color: colors.amber
                                        border.width: 1
                                        Layout.preferredWidth: previewPinnedText.implicitWidth + 12

                                        Text {
                                            font.family: Theme.fontFamily
                                            id: previewPinnedText
                                            anchors.centerIn: parent
                                            text: "Pinned"
                                            color: colors.amber
                                            font.pixelSize: Theme.fs(8)
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                Text {
                                    font.family: Theme.fontFamily
                                    Layout.fillWidth: true
                                    text: root.clipboardEntrySubtitle(launcherClipboardPreviewPane.previewEntry)
                                    color: colors.subtle
                                    font.pixelSize: Theme.fs(10)
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.rad(8)
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
                                                font.pixelSize: Theme.fs(11)
                                                background: null
                                            }
                                        }

                                        Text {
                                            font.family: Theme.fontFamily
                                            visible: launcherClipboardPreviewPane.previewImageSource === "" && launcherClipboardPreviewPane.previewBody === ""
                                            anchors.centerIn: parent
                                            text: "No preview available"
                                            color: colors.subtle
                                            font.pixelSize: Theme.fs(11)
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
                        radius: Theme.rad(12)
                        color: colors.cardAlt
                        border.color: colors.lineSoft
                        border.width: 1

                        Text {
                            font.family: Theme.fontFamily
                            anchors.centerIn: parent
                            text: root.launcherEmptyText()
                            color: root.launcherError ? colors.red : colors.subtle
                            font.pixelSize: Theme.fs(11)
                        }
                    }
                }
            }
        }
    }
}
