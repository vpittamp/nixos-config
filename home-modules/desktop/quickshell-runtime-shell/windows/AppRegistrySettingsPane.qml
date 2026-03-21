import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Item {
    id: pane

    required property QtObject shellRoot
    required property QtObject runtimeConfig
    required property var colors
    required property bool active

    property string query: ""
    property bool loading: false
    property string errorText: ""
    property string statusText: ""
    property var entries: []
    property string filterMode: "all"
    property int selectedIndex: 0
    property bool editorBusy: false
    property string editorError: ""
    property string editorMessage: ""
    property bool editorSyncing: false
    property string currentAppName: ""
    property string editorDisplayName: ""
    property string editorDescription: ""
    property string editorWorkspace: ""
    property string editorMonitorRole: ""
    property bool editorFloating: false
    property string editorFloatingSize: ""
    property bool editorMultiInstance: false
    property string editorFallbackBehavior: ""
    property string editorIcon: ""
    property string editorAliases: ""
    property string currentScope: ""
    property string currentCommand: ""
    property string currentExpectedClass: ""
    property bool currentDirty: false
    readonly property int totalCount: entries.length
    readonly property int dirtyCount: entries.filter(function(entry) { return !!(entry && entry.dirty); }).length
    readonly property int scopedCount: entries.filter(function(entry) { return pane.stringOrEmpty(entry && entry.scope).toLowerCase() === "scoped"; }).length
    readonly property int globalCount: entries.filter(function(entry) { return pane.stringOrEmpty(entry && entry.scope).toLowerCase() === "global"; }).length
    readonly property int pwaCount: entries.filter(function(entry) { return !!(entry && entry.is_pwa); }).length
    readonly property var displayEntries: entries.filter(function(entry) {
        const mode = pane.stringOrEmpty(filterMode).toLowerCase();
        if (mode === "dirty") {
            return !!(entry && entry.dirty);
        }
        if (mode === "scoped") {
            return pane.stringOrEmpty(entry && entry.scope).toLowerCase() === "scoped";
        }
        if (mode === "global") {
            return pane.stringOrEmpty(entry && entry.scope).toLowerCase() === "global";
        }
        if (mode === "pwa") {
            return !!(entry && entry.is_pwa);
        }
        return true;
    })

    function stringOrEmpty(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function arrayOrEmpty(value) {
        return Array.isArray(value) ? value : [];
    }

    function activeEntry() {
        if (!displayEntries.length) {
            return null;
        }
        if (selectedIndex < 0 || selectedIndex >= displayEntries.length) {
            return displayEntries[0];
        }
        return displayEntries[selectedIndex];
    }

    function resetEditor() {
        editorSyncing = true;
        currentAppName = "";
        editorDisplayName = "";
        editorDescription = "";
        editorWorkspace = "";
        editorMonitorRole = "";
        editorFloating = false;
        editorFloatingSize = "";
        editorMultiInstance = false;
        editorFallbackBehavior = "";
        editorIcon = "";
        editorAliases = "";
        currentScope = "";
        currentCommand = "";
        currentExpectedClass = "";
        currentDirty = false;
        editorSyncing = false;
    }

    function iconSource(entry) {
        if (!entry) {
            return "";
        }
        return shellRoot.launcherIconSource(entry);
    }

    function badgeColor(tone) {
        return shellRoot.launcherBadgeColor(tone);
    }

    function badgeBackground(tone) {
        return shellRoot.launcherBadgeBackground(tone);
    }

    function setFilterMode(mode) {
        filterMode = mode;
        selectedIndex = 0;
        loadEntry(activeEntry());
    }

    function loadEntry(entry) {
        if (!entry) {
            resetEditor();
            return;
        }

        editorSyncing = true;
        currentAppName = stringOrEmpty(entry.name);
        editorDisplayName = stringOrEmpty(entry.display_name || entry.text);
        editorDescription = stringOrEmpty(entry.description);
        editorWorkspace = entry.preferred_workspace === undefined || entry.preferred_workspace === null ? "" : String(entry.preferred_workspace);
        editorMonitorRole = stringOrEmpty(entry.preferred_monitor_role);
        editorFloating = !!entry.floating;
        editorFloatingSize = stringOrEmpty(entry.floating_size);
        editorMultiInstance = !!entry.multi_instance;
        editorFallbackBehavior = stringOrEmpty(entry.fallback_behavior);
        editorIcon = stringOrEmpty(entry.icon);
        editorAliases = arrayOrEmpty(entry.aliases).join(", ");
        currentScope = stringOrEmpty(entry.scope);
        currentCommand = stringOrEmpty(entry.command);
        currentExpectedClass = stringOrEmpty(entry.expected_class);
        currentDirty = !!entry.dirty;
        editorError = "";
        editorMessage = "";
        editorSyncing = false;
    }

    function reloadEntries() {
        if (!active) {
            return;
        }
        if (listProcess.running) {
            listProcess.running = false;
        }
        loading = true;
        errorText = "";
        statusText = "";
        listProcess.command = [runtimeConfig.appRegistryListBin, query, "400"];
        listProcess.running = true;
    }

    function saveOverride() {
        if (!currentAppName || editorBusy) {
            return;
        }

        if (manageProcess.running) {
            manageProcess.running = false;
        }

        editorBusy = true;
        editorError = "";
        editorMessage = "";
        manageProcess.command = [
            runtimeConfig.appRegistryManageBin,
            "upsert",
            currentAppName,
            editorDisplayName,
            editorDescription,
            editorWorkspace,
            editorMonitorRole,
            editorFloating ? "true" : "false",
            editorFloatingSize,
            editorMultiInstance ? "true" : "false",
            editorFallbackBehavior,
            editorIcon,
            JSON.stringify(editorAliases.split(",").map(function(alias) {
                return String(alias).trim();
            }).filter(function(alias) {
                return alias.length > 0;
            })),
        ];
        manageProcess.running = true;
    }

    function clearOverride() {
        if (!currentAppName || editorBusy) {
            return;
        }
        if (manageProcess.running) {
            manageProcess.running = false;
        }
        editorBusy = true;
        editorError = "";
        editorMessage = "";
        manageProcess.command = [runtimeConfig.appRegistryManageBin, "remove", currentAppName];
        manageProcess.running = true;
    }

    function applyWorkingCopy() {
        if (manageProcess.running) {
            manageProcess.running = false;
        }
        editorBusy = true;
        editorError = "";
        editorMessage = "";
        manageProcess.command = [runtimeConfig.appRegistryManageBin, "apply"];
        manageProcess.running = true;
    }

    function resetWorkingCopy() {
        if (manageProcess.running) {
            manageProcess.running = false;
        }
        editorBusy = true;
        editorError = "";
        editorMessage = "";
        manageProcess.command = [runtimeConfig.appRegistryManageBin, "reset"];
        manageProcess.running = true;
    }

    onActiveChanged: {
        if (active) {
            reloadEntries();
        }
    }

    Component.onCompleted: {
        if (active) {
            reloadEntries();
        }
    }

    Process {
        id: listProcess
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                const raw = pane.stringOrEmpty(data).trim();
                if (!raw) {
                    pane.entries = [];
                    pane.loading = false;
                    pane.resetEditor();
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    pane.entries = Array.isArray(parsed) ? parsed : [];
                    pane.selectedIndex = Math.max(0, Math.min(pane.selectedIndex, pane.displayEntries.length - 1));
                    pane.loadEntry(pane.activeEntry());
                    pane.statusText = pane.entries.length + " app" + (pane.entries.length === 1 ? "" : "s");
                    pane.loading = false;
                } catch (error) {
                    pane.entries = [];
                    pane.loading = false;
                    pane.errorText = "Unable to load app registry entries";
                    console.warn("app-registry.list.parse:", raw, error);
                }
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                const raw = pane.stringOrEmpty(data).trim();
                if (raw.length > 0) {
                    pane.errorText = raw;
                }
            }
        }
        onExited: function(exitCode) {
            pane.loading = false;
            if (exitCode !== 0 && !pane.errorText) {
                pane.errorText = "App registry query failed";
            }
        }
    }

    Process {
        id: manageProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = pane.stringOrEmpty(text).trim();
                pane.editorBusy = false;
                if (!raw) {
                    pane.reloadEntries();
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    pane.editorMessage = pane.stringOrEmpty(parsed && parsed.message);
                    pane.statusText = pane.editorMessage;
                    pane.reloadEntries();
                } catch (error) {
                    pane.editorError = "Unable to update app registry";
                    console.warn("app-registry.manage.parse:", raw, error);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const raw = pane.stringOrEmpty(text).trim();
                if (raw.length > 0) {
                    pane.editorError = raw;
                }
            }
        }
        onExited: function(exitCode) {
            pane.editorBusy = false;
            if (exitCode !== 0 && !pane.editorError) {
                pane.editorError = "App registry action failed";
            }
        }
    }

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
                    text: "App Registry"
                    color: colors.text
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Text {
                    text: "Edit the live app-registry working copy, then apply those changes back into declarative JSON."
                    color: colors.subtle
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }

            Button {
                text: "Close"
                onClicked: shellRoot.closeSettings()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: errorText.length > 0 ? errorText : (loading ? "Loading apps" : statusText)
                color: errorText.length > 0 ? colors.red : colors.subtle
                font.pixelSize: 10
            }

            Text {
                text: editorError.length > 0 ? editorError : editorMessage
                color: editorError.length > 0 ? colors.red : colors.subtle
                font.pixelSize: 10
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { id: "all", label: "All", value: pane.totalCount },
                    { id: "scoped", label: "Scoped", value: pane.scopedCount },
                    { id: "global", label: "Global", value: pane.globalCount },
                    { id: "pwa", label: "PWA", value: pane.pwaCount },
                    { id: "dirty", label: "Live", value: pane.dirtyCount }
                ]

                delegate: Rectangle {
                    required property var modelData
                    readonly property var chip: modelData
                    readonly property bool selected: pane.filterMode === pane.stringOrEmpty(chip && chip.id)

                    Layout.preferredWidth: metricsRow.implicitWidth + 16
                    height: 28
                    radius: 7
                    color: selected ? colors.blueBg : colors.cardAlt
                    border.color: selected ? colors.blue : colors.lineSoft
                    border.width: 1

                    RowLayout {
                        id: metricsRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: pane.stringOrEmpty(chip && chip.label)
                            color: selected ? colors.blue : colors.text
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            radius: 5
                            color: selected ? colors.bg : colors.panel
                            implicitWidth: countText.implicitWidth + 8
                            implicitHeight: countText.implicitHeight + 3

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: String(Number(chip && chip.value || 0))
                                color: selected ? colors.blue : colors.textDim
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.setFilterMode(pane.stringOrEmpty(chip && chip.id))
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 340
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
                            id: queryField
                            Layout.fillWidth: true
                            text: pane.query
                            placeholderText: "Search apps"
                            color: colors.text
                            selectByMouse: true
                            background: Rectangle {
                                radius: 8
                                color: colors.panel
                                border.color: queryField.activeFocus ? colors.teal : colors.border
                                border.width: 1
                            }
                            onTextChanged: {
                                pane.query = text;
                                queryDebounce.restart();
                            }
                        }

                        Button {
                            text: "Reload"
                            enabled: !pane.loading
                            onClicked: pane.reloadEntries()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text: "Apply"
                            enabled: !pane.editorBusy
                            onClicked: pane.applyWorkingCopy()
                        }

                        Button {
                            text: "Reset"
                            enabled: !pane.editorBusy
                            onClicked: pane.resetWorkingCopy()
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: colors.lineSoft
                    }

                    ScriptModel {
                        id: appEntriesModel
                        values: pane.displayEntries
                        objectProp: "modelData"
                    }

                    ListView {
                        id: appList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        model: appEntriesModel

                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            readonly property var entry: modelData
                            readonly property int itemIndex: index
                            readonly property bool selected: itemIndex === pane.selectedIndex

                            width: appList.width - 4
                            height: 88
                            radius: 10
                            color: selected ? colors.blueBg : (mouseArea.containsMouse ? colors.panelAlt : "transparent")
                            border.color: selected ? colors.blue : (mouseArea.containsMouse ? colors.borderStrong : colors.lineSoft)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 10
                                anchors.bottomMargin: 10
                                spacing: 10

                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 10
                                    color: selected ? colors.bg : colors.card
                                    border.color: selected ? colors.blueMuted : colors.lineSoft
                                    border.width: 1

                                    IconImage {
                                        visible: pane.iconSource(entry) !== ""
                                        anchors.centerIn: parent
                                        implicitSize: 22
                                        source: pane.iconSource(entry)
                                        mipmap: true
                                    }

                                    Text {
                                        visible: pane.iconSource(entry) === ""
                                        anchors.centerIn: parent
                                        text: pane.stringOrEmpty(entry && entry.text).slice(0, 1).toUpperCase()
                                        color: selected ? colors.blue : colors.textDim
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Text {
                                            Layout.fillWidth: true
                                            text: pane.stringOrEmpty(entry && entry.text)
                                            color: colors.text
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: pane.stringOrEmpty(entry && entry.name)
                                            color: selected ? colors.blue : colors.textDim
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: pane.stringOrEmpty(entry && entry.subtext)
                                            color: colors.subtle
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Repeater {
                                                model: pane.arrayOrEmpty(entry && entry.badges)

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property var badge: modelData
                                                    readonly property string tone: pane.stringOrEmpty(badge && badge.tone)

                                                    height: 18
                                                    radius: 6
                                                    color: pane.badgeBackground(tone)
                                                    border.color: pane.badgeColor(tone)
                                                    border.width: 1
                                                    Layout.preferredWidth: badgeText.implicitWidth + 10

                                                    Text {
                                                        id: badgeText
                                                        anchors.centerIn: parent
                                                        text: pane.stringOrEmpty(badge && badge.label)
                                                        color: pane.badgeColor(tone)
                                                        font.pixelSize: 8
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: pane.selectedIndex = itemIndex
                                onClicked: {
                                    pane.selectedIndex = itemIndex;
                                    pane.loadEntry(entry);
                                }
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

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            radius: 10
                            color: colors.panel
                            border.color: colors.lineSoft
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 46
                                    height: 46
                                    radius: 12
                                    color: colors.cardAlt
                                    border.color: colors.lineSoft
                                    border.width: 1

                                    IconImage {
                                        visible: pane.iconSource(pane.activeEntry()) !== ""
                                        anchors.centerIn: parent
                                        implicitSize: 26
                                        source: pane.iconSource(pane.activeEntry())
                                        mipmap: true
                                    }

                                    Text {
                                        visible: pane.iconSource(pane.activeEntry()) === ""
                                        anchors.centerIn: parent
                                        text: currentAppName.length > 0 ? currentAppName.slice(0, 1).toUpperCase() : "?"
                                        color: colors.textDim
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: currentAppName.length > 0 ? currentAppName : "Select an app"
                                        color: colors.text
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: currentScope.length > 0 ? "Scope: " + currentScope + "  •  WM_CLASS: " + currentExpectedClass : "Editable fields are stored in the working copy only."
                                        color: colors.subtle
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: currentCommand.length > 0 ? "Command: " + currentCommand : ""
                                        visible: currentCommand.length > 0
                                        color: colors.subtle
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Repeater {
                                            model: pane.arrayOrEmpty(pane.activeEntry() && pane.activeEntry().badges)

                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property var badge: modelData
                                                readonly property string tone: pane.stringOrEmpty(badge && badge.tone)

                                                height: 18
                                                radius: 6
                                                color: pane.badgeBackground(tone)
                                                border.color: pane.badgeColor(tone)
                                                border.width: 1
                                                Layout.preferredWidth: headerBadgeText.implicitWidth + 10

                                                Text {
                                                    id: headerBadgeText
                                                    anchors.centerIn: parent
                                                    text: pane.stringOrEmpty(badge && badge.label)
                                                    color: pane.badgeColor(tone)
                                                    font.pixelSize: 8
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 8

                            Text {
                                text: "Display Name"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            TextField {
                                id: displayNameField
                                Layout.fillWidth: true
                                text: pane.editorDisplayName
                                color: colors.text
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                background: Rectangle {
                                    radius: 8
                                    color: colors.panel
                                    border.color: displayNameField.activeFocus ? colors.teal : colors.border
                                    border.width: 1
                                }
                                onTextChanged: {
                                    if (!pane.editorSyncing) {
                                        pane.editorDisplayName = text;
                                    }
                                }
                            }

                            Text {
                                text: "Description"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            TextField {
                                id: descriptionField
                                Layout.fillWidth: true
                                text: pane.editorDescription
                                color: colors.text
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                background: Rectangle {
                                    radius: 8
                                    color: colors.panel
                                    border.color: descriptionField.activeFocus ? colors.blue : colors.border
                                    border.width: 1
                                }
                                onTextChanged: {
                                    if (!pane.editorSyncing) {
                                        pane.editorDescription = text;
                                    }
                                }
                            }

                            Text {
                                text: "Workspace"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            TextField {
                                id: workspaceField
                                Layout.fillWidth: true
                                text: pane.editorWorkspace
                                placeholderText: "1-9 or empty"
                                color: colors.text
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                background: Rectangle {
                                    radius: 8
                                    color: colors.panel
                                    border.color: workspaceField.activeFocus ? colors.blue : colors.border
                                    border.width: 1
                                }
                                onTextChanged: {
                                    if (!pane.editorSyncing) {
                                        pane.editorWorkspace = text;
                                    }
                                }
                            }

                            Text {
                                text: "Monitor Role"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                model: ["", "primary", "secondary", "tertiary"]
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                currentIndex: Math.max(0, model.indexOf(pane.editorMonitorRole))
                                onActivated: pane.editorMonitorRole = currentText
                            }

                            Text {
                                text: "Floating Size"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                model: ["", "scratchpad", "small", "medium", "large"]
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                currentIndex: Math.max(0, model.indexOf(pane.editorFloatingSize))
                                onActivated: pane.editorFloatingSize = currentText
                            }

                            Text {
                                text: "Fallback"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            ComboBox {
                                Layout.fillWidth: true
                                model: ["", "skip", "use_home", "error"]
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                currentIndex: Math.max(0, model.indexOf(pane.editorFallbackBehavior))
                                onActivated: pane.editorFallbackBehavior = currentText
                            }

                            Text {
                                text: "Icon"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            TextField {
                                id: iconField
                                Layout.fillWidth: true
                                text: pane.editorIcon
                                color: colors.text
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                background: Rectangle {
                                    radius: 8
                                    color: colors.panel
                                    border.color: iconField.activeFocus ? colors.blue : colors.border
                                    border.width: 1
                                }
                                onTextChanged: {
                                    if (!pane.editorSyncing) {
                                        pane.editorIcon = text;
                                    }
                                }
                            }

                            Text {
                                text: "Aliases"
                                color: colors.textDim
                                font.pixelSize: 10
                            }

                            TextField {
                                id: aliasesField
                                Layout.fillWidth: true
                                text: pane.editorAliases
                                placeholderText: "code, vsc"
                                color: colors.text
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                background: Rectangle {
                                    radius: 8
                                    color: colors.panel
                                    border.color: aliasesField.activeFocus ? colors.blue : colors.border
                                    border.width: 1
                                }
                                onTextChanged: {
                                    if (!pane.editorSyncing) {
                                        pane.editorAliases = text;
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            CheckBox {
                                text: "Floating"
                                checked: pane.editorFloating
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                onToggled: pane.editorFloating = checked
                            }

                            CheckBox {
                                text: "Multi-instance"
                                checked: pane.editorMultiInstance
                                enabled: !pane.editorBusy && pane.currentAppName.length > 0
                                onToggled: pane.editorMultiInstance = checked
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Button {
                                text: pane.editorBusy ? "Saving..." : "Save Live"
                                enabled: pane.currentAppName.length > 0 && !pane.editorBusy
                                onClicked: pane.saveOverride()
                            }

                            Button {
                                text: "Clear Override"
                                enabled: pane.currentAppName.length > 0 && !pane.editorBusy
                                onClicked: pane.clearOverride()
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

    Timer {
        id: queryDebounce
        interval: 100
        repeat: false
        onTriggered: pane.reloadEntries()
    }
}
