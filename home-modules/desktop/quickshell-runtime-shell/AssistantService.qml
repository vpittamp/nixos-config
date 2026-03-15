import QtQuick
import Quickshell
import Quickshell.Io
import "./AssistantProviderLogic.js" as AssistantProviderLogic

Item {
    id: root
    visible: false

    property string shellConfigName: "i3pm-shell"
    property string contextLabel: ""
    property string contextDetails: ""

    property var config: AssistantProviderLogic.defaultConfig()
    property var chats: []
    property string activeChatId: ""
    property string activeTab: "chat"
    property string draftText: ""
    property int draftCursorPosition: 0
    property bool isGenerating: false
    property string currentResponse: ""
    property string errorMessage: ""
    property bool isManuallyStopped: false
    property string translatedText: ""
    property bool isTranslating: false
    property string translationError: ""
    property bool stateLoaded: false
    property bool configLoaded: false

    readonly property string xdgConfigHome: stringValue(Quickshell.env("XDG_CONFIG_HOME"), stringValue(Quickshell.env("HOME"), "") + "/.config")
    readonly property string configFilePath: xdgConfigHome + "/quickshell/" + shellConfigName + "/assistant-config.json"
    readonly property string stateFilePath: Quickshell.dataPath("assistant-state.json")
    readonly property string configDisplayPath: configFilePath
    readonly property string provider: stringValue(config.ai && config.ai.provider, AssistantProviderLogic.Providers.OPENAI_COMPATIBLE)
    readonly property string model: {
        var models = config.ai && config.ai.models && typeof config.ai.models === "object" ? config.ai.models : {};
        var selected = models[provider];
        if (typeof selected === "string" && selected.trim() !== "")
            return selected.trim();
        return provider === AssistantProviderLogic.Providers.GOOGLE ? "gemini-2.5-flash" : "gpt-4o-mini";
    }
    readonly property string openaiBaseUrl: {
        var value = stringValue(config.ai && config.ai.openaiBaseUrl, "");
        return value !== "" ? value : "https://api.openai.com/v1/chat/completions";
    }
    readonly property bool openaiLocal: !!(config.ai && config.ai.openaiLocal)
    readonly property real temperature: {
        var value = Number(config.ai && config.ai.temperature);
        return Number.isFinite(value) ? value : 0.7;
    }
    readonly property string systemPrompt: stringValue(config.ai && config.ai.systemPrompt, "")
    readonly property string translatorBackend: stringValue(config.translator && config.translator.backend, "google")
    readonly property string sourceLanguage: stringValue(config.translator && config.translator.sourceLanguage, "auto")
    readonly property string targetLanguage: stringValue(config.translator && config.translator.targetLanguage, "en")
    readonly property bool realTimeTranslation: config.translator && config.translator.realTimeTranslation !== undefined ? !!config.translator.realTimeTranslation : true
    readonly property string envOpenAiApiKey: stringValue(Quickshell.env("I3PM_ASSISTANT_OPENAI_API_KEY") || Quickshell.env("OPENAI_API_KEY"), "")
    readonly property string envGeminiApiKey: stringValue(Quickshell.env("I3PM_ASSISTANT_GEMINI_API_KEY") || Quickshell.env("GEMINI_API_KEY") || Quickshell.env("GOOGLE_API_KEY"), "")
    readonly property string envDeepLApiKey: stringValue(Quickshell.env("I3PM_ASSISTANT_DEEPL_API_KEY") || Quickshell.env("DEEPL_API_KEY"), "")
    readonly property string settingsOpenAiApiKey: stringValue(config.ai && config.ai.apiKeys && config.ai.apiKeys[AssistantProviderLogic.Providers.OPENAI_COMPATIBLE], "")
    readonly property string settingsGeminiApiKey: stringValue(config.ai && config.ai.apiKeys && config.ai.apiKeys[AssistantProviderLogic.Providers.GOOGLE], "")
    readonly property string settingsDeepLApiKey: stringValue(config.translator && config.translator.deeplApiKey, "")
    readonly property string apiKey: provider === AssistantProviderLogic.Providers.GOOGLE ? (envGeminiApiKey || settingsGeminiApiKey) : (envOpenAiApiKey || settingsOpenAiApiKey)
    readonly property string deeplApiKey: envDeepLApiKey || settingsDeepLApiKey
    readonly property bool requiresApiKey: provider === AssistantProviderLogic.Providers.OPENAI_COMPATIBLE ? !openaiLocal : true
    readonly property bool hasConfiguredApiKey: !requiresApiKey || apiKey !== ""
    readonly property var messages: activeChatMessages()
    readonly property var activeChat: activeChatObject()

    Timer {
        id: saveConfigTimer
        interval: 200
        repeat: false
        onTriggered: root.performSaveConfig()
    }

    Timer {
        id: saveStateTimer
        interval: 200
        repeat: false
        onTriggered: root.performSaveState()
    }

    FileView {
        id: configFile
        path: root.configFilePath
        watchChanges: false

        onLoaded: root.loadConfigFromDisk()
        onLoadFailed: function(error) {
            if (error === 2) {
                root.config = AssistantProviderLogic.defaultConfig();
                root.configLoaded = true;
                root.saveConfig();
            }
        }
    }

    FileView {
        id: stateFile
        path: root.stateFilePath
        watchChanges: false

        onLoaded: root.loadStateFromDisk()
        onLoadFailed: function(error) {
            if (error === 2) {
                root.ensureChat();
                root.stateLoaded = true;
                root.saveState();
            }
        }
    }

    Component.onCompleted: {
        root.ensureChat();
    }

    onActiveTabChanged: {
        if (stateLoaded)
            saveState();
    }

    onDraftTextChanged: {
        if (stateLoaded)
            saveState();
    }

    onDraftCursorPositionChanged: {
        if (stateLoaded)
            saveState();
    }

    onActiveChatIdChanged: {
        if (stateLoaded)
            saveState();
    }

    function stringValue(value, fallback) {
        return typeof value === "string" && value.trim() !== "" ? value.trim() : fallback;
    }

    function nowIso() {
        return new Date().toISOString();
    }

    function createChatRecord(title) {
        return {
            id: String(Date.now()) + "-" + Math.floor(Math.random() * 1000),
            title: stringValue(title, "New Chat"),
            updatedAt: nowIso(),
            messages: []
        };
    }

    function activeChatIndex() {
        for (var i = 0; i < chats.length; i++) {
            if (stringValue(chats[i] && chats[i].id, "") === activeChatId)
                return i;
        }
        return chats.length > 0 ? 0 : -1;
    }

    function activeChatObject() {
        var index = activeChatIndex();
        if (index < 0 || index >= chats.length)
            return null;
        return chats[index];
    }

    function activeChatMessages() {
        var chat = activeChatObject();
        return chat && Array.isArray(chat.messages) ? chat.messages : [];
    }

    function chatSummaries(limit) {
        var next = Array.isArray(chats) ? chats.slice() : [];
        next.sort(function(left, right) {
            return stringValue(right && right.updatedAt, "").localeCompare(stringValue(left && left.updatedAt, ""));
        });
        if (Number.isFinite(limit) && limit > 0)
            return next.slice(0, limit);
        return next;
    }

    function activeChatTitle() {
        var chat = activeChatObject();
        return chat ? stringValue(chat.title, "New Chat") : "New Chat";
    }

    function sortChats(items) {
        var next = Array.isArray(items) ? items.slice() : [];
        next.sort(function(left, right) {
            return stringValue(right && right.updatedAt, "").localeCompare(stringValue(left && left.updatedAt, ""));
        });
        return next.slice(0, 24);
    }

    function ensureChat() {
        if (Array.isArray(chats) && chats.length > 0) {
            if (activeChatIndex() === -1) {
                activeChatId = stringValue(chats[0] && chats[0].id, "");
            }
            return;
        }

        var chat = createChatRecord("New Chat");
        chats = [chat];
        activeChatId = chat.id;
    }

    function saveConfig() {
        saveConfigTimer.restart();
    }

    function saveState() {
        saveStateTimer.restart();
    }

    function performSaveConfig() {
        try {
            configFile.setText(JSON.stringify(config, null, 2));
        } catch (_error) {
        }
    }

    function performSaveState() {
        ensureChat();

        var payload = {
            version: 1,
            activeTab: activeTab,
            activeChatId: activeChatId,
            draftText: draftText,
            draftCursorPosition: draftCursorPosition,
            chats: chats,
            updatedAt: nowIso()
        };

        try {
            stateFile.setText(JSON.stringify(payload, null, 2));
        } catch (_error) {
        }
    }

    function loadConfigFromDisk() {
        var raw = configFile.text();
        if (!raw || raw.trim() === "") {
            config = AssistantProviderLogic.defaultConfig();
            configLoaded = true;
            saveConfig();
            return;
        }

        try {
            config = AssistantProviderLogic.normalizeConfig(JSON.parse(raw));
            configLoaded = true;
        } catch (_error) {
            config = AssistantProviderLogic.defaultConfig();
            configLoaded = true;
            saveConfig();
        }
    }

    function loadStateFromDisk() {
        var raw = stateFile.text();
        if (!raw || raw.trim() === "") {
            ensureChat();
            stateLoaded = true;
            saveState();
            return;
        }

        try {
            var parsed = JSON.parse(raw);
            var loadedChats = Array.isArray(parsed.chats) ? parsed.chats.slice() : [];
            var normalizedChats = [];

            for (var i = 0; i < loadedChats.length; i++) {
                if (!loadedChats[i] || typeof loadedChats[i] !== "object")
                    continue;

                normalizedChats.push({
                    id: stringValue(loadedChats[i].id, String(Date.now()) + "-" + i),
                    title: stringValue(loadedChats[i].title, "New Chat"),
                    updatedAt: stringValue(loadedChats[i].updatedAt, nowIso()),
                    messages: Array.isArray(loadedChats[i].messages) ? loadedChats[i].messages.slice() : []
                });
            }

            chats = sortChats(normalizedChats);
            activeChatId = stringValue(parsed.activeChatId, "");
            activeTab = stringValue(parsed.activeTab, "chat");
            draftText = typeof parsed.draftText === "string" ? parsed.draftText : "";
            draftCursorPosition = Number.isFinite(Number(parsed.draftCursorPosition)) ? Number(parsed.draftCursorPosition) : 0;
            ensureChat();
            stateLoaded = true;
        } catch (_error) {
            ensureChat();
            stateLoaded = true;
            saveState();
        }
    }

    function resolvedSystemPrompt() {
        var base = stringValue(systemPrompt, AssistantProviderLogic.defaultConfig().ai.systemPrompt);
        var suffix = [];

        if (stringValue(contextLabel, "") !== "") {
            suffix.push("Current context: " + contextLabel + ".");
        }
        if (stringValue(contextDetails, "") !== "") {
            suffix.push("Context details: " + contextDetails + ".");
        }

        return suffix.length ? base + "\n\n" + suffix.join(" ") : base;
    }

    function updateConfig(mutator) {
        var next = AssistantProviderLogic.cloneValue(config);
        mutator(next);
        config = AssistantProviderLogic.normalizeConfig(next);
        saveConfig();
    }

    function setProvider(providerName) {
        if (providerName !== AssistantProviderLogic.Providers.OPENAI_COMPATIBLE && providerName !== AssistantProviderLogic.Providers.GOOGLE)
            return;

        updateConfig(function(next) {
            next.ai.provider = providerName;
        });
    }

    function setModel(modelName) {
        updateConfig(function(next) {
            if (!next.ai.models || typeof next.ai.models !== "object")
                next.ai.models = {};
            next.ai.models[next.ai.provider] = stringValue(modelName, model);
        });
    }

    function setOpenAiBaseUrl(value) {
        updateConfig(function(next) {
            next.ai.openaiBaseUrl = stringValue(value, openaiBaseUrl);
        });
    }

    function setOpenAiLocal(value) {
        updateConfig(function(next) {
            next.ai.openaiLocal = !!value;
        });
    }

    function setTranslatorBackend(value) {
        updateConfig(function(next) {
            next.translator.backend = stringValue(value, translatorBackend);
        });
    }

    function setSourceLanguage(value) {
        updateConfig(function(next) {
            next.translator.sourceLanguage = stringValue(value, sourceLanguage);
        });
    }

    function setTargetLanguage(value) {
        updateConfig(function(next) {
            next.translator.targetLanguage = stringValue(value, targetLanguage);
        });
    }

    function setRealTimeTranslation(value) {
        updateConfig(function(next) {
            next.translator.realTimeTranslation = !!value;
        });
    }

    function setScale(value) {
        updateConfig(function(next) {
            next.ui.scale = Number.isFinite(Number(value)) ? Number(value) : 1;
        });
    }

    function selectChat(chatId) {
        if (stringValue(chatId, "") === "")
            return;

        activeChatId = chatId;
        currentResponse = "";
        errorMessage = "";
        saveState();
    }

    function newChat() {
        var chat = createChatRecord("New Chat");
        chats = sortChats([chat].concat(chats));
        activeChatId = chat.id;
        draftText = "";
        draftCursorPosition = 0;
        currentResponse = "";
        errorMessage = "";
        saveState();
    }

    function clearMessages() {
        var index = activeChatIndex();
        if (index < 0)
            return;

        var next = chats.slice();
        next[index] = {
            id: next[index].id,
            title: "New Chat",
            updatedAt: nowIso(),
            messages: []
        };
        chats = sortChats(next);
        saveState();
    }

    function updateActiveChat(mutator) {
        ensureChat();
        var index = activeChatIndex();
        if (index < 0)
            return;

        var current = chats[index];
        var nextChat = {
            id: stringValue(current && current.id, String(Date.now())),
            title: stringValue(current && current.title, "New Chat"),
            updatedAt: nowIso(),
            messages: Array.isArray(current && current.messages) ? current.messages.slice() : []
        };
        mutator(nextChat);
        var nextChats = chats.slice();
        nextChats[index] = nextChat;
        chats = sortChats(nextChats);
        activeChatId = nextChat.id;
        saveState();
    }

    function addMessage(role, content) {
        var trimmed = typeof content === "string" ? content.trim() : "";
        if (trimmed === "")
            return null;

        var message = {
            id: String(Date.now()) + "-" + Math.floor(Math.random() * 1000),
            role: role,
            content: trimmed,
            timestamp: nowIso()
        };

        updateActiveChat(function(chat) {
            chat.messages = chat.messages.concat([message]);
            if (chat.messages.length === 1 && role === "user")
                chat.title = trimmed.slice(0, 42);
        });

        return message;
    }

    function regenerateLastResponse() {
        if (isGenerating)
            return;

        var history = messages;
        if (!Array.isArray(history) || history.length < 2)
            return;

        var lastAssistantIndex = -1;
        for (var i = history.length - 1; i >= 0; i--) {
            if (history[i].role === "assistant") {
                lastAssistantIndex = i;
                break;
            }
        }

        if (lastAssistantIndex < 0)
            return;

        updateActiveChat(function(chat) {
            chat.messages = chat.messages.slice(0, lastAssistantIndex);
        });

        beginGeneration();
    }

    function buildConversationHistory() {
        var items = [];
        for (var i = 0; i < messages.length; i++) {
            items.push({
                role: messages[i].role,
                content: messages[i].content
            });
        }
        return items;
    }

    function beginGeneration() {
        if (requiresApiKey && apiKey === "") {
            errorMessage = provider === AssistantProviderLogic.Providers.GOOGLE ? "Set GEMINI_API_KEY or edit assistant-config.json." : "Set OPENAI_API_KEY or edit assistant-config.json.";
            return;
        }

        currentResponse = "";
        errorMessage = "";
        isGenerating = true;
        isManuallyStopped = false;

        if (provider === AssistantProviderLogic.Providers.GOOGLE)
            sendGeminiRequest();
        else
            sendOpenAiRequest();
    }

    function startGeneration(optionalText) {
        if (isGenerating)
            return;

        var text = typeof optionalText === "string" ? optionalText : draftText;
        var trimmed = text.trim();
        if (trimmed === "")
            return;

        if (requiresApiKey && apiKey === "") {
            errorMessage = provider === AssistantProviderLogic.Providers.GOOGLE ? "Set GEMINI_API_KEY or edit assistant-config.json." : "Set OPENAI_API_KEY or edit assistant-config.json.";
            return;
        }

        addMessage("user", trimmed);
        draftText = "";
        draftCursorPosition = 0;
        beginGeneration();
    }

    function sendMessage(text) {
        startGeneration(text);
    }

    function stopGeneration() {
        if (!isGenerating)
            return;

        isManuallyStopped = true;
        if (openAiProcess.running)
            openAiProcess.running = false;
        if (geminiProcess.running)
            geminiProcess.running = false;

        isGenerating = false;

        if (currentResponse.trim() !== "")
            addMessage("assistant", currentResponse.trim());

        currentResponse = "";
    }

    function finalizeGeneration(exitCode) {
        if (isManuallyStopped) {
            isManuallyStopped = false;
            return;
        }

        isGenerating = false;

        if (exitCode !== 0 && currentResponse === "") {
            if (errorMessage === "") {
                errorMessage = provider === AssistantProviderLogic.Providers.OPENAI_COMPATIBLE && openaiLocal ? "Local inference server is not reachable." : "Assistant request failed.";
            }
            return;
        }

        if (currentResponse.trim() !== "")
            addMessage("assistant", currentResponse.trim());

        currentResponse = "";
        saveState();
    }

    function sendOpenAiRequest() {
        var commandData = AssistantProviderLogic.buildOpenAICommand(openaiBaseUrl, apiKey, model, resolvedSystemPrompt(), buildConversationHistory(), temperature);
        openAiProcess.buffer = "";
        openAiProcess.command = commandData.args;
        openAiProcess.running = true;
    }

    function sendGeminiRequest() {
        var commandData = AssistantProviderLogic.buildGeminiCommand(
            "https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse&key={apiKey}",
            model,
            apiKey,
            resolvedSystemPrompt(),
            buildConversationHistory(),
            temperature
        );
        geminiProcess.buffer = "";
        geminiProcess.command = commandData.args;
        geminiProcess.running = true;
    }

    function translate(text, targetLang, sourceLang) {
        var input = typeof text === "string" ? text.trim() : "";
        if (input === "") {
            translatedText = "";
            translationError = "";
            return;
        }

        translatedText = "";
        translationError = "";
        isTranslating = true;

        if (translatorBackend === "deepl") {
            var deepL = AssistantProviderLogic.buildDeepLTranslateCommand(input, targetLang || targetLanguage, deeplApiKey);
            if (deepL.error) {
                isTranslating = false;
                translationError = deepL.error;
                return;
            }
            translateProcess.command = deepL.args;
            translateProcess.running = true;
            return;
        }

        var google = AssistantProviderLogic.buildGoogleTranslateCommand(input, targetLang || targetLanguage, sourceLang || sourceLanguage);
        translateProcess.command = google.args;
        translateProcess.running = true;
    }

    function handleTranslationResponse(text) {
        var result = AssistantProviderLogic.parseTranslateResponse(translatorBackend, text);
        isTranslating = false;
        if (result.error) {
            translationError = result.error;
            return;
        }
        translatedText = result.text || "";
        translationError = "";
    }

    Process {
        id: openAiProcess

        property string buffer: ""

        stdout: SplitParser {
            onRead: function(data) {
                var result = AssistantProviderLogic.parseOpenAIStream(data);
                if (!result)
                    return;

                if (result.content) {
                    root.currentResponse += result.content;
                } else if (result.error) {
                    root.errorMessage = result.error;
                } else if (result.raw) {
                    openAiProcess.buffer += result.raw;
                    try {
                        var json = JSON.parse(openAiProcess.buffer);
                        if (json.error)
                            root.errorMessage = root.stringValue(json.error.message, "API error");
                        openAiProcess.buffer = "";
                    } catch (_error) {
                    }
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                var output = text.trim();
                if (output !== "" && root.errorMessage === "")
                    root.errorMessage = output;
            }
        }

        onExited: function(exitCode) {
            openAiProcess.buffer = "";
            root.finalizeGeneration(exitCode);
        }
    }

    Process {
        id: geminiProcess

        property string buffer: ""

        stdout: SplitParser {
            onRead: function(data) {
                var result = AssistantProviderLogic.parseGeminiStream(data);
                if (!result)
                    return;

                if (result.content) {
                    root.currentResponse += result.content;
                } else if (result.error) {
                    root.errorMessage = result.error;
                } else if (result.raw) {
                    geminiProcess.buffer += result.raw;
                    try {
                        var json = JSON.parse(geminiProcess.buffer);
                        if (json.error)
                            root.errorMessage = root.stringValue(json.error.message, "API error");
                        geminiProcess.buffer = "";
                    } catch (_error) {
                    }
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                var output = text.trim();
                if (output !== "" && root.errorMessage === "")
                    root.errorMessage = output;
            }
        }

        onExited: function(exitCode) {
            geminiProcess.buffer = "";
            root.finalizeGeneration(exitCode);
        }
    }

    Process {
        id: translateProcess

        stdout: StdioCollector {
            onStreamFinished: root.handleTranslationResponse(text)
        }

        stderr: StdioCollector {}

        onExited: function(exitCode) {
            if (exitCode !== 0 && root.translationError === "") {
                root.isTranslating = false;
                root.translationError = "Translation failed.";
            }
        }
    }
}
