# Data Model: Enhanced Worktree User Experience

**Feature**: 109-enhance-worktree-user-experience
**Date**: 2025-12-02

## Entities

### Worktree (Enhanced)

Represents a git worktree with comprehensive status information for UI display.

**Source**: Extends existing `home-modules/tools/i3_project_manager/models/worktree.py`

```python
from pydantic import BaseModel, Field, computed_field
from typing import Optional, Literal
from datetime import datetime

class WorktreeStatus(BaseModel):
    """Git status information for a worktree."""
    is_dirty: bool = False
    staged_count: int = 0
    modified_count: int = 0
    untracked_count: int = 0
    ahead: int = 0
    behind: int = 0
    is_merged: bool = False
    is_stale: bool = False  # No commits in 30+ days
    has_conflicts: bool = False
    last_commit_timestamp: Optional[datetime] = None
    last_commit_message: Optional[str] = None  # Truncated to 50 chars

class Worktree(BaseModel):
    """Enhanced worktree model for UI display."""
    # Identity
    qualified_name: str  # account/repo:branch format
    branch: str
    path: str  # Absolute filesystem path

    # Hierarchy
    parent_repository: str  # Parent repo name
    is_main: bool = False  # Is this the main/master worktree?

    # Status
    status: WorktreeStatus
    is_active: bool = False  # Currently active project?

    # Metadata (Feature 098)
    branch_number: Optional[str] = None  # e.g., "109"
    branch_type: Optional[str] = None  # e.g., "feature", "fix"

    @computed_field
    @property
    def display_name(self) -> str:
        """Format: '109 - Branch Description' or just branch name."""
        if self.branch_number:
            # Extract description after number
            parts = self.branch.split('-', 2)
            if len(parts) > 1:
                desc = parts[-1].replace('-', ' ').title()
                return f"{self.branch_number} - {desc}"
        return self.branch

    @computed_field
    @property
    def dirty_indicator(self) -> str:
        """Visual indicator for dirty state."""
        return "●" if self.status.is_dirty else ""

    @computed_field
    @property
    def sync_indicator(self) -> str:
        """Visual indicator for sync state."""
        parts = []
        if self.status.ahead > 0:
            parts.append(f"↑{self.status.ahead}")
        if self.status.behind > 0:
            parts.append(f"↓{self.status.behind}")
        return " ".join(parts)

    @computed_field
    @property
    def status_tooltip(self) -> str:
        """Multi-line tooltip with status breakdown."""
        lines = []
        if self.status.is_dirty:
            lines.append(f"Staged: {self.status.staged_count}")
            lines.append(f"Modified: {self.status.modified_count}")
            lines.append(f"Untracked: {self.status.untracked_count}")
        if self.status.ahead or self.status.behind:
            lines.append(f"Ahead: {self.status.ahead}, Behind: {self.status.behind}")
        if self.status.has_conflicts:
            lines.append("⚠ Merge conflicts present")
        if self.status.is_stale:
            lines.append("💤 No recent activity")
        if self.status.is_merged:
            lines.append("✓ Merged to main")
        if self.status.last_commit_message:
            lines.append(f"Last: {self.status.last_commit_message}")
        return "\n".join(lines) if lines else "Clean"
```

### LazyGitContext

Configuration for launching lazygit with the correct context.

```python
from pydantic import BaseModel, Field
from typing import Optional, Literal

LazyGitView = Literal["status", "branch", "log", "stash"]

class LazyGitContext(BaseModel):
    """Context for launching lazygit in a specific state."""
    # Required
    working_directory: str  # Absolute path to worktree

    # View selection
    initial_view: LazyGitView = "status"

    # Optional filtering
    filter_path: Optional[str] = None  # --filter argument

    def to_command_args(self) -> list[str]:
        """Generate lazygit CLI arguments."""
        args = ["lazygit", "--path", self.working_directory]
        if self.filter_path:
            args.extend(["--filter", self.filter_path])
        args.append(self.initial_view)
        return args

    def to_command_string(self) -> str:
        """Generate lazygit command string for shell execution."""
        return " ".join(self.to_command_args())
```

### WorktreeAction

Enum and handler for worktree operations.

```python
from enum import Enum
from pydantic import BaseModel
from typing import Optional

class WorktreeActionType(str, Enum):
    """Available actions for a worktree."""
    SWITCH = "switch"
    CREATE = "create"
    DELETE = "delete"
    OPEN_TERMINAL = "open-terminal"
    OPEN_EDITOR = "open-editor"
    OPEN_LAZYGIT = "open-lazygit"
    OPEN_FILE_MANAGER = "open-file-manager"
    COPY_PATH = "copy-path"
    REFRESH = "refresh"

class WorktreeAction(BaseModel):
    """Request to perform an action on a worktree."""
    action_type: WorktreeActionType
    worktree_qualified_name: str  # Target worktree

    # Action-specific parameters
    lazygit_view: Optional[str] = None  # For OPEN_LAZYGIT
    branch_name: Optional[str] = None  # For CREATE
    force: bool = False  # For DELETE with uncommitted changes

class WorktreeActionResult(BaseModel):
    """Result of a worktree action."""
    success: bool
    action_type: WorktreeActionType
    worktree_qualified_name: str
    message: Optional[str] = None
    error: Optional[str] = None
```

### KeyboardShortcut

Mapping of keyboard shortcuts for focus mode.

```python
from pydantic import BaseModel
from typing import Dict

class WorktreeKeyboardShortcuts(BaseModel):
    """Keyboard shortcuts for worktree operations in focus mode."""
    # Navigation
    navigate_down: str = "j"
    navigate_up: str = "k"
    select: str = "Return"

    # Actions
    create: str = "c"
    delete: str = "d"
    git: str = "g"  # Open lazygit
    refresh: str = "r"
    terminal: str = "t"
    editor: str = "e"

    # View
    toggle_expand: str = "space"

    # Exit
    exit_focus: str = "Escape"

    def to_eww_handlers(self) -> Dict[str, str]:
        """Generate Eww keybinding handler map."""
        return {
            self.navigate_down: "worktree-nav-down",
            self.navigate_up: "worktree-nav-up",
            self.select: "worktree-select",
            self.create: "worktree-create",
            self.delete: "worktree-delete",
            self.git: "worktree-lazygit",
            self.refresh: "worktree-refresh",
            self.terminal: "worktree-terminal",
            self.editor: "worktree-editor",
            self.toggle_expand: "worktree-toggle-expand",
            self.exit_focus: "worktree-exit-focus",
        }
```

## Entity Relationships

```
Repository (1) ──────────────────> (*) Worktree
    │                                    │
    │ has parent                         │ has status
    │                                    │
    └───────────────────────────────────>WorktreeStatus

WorktreeAction ────> Worktree (by qualified_name)
    │
    │ produces
    │
    └───────> WorktreeActionResult

LazyGitContext ────> Worktree (references path)
```

## State Transitions

### Worktree Lifecycle

```
                    ┌─────────────────┐
                    │   Not Created   │
                    └────────┬────────┘
                             │ create
                             ▼
                    ┌─────────────────┐
           ┌───────>│     Active      │<───────┐
           │        └────────┬────────┘        │
           │                 │                 │
    switch │                 │ switch          │ switch
           │                 ▼                 │
           │        ┌─────────────────┐        │
           └────────│    Inactive     │────────┘
                    └────────┬────────┘
                             │ 30+ days inactive
                             ▼
                    ┌─────────────────┐
                    │      Stale      │
                    └────────┬────────┘
                             │ merge complete
                             ▼
                    ┌─────────────────┐
                    │     Merged      │
                    └────────┬────────┘
                             │ delete
                             ▼
                    ┌─────────────────┐
                    │    Deleted      │
                    └─────────────────┘
```

### Git Status States

```
                    ┌─────────────────┐
                    │      Clean      │
                    └────────┬────────┘
                             │ modify files
                             ▼
                    ┌─────────────────┐
                    │      Dirty      │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │  Staged  │     │ Modified │     │Untracked │
    └──────────┘     └──────────┘     └──────────┘
           │                 │                 │
           └─────────────────┼─────────────────┘
                             │ commit + push
                             ▼
                    ┌─────────────────┐
                    │    Synced       │
                    └─────────────────┘
```

## Validation Rules

### Worktree Creation

| Field | Rule |
|-------|------|
| branch | Must be valid git branch name (no spaces, valid chars) |
| branch | Must not already exist as worktree for this repository |
| path | Parent directory must exist and be writable |
| path | Must not conflict with existing directory |

### Worktree Deletion

| Condition | Behavior |
|-----------|----------|
| Clean worktree | Single confirmation required |
| Dirty worktree | Enhanced warning with file counts |
| Has conflicts | Block deletion, suggest resolution |
| Is active | Switch to another worktree first |

### LazyGitContext

| Field | Rule |
|-------|------|
| working_directory | Must exist and be a git worktree |
| initial_view | Must be one of: status, branch, log, stash |
| filter_path | If provided, must be relative to working_directory |

## Data Volume Assumptions

| Entity | Expected Volume | Impact |
|--------|-----------------|--------|
| Repositories | 3-5 per user | Minimal |
| Worktrees per repo | 10-20 | Scrollable list needed |
| Total worktrees | 30-100 | Memory efficient models |
| Status refresh rate | Every 5s polling + on-demand | Optimize git operations |
| Actions per minute | 5-20 | Low volume, no throttling needed |
