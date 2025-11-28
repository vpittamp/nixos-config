# Feature Specification: Worktree-Aware Project Environment Integration

**Feature Branch**: `098-integrate-new-project`
**Created**: 2025-11-28
**Status**: Draft
**Input**: User description: "integrate our new worktree/project architecture/format into our sway project management workflow that associates the current 'environment' with the associated directory of the current project/worktree, injects project specific environment variables, etc. Think hard about how to seamlessly integrate our new format that we created in feature 097... don't worry about backwards compatibility. Create the best implementation and replace our current as needed"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Worktree Environment Context (Priority: P1)

When a developer switches to a worktree project, the system automatically provides complete environment context including parent project, branch metadata, and directory associations. This enables launched applications to understand their worktree context without manual configuration.

**Why this priority**: This is the core value proposition - seamless environment context for worktree-based development workflows. Without this, developers must manually track which branch/worktree they're working in across multiple terminal windows and editors.

**Independent Test**: Can be fully tested by switching to a worktree project and launching a terminal - the terminal should have access to all worktree environment variables (parent project, branch number, branch type, full branch name).

**Acceptance Scenarios**:

1. **Given** a discovered worktree project exists for branch "098-feature-auth", **When** user switches to this project and launches a terminal, **Then** the terminal environment contains `I3PM_IS_WORKTREE=true`, `I3PM_PARENT_PROJECT=<parent-name>`, `I3PM_BRANCH_NUMBER=098`, `I3PM_BRANCH_TYPE=feature`, and `I3PM_FULL_BRANCH_NAME=098-feature-auth`

2. **Given** user is in a worktree project, **When** they launch any scoped application (VS Code, Lazygit, Yazi), **Then** that application receives the same worktree environment variables

3. **Given** a worktree project with git metadata showing current branch "098-feature-auth", **When** the project is activated, **Then** the branch name is parsed to extract number ("098") and type ("feature") automatically

---

### User Story 2 - Project Directory Association (Priority: P1)

When a developer switches projects, all launched applications automatically use the correct working directory for that project without requiring manual navigation.

**Why this priority**: Directory association is fundamental to project-based workflows. Developers expect terminals to open in the project directory, not their home directory.

**Independent Test**: Can be tested by switching to a project and launching a terminal - the terminal CWD should be the project's directory path.

**Acceptance Scenarios**:

1. **Given** a project with directory `/home/user/projects/my-app`, **When** user switches to this project and launches a terminal, **Then** the terminal opens with CWD set to `/home/user/projects/my-app`

2. **Given** a worktree project at `/home/user/nixos-098-feature`, **When** user launches VS Code via the app launcher, **Then** VS Code opens with that directory as its workspace root

3. **Given** user switches from project A (directory `/path/a`) to project B (directory `/path/b`), **When** they launch a new terminal, **Then** the terminal uses project B's directory, not project A's

---

### User Story 3 - Branch Metadata Extraction and Storage (Priority: P2)

The system automatically extracts and persists branch metadata (number, type, full name) from git branch names when projects are discovered, enabling rich environment context without runtime parsing.

**Why this priority**: Pre-computed metadata enables fast environment injection and consistent parsing across the system. This supports the P1 stories by providing the underlying data.

**Independent Test**: Can be tested by running project discovery on a repository with worktrees - the resulting project JSON files should contain parsed branch metadata fields.

**Acceptance Scenarios**:

1. **Given** a worktree with branch name "079-preview-pane-switching", **When** project discovery runs, **Then** the project JSON contains `branch_number: "079"`, `branch_type: "preview"`, and `full_branch_name: "079-preview-pane-switching"`

2. **Given** a worktree with branch name "fix-123-broken-auth", **When** project discovery runs, **Then** the project JSON contains `branch_number: "123"`, `branch_type: "fix"`, and `full_branch_name: "fix-123-broken-auth"`

3. **Given** a worktree with a non-standard branch name "main", **When** project discovery runs, **Then** the project JSON contains `branch_number: null`, `branch_type: null`, and `full_branch_name: "main"`

---

### User Story 4 - Parent Project Linking (Priority: P2)

Worktree projects automatically maintain a reference to their parent repository project, enabling hierarchical organization and related worktree discovery.

**Why this priority**: Parent linking enables advanced features like showing all worktrees for a repository and understanding project relationships.

**Independent Test**: Can be tested by creating a worktree from a parent repository - the worktree project should reference the parent project by name.

**Acceptance Scenarios**:

1. **Given** a parent repository project "nixos" at `/etc/nixos`, **When** a worktree is created at `/home/user/nixos-098-feature`, **Then** the worktree project's `parent_project` field references "nixos"

2. **Given** a worktree project with `parent_project: "nixos"`, **When** user queries the project, **Then** the system can resolve the parent project and access its metadata

3. **Given** a parent project "my-app" with three worktrees, **When** user lists worktrees for that parent, **Then** all three worktree projects are returned with their branch metadata

---

### User Story 5 - Git Metadata Environment Variables (Priority: P3)

Launched applications receive git-related environment variables (current branch, commit hash, clean/dirty status) enabling context-aware tooling.

**Why this priority**: Git metadata provides valuable context but is less critical than worktree identity and directory association. Applications can query git directly as a fallback.

**Independent Test**: Can be tested by launching a terminal in a project with uncommitted changes - environment should include git metadata variables.

**Acceptance Scenarios**:

1. **Given** a project with uncommitted changes, **When** user launches a terminal, **Then** environment contains `I3PM_GIT_IS_CLEAN=false`

2. **Given** a project on branch "main" at commit "abc1234", **When** user launches an application, **Then** environment contains `I3PM_GIT_BRANCH=main` and `I3PM_GIT_COMMIT=abc1234`

3. **Given** a project that is 3 commits ahead of upstream, **When** user launches a terminal, **Then** environment contains `I3PM_GIT_AHEAD=3`

---

### Edge Cases

- What happens when a worktree's parent repository project doesn't exist (e.g., parent not discovered)?
  - System creates worktree project with `parent_project: null` and logs a warning. Environment variables omit parent-related fields.

- What happens when branch name doesn't follow the expected pattern (e.g., "main", "develop")?
  - System stores `branch_number: null`, `branch_type: null`, `full_branch_name: "<actual-branch-name>"`. Only `I3PM_FULL_BRANCH_NAME` is set in environment.

- What happens when project directory no longer exists (status: "missing")?
  - System prevents switching to missing projects with a clear error message. User must either restore the directory or delete the project.

- What happens when git metadata extraction fails (e.g., git not installed, corrupted repo)?
  - System creates project with `git_metadata: null`. Environment variables omit git-related fields. Basic project switching still works.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST inject worktree-specific environment variables (`I3PM_IS_WORKTREE`, `I3PM_PARENT_PROJECT`, `I3PM_BRANCH_NUMBER`, `I3PM_BRANCH_TYPE`, `I3PM_FULL_BRANCH_NAME`) when launching applications in worktree project context

- **FR-002**: System MUST set the working directory for launched applications to the active project's directory path

- **FR-003**: System MUST parse branch names to extract branch number and type using the pattern `<number>-<type>-<description>` or `<type>-<number>-<description>` during project discovery

- **FR-004**: System MUST store parsed branch metadata (number, type, full name) in the project JSON file during discovery, not at runtime

- **FR-005**: System MUST link worktree projects to their parent repository project by resolving the parent repo path to a project name

- **FR-006**: System MUST inject git metadata environment variables (`I3PM_GIT_BRANCH`, `I3PM_GIT_COMMIT`, `I3PM_GIT_IS_CLEAN`, `I3PM_GIT_AHEAD`, `I3PM_GIT_BEHIND`) when available

- **FR-007**: System MUST gracefully handle missing metadata (null parent, unparseable branch names, missing git data) by omitting those environment variables rather than failing

- **FR-008**: System MUST prevent switching to projects with status "missing" and provide actionable error messages

- **FR-009**: System MUST update branch metadata when `i3pm project refresh` is called to capture branch changes

### Key Entities

- **Project**: Extended to include `parent_project` (optional reference to parent project name), `branch_metadata` (parsed branch info), and integration with existing `git_metadata` and `source_type` fields from Feature 097

- **BranchMetadata**: Parsed branch information including `number` (string like "098"), `type` (string like "feature", "fix", "hotfix"), and `full_name` (complete branch name)

- **WorktreeEnvironment**: Collection of environment variables to inject for worktree projects, convertible to key-value pairs for shell export

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Applications launched in worktree projects have access to worktree identity within 50ms of launch (environment variable injection latency)

- **SC-002**: 100% of worktree projects discovered have complete branch metadata extracted and stored (when branch follows standard patterns)

- **SC-003**: Developers can identify their current worktree context from any launched terminal without running additional commands (environment variables immediately available)

- **SC-004**: Project directory is correctly set as working directory for 100% of application launches in project context

- **SC-005**: System handles 50+ worktree projects across multiple parent repositories without degradation in switch time (<200ms maintained from Feature 091)

- **SC-006**: Zero runtime branch parsing required - all metadata pre-computed during discovery phase
