import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property string shellConfigName: "i3pm-shell"
    property string contextLabel: ""
    property string contextDetails: ""
    property string i3pmBin: ""

    property var snapshot: ({
            active_session_key: "",
            sessions: [],
            active_context: {}
        })
    property string selectedSessionKey: ""
    property string preferredProvider: "codex"
    property string preferredModel: ""
    property string draftText: ""
    property string errorMessage: ""
    property string queuedMessageAfterStart: ""
    property bool actionRunning: false

    readonly property var sessions: arrayValue(snapshot && snapshot.sessions)
    readonly property var currentSession: currentSessionObject()
    readonly property var transcript: currentSession && Array.isArray(currentSession.transcript) ? currentSession.transcript : []
    readonly property bool isGenerating: !!(currentSession && currentSession.session_phase === "working")
    readonly property bool hasPendingApproval: !!(currentSession && currentSession.pending_approval)
    readonly property bool canSend: !!(currentSession ? currentSession.can_send : !actionRunning)
    readonly property bool canCancel: !!(currentSession && currentSession.can_cancel)

    Timer {
        id: watcherRestartTimer
        interval: 1000
        repeat: false
        onTriggered: watcher.running = true
    }

    Process {
        id: watcher
        command: [root.i3pmBin, "agent", "watch"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.parseSnapshot(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (data && data.trim() !== "")
                    console.warn("agent.watch:", data);
            }
        }
        onExited: function() {
            watcherRestartTimer.restart();
        }
    }

    Process {
        id: actionProcess
        property string stdoutBuffer: ""
        command: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.handleActionOutput(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (data && data.trim() !== "")
                    root.errorMessage = data.trim();
            }
        }
        onRunningChanged: {
            root.actionRunning = running;
        }
    }

    function stringValue(value, fallback) {
        return typeof value === "string" && value.trim() !== "" ? value.trim() : fallback;
    }

    function arrayValue(value) {
        return Array.isArray(value) ? value : [];
    }

    function sessionExists(sessionKey) {
        for (var i = 0; i < sessions.length; i++) {
            if (stringValue(sessions[i] && sessions[i].session_key, "") === sessionKey)
                return true;
        }
        return false;
    }

    function currentSessionObject() {
        var resolvedKey = stringValue(selectedSessionKey, stringValue(snapshot && snapshot.active_session_key, ""));
        if (!resolvedKey && sessions.length > 0)
            resolvedKey = stringValue(sessions[0] && sessions[0].session_key, "");
        for (var i = 0; i < sessions.length; i++) {
            if (stringValue(sessions[i] && sessions[i].session_key, "") === resolvedKey)
                return sessions[i];
        }
        return sessions.length > 0 ? sessions[0] : null;
    }

    function parseSnapshot(raw) {
        var payload = stringValue(raw, "");
        if (payload === "")
            return;
        try {
            var next = JSON.parse(payload);
            if (!next || typeof next !== "object")
                return;
            snapshot = next;
            var preferred = stringValue(selectedSessionKey, "");
            if (preferred !== "" && sessionExists(preferred))
                return;
            selectedSessionKey = stringValue(next.active_session_key, "");
            if (selectedSessionKey === "" && sessions.length > 0)
                selectedSessionKey = stringValue(sessions[0] && sessions[0].session_key, "");
        } catch (error) {
            console.warn("Failed to parse agent snapshot", error, raw);
        }
    }

    function applyActionResult(result) {
        if (!result || typeof result !== "object")
            return;
        if (result.snapshot)
            snapshot = result.snapshot;
        if (result.session && result.session.session_key)
            selectedSessionKey = result.session.session_key;
        if (queuedMessageAfterStart !== "" && currentSession && currentSession.session_key) {
            var queued = queuedMessageAfterStart;
            queuedMessageAfterStart = "";
            sendMessage(queued);
        }
    }

    function handleActionOutput(raw) {
        var payload = stringValue(raw, "");
        if (payload === "")
            return;
        try {
            applyActionResult(JSON.parse(payload));
            errorMessage = "";
        } catch (error) {
            console.warn("Failed to parse agent action output", error, raw);
        }
    }

    function runAction(args) {
        if (actionProcess.running)
            return;
        errorMessage = "";
        actionProcess.command = [i3pmBin].concat(args);
        actionProcess.running = true;
    }

    function startSession(optionalText) {
        var initialText = typeof optionalText === "string" ? optionalText.trim() : "";
        if (initialText !== "")
            queuedMessageAfterStart = initialText;
        runAction(["agent", "start"]);
    }

    function sendMessage(text) {
        var trimmed = typeof text === "string" ? text.trim() : "";
        if (trimmed === "")
            return;
        if (!currentSession || !currentSession.session_key) {
            startSession(trimmed);
            return;
        }
        if (!canSend)
            return;
        runAction(["agent", "send", currentSession.session_key, "--text", trimmed]);
        draftText = "";
    }

    function cancelCurrentTurn() {
        if (!currentSession || !currentSession.session_key || !canCancel)
            return;
        runAction(["agent", "cancel", currentSession.session_key]);
    }

    function approveRequest(requestId) {
        if (!currentSession || !currentSession.session_key)
            return;
        runAction(["agent", "approve", currentSession.session_key, String(requestId)]);
    }

    function denyRequest(requestId) {
        if (!currentSession || !currentSession.session_key)
            return;
        runAction(["agent", "deny", currentSession.session_key, String(requestId)]);
    }

    function selectSession(sessionKey) {
        selectedSessionKey = stringValue(sessionKey, "");
    }

    function newChat() {
        startSession("");
    }

    function setProvider(provider) {
        preferredProvider = stringValue(provider, preferredProvider);
        if (preferredProvider !== "codex")
            errorMessage = "Only the Codex adapter is implemented in this panel right now.";
    }

    function setModel(model) {
        preferredModel = stringValue(model, preferredModel);
    }
}
