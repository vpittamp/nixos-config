# Feature Specification: Intelligent Automatic Workspace-to-Monitor Assignment

**Feature Branch**: `049-intelligent-automatic-workspace`
**Created**: 2025-10-29
**Status**: Draft
**Input**: User description: "Intelligent automatic workspace-to-monitor assignment that dynamically redistributes workspaces across active monitors when displays connect or disconnect, with automatic window migration to prevent data loss"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Workspace Distribution on Monitor Changes (Priority: P1)

As a remote developer working on a multi-monitor cloud VM, I want workspaces to automatically redistribute across active monitors when I connect or disconnect VNC displays, so that I never have to manually trigger workspace reassignment or worry about which workspaces are on which monitor.

**Why this priority**: This is the core functionality - without automatic redistribution, users must manually trigger reassignment with Win+Shift+M after every monitor change, creating friction and interrupting workflow. This is the primary pain point.

**Independent Test**: Can be fully tested by connecting 3 VNC clients to a headless Sway VM (ports 5900-5902), verifying workspaces distribute automatically (WS 1-2 on HEADLESS-1, WS 3-5 on HEADLESS-2, WS 6-9 on HEADLESS-3), then disconnecting one VNC client and verifying workspaces immediately redistribute without manual intervention.

**Acceptance Scenarios**:

1. **Given** a Sway VM with 3 active virtual displays (HEADLESS-1, HEADLESS-2, HEADLESS-3), **When** the system starts or a monitor connects, **Then** workspaces automatically distribute across monitors within 1 second (WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary)

2. **Given** 3 active monitors with workspaces distributed, **When** I disconnect the secondary monitor (HEADLESS-2), **Then** workspaces 3-5 automatically move to remaining monitors within 1 second without user intervention

3. **Given** 2 active monitors, **When** I connect a third monitor, **Then** workspaces automatically redistribute to the 3-monitor layout within 1 second

4. **Given** multiple rapid monitor connect/disconnect events within 1 second, **When** monitors stabilize, **Then** only one workspace reassignment occurs after a 500ms debounce delay

5. **Given** 3 monitors with custom workspace assignments (e.g., WS 10-15 in use), **When** a monitor disconnects, **Then** all overflow workspaces (WS 10+) automatically move to active monitors

---

### User Story 2 - Window Preservation During Monitor Changes (Priority: P1)

As a developer with multiple applications open across different monitors, I want all my windows to automatically migrate to active monitors when a display disconnects, so that I never lose access to running applications or data.

**Why this priority**: Equal priority to automatic redistribution because losing access to windows on a disconnected monitor is unacceptable. This prevents data loss and maintains workflow continuity.

**Independent Test**: Can be fully tested by opening windows on all 3 monitors, disconnecting one monitor, and verifying all windows from the disconnected monitor are immediately accessible on remaining monitors at their original workspace numbers.

**Acceptance Scenarios**:

1. **Given** windows open on workspaces 3-5 (HEADLESS-2) and HEADLESS-2 disconnects, **When** workspaces redistribute, **Then** all windows remain on their workspace numbers (WS 3-5) but are now accessible on active monitors

2. **Given** 50 windows spread across 9 workspaces on 3 monitors, **When** 2 monitors disconnect leaving only 1 active, **Then** all 50 windows remain accessible on their original workspace numbers, just displayed on the single active monitor

3. **Given** windows on disconnected monitor, **When** that monitor reconnects, **Then** workspaces redistribute but windows stay on their current workspace numbers (no forced migration back)

4. **Given** a focused window on workspace 5 (HEADLESS-2), **When** HEADLESS-2 disconnects, **Then** the window remains focused and accessible on an active monitor showing workspace 5

---

### User Story 3 - Built-in Smart Distribution Rules (Priority: P2)

As a system administrator, I want the system to use intelligent workspace distribution rules based on monitor count, so that workspaces are optimally distributed without requiring configuration files.

**Why this priority**: Important for usability but not critical for core functionality. Can work with hardcoded distribution rules initially.

**Independent Test**: Can be fully tested by connecting 1, 2, or 3 monitors and verifying distribution follows documented rules without any configuration required.

**Acceptance Scenarios**:

1. **Given** 1 active monitor, **When** system detects monitor count, **Then** all workspaces (1-70) are assigned to the single monitor

2. **Given** 2 active monitors, **When** system detects monitor count, **Then** WS 1-2 go to primary, WS 3-70 go to secondary

3. **Given** 3 active monitors, **When** system detects monitor count, **Then** WS 1-2 go to primary, WS 3-5 go to secondary, WS 6-70 go to tertiary

4. **Given** 4+ active monitors, **When** system detects monitor count, **Then** WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary, WS 10-70 overflow to additional monitors

---

### User Story 4 - State Persistence and Monitor Reconnection (Priority: P3)

As a user who frequently connects and disconnects monitors, I want the system to remember my workspace assignments when monitors reconnect, so that my layout is automatically restored.

**Why this priority**: Nice to have for power users but not essential for basic functionality. Can be added after core automation works.

**Independent Test**: Can be fully tested by disconnecting a monitor, moving workspaces manually, reconnecting the monitor, and verifying the system restores the preferred layout.

**Acceptance Scenarios**:

1. **Given** 3 monitors with default distribution, **When** I manually assign WS 7 to primary monitor and later that monitor disconnects then reconnects, **Then** WS 7 returns to primary monitor (preference remembered)

2. **Given** saved workspace preferences in state file, **When** system starts with monitors in different configuration, **Then** workspaces use fallback roles (primary/secondary/tertiary) until preferred monitors reconnect

3. **Given** monitor state file doesn't exist, **When** system performs first reassignment, **Then** state file is created with current distribution

---

### Edge Cases

- What happens when all monitors disconnect except one? (System moves all workspaces to single remaining monitor, windows remain accessible)
- How does system handle rapid monitor connect/disconnect cycles? (500ms debounce prevents flapping, only final state triggers reassignment)
- What happens to windows on workspace 15 when only 2 monitors are active? (Overflow workspaces go to secondary monitor by default)
- How does system handle monitor reconnecting with different name (e.g., HDMI-1 becomes HDMI-2)? (Uses monitor roles, not names, so works seamlessly)
- What happens when a workspace is manually moved to a different monitor? (Manual moves are preserved until next reassignment event)
- How does system handle monitors with different resolutions? (Workspace assignment is independent of resolution, handles any configuration)
- What happens if window migration fails for a specific window? (Log error, continue migrating other windows, don't block reassignment)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST automatically detect monitor connect and disconnect events via Sway output events
- **FR-002**: System MUST wait 500ms after monitor change before triggering workspace reassignment (debounce)
- **FR-003**: System MUST assign monitor roles (primary, secondary, tertiary) based on output preferences or connection order
- **FR-004**: System MUST calculate workspace distribution based on active monitor count using built-in rules
- **FR-005**: System MUST apply workspace-to-output assignments via Sway IPC commands (workspace number N output OUTPUT_NAME)
- **FR-006**: System MUST detect windows on disconnected monitors before workspace reassignment
- **FR-007**: System MUST move windows from disconnected monitors to active monitors by moving their workspaces to new outputs
- **FR-008**: System MUST preserve workspace numbers during window migration (WS 5 stays WS 5, just on different monitor)
- **FR-009**: System MUST persist monitor state to JSON file after each reassignment
- **FR-010**: System MUST update Sway Config Manager's workspace assignments file with current distribution
- **FR-011**: System MUST work without requiring legacy configuration files
- **FR-012**: System MUST handle overflow workspaces (WS 10-70) by assigning to last available monitor
- **FR-013**: System MUST complete entire reassignment process (detection, migration, assignment, persistence) in under 2 seconds
- **FR-014**: System MUST cancel pending reassignment tasks if new monitor change event occurs during debounce period
- **FR-015**: System MUST log all monitor changes, workspace redistributions, and window migrations for debugging

### Key Entities

- **Monitor State**: Represents current monitor configuration including active monitors, their roles, and timestamp, used for detecting configuration changes and persisting preferences
- **Workspace Distribution**: Maps workspace numbers to monitor roles (primary/secondary/tertiary) based on active monitor count, calculated dynamically from built-in rules
- **Window Migration Record**: Tracks windows that were moved from disconnected monitors including window ID, old output, new output, workspace number, used for logging and diagnostics
- **Reassignment Result**: Contains reassignment outcome including number of workspaces reassigned, windows migrated, duration in milliseconds, used for monitoring and user feedback

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users experience automatic workspace redistribution within 1 second of connecting or disconnecting a monitor, without manual intervention
- **SC-002**: Zero windows are lost or become inaccessible when monitors disconnect - all windows remain accessible on their original workspace numbers
- **SC-003**: System handles 100+ windows across 9 workspaces during monitor changes without performance degradation (reassignment completes in under 2 seconds)
- **SC-004**: Rapid monitor changes (5+ connect/disconnect cycles within 3 seconds) result in only one reassignment after stabilization, preventing system thrashing
- **SC-005**: System works immediately after NixOS installation with zero configuration files required
- **SC-006**: 95% of monitor change events complete reassignment in under 1 second from event detection to final workspace assignment
- **SC-007**: Workspace distribution is predictable and consistent - same monitor count always produces same workspace layout
- **SC-008**: Users can query current monitor configuration and see active workspace assignments within 100ms (diagnostic command)

## Assumptions *(mandatory for AI-generated specs)*

1. **Output Event Reliability**: We assume Sway reliably fires output events when monitors connect/disconnect (standard i3 IPC behavior)
2. **Debounce Duration**: We assume 500ms debounce is sufficient to prevent flapping while being responsive (matches existing i3pm daemon behavior)
3. **Monitor Role Assignment**: We assume monitors are assigned roles in connection order (first connected = primary) unless explicit preferences exist
4. **Workspace Number Preservation**: We assume preserving workspace numbers (vs reassigning windows) is preferred user experience
5. **Legacy Config Removal**: We assume `workspace-monitor-mapping.json` and `MonitorConfigManager` can be completely removed and replaced with simpler built-in logic
6. **State Persistence Location**: We assume `~/.config/sway/monitor-state.json` is appropriate location (matches Sway config patterns)
7. **Sway Config Manager Integration**: We assume updating `workspace-assignments.json` ensures `swaymsg reload` preserves distribution
8. **Window Migration Safety**: We assume moving workspaces (not individual windows) is the correct approach in Sway/i3
9. **Overflow Workspace Handling**: We assume workspaces 10-70 are valid and should go to last available monitor
10. **Single User Context**: We assume single-user Sway session (not multi-user VNC sessions)
11. **No Backwards Compatibility Required**: We assume existing `workspace-monitor-mapping.json` files can be discarded, and `MonitorConfigManager` class can be removed entirely without migration path

## Dependencies

- **External**: Sway 1.5+ (for output events and workspace commands), i3ipc Python library (for async i3 IPC communication)
- **Internal**: i3pm daemon output event handler (handlers.py:1443), workspace_manager.py (for monitor detection), existing debounce infrastructure (handlers.py:1400)
- **Configuration Files**:
  - `~/.config/sway/monitor-state.json` (NEW - created by this feature)
  - `~/.config/sway/workspace-assignments.json` (UPDATED - auto-populated by this feature)
  - `~/.config/i3/workspace-monitor-mapping.json` (DEPRECATED - will be deleted)
- **Code to Remove**:
  - `home-modules/desktop/i3-project-event-daemon/monitor_config_manager.py` (replaced with simpler DynamicWorkspaceManager)
  - All references to `MonitorConfigManager` in handlers.py, workspace_manager.py, ipc_server.py
  - Pydantic models: `WorkspaceMonitorConfig`, `MonitorDistribution`, `ConfigValidationResult` (no longer needed)

## Open Questions (Maximum 3 Clarifications)

None - all critical decisions have reasonable defaults documented in Assumptions section.
