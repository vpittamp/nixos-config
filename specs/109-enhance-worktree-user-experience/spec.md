# Feature Specification: Enhanced Worktree User Experience

**Feature Branch**: `109-enhance-worktree-user-experience`
**Created**: 2025-12-02
**Status**: Draft
**Input**: User description: "Review our implementation of git worktrees via the eww monitoring widget, worktree tab, where we manage worktrees via the UI, with the goal of creating and deleting worktrees for the purpose of parallel development, then to quickly move from one worktree to the next, understand the progress of a worktree, and its status, etc. Secondly, we would like integration with lazygit, which allows us to quickly use lazygit for git/worktree related operations and get to the correct instance of lazygit in the right view/action when relevant. Consider whether we can use command line arguments to enhance the integration between our widget and lazygit within each worktree environment; review the most popular open source projects that help incorporate git worktrees, understand their patterns of usage, and understand how to seek to create the best user experience for managing worktrees, and then determine how we can improve our management of worktree, and create an exceptional user experience for parallel development."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Worktree Navigation (Priority: P1)

A developer working on multiple features needs to rapidly switch between worktrees without losing context. They want to see all worktrees at a glance, understand each one's status (dirty, synced, stale), and switch with minimal keystrokes.

**Why this priority**: Navigation is the most frequent operation in parallel development. Every friction point in switching compounds across dozens of daily transitions. This is the foundation that makes parallel development viable.

**Independent Test**: Can be fully tested by creating 3+ worktrees, switching between them using the panel, and verifying the switch completes in under 500ms while preserving terminal state.

**Acceptance Scenarios**:

1. **Given** a developer has 5 worktrees for a repository, **When** they open the monitoring panel (Mod+M) and press Alt+2, **Then** they see all 5 worktrees with status indicators (dirty ●, sync ↑↓, stale 💤) in a scrollable list optimized for 5-7 visible at once
2. **Given** a developer is in worktree A, **When** they click worktree B in the panel, **Then** the project context switches to B within 500ms and any scoped windows (terminal, lazygit) switch to show B's content
3. **Given** a developer is in focus mode (Mod+Shift+M), **When** they use j/k to navigate and Enter to select a worktree, **Then** the switch occurs and focus mode exits automatically
4. **Given** a worktree has uncommitted changes, **When** it appears in the panel, **Then** a red dirty indicator (●) is prominently visible alongside the worktree name

---

### User Story 2 - Lazygit Integration for Worktree Operations (Priority: P1)

A developer wants to perform git operations (commit, push, pull, resolve conflicts, manage branches) using lazygit and have the lazygit instance automatically open in the correct worktree context with the appropriate view selected.

**Why this priority**: Lazygit is the primary git interface for terminal-based workflows. Deep integration eliminates the friction of manually navigating to the right context after launching lazygit.

**Independent Test**: Can be fully tested by launching lazygit from a worktree card and verifying it opens with the correct working directory and git state visible.

**Acceptance Scenarios**:

1. **Given** a developer selects a worktree in the panel, **When** they click a "Git" action button or press a keyboard shortcut, **Then** lazygit opens in that worktree's directory with the status view displayed
2. **Given** a worktree has uncommitted changes shown in the panel, **When** the developer clicks "Commit" action, **Then** lazygit opens with the files view focused, ready for staging
3. **Given** a worktree is behind remote (↓2 indicator), **When** the developer clicks "Sync" action, **Then** lazygit opens with the branches view showing the remote tracking status
4. **Given** a worktree has merge conflicts (⚠ indicator), **When** the developer clicks "Resolve" action, **Then** lazygit opens with the merge conflict resolution interface displayed
5. **Given** lazygit is already open for worktree A, **When** the developer triggers lazygit for worktree B, **Then** a new lazygit instance opens for B in a separate terminal (parallel instances supported)

---

### User Story 3 - One-Click Worktree Creation (Priority: P2)

A developer needs to create a new worktree for a feature branch quickly, with the worktree automatically configured with the correct environment variables and ready for development.

**Why this priority**: Creation is less frequent than navigation but critical for starting new parallel work streams. A frictionless creation flow encourages the habit of using worktrees.

**Independent Test**: Can be fully tested by clicking the create button, entering a branch name, and verifying the worktree appears in the list within 3 seconds with correct metadata.

**Acceptance Scenarios**:

1. **Given** a developer is viewing a repository in the Projects tab, **When** they click "[+ New Worktree]", **Then** an inline form appears with branch name input field
2. **Given** a developer enters "110-new-feature" in the form, **When** they click "Create" or press Enter, **Then** the worktree is created within 3 seconds and appears in the list with I3PM environment variables configured
3. **Given** worktree creation succeeds, **When** the panel updates, **Then** the new worktree shows feature number (110), branch type detection, and parent project linkage
4. **Given** a branch name already exists as a worktree, **When** the developer tries to create it again, **Then** they see an error message explaining the conflict

---

### User Story 4 - Worktree Status at a Glance (Priority: P2)

A developer managing multiple parallel features needs to quickly assess which worktrees need attention (have changes to commit, are out of sync, are stale, have conflicts) without opening each one.

**Why this priority**: Status visibility prevents context switching just to check state. A developer can make informed decisions about which worktree to work on next from a single view.

**Independent Test**: Can be fully tested by creating worktrees with various states (dirty, ahead, behind, stale, conflicts) and verifying all indicators display correctly in the panel.

**Acceptance Scenarios**:

1. **Given** worktree A has 3 staged, 2 modified, 1 untracked files, **When** the developer hovers over the dirty indicator, **Then** a tooltip shows the breakdown: "3 staged, 2 modified, 1 untracked"
2. **Given** worktree B is 5 commits ahead and 2 behind, **When** it appears in the panel, **Then** it shows "↑5 ↓2" indicators with appropriate coloring
3. **Given** worktree C has not been modified in 35 days, **When** it appears in the panel, **Then** it shows a stale indicator (💤) with tooltip "Last activity: 35 days ago"
4. **Given** worktree D was merged to main, **When** it appears in the panel, **Then** it shows a merged indicator (✓) with option to delete the stale worktree
5. **Given** a developer wants to see the last commit message, **When** they hover over the worktree row, **Then** the commit message appears in a tooltip

---

### User Story 5 - Safe Worktree Deletion (Priority: P2)

A developer completing a feature needs to clean up the worktree, with the system preventing accidental deletion of worktrees with uncommitted work.

**Why this priority**: Cleanup is essential for maintaining a manageable workspace. Safety guardrails prevent data loss from hasty deletions.

**Independent Test**: Can be fully tested by attempting to delete a dirty worktree and verifying the confirmation dialog appears with warnings.

**Acceptance Scenarios**:

1. **Given** a developer clicks "Delete" on a clean worktree, **When** a confirmation appears, **Then** it requires a single confirmation click to proceed
2. **Given** a developer clicks "Delete" on a dirty worktree, **When** a confirmation appears, **Then** it shows a warning with file counts: "This worktree has 5 uncommitted changes. Proceed anyway?"
3. **Given** a developer confirms deletion, **When** the operation completes, **Then** the worktree is removed from the filesystem and the panel updates within 2 seconds
4. **Given** a worktree deletion fails (e.g., locked files), **When** the error occurs, **Then** a clear error message explains the issue and suggests resolution

---

### User Story 6 - Contextual Actions Menu (Priority: P3)

A developer wants quick access to common worktree operations (open in terminal, open in VS Code, open lazygit, copy path, show in file manager) from a single menu.

**Why this priority**: Reduces cognitive load by centralizing all worktree actions in one discoverable location. Improves discoverability for new users.

**Independent Test**: Can be fully tested by right-clicking a worktree and verifying all actions are present and functional.

**Acceptance Scenarios**:

1. **Given** a developer right-clicks (or clicks action menu) on a worktree, **When** the menu appears, **Then** it shows: Terminal, VS Code, Lazygit, File Manager, Copy Path, Delete
2. **Given** a developer selects "Terminal" from the menu, **When** the action executes, **Then** a new scratchpad terminal opens in that worktree's directory
3. **Given** a developer selects "Copy Path", **When** the action executes, **Then** the worktree path is copied to clipboard with a brief notification confirmation

---

### User Story 7 - Keyboard-Driven Worktree Management (Priority: P3)

A power user wants to manage worktrees entirely via keyboard shortcuts without using the mouse, maintaining flow state during development.

**Why this priority**: Power users who live in the terminal expect keyboard-first interfaces. This differentiates the experience from basic GUI tools.

**Independent Test**: Can be fully tested by navigating to a worktree using only keyboard and performing create/switch/delete operations.

**Acceptance Scenarios**:

1. **Given** a developer is in the Projects tab in focus mode, **When** they press 'c' on a repository row, **Then** the create worktree form opens with cursor in the branch name field
2. **Given** a developer is navigating worktrees with j/k, **When** they press 'g' on a worktree, **Then** lazygit opens for that worktree
3. **Given** a developer is on a worktree row, **When** they press 'd', **Then** the delete confirmation flow begins
4. **Given** a developer presses 'r', **When** on a worktree row, **Then** the worktree's git metadata refreshes immediately

---

### Edge Cases

- What happens when a user tries to switch to a worktree whose directory no longer exists? Display error and offer to remove the stale entry.
- How does the system handle worktree operations while a git operation is in progress? Queue the operation and show a "busy" indicator.
- What happens if lazygit crashes or exits unexpectedly during an operation? Terminal remains open with error output visible; worktree state is unchanged.
- How does the system handle very long branch names in the UI? Truncate with ellipsis and show full name in tooltip.
- What happens if the user creates a worktree with a name that conflicts with an existing directory? Show error message with the conflict path.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display all worktrees for a repository in a hierarchical list with parent repository as the group header
- **FR-002**: System MUST show real-time status indicators for each worktree: dirty state (●), ahead/behind counts (↑↓), merge conflicts (⚠), stale status (💤), merged status (✓)
- **FR-003**: System MUST allow switching between worktrees within 500ms of user selection
- **FR-004**: System MUST launch lazygit with the correct `--path` argument to target the selected worktree's directory
- **FR-005**: System MUST support launching lazygit with view-specific focus using positional arguments: `status`, `branch`, `log`, `stash`
- **FR-006**: System MUST allow creating new worktrees from the UI with branch name input
- **FR-007**: System MUST validate branch names before creating worktrees (no spaces, valid git branch characters)
- **FR-008**: System MUST inject I3PM environment variables (I3PM_IS_WORKTREE, I3PM_PARENT_PROJECT, I3PM_BRANCH_NUMBER, etc.) into applications launched within worktree context
- **FR-009**: System MUST require confirmation before deleting any worktree
- **FR-010**: System MUST show enhanced warning when attempting to delete a worktree with uncommitted changes
- **FR-011**: System MUST provide keyboard shortcuts for all primary worktree operations (switch, create, delete, git)
- **FR-012**: System MUST update worktree status display within 2 seconds of any git operation completing
- **FR-013**: System MUST support tooltips showing detailed breakdown of worktree status (file counts, last commit message, last activity date)
- **FR-014**: System MUST provide a contextual actions menu with common operations (terminal, editor, lazygit, file manager, copy path)
- **FR-015**: System MUST handle stale worktree entries gracefully (directory deleted externally) by showing error and offering cleanup

### Key Entities

- **Worktree**: A git worktree with properties: path, branch name, parent repository, git status (dirty/clean), sync status (ahead/behind), activity status (active/stale), merge status (merged/unmerged/conflicted)
- **WorktreeAction**: An operation that can be performed on a worktree: switch, delete, open-terminal, open-editor, open-lazygit, open-file-manager, copy-path, refresh
- **LazyGitContext**: Configuration for launching lazygit: working directory path, initial view (status/branch/log/stash), focus element (if applicable)
- **WorktreeStatusIndicator**: Visual representation of worktree state: dirty indicator (●), sync indicator (↑↓), conflict indicator (⚠), stale indicator (💤), merged indicator (✓)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can switch between worktrees in under 500ms from panel click to terminal showing new context
- **SC-002**: Worktree status updates appear within 2 seconds of any git state change
- **SC-003**: Creating a new worktree takes under 5 seconds from form submission to worktree appearing in list
- **SC-004**: 90% of worktree operations can be completed using keyboard shortcuts alone
- **SC-005**: Users can identify worktrees needing attention (dirty, conflicts, stale) within 2 seconds of viewing the panel
- **SC-006**: Lazygit opens in the correct worktree context 100% of the time when triggered from the panel
- **SC-007**: Zero accidental worktree deletions due to confirmation requirements for all delete operations
- **SC-008**: All worktree status indicators (dirty, sync, stale, merged, conflicts) accurately reflect the actual git state

## Clarifications

### Session 2025-12-02

- Q: When lazygit is already open for worktree A and user triggers lazygit for worktree B, should it spawn a new instance or reuse existing? → A: Always spawn new lazygit instance per worktree (parallel instances)
- Q: How should the UI handle repositories with many worktrees (10+)? → A: Scrollable list with no limit, optimize for 5-7 visible at once

## Assumptions

- Lazygit version 0.40+ is installed (supports `--path` and view positional arguments)
- Users have git 2.5+ with worktree support
- The i3pm daemon is running and responsive
- Eww monitoring panel is enabled in the user's configuration
- Users are familiar with basic git worktree concepts
- The existing monitoring panel infrastructure (Feature 085) is stable
- Worktree directories follow the sibling directory pattern (e.g., `repo__worktrees/branch-name/`)
