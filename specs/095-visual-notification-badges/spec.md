# Feature Specification: Visual Notification Badges in Monitoring Panel

**Feature Branch**: `095-visual-notification-badges`
**Created**: 2025-11-24
**Status**: Draft
**Input**: User description: "i want to explore a fantastic user experience for showing nofitications within our window view for our termals where we use claude code and p. the idea is that we would use claude-codee hooks to genrated a notification (or something cimilar) and add a visual indicator (perhaps a badge) on the window item in the eww widget to notify the user that they should return to that window, because theyire attention is needed to enter a prompt or respond to an llm message."

## Clarifications

### Session 2025-11-24

- Q: Should badges clear on *any* focus event, or only when the window remains focused for a minimum duration? → A: Clear immediately on any focus - Badge disappears as soon as window receives focus, even if user switches away 1 second later (simpler, matches FR-003 literal reading)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visual Badge on Window Awaiting Input (Priority: P1)

**Context**: User starts a long-running Claude Code task in a terminal window, then switches to another project or workspace. When Claude Code finishes and needs input, user needs an immediate visual cue in the monitoring panel to identify which window requires attention, without relying solely on desktop notifications which may be missed or dismissed.

**User Journey**:
1. User is working in project A with Claude Code running in terminal on workspace 1
2. User starts a long-running task: "analyze the entire codebase and suggest refactoring opportunities"
3. User switches to project B to work on unrelated tasks (workspace 5)
4. User opens the monitoring panel (Mod+M) to check system state
5. Claude Code finishes task and requires input while user is still in project B
6. Monitoring panel automatically shows a visual badge (notification bell icon with count) on the terminal window item in the Windows tab
7. Badge is immediately visible without needing to search through window list
8. User clicks on the badged window item in monitoring panel
9. System focuses the terminal window, switches to project A if needed, and the badge disappears
10. User can immediately provide input to Claude Code

**Why this priority**: This is the core value - providing persistent, in-context visual feedback within the window management interface users already use. Desktop notifications can be dismissed or missed, but badges in the monitoring panel remain visible until addressed. This eliminates the cognitive overhead of remembering "which terminal was running Claude Code?"

**Independent Test**: Can be fully tested by triggering a Claude Code stop hook, verifying badge appears on correct window item in monitoring panel, clicking the window item, and confirming badge clears when window is focused. Delivers immediate value by making waiting notifications discoverable within the existing workflow UI.

**Acceptance Scenarios**:

1. **Given** Claude Code is running in terminal window on workspace 1, **When** Claude Code hook fires stop event, **Then** terminal window item in monitoring panel displays notification badge (bell icon with "1")

2. **Given** window item has notification badge, **When** user clicks the window item in monitoring panel, **Then** system focuses the terminal window and badge disappears

3. **Given** multiple windows have notification badges, **When** user views monitoring panel, **Then** each badged window shows individual notification count without visual clutter

4. **Given** user focuses a badged window manually (not via monitoring panel), **When** window receives focus, **Then** badge immediately clears regardless of how long window remains focused

5. **Given** window with notification badge is closed, **When** window closes, **Then** badge state is cleaned up and no errors occur

---

### User Story 2 - Badge Persistence Across Panel Toggles (Priority: P2)

**Context**: User may toggle the monitoring panel on/off multiple times while working. Notification badges should persist across panel visibility changes and survive system restarts until the window is focused.

**User Journey**:
1. Claude Code sends stop notification, badge appears on terminal window in monitoring panel
2. User closes monitoring panel (Mod+M) to focus on current work
3. User works for 10 minutes without opening monitoring panel
4. User reopens monitoring panel (Mod+M)
5. Badge is still visible on the terminal window item
6. User focuses the terminal window via monitoring panel click
7. Badge clears

**Why this priority**: Ensures reliability of notification badges - they must persist reliably until addressed, not disappear due to UI state changes. This builds trust that badges are a reliable reminder system.

**Independent Test**: Can be tested by generating badge, closing/reopening panel multiple times, verifying badge persists, then clearing by focusing window. Demonstrates badge state management is robust.

**Acceptance Scenarios**:

1. **Given** window has notification badge and monitoring panel is open, **When** user closes panel (Mod+M), **Then** badge state is preserved in daemon memory

2. **Given** monitoring panel was closed with badged windows, **When** user reopens panel, **Then** all badges are restored correctly on window items

3. **Given** system restarts with badged windows open, **When** monitoring panel opens after restart, **Then** badge state is lost (acceptable degradation - no persistent storage required)

---

### User Story 3 - Badge Integration with Project Switching (Priority: P3)

**Context**: When user switches projects using i3pm, windows from inactive projects are hidden to scratchpad. Badged windows in hidden projects should still be discoverable in the monitoring panel to remind user of pending tasks.

**User Journey**:
1. User is in project A with Claude Code running
2. Claude Code sends notification, badge appears
3. User switches to project B (project A windows hidden to scratchpad)
4. User opens monitoring panel and switches to Projects tab
5. Project A entry shows notification indicator (badge count)
6. User clicks project A in monitoring panel
7. System switches to project A, focuses terminal window, badge clears

**Why this priority**: Extends badge visibility to project-level aggregation. Users managing multiple projects need to see "Project X has notifications" without drilling into window lists. This is lower priority because User Story 1 already solves discoverability within the Windows tab.

**Independent Test**: Can be tested by creating badge in project A, switching to project B, verifying project A shows aggregated badge count in Projects tab, and confirming switching to project A focuses the badged window.

**Acceptance Scenarios**:

1. **Given** project A has 2 windows with notification badges, **When** user views Projects tab in monitoring panel, **Then** project A entry shows aggregate count "2"

2. **Given** project has badged windows but project is inactive (scratchpad), **When** user clicks project entry in Projects tab, **Then** system switches to project and focuses first badged window

3. **Given** all badged windows in a project are addressed, **When** last badge clears, **Then** project-level notification indicator disappears

---

### User Story 4 - Multi-Notification Badge Count (Priority: P4)

**Context**: A terminal window may accumulate multiple notifications if user is away for extended period. Badge should show count of pending notifications rather than just a binary "has notification" indicator.

**User Journey**:
1. User starts Claude Code task in terminal window
2. Task completes, badge shows "1"
3. User is away from desk for 15 minutes
4. User returns and starts another Claude Code task in same terminal (without clearing first badge)
5. Second task completes
6. Badge now shows "2"
7. User focuses window, both notifications are considered addressed, badge clears

**Why this priority**: Provides richer context about notification volume. However, this is lower priority because the primary value is "this window needs attention" (binary), not "this window has N notifications" (count). Most use cases will have count=1.

**Independent Test**: Can be tested by triggering multiple notification events on same window without focusing, verifying count increments, then focusing and verifying count clears.

**Acceptance Scenarios**:

1. **Given** window has notification badge count of 1, **When** another notification event fires for same window, **Then** badge count increments to 2

2. **Given** window has badge count of 5, **When** user focuses window, **Then** badge clears completely (all notifications considered addressed)

3. **Given** badge count exceeds 9, **When** monitoring panel renders badge, **Then** badge shows "9+" to prevent visual overflow

---

### Edge Cases

- **What happens when** a badged window is closed?
  → Badge state is removed from daemon memory immediately, no cleanup errors, badge doesn't reappear on new windows

- **What happens when** monitoring panel daemon restarts while badges are active?
  → Badges are lost (acceptable degradation - in-memory state only, no persistence)

- **What happens when** user focuses a badged window via method other than monitoring panel (e.g., Alt+Tab, Sway focus commands)?
  → Badge clears immediately via focus event listener, ensuring consistency

- **What happens when** user briefly focuses a badged window (e.g., quick Alt+Tab preview for 1 second) then switches away?
  → Badge clears immediately on first focus event and does not reappear, even if user did not interact with window (simple, predictable behavior)

- **What happens when** Claude Code hook fires while window is already focused?
  → No badge appears (window already has user's attention), notification acts as transient desktop alert only

- **What happens when** multiple terminals are running Claude Code simultaneously in different projects?
  → Each terminal window gets independent badge, user can see all pending tasks at a glance in monitoring panel

- **What happens when** badge state conflicts with actual window state (e.g., window focused but badge still showing due to race condition)?
  → Badge clears on next focus event or monitoring panel refresh, self-correcting behavior

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a visual badge (notification bell icon with count) on window items in monitoring panel when notification event is triggered by Claude Code hook
- **FR-002**: System MUST store badge state in daemon memory, associating badge count with window ID
- **FR-003**: System MUST immediately clear badge when associated window receives focus via any method (monitoring panel click, keyboard focus, Sway IPC focus command), regardless of focus duration
- **FR-004**: System MUST update monitoring panel UI in real-time (<100ms) when badge state changes
- **FR-005**: Badge count MUST increment when multiple notifications occur on same window without intervening focus
- **FR-006**: System MUST clean up badge state when window is closed, preventing orphaned badges
- **FR-007**: System MUST persist badge state across monitoring panel visibility toggles (hide/show panel)
- **FR-008**: Badge icon MUST be visually distinct from existing window state indicators (floating, hidden, focused, PWA)
- **FR-009**: System MUST support badge display for any terminal window (Ghostty, Alacritty, etc.), not just Claude Code-specific terminals
- **FR-010**: Badge state MUST survive project switches (windows hidden to scratchpad retain badge state)
- **FR-011**: System MUST provide mechanism for external processes (Claude Code hooks, other notification sources) to trigger badge creation via IPC or file-based signaling
- **FR-012**: Projects tab MUST show aggregated badge count for projects containing badged windows
- **FR-013**: Badge display MUST be optional - users can disable badge feature without breaking monitoring panel functionality

### Key Entities *(include if feature involves data)*

- **WindowBadge**: Represents notification badge state for a single window
  - Window ID (integer): Sway window container ID
  - Badge count (integer): Number of pending notifications (1-9+)
  - Timestamp (float): Unix timestamp when badge was created
  - Source type (string): Notification source ("claude-code", "generic", etc.)

- **BadgeState**: Daemon-level badge state manager
  - Window badges (map): Window ID → WindowBadge mapping
  - Project badges (map): Project name → aggregated badge count
  - Last sync timestamp (float): When state was last synced with Eww

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify which window requires attention in under 2 seconds by viewing monitoring panel (measured via user testing)
- **SC-002**: Badge appears on correct window item within 100ms of Claude Code hook firing (measured via timestamp logging)
- **SC-003**: Badge clears within 100ms of window receiving focus (measured via focus event to UI update latency)
- **SC-004**: Badge state survives 100% of panel hide/show cycles during 30-minute work session (measured via integration testing)
- **SC-005**: Badge system handles 20+ concurrent badged windows without UI performance degradation (<100ms update latency maintained)
- **SC-006**: Users report 80%+ reduction in "which terminal was that?" confusion when using badges vs. desktop notifications alone (measured via user survey)
- **SC-007**: Zero badge state leaks occur - closing badged window always cleans up state (measured via memory profiling over 24-hour daemon session)
- **SC-008**: Badge appearance is visually discoverable - 90%+ of users notice badge on first glance at monitoring panel (measured via user testing)

## Assumptions *(mandatory)*

1. **Notification Source**: Claude Code hooks are the primary notification source, but design should support other terminal notification sources (build completion, test failures, etc.)

2. **Window Identification**: Sway window IDs remain stable during window lifetime - window ID is sufficient to track badge association

3. **Focus Detection**: Sway IPC focus events are reliable and fire consistently when window receives focus via any method

4. **Monitoring Panel Usage**: Users regularly check monitoring panel as part of workflow - badges only provide value if panel is viewed

5. **Project Switching**: i3pm daemon provides reliable project state and window-to-project mapping for project-level badge aggregation

6. **Desktop Notifications**: Feature 090 desktop notifications will continue to exist - badges complement (not replace) desktop notifications for immediate alerts

7. **Single User Environment**: Badge state is per-user, no multi-user badge sharing considerations needed

8. **Terminal Applications**: Claude Code and similar tools run in terminal emulators (Ghostty, Alacritty) that have Sway window IDs, not terminal multiplexer sessions without windows

## Out of Scope *(mandatory)*

1. **Persistent Badge Storage**: Badge state is in-memory only, does not survive daemon restarts or system reboots
   - Rationale: Added complexity for minimal value - notifications requiring attention will be re-triggered or user will remember

2. **Badge Priority/Severity Levels**: All badges are equal priority, no visual distinction between urgent vs. normal notifications
   - Rationale: Terminal notifications are typically action-required (input needed), not hierarchical priority system

3. **Badge Customization**: Badge color, icon, position are fixed, no user customization options in MVP
   - Rationale: Adds complexity, can be deferred to future enhancement if users request customization

4. **Badge Dismissal Without Focus**: No "clear badge without focusing window" action
   - Rationale: Badge clearing should require user to address the notification by viewing the window, preventing accidental dismissals

5. **Badge Sound/Animation**: Badges are purely visual, no audio alerts or animations on badge appearance
   - Rationale: Desktop notifications (Feature 090) already provide audio/visual alerts, badges are secondary persistent reminder

6. **Badge Filtering**: No ability to filter/hide badges from specific sources or windows
   - Rationale: Feature is opt-in at source (hook level), not UI level - unwanted notifications should be disabled at source

7. **Historical Badge Log**: No log of past badges or notification history
   - Rationale: Monitoring panel is real-time state viewer, not historical log viewer - logs belong in system journal

8. **Mobile/Remote Badge Access**: Badges only visible in local monitoring panel, no remote notification system
   - Rationale: Monitoring panel is local Eww UI, remote access is separate concern (VNC, etc.)

## Dependencies *(mandatory)*

1. **Feature 085 (Monitoring Panel)**: Requires Eww monitoring panel with real-time window list display
   - Impact: Badge UI must integrate with existing window item rendering in Windows tab

2. **Feature 090 (Notification Callbacks)**: Claude Code hooks already send desktop notifications with action callbacks
   - Impact: Badge system extends notification hooks to also update badge state, can reuse notification metadata

3. **i3pm Daemon**: Requires i3pm event daemon for IPC communication and window state tracking
   - Impact: Badge state manager must integrate with existing daemon, use daemon's window focus event listeners

4. **Sway IPC**: Requires stable Sway window IDs and focus events
   - Impact: Badge clearing relies on Sway focus events firing reliably for all focus methods

5. **Eww Real-Time Updates**: Requires Eww `deflisten` or `eww update` mechanism for <100ms badge UI updates
   - Impact: Badge state changes must push to Eww immediately, not wait for polling cycle

## Technical Constraints

1. **In-Memory State Only**: Badge state stored in daemon memory, no persistent storage (database, JSON files)
   - Reason: Simplifies implementation, avoids file I/O latency, acceptable data loss on daemon restart

2. **Sway Window ID as Key**: Badge state keyed by Sway window ID (integer), not PID or terminal session ID
   - Reason: Window IDs are stable and unique within Sway session, direct mapping to monitoring panel display

3. **Single Badge Icon**: One badge design for all notification types, no per-source icon customization
   - Reason: Visual consistency, reduces UI complexity, future enhancement if needed

4. **100ms Update Latency Target**: Badge appearance/clearing must complete within 100ms to feel instantaneous
   - Reason: Matches Feature 085 real-time update latency target, ensures responsive UX

5. **No Badge Polling**: Badge state updates must be event-driven (focus events, notification hooks), not polling loops
   - Reason: Polling wastes CPU, event-driven architecture already established in Feature 085

6. **Eww Widget Compatibility**: Badge UI must work within existing Eww window-item widget structure
   - Reason: Avoid breaking existing monitoring panel layout, minimize CSS/widget refactoring

## Privacy & Security

1. **No Sensitive Data in Badges**: Badge state contains only window ID, count, timestamp - no message content or user data
   - Reason: Prevents accidental exposure of Claude Code prompts/responses in badge metadata

2. **Local-Only State**: Badge state lives in local daemon memory, never transmitted over network
   - Reason: No remote access requirements, local-only monitoring panel

3. **Notification Source Validation**: Badge creation IPC endpoint should validate source (e.g., requires user's UID)
   - Reason: Prevent arbitrary processes from creating fake badges on user's windows
