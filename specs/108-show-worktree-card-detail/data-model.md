# Data Model: Enhanced Worktree Card Status Display

**Feature**: 108-show-worktree-card-detail
**Date**: 2025-12-01

## Entity Definitions

### 1. EnhancedGitMetadata

Extended git metadata returned by `get_git_metadata()` function.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `current_branch` | `str` | Branch name | `git rev-parse --abbrev-ref HEAD` |
| `commit_hash` | `str` | Short commit hash (7 chars) | `git rev-parse --short HEAD` |
| `is_clean` | `bool` | No uncommitted changes | `git status --porcelain` (empty) |
| `has_untracked` | `bool` | Has untracked files | `??` in porcelain output |
| `ahead_count` | `int` | Commits ahead of upstream | `git rev-list --left-right --count` |
| `behind_count` | `int` | Commits behind upstream | `git rev-list --left-right --count` |
| `remote_url` | `Optional[str]` | Origin remote URL | `git remote get-url origin` |
| **`is_merged`** | `bool` | Branch merged into main | `git branch --merged main` |
| **`is_stale`** | `bool` | No commits in 30+ days | `git log -1 --format=%ct` |
| **`last_commit_timestamp`** | `int` | Unix epoch of last commit | `git log -1 --format=%ct` |
| **`last_commit_message`** | `str` | Commit subject line (max 50 chars) | `git log -1 --format=%s` |
| **`staged_count`** | `int` | Staged files count | Porcelain: lines with [MADRC] in col 1 |
| **`modified_count`** | `int` | Modified (unstaged) count | Porcelain: lines with [MD] in col 2 |
| **`untracked_count`** | `int` | Untracked files count | Porcelain: lines starting with `??` |
| **`has_conflicts`** | `bool` | Has unresolved conflicts | Porcelain: `UU`, `AA`, or `DD` codes |

**Bold** = New fields for Feature 108

### 2. WorktreeStatusIndicators

Computed display values for Eww widget rendering.

| Field | Type | Description | Derived From |
|-------|------|-------------|--------------|
| `git_is_dirty` | `bool` | Has uncommitted changes | `not is_clean` |
| `git_dirty_indicator` | `str` | "●" or "" | `"●" if git_is_dirty else ""` |
| `git_ahead` | `int` | Commits ahead | `ahead_count` |
| `git_behind` | `int` | Commits behind | `behind_count` |
| `git_sync_indicator` | `str` | "↑5 ↓2" format | Computed from ahead/behind |
| **`git_is_merged`** | `bool` | Merged into main | `is_merged` |
| **`git_merged_indicator`** | `str` | "✓" or "" | `"✓" if is_merged else ""` |
| **`git_is_stale`** | `bool` | Stale worktree | `is_stale` |
| **`git_stale_indicator`** | `str` | "💤" or "" | `"💤" if is_stale else ""` |
| **`git_has_conflicts`** | `bool` | Has conflicts | `has_conflicts` |
| **`git_conflict_indicator`** | `str` | "⚠" or "" | `"⚠" if has_conflicts else ""` |
| **`git_last_commit_relative`** | `str` | "2h ago", "3 days ago" | Computed from timestamp |
| **`git_last_commit_message`** | `str` | Truncated subject | `last_commit_message[:50]` |
| **`git_status_tooltip`** | `str` | Multi-line tooltip | Computed summary |

### 3. WorktreeData (JSON Structure for Eww)

Complete worktree object passed to Eww widget via deflisten stream.

```json
{
  "qualified_name": "vpittamp/nixos:099-feature",
  "branch": "099-feature",
  "path": "/home/vpittamp/nixos-099-feature",
  "directory_display": "~/nixos-099-feature",
  "commit": "abc1234",
  "is_active": true,
  "is_main": false,

  // Existing status fields
  "git_is_dirty": true,
  "git_dirty_indicator": "●",
  "git_ahead": 5,
  "git_behind": 2,
  "git_sync_indicator": "↑5 ↓2",

  // NEW: Merge status (Feature 108)
  "git_is_merged": false,
  "git_merged_indicator": "",

  // NEW: Stale detection (Feature 108)
  "git_is_stale": false,
  "git_stale_indicator": "",

  // NEW: Conflict detection (Feature 108)
  "git_has_conflicts": false,
  "git_conflict_indicator": "",

  // NEW: Detailed breakdown (Feature 108)
  "git_staged_count": 2,
  "git_modified_count": 3,
  "git_untracked_count": 1,
  "git_last_commit_relative": "2h ago",
  "git_last_commit_message": "Fix authentication bug",

  // NEW: Tooltip content (Feature 108)
  "git_status_tooltip": "Branch: 099-feature\nCommit: abc1234 (2h ago)\nStatus: 2 staged, 3 modified, 1 untracked\nSync: 5 to push, 2 to pull"
}
```

## Validation Rules

### EnhancedGitMetadata

| Field | Validation |
|-------|------------|
| `current_branch` | Non-empty string, "HEAD" for detached state |
| `commit_hash` | 7-character hex string |
| `ahead_count` | Non-negative integer |
| `behind_count` | Non-negative integer |
| `last_commit_timestamp` | Positive Unix epoch (> 0) |
| `last_commit_message` | Truncated to 50 characters |
| `staged_count` | Non-negative integer |
| `modified_count` | Non-negative integer |
| `untracked_count` | Non-negative integer |

### WorktreeStatusIndicators

| Field | Validation |
|-------|------------|
| `git_sync_indicator` | Empty string if both ahead/behind are 0 |
| `git_merged_indicator` | Only "✓" for merged branches, not for main itself |
| `git_stale_indicator` | Only for branches with last_commit > 30 days |
| `git_last_commit_relative` | Format: "Xm ago", "Xh ago", "Xd ago", "X weeks ago", "X months ago" |

## State Transitions

### Dirty State

```
Clean → Dirty: Any file modified/staged/untracked
Dirty → Clean: All changes committed or discarded
```

### Merge State

```
Unmerged → Merged: Branch merged into main (locally or via PR)
Merged → Unmerged: Not possible (immutable once merged)
```

### Stale State

```
Active → Stale: No commits for 30+ days
Stale → Active: New commit added
```

### Conflict State

```
No Conflicts → Conflicts: Merge/rebase with conflicts
Conflicts → No Conflicts: All conflicts resolved
```

## Relationships

```
Repository (1) ──────< (*) Worktree
                          │
                          ├── has EnhancedGitMetadata (1:1)
                          │
                          └── computed WorktreeStatusIndicators (1:1)
```

## Catppuccin Mocha Color Mapping

| Status | CSS Class | Color | Hex |
|--------|-----------|-------|-----|
| Dirty | `.badge-dirty`, `.git-dirty` | red | #f38ba8 |
| Ahead | `.git-sync.ahead` | green | #a6e3a1 |
| Behind | `.git-sync.behind` | peach/orange | #fab387 |
| Merged | `.badge-merged` | teal | #94e2d5 |
| Stale | `.badge-stale` | overlay0 (gray) | #6c7086 |
| Conflicts | `.badge-conflict` | red | #f38ba8 |
| Active | `.badge-active` | teal | #94e2d5 |
