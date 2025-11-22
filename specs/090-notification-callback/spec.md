# Feature Specification: Enhanced Notification Callback for Claude Code

**Feature Branch**: `090-notification-callback`
**Created**: 2025-11-22
**Status**: Draft
**Input**: User description: "enhance our notification mechanism and claude-code hook to allow for a callback to the application/terminal/pane that generated the notification. review @scripts/claude-hooks/ and @home-modules/ai-assistants/claude-code.nix; we want the notification to provide some type of action that when clicked or (via keypress) returns the user to the originating terminal. the use case is that claude-code has a long running task, and we notify the user when its done and they need to enter a new prompt; we can assume we return to another project, and we want the notifcation come through, and then when i click/keypress that should return to the project/terminal/pane with the correct focus. assume we always run claude code within the 'terminal' application with workpace 1, which uses ghostty, and sesh (tmux)"

## User Scenarios & Testing

### User Story 1 - Cross-Project Return to Claude Code Terminal (Priority: P1)

**Context**: User starts a long-running Claude Code task (e.g., complex refactoring, test suite execution) in project A (e.g., nixos-090-notification-callback). While Claude Code works, user switches to project B (e.g., nixos-089-cleanup) to continue other work. When Claude Code finishes and requires input, user receives a notification while focused on project B.

**User Journey**:
1. User is working in project A (nixos-090) with Claude Code running in terminal on workspace 1
2. User starts a long-running task in Claude Code (e.g., "analyze all Python files and suggest improvements")
3. While Claude Code works, user switches to project B (nixos-089) to review code
4. User works in project B for several minutes, now on workspace 5
5. Claude Code completes the task and sends notification: "Claude Code Ready - Task complete, awaiting your input"
6. Notification appears with action buttons: "🖥️ Return to Window" and "Dismiss"
7. User clicks "Return to Window" (or presses keyboard shortcut)
8. System automatically:
   - Switches from project B back to project A
   - Focuses workspace 1 (where terminal lives)
   - Focuses the Ghostty terminal window
   - Selects the correct tmux window/pane where Claude Code is running
9. User can immediately type next prompt without manual navigation

**Why this priority**: This is the core value proposition - eliminating manual context switching overhead when Claude Code requires input. Without this, users must manually remember which project, workspace, and tmux pane Claude Code was running in, which breaks flow state.

**Independent Test**: Can be fully tested by starting Claude Code in one project, switching to another project (different workspace), triggering a Claude Code stop event, and verifying the notification action returns to the exact terminal pane. Delivers immediate value by reducing 10-15 seconds of manual navigation to <1 second automated return.

**Acceptance Scenarios**:

1. **Given** Claude Code is running in project A workspace 1 terminal with tmux session "nixos-090", **When** user switches to project B workspace 5 and Claude Code finishes task, **Then** notification shows "Return to Window" action with source info "nixos-090:0"

2. **Given** notification is displayed with "Return to Window" action, **When** user clicks the action button, **Then** system switches to project A, focuses workspace 1, focuses terminal window, and selects tmux window 0

3. **Given** notification is displayed with "Return to Window" action, **When** user presses Ctrl+R keyboard shortcut, **Then** same focus behavior occurs as clicking the button

4. **Given** user has switched projects multiple times since starting Claude Code task, **When** notification action is triggered, **Then** system still correctly identifies and focuses the original terminal window regardless of current context

---

### User Story 2 - Same-Project Terminal Focus (Priority: P2)

**Context**: User starts Claude Code task but doesn't switch projects. Instead, user opens other applications (browser, editor) in different workspaces within the same project. When Claude Code finishes, user needs quick return to terminal.

**User Journey**:
1. User is in project A with Claude Code running in terminal on workspace 1
2. User starts task: "review all test files and suggest improvements"
3. Without switching projects, user opens VS Code on workspace 2 to review code
4. User opens Firefox on workspace 3 to check documentation
5. Claude Code finishes and sends notification
6. User clicks "Return to Window" action
7. System focuses workspace 1 and the terminal window (project already active)
8. User can immediately interact with Claude Code

**Why this priority**: Handles the simpler case of same-project navigation. While less complex than cross-project switching, this is still a common scenario and validates the core window-focus mechanism works before tackling project switching logic.

**Independent Test**: Can be tested by staying in one project, opening multiple workspaces with different apps, then verifying notification action focuses the correct terminal workspace. Demonstrates value even without project-switching complexity.

**Acceptance Scenarios**:

1. **Given** Claude Code running in workspace 1 and user viewing workspace 3 in same project, **When** notification action is triggered, **Then** workspace 1 is focused and terminal receives input focus

2. **Given** terminal window is hidden/minimized on workspace 1, **When** notification action is triggered, **Then** window is restored and brought to foreground before focusing

3. **Given** multiple terminal windows exist on workspace 1, **When** notification action is triggered, **Then** the specific terminal window running Claude Code receives focus (not other terminals)

---

### User Story 3 - Notification Dismissal Without Action (Priority: P3)

**Context**: User receives Claude Code notification but wants to defer returning to the task. User should be able to dismiss notification without triggering focus action.

**User Journey**:
1. User receives "Claude Code Ready" notification with action buttons
2. User is in the middle of critical work in current project
3. User clicks "Dismiss" button (or presses Escape key)
4. Notification disappears without changing window focus or project context
5. User continues current work
6. Later, user manually switches back to Claude Code project when ready

**Why this priority**: Provides user control over workflow interruption. Not all notifications require immediate action - user should have option to acknowledge and defer.

**Independent Test**: Can be tested by triggering notification and verifying Dismiss action removes notification without any focus changes. Demonstrates system respects user's decision to stay in current context.

**Acceptance Scenarios**:

1. **Given** notification is displayed with "Return to Window" and "Dismiss" actions, **When** user clicks "Dismiss", **Then** notification disappears and focus remains on current workspace/window

2. **Given** notification is displayed, **When** user presses Escape key, **Then** notification is dismissed without focus change

3. **Given** notification was dismissed without action, **When** user later manually navigates to Claude Code terminal, **Then** Claude Code is still waiting for input (dismissal didn't affect state)

---

### User Story 4 - Notification Content Clarity (Priority: P4)

**Context**: User receives notification but needs to understand what task completed before deciding whether to return immediately or defer.

**User Journey**:
1. Claude Code completes task and sends notification
2. Notification displays:
   - Title: "Claude Code Ready"
   - Message preview: First 80 characters of last assistant message
   - Activity summary: "📊 Activity: 5 bash, 3 edits, 2 writes"
   - Modified files: "📝 Modified: config.nix, flake.nix"
   - Working directory: "📁 nixos-090-notification-callback"
   - Source: "nixos-090:0" (tmux session:window)
3. User reads notification content and decides whether to return immediately based on:
   - What task was completed (from message preview)
   - What files were changed (impact assessment)
   - Which project/session it came from (context verification)

**Why this priority**: Contextual information helps user make informed decision about when to return to Claude Code. Without this, all notifications look identical and user can't prioritize which tasks to address first.

**Independent Test**: Can be tested by running various Claude Code tasks (different tool usage, file modifications) and verifying notification content accurately reflects the completed work. Demonstrates value through improved user decision-making.

**Acceptance Scenarios**:

1. **Given** Claude Code used multiple tools in last task, **When** notification is sent, **Then** activity summary shows accurate count of bash/edit/write/read operations

2. **Given** Claude Code modified 5 files, **When** notification is sent, **Then** notification shows up to 3 most recently modified files (prevents overwhelming UI)

3. **Given** Claude Code is running in tmux session "my-project" window 2, **When** notification is sent, **Then** source info displays as "my-project:2"

4. **Given** last assistant message is 300 characters long, **When** notification is sent, **Then** message is truncated to 80 characters with "..." suffix

---

### Edge Cases

- **What happens when terminal window is closed before notification action is triggered?**
  - System should detect window no longer exists and show error notification: "Claude Code terminal no longer available"
  - Alternatively, gracefully fail silently (no focus change occurs)

- **What happens when tmux session is killed before notification action is triggered?**
  - System should detect session no longer exists via `tmux has-session` check
  - Fall back to focusing terminal window only (without tmux window selection)
  - User lands in terminal but may need to manually recreate session

- **What happens when multiple Claude Code instances are running in different terminals?**
  - Each instance sends notifications with unique window IDs
  - Each notification action focuses the specific terminal window that sent it
  - Window ID correlation ensures correct terminal is focused (no ambiguity)

- **What happens when user clicks "Return to Window" action multiple times rapidly?**
  - First click triggers focus action and marks notification as handled
  - Subsequent clicks should be idempotent (no unintended side effects)
  - SwayNC's transient flag ensures notification auto-dismisses after first action

- **What happens when notification is sent but SwayNC is not running?**
  - System should fall back to standard notify-send (without actions)
  - Or display terminal bell / visual indicator in terminal itself
  - Hook should not fail or block Claude Code execution

- **What happens when user is on a different monitor and notification appears?**
  - Notification appears on current monitor (standard SwayNC behavior)
  - Clicking action switches to workspace/monitor where terminal lives
  - Focus action is monitor-aware (leverages existing i3pm monitor assignment)

- **What happens when Claude Code is running in global mode (not project-scoped)?**
  - Notification still contains terminal window ID and tmux info
  - Focus action works identically (focuses terminal workspace 1)
  - No project switching occurs (already in global context)

## Requirements

### Functional Requirements

- **FR-001**: System MUST capture terminal window ID, tmux session name, and tmux window index when Claude Code stop hook is triggered

- **FR-002**: System MUST send desktop notification with at least two action buttons: "Return to Window" and "Dismiss"

- **FR-003**: System MUST include contextual information in notification body: message preview (max 80 chars), activity summary (tool counts), modified files (up to 3), working directory name, and tmux source location

- **FR-004**: Notification "Return to Window" action MUST focus the terminal window using Sway IPC (swaymsg con_id focus)

- **FR-005**: Notification "Return to Window" action MUST select the correct tmux window using tmux select-window command (if tmux session exists)

- **FR-006**: Notification "Return to Window" action MUST switch to the correct i3pm project context (if Claude Code was running in project-scoped mode)

- **FR-007**: Notification "Dismiss" action MUST remove notification without changing window focus or project context

- **FR-008**: System MUST handle missing terminal window gracefully (window closed after task started but before notification action triggered)

- **FR-009**: System MUST handle missing tmux session gracefully (session killed before notification action triggered) by falling back to terminal-only focus

- **FR-010**: Notification handler MUST run in background (non-blocking) so Claude Code hook returns immediately (<100ms)

- **FR-011**: System MUST support custom keyboard shortcuts for notification actions: Ctrl+R for "Return to Window" action, Escape for "Dismiss" action (configured in SwayNC)

- **FR-012**: System MUST persist notification until user takes action (not auto-dismiss after timeout)

### Key Entities

- **Terminal Window**: The Ghostty terminal instance running Claude Code
  - Attributes: Sway window ID (con_id), process PID, workspace number (typically 1)
  - Relationships: Belongs to exactly one workspace, contains zero or more tmux sessions

- **Tmux Session**: The tmux session context where Claude Code commands execute
  - Attributes: Session name (e.g., "nixos-090"), window index (e.g., 0), pane ID
  - Relationships: Runs inside terminal window, maps to i3pm project name

- **Notification**: Desktop notification sent when Claude Code stops
  - Attributes: Title, body (message + context), action buttons (Return/Dismiss), source info (session:window)
  - Relationships: References specific terminal window and tmux session

- **Project Context**: i3pm project that was active when Claude Code task started
  - Attributes: Project name (e.g., "nixos-090"), associated workspaces (1-50), scoped applications
  - Relationships: May contain terminal window running Claude Code

## Success Criteria

### Measurable Outcomes

- **SC-001**: User can return to Claude Code terminal from any workspace or project in under 2 seconds by clicking notification action (vs. 10-15 seconds manual navigation)

- **SC-002**: Notification action correctly focuses the exact terminal window and tmux pane in 100% of cases when window/session still exist

- **SC-003**: Notification action gracefully handles missing terminal window or tmux session without errors or crashes in 100% of edge cases

- **SC-004**: Notification hook completes execution and returns control to Claude Code in under 100 milliseconds (non-blocking background handler)

- **SC-005**: Notification displays accurate contextual information (message preview, activity summary, modified files, source location) in 95% of cases

- **SC-006**: User can dismiss notification without unintended focus changes in 100% of cases

- **SC-007**: System supports cross-project navigation (return from project B to Claude Code in project A) in 100% of project-switching scenarios

### User Experience Goals

- **UX-001**: User never needs to manually remember which project, workspace, or tmux pane Claude Code is running in

- **UX-002**: Notification provides enough context for user to decide whether to return immediately or defer without additional investigation

- **UX-003**: Notification actions are discoverable (clearly labeled buttons) and accessible (support keyboard shortcuts)

- **UX-004**: System respects user's workflow interruption preferences (non-intrusive notifications that can be easily dismissed)

## Assumptions

- **A-001**: Claude Code always runs in "terminal" application (Ghostty) on workspace 1
- **A-002**: Terminal always uses tmux session manager (sesh wrapper around tmux)
- **A-003**: SwayNC is installed and running as notification daemon (supports action buttons)
- **A-004**: i3pm project system is active and tracking current project context
- **A-005**: Sway window manager is used (swaymsg commands available for focus control)
- **A-006**: User has configured Claude Code hooks in home-manager configuration (hooks.Stop enabled)
- **A-007**: Custom keyboard shortcuts configured in SwayNC: Ctrl+R for "Return to Window", Escape for "Dismiss"
- **A-008**: Notification auto-dismisses after user clicks action button (SwayNC transient flag behavior)
- **A-009**: Terminal window PID can be reliably detected via GHOSTTY_RESOURCES_DIR environment variable or shell parent process inspection
- **A-010**: Multiple Claude Code instances in different terminals are supported (each has unique window ID)

## Dependencies

- **D-001**: SwayNC notification daemon (0.10+) with action button support
- **D-002**: Sway window manager (1.8+) with IPC support (swaymsg)
- **D-003**: i3pm project management system (for cross-project switching)
- **D-004**: Ghostty terminal emulator (with GHOSTTY_RESOURCES_DIR env var)
- **D-005**: tmux/sesh session manager (for pane-level focus)
- **D-006**: jq command-line JSON processor (for parsing hook input and Sway tree)
- **D-007**: Existing Claude Code hook infrastructure (hooks.Stop configuration in home-manager)

## Constraints

- **C-001**: Notification handler must not block Claude Code execution (background process with immediate exit)
- **C-002**: Notification content limited to 80 characters for message preview (keep notifications readable)
- **C-003**: File modification list limited to 3 most recent files (prevent notification overflow)
- **C-004**: Focus action must complete within 2 seconds (includes project switch + workspace focus + terminal focus + tmux select)
- **C-005**: Solution must work with existing notification system (cannot break terminal bell or other notification channels)
- **C-006**: Must preserve backward compatibility with existing stop-notification.sh script structure (hooks already deployed)
