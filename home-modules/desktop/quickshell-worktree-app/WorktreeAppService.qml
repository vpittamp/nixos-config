import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    required property QtObject appConfig

    property var dashboard: ({
            status: "loading",
            active_context: {},
            active_ai_sessions: [],
            projects: [],
            worktrees: []
        })
    property string selectedQualifiedName: ""
    property string actionMessage: ""
    property string actionError: ""
    property string busyLabel: ""
    property bool watcherStarted: false
    readonly property bool busy: commandProcess.running

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

    function applyDashboard(payload) {
        if (!payload || typeof payload !== "object")
            return;

        dashboard = payload;
        const worktrees = arrayOrEmpty(payload.worktrees);
        if (!worktrees.length) {
            selectedQualifiedName = "";
            return;
        }

        const activeQualified = stringOrEmpty(payload.active_context && (payload.active_context.qualified_name || payload.active_context.project_name));
        const selectedExists = worktrees.some(item => stringOrEmpty(item && item.qualified_name) === selectedQualifiedName);
        if (selectedExists)
            return;

        if (activeQualified && worktrees.some(item => stringOrEmpty(item && item.qualified_name) === activeQualified)) {
            selectedQualifiedName = activeQualified;
            return;
        }

        selectedQualifiedName = stringOrEmpty(worktrees[0] && worktrees[0].qualified_name);
    }

    function ensureWatcher() {
        if (dashboardWatchProcess.running)
            return;
        dashboardWatchProcess.command = [appConfig.i3pmBin, "dashboard", "watch", "--json", "--interval", String(appConfig.dashboardHeartbeatMs)];
        dashboardWatchProcess.running = true;
        watcherStarted = true;
    }

    function requestSnapshot() {
        if (snapshotProcess.running)
            return;
        snapshotProcess.command = [appConfig.i3pmBin, "dashboard", "snapshot", "--json"];
        snapshotProcess.running = true;
    }

    function clearStatus() {
        actionMessage = "";
        actionError = "";
    }

    function runJsonCommand(args, successLabel) {
        if (commandProcess.running)
            return;

        clearStatus();
        busyLabel = successLabel;
        commandProcess.successLabel = successLabel;
        commandProcess.command = args;
        commandProcess.running = true;
    }

    function switchWorktree(qualifiedName, targetHost) {
        if (!qualifiedName)
            return;
        const host = stringOrEmpty(targetHost).trim();
        const command = [appConfig.i3pmBin, "context", "ensure", qualifiedName, "--json"];
        if (host)
            command.splice(command.length - 1, 0, "--host", host);
        runJsonCommand(command, host ? `Switched to ${host}` : "Switched context");
    }

    function clearContext() {
        runJsonCommand([appConfig.i3pmBin, "context", "clear", "--json"], "Cleared worktree context");
    }

    function openTerminal(qualifiedName, targetHost) {
        if (!qualifiedName)
            return;
        const host = stringOrEmpty(targetHost).trim();
        const command = [appConfig.i3pmBin, "launch", "open", "terminal", "--project", qualifiedName, "--json"];
        if (host)
            command.splice(command.length - 1, 0, "--host", host);
        runJsonCommand(command, "Opened managed terminal");
    }

    function createWorktree(repoQualified, branch, baseBranch) {
        const repo = stringOrEmpty(repoQualified).trim();
        const nextBranch = stringOrEmpty(branch).trim();
        const base = stringOrEmpty(baseBranch).trim();
        if (!repo || !nextBranch)
            return;

        const command = [appConfig.i3pmBin, "worktree", "create", nextBranch, "--repo", repo, "--json"];
        if (base)
            command.splice(4, 0, "--from", base);
        runJsonCommand(command, "Created worktree");
    }

    function renameWorktree(qualifiedName, newBranch, forceRename) {
        const target = stringOrEmpty(qualifiedName).trim();
        const branch = stringOrEmpty(newBranch).trim();
        if (!target || !branch)
            return;

        const command = [appConfig.i3pmBin, "worktree", "rename", target, branch, "--json"];
        if (forceRename)
            command.push("--force");
        runJsonCommand(command, "Renamed worktree");
    }

    function removeWorktree(qualifiedName, forceRemove) {
        const target = stringOrEmpty(qualifiedName).trim();
        if (!target)
            return;

        const command = [appConfig.i3pmBin, "worktree", "remove", target, "--json"];
        if (forceRemove)
            command.push("--force");
        runJsonCommand(command, "Removed worktree");
    }

    function focusSession(sessionKey) {
        const target = stringOrEmpty(sessionKey).trim();
        if (!target)
            return;
        runJsonCommand([appConfig.i3pmBin, "session", "focus", target, "--json"], "Focused AI session");
    }

    function focusWindow(windowId, qualifiedName, targetHost, connectionKey) {
        const numericWindowId = Number(windowId || 0);
        if (!Number.isInteger(numericWindowId) || numericWindowId <= 0)
            return;

        const command = [appConfig.i3pmBin, "window", "focus", String(numericWindowId), "--project", stringOrEmpty(qualifiedName), "--json"];
        if (stringOrEmpty(targetHost))
            command.splice(command.length - 1, 0, "--host", stringOrEmpty(targetHost));
        if (stringOrEmpty(connectionKey))
            command.splice(command.length - 1, 0, "--connection-key", stringOrEmpty(connectionKey));
        runJsonCommand(command, "Focused window");
    }

    function openPath(path) {
        const target = stringOrEmpty(path).trim();
        if (!target || helperProcess.running)
            return;
        helperProcess.command = [appConfig.gioBin, "open", target];
        helperProcess.running = true;
    }

    Timer {
        id: dashboardRestartTimer
        interval: 1200
        repeat: false
        onTriggered: root.ensureWatcher()
    }

    Process {
        id: dashboardWatchProcess

        stdout: SplitParser {
            onRead: function(data) {
                const line = root.stringOrEmpty(data).trim();
                if (!line)
                    return;
                try {
                    root.applyDashboard(JSON.parse(line));
                } catch (_error) {
                }
            }
        }

        stderr: StdioCollector {
            id: dashboardWatchStderr
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                const stderr = root.stringOrEmpty(dashboardWatchStderr.text).trim();
                if (stderr)
                    root.actionError = stderr;
                dashboardRestartTimer.restart();
            }
        }
    }

    Process {
        id: snapshotProcess

        stdout: StdioCollector {
            id: snapshotStdout
        }

        stderr: StdioCollector {
            id: snapshotStderr
        }

        onExited: function(exitCode) {
            if (exitCode === 0) {
                const stdout = root.stringOrEmpty(snapshotStdout.text).trim();
                if (!stdout)
                    return;
                try {
                    root.applyDashboard(JSON.parse(stdout));
                } catch (_error) {
                    root.actionError = "Could not parse dashboard snapshot.";
                }
                return;
            }

            const stderr = root.stringOrEmpty(snapshotStderr.text).trim();
            if (stderr)
                root.actionError = stderr;
        }
    }

    Process {
        id: commandProcess

        property string successLabel: ""

        stdout: StdioCollector {
            id: commandStdout
        }

        stderr: StdioCollector {
            id: commandStderr
        }

        onExited: function(exitCode) {
            const stdout = root.stringOrEmpty(commandStdout.text).trim();
            const stderr = root.stringOrEmpty(commandStderr.text).trim();
            let parsed = null;

            if (stdout) {
                try {
                    parsed = JSON.parse(stdout);
                } catch (_error) {
                    parsed = null;
                }
            }

            root.busyLabel = "";

            if (exitCode === 0) {
                if (parsed && parsed.qualified_name)
                    root.selectedQualifiedName = root.stringOrEmpty(parsed.qualified_name);
                root.actionError = "";
                root.actionMessage = commandProcess.successLabel;
                root.requestSnapshot();
                return;
            }

            if (parsed && parsed.error) {
                root.actionError = root.stringOrEmpty(parsed.error);
            } else if (stderr) {
                root.actionError = stderr;
            } else if (stdout) {
                root.actionError = stdout;
            } else {
                root.actionError = "Command failed.";
            }
            root.actionMessage = "";
        }
    }

    Process {
        id: helperProcess

        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: helperStderr
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                const stderr = root.stringOrEmpty(helperStderr.text).trim();
                if (stderr)
                    root.actionError = stderr;
            }
        }
    }
}
