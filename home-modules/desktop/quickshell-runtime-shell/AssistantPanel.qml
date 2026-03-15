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
        teal: "#2dd4bf",
        tealBg: "#12373a",
        orange: "#fb923c",
        orangeBg: "#3a2414",
        red: "#f87171",
        redBg: "#3b1720"
    })
    property string contextLabel: ""
    property string contextDetails: ""

    readonly property var translationBackends: [
        { key: "google", label: "Google" },
        { key: "deepl", label: "DeepL" }
    ]
    readonly property var languages: [
        { code: "auto", name: "Auto" },
        { code: "en", name: "English" },
        { code: "es", name: "Spanish" },
        { code: "fr", name: "French" },
        { code: "de", name: "German" },
        { code: "it", name: "Italian" },
        { code: "ja", name: "Japanese" },
        { code: "ko", name: "Korean" },
        { code: "nl", name: "Dutch" },
        { code: "pl", name: "Polish" },
        { code: "pt", name: "Portuguese" },
        { code: "ru", name: "Russian" },
        { code: "uk", name: "Ukrainian" },
        { code: "zh", name: "Chinese" }
    ]

    function languageIndex(code, fallbackIndex) {
        for (var i = 0; i < languages.length; i++) {
            if (languages[i].code === code)
                return i;
        }
        return fallbackIndex;
    }

    function backendIndex(key) {
        for (var i = 0; i < translationBackends.length; i++) {
            if (translationBackends[i].key === key)
                return i;
        }
        return 0;
    }

    Timer {
        id: realtimeTranslateTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (translateInput.text.trim() !== "")
                root.service.translate(translateInput.text, root.service.targetLanguage, root.service.sourceLanguage);
        }
    }

    Connections {
        target: service

        function onDraftTextChanged() {
            if (composeField.text !== service.draftText)
                composeField.text = service.draftText;
        }

        function onDraftCursorPositionChanged() {
            if (composeField.cursorPosition !== service.draftCursorPosition)
                composeField.cursorPosition = service.draftCursorPosition;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            radius: 12
            color: root.palette.panel
            border.color: root.palette.border
            border.width: 1
            implicitHeight: assistantHeader.implicitHeight + 20

            ColumnLayout {
                id: assistantHeader
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
                            text: "Assistant"
                            color: root.palette.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: contextLabel !== "" ? contextLabel + "  •  " + contextDetails : "Shell-owned assistant with local persistence"
                            color: root.palette.subtle
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        visible: service.isGenerating || service.isTranslating
                        height: 20
                        radius: 6
                        color: service.isGenerating ? root.palette.accentBg : root.palette.blueBg
                        border.color: service.isGenerating ? root.palette.accent : root.palette.blue
                        border.width: 1
                        Layout.preferredWidth: statusChipText.implicitWidth + 14

                        Text {
                            id: statusChipText
                            anchors.centerIn: parent
                            text: service.isGenerating ? "Generating" : "Translating"
                            color: service.isGenerating ? root.palette.accent : root.palette.blue
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }
                    }

                    ActionChip {
                        text: "Config"
                        onClicked: Quickshell.clipboardText = service.configDisplayPath
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ProviderButton {
                        Layout.preferredWidth: 88
                        text: "OpenAI"
                        accentColor: root.palette.teal
                        accentFill: root.palette.tealBg
                        active: service.provider === "openai_compatible"
                        onClicked: service.setProvider("openai_compatible")
                    }

                    ProviderButton {
                        Layout.preferredWidth: 88
                        text: "Gemini"
                        accentColor: root.palette.blue
                        accentFill: root.palette.blueBg
                        active: service.provider === "google"
                        onClicked: service.setProvider("google")
                    }

                    StyledField {
                        id: modelField
                        Layout.fillWidth: true
                        text: service.model
                        placeholderText: "Model"
                        onEditingFinished: service.setModel(text)
                    }

                    ActionChip {
                        text: "New"
                        onClicked: service.newChat()
                    }

                    ActionChip {
                        text: "Clear"
                        enabled: service.messages.length > 0 && !service.isGenerating
                        destructive: true
                        onClicked: service.clearMessages()
                    }

                    ActionChip {
                        text: "Regen"
                        enabled: !service.isGenerating && service.messages.length > 1
                        onClicked: service.regenerateLastResponse()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: service.provider === "openai_compatible"

                    CheckBox {
                        id: localToggle
                        text: "Local"
                        checked: service.openaiLocal
                        onToggled: service.setOpenAiLocal(checked)
                    }

                    StyledField {
                        id: endpointField
                        Layout.fillWidth: true
                        text: service.openaiBaseUrl
                        placeholderText: "OpenAI-compatible endpoint"
                        onEditingFinished: service.setOpenAiBaseUrl(text)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 10
                    color: service.hasConfiguredApiKey ? root.palette.cardAlt : root.palette.orangeBg
                    border.color: service.hasConfiguredApiKey ? root.palette.border : root.palette.orange
                    border.width: 1
                    implicitHeight: credentialsText.implicitHeight + 16

                    Text {
                        id: credentialsText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        text: service.hasConfiguredApiKey
                            ? "Config copied to clipboard with the Config button. Secrets prefer env vars."
                            : "Missing credentials for " + (service.provider === "google" ? "Gemini" : "OpenAI-compatible") + ". Set env vars or edit " + service.configDisplayPath
                        color: service.hasConfiguredApiKey ? root.palette.subtle : root.palette.orange
                        font.pixelSize: 8
                        wrapMode: Text.Wrap
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

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SectionTab {
                        Layout.preferredWidth: 92
                        text: "Chat"
                        active: service.activeTab === "chat"
                        accentColor: root.palette.accent
                        accentFill: root.palette.accentBg
                        onClicked: service.activeTab = "chat"
                    }

                    SectionTab {
                        Layout.preferredWidth: 92
                        text: "Translate"
                        active: service.activeTab === "translate"
                        accentColor: root.palette.blue
                        accentFill: root.palette.blueBg
                        onClicked: service.activeTab = "translate"
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: service.activeTab === "chat"
                        text: service.activeChatTitle()
                        color: root.palette.subtle
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }

                ListView {
                    id: chatList
                    Layout.fillWidth: true
                    Layout.preferredHeight: service.chats.length > 1 ? 34 : 0
                    visible: service.activeTab === "chat" && service.chats.length > 1
                    orientation: ListView.Horizontal
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: service.chatSummaries(8)

                    delegate: Rectangle {
                        required property var modelData
                        width: Math.min(chatList.width * 0.45, Math.max(78, titleText.implicitWidth + 18))
                        height: 30
                        radius: 9
                        color: service.activeChatId === modelData.id ? root.palette.blueBg : root.palette.cardAlt
                        border.color: service.activeChatId === modelData.id ? root.palette.blue : root.palette.border
                        border.width: 1

                        Text {
                            id: titleText
                            anchors.centerIn: parent
                            width: parent.width - 16
                            text: modelData.title || "New Chat"
                            color: service.activeChatId === modelData.id ? root.palette.blue : root.palette.textDim
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: service.selectChat(modelData.id)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: service.activeTab === "chat"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: root.palette.bg
                            border.color: root.palette.lineSoft
                            border.width: 1

                            Item {
                                anchors.fill: parent
                                anchors.margins: 10

                                Flickable {
                                    id: chatFlickable
                                    anchors.fill: parent
                                    contentWidth: width
                                    contentHeight: messagesColumn.height
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds

                                    property bool autoScrollEnabled: true
                                    readonly property bool isNearBottom: {
                                        if (contentHeight <= height)
                                            return true;
                                        return contentY >= contentHeight - height - 30;
                                    }

                                    function scrollToBottom() {
                                        if (contentHeight > height)
                                            contentY = Math.max(0, contentHeight - height);
                                    }

                                    onContentHeightChanged: {
                                        if (autoScrollEnabled)
                                            scrollToBottom();
                                    }

                                    onMovementEnded: autoScrollEnabled = isNearBottom
                                    onFlickEnded: autoScrollEnabled = isNearBottom

                                    Column {
                                        id: messagesColumn
                                        width: chatFlickable.width
                                        spacing: 8

                                        Item {
                                            width: parent.width
                                            height: service.messages.length === 0 && !service.isGenerating ? emptyState.implicitHeight : 0
                                            visible: service.messages.length === 0 && !service.isGenerating

                                            ColumnLayout {
                                                id: emptyState
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "Start a conversation"
                                                    color: root.palette.subtle
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }

                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "The assistant keeps local chat history and uses the current context in its system prompt."
                                                    color: root.palette.muted
                                                    font.pixelSize: 9
                                                    horizontalAlignment: Text.AlignHCenter
                                                    wrapMode: Text.Wrap
                                                    Layout.maximumWidth: 260
                                                }
                                            }
                                        }

                                        Repeater {
                                            model: service.messages

                                            delegate: MessageBubble {
                                                required property var modelData
                                                width: messagesColumn.width
                                                colors: root.palette
                                                message: modelData
                                            }
                                        }

                                        MessageBubble {
                                            width: messagesColumn.width
                                            visible: service.isGenerating && service.currentResponse.trim() !== ""
                                            colors: root.palette
                                            message: ({
                                                role: "assistant",
                                                content: service.currentResponse,
                                                timestamp: ""
                                            })
                                            streaming: true
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

                                Rectangle {
                                    visible: service.errorMessage !== ""
                                    Layout.fillWidth: true
                                    radius: 8
                                    color: root.palette.redBg
                                    border.color: root.palette.red
                                    border.width: 1
                                    implicitHeight: composerErrorText.implicitHeight + 12

                                    Text {
                                        id: composerErrorText
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

                                TextArea {
                                    id: composeField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.max(84, contentHeight + 16)
                                    placeholderText: "Ask something about the current context..."
                                    wrapMode: TextArea.Wrap
                                    selectByMouse: true
                                    color: root.palette.text
                                    text: service.draftText
                                    cursorPosition: service.draftCursorPosition

                                    background: Rectangle {
                                        radius: 10
                                        color: root.palette.panelAlt
                                        border.color: composeField.activeFocus ? root.palette.blue : root.palette.border
                                        border.width: 1
                                    }

                                    onTextChanged: service.draftText = text
                                    onCursorPositionChanged: service.draftCursorPosition = cursorPosition

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
                                        text: "Ctrl+Enter to send"
                                        color: root.palette.muted
                                        font.pixelSize: 8
                                    }

                                    ActionChip {
                                        text: "Stop"
                                        visible: service.isGenerating
                                        accent: true
                                        onClicked: service.stopGeneration()
                                    }

                                    ActionChip {
                                        text: "Send"
                                        enabled: !service.isGenerating && composeField.text.trim() !== ""
                                        accent: true
                                        onClicked: service.sendMessage(composeField.text)
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: service.activeTab === "translate"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ComboBox {
                                id: backendBox
                                Layout.preferredWidth: 120
                                model: translationBackends
                                textRole: "label"
                                currentIndex: backendIndex(service.translatorBackend)
                                onActivated: service.setTranslatorBackend(translationBackends[currentIndex].key)
                            }

                            ComboBox {
                                id: sourceBox
                                Layout.preferredWidth: 118
                                model: languages
                                textRole: "name"
                                currentIndex: languageIndex(service.sourceLanguage, 0)
                                onActivated: service.setSourceLanguage(languages[currentIndex].code)
                            }

                            ComboBox {
                                id: targetBox
                                Layout.preferredWidth: 118
                                model: languages.slice(1)
                                textRole: "name"
                                currentIndex: Math.max(0, languageIndex(service.targetLanguage, 1) - 1)
                                onActivated: service.setTargetLanguage(languages[currentIndex + 1].code)
                            }

                            CheckBox {
                                text: "Realtime"
                                checked: service.realTimeTranslation
                                onToggled: service.setRealTimeTranslation(checked)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                            radius: 12
                            color: root.palette.bg
                            border.color: root.palette.lineSoft
                            border.width: 1

                            TextArea {
                                id: translateInput
                                anchors.fill: parent
                                anchors.margins: 10
                                placeholderText: "Paste text to translate..."
                                wrapMode: TextArea.Wrap
                                selectByMouse: true
                                color: root.palette.text
                                background: null

                                onTextChanged: {
                                    if (service.realTimeTranslation && text.trim() !== "") {
                                        realtimeTranslateTimer.restart();
                                    } else if (text.trim() === "") {
                                        service.translatedText = "";
                                        service.translationError = "";
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ActionChip {
                                text: "Translate"
                                accent: true
                                enabled: translateInput.text.trim() !== "" && !service.isTranslating
                                onClicked: service.translate(translateInput.text, service.targetLanguage, service.sourceLanguage)
                            }

                            ActionChip {
                                text: "Copy"
                                enabled: service.translatedText.trim() !== ""
                                onClicked: Quickshell.clipboardText = service.translatedText
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Text {
                                text: service.translationError !== "" ? service.translationError : (service.isTranslating ? "Working..." : "")
                                color: service.translationError !== "" ? root.palette.red : root.palette.subtle
                                font.pixelSize: 8
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: root.palette.bg
                            border.color: root.palette.lineSoft
                            border.width: 1

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 10
                                clip: true

                                TextArea {
                                    text: service.translatedText
                                    wrapMode: TextArea.Wrap
                                    readOnly: true
                                    selectByMouse: true
                                    color: root.palette.text
                                    background: null
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component ProviderButton: Rectangle {
        id: providerButton
        property string text: ""
        property bool active: false
        property color accentColor: "white"
        property color accentFill: "transparent"
        signal clicked

        implicitHeight: 30
        radius: 9
        color: active ? accentFill : root.palette.cardAlt
        border.color: active ? accentColor : root.palette.border
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: providerButton.text
            color: providerButton.active ? providerButton.accentColor : root.palette.textDim
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: providerButton.clicked()
        }
    }

    component SectionTab: Rectangle {
        id: sectionTab
        property string text: ""
        property bool active: false
        property color accentColor: "white"
        property color accentFill: "transparent"
        signal clicked

        implicitHeight: 30
        radius: 9
        color: active ? accentFill : root.palette.cardAlt
        border.color: active ? accentColor : root.palette.border
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: sectionTab.text
            color: sectionTab.active ? sectionTab.accentColor : root.palette.textDim
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sectionTab.clicked()
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

    component StyledField: TextField {
        color: root.palette.text
        selectByMouse: true

        background: Rectangle {
            radius: 9
            color: root.palette.panelAlt
            border.color: parent.activeFocus ? root.palette.blue : root.palette.border
            border.width: 1
        }
    }

    component MessageBubble: Rectangle {
        id: bubble
        required property var colors
        property var message: ({})
        property bool streaming: false
        readonly property bool assistant: !!(message && message.role === "assistant")

        implicitHeight: bubbleContent.implicitHeight + 16
        radius: 12
        color: assistant ? root.palette.panelAlt : root.palette.blueBg
        border.color: assistant ? root.palette.border : root.palette.blue
        border.width: 1

        ColumnLayout {
            id: bubbleContent
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    height: 18
                    radius: 6
                    color: bubble.assistant ? root.palette.bg : root.palette.blue
                    border.color: "transparent"
                    border.width: 0
                    Layout.preferredWidth: bubbleRoleText.implicitWidth + 12

                    Text {
                        id: bubbleRoleText
                        anchors.centerIn: parent
                        text: bubble.assistant ? (bubble.streaming ? "Streaming" : "Assistant") : "You"
                        color: bubble.assistant ? root.palette.subtle : root.palette.bg
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: message && message.timestamp ? Qt.formatDateTime(new Date(message.timestamp), "h:mm AP") : ""
                    color: root.palette.muted
                    font.pixelSize: 8
                    elide: Text.ElideRight
                }

                ActionChip {
                    visible: bubble.assistant && !!message && message.content && message.content.trim() !== ""
                    text: "Copy"
                    onClicked: Quickshell.clipboardText = message.content
                }
            }

            TextEdit {
                Layout.fillWidth: true
                text: message && message.content ? message.content : ""
                textFormat: bubble.assistant ? Text.MarkdownText : Text.PlainText
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: true
                color: bubble.assistant ? root.palette.text : root.palette.blue
                selectionColor: root.palette.blue
                selectedTextColor: root.palette.bg
                onLinkActivated: function(link) {
                    Qt.openUrlExternally(link);
                }
            }
        }
    }
}
