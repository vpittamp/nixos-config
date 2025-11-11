# Feature Specification: Workspace Mode Visual Feedback

**Feature Branch**: `058-workspace-mode-feedback`
**Created**: 2025-11-11
**Status**: Draft
**Input**: User description: "create a new feature.  we currenly have a "workspace mode" that is activated via a keybinding, and then the user can prese a series of numbers that correspond to a workspace, and then hit enter to change focus to the workspace.  currently we don't have a good mechanism for the user to have visual feedback for what workspace they will move to when they press enter.  on hetzner-sway, we use keypad events to show a notification, but this doesn't work well or look good.  i want to use our new icon workspaces to improve the functionality.  the objective is to give the user a visual indicator of what workspace they have selected based on what digits they have pressed.  perhaps when key(s) that correspond to an active workspace are pressed, the workspace button lights up in a way that denotes that it is "pending" and will be focused if they hit enter?  or perhaps the a version of the button is displayed on the screen or in teh bottom or top bar, etc.  explore different strategies to create a fantastic user experience, and we can consider improving the "workspace mode" functionality as needed to do so."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Workspace Button Preview Highlighting (Priority: P1)

When a user enters workspace mode and types digits corresponding to a workspace, the workspace bar button for that workspace highlights with a distinctive "pending" visual state, showing exactly which workspace will be focused when Enter is pressed.

**Why this priority**: This is the core functionality that addresses the user's primary complaint - lack of visual feedback. It leverages the existing workspace bar UI that users are already familiar with, making it the most natural and intuitive solution.

**Independent Test**: Can be fully tested by entering workspace mode (CapsLock), typing digits (e.g., "23"), and visually confirming that workspace 23's button shows a pending highlight. Delivers immediate value by showing workspace destination before navigation.

**Acceptance Scenarios**:

1. **Given** workspace mode is inactive, **When** user presses CapsLock to enter goto mode and types "5", **Then** workspace 5's button in the workspace bar shows a pending highlight (distinct from focused/visible states)

2. **Given** workspace mode is active with no digits entered, **When** user types "2" then "3", **Then** workspace 23's button shows pending highlight (workspace 2's button stops highlighting after "3" is typed)

3. **Given** workspace mode is active with digits "23" entered and workspace 23 button highlighted, **When** user presses Enter, **Then** focus switches to workspace 23 and the pending highlight is removed

4. **Given** workspace mode is active with digits "5" entered and workspace 5 button highlighted, **When** user presses Escape, **Then** workspace mode exits and the pending highlight is removed without changing workspace

5. **Given** user types "99" (non-existent workspace), **When** looking at workspace bar, **Then** no button shows pending highlight (invalid workspace)

---

### User Story 2 - Target Workspace Preview Card (Priority: P2)

When a user enters workspace mode and types digits, a preview card appears on screen showing the target workspace number, icon, and application name (if workspace has windows), positioned near the workspace bar for easy reference.

**Why this priority**: Provides richer contextual information than button highlighting alone, especially useful for confirming the correct workspace when multiple workspaces have similar applications. Secondary to button highlighting because it requires more screen real estate.

**Independent Test**: Can be tested independently by entering workspace mode, typing digits, and verifying a preview card appears showing workspace details. Delivers value by showing what applications are running on the target workspace before navigation.

**Acceptance Scenarios**:

1. **Given** workspace mode is active, **When** user types "3" and workspace 3 contains Firefox, **Then** preview card appears showing "Workspace 3 | Firefox" with Firefox icon

2. **Given** workspace mode is active with preview card showing "Workspace 3", **When** user types another digit "5", **Then** preview card updates to show "Workspace 35" (or "Workspace 5" if starting fresh)

3. **Given** workspace mode is active with preview card visible, **When** user presses Enter to navigate to workspace, **Then** preview card fades out smoothly (animation duration <300ms)

4. **Given** workspace mode is active, **When** user types "7" and workspace 7 is empty, **Then** preview card shows "Workspace 7 | Empty" with generic workspace icon

---

### User Story 3 - Notification Badge on Workspace Button (Priority: P2)

When a workspace has urgent windows or notifications, display a small circular badge (Apple-style red dot) in the top-right corner of the workspace button using Eww's native overlay widget.

**Why this priority**: Leverages native Eww overlay widget for clean, performant badge UI without custom CSS hacks. Provides at-a-glance awareness of which workspaces need attention. Secondary to pending highlight because notification badges are less time-sensitive than navigation feedback.

**Independent Test**: Can be tested by triggering an urgent window event on a workspace and verifying a red badge dot appears on the workspace button. Delivers value by making urgent workspace states more visually prominent than the current subtle red background.

**Acceptance Scenarios**:

1. **Given** workspace 5 has an urgent window, **When** looking at workspace bar, **Then** workspace 5 button shows a red circular badge in the top-right corner (8px diameter)

2. **Given** workspace 5 has a badge and user focuses workspace 5, **When** the urgent state clears, **Then** the badge disappears with a smooth fade-out animation (<200ms)

3. **Given** workspace 5 has a badge and is pending navigation, **When** user types "5" in workspace mode, **Then** both the pending highlight and badge are visible (badge renders on top via overlay)

4. **Given** workspace 5 has multiple urgent windows, **When** looking at workspace bar, **Then** badge shows a single red dot (no count indicator in MVP)

5. **Given** workspace 5 has a badge, **When** user hovers over workspace 5 button, **Then** tooltip shows "Workspace 5 · Firefox (urgent)" or similar text indicating urgent state

---

### User Story 4 - Multi-Digit Workspace Confidence Indicator (Priority: P3)

When a user is typing multi-digit workspace numbers (e.g., 23, 52), provide visual confirmation that the system is accumulating digits correctly, showing each digit as it's entered before the final workspace is resolved.

**Why this priority**: Reduces user anxiety when typing multi-digit workspaces, but is less critical than showing the final target workspace. Can be addressed with simple digit echo in the preview card.

**Independent Test**: Can be tested by entering workspace mode, typing multiple digits slowly (e.g., "2" pause "3"), and verifying that both digits are displayed. Delivers value by confirming user input is being captured correctly.

**Acceptance Scenarios**:

1. **Given** workspace mode is active, **When** user types "2", **Then** preview card shows "2_" (underscore indicates more digits can be entered)

2. **Given** workspace mode is active with "2_" displayed, **When** user types "3", **Then** preview card updates to show "Workspace 23" (underscore removed, final workspace resolved)

3. **Given** workspace mode is active, **When** user types "0" followed by "5", **Then** preview card shows "5" (leading zeros ignored per Feature 042 specification)

4. **Given** workspace mode is active with "5" displayed, **When** user waits >500ms without typing, **Then** preview card shows "Workspace 5" (auto-resolves single digit after short delay)

---

### Edge Cases

- What happens when user types digits for a workspace number >70 (maximum workspace)? → No highlight appears, preview card shows "Invalid workspace (>70)"
- How does system handle rapid digit entry (e.g., "23" typed in <100ms)? → All digits accumulate correctly, preview updates on each keystroke with <50ms latency
- What happens when workspace mode is active and user switches to a different workspace via mouse/trackpad? → Workspace mode exits automatically, pending highlights clear
- How does preview card handle workspaces with multiple windows (e.g., workspace 3 has Firefox, VS Code, Terminal)? → Preview card shows first window's icon and "Firefox +2 more" or similar count indicator
- What happens when user enters move mode (Shift+CapsLock) instead of goto mode? → Preview card shows "Move to Workspace X" header instead of "Workspace X", button highlighting works the same way
- How does preview card position itself on multi-monitor setups? → Preview card appears on the monitor where the target workspace will open (based on workspace-to-monitor assignment rules from Feature 001)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST highlight the workspace button in the workspace bar when user types digits corresponding to that workspace in workspace mode
- **FR-002**: Pending highlight visual state MUST be visually distinct from focused workspace state (different color/effect)
- **FR-003**: Pending highlight visual state MUST be visually distinct from visible-on-other-monitor state
- **FR-004**: System MUST update pending highlight in real-time as user types additional digits (e.g., typing "2" then "3" moves highlight from workspace 2 button to workspace 23 button)
- **FR-005**: System MUST clear pending highlight when user exits workspace mode (via Enter, Escape, or workspace switch)
- **FR-006**: System MUST NOT highlight any button when user types digits corresponding to non-existent workspace (>70 or ≤0)
- **FR-007**: System MUST display a preview card showing target workspace number when user enters workspace mode and types digits
- **FR-008**: Preview card MUST show workspace icon and primary application name if workspace contains windows
- **FR-009**: Preview card MUST show "Empty" status if target workspace has no windows
- **FR-010**: Preview card MUST update within 50ms of each digit keypress
- **FR-011**: Preview card MUST position itself near the workspace bar for easy reference
- **FR-012**: Preview card MUST fade out smoothly when workspace mode exits (animation duration <300ms)
- **FR-013**: System MUST echo digits as they are typed, showing partial input before final workspace is resolved (e.g., "2_" then "Workspace 23")
- **FR-014**: System MUST ignore leading zeros per Feature 042 specification (e.g., "05" resolves to workspace 5)
- **FR-015**: System MUST auto-resolve single-digit input after 500ms delay (optional optimization for single-digit workspaces)
- **FR-016**: System MUST differentiate between goto mode and move mode in preview card header text
- **FR-017**: Preview card MUST appear on the monitor where the target workspace will open (based on workspace-to-monitor assignment from Feature 001)
- **FR-018**: System MUST display a circular notification badge (8px diameter) in the top-right corner of workspace buttons when workspace has urgent windows
- **FR-019**: Notification badge MUST use Eww's native overlay widget to layer badge over workspace button
- **FR-020**: Notification badge MUST be styled with Catppuccin Mocha Red background (#f38ba8) and white border for contrast
- **FR-021**: Notification badge MUST fade out smoothly (animation <200ms) when urgent state clears
- **FR-022**: Notification badge MUST remain visible when workspace button is in pending state (both indicators can coexist)
- **FR-023**: System MUST show single badge dot regardless of number of urgent windows on workspace (no count indicator in MVP)

### Key Entities

- **Pending Workspace State**: The workspace number that will be focused when user presses Enter, derived from accumulated digits in workspace mode
- **Workspace Preview**: Visual card showing workspace number, icon, application name, and empty status
- **Pending Highlight**: Visual state applied to workspace bar button to indicate pending navigation target
- **Notification Badge**: Circular red dot indicator (8px diameter) overlaid on workspace button top-right corner to show urgent windows, implemented using Eww overlay widget

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify target workspace before pressing Enter with 100% accuracy (visual feedback eliminates guesswork)
- **SC-002**: Visual feedback appears within 50ms of typing each digit (real-time responsiveness)
- **SC-003**: Preview card and button highlighting render without visual artifacts or flicker (smooth UI updates)
- **SC-004**: Users successfully navigate to intended workspace on first attempt 95%+ of the time (reduced navigation errors)
- **SC-005**: Workspace mode visual feedback works consistently across single-monitor (M1) and multi-monitor (Hetzner) setups
- **SC-006**: Preview card animations complete within 300ms (fade in/out feel responsive, not sluggish)
- **SC-007**: System handles rapid digit entry (>10 keystrokes/second) without dropping digits or showing incorrect highlights
- **SC-008**: Notification badges render cleanly without layout shifts or overlapping button content (overlay widget prevents layout issues)
- **SC-009**: Badge fade-out animations complete within 200ms (feel snappy when urgent state clears)

## Assumptions

1. **Visual Design Language**: Pending highlight will use a distinct color from the Catppuccin Mocha palette (e.g., yellow/peach for "pending" vs blue for "focused" vs mauve for "visible-on-other-monitor")
2. **GTK CSS Compatibility**: Pending highlight effects will use GTK-compatible CSS properties only (no transform, filter, etc.) per Feature 057 learnings
3. **Preview Card Implementation**: Preview card will be implemented using Eww widget as a floating window, similar to notification approach but with better positioning and styling
4. **Daemon Integration**: Workspace mode state changes will be communicated to workspace bar via IPC (likely extending i3pm daemon workspace-mode module)
5. **Icon Reuse**: Preview card will use the same icon lookup logic as workspace bar (Feature 057) for consistency
6. **Monitor Assignment**: Preview card monitor positioning will use the same workspace-to-monitor rules as Feature 001 (declarative workspace-monitor assignment)
7. **Animation Performance**: CSS transitions will be used for smooth fade effects (GTK supports opacity transitions)
8. **Multi-Window Display**: When workspace has multiple windows, preview card will show icon of first window alphabetically by application name, with count of additional windows
9. **Invalid Input Handling**: Typing invalid workspace numbers (>70, ≤0) will clear any existing highlights and show error state in preview card
10. **Accessibility**: Preview card will have sufficient contrast ratio (WCAG AA minimum 4.5:1) and font size (11pt minimum per workspace bar standards)
11. **Notification Badge Implementation**: Badge uses Eww's native overlay widget to layer circular red dot (8px diameter) on top-right corner of workspace button without requiring complex CSS positioning hacks
12. **Badge Visual Design**: Badge styled with Catppuccin Mocha Red (#f38ba8) background, 2px white border for contrast, border-radius: 50% for perfect circle
13. **Badge State Layering**: Notification badges and pending highlights can coexist (urgent workspace that user is typing digits for shows both yellow pending highlight and red badge dot)

## Dependencies

- **Feature 042**: Event-Driven Workspace Mode Navigation - Provides workspace mode state (active/inactive, digits entered, goto vs move mode)
- **Feature 057**: Workspace Bar Icons - Provides workspace button widgets that need pending highlight, icon lookup logic for preview card
- **Feature 001**: Declarative Workspace-to-Monitor Assignment - Provides workspace-to-monitor mapping for preview card positioning
- **i3pm Daemon**: Needs extension to emit workspace mode state changes via IPC for real-time updates to workspace bar
- **Eww Widget System**: Preview card will be implemented as Eww floating window with GTK CSS styling
