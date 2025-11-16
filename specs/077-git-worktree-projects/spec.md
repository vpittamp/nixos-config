# Feature Specification: Git Worktree Project Management

**Feature Branch**: `077-git-worktree-projects`
**Created**: 2025-11-15
**Status**: Draft
**Input**: User description: "review my nixos / home-manager configuration sway project/workspace/window management solution; i want to incorporate git worktrees to create parallel 'projects' that use our project structure to maintain some isolation, and launch apps in the project directory. i'd like this to be dynamic such that i can quickly create a project based on a bare repo and then switch to that project. explore the best options to do this in an automated way that's efficient, fast and creates a great user experience. consider using the eww preview dialog to add a project based on a worktree"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Worktree Project Creation (Priority: P1)

A developer wants to quickly create a new isolated workspace for a feature branch using git worktrees, automatically registering it as an i3pm project without manual configuration.

**Why this priority**: This is the core value proposition - reducing context-switching friction by automating worktree creation and i3pm registration in a single operation.

**Independent Test**: Can be fully tested by running a single command (e.g., `i3pm worktree create feature-name`) and verifying that both the git worktree exists and the i3pm project is registered and switchable.

**Acceptance Scenarios**:

1. **Given** user is in a git repository at `/etc/nixos`, **When** user executes create worktree command with branch name "refactor-sway", **Then** system creates worktree directory, checks out branch, and registers i3pm project with same name
2. **Given** user provides a worktree name "hotfix-123", **When** creation completes, **Then** user can immediately switch to the project using `i3pm project switch` and all scoped apps open in the worktree directory
3. **Given** user is working on main branch, **When** creating worktree for existing remote branch, **Then** system automatically tracks the remote branch and sets up project directory structure

---

### User Story 2 - Visual Worktree Selection and Management (Priority: P2)

A developer wants to see all available worktrees in a visual menu (Eww dialog) with metadata like branch name, last modified time, and git status, enabling quick selection and switching.

**Why this priority**: Provides discoverability and visual feedback for worktree-based projects, making the system intuitive for users who prefer GUI over CLI.

**Independent Test**: Can be tested by opening the Eww dialog (e.g., via `Win+P` when in worktree mode), verifying all worktrees are listed with correct metadata, and confirming that selecting one switches the i3pm project.

**Acceptance Scenarios**:

1. **Given** user has 3 worktrees created, **When** user opens worktree selector dialog, **Then** all 3 worktrees are displayed with branch names, directory paths, and uncommitted changes indicator
2. **Given** user selects a worktree from the dialog, **When** selection is confirmed, **Then** i3pm switches to that project and all scoped apps (terminal, editor, file manager) open in the worktree directory
3. **Given** a worktree has uncommitted changes, **When** displayed in selector, **Then** visual indicator (icon or color) shows dirty working tree status

---

### User Story 3 - Seamless Project Directory Context (Priority: P1)

A developer switches between worktree-based projects and expects all project-scoped applications (terminal, VS Code, file manager) to automatically open in the correct worktree directory without manual navigation.

**Why this priority**: This is essential for the isolation promise - each worktree should feel like a completely independent workspace with automatic directory context.

**Independent Test**: Can be tested by switching projects and launching scoped apps (terminal, VS Code, Yazi), verifying each opens with CWD set to the worktree directory.

**Acceptance Scenarios**:

1. **Given** user is in project "feature-A" (worktree at `/home/user/repos/feature-A`), **When** user launches terminal via `Win+Return`, **Then** terminal opens with working directory `/home/user/repos/feature-A`
2. **Given** user switches from "feature-A" to "feature-B" worktree project, **When** VS Code is launched, **Then** VS Code opens with workspace root at feature-B's worktree directory
3. **Given** user opens Yazi file manager in a worktree project, **When** Yazi starts, **Then** it displays the worktree directory as the initial path

---

### User Story 4 - Worktree Cleanup and Removal (Priority: P3)

A developer finishes work on a feature branch and wants to remove the associated worktree and i3pm project registration in a single operation, with safety checks to prevent data loss.

**Why this priority**: Lower priority than creation/switching, but necessary for long-term usability to prevent abandoned worktrees from cluttering the system.

**Independent Test**: Can be tested by deleting a worktree project, verifying the worktree directory is removed, git worktree is pruned, and i3pm project is unregistered.

**Acceptance Scenarios**:

1. **Given** user has finished work on worktree "hotfix-123", **When** user executes delete command, **Then** system prompts for confirmation if uncommitted changes exist
2. **Given** user confirms deletion of a clean worktree, **When** deletion completes, **Then** worktree directory is removed, git worktree list no longer shows it, and i3pm project list does not include it
3. **Given** user attempts to delete currently active worktree project, **When** command is executed, **Then** system prevents deletion and suggests switching to another project first

---

### User Story 5 - Automatic Worktree Discovery on Startup (Priority: P2)

When the system starts or i3pm daemon restarts, existing git worktrees are automatically discovered and registered as i3pm projects if they aren't already, ensuring consistency between git state and i3pm state.

**Why this priority**: Ensures resilience and reduces manual maintenance - users shouldn't need to manually re-register worktrees after system restarts or git operations performed outside the tooling.

**Independent Test**: Can be tested by creating a worktree manually via `git worktree add`, restarting i3pm daemon, and verifying the worktree appears in the project list.

**Acceptance Scenarios**:

1. **Given** user creates worktree via `git worktree add ../feature-X`, **When** i3pm daemon restarts or discovery command runs, **Then** "feature-X" appears in i3pm project list
2. **Given** user has 5 worktrees but only 3 registered i3pm projects, **When** auto-discovery runs, **Then** the 2 unregistered worktrees are added as i3pm projects
3. **Given** an i3pm project references a worktree that no longer exists in git, **When** discovery runs, **Then** the orphaned project is flagged for cleanup or automatically removed

---

### Edge Cases

- What happens when user tries to create a worktree with a name that conflicts with an existing i3pm project?
- How does system handle worktree creation when disk space is insufficient?
- What occurs if git worktree operation fails midway (e.g., network issue during branch checkout)?
- How are nested git repositories within worktrees handled?
- What happens when user manually deletes a worktree directory without using the removal command?
- How does the system behave when switching to a worktree project that has merge conflicts?
- What happens when a worktree's branch is deleted from remote but worktree still exists locally?
- How are worktrees created from detached HEAD states handled?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a command to create a new git worktree and simultaneously register it as an i3pm project with a single operation
- **FR-002**: System MUST support creating worktrees from both new and existing branches (local or remote)
- **FR-003**: System MUST automatically set the project directory for i3pm to the worktree path
- **FR-004**: System MUST configure all project-scoped applications to use the worktree directory as their working directory
- **FR-005**: System MUST provide a visual selector (Eww dialog) showing all available worktrees with metadata (branch name, status, last modified)
- **FR-006**: System MUST display git status indicators (uncommitted changes, untracked files) in the worktree selector
- **FR-007**: System MUST allow switching between worktree-based projects using existing i3pm project switching mechanisms
- **FR-008**: System MUST provide a command to remove a worktree and its i3pm project registration together
- **FR-009**: System MUST warn users before deleting worktrees with uncommitted changes or untracked files
- **FR-010**: System MUST prevent deletion of the currently active worktree project
- **FR-011**: System MUST automatically discover existing git worktrees and register them as i3pm projects on daemon startup
- **FR-012**: System MUST detect and clean up orphaned i3pm projects that reference non-existent worktrees
- **FR-013**: System MUST support configurable worktree base directory (default: sibling to main repository)
- **FR-014**: System MUST preserve i3pm project metadata (icon, display name, scoped apps) for worktree projects
- **FR-015**: System MUST handle worktree naming conflicts by either auto-incrementing names or prompting for alternative
- **FR-016**: System MUST validate git repository state before attempting worktree operations
- **FR-017**: System MUST provide clear error messages when worktree operations fail (e.g., branch already exists, insufficient permissions)
- **FR-018**: System MUST track which i3pm projects are worktree-managed vs. regular directory-based projects
- **FR-019**: System MUST allow users to specify custom branch names separate from worktree directory names
- **FR-020**: System MUST update Eww project switcher to include worktree-specific metadata when displaying projects

### Key Entities

- **Worktree Project**: An i3pm project that corresponds to a git worktree, containing metadata linking the project to its git branch and worktree path
- **Worktree Metadata**: Information about a worktree including branch name, creation date, last modified time, git status (clean/dirty), and commit count ahead/behind remote
- **Project Directory Binding**: Association between an i3pm project and a filesystem path, used to set working directory for scoped applications
- **Scoped Application**: Applications (terminal, editor, file manager) that automatically inherit the project's working directory context when launched

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can create a new worktree-based project and switch to it in under 5 seconds (from command execution to first scoped app opening in worktree directory)
- **SC-002**: Switching between worktree projects takes less than 500ms (same as regular i3pm project switching)
- **SC-003**: 100% of scoped applications (terminal, VS Code, Yazi, Lazygit) correctly open in the worktree directory when launched
- **SC-004**: Worktree selector dialog displays complete metadata (branch, status, path) for all worktrees within 200ms of opening
- **SC-005**: System successfully discovers and registers 100% of manually created worktrees on daemon restart
- **SC-006**: Zero data loss incidents - system never deletes worktrees with uncommitted changes without explicit user confirmation
- **SC-007**: Worktree creation success rate exceeds 99% for valid git repositories
- **SC-008**: Users can manage (create, switch, delete) at least 10 concurrent worktree projects without performance degradation

## Assumptions

- Users are working with git repositories that support worktrees (git version 2.5+)
- The base repository is already cloned and accessible
- i3pm daemon is running and responsive
- Users have sufficient disk space for multiple worktrees (typically same size as repository)
- Project-scoped applications are already configured in i3pm app registry
- Eww widget system is available and configured for the project switcher
- Users have basic git knowledge (understand branches and worktrees concept)
- Worktree base directory is writable by the user
- Git operations (checkout, worktree add/remove) complete within reasonable time (< 30 seconds for typical repositories)
- Users primarily work with one git repository per project type (e.g., one NixOS config repo with multiple feature worktrees)

## Dependencies

- Existing i3pm project management system (project creation, switching, deletion)
- i3pm daemon with event listener for project state changes
- Eww widget framework for visual dialogs
- Git worktree functionality (requires git CLI available)
- App registry with scoped application definitions
- Project directory context mechanism (environment variables or working directory setting)
- File system permissions for creating/deleting directories in worktree base path

## Scope

### In Scope

- Automated git worktree creation integrated with i3pm project registration
- Visual worktree selector with git status metadata
- Automatic working directory context for scoped applications
- Worktree cleanup and removal with safety checks
- Auto-discovery of existing worktrees
- Conflict resolution for duplicate project names
- Error handling for common git worktree failures

### Out of Scope

- Managing multiple different git repositories (feature focuses on multiple worktrees of a single repository)
- Git operations beyond worktree management (commits, pushes, merges, rebases)
- Workspace layout persistence specific to worktrees (covered by existing Feature 074 session management)
- Cross-machine worktree synchronization
- Worktree-specific Sway window rules or keybindings
- Integration with git GUI tools beyond command-line git
- Migration tools for converting existing i3pm projects to worktree-based projects
- Backup or versioning of worktree directories
