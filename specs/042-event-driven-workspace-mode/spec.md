# Feature Specification: Event-Driven Workspace Mode Navigation

**Feature Branch**: `042-event-driven-workspace-mode`
**Created**: 2025-10-31
**Status**: Draft
**Input**: User description: "Migrate workspace mode from bash script to event-driven Python architecture integrated with i3pm daemon. Use native Sway binding_mode_indicator where possible, fully integrated into Python architecture."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fast Digit-Based Workspace Navigation (Priority: P1)

As a user working across multiple workspaces, I want to quickly navigate to any workspace by typing its number, so I can switch between contexts without memorizing dozens of keybindings.

**Why this priority**: This is the core value proposition - replacing slow bash script spawning (70ms) with fast daemon-based processing (15ms) for immediate workspace switching.

**Independent Test**: Can be fully tested by pressing CapsLock (M1) or Ctrl+0 (Hetzner), typing digits "23", pressing Enter, and verifying workspace 23 is focused. Delivers immediate value even without status bar integration or history tracking.

**Acceptance Scenarios**:

1. **Given** I'm on workspace 1, **When** I press CapsLock, type "5", and press Enter, **Then** I switch to workspace 5 in under 20ms
2. **Given** I'm on workspace 2, **When** I press CapsLock, type "2", "3", and press Enter, **Then** I switch to workspace 23 with correct output focusing
3. **Given** I'm in goto_workspace mode with "1" accumulated, **When** I press Escape, **Then** mode exits without switching and state resets
4. **Given** I type "0" as first digit, **When** I type "5", **Then** accumulated state shows "5" not "05"
5. **Given** I'm on workspace 3, **When** I enter workspace mode and press Enter without typing digits, **Then** mode exits without action

---

### User Story 2 - Move Windows to Workspaces (Priority: P1)

As a user organizing my workspace layout, I want to quickly move the focused window to any workspace by typing its number, so I can reorganize without multiple keybinding sequences.

**Why this priority**: Equal importance to goto mode - users need both navigation and window management. Same performance improvement (bash → daemon).

**Independent Test**: Can be tested by focusing a window, pressing Shift+CapsLock, typing "7", pressing Enter, and verifying window moved to workspace 7 and user followed it there.

**Acceptance Scenarios**:

1. **Given** I have Firefox focused on workspace 1, **When** I press Shift+CapsLock, type "3", press Enter, **Then** Firefox moves to workspace 3 and I'm switched to workspace 3
2. **Given** I'm in move_workspace mode with digits accumulated, **When** I press Escape, **Then** mode exits, window stays on current workspace
3. **Given** I have a floating window focused, **When** I move it via workspace mode to workspace 8, **Then** it retains floating state and geometry

---

### User Story 3 - Real-Time Visual Feedback (Priority: P2)

As a user typing workspace digits, I want to see what I've typed so far in my status bar, so I have immediate confirmation of my input without external notifications.

**Why this priority**: Improves usability significantly but not blocking for core navigation. Can use fallback (notify-send) temporarily.

**Independent Test**: Can be tested by entering workspace mode, typing "1", "2", and observing status bar shows "WS: 12" before pressing Enter. Delivers value independently of navigation performance.

**Acceptance Scenarios**:

1. **Given** I enter goto_workspace mode, **When** I type "2", **Then** status bar shows "WS: 2" within 10ms
2. **Given** I have "1" accumulated, **When** I type "5", **Then** status bar updates to show "WS: 15"
3. **Given** I'm in move_workspace mode with "23" accumulated, **When** I press Escape, **Then** status bar clears workspace mode indicator
4. **Given** I complete a workspace switch, **When** mode exits, **Then** status bar returns to showing project/system info

---

### User Story 4 - Workspace Navigation History (Priority: P3)

As a user who frequently switches between several workspaces, I want the system to track my workspace navigation history, so I can analyze patterns and potentially add "jump to recent" shortcuts in the future.

**Why this priority**: Nice-to-have for future enhancements (recent workspace shortcuts, analytics), but not required for core functionality.

**Independent Test**: Can be tested by performing several workspace switches, then querying `i3pm workspace-mode history` and verifying last 100 switches are recorded with timestamps and output assignments.

**Acceptance Scenarios**:

1. **Given** I perform 5 workspace switches, **When** I check history via CLI, **Then** I see all 5 switches with timestamps, workspace numbers, and outputs
2. **Given** history contains 100 entries, **When** I perform another switch, **Then** oldest entry is removed (circular buffer)
3. **Given** daemon restarts, **When** I check history, **Then** history is empty (in-memory only)

---

### User Story 5 - Smart Output Focusing (Priority: P1)

As a user with multiple monitors, I want the system to automatically focus the correct monitor when I switch workspaces, so I don't need to manually focus outputs after switching.

**Why this priority**: Critical for multi-monitor workflows - without this, workspace mode is significantly degraded. This is already working in bash version, must be preserved.

**Independent Test**: Can be tested on Hetzner (3 monitors) by switching to workspace 1 (PRIMARY), workspace 4 (SECONDARY), workspace 7 (TERTIARY) and verifying correct output is focused each time.

**Acceptance Scenarios**:

1. **Given** I have 3 monitors (Hetzner), **When** I switch to workspace 1 or 2, **Then** PRIMARY output is focused
2. **Given** I have 3 monitors, **When** I switch to workspace 3, 4, or 5, **Then** SECONDARY output is focused
3. **Given** I have 3 monitors, **When** I switch to workspace 6+, **Then** TERTIARY output is focused
4. **Given** I have 1 monitor (M1 without external), **When** I switch to any workspace, **Then** eDP-1 output is focused (no errors)
5. **Given** monitor configuration changes (plug/unplug), **When** I switch workspaces, **Then** output cache updates and correct output is focused

---

### User Story 6 - Native Sway Mode Indicator (Priority: P2)

As a user, I want to see when I'm in workspace navigation mode using Sway's native binding_mode_indicator, so the UI feels integrated and consistent with the window manager.

**Why this priority**: Nice visual improvement but not blocking - can use status bar or notify-send initially.

**Independent Test**: Can be tested by configuring swaybar with `binding_mode_indicator yes` and verifying mode name appears when entering goto_workspace or move_workspace mode.

**Acceptance Scenarios**:

1. **Given** swaybar is configured with binding_mode_indicator, **When** I enter goto_workspace mode, **Then** mode indicator shows styled mode name
2. **Given** I'm in workspace mode, **When** mode indicator is visible, **Then** it uses Pango markup for attractive styling
3. **Given** I exit workspace mode, **When** I return to default mode, **Then** mode indicator disappears

---

### Edge Cases

- What happens when user types invalid digits (empty, starts with "00")?
  - Empty: Mode exits without action (user pressed Enter immediately)
  - Leading zeros: First "0" is ignored, subsequent digits accumulate normally ("0" + "5" = "5")

- How does system handle rapid successive mode entries (stress test)?
  - Daemon processes each event sequentially with async-safe state management
  - No race conditions due to single-threaded event loop
  - Previous mode state is properly reset before new mode entry

- What happens when daemon restarts while user is in workspace mode?
  - Mode state is lost (in-memory only)
  - User pressing Enter will do nothing (no accumulated digits in daemon)
  - User must exit mode (Escape) and re-enter

- What happens when output configuration changes during accumulated digit entry?
  - Output cache is updated via on_output event subscription
  - Next workspace switch uses updated output assignments
  - No stale output names used

- What happens when user switches to non-existent workspace (e.g., workspace 99 has no windows)?
  - System allows switch (creates workspace on demand - standard Sway behavior)
  - No validation error (users may want to open apps on empty workspace)
  - Logged at DEBUG level for monitoring

- What happens when user is on workspace 23 and switches to workspace 23 again?
  - No error, focus remains on workspace 23 (idempotent)
  - Recorded in history as valid navigation event

- What happens when mode indicator conflicts with custom status bar blocks?
  - Priority order: binding_mode_indicator > custom status bar blocks
  - Status bar blocks can detect mode state via daemon events and hide themselves if desired

## Requirements *(mandatory)*

### Functional Requirements

#### Core Navigation

- **FR-001**: System MUST accept digit input (0-9) during goto_workspace mode and accumulate digits in daemon state
- **FR-002**: System MUST switch to accumulated workspace number when Enter is pressed in goto_workspace mode
- **FR-003**: System MUST reset accumulated digits to empty state after workspace switch or cancel
- **FR-004**: System MUST handle leading zero by replacing initial "0" with first non-zero digit
- **FR-005**: System MUST move focused window to accumulated workspace number when Enter is pressed in move_workspace mode
- **FR-006**: System MUST follow window after moving (focus target workspace)
- **FR-007**: System MUST exit mode and return to default when Escape is pressed without executing action

#### Output Management

- **FR-008**: System MUST maintain cached output-to-name mapping (PRIMARY, SECONDARY, TERTIARY)
- **FR-009**: System MUST update output cache when on_output events are received (monitor plug/unplug)
- **FR-010**: System MUST focus correct output based on workspace number: 1-2 → PRIMARY, 3-5 → SECONDARY, 6+ → TERTIARY
- **FR-011**: System MUST handle single-monitor configurations by assigning all outputs to same physical display

#### State Management

- **FR-012**: System MUST store workspace mode state in daemon memory (not files)
- **FR-013**: System MUST expose workspace mode state via IPC for CLI tool queries
- **FR-014**: System MUST track workspace switch history (last 100 events) with timestamp, workspace number, output
- **FR-015**: System MUST clear history on daemon restart (in-memory only, no persistence)

#### Event Integration

- **FR-016**: System MUST broadcast workspace_mode event to subscribed clients when digit is accumulated
- **FR-017**: System MUST broadcast workspace_mode event when mode is entered or exited
- **FR-018**: System MUST include accumulated digits, mode type (goto/move), and timestamp in broadcast events
- **FR-019**: Status bar scripts MUST receive real-time events for displaying workspace mode state

#### IPC Interface

- **FR-020**: System MUST provide `workspace_mode.digit <N>` IPC method for digit input
- **FR-021**: System MUST provide `workspace_mode.execute` IPC method for switch execution
- **FR-022**: System MUST provide `workspace_mode.cancel` IPC method for mode exit
- **FR-023**: System MUST provide `workspace_mode.state` IPC method for current state query
- **FR-024**: System MUST provide `workspace_mode.history` IPC method for navigation history query

#### CLI Tool

- **FR-025**: CLI tool MUST expose `i3pm workspace-mode digit <N>` subcommand
- **FR-026**: CLI tool MUST expose `i3pm workspace-mode execute` subcommand
- **FR-027**: CLI tool MUST expose `i3pm workspace-mode cancel` subcommand
- **FR-028**: CLI tool MUST expose `i3pm workspace-mode state` subcommand with --json flag
- **FR-029**: CLI tool MUST expose `i3pm workspace-mode history` subcommand with --json flag

#### Sway Integration

- **FR-030**: Sway mode bindings MUST call `i3pm workspace-mode` CLI commands (not bash scripts)
- **FR-031**: System MUST support native Sway binding_mode_indicator for visual feedback
- **FR-032**: Mode definitions MUST use Pango markup for styled mode names
- **FR-033**: System MUST subscribe to Sway mode events to detect mode entry/exit

#### Platform Support

- **FR-034**: System MUST work on M1 MacBook Pro with physical keyboard (CapsLock activation)
- **FR-035**: System MUST work on Hetzner Cloud with VNC (Ctrl+0 activation)
- **FR-036**: System MUST work on configurations with 1, 2, or 3 monitors
- **FR-037**: System MUST adapt to both i3 and Sway window managers (shared IPC protocol)

#### Performance

- **FR-038**: Digit accumulation MUST complete in under 10ms (measured from IPC call to state update)
- **FR-039**: Workspace switch execution MUST complete in under 20ms (measured from execute call to focus change)
- **FR-040**: Status bar event broadcast MUST occur within 5ms of state change
- **FR-041**: System MUST avoid spawning external processes for core navigation (all in-daemon)

#### Backward Compatibility

- **FR-042**: System MUST maintain existing keybindings (CapsLock, Shift+CapsLock, Ctrl+0, Mod+semicolon)
- **FR-043**: System MUST preserve workspace distribution logic (1-2 PRIMARY, 3-5 SECONDARY, 6+ TERTIARY)
- **FR-044**: System MUST preserve fallback to notify-send if status bar integration unavailable

### Key Entities

- **WorkspaceModeState**: Current workspace mode session state
  - active: bool (whether mode is currently active)
  - mode_type: "goto" | "move" (which mode is active)
  - accumulated_digits: string (digits typed so far, e.g., "23")
  - entered_at: timestamp (when mode was entered)
  - output_cache: mapping of output roles (PRIMARY/SECONDARY/TERTIARY) to physical output names (eDP-1, HEADLESS-1, etc.)

- **WorkspaceSwitch**: Historical navigation event
  - workspace: int (workspace number switched to)
  - output: string (output name that was focused)
  - timestamp: float (Unix timestamp)
  - mode_type: "goto" | "move" (how user navigated)

- **WorkspaceModeEvent**: Broadcast event for status bar updates
  - event_type: "workspace_mode"
  - mode_active: bool
  - mode_type: "goto" | "move" | null
  - accumulated_digits: string
  - timestamp: float

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete workspace navigation (enter mode, type digits, execute) in under 30ms total latency (down from 70ms with bash)
- **SC-002**: Digit accumulation provides visual feedback in status bar within 10ms of keypress
- **SC-003**: System handles 50 rapid workspace switches per minute without lag or state corruption
- **SC-004**: Workspace mode state is visible in status bar 100% of the time when mode is active (no missed updates)
- **SC-005**: Multi-monitor output focusing is correct 100% of the time (workspaces appear on expected monitors)
- **SC-006**: Zero instances of stale state after daemon restart (clean in-memory state management)
- **SC-007**: Navigation history accurately tracks last 100 switches with timestamps for future analytics features
- **SC-008**: System works identically on M1 (physical keyboard) and Hetzner (VNC) with no platform-specific bugs

### User Experience

- **SC-009**: Users perceive workspace switching as "instant" with no noticeable delay between keypress and focus change
- **SC-010**: Visual feedback (status bar or mode indicator) makes accumulated digits clearly visible at all times during mode
- **SC-011**: System behavior is predictable and consistent across all workspace numbers and monitor configurations
- **SC-012**: No user-facing errors or crashes when switching between 1, 2, or 3 monitor configurations

## Assumptions

1. **Event Loop**: Assumes i3pm daemon uses asyncio event loop that can handle workspace mode state without blocking other event handlers
2. **IPC Protocol**: Assumes existing JSON-RPC IPC infrastructure can be extended with new workspace_mode.* methods
3. **Status Bar**: Assumes i3bar status scripts can subscribe to daemon events and update in real-time (already working for project switching)
4. **Sway Compatibility**: Assumes Sway's binding_mode_indicator behavior matches i3 documentation (both use same IPC protocol)
5. **Performance**: Assumes Python daemon with in-memory state is faster than spawning bash processes for each keypress
6. **Monitor Detection**: Assumes Sway emits output events reliably when monitors are plugged/unplugged
7. **Workspace Creation**: Assumes Sway automatically creates non-existent workspaces when user navigates to them (standard behavior)
8. **Mode Events**: Assumes Sway emits mode events when bindings trigger "mode" command (for daemon to detect mode entry)

## Dependencies

- **i3pm daemon**: Must be running and healthy (all workspace mode operations depend on daemon)
- **Sway IPC socket**: Must be accessible for sending workspace switch commands
- **Status bar subscription**: Status bar scripts must subscribe to daemon events for real-time feedback
- **Sway configuration**: modes.conf must define goto_workspace and move_workspace modes with bindings
- **Python packages**: i3ipc, asyncio (already installed in daemon environment)

## Out of Scope

- Workspace suggestions based on recent history (future enhancement - User Story 4 provides foundation)
- Workspace validation (warning for empty workspaces) - system allows all switches
- Relative navigation (hjkl-style previous/next workspace) - potential future enhancement
- Workspace mode analytics dashboard - only basic history tracking included
- Integration with walker launcher for fuzzy workspace search
- Persistent workspace mode history across daemon restarts
- Configuration options for workspace distribution rules (hardcoded: 1-2 PRIMARY, 3-5 SECONDARY, 6+ TERTIARY)
- Custom mode styling beyond Pango markup (uses Sway defaults)
- Workspace renaming or labeling (uses numeric workspace IDs only)

## Risks

1. **Sway Mode Events**: If Sway doesn't emit mode events reliably, daemon won't know when user enters/exits mode
   - *Mitigation*: Test early, fallback to polling mode state via IPC if needed

2. **Race Condition on Rapid Entry**: User might enter mode, exit, re-enter faster than daemon can process
   - *Mitigation*: Async-safe state management with locks, sequential processing of mode events

3. **Status Bar Latency**: If status bar script is slow to process events, visual feedback may lag
   - *Mitigation*: Optimize status bar event handling, measure and monitor latency

4. **Output Cache Stale**: If monitor changes occur but output events are missed, cache could be stale
   - *Mitigation*: Refresh output cache on every workspace switch (query Sway outputs as fallback)

5. **Daemon Restart During Mode**: User might be in workspace mode when daemon crashes
   - *Mitigation*: Sway mode state is independent of daemon - user can exit mode (Escape) and retry

6. **IPC Socket Permissions**: If IPC socket becomes inaccessible, CLI commands will fail
   - *Mitigation*: Existing daemon health monitoring detects socket issues, logs errors clearly

## Notes

- This feature represents a significant architectural improvement (bash → Python) with measurable performance gains
- The foundation laid here (history tracking, event broadcasting) enables future enhancements like smart workspace suggestions
- Native Sway binding_mode_indicator provides better visual integration than external notify-send
- All workspace distribution logic is preserved from current bash implementation (no behavior changes for users)
- Feature follows existing i3pm daemon patterns (IPC methods, event broadcasting, CLI tool delegation)
