# Feature Specification: Live Window/Project Monitoring Panel

**Feature Branch**: `085-sway-monitoring-widget`
**Created**: 2025-11-20
**Status**: ✅ **COMPLETE** - All Phases Implemented
**Last Updated**: 2025-11-20
**Input**: User description: "i want to explore creating a specific window/application that uses my current command: i3pm windows --live, to create a live view of my windows/projects, etc; explore whether this should be a regular terminal application that we add to home-modules/desktop/app-registry-data.nix or should we create a dedicated eww widget that will have it's own window signature, and cause less challenges around window matching, uniqueness, etc. we want the window to appear as a floating panel that can appear and disappear similar to scratchpad logic, but it should be global scoped since it should update automatically when we switch projects."

## Implementation Status

**MVP Milestone (User Story 1)**: ✅ **COMPLETE** - 2025-11-20
**User Story 2 (Cross-Project Navigation)**: ✅ **COMPLETE** - 2025-11-20
**User Story 3 (Window State Inspection)**: ✅ **COMPLETE** - 2025-11-20
**Phase 6 (Testing & Validation)**: ✅ **COMPLETE** - 2025-11-20
**Phase 7 (Real-Time Streaming)**: ✅ **COMPLETE** - 2025-11-20

The monitoring panel is now fully functional with:
- ✅ Keybinding toggle (Mod+m) working correctly
- ✅ Floating panel display with hierarchical view (monitors → workspaces → windows)
- ✅ Project association labels for scoped windows in (project-name) format
- ✅ Visual distinction: scoped windows (teal border) vs global windows (gray border)
- ✅ Window state indicators: floating (⚓ icon, yellow border), hidden (50% opacity, italic), focused (blue border)
- ✅ Workspace number display for each window [WS N]
- ✅ PWA detection and badge for windows on workspaces 50+
- ✅ **Real-time event streaming** via Eww `deflisten` (<100ms latency)
- ✅ **Automatic reconnection** with exponential backoff (1s → 2s → 4s → max 10s)
- ✅ **Heartbeat mechanism** every 5s to detect stale connections
- ✅ **Graceful shutdown** handling (SIGTERM/SIGINT/SIGPIPE)
- ✅ Event-driven updates on window/workspace/output changes via i3ipc.aio
- ✅ Catppuccin Mocha theme integration
- ✅ Systemd service running and stable
- ✅ Backend execution time <50ms for typical workload
- ✅ Multi-monitor support tested (3 virtual displays)
- ✅ Empty state handling with clear UI message
- ✅ Error state display with diagnostic information
- ✅ Summary counts in panel header (monitors, workspaces, windows)
- ✅ Timestamp display in panel footer

**Performance Validated**:
- Toggle latency: 26-28ms (target <200ms) ✅
- Update latency: <100ms via event stream (target <100ms) ✅
- Memory usage: 51MB with 11 windows (target <50MB for 30 windows) ⚠️ Marginal

## User Scenarios & Testing

### User Story 1 - Quick System Overview Access (Priority: P1)

When working across multiple projects and workspaces, users need instant visibility into the current window/project state without disrupting their workflow. This panel must show active projects, windows per workspace, and update automatically as the system state changes.

**Why this priority**: Core functionality - the primary value proposition. Without instant access to a live monitoring view, the feature delivers no value.

**Independent Test**: Can be fully tested by pressing a keybinding, verifying the monitoring panel appears as a floating window showing current window/project state, and confirming it updates in real-time when windows are created/destroyed or projects are switched.

**Acceptance Scenarios**:

1. **Given** user is working in any project on any workspace, **When** user presses the monitoring panel keybinding, **Then** floating panel appears centered on the current display showing hierarchical view of monitors → workspaces → windows with project associations
2. **Given** monitoring panel is visible, **When** user creates a new window or switches projects, **Then** panel content updates automatically within 100ms to reflect new state
3. **Given** monitoring panel is visible, **When** user presses the keybinding again, **Then** panel hides from view but remains ready for instant reactivation

---

### User Story 2 - Cross-Project Navigation (Priority: P2)

When monitoring multiple active projects, users need to identify which windows belong to which projects and navigate between them efficiently. The panel should clearly indicate project scopes and workspace allocations.

**Why this priority**: Enhances the core monitoring functionality but builds on P1. Can be developed after basic panel display works.

**Independent Test**: Can be tested by working across 3 different projects with multiple windows each, opening the monitoring panel, and verifying that project associations are clearly displayed and distinguishable.

**Acceptance Scenarios**:

1. **Given** user has windows from 3 different projects (nixos, dotfiles, feature-branch) across 6 workspaces, **When** user opens monitoring panel, **Then** panel displays each window with clear project label indicating which project owns it
2. **Given** monitoring panel shows windows grouped by workspace, **When** user has both scoped and global windows visible, **Then** panel distinguishes scoped windows (showing project name) from global windows (showing "global" indicator)
3. **Given** user switches from project A to project B, **When** monitoring panel is visible, **Then** panel updates to show project B's windows brought into view and project A's windows hidden to scratchpad

---

### User Story 3 - Window State Inspection (Priority: P3)

When troubleshooting window management issues or understanding system state, users need detailed information about each window including application type, workspace assignment, floating status, and process information.

**Why this priority**: Adds diagnostic value but feature is still useful without detailed inspection. Can be refined after basic display and project navigation work.

**Independent Test**: Can be tested by opening monitoring panel with various window types (terminals, browsers, PWAs, floating windows), and verifying that each window shows relevant metadata like app name, workspace number, and state indicators.

**Acceptance Scenarios**:

1. **Given** user has mix of tiled and floating windows, **When** user opens monitoring panel, **Then** panel shows floating windows with distinct visual indicator (e.g., icon or label)
2. **Given** monitoring panel is displaying window list, **When** user views a PWA window (workspace 50+), **Then** panel shows PWA indicator and workspace number clearly
3. **Given** user has scratchpad terminal hidden, **When** user opens monitoring panel, **Then** panel shows hidden scratchpad windows with "hidden" state indicator

---

### Edge Cases

- **Panel already visible**: If monitoring panel is already open and user presses keybinding again, panel should hide (toggle behavior)
- **No windows present**: If user opens panel when no windows exist (empty workspaces), panel should display "No windows" message rather than empty/broken UI
- **Rapid window creation**: If multiple windows are created in quick succession (<50ms apart), panel should batch updates to avoid flicker while maintaining <100ms update latency
- **Multi-monitor environments**: Panel should appear on the currently focused monitor, not always on primary monitor
- **Panel loses focus**: If user clicks outside panel or switches focus to another window, panel should remain visible until explicitly hidden with keybinding

## Requirements

### Functional Requirements

- **FR-001**: System MUST display a floating panel showing hierarchical window organization (monitors → workspaces → windows)
- **FR-002**: Panel MUST appear/disappear via keyboard shortcut toggle (show when hidden, hide when visible)
- **FR-003**: Panel MUST update automatically within 100ms when windows are created, destroyed, moved, or hidden
- **FR-004**: Panel MUST update automatically when user switches between projects
- **FR-005**: Panel MUST clearly indicate project association for each scoped window
- **FR-006**: Panel MUST distinguish between scoped windows (project-specific) and global windows (visible across all projects)
- **FR-007**: Panel MUST show window state indicators (floating, hidden, scratchpad)
- **FR-008**: Panel MUST display on the currently focused monitor in multi-monitor setups
- **FR-009**: Panel MUST have global scope (not hidden when switching projects)
- **FR-010**: Panel MUST use consistent visual styling with existing system theme (Catppuccin Mocha)
- **FR-011**: Panel MUST be implemented as dedicated Eww widget with custom Yuck UI and GTK widgets
- **FR-012**: Panel MUST use Sway marks for deterministic window identification and management
- **FR-013**: Panel MUST query i3pm daemon backend using data polling mechanism (defpoll or similar)
- **FR-014**: Panel window MUST have Sway window rules to ensure floating behavior, global scope, and proper positioning

### Key Entities

- **Window**: Represents a Sway window with attributes (app name, workspace, project association, state, floating status, process ID)
- **Workspace**: Represents a Sway workspace containing zero or more windows, belongs to a monitor
- **Monitor**: Represents physical or virtual display output containing workspaces
- **Project**: Represents i3pm project context with associated scoped windows
- **Panel State**: Tracks panel visibility (visible/hidden), last update timestamp, current focused monitor

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can toggle panel visibility in under 200ms from keybinding press to panel fully rendered
- **SC-002**: Panel updates reflect system state changes (window create/destroy/move) within 100ms of event occurrence
- **SC-003**: Panel displays accurate project associations for 100% of scoped windows without misidentification
- **SC-004**: Users can identify window locations (workspace, monitor) in under 3 seconds by viewing panel
- **SC-005**: Panel remains responsive (accepts input, updates UI) when system has 50+ windows across 10+ workspaces
- **SC-006**: Panel consumes less than 50MB memory when displaying typical workload (20-30 windows across 5 projects)

## Assumptions

- Users have existing i3pm daemon running (required for window/project state queries)
- System uses Sway window manager (not i3wm)
- Users are familiar with existing i3pm concepts (projects, scoped windows, scratchpad)
- Panel will leverage existing `i3pm windows` command backend for data retrieval via Python daemon client
- Eww widget will use defpoll mechanism to query daemon at regular intervals (e.g., 500ms-1s) or implement event-driven updates via helper script
- Keybinding configuration follows existing Sway keybinding patterns in `home-modules/desktop/sway-keybindings.nix`
- Eww is available and configured in the user's environment (already present in Feature 057, 060)

## Dependencies

- **Feature 025**: Visual Window State Management (provides `i3pm windows` command and TUI implementation)
- **Feature 062**: Project-Scoped Scratchpad Terminal (reference implementation for floating toggle behavior)
- **Feature 057**: Unified Bar System (provides Catppuccin Mocha theme styling patterns)
- **Feature 076**: Mark-Based App Identification (provides Sway marks for Eww widget window identification)
- **i3pm daemon**: Running i3-project-event-listener service for window/project state queries
- **Sway IPC**: Window events for real-time updates (window::new, window::close, window::move, workspace::focus)
- **Eww**: ElKowar's Wacky Widgets framework for GTK-based UI widgets

## Architectural Decision

**Implementation Approach**: Eww Widget (Option A)

After exploring terminal app and hybrid approaches, the decision was made to implement this as a dedicated Eww widget for the following reasons:

1. **Better window matching**: Sway marks provide deterministic window identification without class name conflicts
2. **Memory efficiency**: Native GTK widgets (~5-10MB) vs terminal emulator overhead (~30MB)
3. **Visual consistency**: Leverages existing Eww patterns from Feature 057 (Unified Bar System) and Feature 060 (Eww Top Bar)
4. **Superior UX**: Native GTK provides smooth scrolling, mouse interaction, and responsive rendering
5. **Global scope alignment**: Eww windows naturally support global visibility and floating behavior via Sway window rules

**Trade-offs Accepted**:
- Longer initial development (building Yuck UI from scratch vs reusing Textual TUI)
- Cannot directly reuse `i3pm windows --live` TUI code (but can reuse daemon client backend logic)

## Scope Boundaries

**In Scope**:
- Toggle visibility via keybinding
- Real-time display of window/workspace/project state
- Visual distinction between scoped/global windows
- Floating panel positioning on current monitor
- Integration with existing i3pm daemon for state queries
- Consistent theme styling with Catppuccin Mocha

**Out of Scope**:
- Interactive window management actions (closing windows, moving between workspaces) - panel is read-only monitoring
- Historical window state tracking or timeline view
- Filtering/searching windows within the panel
- Customizable panel layouts or user preferences
- Panel resize/repositioning by user (fixed size/position)
- Multi-panel support (only one global monitoring panel instance)

---

## Implementation Notes

### Architectural Decisions

**Eww Widget Implementation** (Selected in Phase 0):
- Native GTK rendering for smooth scrolling and responsive UI
- Sway marks for deterministic window identification
- Python backend script with dual modes (one-shot + streaming)
- **Deflisten mechanism** for real-time event streaming (<100ms latency)
- i3ipc.aio subscriptions to window/workspace/output events
- Automatic reconnection with exponential backoff
- Heartbeat mechanism (5s interval) to detect stale connections
- Global scope via Sway window rules

**Key Technical Decisions**:
1. **Toggle Detection**: Use `eww active-windows` (not `list-windows` which shows all defined windows, not `sway tree` which doesn't show overlay windows reliably)
2. **Backend Connection**: Long-running stream process with automatic reconnection and graceful shutdown
3. **Data Source**: i3pm daemon as single source of truth (already has window/project associations)
4. **Update Strategy**: Event-driven streaming via `deflisten` with i3ipc.aio event subscriptions (window, workspace, output changes)
5. **Python Environment**: Uses `python3.withPackages (ps: [ ps.i3ipc ])` to ensure i3ipc.aio availability

### Challenges Encountered

**Toggle Script Flashing (Fixed 2025-11-20)**:
- **Problem**: Panel would flash when trying to close - rapid open/close cycles
- **Root Cause**: Eww overlay windows not visible in Sway tree, script always thought panel was closed
- **Solution**: Changed from Sway tree checking to `eww active-windows` command
- **Impact**: Keybinding now works correctly without flashing

**Backend Integration**:
- **Challenge**: Python module imports failing from Nix-wrapped script
- **Solution**: Set PYTHONPATH explicitly in wrapper script to include `home-modules/tools/`
- **Challenge**: Daemon socket path incorrect (looking in user runtime dir)
- **Solution**: Set I3PM_DAEMON_SOCKET env var to system service path `/run/i3-project-daemon/ipc.sock`

**User Story 2: Cross-Project Navigation (Fixed 2025-11-20)**:
- **Problem 1**: Yuck syntax error with empty string literal `''` in ternary operator
  - **Solution**: Simplified to `:text "(${window.project})"` with `:visible` conditional
- **Problem 2**: Backend returned "unknown" for all app names
  - **Root Cause**: Backend expected `app_name` field, but daemon returns `class` field
  - **Solution**: Extract from `window.get("class")` or fallback to `window.get("app_id")`
- **Problem 3**: All windows showed scope "global", project labels never visible
  - **Root Cause**: Backend expected `scope` field, but daemon provides marks like `scoped:project:id`
  - **Solution**: Derive scope by checking if any mark starts with "scoped:"
- **Impact**: App names now display correctly, scoped windows show project labels with visual distinction

**Real-Time Streaming via Deflisten (Implemented 2025-11-20)**:
- **Challenge**: Python script couldn't find i3ipc.aio module when run from Eww wrapper
- **Root Cause**: `pkgs.python3` provides plain Python without packages; wrapper's PYTHONPATH didn't include site-packages
- **Solution**: Use `python3.withPackages (ps: [ ps.i3ipc ])` to create Python environment with i3ipc
- **Debug Process**: Added debug logging to wrapper, discovered plain Python path vs env path mismatch
- **Nix Caching Issue**: Required version comment changes to force derivation rebuild (v2 → v3 → v4 → v5)
- **Final Implementation**:
  - Added `--listen` flag to backend for streaming mode
  - i3ipc.aio event subscriptions (window, workspace, output)
  - Automatic reconnection with exponential backoff (1s → 2s → 4s → max 10s)
  - Heartbeat every 5s to detect stale connections
  - Graceful signal handling (SIGTERM/SIGINT/SIGPIPE)
- **Impact**: Panel now updates in real-time (<100ms) instead of 10s polling

### Performance Characteristics (Measured)

- **Panel Toggle**: 26-28ms average (target: <200ms) ✅ *7x faster than target*
- **Backend Execution**: <50ms for typical workload (11-30 windows) ✅
- **Memory Usage**: 51MB Eww daemon with 11 windows (target: <50MB for 30 windows) ⚠️ *Marginal - projected 60-65MB for 30 windows*
- **Update Latency**: <100ms via event stream (target: <100ms) ✅ *Real-time updates on every window/workspace/output change*
- **Data Payload**: ~12KB JSON for 11 windows, 6 workspaces, 3 monitors
- **Streaming Uptime**: Automatic reconnection ensures continuous operation

### Architectural Improvements

**State Model Pattern** (2025-11-20):
- **Challenge**: Eww ternary operators with empty strings caused Nix escaping issues
- **Research**: Investigated Eww best practices and community patterns
- **Solution**: Move conditional CSS class logic from Yuck to Python backend
- **Implementation**: Added `get_window_state_classes()` function in backend
- **Benefits**: Better performance (1 DOM element vs 2), easier testing, no escaping issues
- **Documentation**: `specs/085-sway-monitoring-widget/eww-architecture-research.md`

### Files Modified

**New Files**:
- `home-modules/desktop/eww-monitoring-panel.nix` (560 lines) - Eww widget module
- `home-modules/tools/i3_project_manager/cli/monitoring_data.py` (280 lines) - Backend script with state model
- `specs/085-sway-monitoring-widget/eww-architecture-research.md` - Architectural research document

**Modified Files**:
- `home-modules/desktop/sway-keybindings.nix` (line 134) - Added Mod+m keybinding
- `home-modules/hetzner-sway.nix` (lines 88, 174) - Enabled module

**Generated Files** (at runtime):
- `~/.config/eww-monitoring-panel/eww.yuck` - Widget definition
- `~/.config/eww-monitoring-panel/eww.scss` - Catppuccin Mocha styling
