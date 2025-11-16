# Data Model: Enhanced Project Selection

**Branch**: `078-eww-preview-improvement` | **Date**: 2025-11-16

## Overview

This document defines the data structures for enhanced project selection in the Eww preview dialog. Models are organized by layer: storage (JSON files), daemon (Python Pydantic), and UI (Eww JSON).

---

## 1. Storage Layer (JSON Files)

### ProjectFile Schema

**Location**: `~/.config/i3/projects/{name}.json`

```json
{
  "name": "string",           // Project identifier (e.g., "078-eww-preview-improvement")
  "display_name": "string",   // Human-readable name (e.g., "eww preview improvement")
  "directory": "string",      // Absolute path to project directory
  "icon": "string",           // Emoji icon (e.g., "🌿")
  "scoped_classes": ["string"], // Window classes scoped to this project
  "created_at": "ISO8601",    // Creation timestamp
  "updated_at": "ISO8601",    // Last update timestamp
  "worktree": {               // Optional: Present only for git worktrees
    "branch": "string",       // Git branch name
    "commit_hash": "string",  // Short commit hash (8 chars)
    "is_clean": "boolean",    // No uncommitted changes
    "has_untracked": "boolean", // Has untracked files
    "ahead_count": "integer", // Commits ahead of remote
    "behind_count": "integer", // Commits behind remote
    "worktree_path": "string", // Worktree directory path
    "repository_path": "string", // Parent repository path (e.g., "/etc/nixos")
    "last_modified": "ISO8601" // Last git activity timestamp
  }
}
```

**Examples**:

Root project:
```json
{
  "name": "nixos",
  "display_name": "NixOS",
  "directory": "/etc/nixos",
  "icon": "❄️",
  "created_at": "2025-10-20T10:19:00Z",
  "updated_at": "2025-10-25T13:42:00Z"
}
```

Worktree project:
```json
{
  "name": "078-eww-preview-improvement",
  "display_name": "eww preview improvement",
  "directory": "/home/vpittamp/nixos-078-eww-preview-improvement",
  "icon": "🌿",
  "scoped_classes": ["Ghostty", "code", "yazi", "lazygit"],
  "created_at": "2025-11-16T17:03:24.481Z",
  "updated_at": "2025-11-16T17:03:24.482Z",
  "worktree": {
    "branch": "078-eww-preview-improvement",
    "commit_hash": "371a109f",
    "is_clean": true,
    "has_untracked": false,
    "ahead_count": 0,
    "behind_count": 0,
    "worktree_path": "/home/vpittamp/nixos-078-eww-preview-improvement",
    "repository_path": "/etc/nixos",
    "last_modified": "2025-11-16T11:45:03-05:00"
  }
}
```

---

## 2. Daemon Layer (Python Pydantic Models)

### ProjectMetadata

**Purpose**: In-memory representation of a project with computed fields.

```python
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

class WorktreeMetadata(BaseModel):
    branch: str
    commit_hash: str
    is_clean: bool
    has_untracked: bool
    ahead_count: int
    behind_count: int
    worktree_path: str
    repository_path: str
    last_modified: datetime

class ProjectMetadata(BaseModel):
    name: str
    display_name: str
    directory: str
    icon: str
    scoped_classes: List[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
    worktree: Optional[WorktreeMetadata] = None

    # Computed fields (not stored in JSON)
    is_worktree: bool = False
    parent_project_name: Optional[str] = None
    directory_exists: bool = True
    relative_time: str = "unknown"

    @property
    def effective_last_modified(self) -> datetime:
        """Get the most recent activity timestamp."""
        if self.worktree and self.worktree.last_modified:
            return self.worktree.last_modified
        return self.updated_at
```

### ProjectListItem

**Purpose**: Filtered project with match scoring for UI display.

```python
class MatchPosition(BaseModel):
    start: int
    end: int

class ProjectListItem(BaseModel):
    """Single project in filtered list with match metadata."""
    name: str
    display_name: str
    icon: str
    is_worktree: bool
    parent_project_name: Optional[str]
    directory_exists: bool
    relative_time: str

    # Git status (only for worktrees)
    git_status: Optional[dict] = None  # {is_clean, ahead_count, behind_count}

    # Match scoring
    match_score: int = 0
    match_positions: List[MatchPosition] = Field(default_factory=list)

    # Selection state
    selected: bool = False

    class Config:
        # Allow serialization for JSON
        json_encoders = {
            MatchPosition: lambda v: {"start": v.start, "end": v.end}
        }
```

### FilterState

**Purpose**: Track filter input and selection state.

```python
class FilterState(BaseModel):
    accumulated_chars: str = ""
    selected_index: int = 0
    user_navigated: bool = False  # True if user used arrow keys
    projects: List[ProjectListItem] = Field(default_factory=list)

    def reset(self):
        """Reset to initial state."""
        self.accumulated_chars = ""
        self.selected_index = 0
        self.user_navigated = False
        self.projects = []

    def add_char(self, char: str):
        """Add character to filter."""
        self.accumulated_chars += char
        if not self.user_navigated:
            self.selected_index = 0  # Auto-select best match

    def remove_char(self):
        """Remove last character from filter."""
        if self.accumulated_chars:
            self.accumulated_chars = self.accumulated_chars[:-1]
        if not self.user_navigated:
            self.selected_index = 0

    def navigate_up(self):
        """Move selection up with wrap-around."""
        if not self.projects:
            return
        self.user_navigated = True
        self.selected_index = (self.selected_index - 1) % len(self.projects)

    def navigate_down(self):
        """Move selection down with wrap-around."""
        if not self.projects:
            return
        self.user_navigated = True
        self.selected_index = (self.selected_index + 1) % len(self.projects)

    def get_selected_project(self) -> Optional[ProjectListItem]:
        """Get currently selected project."""
        if not self.projects or self.selected_index >= len(self.projects):
            return None
        return self.projects[self.selected_index]

    def update_projects(self, projects: List[ProjectListItem]):
        """Update project list, maintaining selection if possible."""
        self.projects = projects
        # Clamp selection index
        if self.selected_index >= len(projects):
            self.selected_index = max(0, len(projects) - 1)
        # Update selected flags
        for i, project in enumerate(self.projects):
            project.selected = (i == self.selected_index)
```

### ScoredMatch

**Purpose**: Result of fuzzy matching algorithm.

```python
class ScoredMatch(BaseModel):
    project: ProjectMetadata
    score: int
    match_positions: List[MatchPosition]

    @property
    def to_list_item(self) -> ProjectListItem:
        """Convert to ProjectListItem for UI display."""
        git_status = None
        if self.project.worktree:
            git_status = {
                "is_clean": self.project.worktree.is_clean,
                "ahead_count": self.project.worktree.ahead_count,
                "behind_count": self.project.worktree.behind_count
            }

        return ProjectListItem(
            name=self.project.name,
            display_name=self.project.display_name,
            icon=self.project.icon,
            is_worktree=self.project.is_worktree,
            parent_project_name=self.project.parent_project_name,
            directory_exists=self.project.directory_exists,
            relative_time=self.project.relative_time,
            git_status=git_status,
            match_score=self.score,
            match_positions=self.match_positions,
            selected=False
        )
```

---

## 3. UI Layer (Eww JSON Data)

### ProjectPreviewData

**Purpose**: JSON payload for Eww widget rendering.

```json
{
  "type": "project_list",
  "accumulated_chars": "string",
  "selected_index": 0,
  "total_count": 8,
  "projects": [
    {
      "name": "nixos",
      "display_name": "NixOS",
      "icon": "❄️",
      "is_worktree": false,
      "parent_project_name": null,
      "directory_exists": true,
      "relative_time": "3d ago",
      "git_status": null,
      "match_score": 500,
      "match_positions": [{"start": 0, "end": 3}],
      "selected": true
    },
    {
      "name": "078-eww-preview-improvement",
      "display_name": "eww preview improvement",
      "icon": "🌿",
      "is_worktree": true,
      "parent_project_name": "nixos",
      "directory_exists": true,
      "relative_time": "2h ago",
      "git_status": {
        "is_clean": true,
        "ahead_count": 0,
        "behind_count": 0
      },
      "match_score": 300,
      "match_positions": [],
      "selected": false
    }
  ]
}
```

### Eww Variable Binding

```bash
# Update Eww variable from daemon
eww update workspace_preview_data='{"type":"project_list","accumulated_chars":"nix",...}'
```

### Widget Type Detection

```yuck
;; Existing types
(box :visible {workspace_preview_data.type == "all_windows"} ...)
(box :visible {workspace_preview_data.type == "project"} ...)

;; New type for project list
(box :visible {workspace_preview_data.type == "project_list"} ...)
```

---

## 4. IPC Event Schema

### ProjectModeEvent

**Purpose**: Event payload broadcast from i3pm daemon to workspace-preview-daemon.

```json
{
  "type": "project_mode",
  "payload": {
    "event_type": "enter | char | nav | execute | cancel",
    "accumulated_chars": "string",
    "selected_index": 0,
    "projects": [/* ProjectListItem[] */]
  }
}
```

### Event Types

| Event Type | Trigger | Payload Contents | UI Action |
|------------|---------|------------------|-----------|
| `enter` | User types ":" | All projects (sorted by recency) | Show project list |
| `char` | User types letter/digit | Filtered projects (sorted by score) | Update filter and list |
| `nav` | User presses Up/Down | Updated selected_index | Move highlight |
| `execute` | User presses Enter | Selected project name | Switch project, close dialog |
| `cancel` | User presses Escape | Empty | Close dialog without action |
| `backspace` | User presses Backspace | Updated chars (or empty if colon removed) | Update filter or exit mode |

---

## 5. Validation Rules

### ProjectMetadata Validation

1. **name**: Required, alphanumeric with hyphens, max 100 chars
2. **directory**: Required, absolute path, must start with "/"
3. **icon**: Required, single emoji character (1-4 unicode codepoints)
4. **worktree.repository_path**: If present, must be absolute path
5. **worktree.ahead_count/behind_count**: Non-negative integers

### FilterState Validation

1. **accumulated_chars**: Lowercase alphanumeric and hyphens only
2. **selected_index**: Must be within bounds of projects list
3. **projects**: List may be empty (no matches)

### Match Scoring Rules

1. **Exact match**: `score = 1000` (e.g., "nixos" matches "nixos")
2. **Prefix match**: `score = 500 + (len(query) / len(name)) * 100`
3. **Word-boundary match**: `score = 300 + 50 per consecutive word`
4. **Substring match**: `score = 100 - position_penalty`
5. **No match**: `score = 0` (excluded from results)

### Character Filtering Rules

1. Valid characters: `a-z`, `0-9`, `-`
2. Colon (`:`) activates project mode (not added to filter)
3. Other characters: Ignored (not added to filter)
4. Case: Always lowercase

---

## 6. State Transitions

### Project Mode State Machine

```
[Workspace Mode]
       |
       | User types ":"
       v
[Project Mode: Empty Filter]
       |
       | User types letter/digit
       v
[Project Mode: Filtering]
       |
       +---> User types more chars --> stay in Filtering
       |
       +---> User presses Up/Down --> update selection
       |
       +---> User presses Enter --> [Execute Switch]
       |
       +---> User presses Escape --> [Cancel to Workspace Mode]
       |
       +---> User presses Backspace (with chars) --> remove char
       |
       +---> User presses Backspace (no chars) --> [Exit to Workspace Mode]
```

### Selection State Transitions

```
Initial: selected_index = 0, user_navigated = false

On char input:
  - Filter projects
  - If !user_navigated: reset selected_index to 0
  - Clamp selected_index to new list bounds

On navigate_down:
  - Set user_navigated = true
  - Increment selected_index (wrap at end)

On navigate_up:
  - Set user_navigated = true
  - Decrement selected_index (wrap at start)

On execute:
  - Get project at selected_index
  - Perform project switch
  - Reset state
```

---

## 7. Entity Relationships

```
ProjectFile (Storage)
    |
    |-- 1:1 --> ProjectMetadata (Daemon)
                    |
                    |-- 1:1 --> ProjectListItem (UI)
                    |
                    |-- 0:1 --> WorktreeMetadata
                                    |
                                    +-- repository_path --> [Parent ProjectFile]

FilterState (Daemon)
    |
    +-- accumulated_chars: string
    |
    +-- selected_index: int
    |
    +-- projects: List[ProjectListItem]

IPC Event (Transport)
    |
    +-- event_type: enum
    |
    +-- payload: FilterState snapshot
```

---

## 8. Performance Considerations

### Memory Usage

- ProjectMetadata: ~500 bytes per project
- ProjectListItem: ~300 bytes per project
- FilterState with 100 projects: ~30KB
- IPC event payload: ~30KB (uncompressed JSON)

### Query Performance

- Load all projects: O(n) where n = number of project files
- Fuzzy match scoring: O(n * m) where m = query length
- Sort by score: O(n log n)
- Selection navigation: O(1)
- JSON serialization: O(n)

### Caching Strategy

- Project files: Cached in memory, refreshed on file change
- Filter results: Computed fresh on each char input (fast enough)
- Selection state: Maintained in FilterState object
- No persistent caching across daemon restarts

---

## 9. Migration Notes

### Backward Compatibility

- Existing project JSON files are fully compatible (no schema changes)
- New `is_worktree` and `parent_project_name` are computed fields, not stored
- Old workspace-preview-daemon continues to work (ignores new event fields)
- Gradual rollout: Enable project list mode via configuration flag initially

### Data Migration

No data migration required. All enhancements are additive:
1. Existing project files remain unchanged
2. New computed fields derived from existing data
3. New IPC events extend existing protocol
4. New Eww widget type added alongside existing types
