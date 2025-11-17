# Data Model: Preview Pane User Experience

**Feature Branch**: `079-preview-pane-user-experience`
**Date**: 2025-11-16

## Overview

This document defines the data models for enhanced preview pane navigation, worktree hierarchy display, and cross-component integration.

## Entities

### 1. ProjectListItem (Enhanced)

Represents a project in the filterable list with worktree metadata.

**Module**: `home-modules/desktop/i3-project-event-daemon/models/project_filter.py`

```python
from pydantic import BaseModel, Field, validator
from typing import Optional, List
from datetime import datetime

class GitStatus(BaseModel):
    """Git repository status."""
    dirty: bool = False
    ahead: int = 0
    behind: int = 0
    branch: str = ""

class ProjectListItem(BaseModel):
    """Enhanced project item with worktree metadata."""

    # Core identification
    name: str                                    # Internal name (e.g., "nixos-079-preview-pane")
    display_name: str                            # Human-readable name (e.g., "Preview Pane UX")
    icon: str = ""                               # Icon character or path

    # Branch metadata (NEW)
    branch_number: Optional[str] = None          # Extracted prefix (e.g., "079")
    branch_type: str = "main"                    # "feature", "main", "hotfix", "release"
    full_branch_name: str = ""                   # Git branch (e.g., "079-preview-pane-user-experience")

    # Worktree metadata
    is_worktree: bool = False
    parent_project_name: Optional[str] = None    # Parent repo name (e.g., "nixos")
    git_status: Optional[GitStatus] = None

    # Filtering metadata
    match_score: int = 0
    match_positions: List[int] = Field(default_factory=list)

    # Display metadata
    relative_time: str = ""                      # "2h ago", "3d ago"
    path: str = ""                               # Full path to project directory

    @validator('branch_number', pre=True, always=True)
    def extract_branch_number(cls, v, values):
        """Extract numeric prefix from branch name."""
        if v is not None:
            return v
        full_branch = values.get('full_branch_name', '')
        if full_branch:
            import re
            match = re.match(r'^(\d+)-', full_branch)
            if match:
                return match.group(1)
        return None

    @validator('branch_type', pre=True, always=True)
    def classify_branch_type(cls, v, values):
        """Classify branch by naming pattern."""
        if v != "main":  # Already set
            return v
        full_branch = values.get('full_branch_name', '')
        if re.match(r'^\d+-', full_branch):
            return "feature"
        elif full_branch.startswith("hotfix-"):
            return "hotfix"
        elif full_branch.startswith("release-"):
            return "release"
        return "main"

    def formatted_display_name(self) -> str:
        """Return formatted name with branch number if present."""
        if self.branch_number:
            return f"{self.branch_number} - {self.display_name}"
        return self.display_name
```

**Relationships**:
- Child of `FilterState` (via projects list)
- References `GitStatus` for repository state
- Grouped by `parent_project_name` for hierarchy display

**Validation Rules**:
- `name` must not contain spaces (internal identifier)
- `branch_number` must be numeric string if present
- `branch_type` must be one of: "feature", "main", "hotfix", "release"

---

### 2. FilterState (Enhanced)

Tracks current filter input and navigation state for project selection.

```python
class FilterState(BaseModel):
    """State for project filtering and navigation."""

    # Input tracking
    accumulated_chars: str = ""                  # Current filter text (e.g., ":79")

    # Navigation state
    selected_index: int = 0                      # Currently highlighted project
    user_navigated: bool = False                 # True if user used arrow keys

    # Filtered results
    projects: List[ProjectListItem] = Field(default_factory=list)
    total_unfiltered_count: int = 0              # Total projects before filtering

    # Hierarchy state (NEW)
    grouped_by_parent: bool = False              # Whether to display as hierarchy
    expanded_parents: List[str] = Field(default_factory=list)  # Expanded parent groups

    def navigate_up(self) -> None:
        """Move selection up with circular wrapping."""
        if not self.projects:
            return
        self.user_navigated = True
        self.selected_index = (self.selected_index - 1) % len(self.projects)

    def navigate_down(self) -> None:
        """Move selection down with circular wrapping."""
        if not self.projects:
            return
        self.user_navigated = True
        self.selected_index = (self.selected_index + 1) % len(self.projects)

    def get_selected_project(self) -> Optional[ProjectListItem]:
        """Return currently selected project."""
        if 0 <= self.selected_index < len(self.projects):
            return self.projects[self.selected_index]
        return None

    def filter_by_prefix(self, prefix: str) -> None:
        """Filter projects by branch number prefix."""
        if not prefix:
            return

        # Prioritize exact prefix matches
        for i, project in enumerate(self.projects):
            if project.branch_number and project.branch_number.startswith(prefix):
                project.match_score = 1000  # Highest priority
            elif prefix in (project.branch_number or ""):
                project.match_score = 500
            elif prefix in project.display_name.lower():
                project.match_score = 100

        # Re-sort by match score
        self.projects.sort(key=lambda p: p.match_score, reverse=True)

        # Reset selection if it exceeds new bounds
        if self.selected_index >= len(self.projects):
            self.selected_index = 0

    def group_by_parent(self) -> List[dict]:
        """Group projects by parent for hierarchy display."""
        groups = {}
        root_projects = []

        for project in self.projects:
            if project.is_worktree and project.parent_project_name:
                if project.parent_project_name not in groups:
                    groups[project.parent_project_name] = []
                groups[project.parent_project_name].append(project)
            else:
                root_projects.append(project)

        # Build hierarchical structure
        result = []
        for root in root_projects:
            result.append({
                "type": "root",
                "project": root,
                "children": groups.get(root.name, [])
            })

        return result
```

**State Transitions**:
- Initial: Empty filter, no projects
- Loading: Accumulated chars set, projects populated
- Navigating: User arrow keys change selected_index
- Filtering: New chars trigger match_score recalculation
- Exiting: Backspace removes chars, empty filter triggers mode exit

---

### 3. WorktreeEnvironment (NEW)

Environment variables injected into launched applications.

```python
class WorktreeEnvironment(BaseModel):
    """Environment variables for worktree context."""

    # Core project info (existing)
    app_id: str                                  # I3PM_APP_ID
    app_name: str                                # I3PM_APP_NAME
    scope: str                                   # I3PM_SCOPE ("scoped"/"global")
    project_name: str                            # I3PM_PROJECT_NAME
    project_dir: str                             # I3PM_PROJECT_DIR
    target_workspace: int                        # I3PM_TARGET_WORKSPACE

    # Worktree metadata (NEW)
    is_worktree: bool = False                    # I3PM_IS_WORKTREE
    parent_project: str = ""                     # I3PM_PARENT_PROJECT
    branch_type: str = "main"                    # I3PM_BRANCH_TYPE

    def to_env_dict(self) -> dict:
        """Convert to environment variable dictionary."""
        return {
            "I3PM_APP_ID": self.app_id,
            "I3PM_APP_NAME": self.app_name,
            "I3PM_SCOPE": self.scope,
            "I3PM_PROJECT_NAME": self.project_name,
            "I3PM_PROJECT_DIR": self.project_dir,
            "I3PM_TARGET_WORKSPACE": str(self.target_workspace),
            "I3PM_IS_WORKTREE": "true" if self.is_worktree else "false",
            "I3PM_PARENT_PROJECT": self.parent_project,
            "I3PM_BRANCH_TYPE": self.branch_type,
        }
```

---

### 4. NotificationContext (NEW)

Metadata for Claude Code notifications with source window tracking.

```python
class NotificationContext(BaseModel):
    """Context for notification with source window tracking."""

    # Notification content
    title: str
    body: str
    icon: str = "dialog-information"
    urgency: str = "normal"                      # "low", "normal", "critical"

    # Source window tracking (NEW)
    tmux_session: Optional[str] = None           # e.g., "nixos"
    tmux_window: Optional[int] = None            # e.g., 0
    sway_window_id: Optional[int] = None         # Sway con_id

    # Project context
    project_name: Optional[str] = None           # Which project generated notification

    def window_identifier(self) -> str:
        """Return tmux session:window identifier."""
        if self.tmux_session is not None and self.tmux_window is not None:
            return f"{self.tmux_session}:{self.tmux_window}"
        return ""

    def to_notify_send_args(self) -> List[str]:
        """Generate notify-send command arguments with actions."""
        args = [
            "notify-send",
            "-w",  # Wait for action
            "-i", self.icon,
            "-u", self.urgency,
            "-A", "focus=Return to Window",
            "-A", "dismiss=Dismiss",
        ]

        # Add window identifier to body
        if self.window_identifier():
            body_with_context = f"{self.body}\n\nSource: {self.window_identifier()}"
        else:
            body_with_context = self.body

        args.extend([self.title, body_with_context])
        return args
```

---

### 5. TopBarProjectData (NEW)

Data structure for top bar project label display.

```python
class TopBarProjectData(BaseModel):
    """Active project data for top bar display."""

    # Core fields
    project: str                                 # Project name
    active: bool = False                         # Whether project is active

    # Enhanced display (NEW)
    branch_number: Optional[str] = None          # e.g., "079"
    icon: str = ""                              # Folder or branch icon
    is_worktree: bool = False
    git_status: Optional[GitStatus] = None

    def formatted_label(self) -> str:
        """Return formatted label for display."""
        if self.branch_number:
            return f"{self.branch_number} - {self.project}"
        return self.project

    def icon_path(self) -> str:
        """Return appropriate icon for project type."""
        if not self.active:
            return ""  # Global mode
        if self.is_worktree:
            return ""  # Git branch icon
        return ""  # Folder icon
```

---

### 6. WorktreeListOutput (Deno CLI)

TypeScript interface for `i3pm worktree list` command output.

```typescript
// home-modules/tools/i3pm/src/models/worktree.ts

import { z } from "zod";

export const GitStatusSchema = z.object({
  dirty: z.boolean(),
  ahead: z.number(),
  behind: z.number(),
  branch: z.string(),
});

export const WorktreeItemSchema = z.object({
  branch: z.string(),
  path: z.string(),
  parent_repo: z.string(),
  git_status: GitStatusSchema,
  created_at: z.string().optional(),
});

export const WorktreeListOutputSchema = z.array(WorktreeItemSchema);

export type GitStatus = z.infer<typeof GitStatusSchema>;
export type WorktreeItem = z.infer<typeof WorktreeItemSchema>;
export type WorktreeListOutput = z.infer<typeof WorktreeListOutputSchema>;
```

---

## JSON Schemas

### Project JSON File (Enhanced)

**Location**: `~/.config/i3/projects/<project-name>.json`

```json
{
  "name": "nixos-079-preview-pane",
  "display_name": "Preview Pane UX",
  "path": "/home/vpittamp/nixos-079-preview-pane-user-experience",
  "icon": "",
  "created_at": "2025-11-16T10:30:00Z",
  "last_accessed": "2025-11-16T14:00:00Z",
  "worktree": {
    "is_worktree": true,
    "parent_repo": "nixos",
    "branch": "079-preview-pane-user-experience",
    "git_status": {
      "dirty": false,
      "ahead": 2,
      "behind": 0
    }
  }
}
```

### Eww Project Preview Data

**Eww Variable**: `workspace_preview_data`

```json
{
  "visible": true,
  "type": "project_list",
  "accumulated_chars": ":79",
  "selected_index": 0,
  "total_count": 3,
  "grouped": true,
  "projects": [
    {
      "name": "nixos-079-preview-pane",
      "display_name": "Preview Pane UX",
      "branch_number": "079",
      "branch_type": "feature",
      "icon": "",
      "is_worktree": true,
      "parent_project_name": "nixos",
      "selected": true,
      "git_status": {
        "dirty": false,
        "ahead": 2,
        "behind": 0
      },
      "relative_time": "2h ago"
    }
  ],
  "empty": false
}
```

---

## State Machine: Project Selection Mode

```
┌─────────────────┐
│  Workspace Mode │  (Initial state - workspace preview visible)
└────────┬────────┘
         │ User types ":"
         ▼
┌─────────────────┐
│  Project Mode   │  (Project list visible, filter active)
└────────┬────────┘
         │
    ┌────┴─────────────┬──────────────┐
    │                  │              │
    ▼ Arrow Up/Down    ▼ Digit Input  ▼ Backspace
┌───────────┐    ┌───────────┐   ┌───────────┐
│ Navigate  │    │  Filter   │   │  Delete   │
│ Selection │    │  Projects │   │   Char    │
└─────┬─────┘    └─────┬─────┘   └─────┬─────┘
      │                │               │
      └────────┬───────┘               │
               │                       │
               ▼                       │ (if empty)
         [Stay in Project Mode]        ▼
               │               ┌───────────────┐
               │               │ Exit to       │
               │               │ Workspace Mode│
               │               └───────────────┘
               │ User presses Enter
               ▼
         ┌───────────┐
         │  Switch   │
         │  Project  │
         └─────┬─────┘
               │
               ▼
         [Workspace Mode - New Project]
```

---

## Migration Notes

### Backward Compatibility

- Existing project JSON files without `worktree` field treated as root projects
- Missing `branch_number` field computed from `worktree.branch` on load
- Old FilterState without `grouped_by_parent` defaults to flat list

### Data Transformation

```python
def upgrade_project_data(old_data: dict) -> dict:
    """Upgrade old project JSON to new format."""
    if "worktree" not in old_data:
        old_data["worktree"] = {
            "is_worktree": False,
            "parent_repo": "",
            "branch": "",
            "git_status": {
                "dirty": False,
                "ahead": 0,
                "behind": 0
            }
        }
    return old_data
```

---

## Entity Relationship Diagram

```
FilterState (1)
    │
    ├──── contains ────▶ ProjectListItem (many)
    │                           │
    │                           ├──── has ────▶ GitStatus (optional)
    │                           │
    │                           └──── parent ──▶ ProjectListItem (optional)
    │
    └──── tracks ────▶ selected_index (int)

WorktreeEnvironment (1)
    │
    └──── injected into ────▶ Process Environment (many)

NotificationContext (1)
    │
    └──── references ────▶ Tmux Window (optional)

TopBarProjectData (1)
    │
    └──── displayed by ────▶ Eww Widget (1)
```

This data model supports all functional requirements while maintaining backward compatibility with existing project JSON files.
