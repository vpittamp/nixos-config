import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    AppConfig {
        id: appConfig
    }

    WorktreeAppService {
        id: appService
        appConfig: appConfig
    }

    // Standalone launches must create a visible window immediately; otherwise
    // QuickShell exits before the wrapper can send an IPC open/toggle request.
    property bool windowVisible: true
    property string query: ""
    property string filterMode: "all"
    property string createRepoValue: ""
    property string createBranchValue: ""
    property string createBaseValue: "main"
    property string renameBranchValue: ""
    property bool removeForceValue: false
    property var palette: ({
            bg: "#09111a",
            panel: "#101a26",
            panelAlt: "#152131",
            card: "#162334",
            cardAlt: "#1a2940",
            border: "#2a3a50",
            borderStrong: "#41536f",
            text: "#ebf1f8",
            textDim: "#c2cfdf",
            muted: "#8ea3bb",
            subtle: "#6f8198",
            blue: "#86c5ff",
            blueBg: "#17324a",
            teal: "#5eead4",
            tealBg: "#10373c",
            amber: "#f8d38c",
            amberBg: "#3d2c12",
            red: "#f9a8b4",
            redBg: "#3e1720",
            green: "#86efac",
            greenBg: "#12311f"
        })

    function stringOrEmpty(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function arrayOrEmpty(value) {
        if (!value)
            return [];
        if (Array.isArray(value))
            return value;
        try {
            return Array.from(value);
        } catch (_error) {
            return [];
        }
    }

    function boolOrFalse(value) {
        return !!value;
    }

    function numberOrZero(value) {
        const number = Number(value || 0);
        return Number.isFinite(number) ? number : 0;
    }

    function shortProject(qualifiedName) {
        const qualified = stringOrEmpty(qualifiedName);
        const repo = qualified.split(":")[0];
        const parts = repo.split("/");
        return parts[parts.length - 1] || repo;
    }

    function repoQualified(qualifiedName) {
        return stringOrEmpty(qualifiedName).split(":")[0] || "";
    }

    function branchName(qualifiedName) {
        return stringOrEmpty(qualifiedName).split(":").slice(1).join(":") || "";
    }

    function activeQualifiedName() {
        const context = appService.dashboard.active_context || {};
        return stringOrEmpty(context.qualified_name || context.project_name);
    }

    function worktreeSessions(qualifiedName) {
        const target = stringOrEmpty(qualifiedName);
        return arrayOrEmpty(appService.dashboard.active_ai_sessions).filter(session => {
            const projectName = stringOrEmpty(session && (session.project_name || session.project));
            return projectName === target;
        });
    }

    function worktreeGroups(qualifiedName) {
        const target = stringOrEmpty(qualifiedName);
        const groups = arrayOrEmpty(appService.dashboard.projects).filter(group => stringOrEmpty(group && group.project) === target);
        groups.sort((left, right) => stringOrEmpty(left.target_host).localeCompare(stringOrEmpty(right.target_host)));
        return groups;
    }

    function matchesFilter(worktree) {
        if (filterMode === "active")
            return boolOrFalse(worktree.is_active);
        if (filterMode === "dirty")
            return numberOrZero(worktree.dirty_count) > 0 || boolOrFalse(worktree.has_conflicts);
        if (filterMode === "remote")
            return boolOrFalse(worktree.host_profile_available);
        if (filterMode === "sessions")
            return worktreeSessions(worktree.qualified_name).length > 0;
        if (filterMode === "windows")
            return numberOrZero(worktree.visible_window_count) > 0 || numberOrZero(worktree.scoped_window_count) > 0;
        return true;
    }

    function matchesQuery(worktree) {
        const haystack = [
            stringOrEmpty(worktree.qualified_name),
            stringOrEmpty(worktree.repo_display),
            stringOrEmpty(worktree.branch),
            stringOrEmpty(worktree.last_commit_message)
        ].join(" ").toLowerCase();
        const tokens = stringOrEmpty(query).trim().toLowerCase().split(/\s+/).filter(token => token.length > 0);
        if (!tokens.length)
            return true;
        return tokens.every(token => haystack.indexOf(token) >= 0);
    }

    function filteredWorktrees() {
        return arrayOrEmpty(appService.dashboard.worktrees).filter(worktree => matchesFilter(worktree) && matchesQuery(worktree));
    }

    function currentWorktree() {
        const items = filteredWorktrees();
        if (!items.length)
            return null;
        const selected = items.find(item => stringOrEmpty(item.qualified_name) === stringOrEmpty(appService.selectedQualifiedName));
        return selected || items[0];
    }

    function selectedWindowForGroup(group) {
        const windows = arrayOrEmpty(group && group.windows).filter(windowData => !boolOrFalse(windowData.hidden));
        const focusedWindow = windows.find(windowData => boolOrFalse(windowData.focused));
        return focusedWindow || (windows.length ? windows[0] : null);
    }

    function sessionLabel(session) {
        const tool = stringOrEmpty(session && session.tool) || "assistant";
        const pane = stringOrEmpty(session && (session.pane_label || session.tmux_pane));
        return pane ? `${tool} ${pane}` : tool;
    }

    function sessionMeta(session) {
        const phase = stringOrEmpty(session && (session.session_phase_label || session.session_phase)) || "idle";
        const host = stringOrEmpty(session && (session.target_host || session.host_name || session.connection_key));
        return host ? `${phase}  •  ${host}` : phase;
    }

    function prepareCreateDialog() {
        const current = currentWorktree();
        createRepoValue = current ? repoQualified(current.qualified_name) : stringOrEmpty(arrayOrEmpty(appService.dashboard.worktrees)[0] && repoQualified(arrayOrEmpty(appService.dashboard.worktrees)[0].qualified_name));
        createBranchValue = "";
        createBaseValue = current ? (stringOrEmpty(current.is_main ? current.branch : "main") || "main") : "main";
        createDialog.open();
    }

    function prepareRenameDialog() {
        const current = currentWorktree();
        renameBranchValue = current ? branchName(current.qualified_name) : "";
        renameDialog.open();
    }

    function prepareRemoveDialog() {
        removeForceValue = false;
        removeDialog.open();
    }

    function openWindow() {
        windowVisible = true;
        appService.ensureWatcher();
        appService.requestSnapshot();
        focusTimer.restart();
    }

    function toggleWindow() {
        if (windowVisible) {
            windowVisible = false;
            return;
        }
        openWindow();
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: searchField.forceActiveFocus()
    }

    IpcHandler {
        target: "app"

        function toggle() {
            root.toggleWindow();
        }

        function open() {
            root.openWindow();
        }

        function close() {
            root.windowVisible = false;
        }
    }

    Component.onCompleted: {
        appService.ensureWatcher();
        appService.requestSnapshot();
    }

    FloatingWindow {
        id: managerWindow
        visible: root.windowVisible
        implicitWidth: appConfig.windowWidth
        implicitHeight: appConfig.windowHeight
        minimumSize: Qt.size(960, 640)
        title: appConfig.windowTitle
        color: root.palette.bg

        onClosed: {
            root.windowVisible = false;
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                color: root.palette.panel
                border.color: root.palette.border
                border.width: 1
                implicitHeight: 72

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 14
                        color: root.palette.blueBg
                        border.color: root.palette.blue
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "WT"
                            color: root.palette.blue
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: appConfig.windowTitle
                            color: root.palette.text
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: `${root.shortProject(root.activeQualifiedName() || "global")}  •  ${appConfig.hostName}  •  ${stringOrEmpty(appService.dashboard.active_context && appService.dashboard.active_context.target_host) || appConfig.hostName}`
                            color: root.palette.subtle
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        visible: appService.busyLabel !== ""
                        radius: 9
                        color: root.palette.tealBg
                        border.color: root.palette.teal
                        border.width: 1
                        Layout.preferredWidth: busyText.implicitWidth + 18
                        implicitHeight: 28

                        Text {
                            id: busyText
                            anchors.centerIn: parent
                            text: appService.busyLabel
                            color: root.palette.teal
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                color: "transparent"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        radius: 16
                        color: root.palette.panel
                        border.color: root.palette.border
                        border.width: 1
                        implicitHeight: controlsRow.implicitHeight + 22

                        RowLayout {
                            id: controlsRow
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 11
                            anchors.bottomMargin: 11
                            spacing: 10

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Search repo, branch, commit message"
                                text: root.query
                                onTextChanged: root.query = text
                            }

                            ComboBox {
                                id: filterCombo
                                Layout.preferredWidth: 160
                                model: [
                                    { label: "All worktrees", value: "all" },
                                    { label: "Active", value: "active" },
                                { label: "Dirty", value: "dirty" },
                                { label: "Remote", value: "remote" },
                                { label: "Sessions", value: "sessions" },
                                { label: "Windows", value: "windows" }
                            ]
                            textRole: "label"
                            onActivated: root.filterMode = model[index].value
                        }

                        Button {
                            text: "Create"
                            onClicked: root.prepareCreateDialog()
                        }

                        Button {
                            text: "Global"
                            enabled: !appService.busy
                            onClicked: appService.clearContext()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: appService.actionError !== "" || appService.actionMessage !== ""
                    radius: 14
                    color: appService.actionError !== "" ? root.palette.redBg : root.palette.greenBg
                    border.color: appService.actionError !== "" ? root.palette.red : root.palette.green
                    border.width: 1
                    implicitHeight: feedbackText.implicitHeight + 20

                    Text {
                        id: feedbackText
                        anchors.fill: parent
                        anchors.margins: 10
                        text: appService.actionError !== "" ? appService.actionError : appService.actionMessage
                        color: appService.actionError !== "" ? root.palette.red : root.palette.green
                        wrapMode: Text.Wrap
                        font.pixelSize: 11
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 350
                        Layout.fillHeight: true
                        radius: 18
                        color: root.palette.panel
                        border.color: root.palette.border
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    Layout.fillWidth: true
                                    text: `Worktrees (${root.filteredWorktrees().length})`
                                    color: root.palette.text
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: `${arrayOrEmpty(appService.dashboard.active_ai_sessions).length} sessions`
                                    color: root.palette.subtle
                                    font.pixelSize: 10
                                }
                            }

                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 8
                                model: root.filteredWorktrees()

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selected: root.currentWorktree() && root.stringOrEmpty(root.currentWorktree().qualified_name) === root.stringOrEmpty(modelData.qualified_name)
                                    readonly property int sessionsCount: root.worktreeSessions(modelData.qualified_name).length

                                    width: ListView.view.width
                                    radius: 14
                                    color: selected ? root.palette.blueBg : (worktreeMouse.containsMouse ? root.palette.cardAlt : root.palette.card)
                                    border.color: selected ? root.palette.blue : (worktreeMouse.containsMouse ? root.palette.borderStrong : root.palette.border)
                                    border.width: 1
                                    implicitHeight: 96

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                Layout.fillWidth: true
                                                text: `${root.shortProject(modelData.qualified_name)} / ${root.branchName(modelData.qualified_name)}`
                                                color: selected ? root.palette.blue : root.palette.text
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                visible: root.boolOrFalse(modelData.is_active)
                                                radius: 7
                                                color: root.palette.tealBg
                                                border.color: root.palette.teal
                                                border.width: 1
                                                Layout.preferredWidth: 54
                                                implicitHeight: 22

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Active"
                                                    color: root.palette.teal
                                                    font.pixelSize: 9
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.stringOrEmpty(modelData.repo_display)
                                            color: root.palette.subtle
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: `${root.numberOrZero(modelData.visible_window_count)} visible`
                                                color: root.palette.textDim
                                                font.pixelSize: 10
                                            }

                                            Text {
                                                text: `${root.numberOrZero(modelData.scoped_window_count)} scoped`
                                                color: root.palette.textDim
                                                font.pixelSize: 10
                                            }

                                            Text {
                                                text: `${sessionsCount} sessions`
                                                color: root.palette.textDim
                                                font.pixelSize: 10
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.stringOrEmpty(modelData.last_commit_message) || modelData.path
                                            color: root.palette.muted
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: worktreeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: appService.selectedQualifiedName = root.stringOrEmpty(modelData.qualified_name)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 18
                        color: root.palette.panel
                        border.color: root.palette.border
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            Text {
                                visible: !root.currentWorktree()
                                text: "No worktrees match the current filter."
                                color: root.palette.subtle
                                font.pixelSize: 14
                            }

                            Rectangle {
                                visible: !!root.currentWorktree()
                                Layout.fillWidth: true
                                radius: 16
                                color: root.palette.card
                                border.color: root.palette.border
                                border.width: 1
                                implicitHeight: detailsColumn.implicitHeight + 24

                                ColumnLayout {
                                    id: detailsColumn
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                text: root.currentWorktree() ? root.stringOrEmpty(root.currentWorktree().qualified_name) : ""
                                                color: root.palette.text
                                                font.pixelSize: 17
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: root.currentWorktree() ? root.stringOrEmpty(root.currentWorktree().path) : ""
                                                color: root.palette.subtle
                                                font.pixelSize: 10
                                                elide: Text.ElideMiddle
                                            }
                                        }

                                        Button {
                                            text: "Open Path"
                                            enabled: !!root.currentWorktree()
                                            onClicked: {
                                                const item = root.currentWorktree();
                                                if (item)
                                                    appService.openPath(item.path);
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Repeater {
                                            model: root.currentWorktree() ? [
                                                { text: `${root.numberOrZero(root.currentWorktree().dirty_count)} dirty`, fill: root.numberOrZero(root.currentWorktree().dirty_count) > 0 ? root.palette.amberBg : root.palette.cardAlt, border: root.numberOrZero(root.currentWorktree().dirty_count) > 0 ? root.palette.amber : root.palette.border, color: root.numberOrZero(root.currentWorktree().dirty_count) > 0 ? root.palette.amber : root.palette.textDim },
                                                { text: root.boolOrFalse(root.currentWorktree().host_profile_available) ? `Peer host ${root.stringOrEmpty(root.currentWorktree().host_profile_host)}` : "Current host only", fill: root.boolOrFalse(root.currentWorktree().host_profile_available) ? root.palette.blueBg : root.palette.cardAlt, border: root.boolOrFalse(root.currentWorktree().host_profile_available) ? root.palette.blue : root.palette.border, color: root.boolOrFalse(root.currentWorktree().host_profile_available) ? root.palette.blue : root.palette.textDim },
                                                { text: `${root.numberOrZero(root.currentWorktree().ahead)} ahead / ${root.numberOrZero(root.currentWorktree().behind)} behind`, fill: root.palette.cardAlt, border: root.palette.border, color: root.palette.textDim }
                                            ] : []

                                            delegate: Rectangle {
                                                required property var modelData
                                                radius: 8
                                                color: modelData.fill
                                                border.color: modelData.border
                                                border.width: 1
                                                implicitHeight: 26
                                                Layout.preferredWidth: chipText.implicitWidth + 16

                                                Text {
                                                    id: chipText
                                                    anchors.centerIn: parent
                                                    text: modelData.text
                                                    color: modelData.color
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Button {
                                            text: "Switch Current Host"
                                            enabled: !!root.currentWorktree() && !appService.busy
                                            onClicked: {
                                                const item = root.currentWorktree();
                                                if (item)
                                                    appService.switchWorktree(item.qualified_name, appConfig.hostName);
                                            }
                                        }

                                        Button {
                                            text: "Switch Peer Host"
                                            enabled: !!root.currentWorktree() && root.boolOrFalse(root.currentWorktree().host_profile_available) && !appService.busy
                                            onClicked: {
                                                const item = root.currentWorktree();
                                                if (item)
                                                    appService.switchWorktree(item.qualified_name, item.host_profile_host || "");
                                            }
                                        }

                                        Button {
                                            text: "Rename"
                                            enabled: !!root.currentWorktree() && !appService.busy
                                            onClicked: root.prepareRenameDialog()
                                        }

                                        Button {
                                            text: "Remove"
                                            enabled: !!root.currentWorktree() && !appService.busy
                                            onClicked: root.prepareRemoveDialog()
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Button {
                                            text: "Open Current Host Shell"
                                            enabled: !!root.currentWorktree() && !appService.busy
                                            onClicked: {
                                                const item = root.currentWorktree();
                                                if (item)
                                                    appService.openTerminal(item.qualified_name, appConfig.hostName);
                                            }
                                        }

                                        Button {
                                            text: "Open Peer Host Shell"
                                            enabled: !!root.currentWorktree() && root.boolOrFalse(root.currentWorktree().host_profile_available) && !appService.busy
                                            onClicked: {
                                                const item = root.currentWorktree();
                                                if (item)
                                                    appService.openTerminal(item.qualified_name, item.host_profile_host || "");
                                            }
                                        }
                                    }

                                    Text {
                                        visible: !!root.currentWorktree() && root.stringOrEmpty(root.currentWorktree().last_commit_message) !== ""
                                        text: root.currentWorktree() ? root.stringOrEmpty(root.currentWorktree().last_commit_message) : ""
                                        color: root.palette.textDim
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 12
                                visible: !!root.currentWorktree()

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 16
                                    color: root.palette.card
                                    border.color: root.palette.border
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        Text {
                                            text: "Context Windows"
                                            color: root.palette.text
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                        }

                                        Flickable {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            contentWidth: width
                                            contentHeight: windowGroupsColumn.implicitHeight
                                            clip: true

                                            ColumnLayout {
                                                id: windowGroupsColumn
                                                width: parent.width
                                                spacing: 8

                                                Repeater {
                                                    model: root.currentWorktree() ? root.worktreeGroups(root.currentWorktree().qualified_name) : []

                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        readonly property var preferredWindow: root.selectedWindowForGroup(modelData)

                                                        Layout.fillWidth: true
                                                        radius: 12
                                                        color: root.palette.panelAlt
                                                        border.color: root.palette.border
                                                        border.width: 1
                                                        implicitHeight: windowGroupColumn.implicitHeight + 18

                                                        ColumnLayout {
                                                            id: windowGroupColumn
                                                            anchors.fill: parent
                                                            anchors.margins: 9
                                                            spacing: 6

                                                            RowLayout {
                                                                Layout.fillWidth: true

                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: `${root.stringOrEmpty(modelData.target_host || appConfig.hostName)}  •  ${root.numberOrZero(modelData.visible_window_count)} visible / ${root.numberOrZero(modelData.hidden_window_count)} hidden`
                                                                    color: root.palette.text
                                                                    font.pixelSize: 11
                                                                    font.weight: Font.DemiBold
                                                                }

                                                                Button {
                                                                    text: "Focus"
                                                                    enabled: !!preferredWindow && !appService.busy
                                                                    onClicked: appService.focusWindow(preferredWindow.id, modelData.project, modelData.target_host, preferredWindow.connection_key)
                                                                }

                                                                Button {
                                                                    text: "Shell"
                                                                    enabled: !appService.busy
                                                                    onClicked: appService.openTerminal(modelData.project, modelData.target_host || appConfig.hostName)
                                                                }
                                                            }

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: preferredWindow ? root.stringOrEmpty(preferredWindow.title) : "No visible windows in this context."
                                                                color: root.palette.subtle
                                                                font.pixelSize: 10
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 16
                                    color: root.palette.card
                                    border.color: root.palette.border
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        Text {
                                            text: "AI Sessions"
                                            color: root.palette.text
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                        }

                                        ListView {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            spacing: 8
                                            model: root.currentWorktree() ? root.worktreeSessions(root.currentWorktree().qualified_name) : []

                                            delegate: Rectangle {
                                                required property var modelData
                                                width: ListView.view.width
                                                radius: 12
                                                color: sessionMouse.containsMouse ? root.palette.cardAlt : root.palette.panelAlt
                                                border.color: sessionMouse.containsMouse ? root.palette.borderStrong : root.palette.border
                                                border.width: 1
                                                implicitHeight: 72

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 10

                                                    Rectangle {
                                                        Layout.preferredWidth: 36
                                                        Layout.preferredHeight: 36
                                                        radius: 10
                                                        color: root.palette.tealBg
                                                        border.color: root.palette.teal
                                                        border.width: 1

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: root.sessionLabel(modelData).slice(0, 2).toUpperCase()
                                                            color: root.palette.teal
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 3

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.sessionLabel(modelData)
                                                            color: root.palette.text
                                                            font.pixelSize: 12
                                                            font.weight: Font.DemiBold
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.sessionMeta(modelData)
                                                            color: root.palette.subtle
                                                            font.pixelSize: 10
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    Button {
                                                        text: "Focus"
                                                        enabled: !appService.busy
                                                        onClicked: appService.focusSession(root.stringOrEmpty(modelData.session_key))
                                                    }
                                                }

                                                MouseArea {
                                                    id: sessionMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onDoubleClicked: appService.focusSession(root.stringOrEmpty(modelData.session_key))
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

        Dialog {
            id: createDialog
            modal: true
            title: "Create Worktree"
            width: 420
            standardButtons: Dialog.Ok | Dialog.Cancel

            onAccepted: {
                appService.createWorktree(root.createRepoValue, root.createBranchValue, root.createBaseValue);
            }

            contentItem: ColumnLayout {
                spacing: 10

                ComboBox {
                    id: createRepoField
                    Layout.fillWidth: true
                    editable: true
                    model: Array.from(new Set(root.arrayOrEmpty(appService.dashboard.worktrees).map(item => root.repoQualified(item.qualified_name)).filter(Boolean)))
                    editText: root.createRepoValue
                    onEditTextChanged: root.createRepoValue = editText
                    onActivated: root.createRepoValue = currentText
                }

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "New branch"
                    text: root.createBranchValue
                    onTextChanged: root.createBranchValue = text
                }

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "Base branch"
                    text: root.createBaseValue
                    onTextChanged: root.createBaseValue = text
                }
            }
        }

        Dialog {
            id: renameDialog
            modal: true
            title: "Rename Worktree"
            width: 360
            standardButtons: Dialog.Ok | Dialog.Cancel

            onAccepted: {
                const item = root.currentWorktree();
                if (item)
                    appService.renameWorktree(item.qualified_name, root.renameBranchValue, false);
            }

            contentItem: ColumnLayout {
                spacing: 10

                Text {
                    text: root.currentWorktree() ? `Rename ${root.currentWorktree().qualified_name}` : ""
                    color: root.palette.subtle
                }

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "New branch"
                    text: root.renameBranchValue
                    onTextChanged: root.renameBranchValue = text
                }
            }
        }

        Dialog {
            id: removeDialog
            modal: true
            title: "Remove Worktree"
            width: 380
            standardButtons: Dialog.Ok | Dialog.Cancel

            onAccepted: {
                const item = root.currentWorktree();
                if (item)
                    appService.removeWorktree(item.qualified_name, root.removeForceValue);
            }

            contentItem: ColumnLayout {
                spacing: 10

                Text {
                    text: root.currentWorktree() ? `Remove ${root.currentWorktree().qualified_name}?` : ""
                    color: root.palette.text
                    wrapMode: Text.Wrap
                }

                CheckBox {
                    text: "Force remove dirty worktree"
                    checked: root.removeForceValue
                    onToggled: root.removeForceValue = checked
                }
            }
        }
    }
}
