# Feature Specification: Revise Projects Tab with Full CRUD Capabilities

**Feature Branch**: `099-revise-projects-tab`
**Created**: 2025-11-28
**Status**: Draft
**Input**: User description: "Revise the second tab (Projects) in the Eww monitoring widget to correctly provide CRUD capabilities for projects/worktrees, utilizing i3pm worktree commands from Features 097 and 098. Ensure discovery of git repos and worktrees in the home directory, add/edit/delete worktree operations, and verify all functionality works correctly with a great user experience."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discover Git Repositories and Worktrees (Priority: P1)

A developer opens the Projects tab and wants to see all git repositories and worktrees from their home directory automatically discovered and displayed in a hierarchical view. Repository projects appear as expandable containers with their associated worktrees nested underneath.

**Why this priority**: Discovery is the foundation - without it, users cannot see or manage their projects. The system must accurately reflect the actual git state on disk.

**Independent Test**: Open the Projects tab, verify all git repositories in the home directory are displayed with their worktrees grouped correctly under parent repositories.

**Acceptance Scenarios**:

1. **Given** `/etc/nixos` is a git repository with bare repo at `/home/vpittamp/nixos-config.git`, **When** user opens Projects tab, **Then** "nixos" appears as a Repository Project with an expandable indicator showing worktree count.

2. **Given** multiple worktrees exist for nixos (e.g., `nixos-097-*`, `nixos-098-*`, `nixos-099-*`), **When** user expands the nixos project, **Then** all worktrees appear nested with indent, showing branch name, status indicators (clean/dirty), and branch metadata.

3. **Given** a standalone git repository at `/home/vpittamp/other-repo` with no worktrees, **When** user views Projects tab, **Then** it appears as a standalone project without expandable indicator.

4. **Given** the projects data is stale (new worktree created externally), **When** user clicks [Refresh], **Then** the new worktree appears within 2 seconds.

---

### User Story 2 - Create New Worktree from Projects Tab (Priority: P1)

A developer wants to create a new feature worktree directly from the Projects tab by clicking a "Create Worktree" button on a repository project. The form allows entering a feature description or branch name, and the worktree is created and registered automatically.

**Why this priority**: Worktree creation is the primary workflow for starting new features. Users should be able to create worktrees without leaving the monitoring panel.

**Independent Test**: Click "Create Worktree" on a repository, enter branch name, verify git worktree is created on disk and appears in the panel nested under the parent.

**Acceptance Scenarios**:

1. **Given** Repository Project "nixos" is displayed with [+ New Worktree] button visible, **When** user clicks the button, **Then** a creation form appears with fields for branch name (required) and optional display name/icon.

2. **Given** user enters branch name "100-new-feature" in the form, **When** user clicks [Create], **Then**:
   - `i3pm worktree create 100-new-feature` is executed
   - Git worktree is created at `/home/vpittamp/nixos-100-new-feature`
   - New worktree appears nested under "nixos" with branch metadata parsed
   - Success notification appears briefly

3. **Given** user enters a branch name that already exists as a local branch, **When** user clicks [Create], **Then** the system offers: (a) checkout existing branch to new worktree, or (b) enter different name.

4. **Given** worktree creation fails (e.g., directory exists, permission error), **When** error occurs, **Then** error message appears in the form, no orphaned project entry is created, and form remains open for correction.

---

### User Story 3 - Delete Worktree from Projects Tab (Priority: P1)

A developer has finished work on a feature branch and wants to remove the worktree. Deleting removes both the git worktree and the project registration.

**Why this priority**: Complete lifecycle management - create and delete must both work from the UI.

**Independent Test**: Select a worktree, click delete, confirm, verify git worktree is removed from filesystem and disappears from panel.

**Acceptance Scenarios**:

1. **Given** Worktree "097-convert-manual-projects" is displayed with hover actions visible, **When** user clicks [Delete] button, **Then** a confirmation dialog appears with the worktree name and warning about permanent deletion.

2. **Given** confirmation dialog is shown for "097-convert-manual-projects", **When** user clicks [Confirm Delete], **Then**:
   - `i3pm worktree remove 097-convert-manual-projects` is executed
   - Git worktree is removed from filesystem
   - Project JSON file is deleted
   - Worktree disappears from panel
   - Parent repository's worktree count decreases
   - Success notification appears

3. **Given** worktree has uncommitted changes, **When** user clicks delete, **Then** confirmation shows warning: "This worktree has uncommitted changes. They will be lost. Delete anyway?" with [Cancel] [Force Delete] options.

4. **Given** git worktree was already removed externally (orphaned project entry), **When** user deletes the entry, **Then** only the project registration is cleaned up (no git error shown).

---

### User Story 4 - Edit Project/Worktree Properties (Priority: P2)

A developer wants to customize the display name, icon, or scope of a project or worktree. Edits are saved to the project JSON file and reflected immediately in the UI.

**Why this priority**: Customization improves usability but is not critical for basic workflow.

**Independent Test**: Click edit on a project, change display name, save, verify the change persists and is reflected in the panel.

**Acceptance Scenarios**:

1. **Given** project "nixos" is hovered, **When** user clicks [Edit] button, **Then** an inline edit form appears with current values populated (display name, icon, scope).

2. **Given** edit form is open for "nixos", **When** user changes display name to "NixOS Configuration" and clicks [Save], **Then**:
   - Project JSON is updated
   - Panel reflects new display name immediately
   - Form closes
   - Success notification appears

3. **Given** a worktree project edit form is open, **When** user views the form, **Then** branch name and worktree path are displayed as read-only (cannot be changed after creation).

4. **Given** user enters invalid data (empty display name, invalid icon path), **When** validation runs, **Then** inline error messages appear and save is disabled until corrected.

---

### User Story 5 - Switch to Project/Worktree (Priority: P1)

A developer wants to switch their workspace context to a different project by clicking on it in the Projects tab. Switching activates that project's directory for scoped applications.

**Why this priority**: This is the core purpose of i3pm projects - workspace context switching.

**Independent Test**: Click on a worktree project in the panel, verify scoped apps now use that worktree's directory.

**Acceptance Scenarios**:

1. **Given** current project is "nixos" (shown with active indicator), **When** user clicks on worktree "099-revise-projects-tab", **Then**:
   - `i3pm project switch 099-revise-projects-tab` is executed
   - Active indicator moves from "nixos" to "099-revise-projects-tab"
   - Scoped apps now use `/home/vpittamp/nixos-099-revise-projects-tab` as working directory

2. **Given** user is in a worktree project, **When** user clicks on parent Repository Project "nixos", **Then** context moves to the main repository directory `/etc/nixos`.

3. **Given** a project has status "missing" (directory doesn't exist), **When** user clicks to switch to it, **Then** an error notification appears: "Cannot switch - project directory does not exist" and current project remains unchanged.

---

### User Story 6 - View Worktree Git Status and Metadata (Priority: P2)

A developer viewing the Projects tab sees git status indicators for each project/worktree: current branch, clean/dirty status, ahead/behind counts. The hierarchical view bubbles up status from worktrees to parents.

**Why this priority**: Visual status helps developers quickly identify which worktrees need attention (uncommitted changes, need to push).

**Independent Test**: Create uncommitted changes in a worktree, verify dirty indicator appears on both the worktree AND bubbles up to the parent repository.

**Acceptance Scenarios**:

1. **Given** worktree "097-convert-manual-projects" has uncommitted changes, **When** viewing the Projects tab, **Then** a dirty indicator (● red) appears next to the worktree branch name AND a summary indicator appears on the collapsed parent "nixos".

2. **Given** worktree "098-integrate-new-project" is 3 commits ahead of origin, **When** viewing expanded worktree details, **Then** ahead/behind counts are displayed (↑3).

3. **Given** parent Repository Project is collapsed, **When** any child worktree has activity (dirty, ahead/behind), **Then** an aggregate indicator appears on the parent showing count of worktrees with uncommitted changes.

4. **Given** user clicks [Refresh] on a project, **When** refresh completes, **Then** git metadata updates within 2 seconds to reflect current state.

---

### Edge Cases

- What happens when a worktree's parent repository project doesn't exist (orphaned worktree)?
  - System displays orphaned worktrees in a separate "Orphaned" section with [Recover] option to discover and register the parent.

- What happens when branch name doesn't follow expected pattern (e.g., "main", "develop")?
  - System stores `branch_number: null`, `branch_type: null`, displays just the branch name without parsed metadata.

- What happens when target worktree directory already exists during creation?
  - System shows error: "Directory already exists: /path/to/dir" and allows user to choose a different name.

- What happens when user rapidly clicks [Create] multiple times?
  - Form disables submit button during creation (loading state), preventing duplicate requests.

- What happens when project JSON is modified externally while edit form is open?
  - System detects mtime change on save and shows conflict warning, allowing user to discard changes or overwrite.

- What happens when git worktree remove fails (e.g., locked by process)?
  - System shows error message from git and leaves project entry intact; user can retry or force delete.

## Requirements *(mandatory)*

### Functional Requirements

**Discovery (FR-D)**:
- **FR-D-001**: System MUST discover all git repositories in `$HOME` that are not bare repositories
- **FR-D-002**: System MUST identify worktrees by detecting when `.git` is a file (gitdir reference) vs directory
- **FR-D-003**: System MUST group worktrees under their parent repository using `git rev-parse --git-common-dir`
- **FR-D-004**: System MUST extract git metadata (branch, commit, clean/dirty, ahead/behind) for each project
- **FR-D-005**: System MUST provide [Refresh] action to re-scan and update all project/worktree data
- **FR-D-006**: System MUST identify orphaned worktrees (worktrees whose parent repository is not registered)

**Worktree CRUD (FR-W)**:
- **FR-W-001**: System MUST provide [+ New Worktree] button on repository projects in the monitoring panel
- **FR-W-002**: System MUST execute `i3pm worktree create <branch>` when user submits creation form
- **FR-W-003**: System MUST register new worktrees with correct `parent_project`, `bare_repo_path`, and branch metadata
- **FR-W-004**: System MUST provide [Delete] action on worktree projects
- **FR-W-005**: System MUST execute `i3pm worktree remove <name>` when user confirms deletion
- **FR-W-006**: System MUST warn when worktree has uncommitted changes before deletion
- **FR-W-007**: System MUST handle existing branch names by offering checkout or rename options
- **FR-W-008**: System MUST prevent double-submission during create/delete operations via loading state

**Hierarchy Display (FR-H)**:
- **FR-H-001**: System MUST display repository projects as expandable containers with worktree count badge
- **FR-H-002**: System MUST nest worktree projects under their parent repository with visual indent
- **FR-H-003**: System MUST show dirty/ahead-behind indicators that bubble up from worktrees to parent
- **FR-H-004**: System MUST display orphaned worktrees in a separate visual section with recovery options
- **FR-H-005**: System MUST highlight the currently active project distinctly

**Edit Operations (FR-E)**:
- **FR-E-001**: System MUST provide inline edit form for projects and worktrees
- **FR-E-002**: System MUST allow editing display name, icon, and scope
- **FR-E-003**: System MUST display branch name and worktree path as read-only for worktrees
- **FR-E-004**: System MUST validate input fields in real-time (300ms debounce)
- **FR-E-005**: System MUST detect file conflicts and warn before overwriting external changes

**Project Switching (FR-S)**:
- **FR-S-001**: System MUST allow switching to any project by clicking on it
- **FR-S-002**: System MUST execute `i3pm project switch <name>` on selection
- **FR-S-003**: System MUST prevent switching to projects with status "missing"
- **FR-S-004**: System MUST update active indicator immediately upon successful switch

### Key Entities

- **Repository Project**: A project representing the primary entry point for a git repository. Has expandable worktree list, supports [+ New Worktree] action.

- **Worktree Project**: A project representing a git worktree. Has `parent_project` reference, branch metadata (number, type, full_name), and supports edit/delete actions but not creation of sub-worktrees.

- **Orphaned Worktree**: A worktree project whose parent repository is not registered. Displayed separately with recovery options.

- **Git Metadata**: Per-project data including branch name, commit hash, clean/dirty status, ahead/behind counts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can discover and view all git repositories and worktrees in the Projects tab within 3 seconds of opening the panel

- **SC-002**: Users can create a new worktree via the panel in under 30 seconds (form fill + creation)

- **SC-003**: Users can delete a worktree via the panel in under 10 seconds (click + confirm)

- **SC-004**: 100% of git repositories in `$HOME` with worktrees are correctly grouped hierarchically

- **SC-005**: Git status indicators update within 2 seconds of clicking [Refresh]

- **SC-006**: Zero orphaned project entries remain after worktree deletion (both git worktree and JSON cleaned up)

- **SC-007**: Users can switch projects with single click, active indicator updates in under 500ms
