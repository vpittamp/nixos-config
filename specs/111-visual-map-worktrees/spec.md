# Feature Specification: Visual Worktree Relationship Map

**Feature Branch**: `111-visual-map-worktrees`
**Created**: 2025-12-02
**Status**: Draft
**Input**: User description: "explore how we can enhance our worktree management, centralized in the worktree tab of the monitoring widget, by adding a visual representation of the relationship of the worktrees and main repo relative to how they depend on each other, which worktree is ahead of the other, etc. think about the user experience of trying to understand which worktree is responsible for what in a visual way"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visual Worktree Dependency Graph (Priority: P1)

A developer managing multiple parallel features needs to understand how their worktrees relate to each other and to the main branch. They want a visual representation that shows branch lineage, merge relationships, and which worktrees contain changes not yet in other branches, helping them decide which worktree to work on next or which ones need rebasing.

**Why this priority**: Understanding branch relationships is the core value proposition. Without visual context, developers must mentally track or manually run git commands to understand how their parallel work streams interconnect.

**Independent Test**: Can be fully tested by creating 3+ worktrees with varying branch relationships (one ahead of main, one behind, one diverged) and verifying the visual map correctly represents these relationships.

**Acceptance Scenarios**:

1. **Given** a repository with main branch and 3 feature worktrees, **When** the developer opens the visual map, **Then** they see main as a central node with feature branches visually connected showing parent-child relationships
2. **Given** worktree A is 5 commits ahead of main, **When** the map is displayed, **Then** the connection between A and main shows "↑5" indicating commits not yet merged
3. **Given** worktree B branched from worktree A (not directly from main), **When** the map is displayed, **Then** the visual shows B connected to A, not directly to main
4. **Given** worktree C has diverged from main (ahead AND behind), **When** the map is displayed, **Then** the connection shows bidirectional indicators (↑3 ↓2) highlighting the need for sync

---

### User Story 2 - Feature Purpose Attribution (Priority: P1)

A developer wants to quickly understand what each worktree is responsible for without opening each one. The visual map should show meaningful labels that describe the feature or purpose of each branch, derived from branch naming conventions or PR/issue associations.

**Why this priority**: Purpose attribution transforms a technical view (branch names) into a meaningful workflow view (what am I working on). This reduces cognitive load and helps prioritize work.

**Independent Test**: Can be fully tested by viewing worktrees with numbered branches (e.g., "108-show-worktree-card") and verifying human-readable descriptions appear.

**Acceptance Scenarios**:

1. **Given** worktree branch is "109-enhance-worktree-ux", **When** displayed in the map, **Then** it shows both the feature number (109) and a readable title derived from the branch name ("Enhance Worktree UX")
2. **Given** worktree has a linked GitHub issue/PR, **When** displayed in the map, **Then** it can optionally show the issue/PR title instead of or alongside the branch-derived name
3. **Given** the main branch, **When** displayed in the map, **Then** it is visually distinguished (different color/shape) as the primary integration target
4. **Given** a worktree named "hotfix-auth-bug", **When** displayed, **Then** the branch type ("hotfix") is indicated through color or badge

---

### User Story 3 - Interactive Branch Navigation (Priority: P2)

A developer viewing the visual map wants to interact with it - clicking a worktree node should switch to that worktree, and hovering should reveal detailed status information. The map should not be static documentation but an active control surface.

**Why this priority**: Interactive maps provide faster navigation than traditional list views for understanding and acting on branch relationships. Without interactivity, the visual adds viewing overhead without workflow benefit.

**Independent Test**: Can be fully tested by clicking a worktree node in the visual map and verifying the project context switches to that worktree.

**Acceptance Scenarios**:

1. **Given** a developer clicks on a worktree node in the visual map, **When** the click is registered, **Then** the i3pm project switches to that worktree within 500ms
2. **Given** a developer hovers over a worktree node, **When** the tooltip appears, **Then** it shows: branch name, last commit message, dirty/clean status, ahead/behind counts, and last activity timestamp
3. **Given** a developer right-clicks on a worktree node, **When** the context menu appears, **Then** it offers actions: Open Terminal, Open VS Code, Open Lazygit, Copy Path, Delete Worktree
4. **Given** a developer hovers over a connection line between nodes, **When** tooltip appears, **Then** it shows the commit count and direction of the relationship

---

### User Story 4 - Merge Flow Visualization (Priority: P2)

A developer planning to merge work wants to see which worktrees have changes ready to merge into main, which have already been merged, and which might conflict. The visualization should help plan the merge sequence to minimize conflicts.

**Why this priority**: Merge planning is a critical decision point in parallel development. Visual merge flow reduces the risk of conflicts and helps optimize the merge order.

**Independent Test**: Can be fully tested by creating worktrees with overlapping file changes and verifying the potential conflict indicators appear.

**Acceptance Scenarios**:

1. **Given** worktree A has been merged into main, **When** the map is displayed, **Then** A shows a "merged" indicator (checkmark) and its connection to main is styled differently (dashed or grayed)
2. **Given** worktrees B and C both modify the same files, **When** the map is displayed, **Then** a potential conflict indicator appears between B and C
3. **Given** a recommended merge order based on branch age and dependency, **When** viewing the map, **Then** numeric badges (1, 2, 3) suggest the optimal merge sequence
4. **Given** worktree D is ready to merge (clean, up-to-date with main), **When** displayed, **Then** a "ready to merge" indicator highlights it

---

### User Story 5 - Branch Age and Activity Heatmap (Priority: P3)

A developer wants to identify stale branches that should be cleaned up versus active branches that need attention. The visual map uses color intensity or size to represent activity level and age.

**Why this priority**: Repository hygiene is important but less urgent than understanding relationships. Visual cues for staleness help maintain a clean workspace over time.

**Independent Test**: Can be fully tested by creating worktrees of varying ages and verifying visual differentiation based on activity.

**Acceptance Scenarios**:

1. **Given** worktree has no commits in 30+ days, **When** displayed in the map, **Then** its node appears faded or with a staleness badge
2. **Given** worktree had a commit today, **When** displayed in the map, **Then** its node appears with full visual intensity
3. **Given** multiple worktrees with varying ages, **When** viewing the map, **Then** activity gradient makes it immediately clear which are active vs stale

---

### User Story 6 - Compact vs Expanded Map Views (Priority: P3)

A developer with many worktrees (10+) needs the map to remain usable. The system should support both compact view (fits in panel) and expanded view (full detail) modes.

**Why this priority**: Scalability ensures the feature remains useful as repository complexity grows. Without scale handling, the map becomes cluttered and loses value.

**Independent Test**: Can be fully tested by creating 15 worktrees and verifying both compact and expanded views remain readable and navigable.

**Acceptance Scenarios**:

1. **Given** 5 or fewer worktrees, **When** the map is displayed, **Then** all nodes and labels are fully visible without scrolling or collapsing
2. **Given** 10+ worktrees, **When** the compact view is active, **Then** nodes are smaller, labels are abbreviated, and the map fits within the panel
3. **Given** a developer clicks "Expand" or uses a keyboard shortcut, **When** the expanded view opens, **Then** a larger visualization appears with full details and no truncation
4. **Given** expanded view is open, **When** the developer presses Escape, **Then** it returns to the compact panel view

---

### Edge Cases

- What happens when a worktree's branch has been deleted from remote but local worktree exists? Display "orphaned" indicator with warning color and tooltip explaining the remote branch is gone.
- How does the system handle worktrees with very long branch names in the visual map? Truncate to first 30 characters with ellipsis in compact view; show full name in expanded view and tooltips.
- What happens when the branch hierarchy is very deep (worktree branched from worktree branched from worktree)? Support up to 5 levels of depth; beyond that, collapse intermediate nodes with "+" indicator to expand.
- How does the map handle repositories with multiple remotes (fork workflow)? Display a selector to choose which remote's main branch to compare against; default to "origin".
- What happens when git operations are in progress? Show "syncing" spinner on affected nodes; queue user interactions until git operations complete.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST render a visual graph showing worktrees as nodes and their git relationships as edges
- **FR-002**: System MUST distinguish the main/master branch visually (different node shape or color) as the primary integration target
- **FR-003**: System MUST show commit count differences on relationship edges using ↑N (ahead) and ↓N (behind) notation
- **FR-004**: System MUST detect and display branch parent relationships beyond just comparing to main (worktree branched from another worktree)
- **FR-005**: System MUST derive human-readable feature descriptions from branch names using existing parsing conventions (e.g., "109-feature-name" → "Feature Name")
- **FR-006**: System MUST support clicking nodes to switch to that worktree's project context
- **FR-007**: System MUST support hovering nodes to display detailed status tooltips
- **FR-008**: System MUST visually indicate merged branches differently from unmerged branches
- **FR-009**: System MUST indicate potential merge conflicts when multiple worktrees modify overlapping files
- **FR-010**: System MUST support compact view (fits in monitoring panel) and expanded view (larger, full-detail) modes
- **FR-011**: System MUST indicate worktree activity level through visual cues (staleness, recency)
- **FR-012**: System MUST provide context menu with actions (terminal, editor, lazygit, delete) on right-click
- **FR-013**: System MUST handle orphaned worktrees (deleted remote branch) with appropriate warning indicators
- **FR-014**: System MUST support keyboard navigation within the map for accessibility

### Key Entities

- **WorktreeNode**: Visual representation of a worktree with properties: branch name, feature description, status indicators, position in graph, activity level
- **RelationshipEdge**: Connection between two worktree nodes representing git relationship: direction (parent/child), commit delta (ahead/behind counts), merge status
- **GraphLayout**: The visual arrangement algorithm determining node positions: hierarchical (main at center), radial (main at center with branches radiating), or linear (timeline-based)
- **ConflictIndicator**: Visual marker showing potential merge conflicts between two worktrees based on file overlap detection

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can identify the relationship between any two worktrees (which is ahead/behind the other) within 3 seconds of viewing the map
- **SC-002**: Developers can determine which worktrees need rebasing or are ready to merge within 5 seconds of viewing the map
- **SC-003**: Clicking a worktree node in the map switches to that project within 500ms (matching existing switch performance)
- **SC-004**: The visual map correctly represents branch parent relationships with 100% accuracy when compared to `git log --graph`
- **SC-005**: Map renders and becomes interactive within 2 seconds for repositories with up to 20 worktrees
- **SC-006**: Developers can navigate and select worktrees using keyboard alone (no mouse required)
- **SC-007**: 90% of developers report the visual map helps them understand their worktree relationships better than the list view (measured by user feedback survey)
- **SC-008**: The compact map view remains readable and usable with up to 10 worktrees without requiring expansion

## Assumptions

- Existing git metadata infrastructure (Feature 108) provides ahead/behind counts and merge status
- Branch parent relationships can be determined via `git merge-base` commands
- The Eww monitoring panel supports embedded visualizations (GTK drawing or SVG rendering via Eww widgets)
- Performance-sensitive git operations (merge-base, log --graph) will be cached with appropriate invalidation
- Users are familiar with directed graph visualizations (similar to gitk, GitHub network graph)
- The existing worktree card list view remains available as an alternative to the map view
- Conflict detection is based on file path overlap, not content-level diff analysis (performance consideration)
