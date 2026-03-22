import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    required property var service
    property bool autoFollowTranscript: true
    property bool showSessionPicker: false
    property bool showTargetPicker: false
    property var palette: ({
        bg: "#0f1720",
        panel: "#101925",
        panelAlt: "#16202d",
        cardAlt: "#1b2635",
        border: "#273246",
        lineSoft: "#273246",
        text: "#e2e8f0",
        textDim: "#cbd5e1",
        subtle: "#94a3b8",
        muted: "#64748b",
        blue: "#60a5fa",
        blueBg: "#16243a",
        accent: "#2dd4bf",
        accentBg: "#12373a",
        orange: "#fb923c",
        orangeBg: "#3a2414",
        red: "#f87171",
        redBg: "#3b1720"
    })
    property string contextLabel: ""
    property string contextDetails: ""
    readonly property bool showStatusBanner: service.errorMessage !== ""
        || service.hasError
        || service.hasPendingApproval
        || service.isGenerating
        || service.actionRunning
    readonly property string statusBannerTone: service.errorMessage !== "" || service.hasError
        ? "error"
        : (service.hasPendingApproval ? "approval" : ((service.isGenerating || service.actionRunning) ? "running" : ""))
    readonly property string statusBannerLabel: statusBannerTone === "error"
        ? "Issue"
        : (statusBannerTone === "approval" ? "Approval Required" : "In Progress")
    readonly property string statusBannerText: service.errorMessage !== ""
        ? service.errorMessage
        : (service.hasError
            ? service.stringValue(service.currentSession && service.currentSession.last_error, "The current session failed.")
            : (service.hasPendingApproval
                ? "This session needs approval before it can continue."
                : (service.isGenerating
                    ? "The current session is still running. New messages stay disabled until this turn finishes."
                    : (service.actionRunning ? "Syncing with the daemon…" : ""))))

    function blockText(value) {
        if (value === undefined || value === null)
            return "";
        if (typeof value === "string")
            return value;
        return JSON.stringify(value, null, 2);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            radius: 12
            color: root.palette.panel
            border.color: root.palette.border
            border.width: 1
            implicitHeight: compactHeaderLayout.implicitHeight + 14

            ColumnLayout {
                id: compactHeaderLayout
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 7
                anchors.bottomMargin: 7
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: service.currentSession ? service.currentSessionTitle : "Agent Chat"
                            color: root.palette.text
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: service.currentSession
                                ? service.currentSessionSubtitle
                                : (contextLabel !== "" ? contextLabel + "  •  " + contextDetails : "Daemon-owned Codex harness")
                            color: root.palette.subtle
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        visible: service.isGenerating || service.hasPendingApproval || service.actionRunning || service.hasError
                        height: 20
                        radius: 6
                        color: service.hasError
                            ? root.palette.redBg
                            : (service.hasPendingApproval ? root.palette.orangeBg : root.palette.accentBg)
                        border.color: service.hasError
                            ? root.palette.red
                            : (service.hasPendingApproval ? root.palette.orange : root.palette.accent)
                        border.width: 1
                        Layout.preferredWidth: headerStatusText.implicitWidth + 14

                        Text {
                            id: headerStatusText
                            anchors.centerIn: parent
                            text: service.hasError ? "Error" : (service.hasPendingApproval ? "Approval" : (service.isGenerating ? "Running" : "Syncing"))
                            color: service.hasError
                                ? root.palette.red
                                : (service.hasPendingApproval ? root.palette.orange : root.palette.accent)
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        radius: 10
                        color: root.palette.cardAlt
                        border.color: showSessionPicker ? root.palette.blue : root.palette.border
                        border.width: 1
                        implicitHeight: sessionSwitcherLayout.implicitHeight + 12

                        RowLayout {
                            id: sessionSwitcherLayout
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: service.hasError
                                    ? root.palette.red
                                    : (service.hasPendingApproval
                                        ? root.palette.orange
                                        : (service.isGenerating ? root.palette.accent : root.palette.subtle))
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: service.currentSessionTitle
                                    color: root.palette.text
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: service.currentSession
                                        ? ((service.currentSession.state_label || "Idle")
                                            + ((service.currentSession.context && service.currentSession.context.qualified_name)
                                                ? "  •  " + service.currentSession.context.qualified_name
                                                : ""))
                                        : service.currentSessionSubtitle
                                    color: root.palette.subtle
                                    font.pixelSize: 7
                                    elide: Text.ElideRight
                                }
                            }

                            SessionCountBadge {
                                visible: service.runningSessionCount > 0
                                text: String(service.runningSessionCount)
                                label: "Running"
                                accentColor: root.palette.accent
                                accentFill: root.palette.accentBg
                            }

                            SessionCountBadge {
                                visible: service.unreadSessionCount > 0
                                text: String(service.unreadSessionCount)
                                label: "Unread"
                                accentColor: root.palette.blue
                                accentFill: root.palette.blueBg
                            }

                            Text {
                                text: showSessionPicker ? "Hide" : "Threads"
                                color: root.palette.blue
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.showSessionPicker = !root.showSessionPicker;
                                if (root.showSessionPicker)
                                    root.showTargetPicker = false;
                            }
                        }
                    }

                    ProviderChip {
                        text: "Codex"
                        active: true
                        accentColor: root.palette.accent
                        accentFill: root.palette.accentBg
                        onClicked: service.setProvider("codex")
                    }

                    ActionChip {
                        text: service.startTargetQualifiedName === service.activeQualifiedName ? "Active scope" : "Scope"
                        enabled: !service.actionRunning
                        onClicked: {
                            root.showTargetPicker = !root.showTargetPicker;
                            if (root.showTargetPicker)
                                root.showSessionPicker = false;
                        }
                    }

                    ActionChip {
                        text: "New"
                        accent: true
                        enabled: !service.actionRunning
                        onClicked: {
                            root.showSessionPicker = false;
                            root.showTargetPicker = false;
                            service.startSession("");
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: root.palette.panel
            border.color: root.palette.border
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 10

                Rectangle {
                    visible: root.showStatusBanner
                    Layout.fillWidth: true
                    radius: 8
                    color: root.statusBannerTone === "error"
                        ? root.palette.redBg
                        : (root.statusBannerTone === "approval" ? root.palette.orangeBg : root.palette.blueBg)
                    border.color: root.statusBannerTone === "error"
                        ? root.palette.red
                        : (root.statusBannerTone === "approval" ? root.palette.orange : root.palette.blue)
                    border.width: 1
                    implicitHeight: statusBannerLayout.implicitHeight + 12

                    RowLayout {
                        id: statusBannerLayout
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: root.statusBannerTone === "error"
                                ? root.palette.red
                                : (root.statusBannerTone === "approval" ? root.palette.orange : root.palette.blue)
                        }

                        Text {
                            text: root.statusBannerLabel
                            color: root.statusBannerTone === "error"
                                ? root.palette.red
                                : (root.statusBannerTone === "approval" ? root.palette.orange : root.palette.blue)
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.statusBannerText
                            color: root.palette.textDim
                            font.pixelSize: 8
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 10
                    color: root.palette.bg
                    border.color: root.palette.lineSoft
                    border.width: 1
                    implicitHeight: desktopContextScroller.implicitHeight + 10

                    ListView {
                        id: desktopContextScroller
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 5
                        anchors.bottomMargin: 5
                        orientation: ListView.Horizontal
                        spacing: 6
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: [
                            {
                                title: "Context",
                                primary: service.stringValue(service.desktopContext && service.desktopContext.qualified_name, "Global"),
                                secondary: service.stringValue(service.desktopContext && service.desktopContext.connection_key, "local")
                            },
                            {
                                title: "Window",
                                primary: service.stringValue(service.desktopFocusedWindow && (service.desktopFocusedWindow.title || service.desktopFocusedWindow.app_name), "No focus"),
                                secondary: service.desktopVisibleWindowCount > 0 ? service.desktopVisibleWindowCount + " visible" : "No visible windows"
                            },
                            {
                                title: "Workspace",
                                primary: service.stringValue(service.desktopWorkspace && service.desktopWorkspace.current_workspace, "Unknown"),
                                secondary: service.stringValue(service.desktopWorkspace && service.desktopWorkspace.current_output, "No output")
                            },
                            {
                                title: "Scratchpad",
                                primary: service.desktopScratchpad && service.desktopScratchpad.available ? "Ready" : "None",
                                secondary: service.desktopScratchpad && service.desktopScratchpad.context_key ? service.desktopScratchpad.context_key : "Active context"
                            },
                            {
                                title: "AI",
                                primary: service.desktopSessions.length > 0 ? service.desktopSessions.length + " sessions" : "No sessions",
                                secondary: service.stringValue(service.desktopSnapshot && service.desktopSnapshot.current_ai_session_key, "No active AI thread")
                            },
                            {
                                title: "Runtime",
                                primary: service.desktopSnapshot && service.desktopSnapshot.runtime
                                    ? (String(service.desktopSnapshot.runtime.tracked_window_count || 0) + " tracked windows")
                                    : "Runtime idle",
                                secondary: service.desktopRevision > 0 ? "rev " + service.desktopRevision : "Waiting for desktop state"
                            }
                        ]

                        delegate: DesktopContextCard {
                            width: Math.max(96, Math.min(176, desktopContextScroller.width * 0.4))
                            title: modelData.title
                            primaryText: modelData.primary
                            secondaryText: modelData.secondary
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: root.palette.bg
                    border.color: root.palette.lineSoft
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 5

                        RowLayout {
                            id: transcriptSummaryRow
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "Transcript"
                                color: root.palette.text
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                text: service.currentSession ? (service.currentSession.state_label || "Idle") : "Idle"
                                color: root.palette.subtle
                                font.pixelSize: 7
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: service.transcriptCount > 0 ? service.transcriptCount + " items" : "Empty"
                                color: root.palette.muted
                                font.pixelSize: 7
                            }

                            ActionChip {
                                visible: !root.autoFollowTranscript && service.transcriptCount > 0
                                text: "Latest"
                                accent: true
                                onClicked: {
                                    root.autoFollowTranscript = true;
                                    transcriptList.scrollToBottom();
                                }
                            }
                        }

                        ListView {
                            id: transcriptList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            boundsBehavior: Flickable.StopAtBounds
                            model: service.transcriptModel

                            function isNearBottom() {
                                return count === 0 || contentHeight <= height || atYEnd || contentY >= Math.max(0, contentHeight - height - 32)
                            }

                            function scrollToBottom() {
                                positionViewAtEnd()
                            }

                            onMovementStarted: {
                                if (!isNearBottom())
                                    root.autoFollowTranscript = false;
                            }
                            onMovementEnded: root.autoFollowTranscript = isNearBottom()
                            onContentYChanged: {
                                if (movingVertically && !isNearBottom())
                                    root.autoFollowTranscript = false;
                                else if (!movingVertically && isNearBottom())
                                    root.autoFollowTranscript = true;
                            }
                            onCountChanged: {
                                if (root.autoFollowTranscript)
                                    followTranscriptTimer.restart()
                            }
                            onContentHeightChanged: {
                                if (root.autoFollowTranscript)
                                    followTranscriptTimer.restart()
                            }

                            delegate: Item {
                                required property string item_id
                                required property int row_revision
                                readonly property var modelData: {
                                    var marker = row_revision;
                                    return service.transcriptItemById(item_id) || ({});
                                }
                                readonly property string kind: typeof modelData.kind === "string" ? modelData.kind : ""
                                readonly property bool metaHasContent: kind === "plan"
                                    ? !!(modelData.content && String(modelData.content).trim() !== "")
                                    : ((Array.isArray(modelData.summary) && modelData.summary.length > 0)
                                        || (Array.isArray(modelData.content_items) && modelData.content_items.length > 0))
                                width: transcriptList.width
                                readonly property bool showMetaCard: (kind === "plan" || kind === "reasoning") && metaHasContent
                                implicitHeight: approvalCardItem.visible
                                    ? approvalCardItem.implicitHeight
                                    : (toolCardItem.visible
                                        ? toolCardItem.implicitHeight
                                        : (metaCardItem.visible
                                            ? metaCardItem.implicitHeight
                                            : (messageCardItem.visible ? messageCardItem.implicitHeight : 0)))
                                height: visible ? implicitHeight : 0
                                visible: approvalCardItem.visible || toolCardItem.visible || metaCardItem.visible || messageCardItem.visible

                                ApprovalCard {
                                    id: approvalCardItem
                                    width: parent.width
                                    visible: parent.kind === "approval_request"
                                    modelData: parent.modelData
                                }

                                ToolCard {
                                    id: toolCardItem
                                    width: parent.width
                                    visible: parent.kind === "tool_call"
                                    modelData: parent.modelData
                                }

                                MetaCard {
                                    id: metaCardItem
                                    width: parent.width
                                    visible: parent.showMetaCard
                                    modelData: parent.modelData
                                }

                                MessageCard {
                                    id: messageCardItem
                                    width: parent.width
                                    visible: !approvalCardItem.visible && !toolCardItem.visible && !metaCardItem.visible && parent.kind !== "reasoning" && parent.kind !== "plan"
                                    modelData: parent.modelData
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: service.transcriptCount === 0
                                color: "transparent"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Start a daemon-owned Codex session"
                                        color: root.palette.subtle
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "The panel will render messages, tool calls, and approval requests from the harness."
                                        color: root.palette.muted
                                        font.pixelSize: 9
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        Layout.maximumWidth: 280
                                    }

                                    ActionChip {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "Start Session"
                                        accent: true
                                        onClicked: service.startSession("")
                                    }
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 12
                                anchors.bottomMargin: 12
                                visible: !root.autoFollowTranscript && service.transcriptCount > 0
                                radius: 9
                                color: root.palette.blueBg
                                border.color: root.palette.blue
                                border.width: 1
                                implicitHeight: latestHintText.implicitHeight + 10
                                implicitWidth: latestHintText.implicitWidth + 16

                                Text {
                                    id: latestHintText
                                    anchors.centerIn: parent
                                    text: "Jump to latest"
                                    color: root.palette.blue
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.autoFollowTranscript = true;
                                        transcriptList.scrollToBottom();
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 12
                    color: root.palette.bg
                    border.color: root.palette.lineSoft
                    border.width: 1
                    implicitHeight: composerLayout.implicitHeight + 18

                    ColumnLayout {
                        id: composerLayout
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 9
                        anchors.bottomMargin: 9
                        spacing: 7

                        TextArea {
                            id: composeField
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(84, Math.min(168, contentHeight + 18))
                            placeholderText: service.currentSession ? "Send a follow-up..." : "Start a new Codex session..."
                            placeholderTextColor: root.palette.muted
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                            color: root.palette.text
                            font.pixelSize: 9
                            text: service.draftText
                            enabled: service.canSend && !service.actionRunning

                            background: Rectangle {
                                radius: 10
                                color: root.palette.panelAlt
                                border.color: composeField.activeFocus ? root.palette.blue : root.palette.border
                                border.width: 1
                            }

                            onTextChanged: service.draftText = text

                            Keys.onPressed: function(event) {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                                    service.sendMessage(text);
                                    event.accepted = true;
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                color: root.palette.subtle
                                font.pixelSize: 8
                                elide: Text.ElideRight
                                text: service.currentSession
                                    ? ((service.currentSession.provider_label || "Agent")
                                        + "  •  "
                                        + (service.currentSession.state_label || "Idle")
                                        + ((service.currentSession.context && service.currentSession.context.qualified_name)
                                            ? "  •  " + service.currentSession.context.qualified_name
                                            : ""))
                                    : "Start a new session or pick an existing thread"
                            }

                            Text {
                                color: root.palette.muted
                                font.pixelSize: 8
                                text: service.hasPendingApproval
                                    ? "Resolve the pending approval before sending another message."
                                    : "Ctrl+Enter to send"
                            }

                            ActionChip {
                                text: "Cancel"
                                visible: service.canCancel
                                destructive: true
                                onClicked: service.cancelCurrentTurn()
                            }

                            ActionChip {
                                text: service.currentSession ? "Send" : "Start"
                                enabled: !service.actionRunning && composeField.text.trim() !== "" && service.canSend
                                accent: true
                                prominent: true
                                onClicked: service.sendMessage(composeField.text)
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.showSessionPicker
        color: "#c009111a"

        MouseArea {
            anchors.fill: parent
            onClicked: root.showSessionPicker = false
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            radius: 14
            color: root.palette.panel
            border.color: root.palette.blue
            border.width: 1
            implicitHeight: Math.min(parent.height - 36, sessionPickerLayout.implicitHeight + 22)

            ColumnLayout {
                id: sessionPickerLayout
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 11
                anchors.bottomMargin: 11
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Recent Sessions"
                            color: root.palette.text
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Switch threads without shrinking the active chat."
                            color: root.palette.subtle
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }

                    ActionChip {
                        text: "Close"
                        onClicked: root.showSessionPicker = false
                    }
                }

                ListView {
                    id: sessionPickerList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 320)
                    clip: true
                    spacing: 6
                    model: service.sessionModel

                    delegate: Rectangle {
                        required property string session_key
                        required property int row_revision
                        readonly property var modelData: {
                            var marker = row_revision;
                            return service.sessionByKey(session_key) || ({});
                        }
                        readonly property string phase: typeof modelData.session_phase === "string" ? modelData.session_phase : "idle"
                        width: sessionPickerList.width
                        height: 52
                        radius: 10
                        color: service.selectedSessionKey === modelData.session_key ? root.palette.blueBg : root.palette.cardAlt
                        border.color: service.selectedSessionKey === modelData.session_key ? root.palette.blue : root.palette.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: phase === "error"
                                    ? root.palette.red
                                    : (phase === "needs_attention"
                                        ? root.palette.orange
                                        : (phase === "working" ? root.palette.accent : root.palette.subtle))
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: service.sessionTitle(modelData)
                                    color: root.palette.text
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: service.sessionSubtitle(modelData)
                                    color: root.palette.subtle
                                    font.pixelSize: 7
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                visible: service.sessionHasUnread(modelData.session_key)
                                width: 8
                                height: 8
                                radius: 4
                                color: root.palette.accent
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                service.selectSession(session_key);
                                root.showSessionPicker = false;
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 19
        visible: root.showTargetPicker
        color: "#c009111a"

        MouseArea {
            anchors.fill: parent
            onClicked: root.showTargetPicker = false
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            radius: 14
            color: root.palette.panel
            border.color: root.palette.border
            border.width: 1
            implicitHeight: Math.min(parent.height - 36, targetPickerLayout.implicitHeight + 22)

            ColumnLayout {
                id: targetPickerLayout
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 11
                anchors.bottomMargin: 11
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Start In"
                            color: root.palette.text
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Choose the worktree for the next new session."
                            color: root.palette.subtle
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }

                    ActionChip {
                        text: "Close"
                        onClicked: root.showTargetPicker = false
                    }
                }

                ListView {
                    id: targetPickerList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 280)
                    clip: true
                    spacing: 6
                    model: service.startTargets

                    delegate: Rectangle {
                        readonly property bool selected: modelData && modelData.qualified_name === service.startTargetQualifiedName
                        width: targetPickerList.width
                        height: 50
                        radius: 10
                        color: selected ? root.palette.blueBg : root.palette.cardAlt
                        border.color: selected ? root.palette.blue : root.palette.border
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.topMargin: 7
                            anchors.bottomMargin: 7
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: service.worktreeLabel(modelData)
                                color: root.palette.text
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData && modelData.path ? modelData.path : ""
                                color: root.palette.subtle
                                font.pixelSize: 7
                                elide: Text.ElideMiddle
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData && modelData.qualified_name)
                                    service.setStartTarget(modelData.qualified_name);
                                root.showTargetPicker = false;
                            }
                        }
                    }
                }
            }
        }
    }

    component ProviderChip: Rectangle {
        id: chip
        property string text: ""
        property bool active: false
        property bool disabled: false
        property color accentColor: "white"
        property color accentFill: "transparent"
        signal clicked

        implicitHeight: 30
        implicitWidth: chipText.implicitWidth + 18
        radius: 9
        color: active ? accentFill : root.palette.cardAlt
        border.color: active ? accentColor : root.palette.border
        border.width: 1
        opacity: disabled ? 0.45 : 1

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            color: active ? accentColor : root.palette.textDim
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            enabled: !chip.disabled
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }
    }

    component SessionCountBadge: Rectangle {
        id: badge
        property string text: ""
        property string label: ""
        property color accentColor: "white"
        property color accentFill: "transparent"

        implicitHeight: 22
        implicitWidth: badgeText.implicitWidth + 16
        radius: 8
        color: accentFill
        border.color: accentColor
        border.width: 1

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: badge.text + " " + badge.label
            color: badge.accentColor
            font.pixelSize: 8
            font.weight: Font.DemiBold
        }
    }

    component ActionChip: Rectangle {
        id: actionChip
        property string text: ""
        property bool enabled: true
        property bool accent: false
        property bool destructive: false
        property bool prominent: false
        signal clicked

        implicitHeight: prominent ? 30 : 28
        implicitWidth: actionChipText.implicitWidth + (prominent ? 22 : 18)
        radius: 8
        color: !enabled ? root.palette.cardAlt : (destructive ? root.palette.redBg : (accent ? root.palette.blueBg : root.palette.cardAlt))
        border.color: !enabled ? root.palette.border : (destructive ? root.palette.red : (accent ? root.palette.blue : root.palette.border))
        border.width: 1
        opacity: enabled ? 1 : 0.6

        Text {
            id: actionChipText
            anchors.centerIn: parent
            text: actionChip.text
            color: !enabled ? root.palette.subtle : (destructive ? root.palette.red : (accent ? root.palette.blue : root.palette.text))
            font.pixelSize: prominent ? 10 : 9
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            enabled: actionChip.enabled
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: actionChip.clicked()
        }
    }

    component DesktopContextCard: Rectangle {
        id: desktopCard
        property string title: ""
        property string primaryText: ""
        property string secondaryText: ""

        implicitHeight: desktopCardLayout.implicitHeight + 10
        radius: 8
        color: root.palette.cardAlt
        border.color: root.palette.border
        border.width: 1

        ColumnLayout {
            id: desktopCardLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 5
            anchors.bottomMargin: 5
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: desktopCard.title
                color: root.palette.subtle
                font.pixelSize: 6
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: desktopCard.primaryText
                color: root.palette.text
                font.pixelSize: 8
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: desktopCard.secondaryText
                color: root.palette.muted
                font.pixelSize: 6
                elide: Text.ElideMiddle
            }
        }
    }

    component MessageCard: Rectangle {
        property var modelData: ({})
        readonly property string displayKind: modelData.display_kind || modelData.kind || ""
        readonly property bool assistant: displayKind === "assistant_final" || displayKind === "assistant_commentary" || modelData.kind === "assistant_message"
        readonly property bool commentary: displayKind === "assistant_commentary" || modelData.phase === "commentary"
        readonly property bool isError: displayKind === "error" || modelData.kind === "error"
        readonly property bool isStatus: displayKind === "status" || modelData.kind === "status_changed"
        implicitHeight: messageLayout.implicitHeight + 16
        height: implicitHeight
        radius: 12
        color: isError
            ? root.palette.redBg
            : (assistant
                ? (commentary ? root.palette.cardAlt : root.palette.panelAlt)
                : (isStatus ? root.palette.cardAlt : root.palette.blueBg))
        border.color: isError
            ? root.palette.red
            : (assistant
                ? (commentary ? root.palette.lineSoft : root.palette.border)
                : (isStatus ? root.palette.border : root.palette.blue))
        border.width: 1

        ColumnLayout {
            id: messageLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: isError
                        ? "Error"
                        : (assistant
                            ? (commentary ? "Commentary" : (modelData.label || "Agent"))
                            : (isStatus ? (modelData.label || "Status") : "You"))
                    color: isError
                        ? root.palette.red
                        : (assistant ? root.palette.subtle : (isStatus ? root.palette.subtle : root.palette.bg))
                    font.pixelSize: 8
                    font.weight: Font.DemiBold
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: modelData.status === "streaming" ? "Streaming" : (commentary ? "Live" : "")
                    color: root.palette.muted
                    font.pixelSize: 8
                }
            }

            Text {
                Layout.fillWidth: true
                text: modelData.content || ""
                textFormat: assistant && modelData.status !== "streaming" ? Text.MarkdownText : Text.PlainText
                wrapMode: Text.Wrap
                color: isError
                    ? root.palette.red
                    : (assistant ? (commentary ? root.palette.textDim : root.palette.text) : (isStatus ? root.palette.textDim : root.palette.blue))
                font.pixelSize: assistant && !commentary ? 9 : 8
                lineHeight: 1.15
                lineHeightMode: Text.ProportionalHeight
                onLinkActivated: function(link) {
                    Qt.openUrlExternally(link);
                }
            }
        }
    }

    component ToolCard: Rectangle {
        id: toolCard
        property var modelData: ({})
        property bool expanded: false
        function formatValue(value) {
            if (value === undefined || value === null)
                return "";
            if (typeof value === "string")
                return value;
            return JSON.stringify(value, null, 2);
        }
        implicitHeight: toolLayout.implicitHeight + 14
        height: implicitHeight
        radius: 12
        color: root.palette.panelAlt
        border.color: root.palette.border
        border.width: 1

        ColumnLayout {
            id: toolLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 7
            anchors.bottomMargin: 7
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: modelData.label || "Tool"
                    color: modelData.status === "failed" ? root.palette.red : root.palette.accent
                    font.pixelSize: 8
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    text: modelData.title || modelData.tool_type || "Tool call"
                    color: root.palette.text
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                Rectangle {
                    radius: 7
                    color: modelData.status === "failed"
                        ? root.palette.redBg
                        : (modelData.status === "completed" ? root.palette.accentBg : root.palette.cardAlt)
                    border.color: modelData.status === "failed"
                        ? root.palette.red
                        : (modelData.status === "completed" ? root.palette.accent : root.palette.border)
                    border.width: 1
                    implicitHeight: 18
                    implicitWidth: toolStatusText.implicitWidth + 12

                    Text {
                        id: toolStatusText
                        anchors.centerIn: parent
                        text: modelData.duration_ms ? (Math.round(Number(modelData.duration_ms)) + "ms") : (modelData.status || "")
                        color: modelData.status === "failed"
                            ? root.palette.red
                            : (modelData.status === "completed" ? root.palette.accent : root.palette.subtle)
                        font.pixelSize: 7
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                visible: !!modelData.preview
                text: modelData.preview || ""
                color: root.palette.muted
                font.pixelSize: 8
                wrapMode: Text.Wrap
                maximumLineCount: toolCard.expanded ? 12 : 2
                elide: Text.ElideRight
            }

            GridLayout {
                visible: toolCard.expanded
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 4

                    Text {
                        visible: !!modelData.status
                        text: "Status"
                        color: root.palette.subtle
                        font.pixelSize: 7
                        font.weight: Font.DemiBold
                    }

                    Text {
                        visible: !!modelData.status
                        text: modelData.status || ""
                        color: root.palette.textDim
                        font.pixelSize: 7
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: modelData.exit_code !== undefined
                        text: "Exit"
                        color: root.palette.subtle
                        font.pixelSize: 7
                        font.weight: Font.DemiBold
                    }

                    Text {
                        visible: modelData.exit_code !== undefined
                        text: String(modelData.exit_code)
                        color: root.palette.textDim
                        font.pixelSize: 7
                    }
            }

            Text {
                visible: toolCard.expanded && !!(modelData.arguments)
                text: "Arguments"
                color: root.palette.subtle
                font.pixelSize: 7
                font.weight: Font.DemiBold
            }

            Text {
                visible: toolCard.expanded && !!(modelData.arguments)
                Layout.fillWidth: true
                text: root.blockText(modelData.arguments)
                wrapMode: Text.WrapAnywhere
                color: root.palette.textDim
                font.pixelSize: 8
            }

            Text {
                visible: toolCard.expanded && !!(modelData.result)
                text: "Result"
                color: root.palette.subtle
                font.pixelSize: 7
                font.weight: Font.DemiBold
            }

            Text {
                visible: toolCard.expanded && !!(modelData.result)
                Layout.fillWidth: true
                text: root.blockText(modelData.result)
                wrapMode: Text.WrapAnywhere
                color: root.palette.textDim
                font.pixelSize: 8
            }

            Text {
                visible: toolCard.expanded && !!(modelData.output)
                text: "Output"
                color: root.palette.subtle
                font.pixelSize: 7
                font.weight: Font.DemiBold
            }

            Text {
                visible: toolCard.expanded && !!(modelData.output)
                Layout.fillWidth: true
                text: root.blockText(modelData.output)
                wrapMode: Text.WrapAnywhere
                color: root.palette.textDim
                font.pixelSize: 8
            }

            Text {
                visible: toolCard.expanded && !!(modelData.error)
                text: "Error"
                color: root.palette.red
                font.pixelSize: 7
                font.weight: Font.DemiBold
            }

            Text {
                visible: toolCard.expanded && !!(modelData.error)
                Layout.fillWidth: true
                text: root.blockText(modelData.error)
                wrapMode: Text.WrapAnywhere
                color: root.palette.red
                font.pixelSize: 8
            }

            Text {
                visible: toolCard.expanded && Array.isArray(modelData.changes) && modelData.changes.length > 0
                text: "Changes"
                color: root.palette.subtle
                font.pixelSize: 7
                font.weight: Font.DemiBold
            }

            Text {
                visible: toolCard.expanded && Array.isArray(modelData.changes) && modelData.changes.length > 0
                Layout.fillWidth: true
                text: root.blockText(modelData.changes)
                wrapMode: Text.WrapAnywhere
                color: root.palette.textDim
                font.pixelSize: 8
            }

            RowLayout {
                visible: !!modelData.cwd
                    || !!modelData.output
                    || !!modelData.result
                    || !!modelData.arguments
                    || !!modelData.error
                    || (Array.isArray(modelData.changes) && modelData.changes.length > 0)
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: modelData.cwd || ""
                    visible: toolCard.expanded && !!modelData.cwd
                    color: root.palette.subtle
                    font.pixelSize: 7
                    elide: Text.ElideMiddle
                }

                ActionChip {
                    text: toolCard.expanded ? "Collapse" : "Inspect"
                    onClicked: toolCard.expanded = !toolCard.expanded
                }
            }
        }
    }

    component ApprovalCard: Rectangle {
        property var modelData: ({})
        implicitHeight: approvalLayout.implicitHeight + 14
        height: implicitHeight
        radius: 12
        color: root.palette.orangeBg
        border.color: root.palette.orange
        border.width: 1

        ColumnLayout {
            id: approvalLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 7
            anchors.bottomMargin: 7
            spacing: 5

            Text {
                text: modelData.title || "Approval required"
                color: root.palette.orange
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }

            Text {
                text: modelData.details || ""
                color: root.palette.textDim
                font.pixelSize: 8
                wrapMode: Text.Wrap
                visible: !!modelData.details
            }

            RowLayout {
                visible: modelData.status === "pending"
                spacing: 8

                ActionChip {
                    text: "Approve"
                    accent: true
                    prominent: true
                    enabled: !!modelData.can_approve && !service.actionRunning
                    onClicked: service.approveRequest(modelData.request_id)
                }

                ActionChip {
                    text: "Deny"
                    destructive: true
                    prominent: true
                    enabled: !!modelData.can_deny && !service.actionRunning
                    onClicked: service.denyRequest(modelData.request_id)
                }
            }

            Text {
                visible: modelData.status !== "pending"
                text: modelData.resolution ? "Resolved: " + modelData.resolution : "Resolved"
                color: root.palette.subtle
                font.pixelSize: 8
            }
        }
    }

    component MetaCard: Rectangle {
        property var modelData: ({})
        implicitHeight: metaLayout.implicitHeight + 16
        height: implicitHeight
        radius: 12
        color: root.palette.cardAlt
        border.color: root.palette.border
        border.width: 1

        ColumnLayout {
            id: metaLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 6

            Text {
                text: modelData.kind === "plan" ? "Plan" : "Reasoning"
                color: root.palette.subtle
                font.pixelSize: 8
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: root.palette.text
                font.pixelSize: 8
                text: modelData.kind === "plan"
                    ? (modelData.content || "")
                    : ((modelData.summary || []).join("\n") + ((modelData.content_items || []).length ? "\n\n" + (modelData.content_items || []).join("\n") : ""))
            }
        }
    }

    Timer {
        id: followTranscriptTimer
        interval: 0
        repeat: false
        onTriggered: transcriptList.scrollToBottom()
    }

    Connections {
        target: service

        function onCurrentSessionChanged() {
            root.autoFollowTranscript = true;
            followTranscriptTimer.restart();
        }

        function onTranscriptChanged() {
            if (root.autoFollowTranscript)
                followTranscriptTimer.restart();
        }
    }
}
