# Feature Specification: Preview Pane User Experience

**Feature Branch**: `079-preview-pane-user-experience`
**Created**: 2025-11-16
**Status**: Draft
**Input**: User description: "Optimize the user experience for using git worktrees via i3pm worktree commands and using the eww components: preview pane, bottom bar, top bar, and notification center to complement our worktree logic to allow the user to take actions, and get visual feedback."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Navigate Project List with Arrow Keys (Priority: P1)

User enters project selection mode by pressing ":" in workspace mode and wants to navigate through the project list using arrow keys to find and select a project.

**Why this priority**: Core usability issue - users cannot navigate project lists without arrow keys, forcing reliance on fuzzy search alone. This is a fundamental interaction pattern expected in any list-based UI.

**Independent Test**: Can be tested by entering project mode, verifying arrow keys move selection up/down through list, and confirming visual selection indicator updates in real-time.

**Acceptance Scenarios**:

1. **Given** user is in project selection mode with project list displayed, **When** user presses Down arrow, **Then** selection moves to next project in list with visual highlight update
2. **Given** user has selection at bottom of visible list, **When** user presses Down arrow, **Then** selection wraps to top of list (circular navigation)
3. **Given** user has filtered project list with filter text, **When** user presses Up/Down arrows, **Then** navigation occurs within filtered results only
4. **Given** user has navigated to a project, **When** user presses Enter, **Then** system switches to selected project

---

### User Story 2 - Backspace Exits Project Selection Mode (Priority: P1)

User enters project selection mode by typing ":" and wants to cancel by pressing backspace, returning to the main workspace mode menu.

**Why this priority**: Essential escape mechanism - users need intuitive way to exit modes without committing to an action, following standard UI patterns.

**Independent Test**: Can be tested by entering project mode, pressing backspace, and verifying return to main workspace mode with ":" removed from input.

**Acceptance Scenarios**:

1. **Given** user is in project selection mode with ":" as only input, **When** user presses Backspace, **Then** system removes ":" and returns to main workspace mode display
2. **Given** user is in project selection mode with filter text (e.g., ":nix"), **When** user presses Backspace multiple times, **Then** characters are removed one at a time until ":" is removed, then exits to main mode
3. **Given** user returns to main mode via backspace, **When** main mode displays, **Then** workspace preview (not project list) is shown

---

### User Story 3 - Filter Projects by Branch Number Prefix (Priority: P1)

User wants to quickly filter to a specific project by typing its branch number prefix (e.g., ":79" to find branch "079-preview-pane-user-experience").

**Why this priority**: Enables deterministic project selection - users with many feature branches can jump directly to known branch numbers without scrolling or fuzzy matching ambiguity.

**Independent Test**: Can be tested by typing ":79" and verifying that branch "079-*" appears highlighted, with exact numeric match taking priority over substring matches.

**Acceptance Scenarios**:

1. **Given** project list contains branch "079-preview-pane-user-experience", **When** user types ":79", **Then** that project is highlighted as top match
2. **Given** multiple projects have "79" in their names, **When** user types ":079", **Then** exact prefix match "079-*" ranks higher than substring match "179-*"
3. **Given** project display shows "Preview Pane UX", **When** user types ":079", **Then** filter still matches because underlying branch name contains "079"

---

### User Story 4 - Display Branch Number in Project List (Priority: P2)

User views project list and wants to see the full branch identifier including the numeric prefix (e.g., "079") alongside the display name.

**Why this priority**: Users need to identify projects by both human-readable name and technical branch number for deterministic filtering and mental mapping.

**Independent Test**: Can be tested by opening project list and verifying each entry shows both branch number prefix (if present) and display name.

**Acceptance Scenarios**:

1. **Given** project has branch "079-preview-pane-user-experience", **When** project list displays, **Then** entry shows "079 - Preview Pane UX" (number + name)
2. **Given** project has branch without numeric prefix (e.g., "main"), **When** project list displays, **Then** entry shows display name without number prefix
3. **Given** project is a worktree with parent "nixos" and branch "079-*", **When** project list displays, **Then** entry shows hierarchical relationship (parent indicator + number + name)

---

### User Story 5 - Visual Worktree Hierarchy in Project List (Priority: P2)

User views project list and wants to see worktrees grouped under their root projects to understand repository relationships.

**Why this priority**: Worktrees are branches of a parent repository; visual hierarchy clarifies relationships and reduces cognitive load when managing multiple worktrees.

**Independent Test**: Can be tested by creating worktrees from a root project and verifying they appear visually nested or grouped under parent in project list.

**Acceptance Scenarios**:

1. **Given** "nixos" is root project with worktrees "079-preview-pane", "080-feature-x", **When** project list displays, **Then** worktrees appear indented or grouped under "nixos" parent
2. **Given** user has both standalone projects and worktrees, **When** project list displays, **Then** standalone projects appear at top level, worktrees appear nested
3. **Given** worktree list is long, **When** user filters by parent name (e.g., ":nixos"), **Then** all worktrees of that parent are shown

---

### User Story 6 - Fix i3pm Worktree List Command (Priority: P2)

User runs `i3pm worktree list` command to see all available worktrees and expects a formatted list output.

**Why this priority**: CLI command is non-functional; users need programmatic access to worktree information for scripting and verification.

**Independent Test**: Can be tested by running `i3pm worktree list` and verifying JSON output with worktree metadata.

**Acceptance Scenarios**:

1. **Given** repository has 3 worktrees, **When** user runs `i3pm worktree list`, **Then** command outputs list with branch name, path, and git status for each
2. **Given** worktree is dirty (uncommitted changes), **When** user runs `i3pm worktree list`, **Then** status indicator shows "dirty" state
3. **Given** no worktrees exist, **When** user runs `i3pm worktree list`, **Then** command outputs empty list with informative message

---

### User Story 7 - Enhanced Top Bar Project Label (Priority: P2)

User views top bar and wants to see the active project/worktree with prominent visual styling and an icon indicating project type.

**Why this priority**: Active project context is critical information; current label is not visually prominent enough for quick identification.

**Independent Test**: Can be tested by switching projects and verifying top bar label updates with icon, styling, and project name clearly visible.

**Acceptance Scenarios**:

1. **Given** user is in project "079-preview-pane-user-experience", **When** top bar displays, **Then** label shows project icon (folder or git branch icon) + "079 - Preview Pane UX" with accent color background
2. **Given** user switches from one project to another, **When** top bar updates, **Then** label changes within 500ms with smooth transition
3. **Given** user is in global mode (no project), **When** top bar displays, **Then** label shows "Global" with distinct styling (dimmed or different icon)

---

### User Story 8 - Worktree Metadata in Environment Variables (Priority: P3)

User launches an application within a worktree context and expects environment variables to indicate worktree-specific metadata (is_worktree, parent_project, branch_type).

**Why this priority**: Foundation for future worktree-aware features; applications can adapt behavior based on worktree context without additional queries.

**Independent Test**: Can be tested by launching an app in worktree context, inspecting process environment for I3PM_IS_WORKTREE, I3PM_PARENT_PROJECT variables.

**Acceptance Scenarios**:

1. **Given** user launches VS Code in worktree "079-*", **When** process starts, **Then** environment contains I3PM_IS_WORKTREE=true, I3PM_PARENT_PROJECT=nixos, I3PM_BRANCH_TYPE=feature
2. **Given** user launches terminal in root project "nixos", **When** process starts, **Then** environment contains I3PM_IS_WORKTREE=false, I3PM_PARENT_PROJECT="" (empty)
3. **Given** process inherits environment, **When** child processes spawn, **Then** worktree metadata propagates to children

---

### User Story 9 - Click Notification to Navigate to Source Window (Priority: P3)

User receives a Claude Code notification (from stop hook) and wants to click on it to navigate directly to the tmux session/window that generated it.

**Why this priority**: Improves workflow when running multiple Claude Code instances; user can quickly jump to completed session without manual window search.

**Independent Test**: Can be tested by triggering Claude Code stop hook, clicking notification, and verifying focus shifts to originating tmux window.

**Acceptance Scenarios**:

1. **Given** Claude Code session in tmux window "nixos:claude" completes, **When** notification appears, **Then** notification body includes window identifier "nixos:claude"
2. **Given** notification with window identifier is displayed, **When** user clicks notification, **Then** system focuses tmux window "nixos:claude"
3. **Given** multiple Claude Code sessions running, **When** each generates notification, **Then** each notification correctly identifies its source window

---

### User Story 10 - Eliminate Spaces in Project Names for Deterministic Logic (Priority: P3)

User views project list where display names currently contain spaces, but internal project identifiers must be space-free for command compatibility.

**Why this priority**: System commands don't accept spaces; current display creates confusion between visual name and actual identifier used in commands.

**Independent Test**: Can be tested by verifying display shows "Preview Pane UX" but commands/filters use "079-preview-pane-user-experience" (hyphenated).

**Acceptance Scenarios**:

1. **Given** project branch is "079-preview-pane-user-experience", **When** project list displays, **Then** shows human-readable "079 - Preview Pane UX" but filter operates on branch name
2. **Given** user types ":preview pane", **When** filter applies, **Then** matches "079-preview-pane-user-experience" by treating spaces as word boundaries/hyphens
3. **Given** user selects project from list, **When** switch occurs, **Then** system uses branch name (no spaces) for internal operations

---

### Edge Cases

- What happens when user rapidly presses arrow keys during project list animation?
- How does system handle when project JSON files are malformed or missing?
- What happens when user types filter that matches no projects?
- How does backspace behave when pressed in rapid succession?
- What happens when notification is clicked but tmux session no longer exists?
- How does system handle worktrees with very long branch names that exceed display width?

## Requirements *(mandatory)*

### Functional Requirements

**Preview Pane Navigation**:
- **FR-001**: System MUST respond to Up/Down arrow keys in project selection mode by moving selection indicator through project list
- **FR-002**: System MUST support circular navigation (bottom wraps to top, top wraps to bottom) in project list
- **FR-003**: System MUST exit project selection mode and return to main workspace mode when user removes ":" via backspace
- **FR-004**: System MUST filter projects by numeric prefix when user types digits after ":" (e.g., ":79" matches "079-*")
- **FR-005**: System MUST display branch number prefix (e.g., "079") in project list entries when present
- **FR-006**: System MUST visually distinguish worktrees from root projects in project list (hierarchy indicator)
- **FR-007**: System MUST group worktrees under their parent project in project list display
- **FR-008**: System MUST update selection highlight within 50ms of arrow key press (responsive feedback)

**Worktree Commands**:
- **FR-009**: System MUST implement `i3pm worktree list` command to output all worktrees with metadata
- **FR-010**: System MUST include branch name, path, and git status (clean/dirty/ahead/behind) in worktree list output

**Top Bar Enhancement**:
- **FR-011**: System MUST display project/worktree icon alongside active project name in top bar
- **FR-012**: System MUST style active project label with accent color background for visual prominence
- **FR-013**: System MUST update top bar project label within 500ms of project switch

**Environment Variables**:
- **FR-014**: System MUST inject I3PM_IS_WORKTREE environment variable (true/false) into launched applications
- **FR-015**: System MUST inject I3PM_PARENT_PROJECT environment variable (parent repo name or empty) into launched applications
- **FR-016**: System MUST inject I3PM_BRANCH_TYPE environment variable (feature/main/hotfix) into launched applications

**Notification Center**:
- **FR-017**: System MUST include source window identifier (tmux session:window) in Claude Code stop notifications
- **FR-018**: System MUST navigate to source tmux window when user clicks on Claude Code notification
- **FR-019**: System MUST gracefully handle notification click when source window no longer exists (show info message)

### Key Entities

- **Project**: Represents a workspace context with name, path, icon, and metadata (is_worktree, parent, branch_type)
- **Worktree**: Git worktree attached to a parent repository with branch-specific state (dirty/clean, ahead/behind)
- **Filter State**: Current project filter context including input text, filtered results, selected index, navigation position
- **Notification Context**: Metadata about notification source including window identifier, project context, timestamp

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can navigate project list with arrow keys and select project in under 3 key presses (arrow + Enter)
- **SC-002**: Users can filter to specific branch by typing 3-digit prefix with 100% accuracy (e.g., ":079" always finds "079-*")
- **SC-003**: Project list displays branch numbers for 100% of feature branches with numeric prefixes
- **SC-004**: Top bar project label is readable from 1 meter distance (sufficient size and contrast)
- **SC-005**: Arrow key navigation response time is under 50ms (no perceptible lag)
- **SC-006**: Clicking notification navigates to source window in under 500ms
- **SC-007**: i3pm worktree list command returns complete metadata for all worktrees in under 1 second
- **SC-008**: 95% of users can exit project mode via backspace on first attempt (intuitive behavior)
- **SC-009**: Worktree hierarchy is visually distinguishable in project list (users can identify parent-child relationships)
- **SC-010**: Environment variables are present in 100% of launched application processes within worktree context

## Assumptions

- Users have familiarity with keyboard-driven workflows and expect standard navigation patterns (arrow keys, Enter, Escape, Backspace)
- Branch names follow the pattern `NNN-descriptive-name` where NNN is a 3-digit feature number
- Git worktrees are managed through i3pm commands and have JSON metadata files in `~/.config/i3/projects/`
- Tmux is the primary terminal multiplexer for managing Claude Code sessions
- Notification center (SwayNC) supports clickable actions via notify-send parameters
- Top bar widget has sufficient space for icon + formatted project name display
- Response time expectations: UI updates < 50ms, project switches < 500ms, CLI commands < 1 second
