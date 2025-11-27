# Feature Specification: Git-Based Project Discovery and Management

**Feature Branch**: `097-convert-manual-projects`
**Created**: 2025-11-26
**Status**: Draft
**Input**: User description: "Convert manual project creation to automatic git repository discovery using local filesystem scanning and GitHub CLI integration. Transform projects from manually-defined JSON files to repository metadata-driven entries."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discover Local Git Repositories (Priority: P1)

A developer wants to automatically discover existing git repositories on their filesystem and register them as i3pm projects, eliminating the need to manually create project definitions for repositories that already exist.

**Why this priority**: This is the core value proposition - reducing manual project creation by leveraging existing git repository metadata. Most developers have multiple repositories on disk that should be discoverable without manual registration.

**Independent Test**: Can be fully tested by running a discovery command against a directory containing git repositories and verifying that projects are created with correct metadata derived from git.

**Acceptance Scenarios**:

1. **Given** a directory `/home/user/projects/` containing 5 git repositories, **When** the user runs `i3pm project discover --path ~/projects`, **Then** 5 new project entries are created with names derived from repository directory names.

2. **Given** a git repository at `/home/user/projects/my-app` with remote `origin` pointing to `github.com/user/my-app`, **When** discovery runs, **Then** the project display name is derived from the repository name and the icon is inferred from the primary language or topic.

3. **Given** an existing project `my-app` already registered, **When** discovery finds a repository named `my-app`, **Then** the existing project is updated with fresh git metadata rather than creating a duplicate.

4. **Given** a directory that is not a git repository, **When** discovery scans that directory, **Then** it is silently skipped without creating a project.

---

### User Story 2 - Automatic Worktree Detection (Priority: P1)

A developer creates git worktrees using standard git commands (`git worktree add`) outside of i3pm, and expects those worktrees to be automatically discovered and registered as worktree projects linked to their parent repository.

**Why this priority**: Equal priority with local discovery because worktrees are the primary workflow for feature development. Manual worktree registration creates friction in the development workflow.

**Independent Test**: Can be tested by creating a git worktree using native git commands, running discovery, and verifying a worktree project is created with correct parent linkage.

**Acceptance Scenarios**:

1. **Given** a main repository at `/etc/nixos` with a worktree at `/home/user/nixos-feature-x`, **When** discovery runs, **Then** a worktree project is created with `worktree.repository_path` pointing to `/etc/nixos`.

2. **Given** a worktree project already exists for branch `097-convert-manual-projects`, **When** discovery runs and finds the same worktree, **Then** the existing project is updated with current git status (commit hash, clean status, ahead/behind counts).

3. **Given** a worktree directory exists but the worktree was removed via `git worktree remove`, **When** discovery runs, **Then** the orphaned project is flagged for user review (not auto-deleted).

---

### User Story 3 - Discover GitHub Repositories (Priority: P2)

A developer wants to see their GitHub repositories and optionally clone them as local projects, enabling seamless transition from remote repository browsing to local development.

**Why this priority**: Extends discovery beyond local filesystem but depends on local discovery working first. Provides value for developers who want to start work on repositories they don't have locally yet.

**Independent Test**: Can be tested by running GitHub discovery with authenticated gh CLI, verifying remote repositories are listed, and optionally cloning one to verify project creation.

**Acceptance Scenarios**:

1. **Given** a GitHub-authenticated user with 50 repositories, **When** `i3pm project discover --github` runs, **Then** a list of remote repositories is displayed with names, descriptions, primary language, and last update date.

2. **Given** a remote repository `user/my-app` not cloned locally, **When** the user selects it for registration, **Then** a project entry is created with a "remote" status indicating it needs to be cloned before use.

3. **Given** a local repository with remote matching a GitHub repository, **When** both local and GitHub discovery run, **Then** the repositories are recognized as the same and not duplicated.

---

### User Story 4 - Transform Monitoring Widget Projects Tab (Priority: P2)

A developer views the Projects tab in the Eww monitoring panel and sees projects organized by their source (local repositories, worktrees, remote-only) with git metadata prominently displayed.

**Why this priority**: UI transformation depends on the new data model from User Stories 1-3 being in place. Important for the visual feedback loop but not blocking core functionality.

**Independent Test**: Can be tested by opening the monitoring panel after discovery completes and verifying projects display with git branch, status indicators, and source classification.

**Acceptance Scenarios**:

1. **Given** discovered projects exist, **When** the user opens the Projects tab (Alt+2 in monitoring panel), **Then** projects are grouped by type: "Repositories", "Worktrees", and "Remote Only".

2. **Given** a repository project with uncommitted changes, **When** viewing the Projects tab, **Then** a visual indicator (modified badge) shows the repository is dirty.

3. **Given** a worktree project that is 3 commits ahead of origin, **When** viewing the Projects tab, **Then** the ahead/behind count is displayed (e.g., "3").

---

### User Story 5 - Background Discovery on Daemon Startup (Priority: P3)

When the i3pm daemon starts, it automatically scans configured directories for new or changed repositories and updates the project registry without user intervention.

**Why this priority**: Quality-of-life improvement that eliminates manual discovery triggers. Lower priority because manual discovery fulfills the core need.

**Independent Test**: Can be tested by adding a new git repository while the daemon is stopped, starting the daemon, and verifying the new repository appears as a project.

**Acceptance Scenarios**:

1. **Given** a configured scan path `~/projects`, **When** the daemon starts, **Then** any new repositories in that path are automatically registered as projects.

2. **Given** background discovery is enabled, **When** a repository is deleted from disk, **Then** the corresponding project is marked as "missing" rather than auto-deleted.

3. **Given** background discovery takes longer than 5 seconds, **When** the daemon starts, **Then** discovery runs asynchronously without blocking daemon readiness.

---

### Edge Cases

- What happens when a repository has no remote configured? Project is created with local-only status and directory name as display name.
- How does the system handle symbolic links to repositories? Symbolic links are resolved to their real path; duplicates detected by resolved path comparison.
- What happens when two repositories have the same name in different directories? Projects are differentiated by full path; display names may be the same but internal names are unique (e.g., `my-app`, `my-app-2`).
- How are submodules handled? Submodules are not registered as separate projects; only top-level repositories are discovered.
- What if `gh` CLI is not authenticated? GitHub discovery gracefully degrades with a warning; local discovery continues to function.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST scan specified directories recursively to identify git repositories (directories containing `.git`).
- **FR-002**: System MUST extract repository metadata including: name, remote URLs, current branch, commit hash, clean/dirty status, and ahead/behind counts.
- **FR-003**: System MUST detect git worktrees and associate them with their parent repository.
- **FR-004**: System MUST create project entries with metadata derived from git, not requiring manual user input for basic fields.
- **FR-005**: System MUST detect conflicts (same name) and handle them by generating unique identifiers without user intervention.
- **FR-006**: System MUST update existing project entries when re-discovering known repositories rather than creating duplicates.
- **FR-007**: System MUST query GitHub API (via `gh` CLI) to list user repositories when `--github` flag is provided.
- **FR-008**: System MUST allow users to configure default scan paths via project configuration.
- **FR-009**: System MUST mark projects as "missing" when their directories no longer exist, requiring explicit user action to delete.
- **FR-010**: System MUST notify the daemon to refresh its in-memory state after discovery completes.
- **FR-011**: System MUST display discovered repositories in the monitoring panel Projects tab with source type classification.
- **FR-012**: System MUST show git status indicators (dirty, ahead/behind, current branch) in the Projects tab UI.

### Key Entities

- **Repository**: A git repository on the local filesystem. Key attributes: path, name, remote URLs, default branch.
- **Project**: An i3pm project entry derived from a repository. Key attributes: name, display_name, directory, icon, source_type (local/worktree/remote), git_metadata.
- **Worktree**: A git worktree linked to a parent repository. Key attributes: branch, worktree_path, repository_path, commit_hash.
- **GitMetadata**: Git-specific data attached to a project. Key attributes: current_branch, commit_hash, is_clean, ahead_count, behind_count, remote_url.
- **ScanConfiguration**: User-defined paths and settings for discovery. Key attributes: scan_paths, exclude_patterns, auto_discover_on_startup.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can discover and register 10 repositories in under 30 seconds (local filesystem).
- **SC-002**: Users no longer need to manually specify project name, directory, or icon for 90% of discovered repositories.
- **SC-003**: Worktrees created via native git commands appear as projects within 60 seconds of daemon startup.
- **SC-004**: GitHub repository listing completes within 5 seconds for accounts with up to 100 repositories.
- **SC-005**: Zero duplicate projects created when running discovery multiple times on the same directories.
- **SC-006**: Projects tab displays git status (branch, dirty indicator) for 100% of repository-backed projects.
- **SC-007**: Missing repository projects are flagged rather than silently deleted, achieving zero data loss from accidental directory removal.

## Assumptions

- Users have `git` installed and accessible in PATH.
- For GitHub discovery, users have `gh` CLI installed and authenticated.
- Typical scan directories contain 10-50 repositories (not thousands).
- Repository names derived from directory names are acceptable defaults (users can rename later).
- Worktrees follow standard git worktree structure (linked via `.git` file pointing to main repository).
- The Eww monitoring panel and i3pm daemon are already running when discovery is invoked.

## Out of Scope

- Automatic cloning of remote repositories (listing only; clone is a separate action).
- Support for non-git version control systems (Mercurial, SVN, etc.).
- Real-time filesystem watching for new repository creation (only on-demand and startup discovery).
- GitLab, Bitbucket, or other remote hosting providers (GitHub only for initial implementation).
- Automatic project deletion when repositories are removed (flagging only).
