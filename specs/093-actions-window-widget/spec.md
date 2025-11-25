# Feature Specification: Interactive Monitoring Widget Actions

**Feature Branch**: `093-actions-window-widget`
**Created**: 2025-11-23
**Status**: Draft
**Input**: User description: "add the following interactivity into my eww monitoring widget. the first tab has windows by project, and i want to be able to click on a project to trigger a switch project to the clicked project, and focus on a window by clicking on the window. if clicking on a window not in the same project, it should switch projects and then focus on the window. also, after reviewing our logic, determine if it make sense to focus on the 'workspace' instead of the individual window. review our project to understand the full functionality of our python module that manages windows/workspaces/projects via sway"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Click Window to Focus (Priority: P1)

Users can click on any window in the monitoring panel to immediately switch to and focus that window, regardless of which project it belongs to.

**Why this priority**: This is the core workflow enhancement - users frequently need to jump to specific windows they can see in the monitoring panel. Without this, the panel is view-only and requires manual workspace navigation.

**Independent Test**: Can be fully tested by opening multiple windows across different projects, opening the monitoring panel (Mod+M), clicking on a window not currently focused, and verifying that Sway switches to that window's workspace and project context, then focuses the window.

**Acceptance Scenarios**:

1. **Given** monitoring panel is open with multiple windows visible, **When** user clicks on a window in the same project, **Then** system focuses that window without switching projects
2. **Given** monitoring panel shows windows from multiple projects, **When** user clicks on a window in a different project, **Then** system switches to that project context AND focuses the window
3. **Given** user clicks on a window that's on a different workspace but same project, **When** focus completes, **Then** system switches to the target workspace and focuses the window
4. **Given** user clicks on a hidden/scratchpad window, **When** focus action triggers, **Then** system restores the window from scratchpad and focuses it

---

### User Story 2 - Click Project to Switch Context (Priority: P2)

Users can click on a project name/header in the monitoring panel to switch the entire project context, bringing all scoped windows for that project into view.

**Why this priority**: While less frequent than window-level focus (P1), project switching is a common workflow when users want to change their entire working context. This complements the existing keyboard shortcut (Win+P) with a visual alternative.

**Independent Test**: Can be fully tested by creating multiple projects with scoped windows, opening the monitoring panel, clicking on a different project name, and verifying that i3pm switches project context (hides old scoped windows, shows new scoped windows).

**Acceptance Scenarios**:

1. **Given** user is in project A with multiple scoped windows, **When** user clicks on project B header in panel, **Then** system switches to project B context (scoped windows for A hidden, scoped windows for B restored)
2. **Given** user clicks on the current project name, **When** click completes, **Then** system does nothing (already in that project)
3. **Given** monitoring panel shows project with no scoped windows (global-only), **When** user clicks that project, **Then** system switches to that project (even though no visible window changes occur)

---

### User Story 3 - Visual Feedback for Click Actions (Priority: P3)

Users receive immediate visual feedback when clicking on windows or projects, including hover states, click animations, and error notifications.

**Why this priority**: User experience polish - ensures users know their clicks are registered and provides confidence during the 100-200ms project switching delay. Not critical for MVP functionality but important for production quality.

**Independent Test**: Can be fully tested by hovering over and clicking windows/projects in the monitoring panel, observing CSS hover states, click ripple effects, and watching for success/error notifications via SwayNC.

**Acceptance Scenarios**:

1. **Given** user hovers over a clickable window or project, **When** cursor enters the element, **Then** visual hover state appears (border color change, slight opacity shift)
2. **Given** user clicks on a window, **When** click action is processing, **Then** visual feedback appears (brief highlight or animation)
3. **Given** window focus or project switch fails (e.g., window closed), **When** error occurs, **Then** user sees error notification with specific message
4. **Given** click action completes successfully, **When** focus/switch finishes, **Then** monitoring panel updates to reflect new state within 100ms

---

### Edge Cases

- **What happens when a user clicks on a window that was just closed?** System detects window no longer exists, shows error notification "Window no longer available", and refreshes panel data
- **How does the system handle clicking on a window during an active project switch?** System queues the window focus action until project switch completes, or rejects with "Project switch in progress" notification
- **What if a user rapidly clicks multiple windows?** System debounces click events (300ms) to prevent race conditions, processes only the last click
- **How does clicking interact with the monitoring panel's global scope?** Panel remains visible during focus/switch operations (Feature 085 global scope), only closes if user presses Mod+M or Escape
- **What happens when clicking on a floating window?** System focuses the floating window without changing workspace (floating windows can be focused on any workspace)
- **How does the system handle clicking on a workspace number vs. window title?** The entire window row (including workspace number badge and window title) acts as a single clickable target that focuses the window. Workspace switching happens automatically when Sway focuses the window.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to focus any window by clicking on its row in the monitoring panel "Windows by Project" tab
- **FR-002**: System MUST switch project context when user clicks on a window belonging to a different project
- **FR-003**: System MUST allow users to switch project context by clicking on a project name/header in the monitoring panel
- **FR-004**: System MUST provide visual hover state for all clickable elements (windows, projects, workspaces)
- **FR-005**: System MUST show error notifications when click actions fail (window closed, IPC error, etc.)
- **FR-006**: System MUST debounce rapid clicks to prevent race conditions and duplicate commands
- **FR-007**: System MUST maintain monitoring panel visibility during focus/switch operations (global scope per Feature 085)
- **FR-008**: System MUST update panel data within 100ms after successful focus/switch actions
- **FR-009**: System MUST handle hidden/scratchpad windows by restoring them before focusing
- **FR-010**: System MUST execute window focus commands via Sway IPC (`swaymsg [con_id=X] focus`)
- **FR-011**: System MUST execute project switch commands via i3pm CLI (`i3pm project switch <name>`)
- **FR-012**: System MUST determine whether to focus workspace vs. individual window based on window state and project scope

### Key Entities

- **Clickable Window Row**: Represents a window in the monitoring panel with metadata (window_id, workspace_number, project_name, display_name, is_focused, is_hidden, is_floating)
- **Clickable Project Header**: Represents a project grouping in the monitoring panel with metadata (project_name, display_name, scoped_window_count, is_current_project)
- **Click Action**: Represents a user interaction with outcomes (action_type: focus_window|switch_project, target_id, requires_project_switch, timestamp, success_state)
- **Focus Target**: The subject of a focus action - either a window (con_id) or workspace (number), determined by window state (hidden windows require workspace focus first)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can focus any visible window in under 2 clicks (1 click to open panel, 1 click on window)
- **SC-002**: Window focus actions complete within 300ms for same-project windows
- **SC-003**: Window focus with project switch completes within 500ms (200ms switch + 300ms focus per Feature 091 optimization)
- **SC-004**: Click actions show visual feedback within 50ms (hover state, click animation)
- **SC-005**: System correctly handles 95% of edge cases without crashes (closed windows, rapid clicks, hidden windows)
- **SC-006**: Monitoring panel updates reflect successful actions within 100ms (via deflisten event stream)
- **SC-007**: Users can successfully switch projects in 1 click (vs. current 3-step keyboard workflow: Win+P, type filter, Enter)

## Assumptions

- **Sway IPC Reliability**: Assumes `swaymsg [con_id=X] focus` and workspace focus commands complete reliably (Feature 091 testing validates this)
- **i3pm CLI Availability**: Assumes `i3pm project switch` command is accessible from Eww widget context (bash scripts in Nix can execute system commands)
- **Window ID Stability**: Assumes Sway window IDs (con_id) remain stable during the lifecycle of a window (do not change until window closes)
- **Event-Driven Updates**: Assumes monitoring panel's deflisten mechanism (Feature 085) will automatically refresh data after Sway IPC changes within 100ms
- **Global Panel Scope**: Assumes monitoring panel remains visible across project switches per Feature 085 design (does not auto-hide on switch)
- **Error Handling**: Assumes SwayNC notification system is available for error messages (Feature 090 integration)
- **Click Debouncing**: Assumes 300ms debounce window is sufficient to prevent race conditions based on Feature 091's 200ms project switch performance
- **Focus vs. Workspace Logic**: Assumes hidden/scratchpad windows require workspace focus before window focus, while visible windows can be focused directly (standard Sway behavior)

## Dependencies

- **Feature 085**: Sway Monitoring Widget provides the base panel UI and data streaming infrastructure
- **Feature 091**: Optimized i3pm project switching ensures <200ms switch performance for responsive clicks
- **Feature 090**: SwayNC notification system for error/success feedback
- **Sway IPC**: Window manager commands for focus actions
- **i3pm Daemon**: Project management daemon for project switching and window state queries

## Out of Scope

- **Drag-and-drop window reordering**: Moving windows between workspaces via drag-and-drop in the panel
- **Right-click context menus**: Additional actions like close window, move to workspace, etc.
- **Keyboard navigation within panel**: Arrow keys to select windows (panel already has focus mode per Feature 086, but not item-level navigation)
- **Window thumbnails/previews**: Visual previews of window content on hover
- **Multi-window selection**: Selecting and acting on multiple windows simultaneously
- **Custom click actions**: User-configurable actions beyond focus/switch
- **Analytics/telemetry**: Tracking which windows users click most frequently

## Technical Constraints

- **Eww Widget Framework**: Must use Eww/Yuck syntax for click handlers (`:onclick` properties)
- **Bash Command Execution**: Click handlers execute bash commands in subshells (may require quoting and escaping)
- **IPC Performance**: Focus actions must not block Eww UI thread (commands must run in background with `&`)
- **Panel Update Latency**: Visual updates depend on deflisten stream refresh rate (~100ms per Feature 085)
- **Project Switch Timing**: Cross-project window focus requires waiting for project switch completion (~200ms per Feature 091)
