# Feature Specification: Improve Notification Progress Indicators

**Feature Branch**: `117-improve-notification-progress-indicators`
**Created**: 2025-12-14
**Status**: Draft
**Input**: User description: "Review and improve the Claude Code notification system in the EWW monitoring widget, including timing synchronization, stale notification cleanup, multi-process handling, and optimal user experience"

## Scope & Approach

### Design Philosophy

This feature takes a **clean-slate optimization approach**:

- **No backwards compatibility**: Legacy implementations will be replaced entirely, not preserved
- **Single optimal path**: Only the best-performing approach will be implemented; redundant/fallback code paths will be removed
- **Simplicity over flexibility**: Remove configuration options and code branches that add complexity without clear user value

### What Will Be Replaced

The current implementation has accumulated complexity from iterative development. This feature will consolidate and simplify:

1. **Dual notification channels** → Single unified notification flow (monitoring panel badge + optional desktop notification)
2. **File-based + IPC badge updates** → Single source of truth with optimal latency
3. **Multiple window ID detection methods** → Single reliable detection method
4. **Polling + inotify hybrid detection** → Single detection mechanism based on reliability analysis

### Non-Goals

- Maintaining fallback code paths for edge cases that can be solved properly
- Supporting configurations or environments that aren't actively used
- Preserving existing behavior that conflicts with optimal user experience

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-Time Progress Visibility (Priority: P1)

As a developer using Claude Code in a terminal, I want to see an accurate real-time indicator in the monitoring panel that shows when Claude Code is actively working, so I can switch to other tasks and confidently know when Claude is done without repeatedly checking my terminal.

**Why this priority**: This is the core value proposition - users need reliable, trustworthy visual feedback. If the indicator is out of sync with actual Claude Code state, the entire notification system loses credibility and usefulness.

**Independent Test**: Can be fully tested by running a Claude Code command, switching to another window, and verifying the spinner animation starts within 600ms of submitting a prompt and stops within 600ms of Claude completing its response.

**Acceptance Scenarios**:

1. **Given** Claude Code is idle in a terminal window, **When** the user submits a prompt, **Then** the monitoring panel shows a pulsating spinner within 600ms on the corresponding window entry
2. **Given** Claude Code is working (spinner visible), **When** Claude completes processing and awaits input, **Then** the spinner transitions to a stopped indicator (bell icon) within 600ms
3. **Given** the user is focused on the Claude Code terminal, **When** Claude Code is working, **Then** the spinner is dimmed (reduced opacity) to indicate the user already has attention on that window
4. **Given** multiple Claude Code sessions running in parallel, **When** each session changes state independently, **Then** each window shows its own accurate state indicator

---

### User Story 2 - Focus-Aware Notification Dismissal (Priority: P1)

As a developer managing multiple Claude Code sessions, I want the stopped notification indicator to automatically clear when I return my focus to the terminal window, so I don't accumulate stale "awaiting input" badges that clutter my monitoring panel.

**Why this priority**: Stale notifications create visual noise and cognitive load. Users should not need to manually dismiss indicators - focusing on the window is an implicit acknowledgment that they're aware of the state.

**Independent Test**: Can be fully tested by letting Claude Code complete a task, seeing the bell badge appear, then focusing the terminal window and verifying the badge disappears.

**Acceptance Scenarios**:

1. **Given** a stopped indicator (bell badge) is showing for a window, **When** the user focuses that window, **Then** the badge is removed within 500ms
2. **Given** a stopped indicator is showing and user focuses a different window, **When** the user does not interact with the notified window, **Then** the badge remains visible
3. **Given** a badge was created while the window was already focused, **When** the user briefly switches away and back, **Then** the badge clears (minimum age check prevents immediate dismissal on creation)

---

### User Story 3 - Desktop Notification with Direct Navigation (Priority: P2)

As a developer working on other tasks, I want to receive a desktop notification when Claude Code completes, with an action button that directly returns me to the correct terminal window and project context, so I can quickly resume my work.

**Why this priority**: Desktop notifications provide cross-desktop visibility that the monitoring panel cannot (when panel is closed or on different workspace). The "Return to Window" action eliminates manual window hunting.

**Independent Test**: Can be fully tested by running a Claude Code task, switching workspaces, waiting for completion notification, clicking the action button, and verifying you arrive at the correct terminal in the correct project.

**Acceptance Scenarios**:

1. **Given** Claude Code completes a task, **When** notification is sent, **Then** a desktop notification appears with title "Claude Code Ready" and brief message
2. **Given** a notification is displayed with "Return to Window" action, **When** user clicks the action, **Then** the correct terminal window is focused and project context is switched if needed
3. **Given** user clicks notification action, **When** action executes, **Then** the desktop notification is dismissed and the monitoring panel badge is cleared
4. **Given** user dismisses notification without clicking action, **When** notification is dismissed, **Then** the monitoring panel badge remains until window is focused

---

### User Story 4 - Concise Notification Content (Priority: P2)

As a developer receiving multiple notifications, I want Claude Code notifications to be brief and actionable rather than verbose, so I can quickly scan and decide which session needs my attention without reading lengthy messages.

**Why this priority**: Verbose notifications slow down triage. Users managing multiple sessions need to glance at notifications and quickly identify which one matters, not read paragraphs.

**Independent Test**: Can be fully tested by receiving a notification and verifying the message is 2 lines or less, clearly identifies the project/context, and has obvious action to take.

**Acceptance Scenarios**:

1. **Given** Claude Code completes, **When** notification is sent, **Then** notification body contains only: status and project identifier (not full paths or session details)
2. **Given** Claude Code runs in project "feature-123", **When** notification appears, **Then** project name is visible in notification
3. **Given** Claude Code runs outside any project, **When** notification appears, **Then** notification shows "Awaiting input" without confusing empty project fields

---

### User Story 5 - Stale Badge Cleanup (Priority: P3)

As a user whose terminal windows may close unexpectedly or whose sessions may end without proper cleanup, I want orphaned badges to be automatically removed, so the monitoring panel remains accurate and doesn't show badges for windows that no longer exist.

**Why this priority**: While not blocking core functionality, orphaned badges erode trust in the system. Automatic cleanup ensures long-running sessions don't accumulate garbage.

**Independent Test**: Can be fully tested by closing a terminal window that has a badge, and verifying the badge is removed from the monitoring panel within the cleanup interval.

**Acceptance Scenarios**:

1. **Given** a badge exists for window ID 12345, **When** window 12345 is closed/destroyed, **Then** the badge is removed on the next cleanup cycle (within 30 seconds)
2. **Given** badges exist for windows on a workspace, **When** monitoring data is refreshed, **Then** badges are validated against the current Sway window tree
3. **Given** the badge file is older than the TTL threshold, **When** cleanup runs, **Then** the stale badge file is removed even if window exists (recovery from stuck states)

---

### Edge Cases

- What happens when Claude Code hook script fails? (System degrades gracefully - no indicator shown, no crash)
- What happens when user rapidly submits multiple prompts? (Badge state updates to "working" on each submit; only one badge per window)
- What happens when notification action is clicked but window was already closed? (Brief error notification shown: "Terminal unavailable")
- What happens when terminal is closed while Claude is working? (Badge cleaned up on next validation cycle)
- What happens during system restart? (Clean slate - no stale badges persist across sessions)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a pulsating visual indicator when Claude Code is actively processing
- **FR-002**: System MUST transition the indicator from "working" to "stopped" state when Claude Code completes
- **FR-003**: System MUST remove badge when user focuses the associated window (focus-aware dismissal)
- **FR-004**: System MUST support multiple simultaneous Claude Code sessions with independent state tracking
- **FR-005**: System MUST send desktop notification when Claude Code completes and awaits input
- **FR-006**: System MUST provide "Return to Window" action in notifications that focuses the correct terminal
- **FR-007**: System MUST clear both desktop notification and panel badge when action is clicked
- **FR-008**: System MUST validate badges against active windows and remove orphaned badges
- **FR-009**: Notification content MUST be concise (summary + project name only, not verbose output)
- **FR-010**: System MUST handle hook script failures gracefully (no crash, degrade to no indicator)
- **FR-011**: Badge state MUST use a single persistence mechanism (no dual file+IPC approach)
- **FR-012**: System MUST prevent badges from being dismissed immediately if window was already focused when badge was created (minimum age requirement)
- **FR-013**: Implementation MUST remove legacy/redundant code paths that are replaced by the optimized approach
- **FR-014**: Window ID detection MUST use a single reliable method (no fallback chains)

### Key Entities

- **Badge**: Visual notification indicator with properties: window_id, state (working/stopped), source, timestamp, count
- **Window**: Sway container with unique ID, tracked for focus events and existence validation
- **Hook Event**: Claude Code lifecycle events (UserPromptSubmit, Stop) that trigger badge state changes
- **Notification**: Desktop notification with action buttons, linked to specific window context

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Progress indicator state changes reflect actual Claude Code state within 600ms
- **SC-002**: Badges are automatically cleared within 500ms of user focusing the associated window
- **SC-003**: Orphaned badges for closed windows are removed within 30 seconds
- **SC-004**: Notification action successfully navigates to correct window 95% of attempts (allowing for edge case window closure)
- **SC-005**: Users can identify which Claude Code session completed from notification content without opening monitoring panel
- **SC-006**: Zero stale badges remain after 5 minutes of normal usage with multiple Claude Code sessions
- **SC-007**: System continues functioning (degraded mode) when daemon is unavailable
