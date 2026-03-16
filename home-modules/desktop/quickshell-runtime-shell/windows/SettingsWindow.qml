import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    readonly property QtObject root: shellRoot
    property alias settingsCommandQueryFieldRef: settingsCommandQueryField
    property alias settingsCommandsListRef: settingsCommandsList
    id: settingsWindow
    screen: root.primaryScreen
    visible: root.settingsVisible && root.primaryScreen !== null
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    aboveWindows: true
    WlrLayershell.namespace: "i3pm-runtime-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
        anchors.fill: parent
        color: "#66070b12"

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeSettings()
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(1040, parent.width - 72)
            height: Math.min(700, parent.height - 72)
            radius: 14
            color: colors.panel
            border.color: colors.borderStrong
            border.width: 1

            MouseArea {
                anchors.fill: parent
                onClicked: function (mouse) {
                    mouse.accepted = true;
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 180
                    radius: 10
                    color: colors.card
                    border.color: colors.border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Text {
                            text: root.settingsTitle()
                            color: colors.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Manage runtime shell commands and devices without leaving QuickShell."
                            color: colors.subtle
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: colors.lineSoft
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 8
                            color: root.settingsSection === "commands" ? colors.tealBg : colors.cardAlt
                            border.color: root.settingsSection === "commands" ? colors.teal : colors.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Text {
                                    text: "$"
                                    color: root.settingsSection === "commands" ? colors.teal : colors.textDim
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Commands"
                                        color: root.settingsSection === "commands" ? colors.teal : colors.text
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: "Elephant snippets"
                                        color: colors.subtle
                                        font.pixelSize: 9
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setSettingsSection("commands")
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 8
                            color: root.settingsSection === "devices" ? colors.blueBg : colors.cardAlt
                            border.color: root.settingsSection === "devices" ? colors.blue : colors.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                Text {
                                    text: "◈"
                                    color: root.settingsSection === "devices" ? colors.blue : colors.textDim
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Devices"
                                        color: root.settingsSection === "devices" ? colors.blue : colors.text
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: "Audio, Bluetooth, network, resources"
                                        color: colors.subtle
                                        font.pixelSize: 9
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setSettingsSection("devices")
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Open with `toggle-runtime-settings`."
                            color: colors.subtle
                            font.pixelSize: 9
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    radius: 10
                    color: colors.card
                    border.color: colors.border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        visible: root.settingsSection === "commands"

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "Commands"
                                    color: colors.text
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: "Browse and edit curated commands stored in `~/.config/elephant/snippets.toml`."
                                    color: colors.subtle
                                    font.pixelSize: 10
                                }
                            }

                            Button {
                                text: "Close"
                                onClicked: root.closeSettings()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: root.settingsCommandStatusText()
                                color: root.settingsCommandError ? colors.red : colors.subtle
                                font.pixelSize: 10
                            }

                            Text {
                                text: root.snippetEditorStatus()
                                color: root.snippetEditorError ? colors.red : (root.snippetEditorDirty ? colors.orange : colors.subtle)
                                font.pixelSize: 10
                            }
                        }

                        Shortcut {
                            enabled: root.settingsVisible && root.settingsSection === "commands"
                            sequences: [StandardKey.New]
                            onActivated: root.beginNewSnippetFromQuery()
                        }

                        Shortcut {
                            enabled: root.settingsVisible && root.settingsSection === "commands"
                            sequences: [StandardKey.Save]
                            onActivated: root.saveSnippetEditor()
                        }

                        Shortcut {
                            enabled: root.settingsVisible && root.settingsSection === "commands"
                            sequences: ["Ctrl+D"]
                            onActivated: root.removeSnippetEditorEntry()
                        }

                        Shortcut {
                            enabled: root.settingsVisible && root.settingsSection === "commands"
                            sequences: ["Alt+Up"]
                            onActivated: root.moveSnippetEditorEntry("up")
                        }

                        Shortcut {
                            enabled: root.settingsVisible && root.settingsSection === "commands"
                            sequences: ["Alt+Down"]
                            onActivated: root.moveSnippetEditorEntry("down")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.preferredWidth: 330
                                radius: 8
                                color: colors.cardAlt
                                border.color: colors.lineSoft
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        TextField {
                                            id: settingsCommandQueryField
                                            Layout.fillWidth: true
                                            text: ""
                                            placeholderText: "Search commands"
                                            color: colors.text
                                            selectByMouse: true
                                            background: Rectangle {
                                                radius: 8
                                                color: colors.panel
                                                border.color: settingsCommandQueryField.activeFocus ? colors.teal : colors.border
                                                border.width: 1
                                            }
                                            onTextChanged: {
                                                if (!root.settingsCommandNormalizingInput) {
                                                    root.settingsCommandQuery = text;
                                                }
                                            }
                                            Keys.onPressed: function (event) {
                                                switch (event.key) {
                                                case Qt.Key_Escape:
                                                    root.closeSettings();
                                                    event.accepted = true;
                                                    break;
                                                case Qt.Key_Down:
                                                    root.moveSettingsCommandSelection(1);
                                                    event.accepted = true;
                                                    break;
                                                case Qt.Key_Up:
                                                    root.moveSettingsCommandSelection(-1);
                                                    event.accepted = true;
                                                    break;
                                                default:
                                                    break;
                                                }
                                            }
                                        }

                                        Button {
                                            text: "New"
                                            enabled: !root.snippetEditorBusy
                                            onClicked: root.beginNewSnippetFromQuery()
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: colors.lineSoft
                                    }

                                    ScriptModel {
                                        id: settingsCommandEntriesModel
                                        values: root.settingsCommandEntries
                                        objectProp: "modelData"
                                    }

                                    ListView {
                                        id: settingsCommandsList
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: 6
                                        model: settingsCommandEntriesModel

                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property var entry: modelData
                                            readonly property int itemIndex: root.settingsCommandEntries.findIndex(function (candidate) {
                                                return root.launcherEntryIdentity(candidate) === root.launcherEntryIdentity(entry);
                                            })
                                            readonly property bool selected: itemIndex === root.settingsCommandSelectedIndex

                                            width: settingsCommandsList.width
                                            height: 70
                                            radius: 8
                                            color: selected ? colors.blueBg : (settingsCommandMouse.containsMouse ? colors.panelAlt : "transparent")
                                            border.color: selected ? colors.blue : (settingsCommandMouse.containsMouse ? colors.borderStrong : "transparent")
                                            border.width: 1

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                anchors.topMargin: 10
                                                anchors.bottomMargin: 10
                                                spacing: 4

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.stringOrEmpty(entry && entry.text)
                                                    color: colors.text
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.stringOrEmpty(entry && entry.description)
                                                    visible: text.length > 0
                                                    color: colors.subtle
                                                    font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.stringOrEmpty(entry && entry.command)
                                                    color: selected ? colors.blue : colors.textDim
                                                    font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                id: settingsCommandMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: root.settingsCommandSelectedIndex = itemIndex
                                                onClicked: root.settingsCommandSelectedIndex = itemIndex
                                            }
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: !root.settingsCommandLoading && root.settingsCommandEntries.length === 0
                                            width: parent.width - 12
                                            height: 72
                                            radius: 8
                                            color: colors.panel
                                            border.color: colors.border
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.settingsCommandEmptyText()
                                                color: root.settingsCommandError ? colors.red : colors.subtle
                                                font.pixelSize: 10
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
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
                                            text: root.snippetEditorTitle()
                                            color: colors.text
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            height: 20
                                            radius: 6
                                            color: root.snippetEditorNewDraft ? colors.orangeBg : colors.tealBg
                                            border.color: root.snippetEditorNewDraft ? colors.orange : colors.teal
                                            border.width: 1
                                            Layout.preferredWidth: settingsEditorModeText.implicitWidth + 12

                                            Text {
                                                id: settingsEditorModeText
                                                anchors.centerIn: parent
                                                text: root.snippetEditorNewDraft ? "New" : "Saved"
                                                color: root.snippetEditorNewDraft ? colors.orange : colors.teal
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.snippetEditorStatus()
                                        color: root.snippetEditorError ? colors.red : (root.snippetEditorDirty ? colors.orange : colors.subtle)
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        text: "Name"
                                        color: colors.textDim
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }

                                    TextField {
                                        id: settingsSnippetNameField
                                        Layout.fillWidth: true
                                        text: root.snippetEditorName
                                        placeholderText: "deploy api"
                                        color: colors.text
                                        selectByMouse: true
                                        enabled: !root.snippetEditorBusy
                                        background: Rectangle {
                                            radius: 8
                                            color: colors.panel
                                            border.color: settingsSnippetNameField.activeFocus ? colors.teal : colors.border
                                            border.width: 1
                                        }
                                        onTextChanged: {
                                            if (root.snippetEditorSyncing) {
                                                return;
                                            }
                                            root.snippetEditorName = text;
                                            root.snippetEditorDirty = true;
                                            root.snippetEditorError = "";
                                            root.snippetEditorMessage = "";
                                        }
                                    }

                                    Text {
                                        text: "Command"
                                        color: colors.textDim
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 180
                                        radius: 8
                                        color: colors.panel
                                        border.color: colors.border
                                        border.width: 1

                                        ScrollView {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            clip: true

                                            TextArea {
                                                text: root.snippetEditorCommand
                                                placeholderText: "just deploy api"
                                                color: colors.text
                                                selectByMouse: true
                                                wrapMode: TextEdit.Wrap
                                                enabled: !root.snippetEditorBusy
                                                background: null
                                                onTextChanged: {
                                                    if (root.snippetEditorSyncing) {
                                                        return;
                                                    }
                                                    root.snippetEditorCommand = text;
                                                    root.snippetEditorDirty = true;
                                                    root.snippetEditorError = "";
                                                    root.snippetEditorMessage = "";
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: "Description"
                                        color: colors.textDim
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }

                                    TextField {
                                        id: settingsSnippetDescriptionField
                                        Layout.fillWidth: true
                                        text: root.snippetEditorDescription
                                        placeholderText: "Optional note shown in the launcher"
                                        color: colors.text
                                        selectByMouse: true
                                        enabled: !root.snippetEditorBusy
                                        background: Rectangle {
                                            radius: 8
                                            color: colors.panel
                                            border.color: settingsSnippetDescriptionField.activeFocus ? colors.blue : colors.border
                                            border.width: 1
                                        }
                                        onTextChanged: {
                                            if (root.snippetEditorSyncing) {
                                                return;
                                            }
                                            root.snippetEditorDescription = text;
                                            root.snippetEditorDirty = true;
                                            root.snippetEditorError = "";
                                            root.snippetEditorMessage = "";
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Button {
                                            text: root.snippetEditorBusy ? "Saving..." : "Save"
                                            enabled: root.snippetEditorCanSave()
                                            onClicked: root.saveSnippetEditor()
                                        }

                                        Button {
                                            text: "Delete"
                                            enabled: !root.snippetEditorBusy && !root.snippetEditorNewDraft && root.snippetEditorIndex >= 0
                                            onClicked: root.removeSnippetEditorEntry()
                                        }

                                        Button {
                                            text: "Move Up"
                                            enabled: !root.snippetEditorBusy && !root.snippetEditorNewDraft && root.snippetEditorIndex > 0
                                            onClicked: root.moveSnippetEditorEntry("up")
                                        }

                                        Button {
                                            text: "Move Down"
                                            enabled: !root.snippetEditorBusy && !root.snippetEditorNewDraft && root.snippetEditorIndex >= 0 && root.snippetEditorIndex < root.settingsCommandEntries.length - 1
                                            onClicked: root.moveSnippetEditorEntry("down")
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12
                            visible: root.settingsSection === "devices"

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: "Devices"
                                        color: colors.text
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: "Native QuickShell controls for audio, Bluetooth, network, and system resources."
                                        color: colors.subtle
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Button {
                                    text: "Close"
                                    onClicked: root.closeSettings()
                                }
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                ColumnLayout {
                                    width: parent.width
                                    spacing: 12

                                    Rectangle {
                                        Layout.fillWidth: true
                                        radius: 10
                                        color: colors.cardAlt
                                        border.color: colors.lineSoft
                                        border.width: 1
                                        implicitHeight: devicesSummaryContent.implicitHeight + 24

                                        ColumnLayout {
                                            id: devicesSummaryContent
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 8

                                            Text {
                                                text: "System Resources"
                                                color: colors.text
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }

                                            Text {
                                                text: root.systemStatsSummaryLabel()
                                                color: colors.subtle
                                                font.pixelSize: 10
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 34
                                                    radius: 8
                                                    color: colors.panel
                                                    border.color: colors.border
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: root.systemStatsMemoryLabel()
                                                        color: colors.text
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 34
                                                    radius: 8
                                                    color: colors.panel
                                                    border.color: colors.border
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Load " + Number(root.systemStatsState.load1 || 0).toFixed(2)
                                                        color: colors.text
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 34
                                                    radius: 8
                                                    color: colors.panel
                                                    border.color: colors.border
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: root.systemStatsState.temperature_c !== null && root.systemStatsState.temperature_c !== undefined ? String(root.systemStatsState.temperature_c) + "°C" : "Temp --"
                                                        color: colors.text
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        radius: 10
                                        color: colors.cardAlt
                                        border.color: colors.lineSoft
                                        border.width: 1
                                        implicitHeight: settingsAudioCardContent.implicitHeight + 24

                                        ColumnLayout {
                                            id: settingsAudioCardContent
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Audio"
                                                    color: colors.text
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }

                                                Button {
                                                    text: root.audioMuted() ? "Unmute" : "Mute"
                                                    onClicked: root.toggleMute()
                                                }

                                                Button {
                                                    text: "Mixer"
                                                    onClicked: root.runDetached(["pavucontrol"])
                                                }
                                            }

                                            Text {
                                                text: root.audioDetail()
                                                color: colors.subtle
                                                font.pixelSize: 10
                                            }

                                            Slider {
                                                Layout.fillWidth: true
                                                from: 0
                                                to: 150
                                                value: root.volumePercent()
                                                onMoved: {
                                                    const node = root.audioNode();
                                                    if (node && node.audio) {
                                                        node.audio.volume = Math.max(0, Math.min(1.5, value / 100));
                                                    }
                                                }
                                            }

                                            Repeater {
                                                model: root.audioNodes()

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var sink: modelData
                                                    readonly property bool activeSink: root.audioSinkIsActive(sink)
                                                    Layout.fillWidth: true
                                                    implicitHeight: 34
                                                    radius: 8
                                                    color: activeSink ? colors.blueBg : colors.panel
                                                    border.color: activeSink ? colors.blue : colors.border
                                                    border.width: 1

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.audioSinkLabel(sink)
                                                            color: activeSink ? colors.blue : colors.text
                                                            font.pixelSize: 9
                                                            font.weight: Font.Medium
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.setPreferredAudioSink(sink)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        radius: 10
                                        color: colors.cardAlt
                                        border.color: colors.lineSoft
                                        border.width: 1
                                        implicitHeight: settingsBluetoothCardContent.implicitHeight + 24

                                        ColumnLayout {
                                            id: settingsBluetoothCardContent
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Bluetooth & Network"
                                                    color: colors.text
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }

                                                Button {
                                                    text: root.bluetoothEnabled() ? "BT Off" : "BT On"
                                                    enabled: root.bluetoothAvailable()
                                                    onClicked: root.toggleBluetoothEnabled()
                                                }

                                                Button {
                                                    text: "Manager"
                                                    onClicked: root.runDetached(["blueman-manager"])
                                                }
                                            }

                                            Text {
                                                text: root.networkDetail()
                                                color: colors.subtle
                                                font.pixelSize: 10
                                            }

                                            Repeater {
                                                model: root.bluetoothDevices()

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var device: modelData
                                                    readonly property bool connected: !!(device && device.connected)
                                                    Layout.fillWidth: true
                                                    implicitHeight: 36
                                                    radius: 8
                                                    color: connected ? colors.tealBg : colors.panel
                                                    border.color: connected ? colors.teal : colors.border
                                                    border.width: 1

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10
                                                        spacing: 8

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.stringOrEmpty(device && device.name) || "Bluetooth device"
                                                            color: connected ? colors.teal : colors.text
                                                            font.pixelSize: 9
                                                            font.weight: Font.Medium
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            text: connected ? "Disconnect" : "Connect"
                                                            color: connected ? colors.teal : colors.subtle
                                                            font.pixelSize: 8
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: root.bluetoothEnabled()
                                                        onClicked: root.toggleBluetoothDevice(device)
                                                    }
                                                }
                                            }

                                            Text {
                                                visible: !root.bluetoothAvailable()
                                                text: "No Bluetooth adapter detected on this host."
                                                color: colors.subtle
                                                font.pixelSize: 9
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
