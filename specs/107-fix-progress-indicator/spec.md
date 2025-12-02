# Feature Specification: Fix Progress Indicator Focus State and Event Efficiency

**Feature Branch**: `107-fix-progress-indicator`
**Created**: 2025-12-01
**Status**: Draft
**Input**: User description: "review my current configuration around claude-code hooks that generates a progress indicator in the window tab of the monitoring widget. make sure the progress indicator shows whether or not the window is in focus; also determine if we have structured the progress indicator in the most efficient, performant manner possible; preferable in a event based manner"

## Analysis Summary

### Current Implementation (Feature 095)

The progress indicator system consists of:

1. **Claude Code Hooks** (`home-modules/ai-assistants/claude-code.nix`):
   - `UserPromptSubmit` hook → creates "working" badge (spinner animation)
   - `Stop` hook → changes badge to "stopped" state (bell icon)

2. **Badge State Storage** (file-based):
   - Location: `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`
   - Written by hook scripts directly (no daemon IPC)

3. **Badge Reading** (`monitoring_data.py`):
   - `load_badge_state_from_files()` reads badge JSON files
   - Checks badge files every 500ms in idle mode
   - Switches to 50ms polling when "working" badge detected (for spinner animation at 120ms frames)

4. **Focus-Based Badge Clearing**:
   - `on_window_event()` handler clears badge file when window receives focus
   - Badge file is deleted immediately upon focus event

### Issues Identified

**Issue 1: Focus State Not Displayed in Badge**
- Current badge visibility: `{(window.badge?.count ?: "") != "" || (window.badge?.state ?: "") == "working"}`
- Badge shows only when there's a count OR working state
- **Missing**: No consideration of whether the window is currently focused
- User cannot distinguish if the badged window is already focused vs. needs attention

**Issue 2: Polling-Based Badge Detection (Inefficient)**
- Badge files are checked via filesystem polling (500ms idle, 50ms when working)
- This adds CPU overhead and latency vs. event-driven approach
- Hook scripts write files → `monitoring_data.py` polls files → Eww updates
- **Better**: Hook scripts could signal daemon directly via IPC

**Issue 3: Dual-Path Badge State**
- Badge state exists in two places:
  1. File system (`$XDG_RUNTIME_DIR/i3pm-badges/*.json`)
  2. Badge service Pydantic models (`badge_service.py`) - currently unused
- The daemon `badge_service.py` was designed for IPC but implementation uses file-based approach

**Issue 4: Badge Spinner Animation Causes Frequent Updates**
- When "working" badge exists, system polls every 50ms and refreshes full data
- Spinner frame changes every 120ms
- This causes ~20 JSON updates per second during "working" state

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Badge Reflects Window Focus State (Priority: P1)

User needs to see at a glance whether a badged window is already focused or requires navigation. Currently, a badge shows the same appearance regardless of focus state, creating confusion.

**User Journey**:
1. User starts Claude Code task in terminal on workspace 1
2. Claude Code finishes, badge appears on window in monitoring panel
3. User is already focused on that terminal (same workspace)
4. Badge should visually indicate "this window is focused" (e.g., dimmed or different icon)
5. User switches to different workspace
6. Badge should visually indicate "this window needs attention" (full prominence)
7. User can distinguish focused-badged from unfocused-badged windows instantly

**Why this priority**: Core usability gap - users currently cannot tell if the badged window is already focused, leading to unnecessary navigation attempts.

**Independent Test**: Can be tested by creating badge on focused window, verifying visual distinction; then switching away and verifying prominence change.

**Acceptance Scenarios**:

1. **Given** window with badge is currently focused, **When** user views monitoring panel, **Then** badge displays with "focused" visual treatment (dimmed or different indicator)

2. **Given** window with badge is not focused, **When** user views monitoring panel, **Then** badge displays with full prominence (current stopped/working styling)

3. **Given** user switches focus from badged window to another window, **When** monitoring panel updates, **Then** badge visual treatment changes from "focused" to "attention needed"

---

### User Story 2 - Event-Driven Badge Updates (Priority: P2)

Replace polling-based badge detection with event-driven IPC for better performance and lower latency.

**User Journey**:
1. User submits prompt to Claude Code
2. Hook script signals daemon directly via Unix socket IPC
3. Daemon updates badge state in-memory and publishes to Eww stream
4. Badge appears in monitoring panel within 100ms (no filesystem polling)
5. Claude Code finishes, stop hook signals daemon via IPC
6. Badge state changes to "stopped" immediately

**Why this priority**: Performance optimization - reduces CPU overhead, file I/O, and latency. Current polling adds 0-500ms latency in idle mode.

**Independent Test**: Can be tested by measuring time from hook execution to badge appearance in panel, comparing file-based vs IPC-based implementation.

**Acceptance Scenarios**:

1. **Given** Claude Code submits prompt, **When** hook fires, **Then** badge appears in monitoring panel within 100ms (no polling delay)

2. **Given** badge state changes frequently, **When** monitoring panel is open, **Then** CPU usage remains below 2% (no polling loops)

3. **Given** daemon restarts, **When** hook fires next, **Then** IPC connection re-establishes automatically

---

### User Story 3 - Optimized Spinner Animation (Priority: P3)

Reduce update frequency for spinner animation while maintaining smooth visual appearance.

**User Journey**:
1. User submits Claude Code prompt
2. "Working" badge appears with spinner animation
3. Spinner animates smoothly at visible rate (~8fps sufficient for braille spinner)
4. Only spinner_frame field updates, not entire monitoring data
5. System uses minimal CPU for animation
6. Claude Code finishes, spinner stops and bell icon appears

**Why this priority**: Performance refinement - current implementation refreshes full monitoring data every 50ms during spinner. Can be optimized to update only spinner frame via separate Eww variable.

**Independent Test**: Can be tested by monitoring CPU usage during "working" state, comparing current vs. optimized implementation.

**Acceptance Scenarios**:

1. **Given** "working" badge is active, **When** spinner animates, **Then** only spinner frame data is transmitted (not full window tree)

2. **Given** "working" badge is active for 60 seconds, **When** measuring CPU usage, **Then** average CPU < 1% for monitoring backend

3. **Given** spinner animation is visible, **When** user observes animation, **Then** animation appears smooth (no visible stuttering)

---

### Edge Cases

- What happens when focus changes rapidly (multiple focus events per second)?
  → Focus state updates with each event; badge visibility/treatment updates accordingly

- What happens when daemon is not running and hook fires?
  → Hook script should fall back to file-based approach (current behavior preserved)

- What happens when badge file is corrupted or malformed?
  → Gracefully ignore, log warning, continue with other badges

- What happens when window closes while "working" badge is active?
  → Badge state and file cleaned up immediately via window close event

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Badge visual treatment MUST distinguish between focused and unfocused badged windows
- **FR-002**: System MUST update badge focus state within 100ms of window focus event
- **FR-003**: Hook scripts MUST support IPC-based badge signaling as primary path with file fallback
- **FR-004**: Daemon MUST accept badge create/update/clear commands via Unix socket IPC
- **FR-005**: Spinner animation updates MUST be decoupled from full monitoring data refresh
- **FR-006**: System MUST provide visual indicator showing "working" vs "stopped" badge states (existing)
- **FR-007**: Badge MUST clear when window receives focus (existing behavior preserved)
- **FR-008**: System MUST display window focus state accurately for all windows in monitoring panel
- **FR-009**: IPC-based badge updates MUST complete within 50ms from hook invocation to daemon acknowledgment
- **FR-010**: Badge system MUST degrade gracefully if daemon is unavailable (file-based fallback)

### Key Entities

- **WindowBadge** (existing): Extended with `is_focused` flag for rendering decisions
- **BadgeState** (existing): Now used as authoritative state (not file-based)
- **BadgeIpcCommand**: New IPC message type for badge create/update/clear operations

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can distinguish focused vs. unfocused badged windows in under 1 second (visual differentiation)
- **SC-002**: Badge appears in monitoring panel within 100ms of hook execution (IPC path)
- **SC-003**: CPU usage during "working" badge state remains below 2% (optimized spinner)
- **SC-004**: Focus state accuracy: 100% of focus changes reflected in badge treatment within 100ms
- **SC-005**: Zero regression in existing badge functionality (clear on focus, persistence across panel toggles)
- **SC-006**: File I/O operations reduced by 90% during badge operations (IPC replaces polling)

## Assumptions

1. **Daemon Availability**: i3pm daemon is typically running; file fallback is for edge cases only
2. **Sway IPC Reliability**: Focus events fire reliably and quickly (<50ms from actual focus)
3. **Eww Update Performance**: Eww can handle rapid variable updates without UI lag
4. **Hook Execution Context**: Hook scripts execute with access to daemon Unix socket

## Out of Scope

1. **Badge History**: No historical tracking of badge state changes
2. **Multi-Source Badge Aggregation**: Focus on Claude Code hooks; other sources use same mechanism
3. **Badge Customization UI**: No user preferences for badge appearance
4. **Remote Badge Signaling**: Badges are local to machine running monitoring panel

## Dependencies

1. **Feature 095 (Visual Notification Badges)**: This feature extends and optimizes Feature 095
2. **i3pm Daemon**: Requires daemon IPC infrastructure (already exists)
3. **Feature 085 (Monitoring Panel)**: Requires deflisten streaming infrastructure (already exists)
4. **Sway IPC**: Window focus events for state tracking

## Technical Constraints

1. **Backward Compatibility**: File-based badge state must remain functional as fallback
2. **Eww Variable Limits**: Avoid creating too many deflisten streams (consolidate into existing)
3. **Hook Timeout**: Claude Code hooks have 3-second timeout; IPC must complete well under this
4. **Non-Blocking Hooks**: Hook scripts must not block Claude Code operation
