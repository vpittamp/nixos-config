# Feature Specification: Enhanced Git Worktree Status Indicators

**Feature Branch**: `120-improve-git-changes`
**Created**: 2025-12-16
**Status**: Draft
**Input**: User description: "Improve user experience of managing multiple git worktrees by displaying enhanced status information in eww monitoring panel's windows view and worktree cards, including git changes visualization, merge status, and actionable status indicators"

## Clarifications

### Session 2025-12-16

- Q: When a worktree has multiple simultaneous states (e.g., dirty + behind remote + stale), how should the status indicators be prioritized or combined? → A: Show all applicable states in priority order (most urgent left-to-right): conflicts > dirty > sync > stale > merged
- Q: What should be the maximum timeout for git commands and polling frequency for status updates? → A: 2 second timeout, 10 second polling interval (balanced approach)
- Q: For the git diff statistics display, what metric should be visualized and in what format? → A: Line counts as compact colored bar with numbers (e.g., ██░░ +45 -12)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Status Assessment at a Glance (Priority: P1)

As a developer working with multiple Claude Code or Codex CLI sessions across different worktrees, I need to quickly understand which worktrees have uncommitted work requiring attention so I can prioritize my review and avoid losing work.

**Why this priority**: This is the core value proposition - enabling rapid assessment of worktree health across all active sessions without switching contexts. Users currently struggle to identify which worktrees need attention.

**Independent Test**: Can be fully tested by viewing the monitoring panel with multiple worktrees in various states and verifying that status indicators clearly differentiate between clean, dirty, merged, and stale worktrees.

**Acceptance Scenarios**:

1. **Given** I have 5 worktrees open in the monitoring panel, **When** I look at the worktree cards or windows view, **Then** I can immediately identify which have uncommitted changes vs clean state without clicking or hovering.

2. **Given** a worktree has staged, modified, and untracked files, **When** I view its status indicator, **Then** I see a summary showing the count/presence of each change type (e.g., visual representation of additions/deletions or file counts).

3. **Given** a worktree's branch has been merged into main, **When** I view the monitoring panel, **Then** I see a clear merged indicator (checkmark or similar) distinguishing it from unmerged branches.

4. **Given** a worktree has changes that are ahead of or behind remote, **When** I view its status, **Then** I see sync status with counts (e.g., ↑3 ↓2) indicating push/pull needed.

---

### User Story 2 - Worktree Header Status in Windows View (Priority: P2)

As a developer viewing active windows grouped by project/worktree, I need git status information displayed in the project/worktree header so I can understand the state of each workspace without navigating to the worktree tab.

**Why this priority**: Windows view is the primary navigation interface. Showing status there eliminates extra clicks to check worktree health and supports the user's workflow of managing multiple parallel Claude Code sessions.

**Independent Test**: Can be tested by viewing the windows tab with projects that have worktrees and verifying git status indicators appear in project headers.

**Acceptance Scenarios**:

1. **Given** I am on the Windows tab viewing project groupings, **When** a project is a worktree, **Then** the project header displays git status indicators (dirty/clean, sync status, merge status).

2. **Given** a worktree project header shows dirty status, **When** I see the indicator, **Then** I can distinguish between staged changes, unstaged modifications, and untracked files through visual differentiation.

3. **Given** multiple worktrees for the same parent repository, **When** I view them in windows view, **Then** each worktree header shows its independent git status, making it easy to compare states.

---

### User Story 3 - Actionable Status Context (Priority: P3)

As a developer reviewing worktree status, I need the indicators to suggest what action is needed so I can quickly decide whether to commit, push, pull, merge, or clean up a worktree.

**Why this priority**: Status indicators are only useful if they guide action. This story transforms passive status display into actionable guidance, reducing cognitive load.

**Independent Test**: Can be tested by hovering over or expanding status indicators and verifying that contextual information suggests appropriate actions.

**Acceptance Scenarios**:

1. **Given** a worktree has uncommitted changes, **When** I view or hover over its status, **Then** I see context suggesting "commit" or "stash" as potential actions.

2. **Given** a worktree is behind remote, **When** I view its status, **Then** I see an indicator suggesting "pull needed" with the count of commits behind.

3. **Given** a worktree's branch is merged into main, **When** I view its status, **Then** I see a "merged" indicator suggesting the branch can be cleaned up or deleted.

4. **Given** a worktree has merge conflicts, **When** I view its status, **Then** I see a prominent conflict indicator suggesting "resolve conflicts" as the required action.

---

### User Story 4 - Git Diff Statistics Display (Priority: P4)

As a developer assessing the scope of changes in a worktree, I want to see a visual summary of additions and deletions (similar to GitHub's +/- bars) so I can gauge the magnitude of changes at a glance.

**Why this priority**: While counts are helpful, a visual diff representation provides intuitive understanding of change magnitude. This is an enhancement over basic counts.

**Independent Test**: Can be tested by making changes of varying sizes in worktrees and verifying the visual diff indicator accurately represents the scale of additions vs deletions.

**Acceptance Scenarios**:

1. **Given** a worktree has code changes, **When** I view its status indicator, **Then** I see a compact visual representation of additions (green) and deletions (red) proportions.

2. **Given** a worktree has only additions (new files), **When** I view the diff visual, **Then** it shows predominantly green with appropriate scale.

3. **Given** a worktree has a large refactor (many additions and deletions), **When** I view the diff visual, **Then** the scale reflects the magnitude without being overwhelming in the UI.

---

### Edge Cases

- What happens when a worktree is in detached HEAD state? Display "detached" indicator with commit hash instead of branch name.
- How does the system handle worktrees with no remote configured? Show local-only indicator, omit sync status arrows.
- What happens when git commands fail or timeout? Display "unknown" or "?" status with error indicator, do not block UI rendering.
- How are very long branch names handled? Truncate with ellipsis, show full name on hover/tooltip.
- What happens when a worktree directory no longer exists? Show "missing" indicator with cleanup suggestion.
- How does the system behave with thousands of changed files? Cap visual display, show "+999" or similar for extreme cases.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a dirty/clean indicator for each worktree in both windows view headers and worktree cards.
- **FR-002**: System MUST differentiate between staged files, unstaged modifications, and untracked files in the status display.
- **FR-003**: System MUST display sync status showing commits ahead and behind remote tracking branch.
- **FR-004**: System MUST display a "merged" indicator when a worktree's branch has been merged into main/master.
- **FR-005**: System MUST display a "stale" indicator for worktrees with no commits in the configured threshold period.
- **FR-006**: System MUST display a conflict indicator when unresolved merge conflicts exist.
- **FR-007**: System MUST display git status in project/worktree headers in the Windows view tab.
- **FR-008**: System MUST provide hover/tooltip details showing expanded status information including last commit message and timestamp.
- **FR-009**: System MUST display line-based diff statistics as a compact colored bar with counts (e.g., green/red proportional bar + "+45 -12" text) for worktrees with uncommitted changes.
- **FR-010**: System MUST update status indicators via polling at 10-second intervals.
- **FR-011**: System MUST timeout git commands after 2 seconds and display "unknown" status without blocking UI rendering.
- **FR-012**: System MUST support worktrees in detached HEAD state with appropriate indicator.
- **FR-013**: System MUST display multiple simultaneous states in priority order (left-to-right): conflicts > dirty > sync > stale > merged, showing all applicable indicators.

### Key Entities

- **Worktree**: A git worktree associated with a project, containing branch info, change counts, sync status, merge status, and staleness state.
- **Git Status**: Aggregate state including staged count, modified count, untracked count, conflict presence, ahead/behind counts, merged flag, stale flag.
- **Status Indicator**: Visual element displaying git status through color, icon, and optional count/bar visualization.
- **Project Header**: UI element in windows view showing project name and associated git status for worktree projects.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify worktrees requiring attention (uncommitted work, conflicts, sync needed) within 2 seconds of viewing the monitoring panel.
- **SC-002**: Users can distinguish between clean, dirty, merged, stale, and conflicted worktree states without clicking or hovering.
- **SC-003**: Status indicators update within 10 seconds of git state changes occurring in the worktree (aligned with polling interval).
- **SC-004**: Users report at least 80% reduction in time spent checking worktree status compared to manual git status commands.
- **SC-005**: All status information remains visible and useful when managing 10+ simultaneous worktrees.
- **SC-006**: Status indicator rendering does not cause perceptible UI lag or delay in panel responsiveness.

## Assumptions

- Git metadata extraction (Feature 108) is already implemented and provides staged_count, modified_count, untracked_count, is_merged, is_stale, has_conflicts, ahead_count, behind_count.
- The eww monitoring panel infrastructure supports updating widget content dynamically.
- Users primarily work with worktrees that have remote tracking branches configured.
- The stale threshold of 30 days (existing implementation) is acceptable for determining staleness.
- Color-based indicators (teal, red, green) from existing implementation are appropriate and accessible.
