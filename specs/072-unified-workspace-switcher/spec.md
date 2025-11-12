# Feature Specification: Unified Workspace/Window/Project Switcher

**Feature Branch**: `072-unified-workspace-switcher`
**Created**: 2025-11-12
**Status**: Draft
**Input**: User description: "create a spec based on your recommended implementation"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View All Windows on Workspace Mode Entry (Priority: P1)

When a user enters workspace mode (CapsLock on M1, Ctrl+0 on Hetzner), they immediately see a visual list of all windows across all workspaces organized by workspace number. This provides context about the current window layout before filtering or navigating.

**Why this priority**: This is the foundation of the feature - it replaces the current empty state with immediate contextual information. Without this, the other features (filtering, project mode) have no base to build upon. It's the minimum viable product that delivers value: improved discoverability and awareness.

**Independent Test**: Can be fully tested by entering workspace mode and verifying that a preview card appears showing all windows grouped by workspace. Delivers immediate value by helping users understand their current workspace layout.

**Acceptance Scenarios**:

1. **Given** user has windows open on workspaces 1, 5, and 23, **When** user presses CapsLock (or Ctrl+0), **Then** preview card appears showing grouped list: "WS 1 (3 windows)", "WS 5 (2 windows)", "WS 23 (1 window)" with window names under each group
2. **Given** user has 50+ windows across 20 workspaces, **When** user enters workspace mode, **Then** preview card displays within 150ms showing grouped workspace list with scrolling available if content exceeds 600px height
3. **Given** user has no windows open (empty workspaces), **When** user enters workspace mode, **Then** preview card shows "No windows open" message
4. **Given** preview card is showing all windows, **When** user presses Escape, **Then** preview card disappears and workspace mode exits without navigation

---

### User Story 2 - Filter Windows by Workspace Number (Priority: P2)

After seeing all windows, users can type workspace digits (e.g., "2" then "3") to filter the window list to show only workspace 23's windows. This maintains backward compatibility with the current workspace navigation behavior while adding visual context.

**Why this priority**: This builds on P1 (all windows view) and maintains the existing muscle memory of digit-based workspace navigation. It's independently valuable because it helps users confirm they're navigating to the right workspace before pressing Enter.

**Independent Test**: After implementing P1, test by typing digits in workspace mode and verifying the preview card filters to show only the matching workspace's windows. Delivers value by providing visual confirmation before navigation.

**Acceptance Scenarios**:

1. **Given** preview card shows all windows grouped by workspace, **When** user types "2", **Then** preview card filters to show only workspace 2's windows with heading "WS 2 (N windows)"
2. **Given** user has typed "2" (showing WS 2), **When** user types "3", **Then** preview card updates to show workspace 23's windows (multi-digit workspace)
3. **Given** user types "99" (invalid workspace >70), **When** preview card updates, **Then** shows "Invalid workspace number (1-70)" message
4. **Given** preview card shows filtered workspace 5, **When** user presses Enter, **Then** focus switches to workspace 5 and preview card disappears (current behavior preserved)
5. **Given** user has typed "5" (WS 5 showing), **When** user types "0" (making "50"), **Then** preview card updates to show workspace 50 (handles leading zeros correctly)

---

### User Story 3 - Switch to Project Mode with Prefix (Priority: P3)

Users can type a colon ":" prefix at any time during workspace mode to switch to project search mode. The preview card changes from showing windows to showing fuzzy-matched projects as the user types project name characters.

**Why this priority**: This integrates project navigation into the unified switcher, but it's lower priority because the existing project switcher (Win+P) still works. This is a convenience enhancement that provides a unified entry point for all navigation types.

**Independent Test**: After implementing P1, test by typing ":" in workspace mode and verifying the preview switches to project search mode. Works independently because the project search infrastructure already exists (Feature 057 workspace-preview-daemon lines 309-334).

**Acceptance Scenarios**:

1. **Given** preview card shows all windows (P1 implemented), **When** user types ":", **Then** preview card switches to project mode showing "Type project name..." with fuzzy search active
2. **Given** project mode is active, **When** user types "nix", **Then** preview card shows fuzzy-matched projects (e.g., "nixos", "nix-config") with project icons
3. **Given** project mode shows matched project "nixos", **When** user presses Enter, **Then** system switches to nixos project and preview card disappears (existing project switching behavior)
4. **Given** user types ":abc" (project that doesn't exist), **When** preview updates, **Then** shows "No matching projects" message
5. **Given** project mode is active, **When** user presses Escape, **Then** exits workspace mode and returns to normal state without switching projects

---

### Edge Cases

- **What happens when user has 100+ windows across 70 workspaces?**
  - Preview card shows grouped workspace headers with window counts
  - Maximum preview card height is 600px with GTK scrolling enabled
  - Show top 20 workspaces initially, with "... and N more workspaces" footer if >20
  - Filtering by workspace number bypasses the limit (always shows selected workspace fully)

- **How does system handle rapid typing (>10 digits/second)?**
  - Preview card updates are debounced to prevent flicker
  - Last typed state always wins (accumulated_digits processed in order)
  - Target: <50ms latency from keystroke to preview update

- **What happens if workspace-preview-daemon crashes?**
  - Workspace mode continues to work (preview card simply doesn't appear)
  - Digit accumulation and navigation still function (backward compatible)
  - User sees existing status bar indicator but no preview card
  - Daemon auto-restarts via systemd (existing behavior)

- **How does system handle windows with no identifiable app name?**
  - Falls back to window title (leaf.name)
  - If no title, uses workspace number as fallback
  - Icon shows first character of fallback text as symbol

- **What happens when user types ":" in the middle of digits (e.g., "2:3")?**
  - System interprets ":" as immediate mode switch regardless of position
  - "2:3" becomes "project mode with search query '3'"
  - Accumulated workspace digits are discarded when ":" is detected

- **How does system handle project names with digits (e.g., "web3-app")?**
  - Once ":" is typed, all subsequent input is project search (no ambiguity)
  - Digits after ":" are treated as project name characters
  - Example: ":web3" searches for projects matching "web3"

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a preview card within 150ms of user entering workspace mode showing all windows grouped by workspace number
- **FR-002**: System MUST organize window list by workspace number in ascending order with workspace headers showing window count
- **FR-003**: System MUST limit preview card maximum height to 600px with scrolling enabled when content exceeds height
- **FR-004**: System MUST filter window list to show only selected workspace when user types digit(s)
- **FR-005**: System MUST update preview card within 50ms of each digit typed to maintain responsive feedback
- **FR-006**: System MUST support multi-digit workspace numbers (1-70) by accumulating typed digits
- **FR-007**: System MUST validate workspace number range (1-70) and show error message for invalid numbers (0, 71+)
- **FR-008**: System MUST switch to project search mode when user types ":" character at any point during workspace mode
- **FR-009**: System MUST preserve existing workspace navigation behavior: pressing Enter executes navigation, Escape cancels
- **FR-010**: System MUST continue functioning if preview card fails to render (backward compatibility with current workspace mode)
- **FR-011**: System MUST show instructional text in preview card when workspace mode first entered: "Type workspace number to filter, or :project for project mode"
- **FR-012**: System MUST display window information including: window name, application name, icon, and workspace number
- **FR-013**: System MUST handle empty workspaces by showing "No windows open" or omitting from grouped list
- **FR-014**: System MUST clear preview card and exit workspace mode when navigation completes (Enter) or is cancelled (Escape)
- **FR-015**: System MUST support project fuzzy search showing matched projects with icons when in project mode (after ":" prefix)

### Key Entities

- **Window**: Represents an open application window with attributes: window ID, application name, workspace number, icon path, focused state, window title
- **Workspace**: Represents a numbered workspace (1-70) with attributes: workspace number, window count, primary application (topmost/focused window), output/monitor assignment
- **Preview Card**: Visual overlay showing filtered window/workspace list with attributes: visibility state, content type (all windows/filtered workspace/project search), scroll position, height
- **Workspace Mode State**: System state tracking: active/inactive, accumulated digits, mode type (goto/move), target workspace number, preview visibility

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can see all open windows across all workspaces within 150ms of entering workspace mode
- **SC-002**: Preview card updates within 50ms of typing each digit, maintaining responsive visual feedback
- **SC-003**: System handles 100+ windows across 70 workspaces without preview card render time exceeding 150ms
- **SC-004**: Workspace navigation with preview card maintains backward compatibility: existing keyboard shortcuts (CapsLock → digits → Enter) produce identical navigation results to pre-feature behavior
- **SC-005**: Users can successfully filter to any workspace (1-70) and see its window contents before navigating
- **SC-006**: Users can switch to project search mode by typing ":" and see fuzzy-matched results within 100ms
- **SC-007**: Preview card remains usable with 50+ visible entries by providing smooth scrolling within 600px height constraint
- **SC-008**: System gracefully degrades: if preview card component fails, workspace navigation continues to function via existing status bar indicator

## Assumptions

- **A-001**: Existing workspace-preview-daemon infrastructure (Feature 057) can be extended to query all windows on mode entry
- **A-002**: Sway IPC performance is sufficient to query 100+ windows within 50ms budget
- **A-003**: Eww (ElKowar's Wacky Widgets) rendering performance can handle scrollable lists of 50+ items within 150ms
- **A-004**: Users understand colon ":" as a mode-switching prefix (consistent with walker's `;s`, `;p` patterns)
- **A-005**: GTK scrollable window provides acceptable UX for navigating long window lists (no custom scroll implementation needed)
- **A-006**: Preview card can be positioned centered on screen without obscuring critical UI elements (workspace bar, status bar)
- **A-007**: Window identification via I3PM_APP_NAME environment variable (Feature 057) provides sufficient accuracy for window list display
- **A-008**: Existing icon resolution system (icon_resolver.py) covers 70-80% of common applications for preview card icons

## Out of Scope

- **Interactive selection via arrow keys**: Preview card remains visual-only; no keyboard navigation within the list (use walker for interactive window switching if needed)
- **Mouse click selection**: Preview card does not support clicking on windows to switch focus
- **Window preview thumbnails**: Shows app names and icons only, not visual screenshots of window contents
- **Multi-monitor workspace filtering**: Preview shows all workspaces regardless of monitor assignment (filtering is workspace-number-only)
- **Real-time window updates during mode**: Preview card content is snapshot at mode entry; does not update if windows open/close while mode is active
- **Customizable preview card layout**: Grouped-by-workspace layout is fixed; no user configuration options for sorting or grouping
- **Window actions (close, minimize, move)**: Preview is read-only display; no window management operations available from preview card
- **Persistent window search history**: No "recent workspaces" or "frequently visited" ordering; always shows current state only
