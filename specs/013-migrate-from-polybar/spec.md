# Feature Specification: Migrate from Polybar to i3 Native Status Bar

**Feature Branch**: `013-migrate-from-polybar`
**Created**: 2025-10-19
**Status**: Draft
**Input**: User description: "migrate from polybar to i3 native status bar for reliable workspace display"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Active Workspaces (Priority: P1)

As a window manager user, I need to see which workspaces are currently active and which workspace I'm currently on, so I can navigate between different workspaces and understand my current context.

**Why this priority**: This is the core functionality that is currently broken with polybar. Without visible workspace indicators, users cannot effectively use the multi-workspace system.

**Independent Test**: Can be fully tested by opening the system, verifying that workspace indicators are visible on each monitor's status bar, and switching between workspaces to confirm the active workspace is highlighted.

**Acceptance Scenarios**:

1. **Given** the system has just started, **When** I look at the status bar, **Then** I see indicators for all workspaces with the current workspace visually distinguished
2. **Given** I am on workspace 1, **When** I switch to workspace 2, **Then** the status bar updates to show workspace 2 as active
3. **Given** I have 3 monitors with different workspace assignments, **When** I look at each monitor's status bar, **Then** each shows the workspaces assigned to that monitor

---

### User Story 2 - View System Information (Priority: P2)

As a system administrator, I need to see system information like CPU usage, memory usage, network status, and date/time in the status bar, so I can monitor system health without opening additional tools.

**Why this priority**: While important for monitoring, users can still work effectively without this information. It's a quality-of-life feature that comes after core workspace functionality.

**Independent Test**: Can be fully tested by viewing the status bar and confirming that system metrics update in real-time (e.g., watching CPU percentage change during load).

**Acceptance Scenarios**:

1. **Given** the system is running, **When** I look at the status bar, **Then** I see current CPU usage, memory usage, network status, and date/time
2. **Given** the system metrics are displayed, **When** system load changes, **Then** the status bar updates to reflect new values within 5 seconds
3. **Given** network connectivity changes, **When** I disconnect or reconnect, **Then** the network status indicator updates accordingly

---

### User Story 3 - View Project Context Indicator (Priority: P3)

As a developer using project-scoped workspaces, I want to see the currently active project name in the status bar, so I know which project context I'm working in without checking manually.

**Why this priority**: This is a nice-to-have enhancement to the existing project system. Users can still check their current project using the CLI command, so this is convenience rather than necessity.

**Independent Test**: Can be fully tested by switching between projects and verifying the status bar updates to show the correct project name.

**Acceptance Scenarios**:

1. **Given** I have activated a project, **When** I look at the status bar, **Then** I see the project name or icon displayed
2. **Given** I am in global mode (no active project), **When** I look at the status bar, **Then** I see a generic indicator or no project indicator
3. **Given** I switch from one project to another, **When** the switch completes, **Then** the status bar updates to show the new project name

---

### Edge Cases

- What happens when no workspaces are active? (System should always have at least one workspace)
- How does the status bar handle monitor connect/disconnect events? (Should automatically appear on new monitors)
- What happens if the status bar process crashes? (i3 should automatically restart it)
- How does the system handle workspace names that are very long? (Should truncate or abbreviate)
- What happens when system information is temporarily unavailable? (Should show placeholder or last known value)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display all workspace indicators on each monitor's status bar
- **FR-002**: System MUST visually distinguish the currently active workspace from inactive workspaces
- **FR-003**: System MUST update workspace indicators immediately when the user switches workspaces
- **FR-004**: System MUST show workspaces assigned to each specific monitor when multi-monitor workspace pinning is enabled
- **FR-005**: System MUST display system information including CPU usage, memory usage, network status, and date/time
- **FR-006**: System MUST update system information at regular intervals (no longer than 5 seconds)
- **FR-007**: Status bar MUST automatically appear on all connected monitors
- **FR-008**: Status bar MUST survive system configuration rebuilds without requiring manual restart
- **FR-009**: Status bar MUST integrate with the existing i3 window manager configuration without conflicts
- **FR-010**: System MUST support displaying the active project name from the project workspace management system
- **FR-011**: Status bar MUST use consistent visual theming with the rest of the desktop environment (Catppuccin color scheme)
- **FR-012**: System MUST remove all polybar configuration and processes to avoid conflicts
- **FR-013**: Status bar MUST use native i3 workspace state via i3 IPC (GET_WORKSPACES) to ensure workspace indicators are always in sync
- **FR-014**: System MUST subscribe to i3 workspace events via IPC to receive real-time workspace state changes
- **FR-015**: Status bar MUST use native i3 bar configuration (bar {} block) integrated into i3 config
- **FR-016**: Project indicator MUST integrate with i3's status command protocol to display project context alongside system information

### Key Entities

- **Workspace**: Represents a virtual desktop, has a name/number, an assignment to a specific monitor, and an active/inactive state
- **Monitor**: Physical or virtual display output, has workspaces assigned to it, displays its own status bar
- **Status Bar**: Visual component showing workspace indicators and system information, exists per-monitor
- **Project Context**: Currently active project (optional), has a name and display icon, shown in status bar when active
- **System Metrics**: Real-time system information including CPU percentage, memory percentage, network connectivity status, current date and time

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can immediately see which workspaces are available and which one is currently active on all monitors
- **SC-002**: Workspace indicator updates occur within 100 milliseconds of workspace switch
- **SC-003**: Status bar appears on all monitors within 2 seconds of system startup
- **SC-004**: Status bar survives system configuration rebuilds 100% of the time without requiring manual intervention
- **SC-005**: System information updates reflect changes within 5 seconds
- **SC-006**: Zero polybar processes remain running after migration
- **SC-007**: Users report being able to navigate workspaces effectively (qualitative measure via testing)
- **SC-008**: Status bar configuration requires fewer lines of code than previous polybar configuration
- **SC-009**: Status bar continues functioning after monitor connect/disconnect events

## Assumptions *(mandatory)*

- The i3 window manager is already installed and configured
- The system uses NixOS with home-manager for declarative configuration
- The Catppuccin Mocha color scheme is the desired theme
- The system uses i3status or i3blocks as the status command (standard for i3bar)
- Multi-monitor support is required (system has 3 monitors in current setup)
- The project workspace management system is already implemented and provides project context via state file (~/.config/i3/active-project)
- Users expect a status bar at the bottom of each screen (current polybar position)
- i3bar will use the native i3 IPC protocol to query and subscribe to workspace state
- i3bar's built-in workspace buttons will be used rather than external modules
- The bar configuration will be embedded in the i3 config file (declaratively managed via home-manager)
- Project context will be read by the status command and formatted according to i3bar protocol

## Out of Scope

- Implementing entirely new status bar features not present in the current polybar setup
- Changing the window manager from i3 to something else
- Advanced status bar customizations requiring third-party tools beyond i3status/i3blocks
- Tray icon support (i3bar has limited tray support compared to polybar)
- Custom graphical widgets or animations
- Mouse gesture support beyond basic click actions

## Dependencies

- i3 window manager (already installed)
- i3status or i3blocks (standard NixOS packages)
- NixOS home-manager module system
- Project workspace management system state (for project indicator)

## Technical Integration Points

### Native i3 Integration

The status bar will leverage i3's native capabilities for maximum reliability:

1. **Workspace State Synchronization**
   - i3bar automatically queries workspace state via i3 IPC GET_WORKSPACES message
   - i3bar subscribes to workspace events to receive real-time updates (focus, init, empty, rename, urgent, move)
   - No external polling or state management required - i3 maintains the single source of truth

2. **Bar Configuration Integration**
   - Bar configuration lives in the i3 config file as a `bar {}` block
   - i3 manages the bar lifecycle (starts, restarts, and monitors the bar process)
   - Bar configuration can be queried via GET_BAR_CONFIG IPC message
   - Changes to bar config trigger barconfig_update events

3. **Multi-Monitor Support**
   - i3bar automatically creates one bar instance per output (monitor)
   - Workspace-to-output assignments from i3 config determine which workspaces appear on which bar
   - Monitor connect/disconnect events handled natively by i3

4. **Workspace Display Properties**
   - i3 provides workspace properties: num, name, visible, focused, urgent, rect, output
   - i3bar's workspace buttons automatically reflect these states with appropriate visual styling
   - Workspace buttons respond to mouse clicks (left-click to switch, scroll to cycle)

### Project Context Integration

The project indicator will integrate with i3's status command protocol:

1. **Status Command Protocol**
   - Status commands output JSON or plain text to stdout
   - i3bar reads this output and displays it in the status section
   - Protocol supports blocks with color, text, and formatting

2. **Project State Reading**
   - Status command (i3status/i3blocks) will read project context from state file
   - State file: `~/.config/i3/active-project` (JSON format from project management system)
   - Project name/icon formatted as a status block

3. **Update Mechanism**
   - i3blocks supports event-based updates via signals
   - When project switches, project management system can send SIGRTMIN+N to i3blocks
   - i3blocks re-runs the project indicator script to fetch new state

## Risks & Mitigations

**Risk**: i3bar may not support all the customization features currently used in polybar
**Mitigation**: Audit current polybar features and identify which are essential vs. nice-to-have. Focus on essential features (workspace display, system info) first.

**Risk**: Project indicator may require custom scripting with i3blocks
**Mitigation**: Treat project indicator as P3 priority. If it proves complex, defer to a future enhancement.

**Risk**: Color scheme may not translate perfectly to i3bar configuration format
**Mitigation**: Use standard Catppuccin color values and test on actual monitors before finalizing.

**Risk**: Users may prefer polybar's appearance and resist the change
**Mitigation**: Focus on reliability and functionality over aesthetics. Ensure the new solution works consistently.
