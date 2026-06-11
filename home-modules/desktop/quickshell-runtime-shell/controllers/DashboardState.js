.pragma library

function dashboardGeneration(state) {
    if (!state || typeof state !== "object") {
        return -1;
    }
    const generation = Number(state.snapshot_version || state.generation || -1);
    return Number.isFinite(generation) ? generation : -1;
}

function focusInvariantIssues(root, state) {
    const issues = [];
    const model = state && typeof state === "object" ? state : {};
    const focus = model.focus_state && typeof model.focus_state === "object" ? model.focus_state : {};
    const sessions = root.arrayOrEmpty(model.active_ai_sessions);
    const currentSession = root.stringOrEmpty(focus.current_session_key);
    if (currentSession) {
        let matchingSessions = 0;
        let currentWindowRows = 0;
        let currentRowMatchesSession = true;
        for (let i = 0; i < sessions.length; i += 1) {
            const session = sessions[i];
            if (root.sessionMatchesKey(session, currentSession)) {
                matchingSessions += 1;
            }
            if (root.boolOrFalse(session && session.is_current_window)) {
                currentWindowRows += 1;
                currentRowMatchesSession = currentRowMatchesSession && root.sessionMatchesKey(session, currentSession);
            }
        }
        if (matchingSessions !== 1) {
            issues.push("current_session_matches=" + String(matchingSessions));
        }
        if (currentWindowRows !== 1) {
            issues.push("current_session_rows=" + String(currentWindowRows));
        }
        if (!currentRowMatchesSession) {
            issues.push("current_session_row_mismatch");
        }
    }

    const currentWindowId = Number(focus.current_window_id || 0);
    if (currentWindowId > 0) {
        let matchingWindows = 0;
        const projects = root.arrayOrEmpty(model.projects);
        for (let i = 0; i < projects.length; i += 1) {
            const windows = root.arrayOrEmpty(projects[i] && projects[i].windows);
            for (let j = 0; j < windows.length; j += 1) {
                if (root.windowIdValue(windows[j]) === currentWindowId) {
                    matchingWindows += 1;
                }
            }
        }
        if (matchingWindows > 1) {
            issues.push("current_window_matches=" + String(matchingWindows));
        }
    }

    const currentWorkspace = root.stringOrEmpty(focus.current_workspace_name);
    if (currentWorkspace) {
        let seenWorkspaces = 0;
        const outputs = root.arrayOrEmpty(model.outputs);
        for (let i = 0; i < outputs.length; i += 1) {
            const workspaces = root.arrayOrEmpty(outputs[i] && outputs[i].workspaces);
            for (let j = 0; j < workspaces.length; j += 1) {
                if (root.workspaceNameValue(workspaces[j]) === currentWorkspace) {
                    seenWorkspaces += 1;
                }
            }
        }
        if (seenWorkspaces > 1) {
            issues.push("current_workspace_matches=" + String(seenWorkspaces));
        }
    }
    return issues;
}
