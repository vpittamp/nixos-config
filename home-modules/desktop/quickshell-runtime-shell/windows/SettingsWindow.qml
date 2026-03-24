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

                                IconImage {
                                    readonly property string iconSrc: root.iconSource("insert-text", "")
                                    visible: iconSrc !== ""
                                    implicitSize: 12
                                    source: iconSrc
                                    mipmap: true
                                }

                                Text {
                                    visible: root.iconSource("insert-text", "") === ""
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
                            color: root.settingsSection === "apps" ? colors.orangeBg : colors.cardAlt
                            border.color: root.settingsSection === "apps" ? colors.orange : colors.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                IconImage {
                                    readonly property string iconSrc: root.iconSource("application-x-executable", "")
                                    visible: iconSrc !== ""
                                    implicitSize: 12
                                    source: iconSrc
                                    mipmap: true
                                }

                                Text {
                                    visible: root.iconSource("application-x-executable", "") === ""
                                    text: "◎"
                                    color: root.settingsSection === "apps" ? colors.orange : colors.textDim
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Apps"
                                        color: root.settingsSection === "apps" ? colors.orange : colors.text
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: "Live registry + declarative sync"
                                        color: colors.subtle
                                        font.pixelSize: 9
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setSettingsSection("apps")
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

                                IconImage {
                                    readonly property string iconSrc: root.iconSource("preferences-system", "")
                                    visible: iconSrc !== ""
                                    implicitSize: 12
                                    source: iconSrc
                                    mipmap: true
                                }

                                Text {
                                    visible: root.iconSource("preferences-system", "") === ""
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

                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.settingsSection === "commands" ? 1 : (root.settingsSection === "apps" ? 0 : 2)

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            AppRegistrySettingsPane {
                                anchors.fill: parent
                                shellRoot: root
                                runtimeConfig: settingsWindow.runtimeConfig
                                colors: settingsWindow.colors
                                active: root.settingsVisible && root.settingsSection === "apps"
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

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
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

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
                                        text: "Native QuickShell controls for displays, brightness, battery, audio, Bluetooth, and host runtime status."
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
                                        implicitHeight: settingsDisplayCardContent.implicitHeight + 24

                                        ColumnLayout {
                                            id: settingsDisplayCardContent
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    Text {
                                                        text: "Displays"
                                                        color: colors.text
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                    }

                                                    Text {
                                                        text: root.displayApplyStatusText()
                                                        color: root.displayApplyError ? colors.red : colors.subtle
                                                        font.pixelSize: 10
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }

                                                Button {
                                                    text: "Picker"
                                                    onClicked: root.openDisplaySelector()
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: "Current: " + root.currentLayoutLabel() + "  •  " + root.activeDisplaySummary()
                                                color: colors.subtle
                                                font.pixelSize: 10
                                                wrapMode: Text.WordWrap
                                            }

                                            Repeater {
                                                model: root.displayLayoutOptions()

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property string layoutName: root.displayOptionName(modelData)
                                                    readonly property bool current: !!(modelData && modelData.current)
                                                    readonly property bool pending: root.displayApplyPending(layoutName)
                                                    readonly property var outputNames: root.displayOptionOutputs(modelData)
                                                    Layout.fillWidth: true
                                                    implicitHeight: settingsDisplayOptionColumn.implicitHeight + 20
                                                    radius: 8
                                                    color: current ? colors.blueBg : colors.panel
                                                    border.color: current ? colors.blue : colors.border
                                                    border.width: 1

                                                    ColumnLayout {
                                                        id: settingsDisplayOptionColumn
                                                        anchors.fill: parent
                                                        anchors.margins: 10
                                                        spacing: 8

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 8

                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 2

                                                                Text {
                                                                    text: root.displayOptionLabel(modelData)
                                                                    color: current ? colors.blue : colors.text
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.DemiBold
                                                                }

                                                                Text {
                                                                    text: root.displayOptionDescription(modelData)
                                                                    color: colors.subtle
                                                                    font.pixelSize: 9
                                                                    wrapMode: Text.WordWrap
                                                                }
                                                            }

                                                            Button {
                                                                text: pending ? "Applying" : (current ? "Active" : "Apply")
                                                                enabled: !pending && !current && !(root.displayApplyProcess && root.displayApplyProcess.running)
                                                                onClicked: root.applyDisplayLayout(layoutName)
                                                            }
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            visible: outputNames.length > 0
                                                            text: outputNames.join("  •  ")
                                                            color: colors.subtle
                                                            font.pixelSize: 9
                                                            wrapMode: Text.WordWrap
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                visible: root.displayLayoutOptions().length === 0
                                                text: "No daemon-backed display layouts are configured for this host."
                                                color: colors.subtle
                                                font.pixelSize: 9
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        radius: 10
                                        color: colors.cardAlt
                                        border.color: colors.lineSoft
                                        border.width: 1
                                        visible: root.allDisplayOutputs().length > 0
                                        implicitHeight: perOutputColumn.implicitHeight + 24

                                        ColumnLayout {
                                            id: perOutputColumn
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10

                                            Text {
                                                text: "Per-Output Controls"
                                                color: colors.text
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }

                                            Repeater {
                                                model: root.allDisplayOutputs()

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var output: modelData
                                                    readonly property string outputName: root.stringOrEmpty(output && output.name)
                                                    readonly property bool outputEnabled: !!(output && output.enabled !== false)
                                                    readonly property bool pending: root.displayTogglePending(outputName)
                                                    Layout.fillWidth: true
                                                    implicitHeight: perOutputRow.implicitHeight + 16
                                                    radius: 8
                                                    color: outputEnabled ? colors.panel : colors.cardAlt
                                                    border.color: outputEnabled ? colors.border : colors.lineSoft
                                                    border.width: 1
                                                    opacity: outputEnabled ? 1.0 : 0.6

                                                    RowLayout {
                                                        id: perOutputRow
                                                        anchors.fill: parent
                                                        anchors.margins: 8
                                                        spacing: 8

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2

                                                            RowLayout {
                                                                spacing: 6

                                                                Text {
                                                                    text: outputName
                                                                    color: colors.text
                                                                    font.pixelSize: 11
                                                                    font.weight: Font.DemiBold
                                                                    font.strikeout: !outputEnabled
                                                                }

                                                                Text {
                                                                    visible: !!(output && output.primary)
                                                                    text: "primary"
                                                                    color: colors.blue
                                                                    font.pixelSize: 9
                                                                    font.weight: Font.Bold
                                                                }
                                                            }

                                                            Text {
                                                                visible: !!(output && output.rect)
                                                                text: {
                                                                    const r = output && output.rect;
                                                                    if (!r) return "";
                                                                    return (r.width || 0) + "x" + (r.height || 0);
                                                                }
                                                                color: colors.subtle
                                                                font.pixelSize: 9
                                                            }

                                                            RowLayout {
                                                                spacing: 4
                                                                readonly property real currentScale: (output && output.scale) ? output.scale : 1.0
                                                                readonly property bool scalePending: root.displayScalePending(outputName)

                                                                Text {
                                                                    text: "Scale:"
                                                                    color: colors.subtle
                                                                    font.pixelSize: 9
                                                                }

                                                                Repeater {
                                                                    model: [1.0, 1.25]
                                                                    delegate: Button {
                                                                        readonly property real scaleValue: modelData
                                                                        readonly property bool isActive: Math.abs(parent.currentScale - scaleValue) < 0.01
                                                                        text: scaleValue + "x"
                                                                        enabled: !parent.scalePending && !isActive && !(root.displayScaleProcess && root.displayScaleProcess.running)
                                                                        font.pixelSize: 9
                                                                        font.weight: isActive ? Font.Bold : Font.Normal
                                                                        palette.buttonText: isActive ? colors.teal : colors.text
                                                                        onClicked: root.setDisplayScale(outputName, scaleValue)
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Button {
                                                            text: pending ? "..." : (outputEnabled ? "Disable" : "Enable")
                                                            enabled: !pending && !(root.displayToggleOutputProcess && root.displayToggleOutputProcess.running)
                                                            onClicked: root.toggleDisplayOutput(outputName)
                                                        }
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
                                        implicitHeight: brightnessPowerCardContent.implicitHeight + 24

                                        ColumnLayout {
                                            id: brightnessPowerCardContent
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 10

                                            Text {
                                                text: "Brightness & Power"
                                                color: colors.text
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: root.brightnessActionError ? root.brightnessActionError : (root.brightnessPowerSummaryText() || "Expose local backlight and battery controls when the host supports them.")
                                                color: root.brightnessActionError ? colors.red : colors.subtle
                                                font.pixelSize: 10
                                                wrapMode: Text.WordWrap
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                visible: root.brightnessAvailable("display")
                                                spacing: 6

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2

                                                        Text {
                                                            text: root.brightnessLabel("display")
                                                            color: colors.text
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                        }

                                                        Text {
                                                            text: root.brightnessDetail("display")
                                                            color: colors.subtle
                                                            font.pixelSize: 9
                                                        }
                                                    }

                                                    Button {
                                                        text: "-"
                                                        onClicked: root.setBrightness("display", root.brightnessPercent("display") - 5)
                                                    }

                                                    Text {
                                                        text: String(root.brightnessPercent("display")) + "%"
                                                        color: colors.text
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }

                                                    Button {
                                                        text: "+"
                                                        onClicked: root.setBrightness("display", root.brightnessPercent("display") + 5)
                                                    }
                                                }

                                                    Slider {
                                                        Layout.fillWidth: true
                                                        from: 0
                                                        to: 100
                                                        stepSize: 5
                                                        value: root.brightnessPercent("display")
                                                        onMoved: root.setBrightness("display", Math.round(value / 5) * 5)
                                                    }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                visible: root.brightnessAvailable("keyboard")
                                                spacing: 6

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2

                                                        Text {
                                                            text: root.brightnessLabel("keyboard")
                                                            color: colors.text
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                        }

                                                        Text {
                                                            text: root.brightnessDetail("keyboard")
                                                            color: colors.subtle
                                                            font.pixelSize: 9
                                                        }
                                                    }

                                                    Button {
                                                        text: "-"
                                                        onClicked: root.setBrightness("keyboard", root.brightnessPercent("keyboard") - 10)
                                                    }

                                                    Text {
                                                        text: String(root.brightnessPercent("keyboard")) + "%"
                                                        color: colors.text
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }

                                                    Button {
                                                        text: "+"
                                                        onClicked: root.setBrightness("keyboard", root.brightnessPercent("keyboard") + 10)
                                                    }
                                                }

                                                    Slider {
                                                        Layout.fillWidth: true
                                                        from: 0
                                                        to: 100
                                                        stepSize: 10
                                                        value: root.brightnessPercent("keyboard")
                                                        onMoved: root.setBrightness("keyboard", Math.round(value / 10) * 10)
                                                    }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                visible: root.batteryReady()
                                                radius: 8
                                                color: colors.panel
                                                border.color: colors.border
                                                border.width: 1
                                                implicitHeight: batteryInfoColumn.implicitHeight + 20

                                                ColumnLayout {
                                                    id: batteryInfoColumn
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 6

                                                    Text {
                                                        text: "Battery"
                                                        color: colors.text
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: root.batteryLabel()
                                                        color: colors.text
                                                        font.pixelSize: 10
                                                        wrapMode: Text.WordWrap
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: root.batteryStateText() + (root.batteryDurationLabel() ? "  •  " + root.batteryDurationLabel() : "")
                                                        color: colors.subtle
                                                        font.pixelSize: 9
                                                        wrapMode: Text.WordWrap
                                                    }

                                                    Text {
                                                        visible: root.batteryHealthLabel() !== "" || root.batteryRateLabel() !== "" || root.batteryEnergyLabel() !== ""
                                                        Layout.fillWidth: true
                                                        text: [root.batteryHealthLabel(), root.batteryRateLabel(), root.batteryEnergyLabel()].filter(function(part) { return part !== ""; }).join("  •  ")
                                                        color: colors.subtle
                                                        font.pixelSize: 9
                                                        wrapMode: Text.WordWrap
                                                    }

                                                    Text {
                                                        visible: root.batteryMetadataLabel() !== ""
                                                        Layout.fillWidth: true
                                                        text: root.batteryMetadataLabel()
                                                        color: colors.subtle
                                                        font.pixelSize: 9
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                visible: root.powerProfilesSupported()
                                                spacing: 6

                                                Text {
                                                    text: "Power Profile"
                                                    color: colors.text
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Repeater {
                                                        model: root.powerProfileChoices()

                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            readonly property var choice: modelData
                                                            readonly property bool activeChoice: root.powerProfileIsActive(choice.value)
                                                            Layout.fillWidth: true
                                                            implicitHeight: 34
                                                            radius: 8
                                                            color: activeChoice ? colors.amberBg : colors.panel
                                                            border.color: activeChoice ? colors.amber : colors.border
                                                            border.width: 1

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: choice.label
                                                                color: activeChoice ? colors.amber : colors.text
                                                                font.pixelSize: 9
                                                                font.weight: Font.DemiBold
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: root.setPowerProfile(choice.value)
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    visible: root.powerProfileDegradationText() !== ""
                                                    Layout.fillWidth: true
                                                    text: root.powerProfileDegradationText()
                                                    color: colors.amber
                                                    font.pixelSize: 9
                                                    wrapMode: Text.WordWrap
                                                }

                                                Text {
                                                    visible: root.powerProfileHoldText() !== ""
                                                    Layout.fillWidth: true
                                                    text: root.powerProfileHoldText()
                                                    color: colors.subtle
                                                    font.pixelSize: 9
                                                    wrapMode: Text.WordWrap
                                                }
                                            }

                                            Text {
                                                visible: !root.hasBrightnessOrPowerControls()
                                                Layout.fillWidth: true
                                                text: "No display backlight, keyboard backlight, battery, or native power-profile controls are exposed on this host."
                                                color: colors.subtle
                                                font.pixelSize: 9
                                                wrapMode: Text.WordWrap
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
                                                    text: root.audioMuted() ? "Unmute Out" : "Mute Out"
                                                    onClicked: root.toggleMute()
                                                }

                                                Button {
                                                    text: "Mixer"
                                                    onClicked: root.runDetached(["pavucontrol"])
                                                }
                                            }

                                            Text {
                                                text: "Output"
                                                color: colors.text
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
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

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 1
                                                color: colors.lineSoft
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Input"
                                                    color: colors.text
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }

                                                Button {
                                                    text: root.audioInputMuted() ? "Unmute In" : "Mute In"
                                                    enabled: root.audioInputReady()
                                                    onClicked: root.toggleInputMute()
                                                }
                                            }

                                            Text {
                                                text: root.audioInputDetail()
                                                color: colors.subtle
                                                font.pixelSize: 10
                                            }

                                            Slider {
                                                Layout.fillWidth: true
                                                from: 0
                                                to: 150
                                                value: root.inputVolumePercent()
                                                enabled: root.audioInputReady()
                                                onMoved: root.setInputVolumePercent(value)
                                            }

                                            Repeater {
                                                model: root.audioSourceNodes()

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var source: modelData
                                                    readonly property bool activeSource: root.audioSourceIsActive(source)
                                                    Layout.fillWidth: true
                                                    implicitHeight: 34
                                                    radius: 8
                                                    color: activeSource ? colors.tealBg : colors.panel
                                                    border.color: activeSource ? colors.teal : colors.border
                                                    border.width: 1

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10
                                                        anchors.rightMargin: 10

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.audioSourceLabel(source)
                                                            color: activeSource ? colors.teal : colors.text
                                                            font.pixelSize: 9
                                                            font.weight: Font.Medium
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.setPreferredAudioSource(source)
                                                    }
                                                }
                                            }

                                            Text {
                                                visible: root.audioSourceNodes().length === 0
                                                text: "No input sources reported by PipeWire."
                                                color: colors.subtle
                                                font.pixelSize: 9
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
                                                    text: "Bluetooth"
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
                                                text: root.bluetoothDetail()
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
                                                visible: root.bluetoothAvailable() && root.bluetoothDevices().length === 0
                                                text: "Bluetooth is available, but no paired devices are currently reported."
                                                color: colors.subtle
                                                font.pixelSize: 9
                                            }

                                            Text {
                                                visible: !root.bluetoothAvailable()
                                                text: "No Bluetooth adapter detected on this host."
                                                color: colors.subtle
                                                font.pixelSize: 9
                                            }
                                        }
                                    }

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
