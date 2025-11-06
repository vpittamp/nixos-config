# Feature Specification: Project-Scoped Scratchpad Terminal

**Feature Number**: 062
**Status**: Implemented
**Created**: 2025-11-05
**Last Updated**: 2025-11-06

**Implementation Note**: This feature was implemented using Sway IPC `exec` command for terminal launching instead of Python subprocess or systemd-run due to terminal emulator crashes in headless/VNC environments. See TR-001 for technical rationale.

## Overview

### Purpose

Enable users to quickly access a dedicated floating terminal for each project that persists across workspace switches, providing immediate command-line access scoped to the project's directory without cluttering the main workspace layout.

### Background

The current system uses project-based window filtering where switching projects hides windows belonging to other projects by moving them to the scratchpad. However, this scratchpad mechanism is intended only for project isolation and not for user-accessible quick-access functionality. Users need a separate, deliberate scratchpad feature for frequently accessed utilities that should be:

- Easily toggled with a keybinding
- Scoped to the active project
- Persistent across project switches
- Floating to avoid disrupting workspace layouts

The first implementation of this user-facing scratchpad functionality is a project-scoped terminal.

### Goals

- Provide instant terminal access for the active project via keybinding
- Maintain separate terminal instances per project with independent states
- Keep terminals floating to preserve workspace tiling layouts
- Open terminals automatically in the project's root directory
- Allow quick show/hide toggling without affecting other windows

### Non-Goals

- Modifying the existing project window filtering mechanism
- Providing scratchpad functionality for windows other than project terminals
- Supporting multiple scratchpad terminals per project

## User Scenarios & Testing

### User Story 1 - Quick Terminal Access (Priority: P1)

When working in a project, users frequently need command-line access to run git commands, build scripts, or inspect files without leaving their focused workspace. This terminal must be instantly accessible and scoped to the project directory.

**Why this priority**: Core functionality - the primary value proposition of this feature. Without this, the feature delivers no value.

**Independent Test**: Can be fully tested by switching to a project, pressing the scratchpad keybinding, and verifying a terminal opens in the correct directory. Delivers immediate value as a quick-access project terminal.

**Acceptance Scenarios**:

1. **Given** user is in project "nixos", **When** user presses scratchpad terminal keybinding for first time, **Then** Ghostty terminal opens as floating window centered on display with working directory set to nixos project root (falls back to Alacritty if Ghostty unavailable)
2. **Given** project scratchpad terminal is visible, **When** user presses scratchpad keybinding, **Then** terminal hides to scratchpad (process continues running)
3. **Given** project scratchpad terminal is hidden, **When** user presses scratchpad keybinding, **Then** same terminal instance appears in same position with command history intact

---

### User Story 2 - Multi-Project Terminal Isolation (Priority: P2)

When working across multiple projects during the day, users need each project to maintain its own terminal state (command history, running processes, working directory) without interference.

**Why this priority**: Essential for multi-project workflows but builds on P1. Can be developed/tested after basic show/hide works.

**Independent Test**: Can be tested by creating scratchpad terminals in two different projects, running different commands in each, switching between projects, and verifying each terminal maintains independent state.

**Acceptance Scenarios**:

1. **Given** user has opened scratchpad terminal in project "nixos" and run command `git status`, **When** user switches to project "dotfiles" and opens its scratchpad terminal, **Then** dotfiles terminal shows empty history, different working directory, separate process ID
2. **Given** scratchpad terminals exist for both "nixos" and "dotfiles", **When** user switches from nixos to dotfiles, **Then** nixos terminal automatically hides, dotfiles terminal remains hidden until explicitly shown
3. **Given** user has multiple regular Alacritty windows open in a project, **When** user presses scratchpad keybinding, **Then** only the designated scratchpad terminal toggles, other terminals remain unaffected

---

### User Story 3 - Terminal State Persistence (Priority: P3)

After hiding a scratchpad terminal, users expect to return to exactly where they left off - same directory, command history, and any running processes (like watch commands or tail -f).

**Why this priority**: Enhances user experience but feature is still valuable without perfect persistence. Can be refined after core toggle functionality works.

**Independent Test**: Can be tested by starting a long-running command in scratchpad terminal, hiding it, performing other work, then showing it again to verify command still running.

**Acceptance Scenarios**:

1. **Given** scratchpad terminal has been hidden for 4 hours, **When** user shows it again, **Then** terminal appears with all command history and session state intact
2. **Given** user started `tail -f logfile.txt` in scratchpad terminal then hid it, **When** user shows terminal 30 minutes later, **Then** tail command still running and showing updates
3. **Given** scratchpad terminal was visible when user switched projects, **When** user switches back to original project and shows scratchpad terminal, **Then** terminal appears in same state as when project was left

---

### Edge Cases

**Case 1: First-time terminal creation**
- **Given**: User has never opened scratchpad terminal for current project
- **When**: User presses scratchpad terminal keybinding
- **Then**: New Alacritty instance launches in project directory, appears as floating window
- **Verify**: Terminal working directory matches project root, terminal is marked as scratchpad for this project

**Case 2: Terminal already visible**
- **Given**: Project scratchpad terminal is currently visible on workspace
- **When**: User presses scratchpad terminal keybinding
- **Then**: Terminal hides to scratchpad
- **Verify**: Terminal disappears from workspace but process remains running, can be restored with same keybinding

**Case 3: Terminal process terminated**
- **Given**: User manually closed scratchpad terminal window (e.g., `exit` command)
- **When**: User presses scratchpad terminal keybinding
- **Then**: New terminal launches as if first-time creation
- **Verify**: System detects terminated process, creates fresh terminal instance

**Case 4: No active project**
- **Given**: User has not switched to any project (global mode)
- **When**: User presses scratchpad terminal keybinding
- **Then**: System launches a global scratchpad terminal with working directory set to user's home directory
- **Verify**: Terminal opens in home directory, behaves like project scratchpad but persists across all projects

**Case 5: Project switch with terminal visible**
- **Given**: Current project's scratchpad terminal is visible on workspace
- **When**: User switches to different project
- **Then**: Current terminal automatically hides to scratchpad as part of project switch
- **Verify**: Terminal for old project becomes hidden, new project's terminal (if any) remains in scratchpad until explicitly shown

**Case 6: Multiple terminals in project**
- **Given**: User has manually launched additional Alacritty windows in the project
- **When**: User presses scratchpad terminal keybinding
- **Then**: Only the designated scratchpad terminal toggles, other terminals unaffected
- **Verify**: Scratchpad terminal is uniquely identified (via mark, app_id, or other mechanism)

## Requirements

### Functional Requirements

**FR-001: Project-Scoped Terminal Creation**
When the user activates the scratchpad terminal keybinding for a project without an existing scratchpad terminal, the system MUST launch a Ghostty terminal instance with its working directory set to the project's root directory. If Ghostty is unavailable, the system MUST fall back to Alacritty.

**FR-002: Terminal Floating Display**
The scratchpad terminal MUST appear as a floating window, centered on the current display, with dimensions of 1400x850 pixels.

**FR-003: Terminal Show/Hide Toggle**
When the user activates the scratchpad terminal keybinding:
- If the project's scratchpad terminal is hidden, it MUST become visible
- If the project's scratchpad terminal is visible, it MUST hide to the scratchpad

**FR-004: Terminal Persistence**
Each project's scratchpad terminal MUST persist across:
- Project switches (terminal remains running in scratchpad)
- Workspace changes within the same project

Scratchpad terminals do NOT persist across Sway/i3 restarts. Users must relaunch terminals after compositor restarts. This is acceptable for the quick-access use case since terminals are inexpensive to recreate.

**FR-005: Terminal Isolation**
Each project MUST maintain its own independent scratchpad terminal instance with:
- Separate process (PID)
- Independent command history
- Isolated working directory

**FR-006: Terminal Identification**
The system MUST uniquely identify each project's scratchpad terminal to distinguish it from:
- Regular Alacritty windows launched by the user
- Scratchpad terminals belonging to other projects
- Windows filtered by project window management

**FR-007: Scratchpad Terminal Keybinding**
The system MUST provide a configurable keybinding for toggling the project scratchpad terminal, with a default binding of `Mod+Shift+Return` or `Control+Alt+Return`.

**FR-008: Keybinding Scope**
The scratchpad terminal keybinding MUST operate on the currently active project's terminal, not a global terminal.

**FR-009: Project-Aware Terminal Launch**
The terminal launch mechanism MUST read the current project context from i3pm to determine:
- Project name/identifier
- Project root directory path
- Whether a scratchpad terminal already exists for this project

**FR-010: Scratchpad vs Filter Separation**
The project scratchpad terminal MUST NOT be affected by the regular project window filtering mechanism. When switching projects, the scratchpad terminal shall remain in the scratchpad (not visible), accessible when switching back to its parent project.

**FR-011: Terminal Cleanup on Project Deletion**
When a project is deleted from i3pm, the associated scratchpad terminal MUST remain running but become orphaned (no longer associated with any project). The terminal continues to function but is not accessible via the project-scoped scratchpad keybinding. Users must manually close the terminal window if desired.

**FR-012: Global Mode Terminal**
When the user activates the scratchpad terminal keybinding without an active project (global mode), the system MUST launch or toggle a global scratchpad terminal with its working directory set to the user's home directory. This terminal persists across all project switches and behaves identically to project-scoped terminals.

**FR-013: Sway Exec Launch Integration**
The system MUST launch scratchpad terminals via Sway IPC `exec` command to ensure proper display server context (WAYLAND_DISPLAY, graphics access) in headless/VNC environments. The system exports I3PM_* environment variables in the shell command before launching the terminal. Direct subprocess launching via asyncio.create_subprocess_exec or systemd-run is NOT permitted due to terminal emulator crashes from missing compositor context.

**FR-014: Window Detection by App ID**
The system MUST detect newly launched terminal windows by searching for windows with matching app_id ("com.mitchellh.ghostty" for Ghostty or "Alacritty" for Alacritty) and without existing scratchpad marks. Since Sway exec does not return a PID, the system cannot use PID-based detection and must rely on app_id matching with a polling timeout of 5 seconds.

**FR-015: PID Retrieval from Window**
After identifying the terminal window by app_id, the system MUST retrieve the process PID from the window object's `pid` attribute for subsequent process validation and management.

**FR-016: Ghostty Terminal Launch**
When launching a scratchpad terminal with Ghostty, the system MUST use the shell command format: `cd '$PROJECT_DIR' && ghostty --title='Scratchpad Terminal'`. Environment variables are exported before the command via shell exports. The window is identifiable via app_id "com.mitchellh.ghostty".

**FR-017: Environment Variable Export Pattern**
The system MUST export I3PM_* environment variables using shell export statements in the format: `export I3PM_APP_ID='value'; export I3PM_PROJECT_NAME='value'; cd '$PROJECT_DIR' && ghostty`. This ensures variables are available in the spawned process despite Sway exec not inheriting daemon's environment.

**FR-018: Daemon Unavailable Error Handling**
If the daemon socket is unavailable when the user activates the scratchpad keybinding, the CLI MUST display a user-friendly error message: "i3pm daemon is not running. Start with: systemctl --user start i3-project-event-listener" and exit with code 1.

**FR-019: Launch Timeout Handling**
If terminal launch exceeds 2 seconds without window appearance, the system MUST terminate the launch attempt, log the timeout, and notify the user: "Terminal launch timed out. Check system logs: journalctl --user -u i3-project-event-listener -n 50".

**FR-020: Concurrent Toggle Protection**
The daemon MUST serialize concurrent toggle requests for the same project using an async lock to prevent race conditions. If a toggle operation is already in progress, subsequent requests MUST wait for completion (max 5 seconds) before processing.

**FR-021: Shell Script Migration**
The system MUST NOT use the legacy shell script (~/.config/sway/scripts/scratchpad-terminal-toggle.sh) for scratchpad terminal management. The keybinding MUST invoke the daemon via `i3pm scratchpad toggle` CLI command.

**FR-022: Window Rule Migration**
The system MUST define window rules for scratchpad terminals using I3PM_APP_NAME environment variable matching instead of hard-coded app_id patterns, ensuring consistency with unified launcher architecture.

**FR-023: Diagnostic Integration**
The system MUST integrate scratchpad terminal status into `i3pm diagnose` command output, showing: terminal count, PID validity, window existence, and state synchronization status.

### Technical Requirements

**TR-001: Sway Exec Launch Method**
The system MUST launch scratchpad terminals using Sway IPC `exec` command instead of Python subprocess or systemd-run. This is CRITICAL for headless/VNC environments where terminal emulators (Ghostty, Alacritty) require proper compositor context (WAYLAND_DISPLAY, EGL/MESA graphics access) that only Sway exec provides. Subprocess launching results in immediate crashes with "failed to get driver name for fd -1" and "failed to choose pdev" errors.

**TR-001a: App Registry Entry**
The system MUST define a scratchpad-terminal entry in app-registry-data.nix with: name="scratchpad-terminal", command="ghostty", scope="scoped", expected_class="com.mitchellh.ghostty", multi_instance=true, with parameter substitution for $PROJECT_DIR and $SESSION_NAME variables.

**TR-002: Environment Variable Injection via Shell Exports**
The system MUST inject I3PM_* environment variables by building a shell command with export statements: `export I3PM_APP_ID='...'; export I3PM_APP_NAME='scratchpad-terminal'; export I3PM_PROJECT_NAME='...'; export I3PM_PROJECT_DIR='...'; export I3PM_SCOPE='scoped'; export I3PM_SCRATCHPAD='true'; export I3PM_WORKING_DIR='...'; cd '$PROJECT_DIR' && ghostty`. This ensures variables are available in the terminal process despite Sway exec not inheriting the daemon's environment.

**TR-003: Ghostty Launch Command**
When launching Ghostty, the system MUST use the command: `cd '$working_dir' && ghostty --title='Scratchpad Terminal'`. The working directory is set via shell `cd` command before launching, not via Ghostty flags. Single quotes around paths ensure proper escaping for paths with spaces.

**TR-004: Ghostty Window Identification by App ID**
The system MUST identify Ghostty windows by searching for windows with app_id="com.mitchellh.ghostty" (exact match, case-sensitive) that do NOT have existing scratchpad marks. The system uses a polling loop with 100ms intervals and 5-second timeout to detect newly created windows.

**TR-005: Window Size Configuration**
Scratchpad terminals MUST use dimensions 1200x700 pixels (updated from original 1400x850) as currently configured in window-rules.json.

**TR-006: Logging Requirements**
The daemon MUST log the following events at INFO level: terminal launch (with PID, project), toggle operations (show/hide with window_id), validation failures (with reason), cleanup operations (with count). ERROR level: launch failures, timeout events, Sway IPC failures.

**TR-007: Performance Measurement**
The system MUST measure toggle latency from RPC request receipt to Sway command completion. Measurement methodology: timestamp at RPC handler entry, timestamp after final Sway IPC command response. Target: <500ms for existing terminals (show/hide), <2s for initial launch.

**TR-008: Keybinding Configuration**
The Sway keybinding MUST be: `bindsym $mod+Shift+Return exec i3pm scratchpad toggle`. The legacy shell script binding MUST be removed from Sway configuration generation.

**TR-009: Comprehensive Async Operation Timeouts**
The system MUST enforce the following timeout requirements for all async operations:
- Launch correlation (notification to window): 2s (FR-015)
- Terminal launch (total): 2s (FR-019)
- Toggle operation (total): 5s (FR-020)
- Window validation (Sway IPC query): 1s
- Status query (daemon RPC): 500ms
- Close operation (window kill): 3s
- Cleanup operation (all terminals): 10s
- Individual Sway IPC commands: 1s per command
If any operation exceeds its timeout, the system MUST log an ERROR and return appropriate error response to client.

### Migration Requirements

**MIG-001: Shell Script Deprecation**
The shell script ~/.config/sway/scripts/scratchpad-terminal-toggle.sh MUST be removed from version control and Sway configuration generation. A deprecation notice MUST be added to CLAUDE.md documenting the replacement with daemon-based approach.

**MIG-002: for_window Rule Update**
The existing for_window rule matching app_id="^scratchpad-terminal(-[a-z0-9-]+)?$" MUST be updated to match windows with I3PM_APP_NAME="scratchpad-terminal" environment variable, using the environment variable matching pattern from Feature 057.

**MIG-003: Configuration File Cleanup**
The sway-config-manager.nix template MUST NOT generate the scratchpad-terminal-toggle.sh script. The scratchpad terminal logic MUST be entirely daemon-based.

**MIG-004: Window Rules Template**
The window-rules.json template in sway-config-manager.nix MUST define scratchpad terminal rules using the new Ghostty-based criteria with environment variable matching.

### Key Entities

**Project Scratchpad Terminal**

**Attributes**:
- Project identifier (name/slug)
- Process ID (PID)
- Window ID (from Sway/i3)
- Working directory path
- Mark/identifier for window tracking
- Creation timestamp
- Last access timestamp

**Relationships**:
- Belongs to exactly one project
- Associated with one Alacritty process
- Tracked by i3pm daemon

**Lifecycle**:
- Created: On first scratchpad terminal keybinding press for a project
- Active: When visible on workspace
- Hidden: When in scratchpad (still running)
- Terminated: When user closes window or process exits

## Success Criteria

### Measurable Outcomes

**SC-001: Terminal Access Speed**
Users can access their project terminal in under 500ms from keybinding press (for existing terminal) or under 2 seconds (for initial launch).

**SC-002: Terminal Availability**
95% of scratchpad terminal toggle operations successfully show or hide the terminal without errors.

**SC-003: Terminal Independence**
Each project maintains a separate terminal instance, verified by:
- Different process IDs for each project's terminal
- Independent command history (commands in project A terminal do not appear in project B terminal)
- Correct working directory set for each project

**SC-004: User Workflow Efficiency**
Terminal toggle operations complete without requiring users to:
- Navigate file system to reach project directory
- Remember which workspace the terminal is on
- Manually resize or reposition the terminal window

**SC-005: Terminal Persistence**
Scratchpad terminals remain functional across project switches, with command history and session state preserved for at least 8 hours of uptime.

## Implementation Philosophy

**Critical Principle**: This feature prioritizes the **optimal solution** over backwards compatibility.

Any existing code, patterns, or approaches that conflict with the optimal design should be **replaced or discarded**. This includes:

- Legacy scratchpad implementations that don't align with the new architecture
- Existing terminal launch mechanisms that are inconsistent with the new approach
- Previous window management patterns that complicate the optimal solution
- Any workarounds or technical debt that would compromise the feature's quality

The implementation should be designed from first principles to deliver the best user experience and maintainability, regardless of how existing systems currently work.

## Assumptions & Constraints

### Assumptions

1. Users have Ghostty installed (with Alacritty as fallback)
2. Projects are defined with a valid root directory path accessible to the user
3. i3pm daemon is running and tracking the active project
4. The scratchpad functionality is available in the Sway/i3 window manager
5. Terminal will use default shell configured in user's environment (e.g., bash, zsh)
6. tmux/sesh integration (if present) will work with scratchpad terminals as with regular terminals
7. Existing legacy code can be refactored or replaced as needed to achieve optimal solution
8. Sway IPC is available via i3ipc.aio Python library for executing commands in compositor context
9. Terminal emulators require proper display server context (WAYLAND_DISPLAY, graphics access) that only Sway exec provides in headless/VNC environments
10. Window detection can rely on app_id matching since Sway exec does not return process PIDs

### Constraints

1. Only one scratchpad terminal per project (no multi-terminal support in this feature)
2. Terminal must be Ghostty with fallback to Alacritty (other terminal emulators not supported)
3. Terminal keybinding operates only within Sway/i3 window manager context
4. Scratchpad terminal is always floating (cannot be tiled)
5. Working directory is always project root (no subdirectory support in initial version)

### Dependencies

- i3pm project management system
- Ghostty terminal emulator (primary), Alacritty (fallback)
- Sway window manager
- i3pm daemon for project context tracking
- i3ipc.aio (Python async Sway IPC library) for executing commands in compositor context
- Sway native scratchpad functionality for window management
- Bash for shell command execution with environment variable exports
- psutil (Python library) for process validation
