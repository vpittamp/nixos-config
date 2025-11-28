# Feature Specification: Git-Centric Project and Worktree Management

**Feature Branch**: `097-convert-manual-projects`
**Created**: 2025-11-26
**Updated**: 2025-11-28
**Status**: Draft
**Input**: User description: "Redesign i3pm project management around git's native architecture. Use bare repository paths as the canonical identifier for grouping worktrees. Eliminate legacy manual project creation in favor of git-based discovery. Provide full worktree CRUD operations via the monitoring panel UI."

## Architecture Vision

### Core Principle: Git is the Source of Truth

The git bare repository (`GIT_COMMON_DIR`) is the canonical identifier for all related worktrees. An i3pm "project" is a user-facing registration that points to a working directory, with relationships derived from git's actual structure.

### Key Concepts

1. **Bare Repository**: The shared `.git` directory (e.g., `/home/user/nixos-config.git`) that contains the object database and tracks all worktrees. This is the **single identifier** that groups related projects.

2. **Repository Project**: An i3pm project representing the primary entry point for a bare repository. Only ONE per bare repo. Points to a chosen working directory (e.g., `/etc/nixos`).

3. **Worktree Project**: An i3pm project representing a feature branch worktree. Has explicit `parent_project` linking to the Repository Project. Many can exist per bare repo.

4. **Standalone Project**: A project for a repository with no worktrees, or a non-git directory.

### Relationship Model

```
Bare Repo: /home/user/nixos-config.git
    │
    ├── Repository Project: "nixos" → /etc/nixos (main branch)
    │       │
    │       ├── Worktree Project: "097-feature" → /home/user/nixos-097-feature
    │       ├── Worktree Project: "087-ssh" → /home/user/nixos-087-ssh
    │       └── Worktree Project: "085-widget" → /home/user/nixos-085-widget
    │
Bare Repo: /home/user/other-repo/.git
    │
    └── Standalone Project: "other-repo" → /home/user/other-repo
```

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discover and Register Repository (Priority: P1)

A developer wants to register a git repository as an i3pm project. The system discovers the repository's bare repo path and creates a Repository Project that serves as the parent for all worktrees.

**Why this priority**: This is the foundation - establishing the single source of truth by using git's actual structure.

**Independent Test**: Run discovery on a directory containing a git repo, verify a project is created with correct `bare_repo_path` and `source_type`.

**Acceptance Scenarios**:

1. **Given** a git repository at `/etc/nixos` with bare repo at `/home/user/nixos-config.git`, **When** the user runs `i3pm project discover --path /etc/nixos`, **Then** a Repository Project is created with `bare_repo_path: "/home/user/nixos-config.git"` and `source_type: "repository"`.

2. **Given** a bare repo already has a registered Repository Project, **When** discovery finds another worktree of the same bare repo, **Then** that worktree is registered as a Worktree Project linked to the existing Repository Project (not a duplicate).

3. **Given** a standalone repository at `/home/user/other-repo` with no worktrees, **When** discovery runs, **Then** a Standalone Project is created with `source_type: "standalone"` and no parent linkage.

---

### User Story 2 - Create Worktree from Repository Project (Priority: P1)

A developer viewing a Repository Project in the Projects tab wants to create a new worktree for a feature branch. The worktree is created via git and automatically registered as a Worktree Project linked to the parent.

**Why this priority**: Creating worktrees is the primary workflow. The UI must invoke `i3pm worktree create` which handles both git operations and project registration.

**Independent Test**: Click "Create Worktree" on a Repository Project, enter branch name, verify worktree is created on filesystem and appears in panel with correct parent linkage.

**Acceptance Scenarios**:

1. **Given** Repository Project "nixos" is displayed, **When** the user clicks [+ Create Worktree] and enters branch "098-new-feature", **Then**:
   - `git worktree add` creates `/home/user/nixos-098-new-feature`
   - A Worktree Project is created with `parent_project: "nixos"` and `bare_repo_path` matching the parent
   - The new worktree appears nested under "nixos" in the panel

2. **Given** branch "098-new-feature" already exists, **When** user enters that name, **Then** the system offers: (a) checkout existing branch, or (b) create new branch with different name.

3. **Given** worktree creation fails (disk full, permission error), **When** the error occurs, **Then** user sees clear error message and no orphaned project entry is created.

---

### User Story 3 - View Repository with Worktree Hierarchy (Priority: P1)

A developer viewing the Projects tab sees Repository Projects with their Worktree Projects nested underneath, clearly showing the git structure.

**Why this priority**: Visual hierarchy is essential for understanding relationships and navigating between related projects.

**Independent Test**: Register a Repository Project with 3 worktrees, verify panel displays hierarchy with expand/collapse and worktree count.

**Acceptance Scenarios**:

1. **Given** Repository Project "nixos" with 5 Worktree Projects, **When** viewing Projects tab, **Then**:
   - "nixos" appears as expandable item showing "(5 worktrees)"
   - Expanding shows all 5 worktrees indented underneath
   - Each worktree shows branch name, commit, and status indicators

2. **Given** a Worktree Project has uncommitted changes, **When** viewing the hierarchy, **Then** the dirty indicator (●) appears on both the worktree AND bubbles up to the parent Repository Project.

3. **Given** Repository Project is collapsed, **When** any child worktree has activity (dirty, ahead/behind), **Then** an aggregate indicator shows on the collapsed parent.

---

### User Story 4 - Delete Worktree from Panel (Priority: P1)

A developer has finished work on a feature branch and wants to remove the worktree. The system removes both the git worktree and the project registration.

**Why this priority**: Complete lifecycle management - create and delete must both work from UI.

**Independent Test**: Select a Worktree Project, click delete, confirm, verify git worktree is removed and project disappears from panel.

**Acceptance Scenarios**:

1. **Given** Worktree Project "097-feature" is selected, **When** user clicks [Delete] and confirms, **Then**:
   - `git worktree remove` is executed
   - Project JSON file is deleted
   - Worktree disappears from panel
   - Parent Repository Project's worktree count decreases

2. **Given** worktree has uncommitted changes, **When** user clicks delete, **Then** confirmation shows warning: "This worktree has uncommitted changes. Delete anyway?" with [Cancel] [Force Delete] options.

3. **Given** git worktree was already removed externally, **When** user deletes the orphaned project entry, **Then** only the project registration is cleaned up (no git error).

---

### User Story 5 - Switch to Project (Priority: P1)

A developer wants to switch their workspace context to a different project (Repository or Worktree). Switching activates that project's directory for scoped applications.

**Why this priority**: The core purpose of i3pm projects - workspace context switching.

**Independent Test**: Switch to a Worktree Project, verify scoped apps launch in that worktree's directory.

**Acceptance Scenarios**:

1. **Given** current project is "nixos", **When** user clicks on Worktree Project "097-feature" and selects [Switch], **Then** `i3pm project switch 097-feature` is executed and scoped apps now use `/home/user/nixos-097-feature` as working directory.

2. **Given** user is in a Worktree Project, **When** user clicks on parent Repository Project and switches, **Then** context moves to the main repository directory.

---

### User Story 6 - Refresh Git Metadata (Priority: P2)

A developer wants to update the git status displayed in the panel after making commits or pulling changes.

**Why this priority**: Important for accuracy but not blocking core workflow.

**Independent Test**: Make a commit in a worktree, click refresh, verify commit hash and status update in panel.

**Acceptance Scenarios**:

1. **Given** Worktree Project shows commit "abc1234", **When** user makes a commit and clicks [Refresh], **Then** commit hash updates to new value within 2 seconds.

2. **Given** Projects tab is visible, **When** user clicks [Refresh All] button, **Then** all projects' git metadata updates.

---

### User Story 7 - Handle Orphaned Worktrees (Priority: P2)

A worktree exists on disk but its parent Repository Project was deleted or never registered. The system identifies these orphans and allows recovery.

**Why this priority**: Data integrity - prevent lost worktrees.

**Independent Test**: Delete a Repository Project, verify its worktrees appear in "Orphaned" section with recovery options.

**Acceptance Scenarios**:

1. **Given** Repository Project "nixos" is deleted, **When** panel refreshes, **Then** all former child Worktree Projects appear in "Orphaned Worktrees" section with message: "Parent repository not registered".

2. **Given** an orphaned worktree exists, **When** user clicks [Recover], **Then** the system discovers the bare repo and offers to create a new Repository Project for it.

3. **Given** an orphaned worktree's directory no longer exists, **When** viewing orphans, **Then** it shows as "Missing" with option to [Delete Registration].

---

### Edge Cases

**Repository Identity**:
- What identifies a repository? The `bare_repo_path` (GIT_COMMON_DIR) - e.g., `/home/user/nixos-config.git`. All worktrees sharing this path belong to the same logical repository.
- What if two directories resolve to the same bare repo? The first discovered becomes the Repository Project; subsequent ones become Worktree Projects automatically linked to it.
- What about standalone repos (no worktrees)? They have `source_type: "standalone"` with `bare_repo_path` pointing to their `.git` directory.

**Worktree Operations**:
- What happens when creating a worktree for an existing branch? Offer choice: checkout existing or create new branch.
- What if target directory exists? Error with clear message; do not overwrite.
- What if worktree has uncommitted changes on delete? Warn and require force confirmation.
- What if git worktree is already gone but project exists? Clean up project registration only.
- What if multiple worktrees for same branch attempted? Git prevents this; surface git's error message.

**Orphan Handling**:
- What makes a worktree orphaned? Its `bare_repo_path` has no registered Repository Project.
- How to recover orphaned worktrees? Discover and register a Repository Project for that bare repo.
- What if orphan's directory is missing? Show as "Missing" with delete-registration-only option.

**Data Integrity**:
- Single Repository Project per bare repo - enforced constraint.
- Worktree Projects always have `parent_project` pointing to a valid Repository Project name.
- `bare_repo_path` is computed from git, not user-specified - prevents inconsistencies.

## Requirements *(mandatory)*

### Functional Requirements

**Core Architecture (FR-A)**:
- **FR-A-001**: System MUST use `bare_repo_path` (GIT_COMMON_DIR) as the canonical identifier for grouping related projects.
- **FR-A-002**: System MUST enforce exactly ONE Repository Project per unique `bare_repo_path`.
- **FR-A-003**: System MUST require all Worktree Projects to have a valid `parent_project` reference to a Repository Project.
- **FR-A-004**: System MUST compute `bare_repo_path` from git (via `git rev-parse --git-common-dir`), never from user input.
- **FR-A-005**: System MUST classify projects as: `repository` (primary entry for a bare repo), `worktree` (linked to a repository), or `standalone` (no worktrees).

**Discovery (FR-D)**:
- **FR-D-001**: System MUST discover git repositories by detecting `.git` directories or files.
- **FR-D-002**: System MUST extract git metadata: branch, commit, clean/dirty, ahead/behind, remote URL.
- **FR-D-003**: System MUST detect if a directory is a worktree (`.git` is a file pointing to bare repo).
- **FR-D-004**: System MUST automatically link discovered worktrees to existing Repository Projects with matching `bare_repo_path`.
- **FR-D-005**: System MUST create a Repository Project when discovering a bare repo's first working directory.
- **FR-D-006**: System MUST identify orphaned worktrees (no matching Repository Project exists).

**Worktree CRUD (FR-W)**:
- **FR-W-001**: System MUST provide [+ Create Worktree] action on Repository Projects in the monitoring panel.
- **FR-W-002**: System MUST execute `i3pm worktree create <branch>` when user submits creation form.
- **FR-W-003**: System MUST register the new worktree as a Worktree Project with correct `parent_project` and `bare_repo_path`.
- **FR-W-004**: System MUST provide [Delete] action on Worktree Projects.
- **FR-W-005**: System MUST execute `i3pm worktree remove <name>` when user confirms deletion.
- **FR-W-006**: System MUST warn if worktree has uncommitted changes before deletion.
- **FR-W-007**: System MUST handle existing branch names by offering checkout-existing or create-new options.
- **FR-W-008**: System MUST provide [Refresh] action to update git metadata.

**Hierarchy Display (FR-H)**:
- **FR-H-001**: System MUST display Repository Projects as expandable containers.
- **FR-H-002**: System MUST nest Worktree Projects under their parent Repository Project.
- **FR-H-003**: System MUST show worktree count badge on collapsed Repository Projects.
- **FR-H-004**: System MUST bubble up dirty/ahead-behind indicators from worktrees to parent.
- **FR-H-005**: System MUST display orphaned worktrees in a separate "Orphaned" section.
- **FR-H-006**: System MUST provide [Recover] action for orphaned worktrees to create missing Repository Project.

**Project Switching (FR-S)**:
- **FR-S-001**: System MUST allow switching to any project (Repository or Worktree) from the panel.
- **FR-S-002**: System MUST execute `i3pm project switch <name>` on selection.
- **FR-S-003**: System MUST highlight the currently active project in the hierarchy.

### Key Entities

**Unified Project Model**:
```
Project {
  // Identity
  name: string                    // Unique i3pm identifier (e.g., "nixos", "097-feature")
  directory: string               // Working directory path
  display_name: string            // Human-readable name
  icon: string                    // Emoji icon

  // Classification
  source_type: "repository" | "worktree" | "standalone"
  status: "active" | "missing" | "orphaned"

  // Git Identity (computed, never user-specified)
  bare_repo_path: string          // GIT_COMMON_DIR - the canonical repo identifier

  // Relationships
  parent_project: string | null   // Name of Repository Project (null for repository/standalone)

  // Git State
  git_metadata: {
    current_branch: string
    commit_hash: string
    is_clean: boolean
    has_untracked: boolean
    ahead_count: number
    behind_count: number
    remote_url: string
    last_modified: datetime
  }

  // User Configuration
  scoped_classes: string[]

  // Timestamps
  created_at: datetime
  updated_at: datetime
}
```

**Invariants**:
- Only ONE project with `source_type: "repository"` per unique `bare_repo_path`
- Projects with `source_type: "worktree"` MUST have non-null `parent_project`
- `bare_repo_path` is always computed from git, never user input

## Success Criteria *(mandatory)*

### Measurable Outcomes

**Architecture Correctness**:
- **SC-A-001**: 100% of projects have a valid `bare_repo_path` computed from git.
- **SC-A-002**: Zero duplicate Repository Projects for the same `bare_repo_path`.
- **SC-A-003**: 100% of Worktree Projects have valid `parent_project` references.
- **SC-A-004**: All worktrees for a bare repo are grouped under its Repository Project in the UI.

**Worktree Operations**:
- **SC-W-001**: Create worktree from panel completes in under 10 seconds (form + git operation).
- **SC-W-002**: Delete worktree from panel completes in under 5 seconds (confirm + git operation).
- **SC-W-003**: Refresh git metadata completes in under 2 seconds per project.
- **SC-W-004**: Creation/deletion via UI has same success rate as CLI (no UI-introduced failures).

**Hierarchy Display**:
- **SC-H-001**: Repository Projects display worktree count accurately.
- **SC-H-002**: Dirty indicators bubble up from worktrees to collapsed parents.
- **SC-H-003**: Orphaned worktrees appear in dedicated section with recovery option.

**User Workflow**:
- **SC-U-001**: Users can switch between related worktrees in under 3 clicks.
- **SC-U-002**: Active project is visually highlighted in hierarchy.
- **SC-U-003**: Error messages for failed operations are actionable (explain what went wrong and how to fix).

## Assumptions

- Git is installed and accessible in PATH.
- `i3pm worktree create` and `i3pm worktree remove` CLI commands exist and function correctly.
- Eww monitoring panel and i3pm daemon are running.
- Users understand git worktree concepts (branch isolation, shared object store).
- Worktrees are created as siblings to the Repository Project's directory by default.
- No backwards compatibility required - this is a fresh implementation.

## Out of Scope

- Legacy project format migration (old projects will be recreated via discovery).
- Non-git version control systems.
- GitHub/GitLab remote repository discovery (focus on local filesystem only).
- Real-time filesystem watching (manual refresh is acceptable).
- Branch operations beyond worktree create/delete (merge, rebase, push are done via git CLI).
- Worktree repair functionality (users can run `git worktree repair` manually).
- Multiple Repository Projects per bare repo (enforced constraint: exactly one).
