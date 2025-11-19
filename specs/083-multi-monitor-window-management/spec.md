# Feature Specification: Multi-Monitor Window Management Enhancements

**Feature Branch**: `083-multi-monitor-window-management`
**Created**: 2025-11-19
**Status**: Draft
**Input**: Monitor profile system enhancements for event-driven integration, real-time top bar state, and reliability improvements

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-Time Monitor State Feedback (Priority: P1)

When a user switches monitor profiles, they need immediate visual feedback in the top bar showing the new monitor configuration without any perceptible delay.

**Why this priority**: The 2-second polling delay creates confusion about whether the profile switch succeeded. Users may retry the action or assume failure, degrading trust in the system. Immediate feedback is fundamental to usability.

**Independent Test**: Can be fully tested by switching profiles via Mod4+Control+m and observing that the top bar updates within 100ms, delivering immediate confidence that the action succeeded.

**Acceptance Scenarios**:

1. **Given** user is viewing the top bar with current monitor state (e.g., H1 active), **When** user switches to dual profile, **Then** the top bar displays H1 and H2 as active within 100ms of the profile switch completing
2. **Given** user switches from triple to single profile, **When** the profile switch completes, **Then** only H1 shows as active in the top bar, and H2/H3 indicators disappear or show as inactive within 100ms
3. **Given** the i3-project-event-daemon receives a monitor output event from Sway, **When** the event indicates an output was enabled or disabled, **Then** the daemon publishes the new state to Eww immediately without waiting for file system changes

---

### User Story 2 - Monitor Profile Name Display (Priority: P2)

Users need to see which monitor profile is currently active in the top bar, so they know their current configuration at a glance without needing to open a menu.

**Why this priority**: Knowing the current profile name provides context for workspace distribution and helps users remember which layout they selected. This builds on P1 by adding semantic meaning to the visual indicators.

**Independent Test**: Can be fully tested by switching between profiles and verifying the profile name (e.g., "single", "dual", "triple") appears in a designated top bar area.

**Acceptance Scenarios**:

1. **Given** user has selected the "triple" monitor profile, **When** they look at the top bar, **Then** the text "triple" (or similar identifier) is displayed alongside or near the monitor indicators
2. **Given** user switches from "dual" to "single" profile, **When** the switch completes, **Then** the profile name in the top bar updates from "dual" to "single" within 100ms
3. **Given** user creates a custom profile named "presentation", **When** they select it, **Then** the profile name "presentation" appears in the top bar

---

### User Story 3 - Atomic Profile Switching (Priority: P2)

When a user switches monitor profiles, the system must perform all state changes atomically to prevent race conditions where workspaces are reassigned multiple times or end up on disabled monitors.

**Why this priority**: Race conditions cause unpredictable workspace placement, breaking user expectations. This is critical for reliability but ranks behind visual feedback since users can work around race conditions but cannot work around lack of feedback.

**Independent Test**: Can be fully tested by rapidly switching profiles and verifying workspaces end up on correct monitors without duplicates or misplacements.

**Acceptance Scenarios**:

1. **Given** user is on triple profile with workspaces distributed across H1/H2/H3, **When** user switches to single profile, **Then** all workspaces move to H1 in a single coordinated operation without intermediate reassignments
2. **Given** profile switch involves enabling H2 and disabling H3, **When** the operation completes, **Then** workspaces from H3 are redistributed only once to remaining monitors (H1 and H2)
3. **Given** user rapidly switches profiles (within 500ms), **When** both switches complete, **Then** the final state reflects only the last profile selection with no artifacts from the intermediate state

---

### User Story 4 - Daemon-Owned State Management (Priority: P3)

The system should consolidate state management so that the i3-project-event-daemon owns all workspace-to-monitor assignments, eliminating duplicate logic in shell scripts.

**Why this priority**: Simplification improves maintainability and reduces bugs, but does not directly impact user experience. This is technical debt cleanup that enables future enhancements.

**Independent Test**: Can be fully tested by triggering profile switches and verifying the daemon writes output-states.json rather than the shell script.

**Acceptance Scenarios**:

1. **Given** user selects a new monitor profile via the menu, **When** the profile is applied, **Then** the daemon receives a profile change notification and updates output-states.json itself
2. **Given** the set-monitor-profile script is invoked, **When** it completes Sway output commands, **Then** it notifies the daemon to update state rather than writing output-states.json directly
3. **Given** the daemon is restarted while a profile is active, **When** it initializes, **Then** it reads the current profile from monitor-profile.current and applies the correct workspace assignments without requiring the shell script to run again

---

### Edge Cases

- **Failed output enable**: System performs full revert to previous profile state and notifies user of failure
- **Active VNC connections**: System immediately stops WayVNC service on monitors being disabled, disconnecting any active users
- What happens if monitor-profile.current references a profile that no longer exists (was deleted)?
- How does the system behave if the daemon is not running when a profile switch is requested?
- What happens when profile switch is interrupted (e.g., system suspend during switch)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST update the top bar monitor indicators within 100ms of a monitor output state change
- **FR-002**: System MUST display the current active profile name in the top bar
- **FR-003**: System MUST use event-driven communication between profile switches and the top bar (no polling for monitor state)
- **FR-004**: System MUST perform profile switches atomically, preventing workspace reassignment until all output changes are complete
- **FR-005**: System MUST allow the daemon to own output-states.json updates, removing this responsibility from shell scripts
- **FR-006**: System MUST prevent duplicate workspace reassignments when multiple events fire from a single profile switch
- **FR-007**: System MUST persist profile selection to survive reboots (current behavior to maintain)
- **FR-008**: System MUST gracefully handle missing or invalid profile references by falling back to a default profile
- **FR-009**: System MUST notify users of profile switch failures within 1 second via notification system
- **FR-010**: System MUST coordinate WayVNC service management (start/stop) as part of atomic profile switching
- **FR-011**: System MUST perform full revert to previous profile state when any output fails to enable during profile switch
- **FR-012**: System MUST emit structured events with timestamps for each profile switch phase (start, output changes, workspace reassignment, complete/failed)

### Key Entities

- **Monitor Profile**: Named configuration defining which headless outputs to enable, their positions, and workspace allocation metadata
- **Output State**: Runtime state of each headless output (enabled/disabled, connected VNC sessions)
- **Profile Event**: Notification from script to daemon indicating profile change request or completion
- **Workspace Assignment**: Mapping of workspace numbers to monitor roles (primary/secondary/tertiary)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Top bar reflects actual monitor state within 100ms of any output change (down from 2000ms polling)
- **SC-002**: Profile name appears in top bar and updates within 100ms of profile switch
- **SC-003**: Zero duplicate workspace reassignments during profile switches (verified by event logs)
- **SC-004**: Profile switch completes end-to-end in under 500ms for typical configurations
- **SC-005**: 100% of profile switches result in correct workspace distribution without manual intervention
- **SC-006**: System recovers gracefully from 100% of error scenarios (missing profile, failed output, interrupted switch) within 2 seconds
- **SC-007**: Daemon owns all state file writes with zero state management code in shell scripts (excluding Sway IPC commands)

## Clarifications

### Session 2025-11-19

- Q: What should happen when a profile switch fails (e.g., headless output fails to enable)? → A: Full revert: Roll back to previous profile state and notify user
- Q: What observability signals should be captured for profile switch operations? → A: Structured events: Log each phase with timestamps (start, output changes, complete)
- Q: How should the system handle active VNC connections on monitors being disabled? → A: Immediate disconnect: Stop WayVNC service immediately, disconnecting users

## Assumptions

- The system is running on Hetzner with headless outputs (HEADLESS-1, HEADLESS-2, HEADLESS-3)
- Eww supports receiving real-time updates via IPC or socket communication from the daemon
- The i3-project-event-daemon can subscribe to Sway output events
- Users will primarily switch profiles via the Mod4+Control+m keybinding or CLI
- WayVNC services are managed via systemd user units
- The existing monitor-profile.current and output-states.json file locations remain unchanged
- Profile JSON files follow the existing schema with outputs array and metadata
