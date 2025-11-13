# Feature Specification: Eww Interactive Menu Stabilization

**Feature Branch**: `073-eww-menu-stabilization`
**Created**: 2025-11-13
**Status**: Phase 3 Complete - MVP Operational (User Story 1 deployed)
**Input**: User description: "let's create a new feature that stabilizes the functionality of our eww menu. research eww to make sure we're using the native functionality/components where possible to make sure we're using reliable/tested functionality. we want the menu to add interactivity and provide per-window actions. we want a great user experience so research the best way to represent various actions that can be performed for a window, using keyboard navigation/presses. some of the actions are 'focus window', close window, move window, etc. we should reference the most common sway related actions that a user would want to perform; we still want our ability to press keys (numbers for workspaces, letters for projects), but we also want navigation of the menu via arrow keys, and we want keyboard shortcuts from the menu. perhaps we should have the ability to stay in the menu to do multiple actions. for instance, close multiple windows, etc. research eww to see what functionality is native to eww or has recommended best practices and we should try to use that approach where possible"

## User Scenarios & Testing

### User Story 1 - Reliable Window Close Operation (Priority: P1)

Users need to close windows from the workspace preview menu without failures or inconsistent behavior. Currently, pressing Delete when a window is selected doesn't work reliably, which breaks the user's flow and forces them to use alternative methods.

**Why this priority**: This is the most fundamental window action. If users can't reliably close windows through the menu, they lose trust in the entire interface and will avoid using it.

**Independent Test**: Can be fully tested by entering workspace mode (CapsLock), navigating to any window with arrow keys, pressing Delete, and verifying the window closes within 500ms. Delivers immediate value by enabling single-action window cleanup.

**Acceptance Scenarios**:

1. **Given** workspace mode is active with multiple windows visible, **When** user navigates to a window with arrow keys and presses Delete, **Then** the selected window closes within 500ms and disappears from the preview list
2. **Given** a window with unsaved changes is selected, **When** user presses Delete, **Then** the window manager's standard close confirmation appears (if configured) or the window refuses to close gracefully with a notification
3. **Given** a window was just closed via Delete, **When** the window disappears, **Then** the selection automatically moves to the next logical item (next window or previous if at end)
4. **Given** keyboard input is being captured by the Eww window, **When** Delete key is pressed, **Then** the Sway keybinding fires correctly and the daemon receives the delete event

---

### User Story 2 - Multi-Action Workflow Support (Priority: P2)

Users want to perform multiple window management actions in a single menu session without needing to re-enter workspace mode each time. For example, closing 3-5 unneeded windows in quick succession or moving multiple windows to different workspaces.

**Why this priority**: Enables power users to batch window management tasks efficiently. Reduces friction from repeatedly entering/exiting workspace mode for related actions.

**Independent Test**: Enter workspace mode, close two windows consecutively (Delete → navigate → Delete), then exit with Escape. Menu should remain open throughout, delivering value by reducing repetitive mode transitions.

**Acceptance Scenarios**:

1. **Given** workspace mode is active and a window is selected, **When** user closes the window with Delete, **Then** the menu remains open with selection automatically moved to the next item
2. **Given** user has closed 3 windows in succession, **When** they press Escape, **Then** workspace mode exits cleanly without state corruption
3. **Given** user navigates to a workspace heading (not a window), **When** they press Delete, **Then** no action occurs (only windows can be closed, not workspace headers)
4. **Given** all windows in the menu have been closed, **When** the last window closes, **Then** the menu automatically exits workspace mode

---

### User Story 3 - Visual Feedback for Available Actions (Priority: P2)

Users need to know what keyboard shortcuts are available in the workspace preview menu without memorizing them or consulting documentation. Visual hints should guide them toward supported actions like Delete (close), Enter (navigate), and arrow keys.

**Why this priority**: Improves discoverability and reduces cognitive load. New users can learn the interface organically, and experienced users get confirmation of available actions.

**Independent Test**: Open workspace preview menu and verify that a help text footer displays showing "↑/↓ Navigate | Enter Select | Delete Close | Esc Cancel". Value is delivered immediately through self-documenting UI.

**Acceptance Scenarios**:

1. **Given** workspace mode is entered, **When** the preview menu appears, **Then** a footer displays keyboard shortcuts in a consistent, readable format
2. **Given** the help text is displayed, **When** user hovers over or focuses on a workspace heading, **Then** the "Delete Close" hint remains visible but only applies to windows (constraint noted visually or contextually)
3. **Given** multiple monitors are in use, **When** the preview menu appears on any monitor, **Then** the help text footer is positioned consistently (bottom of preview card)

---

### User Story 4 - Additional Per-Window Actions (Priority: P3)

Users want to perform common Sway window actions directly from the workspace preview menu, such as:
- Move window to another workspace
- Toggle window floating/tiling
- Resize window presets
- Focus window in split container
- Mark/unmark window for later reference

**Why this priority**: Extends menu functionality beyond basic navigation and close operations. Enables the workspace preview to become a full window management hub rather than just a navigator.

**Independent Test**: Implement one action (e.g., "M" key to move window to typed workspace number). Test by selecting a window, pressing M, typing workspace digits, pressing Enter, and verifying the window moved. Each action can be tested independently.

**Acceptance Scenarios**:

1. **Given** a window is selected in the preview menu, **When** user presses a designated action key (e.g., M for move, F for float toggle), **Then** the menu enters a sub-mode showing relevant prompts (e.g., "Type workspace number: _")
2. **Given** user initiated a move operation on a window, **When** they type a workspace number and press Enter, **Then** the window moves to that workspace and the preview updates to reflect the change
3. **Given** user initiated a float toggle operation, **When** they press F, **Then** the window toggles between floating and tiling states within 200ms
4. **Given** multiple actions are available, **When** user presses an unbound key, **Then** no action occurs (graceful handling of invalid input)

---

### User Story 5 - Project Navigation from Menu (Priority: P3)

Users want to switch to project mode from within the workspace preview menu by typing a ":" prefix followed by project search letters, maintaining the unified navigation paradigm.

**Why this priority**: Provides seamless transition between workspace navigation and project navigation without exiting to default mode. Completes the unified navigation mental model.

**Independent Test**: Enter workspace mode, type ":", verify UI switches to project search mode, type project letters (e.g., "ni" for nixos), press Enter, and verify project switches. Delivers value by unifying navigation flows.

**Acceptance Scenarios**:

1. **Given** workspace mode is active with preview menu open, **When** user types ":", **Then** the menu transitions to project search mode showing available projects
2. **Given** project search mode is active, **When** user types letters matching a project name, **Then** matching projects are filtered and highlighted in real-time
3. **Given** a project is selected in search mode, **When** user presses Enter, **Then** the system switches to that project and exits workspace mode
4. **Given** project search mode shows no matches, **When** user has typed invalid letters, **Then** a "No projects found" message appears with option to press Escape to return to workspace mode

---

### Edge Cases

- **What happens when the Eww window type blocks keyboard input?** The current issue where windowtype "normal" intercepts Delete key presses before Sway can process the keybinding. Solution: Use windowtype "dock" to pass keyboard events through to the window manager.

- **How does the system handle rapid Delete key presses?** If user presses Delete multiple times in quick succession (< 100ms apart), only one delete event should be processed per window to prevent race conditions or duplicate close attempts.

- **What happens when a window refuses to close?** Some windows block close operations (unsaved changes, critical system windows). The system should detect this, show a notification explaining why closure failed, and keep the window in the preview list.

- **How does selection behave when all windows are closed?** If user closes every window shown in the preview, the menu should automatically exit workspace mode gracefully rather than showing an empty state.

- **What happens when monitors disconnect during menu interaction?** If the monitor displaying the preview window disconnects mid-session, the menu should gracefully close or reposition to the primary monitor without crashing.

- **How are keyboard shortcuts handled during sub-mode operations?** When user enters a sub-mode (e.g., "M" for move window), arrow keys and other shortcuts should either be context-aware (navigate workspace digits) or temporarily disabled to prevent mode confusion.

- **What happens if the workspace-preview-daemon crashes?** The menu should detect daemon unavailability and show a fallback message, or gracefully degrade to basic navigation without per-window actions.

## Requirements

### Functional Requirements

- **FR-001**: System MUST pass keyboard events from Eww window to Sway window manager without interception (using appropriate Eww windowtype configuration)

- **FR-002**: System MUST close the selected window within 500ms when Delete key is pressed while a window is selected in the preview menu

- **FR-003**: System MUST keep the preview menu open after a window close operation completes, automatically moving selection to the next logical item

- **FR-004**: System MUST prevent Delete operations on workspace headings (only windows can be closed)

- **FR-005**: System MUST display keyboard shortcut help text in the preview menu footer showing available actions (Navigate, Select, Close, Cancel)

- **FR-006**: System MUST handle window close failures gracefully, showing a notification when a window refuses to close and keeping it in the preview list

- **FR-007**: System MUST automatically exit workspace mode when the last window in the preview is closed

- **FR-008**: System MUST debounce rapid Delete key presses to process one delete operation per window (minimum 100ms between operations)

- **FR-009**: System MUST maintain visual selection state consistently across window close operations (selected item should remain visually distinct)

- **FR-010**: System MUST support extended per-window actions (move, float toggle, resize presets, focus, mark) via designated keyboard shortcuts from the preview menu

- **FR-011**: System MUST provide visual feedback when entering a sub-mode operation (e.g., "Type workspace number: _" prompt when moving windows)

- **FR-012**: System MUST allow users to cancel any sub-mode operation with Escape key, returning to normal workspace mode selection

- **FR-013**: System MUST support project search mode transition via ":" prefix while in workspace mode

- **FR-014**: System MUST filter project results in real-time as user types project search letters

- **FR-015**: System MUST use Eww's daemon communication patterns (defvar + eww update CLI) for state management to maintain <20ms update latency

- **FR-016**: System MUST handle daemon crashes gracefully, showing fallback UI or degrading to basic navigation without blocking user workflow

### Key Entities

- **Window Action**: Represents an operation that can be performed on a selected window (close, move, float toggle, resize, focus, mark). Each action has a keyboard shortcut, visual label, validation rules (e.g., close only works on windows), and execution handler.

- **Selection State**: Tracks which item is currently selected in the preview menu (workspace heading index or window index), selection type (heading vs window), navigation history (for Home/End jumps), and whether a sub-mode is active (move, float, etc.).

- **Keyboard Event Flow**: Maps physical key presses to actions through the chain: Sway keybinding → CLI command → i3pm daemon IPC → workspace-preview-daemon handler → Eww UI update. Critical that Eww window configuration allows keyboard events to reach Sway.

- **Sub-Mode Context**: When user initiates a multi-step action (e.g., move window), captures temporary state like target workspace digits, original window ID, mode type (move/resize/mark), and provides cancel capability.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can close selected windows via Delete key with 100% success rate across 50+ test cases (no keyboard event interception failures)

- **SC-002**: Window close operations complete within 500ms from Delete keypress to window disappearing from preview list (measured at p95)

- **SC-003**: Users can perform 5 consecutive window close actions in a single menu session in under 10 seconds (average 2 seconds per close including navigation)

- **SC-004**: 90% of new users discover Delete key functionality within 30 seconds of viewing the preview menu (measured through help text visibility testing)

- **SC-005**: Zero workspace mode crashes or state corruption after performing 20+ multi-action workflows (close/navigate/close sequences)

- **SC-006**: Keyboard shortcut help text loads and displays within 50ms of menu appearing (no noticeable delay)

- **SC-007**: Extended window actions (move, float toggle, etc.) complete within 2 seconds from key press to visible state change

- **SC-008**: Project search mode transition (:prefix) provides filtered results within 100ms of typing each character

- **SC-009**: System recovers gracefully from daemon crashes within 3 seconds, either restoring functionality or showing clear fallback UI

- **SC-010**: 95% reduction in GitHub issues related to "Delete key not working" or "menu keyboard input broken" after deployment

## Assumptions

- **Keyboard Event Handling**: Eww's "dock" windowtype will pass keyboard events through to Sway without interception, as indicated by Eww maintainer recommendations and community practices.

- **Python Daemon Architecture**: The existing workspace-preview-daemon architecture (Python 3.11+, i3ipc.aio) is the optimal approach based on Eww limitations, and will remain the foundation for extended functionality.

- **Performance Target**: <20ms state update latency for preview menu updates is achievable using `defvar` + `eww update` CLI pattern (already demonstrated in Feature 072).

- **Sway Keybinding Availability**: Keybindings in workspace mode ("→ WS" and "⇒ WS" modes) can be freely assigned without conflicts with other system shortcuts.

- **User Familiarity**: Users are already familiar with CapsLock/Ctrl+0 to enter workspace mode and arrow key navigation, so adding Delete and other shortcuts builds on existing mental models.

- **Single Monitor Focus**: While multi-monitor support exists, the primary testing and UX design will focus on single-monitor workflows, with multi-monitor as a validated edge case.

- **GTK3 Availability**: Eww's GTK3 CSS engine provides sufficient styling capabilities for visual feedback (highlights, help text, sub-mode prompts) without requiring custom rendering.

## Dependencies

- **Feature 059 (Interactive Workspace Menu)**: This feature directly extends and stabilizes the existing workspace preview menu implementation. The current NavigationHandler and SelectionManager classes are foundational.

- **Feature 072 (Unified Workspace Switcher)**: Relies on the existing daemon IPC architecture and workspace preview rendering system. Any changes must maintain compatibility with all-windows preview and filtering.

- **Sway Window Manager**: Requires Sway IPC support for window manipulation commands (close, move, float toggle) and keybinding subscription.

- **workspace-preview-daemon**: Python daemon must remain responsive and handle new action types. Any crashes or hangs will break menu functionality.

- **Eww (ElKowar's Wacky Widgets)**: Version 0.4+ required for windowtype configuration options and defvar/update CLI patterns.

## Out of Scope

- **Advanced window resize controls**: Pixel-perfect window resizing via drag-and-drop or numeric input is out of scope. Only preset sizes (small/medium/large) will be supported if resize actions are implemented.

- **Window thumbnails/screenshots**: Preview menu shows app names and icons, not live window thumbnails or screenshots. This would require screen capture integration beyond current scope.

- **Mouse interaction**: All interactions remain keyboard-driven. Mouse clicks, hover effects, or drag-and-drop are explicitly out of scope.

- **Custom action macros**: Users cannot define custom action sequences (e.g., "close all Firefox windows"). Only predefined Sway window actions are supported.

- **Window grouping/tagging**: Advanced window organization features like custom tags, groups, or saved layouts are out of scope. Only move to workspace and project switching are supported.

- **Integration with non-Sway window managers**: This feature is Sway-specific. i3 compatibility is not guaranteed and is out of scope.

- **Accessibility features**: Screen reader support, high-contrast themes, and other accessibility features are not included in this scope (future enhancement).

- **Undo/redo operations**: No ability to undo window closes or reverse other actions. Users must rely on application-level recovery mechanisms.
