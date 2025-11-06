# Feature Specification: i3run-Inspired Scratchpad Enhancement

**Feature Branch**: `051-i3run-scratchpad-enhancement`
**Created**: 2025-11-06
**Status**: Draft
**Input**: User description: "create new feature that uses an open-source community project called i3run to enhance our implementation of scratch terminals in our current project. i3run takes i3 commands and packages them together with some custom logic to address some of the practical use cases of users, and to address some of the quirks in i3 that are not desirable from a practical user standpoint. review @docs/budlabs-i3run-c0cc4cc3b3bf7341.txt which contains the source code of i3run, and deconstruct the operations and logic used for different use cases, and then determine if we can incorporate some of its logic and execution methods to transform our own use of scratch terminals (and related functions). its very important that we maintain our overall approach of using a python module that is event/subscription based, async where possible, etc. but i3run addresses some practical aspects that we should solve for within our architecture. our use of scratchpads is detailed in the current branch, and will be for having a floating terminal for each project that can be independently hidden and unhidden. don't worry about backwards compatibility. if we find a more optimal solution for any of the aspects of our project, we should replace the existing methodology/code with the new approach, and discard the legacy artifacts"

## Overview

### Purpose

Enhance the existing project-scoped scratchpad terminal implementation by incorporating intelligent window management patterns from i3run, specifically: smart positioning with screen edge awareness, mouse-cursor-based summoning, adaptive floating window geometry, and robust state preservation across show/hide cycles.

### Background

Feature 062 introduced basic project-scoped scratchpad terminals with fixed positioning (centered, 1000x600px). While functional, it lacks the polish and user-centric behaviors that make i3run popular:

- **Fixed positioning**: Terminals always appear centered, regardless of user context or multi-monitor setup
- **No edge awareness**: Floating windows can be partially off-screen on smaller displays
- **No state tracking**: Doesn't preserve tiling/floating state when hiding windows
- **No workspace-aware summoning**: Can't intelligently move terminals to current workspace vs switching workspaces
- **No mouse-cursor positioning**: Can't summon terminal to where user is actively working

i3run solves these problems with:
1. **Configurable screen gaps** - Prevents floating windows from rendering off-screen
2. **Mouse-cursor positioning** - Summons windows to cursor location with automatic boundary checking
3. **Floating state preservation** - Stores original tiling/floating state in variables, restores on show
4. **Workspace summoning** - Option to move window to current workspace vs switching to window's workspace
5. **Intelligent focus logic** - Prioritizes visible containers, handles scratchpad states correctly

Our enhancement will integrate these patterns into the existing async Python event-driven architecture.

### Goals

- Add mouse-cursor-based terminal summoning with screen-edge boundary detection
- Implement configurable screen edge gaps to prevent off-screen rendering
- Preserve original tiling/floating state when hiding windows
- Add workspace summoning mode (move window to current workspace vs switching workspaces)
- Improve multi-monitor support with workspace-aware positioning
- Maintain async Python architecture with event-driven patterns

### Non-Goals

- Replicating i3run's rename functionality (not needed for our use case)
- Supporting i3fyra container management (we don't use i3fyra)
- Implementing window search by class/instance/title (already handled by daemon)
- Supporting --force command execution (terminals are simple launch-once pattern)
- Backward compatibility with Feature 062 fixed positioning (deliberate replacement)

## User Scenarios & Testing

### User Story 1 - Mouse-Cursor Terminal Summoning (Priority: P1)

When working on a specific area of the screen (editing code, reading logs), users want the scratchpad terminal to appear near the mouse cursor rather than always in the center, reducing eye/cursor travel distance and maintaining focus context.

**Why this priority**: Core UX improvement that fundamentally changes how users interact with scratchpad terminals. Delivers immediate ergonomic value and differentiates from basic center-only positioning.

**Independent Test**: Can be fully tested by positioning mouse in various screen locations (top-left, bottom-right, center), pressing scratchpad keybinding, and verifying terminal appears near cursor without going off-screen. Delivers standalone value as mouse-aware positioning system.

**Acceptance Scenarios**:

1. **Given** mouse cursor is at screen position (X=500, Y=300) and terminal size is 1000x600, **When** user presses scratchpad keybinding, **Then** terminal appears centered on cursor with top-left at (0, 0) since centering would place it partially off-screen
2. **Given** mouse cursor is in bottom-right corner of 1920x1080 screen, **When** user summons terminal, **Then** terminal appears with right edge 10px from screen right edge, bottom edge 10px from screen bottom edge
3. **Given** mouse cursor is in center of screen, **When** user summons terminal, **Then** terminal appears perfectly centered on cursor
4. **Given** terminal is currently visible in center of screen and mouse cursor is in top-left corner, **When** user presses scratchpad keybinding with summon-to-mouse enabled, **Then** terminal hides (toggle behavior takes precedence over repositioning)

---

### User Story 2 - Screen Edge Boundary Protection (Priority: P2)

On smaller displays or when using tiled window managers with panels/bars, floating windows can render partially or fully off-screen, making them inaccessible. Users need automatic boundary detection to keep terminals visible.

**Why this priority**: Essential for usability on small displays and multi-monitor setups, but builds on P1 positioning logic. Can be developed/tested after mouse positioning works.

**Independent Test**: Can be tested by configuring custom gap values, summoning terminal near screen edges, and verifying it stays within configured boundaries on displays of varying sizes (1920x1080, 1366x768, 3840x2160).

**Acceptance Scenarios**:

1. **Given** screen edge gaps are set to TOP=50, BOTTOM=30, LEFT=10, RIGHT=10, **When** user summons terminal near top edge, **Then** terminal top edge is at least 50px from screen top edge
2. **Given** user has a 1366x768 display with terminal size 1000x600, **When** user summons terminal, **Then** terminal automatically shrinks or repositions to fit within visible area minus configured gaps
3. **Given** user has three monitors with different resolutions, **When** user moves between monitors and summons terminal, **Then** terminal respects per-monitor boundaries and appears fully visible on target monitor

---

### User Story 3 - Workspace Summoning Mode (Priority: P3)

When scratchpad terminal is on a different workspace, users want the choice between: (A) switching to terminal's workspace, or (B) moving terminal to current workspace. Option B keeps user in current context while bringing tool to them.

**Why this priority**: Enhances workflow flexibility but feature is valuable without it (default switch-to-workspace behavior is acceptable). Can be refined after core positioning works.

**Independent Test**: Can be tested by opening terminal on workspace 1, switching to workspace 5, toggling summon mode, and pressing scratchpad keybinding to verify terminal either appears on workspace 5 (summon mode) or switches focus to workspace 1 (goto mode).

**Acceptance Scenarios**:

1. **Given** scratchpad terminal is visible on workspace 1 and user is on workspace 5, **When** user presses scratchpad keybinding with summon mode enabled, **Then** terminal moves to workspace 5 centered on mouse cursor
2. **Given** scratchpad terminal is hidden in scratchpad and user is on workspace 3, **When** user presses scratchpad keybinding with summon mode enabled, **Then** terminal appears on workspace 3 (does not switch workspaces)
3. **Given** scratchpad terminal is visible on workspace 2 and user is on workspace 2, **When** user presses scratchpad keybinding with summon mode enabled, **Then** terminal hides to scratchpad (toggle behavior)
4. **Given** summon mode is disabled and terminal is on workspace 1, **When** user on workspace 5 presses scratchpad keybinding, **Then** focus switches to workspace 1 and terminal is shown/focused (i3run default behavior)

---

### User Story 4 - Floating State Preservation (Priority: P4)

When users manually tile a scratchpad terminal (move it from floating to tiling layout), they expect the terminal to remember this preference and restore as tiled when shown again, not forced back to floating.

**Why this priority**: Nice-to-have quality-of-life feature. Most users will keep scratchpad terminals floating, but power users who customize layouts will appreciate state preservation. Lowest priority as it's edge case behavior.

**Independent Test**: Can be tested by launching scratchpad terminal, manually changing it from floating to tiling, hiding it, then showing it again to verify it restores as tiling window in same position.

**Acceptance Scenarios**:

1. **Given** user launched floating scratchpad terminal then manually tiled it, **When** user hides then shows terminal, **Then** terminal restores as tiled window in previous tiling position
2. **Given** user launched floating scratchpad terminal and kept it floating, **When** user hides then shows terminal, **Then** terminal restores as floating window in previous floating position
3. **Given** scratchpad terminal has been hidden for multiple hours, **When** user shows it again, **Then** terminal restores with correct tiling/floating state from when it was hidden

---

### Edge Cases

**Case 1: Mouse cursor outside visible workspace area**
- **Given**: User has mouse cursor on a different monitor than active workspace
- **When**: User presses scratchpad keybinding with mouse summoning enabled
- **Then**: Terminal appears on monitor containing active workspace, centered (fallback to center positioning)
- **Verify**: System detects invalid mouse position, defaults to safe center positioning

**Case 2: Terminal larger than available screen space**
- **Given**: User configured terminal size 1400x850 but has 1366x768 display with 50px top gap for panel
- **When**: User summons terminal
- **Then**: Terminal appears with maximum size that fits within available space (1366x668), maintaining aspect ratio if possible
- **Verify**: Terminal is fully visible, gaps are respected, no content is off-screen

**Case 3: Multi-monitor boundary crossing**
- **Given**: User has two monitors side-by-side, mouse cursor is 10px from right edge of left monitor
- **When**: User summons 1000px wide terminal
- **Then**: Terminal appears on left monitor with right edge at configured gap distance from monitor boundary (does not span monitors)
- **Verify**: System detects monitor boundaries, constrains terminal to single monitor

**Case 4: Changing gap configuration while terminal visible**
- **Given**: User has terminal visible with current gap settings
- **When**: User changes gap configuration via environment variables or config file
- **Then**: Next summon operation uses new gap values
- **Verify**: Gap changes apply immediately on next summon, no restart required

**Case 5: Workspace summoning with tiling window**
- **Given**: User manually converted floating scratchpad terminal to tiled window on workspace 1
- **When**: User on workspace 5 presses scratchpad keybinding with summon mode enabled
- **Then**: Terminal moves to workspace 5 and restores as tiled window (preserves tiling state across workspace move)
- **Verify**: Tiling state is preserved when moving window to different workspace

**Case 6: Rapid toggle during window movement**
- **Given**: User summons terminal which begins animating into position
- **When**: User immediately presses scratchpad keybinding again before animation completes
- **Then**: System queues the hide operation, completes current summon, then hides terminal
- **Verify**: No race condition, state remains consistent, terminal ends up hidden

## Requirements

### Functional Requirements

**FR-001: Mouse-Cursor-Based Positioning**
When summoning a scratchpad terminal with mouse positioning enabled, the system MUST calculate terminal position such that the terminal is centered on the current mouse cursor coordinates, subject to screen edge boundary constraints defined by configurable gap values.

**FR-002: Screen Edge Boundary Protection**
The system MUST respect configurable gap values (TOP_GAP, BOTTOM_GAP, LEFT_GAP, RIGHT_GAP) measured in pixels from screen edges. When positioning a terminal would cause any edge to be closer than the configured gap, the system MUST adjust the position to maintain minimum gap distance.

**FR-003: Configurable Gap Values**
Users MUST be able to configure screen edge gaps through environment variables:
- `I3RUN_TOP_GAP`: Distance from top screen edge (default: 10px)
- `I3RUN_BOTTOM_GAP`: Distance from bottom screen edge (default: 10px)
- `I3RUN_LEFT_GAP`: Distance from left screen edge (default: 10px)
- `I3RUN_RIGHT_GAP`: Distance from right screen edge (default: 10px)

Changes to gap values MUST take effect on next summon operation without requiring daemon restart.

**FR-004: Workspace Summoning Mode**
The system MUST support two terminal summoning behaviors, controlled by user configuration:
- **Goto mode (default)**: When terminal is on different workspace, switch focus to terminal's workspace
- **Summon mode**: When terminal is on different workspace, move terminal to current workspace

**FR-005: Floating State Preservation**
When hiding a scratchpad terminal, the system MUST record its current floating/tiling state in Sway window marks (not daemon memory). When showing the terminal again, the system MUST restore it to the same floating/tiling state it had when hidden, even if the daemon or Sway has restarted since the terminal was hidden.

**FR-006: Multi-Monitor Boundary Detection**
When positioning a terminal on multi-monitor setups, the system MUST:
- Detect which monitor contains the mouse cursor
- Calculate boundaries based on that monitor's dimensions
- Constrain terminal position to stay fully within that monitor (no spanning)

**FR-007: Automatic Size Adjustment**
If configured terminal size exceeds available screen space (accounting for gaps), the system MUST automatically reduce terminal dimensions to fit within available space while maintaining visibility of all terminal content.

**FR-008: Cursor Position Validation**
Before using mouse cursor coordinates for positioning, the system MUST validate that cursor is within the bounds of the current workspace's monitor. If invalid (e.g., cursor on different monitor), the system MUST fallback to center positioning on the active workspace's monitor.

**FR-009: Async State Management**
All window state queries (floating/tiling detection, position queries, workspace queries) MUST be implemented using async Python patterns with Sway IPC, maintaining compatibility with existing event-driven daemon architecture.

**FR-010: Terminal Toggle Priority**
When scratchpad terminal is currently visible on the same workspace where user is located, toggle behavior (hide terminal) MUST take priority over repositioning logic. Mouse-cursor positioning only applies when showing a hidden terminal.

**FR-011: Persistent State Storage via Marks**
When hiding or repositioning a scratchpad terminal, the system MUST store state data in Sway window marks using the format: `scratchpad_state:{project_name}={key1}:{value1},{key2}:{value2}...`

The following state data MUST be persisted in marks:
- Floating/tiling state (boolean)
- Window geometry: x position, y position, width, height (pixels)
- Last position update timestamp (Unix epoch)

State stored in marks MUST persist across daemon restarts and Sway restarts. When showing a terminal, the system MUST read state from marks and restore the terminal to its previous state. If no marks exist for a terminal (first launch), the system MUST use default positioning logic (FR-001).

Mark storage MUST use a ghost container (invisible, persistent window marked `i3pm_ghost`) to store project-wide scratchpad state that isn't tied to specific terminal windows.

### Key Entities

**Terminal Position State** (persisted in Sway marks)
- Window ID reference
- Current floating/tiling state (stored in mark: `floating:true|false`)
- Last known position (stored in mark: `x:N,y:N` in pixels)
- Last known size (stored in mark: `w:N,h:N` in pixels)
- Last update timestamp (stored in mark: `ts:N` Unix epoch)
- Workspace ID where terminal is located (queried from Sway tree)
- Monitor ID where terminal was last shown (derived from position and monitor geometry)

**Screen Geometry** (queried from Sway outputs)
- Monitor dimensions (width, height)
- Monitor offset (X, Y position in multi-monitor layout)
- Configured gap values (top, bottom, left, right) from environment variables
- Available space after accounting for gaps (calculated)

**Mouse Cursor Position** (queried from Sway seat)
- Absolute X, Y coordinates in screen space
- Monitor ID containing cursor (calculated from position and monitor geometry)
- Validity flag (whether cursor is on current workspace's monitor)

**Ghost Container** (persistent mark storage)
- Invisible window marked `i3pm_ghost`
- Size 1x1 pixel, hidden in scratchpad
- Stores project-wide state in additional marks
- Created on first scratchpad operation if doesn't exist

## Success Criteria

### Measurable Outcomes

**SC-001: Positioning Accuracy**
Terminal positioning MUST respect configured gap boundaries in 100% of summon operations across all tested display sizes (1366x768, 1920x1080, 2560x1440, 3840x2160).

**SC-002: Mouse Proximity**
When summoning terminal with mouse positioning enabled on adequately sized displays (≥1920x1080), terminal center MUST be within 100 pixels of mouse cursor position in 95% of cases (excluding edge constraint adjustments).

**SC-003: Multi-Monitor Handling**
On multi-monitor setups (2-3 monitors), terminal MUST appear fully visible on the correct monitor (containing mouse cursor) in 100% of summon operations, with no content spanning multiple monitors.

**SC-004: State Preservation**
Floating/tiling state MUST be correctly preserved and restored after hide/show cycles in 100% of test cases, including across project switches and workspace changes.

**SC-005: Performance**
Terminal positioning calculations (including boundary detection, gap application, monitor detection) MUST complete in under 50 milliseconds measured from scratchpad keybinding press to terminal window appearance.

**SC-006: Workspace Summoning**
When summon mode is enabled and terminal is on different workspace, terminal MUST move to current workspace without switching workspace focus in 100% of operations.

**SC-007: Rapid Toggle Handling**
System MUST handle rapid toggle operations (multiple keybinding presses within 500ms) without entering inconsistent state, with final terminal visibility state correctly reflecting the last user action.

## Assumptions

1. **Display Configuration**: Users have stable display configurations during a session. Display changes (connecting/disconnecting monitors) that occur while daemon is running may require manual terminal repositioning or daemon restart.

2. **Terminal Size**: Default terminal size (1000x600) is appropriate for most use cases. Users requiring different sizes can configure via environment variables. Automatic size adjustment only occurs when terminal literally cannot fit on screen.

3. **Gap Value Reasonableness**: Users will configure gap values that leave sufficient space for terminal display (e.g., not setting all gaps to 500px on a 1366x768 display). System will not validate gap value sanity, only apply them.

4. **Mouse Cursor Availability**: Sway/i3 provides accurate mouse cursor position via IPC or X utilities. If cursor position cannot be determined, system falls back to center positioning.

5. **Single Terminal Per Project**: Enhancement maintains Feature 062's constraint of one scratchpad terminal per project. Multi-terminal support is out of scope.

6. **Floating Window Support**: Users accept that scratchpad terminals are primarily designed for floating usage. While tiling state preservation is supported, the feature is optimized for floating window workflows.

7. **Environment Variable Persistence**: Gap configuration via environment variables is loaded at daemon startup. Changes to environment after daemon starts require manual daemon restart to take effect. (Note: FR-003 will implement hot-reload if feasible within async architecture)

8. **i3run Pattern Adaptation**: Not all i3run patterns are applicable. We deliberately exclude: window renaming (not needed), i3fyra support (not used), force command execution (terminals are simple), search by class/instance/title (already handled by daemon).
