# Data Model: Enhanced Git Worktree Status Indicators

**Feature**: 120-improve-git-changes
**Date**: 2025-12-16

## Entity Overview

This feature extends existing data models with additional git status fields. No new entities are created.

## Extended Entities

### WorktreeMetadata (Extended)

**Location**: `home-modules/tools/i3_project_manager/models/worktree.py`

Extends the existing `WorktreeMetadata` model with diff statistics fields.

```python
from pydantic import BaseModel, Field
from typing import Optional

class WorktreeMetadata(BaseModel):
    """Git worktree metadata with enhanced status indicators."""

    # Existing fields (Feature 108)
    branch: str
    commit: str
    path: str
    is_clean: bool = True
    has_untracked: bool = False
    ahead_count: int = 0
    behind_count: int = 0
    staged_count: int = 0
    modified_count: int = 0
    untracked_count: int = 0
    is_merged: bool = False
    is_stale: bool = False
    has_conflicts: bool = False
    last_commit_timestamp: Optional[int] = None
    last_commit_message: Optional[str] = None

    # NEW: Diff statistics (Feature 120)
    additions: int = Field(default=0, description="Total lines added across all uncommitted changes")
    deletions: int = Field(default=0, description="Total lines deleted across all uncommitted changes")
    diff_error: bool = Field(default=False, description="True if diff stats could not be computed")

    # Computed display fields
    @property
    def diff_total(self) -> int:
        """Total lines changed (additions + deletions)."""
        return self.additions + self.deletions

    @property
    def additions_display(self) -> str:
        """Formatted additions count with cap at 9999."""
        if self.additions > 9999:
            return "+9999"
        return f"+{self.additions}" if self.additions > 0 else ""

    @property
    def deletions_display(self) -> str:
        """Formatted deletions count with cap at 9999."""
        if self.deletions > 9999:
            return "-9999"
        return f"-{self.deletions}" if self.deletions > 0 else ""
```

### WorktreeDisplayData (New Helper)

**Location**: `home-modules/tools/i3_project_manager/cli/monitoring_data.py`

Data structure prepared for eww widget consumption.

```python
class WorktreeDisplayData(TypedDict):
    """Data structure for eww worktree display."""

    # Identity
    branch: str
    commit: str
    path: str
    qualified_name: str
    branch_number: Optional[str]
    branch_description: str

    # Status flags (boolean)
    is_active: bool
    git_is_dirty: bool
    git_is_merged: bool
    git_is_stale: bool
    git_has_conflicts: bool
    git_status_error: bool

    # Status counts
    git_ahead: int
    git_behind: int
    git_staged_count: int
    git_modified_count: int
    git_untracked_count: int

    # NEW: Diff statistics (Feature 120)
    git_additions: int
    git_deletions: int
    git_diff_total: int
    git_additions_display: str  # "+123" or "+9999" capped
    git_deletions_display: str  # "-45" or "-9999" capped

    # Display indicators
    git_dirty_indicator: str      # "●" or ""
    git_sync_indicator: str       # "↑3 ↓2" or ""
    git_merged_indicator: str     # "✓" or ""
    git_stale_indicator: str      # "💤" or ""
    git_conflict_indicator: str   # "⚠" or ""
    git_error_indicator: str      # "?" or ""

    # Tooltips
    git_status_tooltip: str       # Multi-line status summary
    git_diff_tooltip: str         # "+123 additions, -45 deletions"

    # Last commit info
    git_last_commit_relative: str
    git_last_commit_message: str
```

### ProjectDisplayData (Extended)

**Location**: `home-modules/tools/i3_project_manager/cli/monitoring_data.py`

Project data with aggregated git status for header display.

```python
class ProjectDisplayData(TypedDict):
    """Data structure for eww project display."""

    # Identity
    name: str
    scope: str  # "scoped" or "global"
    is_active: bool
    window_count: int

    # Worktrees (may be empty for non-worktree projects)
    worktrees: List[WorktreeDisplayData]

    # NEW: Aggregated git status for header (Feature 120)
    # Uses first worktree's status, or empty if no worktrees
    header_git_dirty: bool
    header_git_ahead: int
    header_git_behind: int
    header_git_merged: bool
    header_git_has_conflicts: bool
    header_git_additions: int
    header_git_deletions: int
```

## Data Transformations

### Transform: Git Diff Output → DiffStats

**Input**: `git diff --numstat HEAD` output
**Output**: `(additions: int, deletions: int)`

```
# Input example:
10	5	src/main.py
-	-	binary.png
3	0	README.md

# Output:
(13, 5)  # Binary files excluded
```

**Rules**:
1. Parse tab-separated: `additions<TAB>deletions<TAB>filename`
2. Skip lines starting with `-` (binary files)
3. Sum all additions and deletions
4. Return (0, 0) on parse error

### Transform: WorktreeMetadata → WorktreeDisplayData

**Rules**:
1. Copy identity fields directly
2. Compute `git_is_dirty = not is_clean`
3. Compute indicators based on state flags
4. Format counts with caps (9999 max)
5. Build tooltip with all status information
6. Include diff bar data (additions, deletions, total)

### Transform: Project + Worktrees → ProjectDisplayData

**Rules**:
1. Aggregate windows by project
2. Attach worktree data if project is worktree-based
3. Extract first worktree's git status for header display
4. Handle empty worktrees array gracefully

## Validation Rules

### WorktreeMetadata Validation

| Field | Rule | Error Message |
|-------|------|---------------|
| branch | Non-empty string | "Branch name is required" |
| commit | 7+ character hex | "Invalid commit hash" |
| path | Existing directory | "Worktree path does not exist" |
| additions | >= 0 | "Additions cannot be negative" |
| deletions | >= 0 | "Deletions cannot be negative" |
| ahead_count | >= 0 | "Ahead count cannot be negative" |
| behind_count | >= 0 | "Behind count cannot be negative" |

### Display Constraints

| Field | Constraint | Display |
|-------|------------|---------|
| additions | > 9999 | Show "+9999" |
| deletions | > 9999 | Show "-9999" |
| branch | > 30 chars | Truncate with "…" |
| commit_message | > 50 chars | Truncate with "…" |

## State Transitions

### Git Status State Machine

```
                    ┌──────────────┐
                    │    CLEAN     │
                    │   (is_clean) │
                    └──────┬───────┘
                           │ file modified/added
                           ▼
                    ┌──────────────┐
              ┌─────│    DIRTY     │─────┐
              │     │ (!is_clean)  │     │
              │     └──────┬───────┘     │
      git add │            │ git commit  │ merge conflict
              ▼            ▼             ▼
       ┌──────────┐  ┌──────────┐  ┌──────────────┐
       │  STAGED  │  │  CLEAN   │  │  CONFLICTS   │
       │(staged>0)│  │(is_clean)│  │(has_conflicts)│
       └──────────┘  └──────────┘  └──────────────┘
```

### Sync Status States

```
                    ┌──────────────┐
                    │   IN SYNC    │
                    │ ahead=0,     │
                    │ behind=0     │
                    └──────┬───────┘
               local commit│          remote commit
                    ┌──────┴──────┐
                    ▼             ▼
             ┌──────────┐  ┌──────────┐
             │  AHEAD   │  │  BEHIND  │
             │ ahead>0  │  │ behind>0 │
             └────┬─────┘  └────┬─────┘
                  │  diverged   │
                  └──────┬──────┘
                         ▼
                  ┌──────────────┐
                  │  DIVERGED    │
                  │ ahead>0 AND  │
                  │ behind>0     │
                  └──────────────┘
```

## JSON Schema (Eww Interface)

### worktree object

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["branch", "commit", "path"],
  "properties": {
    "branch": { "type": "string" },
    "commit": { "type": "string", "minLength": 7 },
    "path": { "type": "string" },
    "qualified_name": { "type": "string" },
    "is_active": { "type": "boolean", "default": false },

    "git_is_dirty": { "type": "boolean", "default": false },
    "git_is_merged": { "type": "boolean", "default": false },
    "git_is_stale": { "type": "boolean", "default": false },
    "git_has_conflicts": { "type": "boolean", "default": false },
    "git_status_error": { "type": "boolean", "default": false },

    "git_ahead": { "type": "integer", "minimum": 0, "default": 0 },
    "git_behind": { "type": "integer", "minimum": 0, "default": 0 },
    "git_staged_count": { "type": "integer", "minimum": 0, "default": 0 },
    "git_modified_count": { "type": "integer", "minimum": 0, "default": 0 },
    "git_untracked_count": { "type": "integer", "minimum": 0, "default": 0 },

    "git_additions": { "type": "integer", "minimum": 0, "default": 0 },
    "git_deletions": { "type": "integer", "minimum": 0, "default": 0 },
    "git_diff_total": { "type": "integer", "minimum": 0, "default": 0 },
    "git_additions_display": { "type": "string", "default": "" },
    "git_deletions_display": { "type": "string", "default": "" },

    "git_dirty_indicator": { "type": "string", "enum": ["●", ""] },
    "git_sync_indicator": { "type": "string" },
    "git_merged_indicator": { "type": "string", "enum": ["✓", ""] },
    "git_stale_indicator": { "type": "string", "enum": ["💤", ""] },
    "git_conflict_indicator": { "type": "string", "enum": ["⚠", ""] },
    "git_error_indicator": { "type": "string", "enum": ["?", ""] },

    "git_status_tooltip": { "type": "string" },
    "git_diff_tooltip": { "type": "string" },
    "git_last_commit_relative": { "type": "string" },
    "git_last_commit_message": { "type": "string" }
  }
}
```

### project object (extended)

```json
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "scope": { "type": "string", "enum": ["scoped", "global"] },
    "is_active": { "type": "boolean" },
    "window_count": { "type": "integer", "minimum": 0 },
    "worktrees": {
      "type": "array",
      "items": { "$ref": "#/definitions/worktree" }
    },

    "header_git_dirty": { "type": "boolean", "default": false },
    "header_git_ahead": { "type": "integer", "default": 0 },
    "header_git_behind": { "type": "integer", "default": 0 },
    "header_git_merged": { "type": "boolean", "default": false },
    "header_git_has_conflicts": { "type": "boolean", "default": false },
    "header_git_additions": { "type": "integer", "default": 0 },
    "header_git_deletions": { "type": "integer", "default": 0 }
  }
}
```
