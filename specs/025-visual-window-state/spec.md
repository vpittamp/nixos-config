# Feature Specification: Visual Window State Management with Layout Integration

**Feature Branch**: `025-visual-window-state`
**Created**: 2025-10-22
**Status**: Draft
**Input**: User description: "Visual Window State Management with Layout Integration - Implement complete integration including real-time window state visualization using i3 JSON format, visual layout editor with diff capabilities, and enhanced layout save/restore with i3-resurrect pattern adoption"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-Time Window State Monitoring (Priority: P1) 🎯 MVP

Users need to understand the current state of all windows across their multi-monitor i3 setup, including which windows belong to which projects, what's visible vs hidden, and what's on which monitor/workspace.

**Why this priority**: This is the foundation for all other features. Without visibility into current window state, users cannot effectively manage layouts or understand project context.

**Independent Test**: Launch TUI with `i3pm windows --monitor`, verify that all windows are shown in a hierarchical tree view (monitor → workspace → window) with real-time updates when windows are created, destroyed, or moved.

**Acceptance Scenarios**:

1. **Given** user has windows on 2 monitors across 4 workspaces, **When** user runs `i3pm windows --tree`, **Then** system displays ASCII tree showing all windows organized by monitor and workspace
2. **Given** user opens TUI monitor screen, **When** new window is created, **Then** window appears in tree view within 100ms without manual refresh
3. **Given** user switches project context, **When** windows are hidden due to project scoping, **Then** hidden windows appear in separate "Hidden" section with reason displayed
4. **Given** user has windows on multiple monitors, **When** monitor is disconnected, **Then** tree view updates to show windows consolidated on remaining monitors

---

### User Story 2 - Visual Layout Save and Restore (Priority: P2)

Users want to save their current window arrangements and restore them later, with visual feedback showing what will be restored and what's missing.

**Why this priority**: Builds on Story 1 by adding persistence. Users can now save good configurations and recreate them. This is independently valuable even without the diff features.

**Independent Test**: Arrange windows in desired layout, save as "dev-setup", close all windows, run restore command, verify all windows relaunch in original positions.

**Acceptance Scenarios**:

1. **Given** user has arranged windows in desired layout, **When** user presses 's' in window state TUI, **Then** system prompts for layout name and saves current state
2. **Given** user has saved layout "dev-setup", **When** user runs `i3pm layout restore dev-setup`, **Then** system relaunches missing applications and positions existing windows to match saved layout
3. **Given** saved layout has windows not currently running, **When** user views layout in TUI, **Then** system displays which applications need to be launched (marked as "missing")
4. **Given** user restores a layout, **When** restoration completes, **Then** windows appear smoothly without visual flicker (unmapped during restore, remapped after)

---

### User Story 3 - Layout Diff and Comparison (Priority: P3)

Users want to compare their current window arrangement with saved layouts to understand what changed and decide whether to update, create new, or restore old layout.

**Why this priority**: Enhances layout management with decision support. Users can see differences before committing to changes.

**Independent Test**: Modify current layout (add/remove/move windows), run `i3pm layout diff default`, verify diff shows added, removed, moved, and kept windows.

**Acceptance Scenarios**:

1. **Given** user has saved layout "default" and current state differs, **When** user runs `i3pm layout diff default`, **Then** system shows side-by-side comparison with added/removed/moved windows highlighted
2. **Given** user views layout diff in TUI, **When** diff shows missing windows, **Then** user can press 'r' to restore only the missing windows without affecting existing ones
3. **Given** current state has 2 new windows vs saved layout, **When** user views diff, **Then** system prompts "Save as new layout?" or "Update 'default'?" with keyboard shortcuts
4. **Given** user has moved window from WS2 to WS1, **When** diff is displayed, **Then** moved window is shown with both old and new workspace locations

---

### User Story 4 - Enhanced Window Matching and Launch (Priority: P2)

Users want saved layouts to accurately restore windows even when window titles change or when applications need specific launch criteria beyond just window class.

**Why this priority**: Improves layout restore reliability for edge cases (terminal tabs, browser windows, PWAs). Critical for production use but can work with basic matching initially.

**Independent Test**: Save layout with terminal showing specific directory in title, close terminal, restore layout, verify terminal reopens in correct directory despite title mismatch.

**Acceptance Scenarios**:

1. **Given** user saves layout with terminal tabs having unique titles, **When** layout is restored, **Then** each terminal tab is matched by title pattern and recreated with correct working directory
2. **Given** user has browser window with specific role (toolbar vs content), **When** layout is restored, **Then** browser windows are matched by window role, not just window class
3. **Given** user configures custom swallow criteria for an application, **When** that application's window appears during restore, **Then** window is matched using configured criteria (title, role, instance, class)
4. **Given** window appears during restore but doesn't match any placeholder, **Then** system logs unmatched window for user review but continues restoration

---

### User Story 5 - i3-resurrect Layout Migration (Priority: P3)

Users who previously used i3-resurrect want to import their existing saved layouts into i3pm without manual recreation.

**Why this priority**: Enables migration from i3-resurrect. Valuable for adoption but not critical for core functionality.

**Independent Test**: Export i3pm layout to i3-resurrect format, import into vanilla i3 using i3-msg append_layout, verify layout restores correctly.

**Acceptance Scenarios**:

1. **Given** user has i3-resurrect layout file, **When** user runs `i3pm layout import ~/.i3/i3-resurrect/workspace_1_layout.json --project=nixos`, **Then** layout is converted to i3pm format and saved
2. **Given** user has i3pm layout, **When** user runs `i3pm layout export default --format=i3-resurrect`, **Then** system generates pure i3 JSON compatible with vanilla i3 tools
3. **Given** exported i3pm layout (i3-resurrect format), **When** user runs `i3-msg "append_layout <file>"` from vanilla i3, **Then** layout restores correctly without errors
4. **Given** migration from i3-resurrect, **When** user imports all old layouts, **Then** launch commands are automatically discovered from running processes or user prompted for command mappings

---

### Edge Cases

- **Empty workspaces**: What happens when user tries to save layout from workspace with no windows?
  - System prompts "Workspace is empty. Save anyway?" - If yes, saves empty workspace layout that clears workspace on restore

- **Placeholder timeout**: How does system handle windows that never appear during restore (app crashed, command wrong)?
  - After 30 second timeout (configurable), system marks window as "failed to launch" and continues with remaining windows
  - Placeholder remains visible with error indicator until manually closed or retry attempted

- **Concurrent modifications**: What happens when windows change during save operation?
  - Save operation captures atomic snapshot of window state at moment of save command
  - If window closes during save, it's excluded from saved layout
  - If window opens during save, it's excluded (next save will include it)

- **Monitor configuration changes**: How does system handle restoring 3-monitor layout on 2-monitor setup?
  - System consolidates windows from missing monitors onto available monitors using intelligent distribution (primary monitor prioritized)
  - User is warned: "Layout was saved with 3 monitors, you have 2. Windows will be consolidated."
  - Original monitor assignments stored in layout metadata for future restore on full setup

- **Duplicate windows**: What happens when user restores layout but windows already exist?
  - System detects existing windows matching swallow criteria and repositions them instead of launching duplicates
  - User is notified: "Found 3 existing windows, relaunched 2 missing windows"
  - Option to "Close all before restore" to start fresh

- **Permission failures**: How does system handle app launch failures due to permissions?
  - Each failed launch is logged with error message
  - System continues with remaining launches
  - After completion, shows summary: "Restored 8/10 windows, 2 failed" with details

- **Tree view performance**: What happens when user has 100+ windows?
  - Tree view uses virtualization - only visible nodes rendered
  - Collapsible sections (monitors, workspaces) to reduce visual clutter
  - Search/filter capability to find specific windows quickly

- **Real-time update conflicts**: What happens when multiple events occur within milliseconds?
  - Events are debounced with 100ms window - batch updates applied together
  - Tree view updates are atomic - no partial state visible
  - If event stream overwhelms system, drops to manual refresh mode with notification

## Requirements *(mandatory)*

### Functional Requirements

**Window State Visualization**:

- **FR-001**: System MUST display all windows in hierarchical view organized by monitor → workspace → window
- **FR-002**: System MUST show window properties including: class, title, workspace, monitor, project association, marks, floating status, focused status
- **FR-003**: System MUST provide tree view (hierarchical) and table view (sortable, filterable) visualization modes
- **FR-004**: System MUST update window state display in real-time when windows are created, destroyed, moved, or properties change (within 100ms)
- **FR-005**: System MUST distinguish between visible windows (current project) and hidden windows (other projects) with visual indication
- **FR-006**: Users MUST be able to filter window view by: project, monitor, workspace, window class, visible/hidden status
- **FR-007**: System MUST provide CLI command for viewing window state with flags: `--tree` (hierarchical), `--table` (tabular), `--live` (real-time updates), `--json` (export)
- **FR-008**: System MUST support keyboard navigation in tree view: arrow keys to navigate, Enter to focus window, 'c' to collapse/expand nodes

**i3 JSON Format Compatibility**:

- **FR-009**: System MUST use i3's native JSON format as the foundation for window state representation
- **FR-010**: System MUST extend i3 JSON with non-invasive `i3pm` namespace for project-specific metadata (project, classification, hidden status)
- **FR-011**: System MUST allow exporting window state as pure i3 JSON (strip `i3pm` extensions) for compatibility with vanilla i3 tools
- **FR-012**: Exported i3 JSON MUST be importable by vanilla i3 using `i3-msg append_layout` without errors

**Layout Save/Restore**:

- **FR-013**: Users MUST be able to save current window state as named layout for a project
- **FR-014**: System MUST capture window properties, workspace layout mode, monitor assignments, application launch commands, working directories, and environment variables
- **FR-015**: System MUST automatically discover launch commands from running process tree using psutil
- **FR-016**: Users MUST be able to restore saved layout, which relaunches missing applications and repositions existing windows
- **FR-017**: System MUST use window unmapping (hide/show) during restore to prevent visual flicker
- **FR-018**: System MUST preserve workspace-level layout mode (splith, splitv, tabbed, stacked) during save and restore
- **FR-019**: System MUST provide "Restore All" capability that launches all auto-launch entries for a project without restoring specific layout
- **FR-020**: System MUST provide "Close All" capability that closes all project-scoped windows

**Enhanced Window Matching**:

- **FR-021**: System MUST support configurable swallow criteria: window class, instance, title (regex), window role
- **FR-022**: System MUST allow per-application swallow criteria overrides in configuration
- **FR-023**: System MUST use default swallow criteria of class + instance when no override configured
- **FR-024**: System MUST match existing windows by swallow criteria during restore and reposition them instead of launching duplicates
- **FR-025**: System MUST create placeholder windows using i3's append_layout mechanism with swallow patterns

**Layout Diff and Comparison**:

- **FR-026**: Users MUST be able to compare current window state with saved layout showing added, removed, moved, and kept windows
- **FR-027**: System MUST display diff in side-by-side format with visual highlighting of differences
- **FR-028**: Users MUST be able to restore only missing windows from diff without affecting existing windows
- **FR-029**: System MUST prompt user with options when diff detected: "Save as new layout", "Update existing layout", "Discard changes"
- **FR-030**: Diff view MUST show workspace assignments for moved windows (both old and new locations)

**i3-resurrect Compatibility**:

- **FR-031**: Users MUST be able to import i3-resurrect layout files into i3pm format
- **FR-032**: Users MUST be able to export i3pm layouts to i3-resurrect format (pure i3 JSON)
- **FR-033**: Import MUST convert i3-resurrect swallow patterns to i3pm swallow criteria configuration
- **FR-034**: Export MUST strip i3pm-specific metadata to produce vanilla i3 JSON compatible with i3-resurrect restore workflow

**Error Handling and Reliability**:

- **FR-035**: System MUST handle window launch failures gracefully, logging errors and continuing with remaining windows
- **FR-036**: System MUST use try/finally pattern to ensure windows are always remapped after restore, even if errors occur
- **FR-037**: System MUST timeout placeholder windows after 30 seconds (configurable) and mark as "failed to launch"
- **FR-038**: System MUST provide detailed error messages for failures including: app command, working directory, error reason
- **FR-039**: System MUST detect and warn when restoring layout on different monitor configuration than saved

### Key Entities

- **WindowState**: Represents current state of a single window with properties from i3 (id, class, instance, title, marks, workspace, output, floating, focused, geometry) and i3pm extensions (project, classification, hidden, app_identifier)

- **LayoutWindow**: Represents a window in saved layout with swallow criteria, launch command, working directory, environment variables, geometry, and workspace assignment

- **WorkspaceLayout**: Represents saved layout for one or more workspaces including workspace layout mode, monitor assignment, list of LayoutWindows, and metadata (saved_at, window_count)

- **SavedLayout**: Complete saved layout for a project including name, multiple WorkspaceLayouts, monitor configuration snapshot, and creation timestamp

- **WindowDiff**: Comparison result between current state and saved layout categorizing windows as: added (in current, not in saved), removed (in saved, not in current), moved (changed workspace/monitor), kept (unchanged), with details for each category

- **SwallowCriteria**: Configuration defining which window properties to match during restore (class, instance, title, role) with per-application overrides

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can view current window state in under 1 second from command execution
- **SC-002**: Window state updates appear in TUI within 100ms of window creation/destruction/movement events
- **SC-003**: Layout save operation completes in under 2 seconds for workspaces with up to 20 windows
- **SC-004**: Layout restore operation successfully restores 95% of windows to correct workspace/monitor within 30 seconds
- **SC-005**: Tree view renders 100+ windows without perceptible lag (under 100ms initial render, under 50ms for updates)
- **SC-006**: Users can identify which windows are hidden due to project context within 3 seconds of viewing window state
- **SC-007**: Layout diff computation completes in under 500ms for layouts with up to 50 windows
- **SC-008**: Exported i3 JSON layouts are 100% compatible with vanilla i3 append_layout command
- **SC-009**: Window unmapping/remapping during restore produces zero visible flicker (tested by user perception)
- **SC-010**: Users successfully import i3-resurrect layouts on first attempt without errors in 90% of cases
- **SC-011**: System handles monitor configuration changes during restore without losing windows in 100% of cases
- **SC-012**: Layout restore reuses existing windows (avoiding duplicates) in 100% of cases where swallow criteria match

### User Satisfaction Outcomes

- **SC-013**: Users can understand current window state organization (which windows where) within 10 seconds of viewing tree view
- **SC-014**: Users can save and restore their "development setup" layout without consulting documentation
- **SC-015**: Users report reduced time to set up project workspace by 80% compared to manual window arrangement
- **SC-016**: Users successfully compare current state with saved layout and make informed decision (save new/update/restore) within 20 seconds

## Assumptions *(if applicable)*

### User Environment

- Users are running i3 window manager (not Sway or other tiling WMs)
- Users have xdotool installed for window manipulation (unmap/map operations)
- Users have multi-monitor setup (1-3 monitors typical)
- Users manage 10-50 windows across 5-10 workspaces (typical case)

### Technical Assumptions

- i3 IPC API is available and responsive (event subscription supported)
- Daemon is running and accessible via Unix socket
- Python 3.11+ with i3ipc.aio library available
- Textual TUI library available for rendering tree and table views
- Process information accessible via /proc filesystem (psutil) for launch command discovery

### Layout Behavior

- Window class + instance is sufficient for most applications (title/role needed for ~20% of cases)
- Applications can be relaunched with same command that originally started them
- Working directory and environment variables are sufficient to recreate application state
- Most applications create windows within 10 seconds of launch (30 second timeout acceptable)

### Data Retention

- Saved layouts persist indefinitely until explicitly deleted by user
- Users maintain 5-10 saved layouts per project (typical)
- Layout files stored in project-specific directories (~/.config/i3pm/projects/<project>/layouts/)

### Compatibility

- i3-resurrect layout files are JSON format matching i3's append_layout schema
- Users migrating from i3-resurrect have layouts in standard i3-resurrect directory structure
- Exported i3pm layouts can be imported by i3-resurrect without modification (pure i3 JSON)

## Dependencies *(if applicable)*

### Internal Dependencies

- **Existing daemon**: Window state visualization requires i3-project-event-daemon to be running and tracking windows
- **Existing project system**: Layout save/restore is project-scoped, requires project configuration to exist
- **Existing classification**: Hidden/visible window detection requires app classification system (scoped/global)
- **Existing IPC server**: Real-time updates require daemon's JSON-RPC IPC server with event subscription support

### External Dependencies

- **i3 window manager**: Feature requires i3 IPC API for window queries and append_layout support
- **xdotool**: Required for window unmapping/remapping during restore (prevents visual flicker)
- **Textual library**: Required for TUI rendering (tree and table widgets)
- **psutil library**: Required for process tree analysis to discover launch commands

### Sequencing Dependencies

1. **Phase 1**: Window state visualization (FR-001 to FR-008) must be complete before layout diff (FR-026 to FR-030) can be implemented
2. **Phase 2**: Enhanced window matching (FR-021 to FR-025) should be implemented before layout restore improvements (FR-016 to FR-020) to ensure accurate window matching
3. **Phase 3**: i3-resurrect compatibility (FR-031 to FR-034) depends on both window state visualization and layout save/restore being stable

## Out of Scope *(if applicable)*

### Not Included in This Feature

- **Sway support**: Only i3 window manager supported, Sway has different IPC
- **Wayland support**: Feature uses X11-specific tools (xdotool), not Wayland-compatible
- **Remote layouts**: No support for sharing layouts between machines or users
- **Layout templates**: No pre-built layout templates provided (users create their own)
- **Visual layout editor**: No drag-and-drop graphical editor for creating layouts (CLI/TUI only)
- **Window content capture**: Layouts save window positions, not window content (screenshots, application state)
- **Automatic layout switching**: No automatic layout restore based on time/context (user must explicitly restore)
- **Multi-project layouts**: Layouts are project-scoped, cannot span multiple projects
- **Historical layout tracking**: No versioning or history of layout changes over time

### Future Enhancements

- Interactive layout editor with drag-and-drop in TUI (post-MVP)
- Layout templates library with community-contributed setups (post-MVP)
- Smart layout recommendations based on usage patterns (post-MVP)
- Integration with window content backup (beyond just positions) (post-MVP)
- Automatic layout restore on project switch (post-MVP)

## Non-Functional Requirements *(if applicable)*

### Performance

- Real-time updates: Window state changes reflected in TUI within 100ms
- Tree rendering: Initial render under 100ms for 100 windows, updates under 50ms
- Layout operations: Save under 2s, restore under 30s, diff under 500ms
- Memory usage: TUI window state monitoring under 50MB RAM
- CPU usage: Real-time event processing under 2% CPU during idle monitoring

### Reliability

- Layout save must be atomic: Either complete save or no changes (no partial layouts)
- Window remap guarantee: Windows must always be remapped after restore, even on errors
- Event stream resilience: TUI must handle daemon disconnection gracefully and reconnect automatically
- Data integrity: Saved layout files must be validated on load, corrupted files rejected with clear error

### Usability

- First-time user can view window state and understand organization without documentation
- Keyboard-only navigation in TUI (no mouse required)
- Clear visual distinction between visible/hidden windows (color coding, icons)
- Error messages must include actionable remediation steps
- Layout operations provide progress feedback for operations over 2 seconds

### Compatibility

- Exported i3 JSON must be 100% compatible with vanilla i3-msg append_layout
- i3-resurrect layout import must succeed without manual editing in 90%+ of cases
- Must work with i3 versions 4.18+ (current stable range)
- Must preserve functionality when daemon is not running (fallback to direct i3 queries)

### Security

- Saved layouts must not expose sensitive environment variables (filter common secret patterns)
- Launch commands must be validated before execution (no shell injection)
- Layout files must have restricted permissions (600, user-only read/write)
- No execution of arbitrary commands from untrusted layout files
