# Feature Specification: Improve Notification Progress Indicators

**Feature Branch**: `117-improve-notification-progress-indicators`
**Created**: 2025-12-14
**Updated**: 2025-12-15
**Status**: Draft
**Input**: User description: "Replace Claude Code hooks with tmux-based process detection that works for both Claude Code and Codex CLI. Temporarily suppress existing hooks and use a unified tmux monitoring approach to detect when AI coding assistants are actively working."

## Scope & Approach

### Design Philosophy

This feature takes a **clean-slate optimization approach**:

- **No backwards compatibility**: Legacy hook-based implementations will be suppressed/replaced entirely
- **Single unified detection**: One tmux-based detection method that works for all AI assistants (Claude Code, Codex CLI)
- **Simplicity over flexibility**: Remove application-specific hooks in favor of universal process monitoring

### What Will Be Replaced

The current implementation relies on Claude Code-specific hooks:

1. **Claude Code UserPromptSubmit hook** → Replaced by tmux process detection for "working" state
2. **Claude Code Stop hook** → Replaced by tmux process detection for "stopped" state (process exits foreground)
3. **Application-specific detection** → Universal approach that detects any configured AI assistant process

### What Will Be Preserved

- **Badge file storage** at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`
- **Badge states**: "working" (pulsating spinner) and "stopped" (bell icon)
- **Desktop notification on completion** with "Return to Window" action
- **Focus-aware badge dismissal**
- **Orphan badge cleanup**
- **EWW monitoring panel integration**

### Non-Goals

- Maintaining fallback to hook-based detection
- Supporting non-tmux terminal sessions for AI assistant detection
- Detecting AI assistants running outside of configured processes

## Clarifications

### Session 2025-12-15

- Q: How should badges be assigned when multiple tmux panes exist in one terminal window? → A: One badge per terminal window (any AI assistant in any pane triggers window-level badge)
- Q: When multiple AI assistants run concurrently in the same terminal window, how should the badge behave? → A: Show "working" if ANY assistant is active; show "stopped" only when ALL exit; source shows last-to-finish

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Universal AI Assistant Progress Detection (Priority: P1)

As a developer using AI coding assistants (Claude Code or Codex CLI) in tmux, I want to see an accurate real-time indicator in the monitoring panel that shows when any supported AI assistant is actively working, so I can switch to other tasks and confidently know when the assistant is done without repeatedly checking my terminal.

**Why this priority**: This is the core value proposition - users need reliable, trustworthy visual feedback that works across different AI tools. A unified detection method eliminates the need for tool-specific integrations and ensures consistent behavior.

**Independent Test**: Can be fully tested by running either Claude Code or Codex CLI in a tmux pane, switching to another window, and verifying the spinner animation starts within 500ms of the AI process becoming foreground and stops within 500ms of the process returning to shell prompt.

**Acceptance Scenarios**:

1. **Given** a tmux pane is at shell prompt, **When** the user runs `claude` command, **Then** the monitoring panel shows a pulsating spinner within 500ms on the corresponding window entry
2. **Given** a tmux pane is at shell prompt, **When** the user runs `codex` command, **Then** the monitoring panel shows a pulsating spinner within 500ms on the corresponding window entry
3. **Given** an AI assistant is running (spinner visible), **When** the assistant exits and returns to shell prompt, **Then** the spinner transitions to a stopped indicator (bell icon) within 500ms
4. **Given** multiple AI assistant sessions running in parallel in different tmux panes, **When** each session changes state independently, **Then** each window shows its own accurate state indicator

---

### User Story 2 - Focus-Aware Notification Dismissal (Priority: P1)

As a developer managing multiple AI assistant sessions, I want the stopped notification indicator to automatically clear when I return my focus to the terminal window, so I don't accumulate stale "awaiting input" badges that clutter my monitoring panel.

**Why this priority**: Stale notifications create visual noise and cognitive load. Users should not need to manually dismiss indicators - focusing on the window is an implicit acknowledgment that they're aware of the state.

**Independent Test**: Can be fully tested by letting an AI assistant complete a task, seeing the bell badge appear, then focusing the terminal window and verifying the badge disappears.

**Acceptance Scenarios**:

1. **Given** a stopped indicator (bell badge) is showing for a window, **When** the user focuses that window, **Then** the badge is removed within 500ms
2. **Given** a stopped indicator is showing and user focuses a different window, **When** the user does not interact with the notified window, **Then** the badge remains visible
3. **Given** a badge was created while the window was already focused, **When** the user briefly switches away and back, **Then** the badge clears (minimum age check prevents immediate dismissal on creation)

---

### User Story 3 - Desktop Notification with Direct Navigation (Priority: P2)

As a developer working on other tasks, I want to receive a desktop notification when an AI assistant completes, with an action button that directly returns me to the correct terminal window and project context, so I can quickly resume my work.

**Why this priority**: Desktop notifications provide cross-desktop visibility that the monitoring panel cannot (when panel is closed or on different workspace). The "Return to Window" action eliminates manual window hunting.

**Independent Test**: Can be fully tested by running an AI assistant task, switching workspaces, waiting for completion notification, clicking the action button, and verifying you arrive at the correct terminal in the correct project.

**Acceptance Scenarios**:

1. **Given** an AI assistant completes a task (process exits foreground), **When** notification is sent, **Then** a desktop notification appears with title "[Assistant Name] Ready" and brief message
2. **Given** a notification is displayed with "Return to Window" action, **When** user clicks the action, **Then** the correct terminal window is focused and project context is switched if needed
3. **Given** user clicks notification action, **When** action executes, **Then** the desktop notification is dismissed and the monitoring panel badge is cleared
4. **Given** user dismisses notification without clicking action, **When** notification is dismissed, **Then** the monitoring panel badge remains until window is focused

---

### User Story 4 - Concise Notification Content (Priority: P2)

As a developer receiving multiple notifications, I want AI assistant notifications to be brief and actionable rather than verbose, so I can quickly scan and decide which session needs my attention without reading lengthy messages.

**Why this priority**: Verbose notifications slow down triage. Users managing multiple sessions need to glance at notifications and quickly identify which one matters, not read paragraphs.

**Independent Test**: Can be fully tested by receiving a notification and verifying the message is 2 lines or less, clearly identifies the assistant type and project/context, and has obvious action to take.

**Acceptance Scenarios**:

1. **Given** an AI assistant completes, **When** notification is sent, **Then** notification body contains only: assistant type and project identifier (not full paths or session details)
2. **Given** Claude Code completes in project "feature-123", **When** notification appears, **Then** title shows "Claude Code Ready" and body shows project name
3. **Given** Codex completes in project "feature-456", **When** notification appears, **Then** title shows "Codex Ready" and body shows project name
4. **Given** AI assistant runs outside any project, **When** notification appears, **Then** notification shows "Awaiting input" without confusing empty project fields

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

### User Story 6 - Suppressed Legacy Hooks (Priority: P3)

As a system maintainer, I want the legacy Claude Code hooks to be temporarily suppressed (not deleted) while the tmux-based detection is in use, so the migration can be easily reverted if issues arise.

**Why this priority**: Ensuring a safe migration path. The hooks are suppressed via configuration, not code deletion, allowing quick rollback.

**Independent Test**: Can be fully tested by verifying that no hook scripts are triggered when submitting prompts to Claude Code, and that the tmux monitor is the sole source of badge state changes.

**Acceptance Scenarios**:

1. **Given** tmux detection is enabled, **When** Claude Code UserPromptSubmit would trigger, **Then** the legacy hook is not executed
2. **Given** tmux detection is enabled, **When** Claude Code Stop would trigger, **Then** the legacy hook is not executed
3. **Given** an administrator wants to revert, **When** the suppression is disabled, **Then** legacy hooks resume functioning immediately

---

### Edge Cases

- What happens when AI assistant is run outside tmux? (No indicator shown - tmux is required for detection)
- What happens when the tmux monitor service fails? (System degrades gracefully - no indicators, no crash)
- What happens when user rapidly starts/stops AI assistants? (Badge state updates on each process change; only one badge per window)
- What happens when notification action is clicked but window was already closed? (Brief error notification shown: "Terminal unavailable")
- What happens when terminal is closed while AI assistant is working? (Badge cleaned up on next validation cycle)
- What happens during system restart? (Clean slate - no stale badges persist across sessions)
- What happens when a non-configured process is run? (Ignored - only processes matching configured list trigger badges)
- What happens when multiple AI assistants run in different panes of the same window? (Badge shows "working" while ANY is active; transitions to "stopped" only when ALL exit; source identifier reflects the last assistant to finish)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect when a configured AI assistant process (claude, codex) becomes the foreground process in a tmux pane
- **FR-002**: System MUST display a pulsating visual indicator when a configured AI assistant is the foreground process
- **FR-003**: System MUST transition the indicator from "working" to "stopped" state when the AI assistant exits foreground (returns to shell)
- **FR-004**: System MUST remove badge when user focuses the associated window (focus-aware dismissal)
- **FR-005**: System MUST support multiple simultaneous AI assistant sessions with independent state tracking per terminal window (one badge per Sway window, regardless of number of tmux panes)
- **FR-006**: System MUST send desktop notification when AI assistant exits foreground
- **FR-007**: System MUST provide "Return to Window" action in notifications that focuses the correct terminal
- **FR-008**: System MUST clear both desktop notification and panel badge when action is clicked
- **FR-009**: System MUST validate badges against active windows and remove orphaned badges
- **FR-010**: Notification title MUST identify which AI assistant completed (e.g., "Claude Code Ready", "Codex Ready")
- **FR-011**: Notification content MUST be concise (assistant type + project name only)
- **FR-012**: System MUST handle monitor service failures gracefully (no crash, degrade to no indicator)
- **FR-013**: Badge state MUST use file-based persistence at `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`
- **FR-014**: System MUST prevent badges from being dismissed immediately if window was already focused when badge was created (minimum age requirement)
- **FR-015**: System MUST suppress legacy Claude Code hooks while tmux detection is active
- **FR-016**: System MUST support configuration of which processes trigger AI assistant detection
- **FR-017**: Detection polling interval MUST be configurable with a default of 300ms

### Supported AI Assistants

The system will detect the following processes as AI assistants:

| Process Name | Notification Title | Source Identifier |
|-------------|-------------------|-------------------|
| `claude`    | Claude Code Ready | claude-code       |
| `codex`     | Codex Ready       | codex             |

Additional processes can be added via configuration.

### Key Entities

- **Badge**: Visual notification indicator with properties: window_id, state (working/stopped), source (claude-code/codex), timestamp, count
- **Window**: Sway container with unique ID, tracked for focus events and existence validation
- **Monitored Process**: A process name (e.g., "claude", "codex") that triggers badge creation when detected as foreground in tmux
- **Tmux Pane**: A terminal session within tmux that can be queried for its foreground process
- **Notification**: Desktop notification with action buttons, linked to specific window context

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Progress indicator state changes reflect actual AI assistant state within 500ms
- **SC-002**: Detection works for both Claude Code and Codex CLI without application-specific hooks
- **SC-003**: Badges are automatically cleared within 500ms of user focusing the associated window
- **SC-004**: Orphaned badges for closed windows are removed within 30 seconds
- **SC-005**: Notification action successfully navigates to correct window 95% of attempts (allowing for edge case window closure)
- **SC-006**: Users can identify which AI assistant completed from notification title
- **SC-007**: Zero stale badges remain after 5 minutes of normal usage with multiple AI assistant sessions
- **SC-008**: System continues functioning (degraded mode) when monitor service is unavailable
- **SC-009**: Legacy Claude Code hooks produce no side effects while suppressed

## Assumptions

- Users run AI assistants (Claude Code, Codex) inside tmux sessions
- Terminal emulator (Ghostty) is the parent process of tmux client
- Sway window manager provides reliable window ID and focus event APIs
- tmux provides reliable pane foreground process information via `#{pane_current_command}`
- AI assistant process names are stable and identifiable (claude, codex)
- 300ms polling interval provides acceptable responsiveness without excessive CPU usage
