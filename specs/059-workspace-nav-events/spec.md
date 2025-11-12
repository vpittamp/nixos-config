# Feature Specification: Workspace Navigation Event Broadcasting

**Feature Branch**: `059-workspace-nav-events`
**Created**: 2025-11-12
**Status**: Draft
**Input**: User description: "Partial: Arrow key navigation (keybindings exist, but i3pm daemon needs additional methods to broadcast events)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Navigate Between Workspaces with Arrow Keys (Priority: P1)

When a user enters workspace mode and views the all-windows preview, they can use arrow keys to highlight different workspaces in the list before making a selection.

**Why this priority**: This is the core navigation mechanic that makes the preview useful. Without navigation, users can only see the preview but cannot interact with it, defeating the purpose of the feature.

**Independent Test**: Can be fully tested by entering workspace mode (Ctrl+0), pressing Down/Up arrow keys, and verifying that the highlighted workspace changes visually in the preview overlay. Delivers immediate value by making the workspace list interactive.

**Acceptance Scenarios**:

1. **Given** user is in workspace mode with multiple workspaces shown, **When** user presses Down arrow, **Then** the next workspace in the list becomes highlighted
2. **Given** user is on the first workspace in the list, **When** user presses Up arrow, **Then** the highlight wraps to the last workspace
3. **Given** user is on the last workspace in the list, **When** user presses Down arrow, **Then** the highlight wraps to the first workspace
4. **Given** user has navigated to a specific workspace, **When** user presses Enter, **Then** the system switches to the highlighted workspace and exits workspace mode
5. **Given** user is navigating the workspace list, **When** user presses Escape, **Then** navigation is cancelled and workspace mode exits without switching

---

### User Story 2 - Navigate Within Workspace Windows (Priority: P2)

When a user highlights a workspace that contains multiple windows, they can navigate between individual windows within that workspace using additional arrow key presses.

**Why this priority**: Enables fine-grained navigation to specific windows, not just workspaces. This is the second layer of navigation that provides precision control.

**Independent Test**: Can be tested by entering workspace mode, navigating to a workspace with multiple windows, and using arrow keys to move between window items. Delivers value by allowing direct window selection from the preview.

**Acceptance Scenarios**:

1. **Given** user has highlighted a workspace with 3 windows, **When** user presses Right/Down arrow, **Then** the first window in that workspace becomes highlighted
2. **Given** user has highlighted a window within a workspace, **When** user presses Down arrow, **Then** the next window in the same workspace becomes highlighted
3. **Given** user has highlighted the last window in a workspace, **When** user presses Down arrow, **Then** the highlight moves to the first window of the next workspace
4. **Given** user has highlighted a specific window, **When** user presses Enter, **Then** focus switches directly to that window and workspace mode exits

---

### User Story 3 - Jump Navigation with Home/End Keys (Priority: P3)

Users can quickly jump to the first or last item in the preview list using Home and End keys respectively.

**Why this priority**: Convenience feature for users with many workspaces who want to quickly jump to the beginning or end of the list instead of arrow-keying through all items.

**Independent Test**: Can be tested by entering workspace mode with many workspaces, pressing Home to jump to the first item and End to jump to the last item. Delivers value through time savings for users with extensive workspace lists.

**Acceptance Scenarios**:

1. **Given** user is at any position in the preview list, **When** user presses Home, **Then** the first workspace in the list becomes highlighted
2. **Given** user is at any position in the preview list, **When** user presses End, **Then** the last workspace in the list becomes highlighted
3. **Given** user has jumped to first/last item, **When** user presses Enter, **Then** the highlighted workspace becomes active

---

### User Story 4 - Close Windows with Delete Key (Priority: P3)

When a user has highlighted a specific window in the preview, they can press Delete to close that window without switching to its workspace.

**Why this priority**: Useful for workspace cleanup and window management directly from the preview. Not critical for navigation but enhances workflow efficiency.

**Independent Test**: Can be tested by highlighting a window in the preview and pressing Delete to verify the window closes while remaining in workspace mode. Delivers value by enabling quick window management.

**Acceptance Scenarios**:

1. **Given** user has highlighted a specific window in the preview, **When** user presses Delete, **Then** the window closes and is removed from the preview list
2. **Given** user closes the last window in a workspace, **When** the window is removed, **Then** that workspace is removed from the preview list
3. **Given** user has closed a window, **When** preview updates, **Then** the highlight moves to the next available item

---

### Edge Cases

- What happens when user presses navigation keys but workspace mode is not active? (Keys should be ignored or handled by default Sway keybindings)
- What happens when user navigates to a workspace that no longer exists? (System should refresh the preview and move highlight to nearest valid workspace)
- What happens when user rapidly presses navigation keys? (System should queue or debounce events to prevent race conditions)
- What happens when no workspaces exist? (Preview should show empty state, navigation keys should have no effect)
- What happens when preview daemon is not running? (Navigation commands should fail gracefully without crashing the system)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST broadcast navigation events when arrow keys (Up/Down/Left/Right) are pressed during workspace mode
- **FR-002**: System MUST broadcast home/end navigation events when Home/End keys are pressed during workspace mode
- **FR-003**: System MUST broadcast delete events when Delete key is pressed during workspace mode
- **FR-004**: System MUST include direction information (up/down/left/right/home/end) in navigation event payloads
- **FR-005**: Preview daemon MUST receive and process navigation events within 50ms of key press
- **FR-006**: System MUST maintain navigation state (current highlighted item) across multiple navigation events
- **FR-007**: System MUST wrap navigation at list boundaries (first item wraps to last, last item wraps to first)
- **FR-008**: System MUST clear navigation state when workspace mode is exited (cancel, execute, or escape)
- **FR-009**: System MUST only broadcast navigation events when workspace mode is active
- **FR-010**: System MUST handle Enter key to execute action on currently highlighted item (switch to workspace or window)

### Key Entities

- **Navigation Event**: Represents a single navigation action with attributes: event type (nav/delete/home/end), direction (up/down/left/right), timestamp, and current mode (all_windows/filtered/project)
- **Selection State**: Tracks the currently highlighted item with attributes: selected index, item type (workspace/window), workspace number, window ID, and navigation history
- **Event Broadcast**: Communication channel between keybinding handler and preview daemon with attributes: event payload, subscriber list, delivery timestamp

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can navigate through the entire workspace list using arrow keys with visual feedback appearing within 50 milliseconds per key press
- **SC-002**: 100% of navigation key presses (Up/Down/Home/End/Delete) result in correct preview state changes when workspace mode is active
- **SC-003**: Users can successfully select and switch to any workspace in the preview using only keyboard navigation
- **SC-004**: System handles rapid navigation (10+ key presses per second) without dropping events or becoming unresponsive
- **SC-005**: Navigation state is cleared immediately (within 20ms) when workspace mode is exited

## Assumptions

- **A-001**: The i3pm daemon IPC server infrastructure already exists and supports adding new JSON-RPC methods
- **A-002**: The workspace-preview-daemon already has SelectionManager and NavigationHandler classes implemented (from Feature 059 original work)
- **A-003**: Sway keybindings for navigation keys (Up/Down/Home/End/Delete) already call `i3pm-workspace-mode nav <direction>` and `i3pm-workspace-mode delete`
- **A-004**: The navigation commands are received by i3pm daemon via JSON-RPC but not currently broadcast as events to subscribers
- **A-005**: Standard keyboard repeat rates apply (typical 30-50ms repeat delay after initial 500ms delay)

## Out of Scope

- Creating new keybindings for navigation (already exists)
- Implementing the SelectionManager/NavigationHandler classes (already implemented in workspace-preview-daemon)
- Changing the visual design or layout of the workspace preview overlay
- Adding mouse/touchpad navigation support
- Implementing undo/redo for window close operations
- Multi-selection or bulk operations on multiple workspaces/windows

## Dependencies

- **Feature 042**: Event-Driven Workspace Mode Navigation (provides workspace mode infrastructure and digit event broadcasting pattern)
- **Feature 059**: Interactive Workspace Menu (provides SelectionManager, NavigationHandler, and preview daemon infrastructure)
- **Feature 072**: Unified Workspace Switcher (provides all-windows preview rendering and display logic)
- **Sway IPC**: System must be able to send window focus and close commands to Sway compositor

## Technical Constraints

- Navigation event latency must stay under 50ms to maintain responsive feel (human perception threshold)
- Event broadcasting must not block the main i3pm daemon event loop
- Preview daemon must handle missing or malformed navigation events gracefully
- System must work across all workspace counts (1-70 workspaces)
- Navigation must work consistently across all monitor configurations (1-3 displays)
