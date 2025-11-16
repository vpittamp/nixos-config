# Feature Specification: Enhanced Project Selection in Eww Preview Dialog

**Feature Branch**: `078-eww-preview-improvement`
**Created**: 2025-11-16
**Status**: Draft
**Input**: User description: "Enhance Eww preview dialog with better project selection - show list of projects via ':' prefix, fuzzy filter as typing, highlight best match, show icons, visualize root vs worktree relationships, support naming convention {digits}-{word}-{word}-{word}"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Quick Project Switch via Fuzzy Search (Priority: P1)

As a developer with multiple projects open, I want to quickly switch to another project by typing a few characters of its name, so that I can context-switch without remembering exact project names or using mouse navigation.

**Why this priority**: This is the core functionality that directly improves productivity. Users spend significant time switching between projects, and reducing friction here has immediate value. This is the minimum viable feature that delivers the promised enhancement.

**Independent Test**: Can be fully tested by activating workspace mode, typing ":" followed by project name characters, and verifying project switch occurs. Delivers immediate value of faster project switching.

**Acceptance Scenarios**:

1. **Given** I'm in workspace mode (CapsLock pressed), **When** I type ":", **Then** the preview dialog shows a scrollable list of all available projects sorted by recency
2. **Given** I'm in project selection mode with the list visible, **When** I type "nix", **Then** the list filters to show only projects containing "nix" (case-insensitive), and the best match is highlighted
3. **Given** I'm in project selection mode with "078" typed and "078-eww-preview-improvement" highlighted, **When** I press Enter, **Then** the system switches to that project and closes the preview dialog
4. **Given** I'm in project selection mode with "age-fra" typed, **When** the system performs matching, **Then** it finds "agent-framework" by matching across word boundaries (a-g-e from "agent", fra from "framework")
5. **Given** I'm in project selection mode, **When** I type characters that match no projects, **Then** the list shows "No matching projects" message and Enter does nothing

---

### User Story 2 - Visual Worktree Relationship Display (Priority: P2)

As a developer working with git worktrees, I want to immediately see which projects are root repositories vs worktrees, and understand their parent relationship, so that I can make informed decisions about which project context to enter.

**Why this priority**: Understanding worktree relationships prevents confusion when working with feature branches. This builds on P1 by adding critical context, but P1 is usable without it.

**Independent Test**: Can be fully tested by viewing the project list and verifying worktree indicators appear correctly for known worktree projects. Delivers contextual information about project structure.

**Acceptance Scenarios**:

1. **Given** a project is a root repository (has no worktree metadata), **When** it's displayed in the project list, **Then** it shows a "root" badge/icon (e.g., 📁 or tree icon)
2. **Given** a project is a git worktree (has worktree metadata), **When** it's displayed in the project list, **Then** it shows a "worktree" badge/icon (e.g., 🌿 or branch icon)
3. **Given** a worktree project with repository_path pointing to /etc/nixos, **When** it's displayed, **Then** it shows the parent relationship (e.g., "from: nixos" or "← NixOS")
4. **Given** multiple worktrees from the same root project, **When** displayed in the list, **Then** they are visually grouped or show consistent parent relationship indicators

---

### User Story 3 - Project Metadata at a Glance (Priority: P3)

As a developer, I want to see relevant metadata about each project (icon, git status, last activity) at a glance in the project list, so that I can quickly assess which project I need and its current state.

**Why this priority**: Metadata enhances decision-making but is not essential for basic switching functionality. This adds polish and power-user features.

**Independent Test**: Can be fully tested by viewing project list entries and verifying all metadata fields display correctly for projects with complete metadata. Delivers richer information context.

**Acceptance Scenarios**:

1. **Given** a project has an icon configured, **When** displayed in the list, **Then** the project's emoji icon appears prominently (e.g., 🌿 for current, ❄️ for nixos)
2. **Given** a worktree project with git status (is_clean, ahead_count, behind_count), **When** displayed in the list, **Then** it shows status indicators (e.g., ✓ clean, ↑3 ahead, ↓2 behind)
3. **Given** a project with last_modified timestamp, **When** displayed in the list, **Then** it shows relative time (e.g., "2h ago", "3 days ago")
4. **Given** a project name follows the pattern {digits}-{word}-{word}-{word} (e.g., "078-eww-preview-improvement"), **When** displayed in the list, **Then** the display_name shows the human-readable version (e.g., "eww preview improvement") with the branch number visible

---

### User Story 4 - Keyboard-Driven Navigation (Priority: P3)

As a keyboard-focused developer, I want to navigate the filtered project list using arrow keys and select using Enter, so that I can efficiently browse and select projects without reaching for the mouse.

**Why this priority**: Enhances usability for power users who prefer keyboard-only workflows. Builds on existing arrow key navigation pattern from workspace mode.

**Independent Test**: Can be fully tested by typing ":", then using Up/Down arrows to navigate through the list, and Enter to select. Delivers consistent keyboard-centric interaction.

**Acceptance Scenarios**:

1. **Given** I'm in project selection mode with multiple projects listed, **When** I press Down arrow, **Then** the highlight moves to the next project in the list (wraps to top at bottom)
2. **Given** I'm in project selection mode with a project highlighted, **When** I press Up arrow, **Then** the highlight moves to the previous project (wraps to bottom at top)
3. **Given** I've navigated to a specific project via arrows, **When** I press Enter, **Then** the system switches to that highlighted project, ignoring typed filter
4. **Given** I'm typing a filter and arrow navigation hasn't been used, **When** Enter is pressed, **Then** the system switches to the top (best match) highlighted project

---

### User Story 5 - Cancel and Return to Previous Mode (Priority: P4)

As a user who accidentally entered project mode or changed my mind, I want to cancel the operation and return to my previous state, so that I can recover from mistakes without side effects.

**Why this priority**: Error recovery is important but is a safety net feature. Core functionality must work first.

**Independent Test**: Can be fully tested by entering project mode, typing characters, then pressing Escape and verifying no project switch occurs. Delivers safe exit path.

**Acceptance Scenarios**:

1. **Given** I'm in project selection mode with characters typed, **When** I press Escape, **Then** the preview dialog closes without switching projects
2. **Given** I'm in project selection mode, **When** I press Backspace repeatedly until ":" is removed, **Then** the system returns to workspace mode (showing all windows)
3. **Given** I'm in project selection mode, **When** I type an invalid character not allowed in project names, **Then** the character is ignored (not added to filter)

---

### Edge Cases

- What happens when no projects are configured? → Show "No projects found" message with hint to create projects
- How does system handle a project directory that no longer exists? → Show project in list with "missing" indicator, prevent switching to it
- What happens if two projects have very similar names (e.g., "nixos" and "nixos-old")? → Exact match takes priority over substring match
- How does the system handle rapid typing during filtering? → Debounce updates to prevent UI flickering, accumulate characters normally
- What happens if user types ":" twice? → Ignore second ":", maintain single project mode
- How does filtering handle special characters in project names (hyphens, underscores)? → Treat hyphens as word separators, include in searchable characters
- What happens if worktree parent project was deleted? → Show worktree with "orphaned" indicator, allow switching but warn

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST activate project selection mode when user types ":" while in workspace mode
- **FR-002**: System MUST display a scrollable list of all configured projects when project mode is activated
- **FR-003**: System MUST filter the project list in real-time as user types characters (case-insensitive fuzzy matching)
- **FR-004**: System MUST highlight the best matching project based on match quality (exact > prefix > substring > word-boundary)
- **FR-005**: System MUST switch to the highlighted project when user presses Enter
- **FR-006**: System MUST display each project's configured emoji icon in the list
- **FR-007**: System MUST visually distinguish between root repositories and git worktrees
- **FR-008**: System MUST show the parent repository relationship for worktree projects
- **FR-009**: System MUST support project names in the format {digits}-{word}-{word}-{word} (e.g., "078-eww-preview-improvement")
- **FR-010**: System MUST allow hyphens and digits in the fuzzy search filter (not exclude as special characters)
- **FR-011**: System MUST provide keyboard navigation (Up/Down arrows) through the project list
- **FR-012**: System MUST cancel project selection and close dialog when user presses Escape
- **FR-013**: System MUST return to workspace mode when user removes all typed characters via Backspace (including the ":")
- **FR-014**: System MUST sort projects by relevance when filter is active (match quality) or by recency when no filter is active
- **FR-015**: System MUST persist the filter state across character additions until mode is exited
- **FR-016**: System MUST display git status indicators (clean/dirty, ahead/behind counts) for worktree projects
- **FR-017**: System MUST show relative last-modified time for each project (when available)
- **FR-018**: System MUST display human-readable project names (display_name) alongside or instead of technical names
- **FR-019**: System MUST handle missing project directories gracefully (show warning, prevent switch)
- **FR-020**: System MUST support circular navigation (wrap from bottom to top and vice versa) in the project list

### Key Entities

- **Project**: Core entity with name, display_name, directory, icon, created_at, updated_at, scoped_classes
- **Worktree Metadata**: Optional sub-entity containing branch, commit_hash, is_clean, has_untracked, ahead_count, behind_count, worktree_path, repository_path, last_modified
- **Filter State**: Accumulated characters typed by user for fuzzy matching
- **Selection State**: Currently highlighted project in the list (index-based)
- **Match Result**: Score and matched project from fuzzy matching algorithm

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can switch to any project in 3 keystrokes or fewer for projects with unique prefixes (e.g., ":", "n", Enter for "nixos")
- **SC-002**: Filter results appear within 50ms of keystroke for lists of up to 100 projects
- **SC-003**: 100% of configured projects are discoverable in the project list (no projects hidden or inaccessible)
- **SC-004**: Users can visually identify root vs worktree status within 1 second of viewing a project entry
- **SC-005**: Parent repository relationship is clearly visible for all worktree projects without additional user action
- **SC-006**: Fuzzy matching correctly identifies projects when typing 3+ consecutive characters from any word in the project name
- **SC-007**: 90% of users successfully complete project switch on first attempt using the new interface
- **SC-008**: Arrow key navigation responds within 16ms (single frame) for smooth interaction
- **SC-009**: Git status indicators (clean/dirty, ahead/behind) are accurate and reflect actual repository state
- **SC-010**: Project list accommodates at least 50 projects without performance degradation or usability issues

## Assumptions

- Projects are stored in JSON files under `~/.config/i3/projects/` directory
- Project files follow the established schema with optional `worktree` metadata field
- The i3pm daemon is running and provides IPC communication channel
- Eww widgets can receive JSON data updates via variable binding
- Git worktree metadata is populated during project creation via `i3pm worktree create`
- Users are familiar with the existing workspace mode activation (CapsLock/Ctrl+0)
- All project icons are valid emoji characters renderable by the font stack
- Network latency is not a concern (local IPC only)
- Project count will not exceed 100 in typical usage scenarios
