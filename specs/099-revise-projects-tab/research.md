# Research: Projects Tab CRUD Enhancement

**Feature**: 099-revise-projects-tab
**Date**: 2025-11-28
**Status**: Complete

## Decisions Summary

### Decision 1: Data Flow Architecture

**Decision**: Use existing CLI commands (`i3pm worktree create/remove`) as backend for form submissions, not direct IPC calls.

**Rationale**:
- CLI already handles all Git operations, validation, error messages
- CLI provides atomic operations (create worktree + register project + zoxide)
- Consistent with existing project-edit-save script pattern
- Simpler error handling - parse CLI stdout/stderr

**Alternatives Considered**:
- Direct IPC calls to daemon → Rejected: Would require reimplementing Git logic in daemon
- Bash wrapper around git commands → Rejected: CLI already exists

### Decision 2: Hierarchical Display Structure

**Decision**: Use `get_projects_hierarchy()` from monitoring_data.py to structure projects as:
- Repository projects (expandable containers with [+ New Worktree] button)
- Nested worktrees (indented children with edit/delete actions)
- Standalone projects (non-git directories)
- Orphaned worktrees (separate section with recovery options)

**Rationale**:
- Function already implemented and provides required data structure
- Includes worktree_count, has_dirty bubble-up, parent linking
- Matches Feature 097 spec architecture

**Alternatives Considered**:
- Flat list with filters → Rejected: Loses hierarchical context

### Decision 3: Form Submission Pattern

**Decision**: Use Bash wrapper scripts that:
1. Read form values from Eww variables
2. Execute CLI command with those values
3. Parse CLI output for success/error
4. Update Eww notification variables

**Rationale**:
- Matches existing project-edit-save, worktree-create scripts
- Keeps Eww widget declarative (no complex logic in Yuck)
- Error handling via exit codes and stderr parsing

**Alternatives Considered**:
- Python subprocess wrapper → More complex, no benefit
- Direct IPC JSON → Would bypass CLI validation

### Decision 4: Worktree Form Fields

**Decision**: Create form accepts:
- `branch` (required): Autocomplete not feasible, validate on submit
- `worktree_path` (optional): Default to `$HOME/nixos-<branch>`
- `display_name` (optional): Default to branch name humanized
- `icon` (optional): Default to "🌿"

Edit form:
- `display_name` (editable)
- `icon` (editable)
- `branch`, `worktree_path` (read-only, shown for context)

**Rationale**:
- Matches CLI command options
- Branch autocomplete requires git branch enumeration (complex UI)
- Validation on submit is sufficient for occasional operation

**Alternatives Considered**:
- Wizard-style multi-step form → Over-engineered for simple operation

### Decision 5: Delete Confirmation Pattern

**Decision**: Two-stage confirmation:
1. Click delete shows "Click again to confirm" (5 second timeout)
2. Second click within timeout executes delete

For worktrees with uncommitted changes: Show warning dialog first.

**Rationale**:
- Matches existing worktree-delete pattern in widget
- Simpler than modal dialog
- Warning for dirty worktrees prevents data loss

**Alternatives Considered**:
- Modal confirmation dialog → Requires overlay component
- Type-to-confirm → Over-engineered

### Decision 6: Git Status Display

**Decision**: Show git status indicators:
- Branch name with icon (󰘬)
- Dirty indicator (● red) next to branch when uncommitted changes
- Ahead/behind counts (↑3 ↓2) in git branch row
- Parent repository shows aggregate dirty count from all worktrees

**Rationale**:
- Already partially implemented in project-card/worktree-card
- Matches existing styling patterns
- Bubble-up via has_dirty field from get_projects_hierarchy()

**Alternatives Considered**:
- Detailed status popup → Too complex for dashboard view

### Decision 7: Orphaned Worktree Handling

**Decision**: Display orphaned worktrees in separate "Orphaned" section with:
- Warning icon (⚠️)
- Message: "Parent repository not registered"
- [Recover] button that runs discovery on bare repo path
- [Delete] button for cleanup

**Rationale**:
- detect_orphaned_worktrees() already identifies these
- Recovery via discovery is the natural fix
- Users need ability to clean up orphans

**Alternatives Considered**:
- Hide orphaned worktrees → Violates transparency principle
- Auto-recover on panel open → Could be slow, surprising

### Decision 8: Project Switching Behavior

**Decision**: Click on project/worktree row executes `i3pm project switch <name>`:
- Clickable area: entire row except action buttons
- Active indicator: moves immediately on switch
- Missing project: show error notification, prevent switch

**Rationale**:
- Consistent with existing project switching behavior
- Active indicator already implemented via is_active field
- Missing status prevents problematic switches

**Alternatives Considered**:
- Double-click to switch → Less discoverable, inconsistent

## Technical Findings

### Existing IPC Methods Available

| Method | Purpose | Status |
|--------|---------|--------|
| `worktree.list` | List worktrees for parent | ✅ Implemented |
| `project.refresh` | Update git/branch metadata | ✅ Implemented |
| `project.update` | Modify project fields | ✅ Implemented |
| `project.list` | List all projects | ✅ Implemented |
| `project.current` | Get active project | ✅ Implemented |

### Existing CLI Commands Available

| Command | Purpose | Status |
|---------|---------|--------|
| `i3pm worktree create <branch>` | Create worktree + project | ✅ Implemented |
| `i3pm worktree remove <name>` | Remove worktree + cleanup | ✅ Implemented |
| `i3pm worktree list [parent]` | List worktrees | ✅ Implemented |
| `i3pm project switch <name>` | Switch active project | ✅ Implemented |
| `i3pm project update <name>` | Update project fields | ✅ Implemented |

### Data Model Fields (from monitoring_data.py)

**Repository Project**:
```python
{
  "name": str,
  "display_name": str,
  "directory": str,
  "icon": str,
  "source_type": "local",
  "status": "active" | "missing",
  "git_metadata": {
    "current_branch": str,
    "commit_hash": str,
    "is_clean": bool,
    "ahead_count": int,
    "behind_count": int
  },
  "worktree_count": int,     # Computed: count of child worktrees
  "has_dirty": bool,         # Computed: any child has uncommitted changes
  "is_active": bool,         # Computed: matches current project
  "is_expanded": bool        # UI state: collapsed/expanded
}
```

**Worktree Project**:
```python
{
  "name": str,
  "display_name": str,
  "directory": str,
  "icon": str,
  "source_type": "worktree",
  "parent_project": str,     # Parent repository name
  "branch_metadata": {
    "number": str | None,    # e.g., "098"
    "type": str | None,      # e.g., "feature"
    "full_name": str         # e.g., "098-feature-auth"
  },
  "git_metadata": {...},     # Same as repository
  "status": "active" | "missing",
  "is_active": bool,
  "is_remote": bool          # Feature 087
}
```

### Key File Locations

| File | Purpose |
|------|---------|
| `home-modules/desktop/eww-monitoring-panel.nix` | Widget definitions (projects-view, project-card, worktree-card) |
| `home-modules/tools/i3_project_manager/cli/monitoring_data.py` | Backend data script |
| `home-modules/tools/i3pm/src/commands/worktree/` | CLI worktree commands |
| `home-modules/desktop/i3-project-event-daemon/models/discovery.py` | BranchMetadata model |

### Gaps Identified

1. **Create worktree form not connected to CLI** - Scripts exist but form submission needs completion
2. **Repository project expand/collapse** - Need expandable container with toggle
3. **Worktree count badge on collapsed parent** - Need computed field display
4. **Orphaned worktree section** - Need separate display section
5. **Git status bubble-up display** - Need aggregate indicator on parent
6. **Refresh button** - Need to trigger `project.refresh` for all displayed projects

## Implementation Priorities

1. **P1**: Verify existing worktree create/delete forms work correctly
2. **P1**: Add hierarchical repository → worktree display with expand/collapse
3. **P1**: Add [+ New Worktree] button on repository cards
4. **P1**: Test project switching from panel
5. **P2**: Add git status bubble-up indicators
6. **P2**: Add orphaned worktree section
7. **P2**: Add refresh all button
