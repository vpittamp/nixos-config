# Feature Specification: Enhanced Worktree Card Status Display

**Feature Branch**: `108-show-worktree-card-detail`
**Created**: 2025-12-01
**Status**: Draft
**Input**: User description: "Review popular worktree projects online that help manage worktrees, then explore what other information we can show on the worktree cards that give some sense of what the status of the worktree is? such as if there are uncommitted changes, merged into main? etc. it should be simple but visually good to understand what is going on providing a great user experience?"

## Research Summary

Based on research into popular git worktree management tools:

**gwq** (Git Worktree Manager with Fuzzy Finder):
- Status table with columns: BRANCH, STATUS, CHANGES, ACTIVITY
- Status values: "up to date", "changed"
- Change indicators: "3 added, 2 modified, 8 untracked"
- Activity timestamps: "just now", relative times
- Watch mode with auto-refresh

**Lazygit**:
- Color-coded commits: Green (merged into main), Yellow (not merged), Red (unpushed)
- Arrows for ahead (↑) / behind (↓) remote tracking
- Status panel showing branch, tracking info, fast-forward availability
- Modified/untracked file counts

**GitKraken / VS Code**:
- Visual branch graphs
- Dirty/clean state indicators
- Ahead/behind badges
- Merge status visualization

**Common UX Patterns**:
- Use color to convey state (green=clean, red=dirty, yellow=warning)
- Keep indicators compact but information-dense
- Show counts rather than just presence (e.g., "↑3" not just "↑")
- Activity/staleness indicators help prioritize attention

## User Scenarios & Testing *(mandatory)*

### User Story 1 - At-a-Glance Worktree Health Status (Priority: P1)

A developer views the Projects tab and instantly understands each worktree's health status through clear visual indicators - whether it has uncommitted changes, whether it's behind the remote, and whether the branch has been merged. The indicators are compact, scannable, and don't require expanding or hovering to see basic status.

**Why this priority**: Quick visual scanning is the primary value-add. Users should understand worktree health in under 1 second per card without any interaction.

**Independent Test**: Can be fully tested by opening Projects tab with worktrees in various git states (dirty, ahead, behind, merged) and verifying each state is visually distinguishable at a glance.

**Acceptance Scenarios**:

1. **Given** worktree "099-feature" has uncommitted changes (modified files), **When** user views the Projects tab, **Then** a red dot indicator (●) appears on the worktree card with a tooltip showing file count (e.g., "3 modified files").

2. **Given** worktree "098-feature" is 5 commits ahead and 2 commits behind origin, **When** user views the worktree card, **Then** sync indicators display "↑5 ↓2" with appropriate coloring (green for ahead, orange for behind).

3. **Given** worktree "097-feature" branch has been merged into main, **When** user views the worktree card, **Then** a merge indicator appears (e.g., "✓ merged" badge in green/teal).

4. **Given** worktree "096-feature" is clean, up-to-date, and not merged, **When** user views the card, **Then** no status indicators are displayed (clean state = absence of warnings).

---

### User Story 2 - Detailed Status on Hover/Expand (Priority: P2)

A developer wants more details about a worktree's status beyond the at-a-glance indicators. Hovering or expanding reveals specific information like file counts by type (modified, staged, untracked), last commit time, and commit message preview.

**Why this priority**: Detailed information supports decision-making but shouldn't clutter the default compact view.

**Independent Test**: Hover over a dirty worktree card, verify detailed breakdown of changes appears in a tooltip or expandable section.

**Acceptance Scenarios**:

1. **Given** worktree has 2 staged, 3 modified, 1 untracked files, **When** user hovers over the dirty indicator, **Then** tooltip shows breakdown: "2 staged, 3 modified, 1 untracked".

2. **Given** worktree is ahead/behind remote, **When** user hovers over sync indicator, **Then** tooltip shows: "5 commits to push, 2 commits to pull".

3. **Given** worktree's last commit was "2 hours ago", **When** user views expanded card details, **Then** relative time and commit message preview appear (e.g., "2h ago: Fix authentication bug").

---

### User Story 3 - Stale Worktree Detection (Priority: P2)

A developer wants to identify worktrees that haven't been touched in a long time and may be candidates for cleanup. Stale worktrees get a subtle visual indicator showing inactivity.

**Why this priority**: Helps with repository hygiene and decluttering, but less critical than active status indicators.

**Independent Test**: Create a worktree, don't touch it for the threshold period, verify staleness indicator appears.

**Acceptance Scenarios**:

1. **Given** worktree "old-feature" has no commits in 30+ days, **When** user views the Projects tab, **Then** a subtle staleness indicator appears (e.g., faded appearance or "💤" icon).

2. **Given** worktree "active-feature" has commits within the last 7 days, **When** user views the card, **Then** no staleness indicator appears.

3. **Given** user hovers over a stale worktree, **When** tooltip appears, **Then** it shows "Last activity: 45 days ago" with optional cleanup suggestion.

---

### User Story 4 - Branch Merge Status (Priority: P2)

A developer wants to know if a feature branch has been merged into main, indicating the worktree can potentially be deleted. The merge status is clearly visible without needing to run git commands.

**Why this priority**: Merge status helps identify completed work, but determining merge status requires additional git operations.

**Independent Test**: Merge a worktree branch into main (via PR or locally), verify merge indicator appears on the worktree card.

**Acceptance Scenarios**:

1. **Given** worktree branch "098-feature" has been merged into main, **When** user views the card, **Then** a "✓ merged" badge appears in green/teal color.

2. **Given** worktree branch "099-wip" has NOT been merged, **When** user views the card, **Then** no merge badge appears (default state).

3. **Given** worktree branch was merged but main has since diverged, **When** user views the card, **Then** badge shows "✓ merged" (original merge status preserved, divergence handled by ahead/behind indicators).

---

### Edge Cases

- What happens when git remote is unreachable (offline mode)?
  - Ahead/behind indicators show "?" or cached values with "offline" tooltip. Dirty/clean status still works from local state.

- What happens when worktree is in detached HEAD state?
  - Card shows "detached @ abc123" instead of branch name, with appropriate warning coloring.

- What happens when worktree has merge conflicts?
  - Conflict indicator (⚠) appears prominently with "merge conflicts" tooltip showing file count.

- What happens when repository has no remote configured?
  - Ahead/behind indicators are hidden (not applicable). Only dirty/clean and merge status shown.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display dirty/clean status indicator on every worktree card visible at-a-glance without hover or expand
- **FR-002**: System MUST display ahead/behind remote counts using ↑N/↓N notation with count numbers
- **FR-003**: System MUST display merge-into-main status for feature branches using a distinct badge
- **FR-004**: System MUST show detailed status breakdown (file counts by type) via tooltip on hover
- **FR-005**: System MUST detect and indicate stale worktrees (configurable threshold, default: 30 days since last commit)
- **FR-006**: System MUST handle offline/unreachable remote gracefully by showing cached or "unknown" state
- **FR-007**: System MUST display last commit timestamp in human-readable relative format (e.g., "2h ago", "3 days ago")
- **FR-008**: System MUST update status indicators when panel is opened or explicitly refreshed (not continuously polling)
- **FR-009**: System MUST use consistent color coding: green (clean/merged), red (dirty), orange (behind), teal (ahead/merged badge)
- **FR-010**: System MUST show conflict indicator when worktree has unresolved merge conflicts

### Key Entities

- **Worktree**: Git worktree with branch, path, and git status metadata
- **Git Status**: Composite state including dirty/clean, staged/modified/untracked counts, ahead/behind counts, merge status, last activity timestamp
- **Status Indicator**: Visual UI element representing a specific status aspect (dirty dot, sync arrows, merge badge, stale icon)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can determine worktree health status (dirty/clean, sync status) within 1 second of viewing the card without any interaction
- **SC-002**: All four status categories (dirty, ahead, behind, merged) are visually distinct and correctly displayed on worktrees with those states
- **SC-003**: Tooltip details appear within 300ms of hovering over any status indicator
- **SC-004**: Status indicators are correctly colored according to the defined color scheme (green=clean/merged, red=dirty, orange=behind, teal=ahead)
- **SC-005**: Stale worktrees (30+ days inactive) display staleness indicator correctly
- **SC-006**: Status display remains readable and compact - all indicators fit within a single horizontal row without truncation

## Assumptions

1. Git metadata (ahead/behind counts) is already being fetched via existing i3pm/monitoring_data.py infrastructure
2. Merge status can be determined via `git branch --merged main` or equivalent
3. Last commit timestamp is available from git log
4. The existing Eww worktree card widget will be enhanced rather than replaced
5. Catppuccin Mocha color palette will be used for status indicator colors (consistent with existing theme)
6. Refresh is triggered manually or on panel open, not via continuous polling (performance consideration)
