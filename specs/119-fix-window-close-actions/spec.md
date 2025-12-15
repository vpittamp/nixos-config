# Feature Specification: Eww Monitoring Widget Improvements

**Feature Branch**: `119-fix-window-close-actions`
**Created**: 2025-12-15
**Status**: Draft
**Input**: User description: "review our eww monitoring widget, and make the following improvements; add a debug setting that can be toggled on and off. when debug is on the json window and environment variable functionality should be exposed, but when debug is off, they should not be exposed; 2. fix the window close action on the project/worktree level and on the individual window level. it doesn't appear to be reliably working; consider making the widget less wide by default, perhaps reducing the width by a third. if we can do so reliably, and in a very stable way (relative to eww functionality. research this), i would like the ability to dynamically change the width of the widget, and persist that width throughout the session, which should persist toggle off and on actions; remove the badges that correspond to workspace numbers as i don't use them currently. also remove the labels that show prj, ws, win; they are unneccessary;"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reliable Window Closing (Priority: P1)

As a user managing windows through the monitoring panel, I need window close actions to work reliably at both the project/worktree level and individual window level so that I can efficiently clean up my workspace without manual intervention.

**Why this priority**: Window closing is a core interaction that users depend on. Unreliable close actions break trust in the tool and force users to manually close windows, defeating the purpose of the panel.

**Independent Test**: Can be fully tested by opening multiple windows in a project, using the close actions, and verifying all targeted windows are closed without errors or leftover windows.

**Acceptance Scenarios**:

1. **Given** a project with 5 open windows in the monitoring panel, **When** I click the close action at the project level, **Then** all 5 windows belonging to that project close within 2 seconds and the panel updates to reflect zero windows.

2. **Given** an individual window row in the panel, **When** I click the close button (󰅖), **Then** that specific window closes immediately and is removed from the panel display.

3. **Given** a worktree with windows across multiple workspaces, **When** I trigger the worktree close action, **Then** all windows marked with that worktree's scope are closed regardless of which workspace they occupy.

4. **Given** I rapidly click close actions on multiple windows (stress test), **When** the system processes these requests, **Then** all windows close without race conditions, duplicate kill attempts, or panel state inconsistencies.

5. **Given** a window that is slow to close (blocking dialog), **When** the close action is triggered, **Then** the system handles the delay gracefully without freezing the panel or losing track of window state.

---

### User Story 2 - Debug Mode Toggle (Priority: P2)

As a developer troubleshooting window management issues, I need a debug mode that exposes JSON inspection and environment variable functionality, while keeping the interface clean for normal use when debug is off.

**Why this priority**: Debug features add visual clutter for daily use but are essential for troubleshooting. A toggle provides the best of both worlds without removing functionality.

**Independent Test**: Can be fully tested by toggling debug mode on/off and verifying the JSON and environment variable UI elements appear/disappear accordingly.

**Acceptance Scenarios**:

1. **Given** debug mode is OFF (default), **When** I view the monitoring panel, **Then** no JSON inspection icons or environment variable expand triggers are visible on any window row.

2. **Given** debug mode is OFF, **When** I interact with window rows, **Then** there is no way to access JSON data or environment variables for any window.

3. **Given** debug mode is ON, **When** I view a window row, **Then** the JSON expand icon (󰅂/󰅀) and environment variable trigger (󰀫) become visible and functional.

4. **Given** debug mode is ON and I click the environment variable trigger, **When** the panel expands, **Then** I see I3PM variables and other environment variables for that window's process.

5. **Given** I toggle debug mode while viewing the panel, **When** the toggle completes, **Then** the UI updates immediately without requiring a panel close/reopen.

---

### User Story 3 - Reduced Panel Width with Session Persistence (Priority: P2)

As a user with limited screen real estate, I want the panel to be narrower by default (approximately one-third less wide) and optionally have the ability to resize it dynamically with the width persisting across toggle off/on actions within a session.

**Why this priority**: Screen space is valuable. A narrower default serves most users better, and dynamic resizing with persistence provides power users flexibility without losing their preferences during a session.

**Independent Test**: Can be fully tested by measuring the panel width, resizing if the feature is implemented, toggling the panel off and on, and verifying the width persists.

**Acceptance Scenarios**:

1. **Given** the default panel configuration on a non-ThinkPad host, **When** the panel opens, **Then** the width is approximately 307 pixels (reduced from 460 pixels, roughly one-third narrower).

2. **Given** the default panel configuration on a ThinkPad host, **When** the panel opens, **Then** the width is approximately 213 pixels (reduced from 320 pixels, roughly one-third narrower).

3. **Given** the panel is open with a specific width, **When** I close the panel and reopen it within the same session, **Then** the panel opens with the same width it had before closing.

4. **Given** I restart my Sway session, **When** I open the panel, **Then** it opens with the default configured width (session persistence does not survive restarts).

5. **(If dynamic resize implemented)** **Given** the panel is open, **When** I drag the panel edge to resize, **Then** the width adjusts smoothly and the new width is remembered for the session.

---

### User Story 4 - Fix Return-to-Window Notification (Priority: P1)

As a Claude Code user who receives "Claude Code Ready" notifications, I need the "Return to Window" action to reliably focus the correct terminal window, switching projects if necessary, so I can seamlessly resume my work without manual window hunting.

**Why this priority**: This is a core workflow interaction. When Claude Code finishes processing, the notification should bring me directly back to the correct terminal. Currently, it fails to focus the correct window, breaking the workflow and requiring manual intervention.

**Independent Test**: Can be fully tested by running Claude Code in a project terminal, waiting for "Claude Code Ready" notification, clicking "Return to Window", and verifying the correct terminal is focused with the correct project active.

**Acceptance Scenarios**:

1. **Given** Claude Code is running in a terminal within project "my-project", **When** Claude Code stops and I click "Return to Window" on the notification, **Then** the system switches to "my-project" (if not already active) and focuses the specific terminal window where Claude Code is running.

2. **Given** I am working on project "other-project" and receive a Claude Code notification from "my-project", **When** I click "Return to Window", **Then** the system first switches to "my-project" context, then focuses the Claude Code terminal window.

3. **Given** I am already in the same project as the Claude Code terminal, **When** I click "Return to Window", **Then** the system focuses the terminal window immediately without unnecessary project switching.

4. **Given** the Claude Code terminal window has been closed since the notification was sent, **When** I click "Return to Window", **Then** the system shows a clear error message indicating the window is no longer available.

5. **Given** Claude Code is running in a tmux session within the terminal, **When** I click "Return to Window", **Then** the correct tmux window is selected after focusing the terminal.

---

### User Story 5 - Cleaner UI Without Workspace Badges and Labels (Priority: P3)

As a user who doesn't use workspace number badges or the PRJ/WS/WIN labels, I want these elements removed to reduce visual noise and make the panel more compact.

**Why this priority**: Removing unused UI elements improves information density and visual clarity. This is lower priority because it's cosmetic rather than functional.

**Independent Test**: Can be fully tested by opening the panel and verifying the specified UI elements are no longer present.

**Acceptance Scenarios**:

1. **Given** the monitoring panel is open, **When** I view any window row, **Then** no workspace number badge (e.g., "WS5") appears next to the window.

2. **Given** the monitoring panel header is visible, **When** I look at the count badges area, **Then** I see only numbers without the "PRJ", "WS", "WIN" text labels.

3. **Given** I have windows across multiple workspaces, **When** I view the panel, **Then** there is no workspace number indicator anywhere in the window listings.

4. **Given** a PWA window exists, **When** I view that window row, **Then** the PWA badge still appears (other badges are unaffected by this change).

---

### Edge Cases

- What happens when attempting to close a window that has already been closed externally? The system should gracefully handle the "window not found" condition without errors.
- What happens if the Sway IPC socket is unavailable during a close operation? The system should display a user-friendly error and not crash.
- What happens if the user toggles debug mode while an environment variable panel is expanded? The panel should collapse gracefully.
- What happens if dynamic resize (if implemented) is used to make the panel extremely narrow or wide? The system should enforce minimum and maximum width bounds.
- What happens if the return-to-window action is clicked but the i3pm daemon is not running? The system should focus the window directly without project switching and show a warning.
- What happens if the project name stored in the notification is no longer valid (project deleted)? The system should still focus the window and show a warning about the failed project switch.

## Requirements *(mandatory)*

### Functional Requirements

**Window Close Actions:**
- **FR-001**: System MUST close all windows belonging to a project when the project-level close action is triggered.
- **FR-002**: System MUST close all windows belonging to a worktree when the worktree-level close action is triggered, regardless of workspace.
- **FR-003**: System MUST close individual windows when the window-row close button is clicked.
- **FR-004**: System MUST handle race conditions when multiple close actions are triggered in rapid succession.
- **FR-005**: System MUST update the panel state to reflect closed windows within 500ms of the close action completing.
- **FR-006**: System MUST provide user feedback (notification or visual indicator) when a batch close operation completes.

**Debug Mode:**
- **FR-007**: System MUST provide a toggle to enable/disable debug mode for the monitoring panel.
- **FR-008**: System MUST hide JSON inspection functionality when debug mode is OFF.
- **FR-009**: System MUST hide environment variable display functionality when debug mode is OFF.
- **FR-010**: System MUST show JSON inspection functionality when debug mode is ON.
- **FR-011**: System MUST show environment variable display functionality when debug mode is ON.
- **FR-012**: Debug mode state MUST persist across panel open/close within a session.

**Panel Width:**
- **FR-013**: System MUST use a reduced default width of approximately one-third narrower than current defaults.
- **FR-014**: System MUST preserve the panel width across panel toggle (close/open) within a session.
- **FR-015**: System SHOULD support dynamic width adjustment via drag (contingent on stable eww implementation).
- **FR-016**: System MUST enforce minimum and maximum width constraints if dynamic resize is implemented.

**UI Cleanup:**
- **FR-017**: System MUST NOT display workspace number badges on window rows.
- **FR-018**: System MUST NOT display "PRJ", "WS", "WIN" text labels in the header count badges area.
- **FR-019**: System MUST preserve other badge types (PWA, notification, git status) unaffected by this change.

**Return-to-Window Notification:**
- **FR-020**: System MUST check current active project before attempting project switch.
- **FR-021**: System MUST only switch projects if the notification's project differs from current active project.
- **FR-022**: System MUST use the same focus logic as the eww monitoring panel's window click action.
- **FR-023**: System MUST focus the terminal window immediately after project switch completes (no arbitrary delays).
- **FR-024**: System MUST verify the window still exists before attempting to focus.
- **FR-025**: System MUST provide clear error feedback if the window no longer exists or project switch fails.
- **FR-026**: System MUST clear the badge file after successfully focusing the window.
- **FR-027**: System MUST select the correct tmux window if the terminal is running in tmux.

### Key Entities

- **Debug Mode State**: Boolean flag indicating whether debug features are visible (persisted per-session in eww state).
- **Panel Width State**: Numeric value representing current panel width in pixels (persisted per-session).
- **Window Close Operation**: Action targeting either a single window, all windows in a project, or all windows in a worktree.
- **Notification Callback State**: Context data (window ID, project name, tmux session/window) passed from stop-notification to callback script.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of window close actions at project, worktree, and individual levels complete successfully without manual intervention required.
- **SC-002**: Zero race condition errors when closing multiple windows in rapid succession (5+ windows in under 1 second).
- **SC-003**: Debug mode toggle updates the UI within 200ms without requiring panel restart.
- **SC-004**: Panel width persists correctly across 10 consecutive toggle off/on cycles within a session.
- **SC-005**: Default panel width is reduced by approximately 33% compared to previous defaults.
- **SC-006**: No workspace number badges or PRJ/WS/WIN labels visible in the panel UI.
- **SC-007**: All acceptance scenarios pass manual testing verification.
- **SC-008**: 100% of "Return to Window" notification actions focus the correct Claude Code terminal window.
- **SC-009**: Project switching during return-to-window completes without arbitrary delays (no hardcoded sleeps).
- **SC-010**: Return-to-window correctly switches projects when notification originates from a different project than currently active.

## Assumptions

- The Sway IPC socket (`swaymsg`) is available and responsive during panel operations.
- The eww daemon is running and can accept state updates via `eww update` commands.
- Current lock file debouncing mechanism in close scripts can be improved or replaced for better reliability.
- Dynamic resize via drag may require eww-specific research to determine feasibility; if unstable, this feature will be deferred to a future iteration.
- Session persistence means persistence while the user's Sway session is active; it does not survive session restarts or logouts.
- The focusWindowScript in eww-monitoring-panel.nix provides the correct, working logic for project-aware window focusing.
- The `active-worktree.json` file is the single source of truth for current active project (Feature 101).
- Claude Code hooks correctly capture the terminal's window ID and project name at the time the notification is generated.
