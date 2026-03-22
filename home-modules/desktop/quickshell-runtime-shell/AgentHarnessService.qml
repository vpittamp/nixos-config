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
            active_context: {},
            available_worktrees: []
        })
    property string selectedSessionKey: ""
    property string startTargetQualifiedName: ""
    property string preferredProvider: "codex"
    property string preferredModel: ""
    property string draftText: ""
    property string errorMessage: ""
    property var desktopSnapshot: ({
            active_context: {},
            focused_window: {},
            visible_windows: [],
            workspace: {},
            scratchpad: {},
            sessions: [],
            runtime: {},
            top_processes: []
        })
    property string queuedMessageAfterStart: ""
    property string deferredMessageUntilSnapshot: ""
    property bool actionRunning: false
    property bool snapshotLoaded: false
    property var pendingActionArgs: null
    property var sessionUnreadState: ({})
    property var pendingSessionEvents: ({})
    property int latestAgentEventSequence: 0
    property var sessionRecords: ({})
    property var sessionOrder: []
    property var sessionRowRevisions: ({})
    property var sessionRowSignatures: ({})
    property var currentSessionData: null
    property var transcriptRecords: ({})
    property var transcriptOrder: []
    property var transcriptRowRevisions: ({})
    property var transcriptRowSignatures: ({})

    readonly property alias sessionModel: sessionListModel
    readonly property alias transcriptModel: transcriptListModel
    readonly property int sessionCount: sessionListModel.count
    readonly property int transcriptCount: transcriptListModel.count
    readonly property var sessions: orderedSessions()
    readonly property var worktrees: arrayValue(snapshot && snapshot.available_worktrees)
    readonly property var startTargets: curatedStartTargets(worktrees, activeQualifiedName, startTargetQualifiedName)
    readonly property var currentSession: currentSessionData
    readonly property var transcript: orderedTranscriptItems()
    readonly property string activeQualifiedName: stringValue(snapshot && snapshot.active_context && snapshot.active_context.qualified_name, "")
    readonly property var desktopContext: desktopSnapshot && desktopSnapshot.active_context ? desktopSnapshot.active_context : ({})
    readonly property var desktopFocusedWindow: desktopSnapshot && desktopSnapshot.focused_window ? desktopSnapshot.focused_window : ({})
    readonly property var desktopWorkspace: desktopSnapshot && desktopSnapshot.workspace ? desktopSnapshot.workspace : ({})
    readonly property var desktopScratchpad: desktopSnapshot && desktopSnapshot.scratchpad ? desktopSnapshot.scratchpad : ({})
    readonly property var desktopSessions: arrayValue(desktopSnapshot && desktopSnapshot.sessions)
    readonly property var desktopProcesses: arrayValue(desktopSnapshot && desktopSnapshot.top_processes)
    readonly property int desktopVisibleWindowCount: Number(desktopSnapshot && desktopSnapshot.visible_window_count || 0)
    readonly property int desktopRevision: Number(desktopSnapshot && desktopSnapshot.desktop_revision || 0)
    readonly property int unreadSessionCount: countUnreadSessions()
    readonly property int runningSessionCount: countSessionsByPhase("working")
    readonly property bool isGenerating: !!(currentSession && currentSession.session_phase === "working")
    readonly property bool hasPendingApproval: !!(currentSession && currentSession.pending_approval)
    readonly property bool hasError: !!(currentSession && stringValue(currentSession.last_error, "") !== "")
    readonly property bool canSend: !!(currentSession ? currentSession.can_send : !actionRunning)
    readonly property bool canCancel: !!(currentSession && currentSession.can_cancel)
    readonly property string currentSessionTitle: sessionTitle(currentSession)
    readonly property string currentSessionSubtitle: sessionSubtitle(currentSession)

    ListModel {
        id: sessionListModel
        dynamicRoles: true
    }

    ListModel {
        id: transcriptListModel
        dynamicRoles: true
    }

    Timer {
        id: watcherRestartTimer
        interval: 1000
        repeat: false
        onTriggered: watcher.running = true
    }

    Timer {
        id: desktopWatcherRestartTimer
        interval: 1000
        repeat: false
        onTriggered: desktopWatcher.running = true
    }

    Timer {
        id: agentEventFlushTimer
        interval: 75
        repeat: false
        onTriggered: root.flushPendingSessionEvents()
    }

    Process {
        id: watcher
        command: [root.i3pmBin, "agent", "watch"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.handleWatcherOutput(data);
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
        id: desktopWatcher
        command: [root.i3pmBin, "agent", "desktop-watch"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.handleDesktopWatcherOutput(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (data && data.trim() !== "")
                    console.warn("agent.desktop-watch:", data);
            }
        }
        onExited: function() {
            desktopWatcherRestartTimer.restart();
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
            if (!running && root.pendingActionArgs && root.pendingActionArgs.length > 0) {
                var nextArgs = root.pendingActionArgs;
                root.pendingActionArgs = null;
                root.runAction(nextArgs);
            }
        }
    }

    Process {
        id: snapshotProcess
        command: [root.i3pmBin, "agent", "snapshot"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                root.handleSnapshotOutput(data);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                if (data && data.trim() !== "")
                    root.errorMessage = data.trim();
            }
        }
    }

    function stringValue(value, fallback) {
        return typeof value === "string" && value.trim() !== "" ? value.trim() : fallback;
    }

    function normalizedText(value) {
        if (value === undefined || value === null)
            return "";
        return String(value).trim();
    }

    function arrayValue(value) {
        return Array.isArray(value) ? value : [];
    }

    function copyMap(value) {
        var result = {};
        if (!value || typeof value !== "object")
            return result;
        for (var key in value)
            result[key] = value[key];
        return result;
    }

    function copyArray(value) {
        return Array.isArray(value) ? value.slice(0) : [];
    }

    function cloneValue(value) {
        if (value === undefined || value === null)
            return value;
        return JSON.parse(JSON.stringify(value));
    }

    function stableSignature(value) {
        if (value === undefined || value === null)
            return "";
        try {
            return JSON.stringify(value);
        } catch (error) {
            return String(value);
        }
    }

    function orderedSessions() {
        var ordered = [];
        for (var i = 0; i < sessionOrder.length; i++) {
            var session = sessionRecords[sessionOrder[i]];
            if (session)
                ordered.push(session);
        }
        return ordered;
    }

    function orderedTranscriptItems() {
        var ordered = [];
        for (var i = 0; i < transcriptOrder.length; i++) {
            var item = transcriptRecords[transcriptOrder[i]];
            if (item)
                ordered.push(item);
        }
        return ordered;
    }

    function sessionByKey(sessionKey) {
        var normalized = stringValue(sessionKey, "");
        return normalized !== "" ? (sessionRecords[normalized] || null) : null;
    }

    function transcriptItemById(itemId) {
        var normalized = stringValue(itemId, "");
        return normalized !== "" ? (transcriptRecords[normalized] || null) : null;
    }

    function sessionTitle(session) {
        if (!session || typeof session !== "object")
            return "New session";
        if (stringValue(session.title, "") !== "")
            return session.title;
        if (stringValue(session && session.context && session.context.qualified_name, "") !== "")
            return session.context.qualified_name;
        if (stringValue(session.cwd, "") !== "")
            return session.cwd.split("/").pop();
        return stringValue(session.session_key, "New session");
    }

    function sessionSubtitle(session) {
        if (!session || typeof session !== "object")
            return "Choose a worktree and start a session";
        var parts = [];
        var qualifiedName = stringValue(session && session.context && session.context.qualified_name, "");
        if (qualifiedName !== "")
            parts.push(qualifiedName);
        var stateLabel = stringValue(session.state_label, stringValue(session.session_phase, ""));
        if (stateLabel !== "")
            parts.push(stateLabel);
        var preview = stringValue(session.preview, "");
        if (preview !== "")
            parts.push(preview);
        else if (stringValue(session.cwd, "") !== "")
            parts.push(session.cwd);
        return parts.join("  •  ");
    }

    function countUnreadSessions() {
        var count = 0;
        for (var i = 0; i < sessionOrder.length; i++) {
            if (sessionHasUnread(sessionOrder[i]))
                count += 1;
        }
        return count;
    }

    function countSessionsByPhase(phase) {
        var normalized = stringValue(phase, "");
        var count = 0;
        for (var i = 0; i < sessionOrder.length; i++) {
            var session = sessionRecords[sessionOrder[i]];
            if (stringValue(session && session.session_phase, "") === normalized)
                count += 1;
        }
        return count;
    }

    function reconcileKeyedModel(model, desiredRows, keyRole) {
        var desired = Array.isArray(desiredRows) ? desiredRows : [];

        function rowEqual(left, right) {
            if (!left || !right)
                return false;
            for (var key in left) {
                if (left[key] !== right[key])
                    return false;
            }
            for (var extraKey in right) {
                if (right[extraKey] !== left[extraKey])
                    return false;
            }
            return true;
        }

        for (var removeIndex = model.count - 1; removeIndex >= 0; removeIndex--) {
            var existingKey = stringValue(model.get(removeIndex)[keyRole], "");
            var keep = false;
            for (var i = 0; i < desired.length; i++) {
                if (stringValue(desired[i] && desired[i][keyRole], "") === existingKey) {
                    keep = true;
                    break;
                }
            }
            if (!keep)
                model.remove(removeIndex, 1);
        }

        for (var desiredIndex = 0; desiredIndex < desired.length; desiredIndex++) {
            var desiredRow = desired[desiredIndex];
            var desiredKey = stringValue(desiredRow && desiredRow[keyRole], "");
            if (desiredKey === "")
                continue;

            if (desiredIndex < model.count && stringValue(model.get(desiredIndex)[keyRole], "") === desiredKey) {
                if (!rowEqual(model.get(desiredIndex), desiredRow))
                    model.set(desiredIndex, desiredRow);
                continue;
            }

            var existingIndex = -1;
            for (var searchIndex = 0; searchIndex < model.count; searchIndex++) {
                if (stringValue(model.get(searchIndex)[keyRole], "") === desiredKey) {
                    existingIndex = searchIndex;
                    break;
                }
            }

            if (existingIndex >= 0) {
                model.move(existingIndex, desiredIndex, 1);
                if (!rowEqual(model.get(desiredIndex), desiredRow))
                    model.set(desiredIndex, desiredRow);
            } else
                model.insert(desiredIndex, desiredRow);
        }
    }

    function syncSessionStore(sessionList) {
        var ordered = sortSessions(sessionList);
        var nextRecords = {};
        var nextOrder = [];
        var nextRevisions = {};
        var nextSignatures = {};

        for (var i = 0; i < ordered.length; i++) {
            var session = cloneValue(ordered[i]);
            var sessionKey = stringValue(session && session.session_key, "");
            if (sessionKey === "")
                continue;
            var signature = stableSignature(session);
            var previousSignature = stringValue(sessionRowSignatures[sessionKey], "");
            var previousRevision = Number(sessionRowRevisions[sessionKey] || 0);
            nextRecords[sessionKey] = session;
            nextOrder.push(sessionKey);
            nextSignatures[sessionKey] = signature;
            nextRevisions[sessionKey] = signature === previousSignature ? previousRevision : previousRevision + 1;
        }

        sessionRecords = nextRecords;
        sessionOrder = nextOrder;
        sessionRowRevisions = nextRevisions;
        sessionRowSignatures = nextSignatures;

        var modelRows = [];
        for (var j = 0; j < nextOrder.length; j++)
            modelRows.push({
                session_key: nextOrder[j],
                row_revision: Number(nextRevisions[nextOrder[j]] || 0)
            });
        reconcileKeyedModel(sessionListModel, modelRows, "session_key");
    }

    function syncTranscriptStore(items) {
        var transcriptItems = arrayValue(items);
        var nextRecords = {};
        var nextOrder = [];
        var nextRevisions = {};
        var nextSignatures = {};

        for (var i = 0; i < transcriptItems.length; i++) {
            var item = cloneValue(transcriptItems[i]);
            var itemId = stringValue(item && item.id, "");
            if (itemId === "")
                continue;
            var signature = stableSignature(item);
            var previousSignature = stringValue(transcriptRowSignatures[itemId], "");
            var previousRevision = Number(transcriptRowRevisions[itemId] || 0);
            nextRecords[itemId] = item;
            nextOrder.push(itemId);
            nextSignatures[itemId] = signature;
            nextRevisions[itemId] = signature === previousSignature ? previousRevision : previousRevision + 1;
        }

        transcriptRecords = nextRecords;
        transcriptOrder = nextOrder;
        transcriptRowRevisions = nextRevisions;
        transcriptRowSignatures = nextSignatures;

        var modelRows = [];
        for (var j = 0; j < nextOrder.length; j++)
            modelRows.push({
                item_id: nextOrder[j],
                row_revision: Number(nextRevisions[nextOrder[j]] || 0)
            });
        reconcileKeyedModel(transcriptListModel, modelRows, "item_id");
    }

    function sortSessions(list) {
        var nextList = copyArray(list);
        nextList.sort(function(a, b) {
            var left = stringValue(a && a.updated_at, "");
            var right = stringValue(b && b.updated_at, "");
            if (left === right)
                return 0;
            return left < right ? 1 : -1;
        });
        return nextList;
    }

    function shouldReplaceSession(existingSession, nextSession) {
        if (!existingSession)
            return true;
        if (!nextSession)
            return false;

        var existingRevision = Number(existingSession.session_revision || 0);
        var nextRevision = Number(nextSession.session_revision || 0);
        if (existingRevision > 0 || nextRevision > 0) {
            if (nextRevision < existingRevision)
                return false;
            if (nextRevision > existingRevision)
                return true;
        }

        var existingUpdated = stringValue(existingSession.updated_at, "");
        var nextUpdated = stringValue(nextSession.updated_at, "");
        var existingTranscriptSize = transcriptSize(existingSession);
        var nextTranscriptSize = transcriptSize(nextSession);

        if (nextUpdated !== "" && existingUpdated !== "" && nextUpdated < existingUpdated && nextTranscriptSize <= existingTranscriptSize)
            return false;
        if (nextTranscriptSize < existingTranscriptSize && nextUpdated === existingUpdated)
            return false;
        return true;
    }

    function mergeSessionList(existingSessions, incomingSessions) {
        var merged = copyArray(existingSessions);
        var incoming = arrayValue(incomingSessions);

        for (var i = 0; i < incoming.length; i++) {
            var nextSession = incoming[i];
            var sessionKey = stringValue(nextSession && nextSession.session_key, "");
            if (sessionKey === "")
                continue;
            var existingIndex = -1;
            for (var j = 0; j < merged.length; j++) {
                if (stringValue(merged[j] && merged[j].session_key, "") === sessionKey) {
                    existingIndex = j;
                    break;
                }
            }

            if (existingIndex < 0) {
                merged.push(nextSession);
                continue;
            }

            if (shouldReplaceSession(merged[existingIndex], nextSession))
                merged[existingIndex] = nextSession;
        }

        return sortSessions(merged);
    }

    function mergeSnapshotData(baseSnapshot, incomingSnapshot) {
        var base = baseSnapshot && typeof baseSnapshot === "object" ? baseSnapshot : ({
                active_session_key: "",
                sessions: [],
                active_context: {},
                available_worktrees: []
            });
        var incoming = incomingSnapshot && typeof incomingSnapshot === "object" ? incomingSnapshot : {};
        return {
            active_session_key: stringValue(incoming.active_session_key, stringValue(base.active_session_key, "")),
            sessions: mergeSessionList(base.sessions, incoming.sessions),
            active_context: incoming.active_context && typeof incoming.active_context === "object"
                ? incoming.active_context
                : (base.active_context || {}),
            available_worktrees: Array.isArray(incoming.available_worktrees)
                ? copyArray(incoming.available_worktrees)
                : copyArray(base.available_worktrees),
        };
    }

    function sessionExists(sessionKey) {
        return sessionByKey(sessionKey) !== null;
    }

    function worktreeExists(qualifiedName, worktreeList) {
        var normalized = stringValue(qualifiedName, "");
        var list = Array.isArray(worktreeList) ? worktreeList : worktrees;
        if (normalized === "")
            return false;
        for (var i = 0; i < list.length; i++) {
            if (stringValue(list[i] && list[i].qualified_name, "") === normalized)
                return true;
        }
        return false;
    }

    function worktreeByQualifiedName(qualifiedName, worktreeList) {
        var normalized = stringValue(qualifiedName, "");
        var list = Array.isArray(worktreeList) ? worktreeList : worktrees;
        if (normalized === "")
            return null;
        for (var i = 0; i < list.length; i++) {
            if (stringValue(list[i] && list[i].qualified_name, "") === normalized)
                return list[i];
        }
        return null;
    }

    function worktreeLabel(worktree) {
        if (!worktree || typeof worktree !== "object")
            return "";
        var qualifiedName = stringValue(worktree.qualified_name, "");
        var branch = stringValue(worktree.branch, "");
        var repoDisplay = stringValue(worktree.repo_display, qualifiedName);
        if (repoDisplay !== "" && branch !== "")
            return repoDisplay + "  •  " + branch;
        return qualifiedName;
    }

    function curatedStartTargets(worktreeList, activeQualifiedNameValue, selectedQualifiedNameValue) {
        var list = Array.isArray(worktreeList) ? worktreeList : [];
        var activeQualified = stringValue(activeQualifiedNameValue, "");
        var selectedQualified = stringValue(selectedQualifiedNameValue, "");
        var ranked = [];
        var seen = {};

        function pushWorktree(worktree) {
            if (!worktree || typeof worktree !== "object")
                return;
            var qualifiedName = stringValue(worktree.qualified_name, "");
            var branch = stringValue(worktree.branch, "");
            if (qualifiedName === "" || branch === "HEAD" || seen[qualifiedName])
                return;
            seen[qualifiedName] = true;
            ranked.push(worktree);
        }

        pushWorktree(worktreeByQualifiedName(selectedQualified, list));
        pushWorktree(worktreeByQualifiedName(activeQualified, list));

        for (var i = 0; i < list.length; i++) {
            pushWorktree(list[i]);
            if (ranked.length >= 12)
                break;
        }

        return ranked;
    }

    function findSessionByKey(sessionKey, sessionList) {
        var normalizedKey = stringValue(sessionKey, "");
        if (normalizedKey === "")
            return null;
        if (Array.isArray(sessionList)) {
            for (var i = 0; i < sessionList.length; i++) {
                if (stringValue(sessionList[i] && sessionList[i].session_key, "") === normalizedKey)
                    return sessionList[i];
            }
        }
        return sessionByKey(normalizedKey);
    }

    function firstSendableSessionObject(sessionList) {
        var list = Array.isArray(sessionList) ? sessionList : sessions;
        for (var i = 0; i < list.length; i++) {
            if (!!(list[i] && list[i].can_send))
                return list[i];
        }
        return list.length > 0 ? list[0] : null;
    }

    function resolvedCurrentSessionObject() {
        var selected = sessionByKey(selectedSessionKey);
        if (selected)
            return selected;
        var currentKey = stringValue(currentSessionData && currentSessionData.session_key, "");
        if (currentKey !== "") {
            var current = sessionByKey(currentKey);
            if (current)
                return current;
        }
        var activeKey = stringValue(snapshot && snapshot.active_session_key, "");
        if (activeKey !== "") {
            var activeSession = sessionByKey(activeKey);
            if (activeSession)
                return activeSession;
        }
        return null;
    }

    function choosePreferredSessionKey(snapshotValue) {
        var nextSessions = arrayValue(snapshotValue && snapshotValue.sessions);
        var activeKey = stringValue(snapshotValue && snapshotValue.active_session_key, "");
        if (activeKey !== "") {
            for (var i = 0; i < nextSessions.length; i++) {
                if (stringValue(nextSessions[i] && nextSessions[i].session_key, "") === activeKey && !!(nextSessions[i] && nextSessions[i].can_send))
                    return activeKey;
            }
        }
        var fallback = firstSendableSessionObject(nextSessions);
        return stringValue(fallback && fallback.session_key, activeKey);
    }

    function chooseDefaultStartTarget(snapshotValue) {
        var nextWorktrees = arrayValue(snapshotValue && snapshotValue.available_worktrees);
        var activeQualified = stringValue(snapshotValue && snapshotValue.active_context && snapshotValue.active_context.qualified_name, "");
        if (worktreeExists(activeQualified, nextWorktrees))
            return activeQualified;
        return stringValue(nextWorktrees.length > 0 && nextWorktrees[0] && nextWorktrees[0].qualified_name, "");
    }

    function transcriptSize(session) {
        return Array.isArray(session && session.transcript) ? session.transcript.length : 0;
    }

    function markUnreadSessions(nextSnapshot) {
        var previousSessions = orderedSessions();
        var nextSessions = arrayValue(nextSnapshot && nextSnapshot.sessions);
        var selectedKey = stringValue(selectedSessionKey, "");
        var unread = copyMap(sessionUnreadState);
        var activeKeys = {};

        for (var i = 0; i < nextSessions.length; i++) {
            var nextSession = nextSessions[i];
            var sessionKey = stringValue(nextSession && nextSession.session_key, "");
            if (sessionKey === "")
                continue;
            activeKeys[sessionKey] = true;
            if (sessionKey === selectedKey) {
                unread[sessionKey] = false;
                continue;
            }

            var previous = findSessionByKey(sessionKey, previousSessions);
            var nextTranscriptSize = transcriptSize(nextSession);
            var previousTranscriptSize = transcriptSize(previous);
            var updatedChanged = stringValue(previous && previous.updated_at, "") !== stringValue(nextSession && nextSession.updated_at, "");
            var needsAttention = stringValue(nextSession && nextSession.session_phase, "") === "needs_attention";
            if ((!previous && nextTranscriptSize > 0) || nextTranscriptSize > previousTranscriptSize || (updatedChanged && needsAttention))
                unread[sessionKey] = true;
        }

        for (var key in unread) {
            if (!activeKeys[key])
                delete unread[key];
        }
        sessionUnreadState = unread;
    }

    function clearUnread(sessionKey) {
        var normalized = stringValue(sessionKey, "");
        if (normalized === "")
            return;
        var unread = copyMap(sessionUnreadState);
        unread[normalized] = false;
        sessionUnreadState = unread;
    }

    function sessionHasUnread(sessionKey) {
        var normalized = stringValue(sessionKey, "");
        return normalized !== "" && !!sessionUnreadState[normalized];
    }

    function applySnapshot(next) {
        if (!next || typeof next !== "object")
            return;
        markUnreadSessions(next);
        snapshot = next;
        syncSessionStore(arrayValue(next.sessions));
        snapshotLoaded = true;

        var preferred = stringValue(selectedSessionKey, "");
        if (preferred !== "" && !sessionExists(preferred))
            preferred = "";
        if (preferred === "")
            selectedSessionKey = choosePreferredSessionKey(next);
        if (selectedSessionKey === "" && sessions.length > 0)
            selectedSessionKey = stringValue(sessions[0] && sessions[0].session_key, "");
        if (selectedSessionKey !== "")
            clearUnread(selectedSessionKey);

        var nextSession = findSessionByKey(selectedSessionKey);
        if (!nextSession) {
            var resolvedKey = choosePreferredSessionKey(next);
            nextSession = findSessionByKey(resolvedKey);
            if (!nextSession && sessionOrder.length > 0)
                nextSession = sessionByKey(sessionOrder[0]);
        }
        currentSessionData = nextSession;
        syncTranscriptStore(nextSession && Array.isArray(nextSession.transcript) ? nextSession.transcript : []);

        var sessionQualifiedName = stringValue(nextSession && nextSession.context && nextSession.context.qualified_name, "");
        if (worktreeExists(sessionQualifiedName, next.available_worktrees))
            startTargetQualifiedName = sessionQualifiedName;
        else {
            var preferredTarget = stringValue(startTargetQualifiedName, "");
            if (preferredTarget === "" || !worktreeExists(preferredTarget, next.available_worktrees))
                startTargetQualifiedName = chooseDefaultStartTarget(next);
        }

        var sessionError = stringValue(nextSession && nextSession.last_error, "");
        if (sessionError !== "")
            errorMessage = sessionError;
        else if (!actionRunning)
            errorMessage = "";
    }

    function queueSessionEvent(event) {
        if (!event || typeof event !== "object")
            return;
        var sequence = Number(event.sequence || 0);
        if (sequence > 0 && sequence <= latestAgentEventSequence)
            return;
        var session = event.session;
        var sessionKey = stringValue(session && session.session_key, "");
        if (sessionKey === "")
            return;
        var pending = copyMap(pendingSessionEvents);
        var previous = pending[sessionKey];
        if (!previous || Number(previous.sequence || 0) <= sequence)
            pending[sessionKey] = event;
        pendingSessionEvents = pending;
        agentEventFlushTimer.restart();
    }

    function flushPendingSessionEvents() {
        var pending = pendingSessionEvents;
        var sessionKeys = Object.keys(pending || {});
        if (sessionKeys.length === 0)
            return;

        pendingSessionEvents = ({});
        var next = mergeSnapshotData(snapshot, {});
        var nextSessions = copyArray(next.sessions);
        var maxSequence = latestAgentEventSequence;

        sessionKeys.sort(function(leftKey, rightKey) {
            return Number(pending[leftKey].sequence || 0) - Number(pending[rightKey].sequence || 0);
        });

        for (var i = 0; i < sessionKeys.length; i++) {
            var event = pending[sessionKeys[i]];
            var session = event && event.session;
            var sessionKey = stringValue(session && session.session_key, "");
            if (sessionKey === "")
                continue;
            var existingIndex = -1;
            for (var j = 0; j < nextSessions.length; j++) {
                if (stringValue(nextSessions[j] && nextSessions[j].session_key, "") === sessionKey) {
                    existingIndex = j;
                    break;
                }
            }
            if (existingIndex >= 0) {
                if (shouldReplaceSession(nextSessions[existingIndex], session))
                    nextSessions[existingIndex] = session;
            } else
                nextSessions.push(session);

            var activeSessionKey = stringValue(event && event.active_session_key, "");
            if (activeSessionKey !== "")
                next.active_session_key = activeSessionKey;

            var sequence = Number(event.sequence || 0);
            if (sequence > maxSequence)
                maxSequence = sequence;
        }

        latestAgentEventSequence = maxSequence;
        next.sessions = sortSessions(nextSessions);
        applySnapshot(next);
    }

    function parseSnapshot(raw) {
        var payload = stringValue(raw, "");
        if (payload === "")
            return;
        try {
            var next = JSON.parse(payload);
            applySnapshot(mergeSnapshotData(snapshot, next));
        } catch (error) {
            console.warn("Failed to parse agent snapshot", error, raw);
        }
    }

    function applyDesktopSnapshot(next) {
        if (!next || typeof next !== "object")
            return;
        desktopSnapshot = cloneValue(next);
    }

    function handleDesktopWatcherOutput(raw) {
        var payload = stringValue(raw, "");
        if (payload === "")
            return;
        try {
            var message = JSON.parse(payload);
            if (message && message.kind === "snapshot" && message.snapshot) {
                applyDesktopSnapshot(message.snapshot);
                return;
            }
            applyDesktopSnapshot(message);
        } catch (error) {
            console.warn("Failed to parse agent desktop watch output", error, raw);
        }
    }

    function handleWatcherOutput(raw) {
        var payload = stringValue(raw, "");
        if (payload === "")
            return;
        try {
            var message = JSON.parse(payload);
            if (message && message.kind === "snapshot" && message.snapshot) {
                latestAgentEventSequence = 0;
                pendingSessionEvents = ({});
                applySnapshot(mergeSnapshotData(snapshot, message.snapshot));
                return;
            }
            if (message && message.kind === "event" && message.event) {
                queueSessionEvent(message.event);
                return;
            }
            applySnapshot(mergeSnapshotData(snapshot, message));
        } catch (error) {
            console.warn("Failed to parse agent watch output", error, raw);
        }
    }

    function handleSnapshotOutput(raw) {
        parseSnapshot(raw);
        if (deferredMessageUntilSnapshot === "")
            return;
        var deferred = deferredMessageUntilSnapshot;
        deferredMessageUntilSnapshot = "";
        sendMessageInternal(deferred, false);
    }

    function applyActionResult(result) {
        if (!result || typeof result !== "object")
            return;
        var nextSnapshot = snapshot;
        if (result.snapshot)
            nextSnapshot = mergeSnapshotData(nextSnapshot, result.snapshot);
        if (result.session && result.session.session_key)
            nextSnapshot = mergeSnapshotData(nextSnapshot, {
                    active_session_key: result.session.session_key,
                    sessions: [result.session]
                });
        if (nextSnapshot)
            applySnapshot(nextSnapshot);
        if (result.session && result.session.session_key) {
            selectedSessionKey = result.session.session_key;
            currentSessionData = sessionByKey(selectedSessionKey);
            syncTranscriptStore(currentSessionData && Array.isArray(currentSessionData.transcript) ? currentSessionData.transcript : []);
        }
        if (selectedSessionKey !== "")
            clearUnread(selectedSessionKey);
        if (queuedMessageAfterStart !== "" && currentSessionData && currentSessionData.session_key) {
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
        if (actionProcess.running) {
            pendingActionArgs = Array.isArray(args) ? args.slice(0) : [String(args)];
            return;
        }
        errorMessage = "";
        actionProcess.command = [i3pmBin].concat(args);
        actionProcess.running = true;
    }

    function requestSnapshot() {
        if (snapshotProcess.running)
            return;
        errorMessage = "";
        snapshotProcess.running = true;
    }

    function startSession(optionalText) {
        var initialText = normalizedText(optionalText);
        if (initialText !== "")
            queuedMessageAfterStart = initialText;
        var args = ["agent", "start"];
        if (startTargetQualifiedName !== "")
            args.push("--qualified-name", startTargetQualifiedName);
        if (preferredModel !== "")
            args.push("--model", preferredModel);
        runAction(args);
    }

    function sendMessageInternal(text, allowSnapshotRecovery) {
        var trimmed = normalizedText(text);
        if (trimmed === "")
            return;
        var resolvedSession = resolvedCurrentSessionObject();
        if (!resolvedSession || !resolvedSession.session_key) {
            if (!snapshotLoaded) {
                deferredMessageUntilSnapshot = trimmed;
                requestSnapshot();
                return;
            }
            var existingSession = firstSendableSessionObject();
            if (existingSession && existingSession.session_key) {
                runAction(["agent", "send", existingSession.session_key, "--text", trimmed]);
                draftText = "";
                return;
            }
            startSession(trimmed);
            return;
        }

        if (!!resolvedSession.can_send) {
            if (stringValue(selectedSessionKey, "") !== stringValue(resolvedSession.session_key, ""))
                selectSession(resolvedSession.session_key);
            runAction(["agent", "send", resolvedSession.session_key, "--text", trimmed]);
            draftText = "";
            return;
        }

        if (allowSnapshotRecovery && snapshotLoaded && !snapshotProcess.running) {
            deferredMessageUntilSnapshot = trimmed;
            requestSnapshot();
            return;
        }

        var blockingSession = resolvedSession;
        var blockingError = stringValue(blockingSession && blockingSession.last_error, "");
        if (blockingError !== "") {
            errorMessage = blockingError;
            return;
        }

        if (!!(blockingSession && blockingSession.pending_approval)) {
            errorMessage = "Resolve the pending approval in this session before sending another message.";
            return;
        }

        errorMessage = "Wait for the current session to finish before sending another message.";
    }

    function sendMessage(text) {
        sendMessageInternal(text, true);
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
        clearUnread(selectedSessionKey);
        var selected = sessionByKey(selectedSessionKey);
        currentSessionData = selected;
        syncTranscriptStore(selected && Array.isArray(selected.transcript) ? selected.transcript : []);
        var qualifiedName = stringValue(selected && selected.context && selected.context.qualified_name, "");
        if (qualifiedName !== "" && worktreeExists(qualifiedName))
            startTargetQualifiedName = qualifiedName;
    }

    function newChat() {
        startSession("");
    }

    function setProvider(provider) {
        preferredProvider = stringValue(provider, preferredProvider);
        if (preferredProvider !== "codex")
            errorMessage = "Only the Codex adapter is implemented in this panel right now.";
    }

    function setStartTarget(qualifiedName) {
        var normalized = stringValue(qualifiedName, "");
        if (normalized === "" || !worktreeExists(normalized))
            return;
        startTargetQualifiedName = normalized;
    }

    function setModel(model) {
        preferredModel = stringValue(model, preferredModel);
    }
}
