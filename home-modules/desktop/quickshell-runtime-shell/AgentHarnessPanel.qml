import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    required property var service
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            radius: 12
            color: root.palette.panel
            border.color: root.palette.border
            border.width: 1
            implicitHeight: headerLayout.implicitHeight + 20

            ColumnLayout {
                id: headerLayout
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Agents"
                            color: root.palette.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: contextLabel !== "" ? contextLabel + "  •  " + contextDetails : "Daemon-owned Codex harness"
                            color: root.palette.subtle
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        visible: service.isGenerating || service.hasPendingApproval || service.actionRunning
                        height: 20
                        radius: 6
                        color: service.hasPendingApproval ? root.palette.orangeBg : root.palette.accentBg
                        border.color: service.hasPendingApproval ? root.palette.orange : root.palette.accent
                        border.width: 1
                        Layout.preferredWidth: headerStatusText.implicitWidth + 14

                        Text {
                            id: headerStatusText
                            anchors.centerIn: parent
                            text: service.hasPendingApproval ? "Approval" : (service.isGenerating ? "Running" : "Syncing")
                            color: service.hasPendingApproval ? root.palette.orange : root.palette.accent
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ProviderChip {
                        text: "Codex"
                        active: true
                        accentColor: root.palette.accent
                        accentFill: root.palette.accentBg
                        onClicked: service.setProvider("codex")
                    }

                    ProviderChip {
                        text: "Claude"
                        active: false
                        disabled: true
                        accentColor: root.palette.orange
                        accentFill: root.palette.orangeBg
                    }

                    ProviderChip {
                        text: "Gemini"
                        active: false
                        disabled: true
                        accentColor: root.palette.blue
                        accentFill: root.palette.blueBg
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    ActionChip {
                        text: "New Session"
                        accent: true
                        enabled: !service.actionRunning
                        onClicked: service.startSession("")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 10
                    color: root.palette.cardAlt
                    border.color: root.palette.border
                    border.width: 1
                    implicitHeight: modeText.implicitHeight + 16

                    Text {
                        id: modeText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        color: root.palette.subtle
                        font.pixelSize: 8
                        wrapMode: Text.Wrap
                        text: "Codex app-server is the active adapter. Claude and Gemini can be added behind the same harness contract next."
                    }
                }
            }
        }

        ListView {
            id: sessionList
            Layout.fillWidth: true
            Layout.preferredHeight: service.sessions.length > 1 ? 36 : 0
            visible: service.sessions.length > 1
            orientation: ListView.Horizontal
            spacing: 6
            model: service.sessions
            clip: true

            delegate: Rectangle {
                required property var modelData
                width: Math.min(sessionList.width * 0.46, Math.max(92, sessionTitle.implicitWidth + 18))
                height: 30
                radius: 9
                color: service.selectedSessionKey === modelData.session_key ? root.palette.blueBg : root.palette.cardAlt
                border.color: service.selectedSessionKey === modelData.session_key ? root.palette.blue : root.palette.border
                border.width: 1

                Text {
                    id: sessionTitle
                    anchors.centerIn: parent
                    width: parent.width - 14
                    color: service.selectedSessionKey === modelData.session_key ? root.palette.blue : root.palette.textDim
                    font.pixelSize: 8
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    text: modelData.cwd ? modelData.cwd.split("/").pop() : modelData.session_key
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: service.selectSession(modelData.session_key)
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
                    visible: service.errorMessage !== ""
                    Layout.fillWidth: true
                    radius: 8
                    color: root.palette.redBg
                    border.color: root.palette.red
                    border.width: 1
                    implicitHeight: errorText.implicitHeight + 12

                    Text {
                        id: errorText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        text: service.errorMessage
                        color: root.palette.red
                        font.pixelSize: 8
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: root.palette.bg
                    border.color: root.palette.lineSoft
                    border.width: 1

                    Flickable {
                        id: transcriptFlickable
                        anchors.fill: parent
                        anchors.margins: 10
                        contentWidth: width
                        contentHeight: transcriptColumn.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: transcriptColumn
                            width: transcriptFlickable.width
                            spacing: 8

                            Item {
                                width: parent.width
                                height: service.transcript.length === 0 ? emptyState.implicitHeight : 0
                                visible: service.transcript.length === 0

                                ColumnLayout {
                                    id: emptyState
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

                            Repeater {
                                model: service.transcript

                                delegate: Loader {
                                    required property var modelData
                                    width: transcriptColumn.width
                                    sourceComponent: {
                                        if (modelData.kind === "approval_request")
                                            return approvalCard;
                                        if (modelData.kind === "tool_call")
                                            return toolCard;
                                        if (modelData.kind === "reasoning" || modelData.kind === "plan")
                                            return metaCard;
                                        return messageCard;
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
                        spacing: 8

                        TextArea {
                            id: composeField
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(84, contentHeight + 16)
                            placeholderText: service.currentSession ? "Send a follow-up..." : "Start a new Codex session..."
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                            color: root.palette.text
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
                                onClicked: service.sendMessage(composeField.text)
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

    component ActionChip: Rectangle {
        id: actionChip
        property string text: ""
        property bool enabled: true
        property bool accent: false
        property bool destructive: false
        signal clicked

        implicitHeight: 28
        implicitWidth: actionChipText.implicitWidth + 18
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
            font.pixelSize: 9
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

    component messageCard: Rectangle {
        required property var modelData
        readonly property bool assistant: modelData.kind === "assistant_message"
        implicitHeight: messageLayout.implicitHeight + 16
        radius: 12
        color: assistant ? root.palette.panelAlt : root.palette.blueBg
        border.color: assistant ? root.palette.border : root.palette.blue
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
                    text: assistant ? "Agent" : "You"
                    color: assistant ? root.palette.subtle : root.palette.bg
                    font.pixelSize: 8
                    font.weight: Font.DemiBold
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: modelData.status === "streaming" ? "Streaming" : ""
                    color: root.palette.muted
                    font.pixelSize: 8
                }
            }

            TextEdit {
                Layout.fillWidth: true
                text: modelData.content || ""
                textFormat: assistant ? Text.MarkdownText : Text.PlainText
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: true
                color: assistant ? root.palette.text : root.palette.blue
                selectionColor: root.palette.blue
                selectedTextColor: root.palette.bg
                onLinkActivated: function(link) {
                    Qt.openUrlExternally(link);
                }
            }
        }
    }

    component toolCard: Rectangle {
        required property var modelData
        implicitHeight: toolLayout.implicitHeight + 16
        radius: 12
        color: root.palette.panelAlt
        border.color: root.palette.border
        border.width: 1

        ColumnLayout {
            id: toolLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Tool"
                    color: root.palette.accent
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

                Text {
                    text: modelData.status || ""
                    color: root.palette.subtle
                    font.pixelSize: 8
                }
            }

            Text {
                visible: !!modelData.cwd
                text: modelData.cwd || ""
                color: root.palette.muted
                font.pixelSize: 8
                wrapMode: Text.Wrap
            }

            TextEdit {
                visible: !!modelData.output
                Layout.fillWidth: true
                text: modelData.output || ""
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: root.palette.textDim
            }
        }
    }

    component approvalCard: Rectangle {
        required property var modelData
        implicitHeight: approvalLayout.implicitHeight + 16
        radius: 12
        color: root.palette.orangeBg
        border.color: root.palette.orange
        border.width: 1

        ColumnLayout {
            id: approvalLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 6

            Text {
                text: modelData.title || "Approval required"
                color: root.palette.orange
                font.pixelSize: 10
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
                    enabled: !!modelData.can_approve && !service.actionRunning
                    onClicked: service.approveRequest(modelData.request_id)
                }

                ActionChip {
                    text: "Deny"
                    destructive: true
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

    component metaCard: Rectangle {
        required property var modelData
        implicitHeight: metaLayout.implicitHeight + 16
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

            TextEdit {
                Layout.fillWidth: true
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: root.palette.text
                text: modelData.kind === "plan"
                    ? (modelData.content || "")
                    : ((modelData.summary || []).join("\n") + ((modelData.content_items || []).length ? "\n\n" + (modelData.content_items || []).join("\n") : ""))
            }
        }
    }
}
