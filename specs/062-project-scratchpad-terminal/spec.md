# Feature Specification: Project-Scoped Scratchpad Terminal

**Feature Number**: 062
**Status**: Draft
**Created**: 2025-11-05
**Last Updated**: 2025-11-05

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

1. **Given** user is in project "nixos", **When** user presses scratchpad terminal keybinding for first time, **Then** Alacritty terminal opens as floating window centered on display with working directory set to nixos project root
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
When the user activates the scratchpad terminal keybinding for a project without an existing scratchpad terminal, the system MUST launch an Alacritty terminal instance with its working directory set to the project's root directory.

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

1. Users have Alacritty installed and configured as the default terminal
2. Projects are defined with a valid root directory path accessible to the user
3. i3pm daemon is running and tracking the active project
4. The scratchpad functionality is available in the Sway/i3 window manager
5. Terminal will use default shell configured in user's environment (e.g., bash, zsh)
6. tmux/sesh integration (if present) will work with scratchpad terminals as with regular terminals
7. Existing legacy code can be refactored or replaced as needed to achieve optimal solution

### Constraints

1. Only one scratchpad terminal per project (no multi-terminal support in this feature)
2. Terminal must be Alacritty (other terminal emulators not supported)
3. Terminal keybinding operates only within Sway/i3 window manager context
4. Scratchpad terminal is always floating (cannot be tiled)
5. Working directory is always project root (no subdirectory support in initial version)

### Dependencies

- i3pm project management system
- Alacritty terminal emulator
- Sway window manager
- i3pm daemon for project context tracking
- Existing scratchpad infrastructure in Sway (may be refactored/replaced if needed)
