# Feature Specification: Interactive Workspace Menu with Keyboard Navigation

**Feature Branch**: `059-interactive-workspace-menu`
**Created**: 2025-11-12
**Status**: Draft
**Input**: User description: "enhance our eww preview dialog to be an interactive menu that will allow me to select items and go to that workspace.  we still want to use the key functionality as is where we press number keys and hit enter to get the workspace, but we also want to be able to press down and up and performa actions on a specific window/workspace, such as "go to workspace" and "close""

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Navigate Window List with Arrow Keys (Priority: P1)

Users can press Up/Down arrow keys to navigate through the workspace/window list shown in the preview card. A visual cursor (highlight/selection indicator) moves between items, and the current selection is clearly visible.

**Why this priority**: This is the foundation for interactive menu functionality. Without keyboard navigation, users cannot select specific items to perform actions. It's independently valuable because it enables visual exploration of the window list without requiring workspace number memorization. This is the minimum viable product that transforms the static preview into an interactive menu.

**Independent Test**: Can be fully tested by entering workspace mode, pressing arrow keys, and verifying that a selection cursor moves between list items. Delivers value by allowing users to visually browse their workspace layout before deciding where to navigate.

**Acceptance Scenarios**:

1. **Given** preview card shows all windows grouped by workspace, **When** user presses Down arrow, **Then** first workspace group heading becomes highlighted/selected
2. **Given** first workspace group is selected, **When** user presses Down arrow, **Then** selection moves to first window under that workspace
3. **Given** last window in workspace 1 is selected, **When** user presses Down arrow, **Then** selection moves to next workspace group heading (workspace 2)
4. **Given** selection is on last item in preview, **When** user presses Down arrow, **Then** selection wraps around to first item (circular navigation)
5. **Given** third item is selected, **When** user presses Up arrow, **Then** selection moves to second item
6. **Given** first item is selected, **When** user presses Up arrow, **Then** selection wraps around to last item in preview
7. **Given** preview shows 50+ items with scrolling, **When** user navigates beyond visible area, **Then** preview card auto-scrolls to keep selection visible
8. **Given** selection is on a window item, **When** user types workspace digits (e.g., "23"), **Then** preview filters to workspace 23 AND selection resets to first item in filtered list

---

### User Story 2 - Navigate to Selected Workspace (Priority: P2)

Users can press Enter while a workspace or window is selected to navigate to that workspace. If a workspace heading is selected, navigate to that workspace. If a window is selected, navigate to the workspace containing that window and focus that window.

**Why this priority**: This builds on P1 (arrow key navigation) and enables the primary use case: navigating to a specific location using visual selection instead of typing digits. It's independently valuable because it provides an alternative navigation method for users who prefer visual browsing over numeric shortcuts.

**Independent Test**: After implementing P1, test by selecting different items with arrow keys and pressing Enter. Verify correct workspace navigation and window focus. Delivers value by completing the "visual navigation" workflow.

**Acceptance Scenarios**:

1. **Given** "WS 5 (2 windows)" workspace heading is selected, **When** user presses Enter, **Then** focus switches to workspace 5 and preview card closes
2. **Given** individual window "Firefox" in workspace 3 is selected, **When** user presses Enter, **Then** focus switches to workspace 3 AND window "Firefox" receives focus
3. **Given** selection is on workspace heading for workspace 23, **When** user presses Enter, **Then** navigates to workspace 23 (same behavior as typing "23" + Enter in current implementation)
4. **Given** user has typed "5" to filter to workspace 5, selection on first window, **When** user presses Enter, **Then** navigates to workspace 5 and focuses selected window
5. **Given** no item is selected (e.g., just entered mode), **When** user presses Enter, **Then** executes current default behavior (navigate to accumulated_digits workspace if any)

---

### User Story 3 - Close Selected Window (Priority: P3)

Users can press a dedicated key (e.g., Delete, Backspace, or "c" for close) while a window is selected to close that window without leaving workspace mode. The window disappears from the preview list immediately, and selection moves to the next item.

**Why this priority**: This adds window management capabilities to the interactive menu, but is lower priority because closing windows can already be done after navigating to them. It's a convenience enhancement that allows users to clean up their workspace layout without multiple navigation steps.

**Independent Test**: After implementing P1, test by selecting a window with arrow keys and pressing the close key. Verify window closes and preview updates. Works independently because it leverages existing Sway IPC window close commands.

**Acceptance Scenarios**:

1. **Given** window "Ghostty" in workspace 1 is selected, **When** user presses Delete key, **Then** Ghostty window closes AND preview list updates to remove that entry AND selection moves to next window
2. **Given** workspace heading "WS 5 (2 windows)" is selected, **When** user presses Delete key, **Then** nothing happens (cannot close workspace headings, only windows)
3. **Given** last window in workspace 23 is selected and closed, **When** Delete is pressed, **Then** window closes AND workspace heading shows "WS 23 (0 windows)" or is removed from list
4. **Given** only one window remains in preview (across all workspaces), **When** that window is selected and deleted, **Then** window closes AND preview shows "No windows open" message
5. **Given** user closes a window, **When** preview updates, **Then** workspace mode remains active (does not exit, allowing multiple deletions)
6. **Given** filtered workspace view (e.g., typed "5" to show only WS 5), **When** user deletes a window, **Then** preview updates to reflect new window count for WS 5

---

### User Story 4 - Visual Selection Feedback with Catppuccin Theme (Priority: P2)

The selected item in the preview card has clear visual distinction using the unified Catppuccin Mocha color palette (Feature 057). Selection highlight uses accent color (e.g., blue/mauve) with subtle background change, ensuring readability across all theme states.

**Why this priority**: This is essential UX that makes P1 (arrow navigation) actually usable. Without clear visual feedback, users cannot tell which item is selected. It's independently valuable and must be completed before P1 is useful, but is separated for clarity in testing.

**Independent Test**: After implementing P1, verify selection highlight renders correctly with proper contrast and theme consistency. Test with all-windows view and filtered workspace view.

**Acceptance Scenarios**:

1. **Given** preview card is visible with selection on "WS 1" heading, **When** user views the preview, **Then** "WS 1" heading has highlighted background using Catppuccin blue (#89b4fa) with 20% opacity
2. **Given** selection is on a window item "Firefox", **When** user views the preview, **Then** window row has highlighted background and text color changes to white (#cdd6f4) for readability
3. **Given** selection moves from item A to item B, **When** arrow key is pressed, **Then** item A highlight disappears AND item B highlight appears with smooth transition (0.1s)
4. **Given** preview shows 30 items with selection at position 25, **When** selection is not in visible scroll area, **Then** preview auto-scrolls to center selection in viewport
5. **Given** workspace mode is in "goto" mode (CapsLock), **When** item is selected, **Then** selection highlight is blue (#89b4fa)
6. **Given** workspace mode is in "move" mode (CapsLock+Shift), **When** item is selected, **Then** selection highlight is yellow/peach (#fab387) to indicate move operation

---

### Edge Cases

- **What happens when user types digits while navigating with arrow keys?**
  - Digit input takes precedence and resets selection
  - Preview filters to typed workspace number
  - Selection resets to first item in filtered list
  - Allows seamless switching between numeric and visual navigation modes

- **How does system handle closing the focused window?**
  - If selected window is currently focused, close it normally
  - Focus automatically moves to next window in workspace (Sway default behavior)
  - Preview updates to remove closed window
  - Selection moves to next item in list

- **What happens when user presses Enter with no selection?**
  - Falls back to current Feature 072 behavior: navigate to `accumulated_digits` workspace
  - If no digits typed, does nothing (or shows error message)
  - Maintains backward compatibility with numeric-only workflow

- **How does system handle window close failures (app blocking close)?**
  - If window doesn't close within 500ms, show error indicator next to item
  - Selection remains on failed item (allows retry)
  - Error message: "Failed to close [app_name]" in preview footer

- **What happens if all windows are closed via Delete key?**
  - Preview updates to show "No windows open" message
  - Workspace mode remains active (does not auto-exit)
  - User must press Escape to exit, or type workspace digits to navigate

- **How does selection behave when preview content changes (e.g., workspace filter)?**
  - Selection resets to first item in new filtered list
  - If filter results in empty list, show "No windows in workspace N" message
  - Selection state is cleared (no item selected)

- **What happens when user mixes arrow navigation with ":" project mode?**
  - Typing ":" clears current selection state
  - Switches to project search mode (Feature 072)
  - Arrow keys could navigate project list (future enhancement, not in this spec)
  - For now, ":" disables arrow navigation (only fuzzy text search)

- **How does system handle preview card with 100+ items?**
  - Arrow navigation works across all items regardless of count
  - Preview card scrolls to keep selection visible (GTK ScrolledWindow)
  - Performance target: <10ms per arrow key press for selection update
  - Use virtualized rendering if performance degrades (GTK best practices)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support Up/Down arrow key navigation through all items in preview card (workspace headings and window items)
- **FR-002**: System MUST visually highlight the currently selected item with distinct background color and text styling
- **FR-003**: System MUST support circular navigation (Down on last item wraps to first, Up on first item wraps to last)
- **FR-004**: System MUST auto-scroll preview card to keep selected item visible when navigating beyond viewport
- **FR-005**: System MUST allow Enter key to navigate to workspace of selected item (workspace heading OR window)
- **FR-006**: System MUST focus the selected window when Enter is pressed on a window item
- **FR-007**: System MUST support Delete key to close selected window (no effect on workspace headings)
- **FR-008**: System MUST update preview card immediately after window close to remove deleted item
- **FR-009**: System MUST move selection to next item after closing a window
- **FR-010**: System MUST reset selection to first item when user types workspace digits (filtering preview)
- **FR-011**: System MUST preserve existing numeric navigation workflow (typing digits + Enter) as fallback when no selection exists
- **FR-012**: System MUST render selection highlight using Catppuccin Mocha theme colors (blue #89b4fa for goto, yellow #fab387 for move mode)
- **FR-013**: System MUST update selection highlight within 10ms of arrow key press for responsive feedback
- **FR-014**: System MUST show error indicator if window close fails (app blocks close request)
- **FR-015**: System MUST maintain workspace mode active after closing windows (allow multiple deletions without re-entering mode)
- **FR-016**: System MUST clear selection state when switching to project mode (typing ":")
- **FR-017**: System MUST handle empty preview state ("No windows open") gracefully with no selectable items
- **FR-018**: System MUST support Home key to jump to first item and End key to jump to last item (optional convenience)

### Key Entities

- **Selection State**: Represents currently selected item in preview card with attributes: selected index (0-based position in flattened list), item type (workspace_heading | window), workspace number, window ID (if window selected), visible (boolean)
- **Navigable Item**: Represents a selectable item in preview (either workspace heading or window) with attributes: item type, display text, workspace number, window ID (if window), icon path, position index, selectable (boolean)
- **Preview List Model**: Flattened list representation of grouped workspace/window structure for navigation with attributes: items (array of Navigable Items), current selection index, total item count, scroll position

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can navigate through a preview list of 50+ items using arrow keys with selection update latency <10ms per keystroke
- **SC-002**: Users can successfully navigate to any workspace or window by selecting it with arrows and pressing Enter, with 100% navigation accuracy
- **SC-003**: Users can close multiple windows sequentially without leaving workspace mode, with preview updating within 100ms after each close operation
- **SC-004**: Selection highlight is visually distinct with sufficient contrast ratio (WCAG AA: 4.5:1 for text, 3:1 for background) across all Catppuccin theme variants
- **SC-005**: Arrow navigation maintains backward compatibility: existing numeric workflow (digits + Enter) continues to function identically when user does not use arrows
- **SC-006**: System handles edge cases gracefully: circular navigation wraps correctly, empty states show appropriate messages, close failures display error feedback
- **SC-007**: Preview card auto-scrolling keeps selected item visible within 50ms of arrow key navigation beyond viewport bounds
- **SC-008**: Users can switch seamlessly between arrow navigation and numeric input: typing digits resets selection and filters preview without errors

## Assumptions

- **A-001**: Eww (ElKowar's Wacky Widgets) supports keyboard event handling for arrow keys via GTK event listeners
- **A-002**: GTK ScrolledWindow provides smooth auto-scrolling API to programmatically adjust scroll position
- **A-003**: Flattening grouped workspace/window structure into linear array for navigation adds negligible latency (<5ms for 100 windows)
- **A-004**: Sway IPC `[con_id=N] kill` command response time is <100ms for closing windows
- **A-005**: Users understand Delete key convention for closing windows (common in file managers and application menus)
- **A-006**: Selection state can be maintained in workspace-preview-daemon Python process without persistent storage
- **A-007**: Catppuccin blue (#89b4fa) and yellow (#fab387) provide sufficient visual distinction for goto vs move mode selection
- **A-008**: Arrow key navigation does not conflict with existing Sway keybindings (arrows not bound in workspace mode)

## Out of Scope

- **Mouse click selection**: Preview card remains keyboard-only; no clicking on items to select or navigate
- **Multi-selection**: Users cannot select multiple windows at once (e.g., Shift+Arrow for bulk operations)
- **Drag-and-drop reordering**: Window list order is fixed by workspace number; no drag-to-rearrange
- **Custom action keybindings**: Close action is fixed to Delete key; no user-configurable action shortcuts
- **Arrow navigation in project mode**: Project search (after typing ":") remains fuzzy-text-only; arrow keys do not navigate project list
- **Window minimize/maximize actions**: Only close operation supported; no other window state management from preview
- **Keyboard shortcuts shown in preview UI**: No visual indicators like "Press Delete to close" (user must discover via documentation)
- **Selection persistence across mode exits**: Selection state resets when workspace mode exits; not preserved on re-entry
- **Horizontal navigation (Left/Right arrows)**: Navigation is strictly vertical (Up/Down); Left/Right keys have no effect
- **Type-ahead search within preview**: No filtering by typing window names; only workspace digit filtering (existing Feature 072 behavior)
- **Undo for closed windows**: Once window is closed via Delete, cannot be undone from preview card
- **Batch actions**: No "close all windows in workspace" or "move all windows" operations from preview menu
