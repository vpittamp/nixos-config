# Feature Specification: Comprehensive Session Management

**Feature Branch**: `074-session-management`
**Created**: 2025-01-14
**Status**: Draft
**Input**: User description: "Comprehensive session management with per-project workspace focus restoration, terminal working directory tracking, focused window restoration, auto-save/restore capabilities, and Sway-compatible window restoration using mark-based correlation"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Workspace Focus Restoration on Project Switch (Priority: P1)

As a developer working on multiple projects, when I switch from Project A (where I'm focused on workspace 3) to Project B and then back to Project A, I want to automatically return to workspace 3 so I can continue exactly where I left off without manually navigating back.

**Why this priority**: This is the core issue that blocks natural project switching workflows. Without it, users must manually navigate to their previous workspace after every project switch, breaking concentration and wasting time. This affects every project switch operation.

**Independent Test**: Can be fully tested by: (1) Focus workspace 3 in Project A, (2) Switch to Project B, (3) Switch back to Project A, (4) Verify automatic focus on workspace 3. Delivers immediate value by eliminating manual workspace navigation.

**Acceptance Scenarios**:

1. **Given** user is on Project A with workspace 3 focused, **When** user switches to Project B and then back to Project A, **Then** workspace 3 is automatically focused
2. **Given** user switches to a new project for the first time (no previous focus history), **When** project becomes active, **Then** system focuses a reasonable default workspace (workspace 1)
3. **Given** user has focused different workspaces across multiple project switches (A→ws3, B→ws5, C→ws12), **When** user cycles through projects A→B→C→A, **Then** each project restores its respective focused workspace

---

### User Story 2 - Terminal Working Directory Preservation (Priority: P1)

As a developer who uses terminal applications in each project, when I save and restore a project session, I want my terminal windows to reopen in their original working directories (not $HOME) so I don't have to manually navigate to the project directory in each terminal.

**Why this priority**: Terminal windows are fundamental to development workflows. Opening them in the wrong directory forces users to manually `cd` to the correct location in every terminal, which is especially frustrating when restoring sessions with 3-5 terminal windows. This affects the core value of session restoration.

**Independent Test**: Can be fully tested by: (1) Open terminal in `/etc/nixos/modules`, (2) Save session, (3) Restore session, (4) Verify terminal opens in `/etc/nixos/modules`. Delivers immediate value for any workflow involving terminals.

**Acceptance Scenarios**:

1. **Given** user has a terminal open in directory `/etc/nixos/modules`, **When** session is saved and restored, **Then** terminal window reopens in `/etc/nixos/modules`
2. **Given** user has multiple terminals in different directories (terminal 1 in `/etc/nixos`, terminal 2 in `~/projects/dotfiles`), **When** session is restored, **Then** each terminal opens in its original directory
3. **Given** user's original working directory no longer exists (directory was deleted), **When** session is restored, **Then** terminal opens in project root directory as fallback

---

### User Story 3 - Sway-Compatible Window Restoration (Priority: P1)

As a Sway user, when I restore a saved layout, I want windows to be correctly matched and positioned even though Sway doesn't support i3's swallow mechanism, so I can use session management on my Wayland compositor.

**Why this priority**: Current implementation is broken on Sway (the primary compositor for this system). Without this, layout restoration is non-functional for the target environment. This is a production blocker.

**Independent Test**: Can be fully tested by: (1) Save layout on Sway, (2) Restore layout on Sway, (3) Verify windows appear with correct geometry and workspace placement. Delivers essential functionality for Sway users.

**Acceptance Scenarios**:

1. **Given** user saves a layout with 3 windows (Code, Firefox, terminal) on Sway, **When** layout is restored, **Then** all 3 windows appear with correct class, geometry, and workspace assignments
2. **Given** two windows with same class launch simultaneously during restore, **When** mark-based correlation runs, **Then** each window is correctly matched to its intended placeholder (>95% accuracy)
3. **Given** a window takes longer than expected to launch (slow startup), **When** mark-based correlation monitors for window appearance, **Then** window is eventually matched within timeout period (30 seconds default)

---

### User Story 4 - Focused Window Restoration Per Workspace (Priority: P2)

As a user with multiple windows per workspace, when I restore a session, I want each workspace to focus the same window I was using before (not an arbitrary window), so I can immediately continue my work without hunting for the right window.

**Why this priority**: Improves restoration accuracy but isn't blocking basic session management. Users can manually focus the correct window if needed, but automatic restoration significantly improves UX.

**Independent Test**: Can be fully tested by: (1) Focus VS Code window on workspace 2, (2) Save session, (3) Restore session, (4) Verify VS Code has focus on workspace 2. Delivers polish to session restoration.

**Acceptance Scenarios**:

1. **Given** workspace 2 has 3 windows (VS Code focused, 2 terminals unfocused), **When** session is restored, **Then** VS Code is focused on workspace 2
2. **Given** user has focused different windows across multiple workspaces (ws2→Code, ws3→Firefox, ws5→terminal), **When** session is restored, **Then** each workspace restores focus to the correct window
3. **Given** the previously focused window no longer exists in restored session (user manually closed it), **When** workspace is restored, **Then** system focuses first available window on that workspace

---

### User Story 5 - Automatic Session Save on Project Switch (Priority: P2)

As a user who frequently switches projects, when I leave Project A to work on Project B, I want the system to automatically save Project A's layout so I don't have to remember to manually save it, ensuring I never lose my workspace configuration.

**Why this priority**: Provides convenience and protection against forgotten saves, but manual save is sufficient for MVP. This is a workflow enhancement rather than core functionality.

**Independent Test**: Can be fully tested by: (1) Arrange windows in Project A, (2) Switch to Project B (no manual save), (3) Switch back to Project A, (4) Verify layout was automatically preserved. Delivers convenience without requiring new core capabilities.

**Acceptance Scenarios**:

1. **Given** user switches from Project A to Project B without manually saving, **When** user later switches back to Project A, **Then** auto-saved layout is available for restoration
2. **Given** user has auto-save enabled and makes 5 project switches in one session, **When** user reviews saved layouts, **Then** system has auto-saved each project's layout with timestamps (keeping recent saves only to limit disk usage)
3. **Given** auto-save is disabled in project configuration, **When** user switches projects, **Then** system does not auto-save layout (user must manually save)

---

### User Story 6 - Automatic Session Restore on Project Activate (Priority: P3)

As a user who prefers a consistent workspace setup, when I activate Project A, I want the system to automatically restore my saved layout (if enabled) so my workspace is immediately ready without manual restore commands.

**Why this priority**: Nice-to-have convenience feature. Many users may prefer manual control over when layouts are restored, making this lower priority than auto-save.

**Independent Test**: Can be fully tested by: (1) Save layout for Project A with auto-restore enabled, (2) Switch to Project B, (3) Switch back to Project A, (4) Verify layout automatically restores without manual command. Delivers workflow automation for users who prefer it.

**Acceptance Scenarios**:

1. **Given** Project A has auto-restore enabled and a saved default layout, **When** user switches to Project A, **Then** layout automatically restores
2. **Given** Project A has auto-restore disabled, **When** user switches to Project A, **Then** layout does not restore automatically (user must manually trigger restore)
3. **Given** Project A has auto-restore enabled but no saved layout exists, **When** user switches to Project A, **Then** system shows no layout to restore (no error, graceful degradation)

---

### Edge Cases

- **What happens when a previously focused workspace no longer exists?** (e.g., monitor disconnected, workspace deleted): System falls back to finding first visible window in the project and focuses that workspace, or defaults to workspace 1 if no project windows are visible.

- **What happens when terminal working directory was deleted?**: System falls back to project root directory as specified in project configuration. If project root also doesn't exist, falls back to user's home directory.

- **How does system handle windows that fail to launch during restoration?**: System logs failed launches, continues restoring remaining windows, and reports summary at end (e.g., "Restored 8/10 windows, 2 failed to launch"). User can manually retry failed windows.

- **What happens when two windows with identical class/instance/title launch simultaneously?**: Mark-based correlation assigns unique restoration marks before launch, ensuring each window is matched correctly regardless of timing (>95% accuracy target).

- **How does system handle mark-based correlation timeout?**: After 30 seconds (configurable), system reports window as "failed to correlate" and continues with remaining windows. User can manually position orphaned windows.

- **What happens when auto-save generates too many saved layouts?**: System keeps only the most recent N auto-saves per project (default: 10), automatically pruning older saves. Manual saves are never auto-deleted.

- **How does system handle project switch during an active layout restoration?**: Current restoration is cancelled gracefully (windows already launched remain), and new project switch proceeds normally. User can re-trigger restoration manually if needed.

## Requirements *(mandatory)*

### Functional Requirements

**Workspace Focus Tracking:**

- **FR-001**: System MUST track the currently focused workspace number for each project separately
- **FR-002**: System MUST update focused workspace tracking whenever user focuses a different workspace within the active project
- **FR-003**: System MUST persist focused workspace state to disk for cross-session recovery (survive daemon restarts)
- **FR-004**: When switching to a project, system MUST restore focus to the previously focused workspace for that project
- **FR-005**: When switching to a project with no previous focus history, system MUST focus workspace 1 as default
- **FR-006**: If previously focused workspace no longer exists (monitor disconnect, workspace deleted), system MUST fall back to first available workspace containing project windows

**Terminal Working Directory Tracking:**

- **FR-007**: System MUST capture working directory from terminal process when saving layouts
- **FR-008**: System MUST identify terminal applications by window class (ghostty, Alacritty, kitty, and other configurable terminal classes)
- **FR-009**: System MUST read working directory from `/proc/{pid}/cwd` symlink for identified terminal processes
- **FR-010**: When restoring terminal windows, system MUST launch terminal with original working directory via process working directory parameter
- **FR-011**: If original working directory no longer exists, system MUST fall back to project root directory
- **FR-012**: If project root directory also doesn't exist, system MUST fall back to user home directory

**Focused Window Tracking:**

- **FR-013**: System MUST track which window has focus within each workspace
- **FR-014**: System MUST update focused window tracking whenever user focuses a different window
- **FR-015**: When restoring a workspace, system MUST focus the previously focused window on that workspace
- **FR-016**: If previously focused window no longer exists in restored session, system MUST focus first available window on workspace

**Sway-Compatible Window Restoration:**

- **FR-017**: System MUST detect whether running on Sway or i3 compositor at runtime
- **FR-018**: On Sway, system MUST use mark-based correlation for window matching (cannot use i3's swallow mechanism)
- **FR-019**: System MUST generate unique restoration marks for each window being restored (format: `i3pm-restore-{uuid}`)
- **FR-020**: System MUST inject restoration mark into window's environment before launching application
- **FR-021**: System MUST poll for window appearance with matching restoration mark (configurable timeout, default 30 seconds)
- **FR-022**: After window is matched via mark, system MUST apply saved geometry, floating state, and project marks
- **FR-023**: System MUST remove temporary restoration mark after successful correlation
- **FR-024**: System MUST achieve >95% correlation accuracy for windows with unique class/instance combinations
- **FR-025**: On i3, system MAY continue using existing swallow mechanism for backward compatibility

**Automatic Session Save:**

- **FR-026**: System MUST provide configurable auto-save setting per project (enabled/disabled)
- **FR-027**: When auto-save is enabled and user switches from a project, system MUST capture current layout before project switch completes
- **FR-028**: Auto-saved layouts MUST include timestamp in filename (format: `auto-YYYYMMDD-HHMMSS`)
- **FR-029**: System MUST limit auto-saved layouts to configurable maximum count per project (default: 10 most recent)
- **FR-030**: When auto-save limit is exceeded, system MUST delete oldest auto-saved layout automatically
- **FR-031**: System MUST never auto-delete manually saved layouts (only auto-saved ones)

**Automatic Session Restore:**

- **FR-032**: System MUST provide configurable auto-restore setting per project (enabled/disabled, default: disabled)
- **FR-033**: System MUST provide configurable default layout name per project for auto-restore
- **FR-034**: When auto-restore is enabled and user switches to a project, system MUST restore specified default layout
- **FR-035**: If default layout is not specified, system MUST use most recent auto-saved layout
- **FR-036**: If no saved layout exists, system MUST gracefully degrade (no error, just log info message)
- **FR-037**: If auto-restore is disabled, system MUST NOT automatically restore layouts (user must manually trigger)

**Layout Data Model Extensions:**

- **FR-038**: Layout snapshot MUST include focused workspace number for the project
- **FR-039**: Window placeholder MUST include working directory path (optional field for non-terminal windows)
- **FR-040**: Window placeholder MUST include focused state boolean (true if window had focus on its workspace)
- **FR-041**: Layout persistence MUST maintain backward compatibility with existing saved layouts (graceful handling of missing new fields)

**Error Handling & Resilience:**

- **FR-042**: If window fails to launch during restoration, system MUST continue restoring remaining windows
- **FR-043**: System MUST provide restoration summary showing successful/failed window count
- **FR-044**: If mark-based correlation times out, system MUST log timeout and continue with next window
- **FR-045**: If layout restoration is interrupted by project switch, system MUST cancel in-progress restoration gracefully

### Key Entities

- **Project Focus State**: Tracks which workspace was focused when user last worked on each project. Contains project name (string) and workspace number (integer 1-70). Persisted to `~/.config/i3/active-project.json` with structure `{"project_name": "nixos", "focused_workspaces": {"nixos": 3, "dotfiles": 5}}`.

- **Workspace Focus State**: Tracks which window was focused on each workspace. Contains workspace number (integer) and window container ID (integer). Stored in daemon memory with optional persistence.

- **Window Placeholder (Extended)**: Represents a window to be restored in a layout. Existing attributes: window class, instance, title pattern, launch command, geometry, floating state, marks. New attributes: working directory path (optional, for terminals), focused state (boolean), restoration mark (temporary, for Sway correlation).

- **Layout Snapshot (Extended)**: Represents a saved session state. Existing attributes: name, project, created timestamp, monitor config, workspace layouts, metadata. New attributes: focused workspace number (integer).

- **Restoration Mark**: Temporary unique identifier for correlating launched windows to placeholders on Sway. Format: `i3pm-restore-{uuid}` where uuid is 8-character hexadecimal. Removed after successful correlation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can switch between projects and return to their previously focused workspace 100% of the time (no manual navigation required)

- **SC-002**: Terminal windows restore to their original working directory in >95% of cases (remaining 5% are edge cases like deleted directories, which fall back gracefully)

- **SC-003**: Window restoration on Sway achieves >95% correlation accuracy for windows with unique class/instance combinations

- **SC-004**: Average time to restore a 10-window layout is under 15 seconds (measured from restore command to all windows positioned)

- **SC-005**: Mark-based correlation timeout rate is <5% under normal conditions (windows launch within 30-second timeout)

- **SC-006**: Users can complete full project switch cycle (A→B→A) and have both projects restore complete context (workspace focus, window focus, terminal cwd) in under 3 seconds total (excluding window launch time)

- **SC-007**: Auto-save captures complete layout state (all windows, geometry, focus) in <200ms (imperceptible to user during project switch)

- **SC-008**: System handles monitor configuration changes gracefully (workspace focus restoration falls back to first available workspace if target no longer exists) with 100% success rate

- **SC-009**: Restored terminal windows open in correct directory on first attempt in >95% of cases (remaining cases gracefully fall back to project root or home directory)

- **SC-010**: Layout restoration reports accurate success/failure summary to user (counts of launched/failed/timed-out windows) 100% of the time

## Assumptions

- **Terminal Detection**: Assumes terminal applications can be identified by window class matching known terminal emulators (ghostty, Alacritty, kitty, etc.). System provides configuration option to add custom terminal classes.

- **Working Directory Access**: Assumes `/proc/{pid}/cwd` symlink is readable for processes owned by the current user. Cross-user terminal processes (e.g., root terminals) may not have accessible working directory.

- **Mark Injection**: Assumes launched applications inherit environment variables from parent process, allowing restoration marks to be set before window creation. Works for most applications; some sandboxed apps may not inherit environment.

- **Correlation Timeout**: Assumes 30 seconds is sufficient for most applications to launch and create windows. Slow-starting applications (e.g., large IDEs on first launch) may exceed timeout; timeout is configurable.

- **Focus Tracking Accuracy**: Assumes Sway/i3 window::focus events are reliable for tracking window focus changes. Event-based tracking should be >99% accurate under normal conditions.

- **Layout Persistence Format**: Assumes existing Pydantic-based layout persistence can be extended with new optional fields without breaking existing saved layouts. New fields default to None/False for backward compatibility.

- **Monitor Configuration**: Assumes workspace-to-monitor mapping from existing system (Feature 001) is available and correct. Focus restoration uses this mapping to validate workspace availability.

- **Auto-Save Disk Usage**: Assumes 10 auto-saved layouts per project with ~10-20KB per layout results in acceptable disk usage (<1MB per project for session data).

- **Compositor Detection**: Assumes presence of `WAYLAND_DISPLAY` environment variable reliably indicates Sway/Wayland environment. Absence indicates i3/X11.

## Dependencies

- **Existing Layout System**: Requires existing layout capture/persistence/restore infrastructure (already implemented in `layout/` module)

- **Workspace Tracker**: Requires existing `WorkspaceTracker` for window-to-workspace mapping persistence

- **Window Filtering**: Requires existing mark-based window filtering system for project association

- **Event Daemon**: Requires event daemon to subscribe to workspace::focus and window::focus events

- **IPC Server**: Requires IPC server for CLI integration (save/restore commands)

## Out of Scope

- **Window Content State**: Does not restore application-specific state (e.g., VS Code open files, browser tabs). Only restores window positioning, geometry, and focus.

- **Cross-Machine Session Sync**: Does not sync saved layouts across multiple machines. Layouts are local to the machine where they were created.

- **Layout Version Control**: Does not provide git-like version control for layouts. Auto-save provides basic history (10 most recent), but no branching/merging.

- **Application State Management**: Does not interact with applications to save/restore their internal state. Applications start fresh with empty state.

- **Network Application Recovery**: Does not handle special cases for network-dependent applications (e.g., remote desktop, SSH sessions). These launch fresh and user must reconnect manually.

- **Predictive Layout Optimization**: Does not analyze user behavior to suggest optimal layouts. Users explicitly save layouts they want to restore.
