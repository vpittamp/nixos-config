# Data Model: i3 Project Management System

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20 | **Phase**: Phase 1 Design
**Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md)

## Overview

This document defines all data entities, their relationships, validation rules, and storage formats for the unified i3 project management system (`i3pm`). All entities use Python dataclasses with type hints and JSON serialization for persistence.

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Project                                  │
│  - name: str (unique, primary key)                              │
│  - directory: Path                                              │
│  - display_name: str                                            │
│  - icon: str (emoji/unicode)                                    │
│  - scoped_classes: List[str]                                    │
│  - workspace_preferences: Dict[int, str]                        │
│  - created_at: datetime                                         │
│  - modified_at: datetime                                        │
└──┬──────────────────────────────────────────────────────────────┘
   │
   │ 1:N
   ├───────────────┬──────────────────┬──────────────────┐
   │               │                  │                  │
   ▼               ▼                  ▼                  ▼
┌─────────────┐ ┌──────────────┐  ┌─────────────┐   ┌─────────────┐
│AutoLaunchApp│ │ SavedLayout  │  │WorkspacePref│   │MarkPattern  │
│- command    │ │- name        │  │- workspace  │   │- pattern    │
│- env        │ │- workspaces  │  │- output_role│   │- scope      │
│- workspace  │ │- saved_at    │  └─────────────┘   └─────────────┘
└─────────────┘ └──┬───────────┘
                   │ 1:N
                   ▼
              ┌──────────────┐
              │WorkspaceLayout│
              │- number      │
              │- output_role │
              └──┬───────────┘
                 │ 1:N
                 ▼
              ┌──────────────┐
              │LayoutWindow  │
              │- class       │
              │- geometry    │
              │- launch_cmd  │
              └──────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    AppClassification                             │
│  (Global configuration: ~/.config/i3/app-classes.json)          │
│  - scoped_classes: List[str]                                    │
│  - global_classes: List[str]                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       TUIState                                   │
│  (Runtime state, not persisted)                                 │
│  - active_screen: str                                           │
│  - selected_project: Optional[str]                              │
│  - filter_text: str                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Entities

### 1. Project

**Purpose**: Represents a project workspace with associated applications and configurations.

**Storage**: `~/.config/i3/projects/{name}.json` (one file per project)

**Python Definition**:

```python
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional
import json

@dataclass
class Project:
    """Project configuration entity."""

    # Primary fields (required)
    name: str                           # Unique identifier (filesystem-safe)
    directory: Path                     # Project working directory

    # Display fields
    display_name: Optional[str] = None  # Human-readable name (defaults to name)
    icon: Optional[str] = None          # Unicode emoji/icon for UI

    # Application associations
    scoped_classes: List[str] = field(default_factory=list)  # Project-specific app classes

    # Workspace configuration
    workspace_preferences: Dict[int, str] = field(default_factory=dict)  # {ws_num: output_role}

    # Auto-launch configuration
    auto_launch: List["AutoLaunchApp"] = field(default_factory=list)

    # Saved layouts
    saved_layouts: List[str] = field(default_factory=list)  # Layout names

    # Metadata
    created_at: datetime = field(default_factory=datetime.now)
    modified_at: datetime = field(default_factory=datetime.now)

    def __post_init__(self):
        """Initialize derived fields."""
        # Convert string path to Path object
        if isinstance(self.directory, str):
            self.directory = Path(self.directory).expanduser()

        # Default display_name to name
        if self.display_name is None:
            self.display_name = self.name

        # Validate name (filesystem-safe)
        if not self.name.replace("-", "").replace("_", "").isalnum():
            raise ValueError(f"Project name '{self.name}' must be alphanumeric (with - or _)")

        # Validate directory exists
        if not self.directory.exists():
            raise ValueError(f"Project directory does not exist: {self.directory}")

    def to_json(self) -> dict:
        """Serialize to JSON (for file storage)."""
        data = asdict(self)
        data["directory"] = str(self.directory)
        data["created_at"] = self.created_at.isoformat()
        data["modified_at"] = self.modified_at.isoformat()

        # Serialize nested AutoLaunchApp objects
        data["auto_launch"] = [app.to_json() for app in self.auto_launch]

        return data

    @classmethod
    def from_json(cls, data: dict) -> "Project":
        """Deserialize from JSON."""
        # Parse datetime fields
        data["created_at"] = datetime.fromisoformat(data["created_at"])
        data["modified_at"] = datetime.fromisoformat(data["modified_at"])

        # Parse AutoLaunchApp objects
        data["auto_launch"] = [
            AutoLaunchApp.from_json(app) for app in data.get("auto_launch", [])
        ]

        return cls(**data)

    def save(self, config_dir: Path = Path.home() / ".config/i3/projects") -> None:
        """Save project to disk."""
        config_dir.mkdir(parents=True, exist_ok=True)
        config_file = config_dir / f"{self.name}.json"

        self.modified_at = datetime.now()

        with config_file.open("w") as f:
            json.dump(self.to_json(), f, indent=2)

    @classmethod
    def load(cls, name: str, config_dir: Path = Path.home() / ".config/i3/projects") -> "Project":
        """Load project from disk."""
        config_file = config_dir / f"{name}.json"

        if not config_file.exists():
            raise FileNotFoundError(f"Project not found: {name}")

        with config_file.open("r") as f:
            data = json.load(f)

        return cls.from_json(data)

    @classmethod
    def list_all(cls, config_dir: Path = Path.home() / ".config/i3/projects") -> List["Project"]:
        """List all projects."""
        if not config_dir.exists():
            return []

        projects = []
        for config_file in config_dir.glob("*.json"):
            try:
                projects.append(cls.load(config_file.stem, config_dir))
            except Exception as e:
                print(f"Warning: Failed to load {config_file}: {e}")

        return sorted(projects, key=lambda p: p.modified_at, reverse=True)

    def delete(self, config_dir: Path = Path.home() / ".config/i3/projects") -> None:
        """Delete project from disk."""
        config_file = config_dir / f"{self.name}.json"
        if config_file.exists():
            config_file.unlink()
```

**Validation Rules**:

| Field | Rule | Error Message |
|-------|------|---------------|
| `name` | Alphanumeric + `-_` only | "Project name must be filesystem-safe" |
| `name` | Unique across all projects | "Project name already exists" |
| `directory` | Must exist on filesystem | "Project directory does not exist" |
| `scoped_classes` | Non-empty list | "Project must have at least one scoped application" |
| `workspace_preferences` | Keys 1-10 only | "Workspace number must be 1-10" |
| `workspace_preferences` | Values: "primary", "secondary", "tertiary" | "Invalid output role" |

**Example JSON** (`~/.config/i3/projects/nixos.json`):

```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS Configuration",
  "icon": "❄️",
  "scoped_classes": ["Ghostty", "Code"],
  "workspace_preferences": {
    "1": "primary",
    "2": "secondary"
  },
  "auto_launch": [
    {
      "command": "ghostty",
      "workspace": 1,
      "env": {"PROJECT_DIR": "/etc/nixos"},
      "wait_for_mark": "project:nixos"
    },
    {
      "command": "code /etc/nixos",
      "workspace": 2,
      "env": {},
      "wait_for_mark": "project:nixos"
    }
  ],
  "saved_layouts": ["default", "debugging"],
  "created_at": "2025-10-20T10:00:00Z",
  "modified_at": "2025-10-20T14:30:00Z"
}
```

---

### 2. AutoLaunchApp

**Purpose**: Configures an application to launch automatically when switching to a project.

**Storage**: Embedded in `Project.auto_launch` list

**Python Definition**:

```python
@dataclass
class AutoLaunchApp:
    """Auto-launch application configuration."""

    # Launch configuration
    command: str                        # Shell command to execute
    workspace: Optional[int] = None     # Target workspace (1-10)

    # Environment variables (merged with PROJECT_DIR, PROJECT_NAME)
    env: Dict[str, str] = field(default_factory=dict)

    # Window matching
    wait_for_mark: Optional[str] = None  # Expected mark (e.g., "project:nixos")
    wait_timeout: float = 5.0            # Timeout in seconds

    # Launch order
    launch_delay: float = 0.5            # Delay before launch (seconds)

    def to_json(self) -> dict:
        """Serialize to JSON."""
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict) -> "AutoLaunchApp":
        """Deserialize from JSON."""
        return cls(**data)

    def get_full_env(self, project: "Project") -> Dict[str, str]:
        """Get environment with project context."""
        import os
        return {
            **os.environ,
            "PROJECT_DIR": str(project.directory),
            "PROJECT_NAME": project.name,
            **self.env
        }
```

**Validation Rules**:

| Field | Rule | Error Message |
|-------|------|---------------|
| `command` | Non-empty string | "Launch command cannot be empty" |
| `workspace` | 1-10 or None | "Workspace must be 1-10" |
| `wait_timeout` | 0.1-30.0 seconds | "Timeout must be 0.1-30.0 seconds" |

**Example**:

```python
auto_launch_ghostty = AutoLaunchApp(
    command="ghostty",
    workspace=1,
    env={"SESH_DEFAULT": "nixos"},
    wait_for_mark="project:nixos",
    launch_delay=0.5
)
```

---

### 3. SavedLayout

**Purpose**: Represents a saved project layout that can be restored later.

**Storage**: `~/.config/i3/layouts/{project_name}/{layout_name}.json`

**Python Definition**:

```python
@dataclass
class SavedLayout:
    """Saved project layout."""

    # Identification
    layout_version: str = "1.0"
    project_name: str = ""              # Associated project
    layout_name: str = "default"        # Layout name

    # Layout data
    workspaces: List["WorkspaceLayout"] = field(default_factory=list)

    # Metadata
    saved_at: datetime = field(default_factory=datetime.now)
    monitor_config: str = "single"      # "single", "dual", "triple"
    total_windows: int = 0

    def to_json(self) -> dict:
        """Serialize to JSON."""
        data = asdict(self)
        data["saved_at"] = self.saved_at.isoformat()
        data["workspaces"] = [ws.to_json() for ws in self.workspaces]
        return data

    @classmethod
    def from_json(cls, data: dict) -> "SavedLayout":
        """Deserialize from JSON."""
        data["saved_at"] = datetime.fromisoformat(data["saved_at"])
        data["workspaces"] = [
            WorkspaceLayout.from_json(ws) for ws in data.get("workspaces", [])
        ]
        return cls(**data)

    def save(self, config_dir: Path = Path.home() / ".config/i3/layouts") -> None:
        """Save layout to disk."""
        layout_dir = config_dir / self.project_name
        layout_dir.mkdir(parents=True, exist_ok=True)

        layout_file = layout_dir / f"{self.layout_name}.json"

        with layout_file.open("w") as f:
            json.dump(self.to_json(), f, indent=2)

    @classmethod
    def load(cls, project_name: str, layout_name: str,
             config_dir: Path = Path.home() / ".config/i3/layouts") -> "SavedLayout":
        """Load layout from disk."""
        layout_file = config_dir / project_name / f"{layout_name}.json"

        if not layout_file.exists():
            raise FileNotFoundError(f"Layout not found: {project_name}/{layout_name}")

        with layout_file.open("r") as f:
            data = json.load(f)

        return cls.from_json(data)

    @classmethod
    def list_for_project(cls, project_name: str,
                        config_dir: Path = Path.home() / ".config/i3/layouts") -> List[str]:
        """List all layout names for a project."""
        layout_dir = config_dir / project_name
        if not layout_dir.exists():
            return []

        return [f.stem for f in layout_dir.glob("*.json")]
```

**Validation Rules**:

| Field | Rule | Error Message |
|-------|------|---------------|
| `layout_version` | Must be "1.0" | "Unsupported layout version" |
| `project_name` | Must match existing project | "Project not found" |
| `layout_name` | Filesystem-safe string | "Layout name must be alphanumeric" |
| `workspaces` | Non-empty list | "Layout must have at least one workspace" |

---

### 4. WorkspaceLayout

**Purpose**: Represents the layout of windows on a single workspace.

**Storage**: Embedded in `SavedLayout.workspaces` list

**Python Definition**:

```python
@dataclass
class WorkspaceLayout:
    """Workspace layout configuration."""

    # Workspace identification
    number: int                         # Workspace number (1-10)
    output_role: str = "primary"        # "primary", "secondary", "tertiary"

    # Window list
    windows: List["LayoutWindow"] = field(default_factory=list)

    # Layout metadata
    split_orientation: Optional[str] = None  # "horizontal", "vertical", None

    def to_json(self) -> dict:
        """Serialize to JSON."""
        data = asdict(self)
        data["windows"] = [w.to_json() for w in self.windows]
        return data

    @classmethod
    def from_json(cls, data: dict) -> "WorkspaceLayout":
        """Deserialize from JSON."""
        data["windows"] = [
            LayoutWindow.from_json(w) for w in data.get("windows", [])
        ]
        return cls(**data)
```

**Validation Rules**:

| Field | Rule | Error Message |
|-------|------|---------------|
| `number` | 1-10 | "Workspace number must be 1-10" |
| `output_role` | "primary", "secondary", "tertiary" | "Invalid output role" |
| `split_orientation` | "horizontal", "vertical", None | "Invalid split orientation" |

---

### 5. LayoutWindow

**Purpose**: Represents a single window in a saved layout with restoration instructions.

**Storage**: Embedded in `WorkspaceLayout.windows` list

**Python Definition**:

```python
@dataclass
class LayoutWindow:
    """Window configuration in a layout."""

    # Window identification (for matching after launch)
    window_class: str                   # WM_CLASS (e.g., "Ghostty", "Code")
    window_title: Optional[str] = None  # Window title (for matching)

    # Geometry (informational, not enforced)
    geometry: Optional[Dict[str, int]] = None  # {"width": 1920, "height": 1080, "x": 0, "y": 0}

    # Layout hints
    layout_role: Optional[str] = None   # "main", "editor", "terminal", "browser"
    split_before: Optional[str] = None  # "horizontal", "vertical", None

    # Launch configuration
    launch_command: str = ""            # Command to launch this window
    launch_env: Dict[str, str] = field(default_factory=dict)

    # Expected state
    expected_marks: List[str] = field(default_factory=list)  # e.g., ["project:nixos"]

    def to_json(self) -> dict:
        """Serialize to JSON."""
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict) -> "LayoutWindow":
        """Deserialize from JSON."""
        return cls(**data)
```

**Validation Rules**:

| Field | Rule | Error Message |
|-------|------|---------------|
| `window_class` | Non-empty string | "Window class cannot be empty" |
| `launch_command` | Non-empty string | "Launch command cannot be empty" |
| `split_before` | "horizontal", "vertical", None | "Invalid split orientation" |

**Example**:

```python
window = LayoutWindow(
    window_class="Ghostty",
    window_title="nvim /etc/nixos/flake.nix",
    geometry={"width": 1920, "height": 1080, "x": 0, "y": 0},
    layout_role="terminal",
    split_before="horizontal",
    launch_command="ghostty",
    launch_env={"PROJECT_DIR": "/etc/nixos"},
    expected_marks=["project:nixos"]
)
```

---

## Global Configuration Entities

### 6. AppClassification

**Purpose**: Global configuration for application scoping (project-specific vs global).

**Storage**: `~/.config/i3/app-classes.json` (single file)

**Python Definition**:

```python
@dataclass
class AppClassification:
    """Global application classification."""

    # Default scoped classes (can be overridden per project)
    scoped_classes: List[str] = field(default_factory=list)

    # Always global (never scoped)
    global_classes: List[str] = field(default_factory=list)

    # Class detection rules
    class_patterns: Dict[str, str] = field(default_factory=dict)  # {pattern: scope}

    def to_json(self) -> dict:
        """Serialize to JSON."""
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict) -> "AppClassification":
        """Deserialize from JSON."""
        return cls(**data)

    def save(self, config_file: Path = Path.home() / ".config/i3/app-classes.json") -> None:
        """Save to disk."""
        config_file.parent.mkdir(parents=True, exist_ok=True)

        with config_file.open("w") as f:
            json.dump(self.to_json(), f, indent=2)

    @classmethod
    def load(cls, config_file: Path = Path.home() / ".config/i3/app-classes.json") -> "AppClassification":
        """Load from disk."""
        if not config_file.exists():
            return cls()  # Return default

        with config_file.open("r") as f:
            data = json.load(f)

        return cls.from_json(data)

    def is_scoped(self, window_class: str, project: Optional["Project"] = None) -> bool:
        """Determine if a window class is scoped."""
        # Check global classes first
        if window_class in self.global_classes:
            return False

        # Check project-specific scoped classes
        if project and window_class in project.scoped_classes:
            return True

        # Check default scoped classes
        if window_class in self.scoped_classes:
            return True

        # Check patterns
        for pattern, scope in self.class_patterns.items():
            if pattern in window_class.lower():
                return scope == "scoped"

        return False  # Default to global
```

**Example JSON** (`~/.config/i3/app-classes.json`):

```json
{
  "scoped_classes": ["Ghostty", "Code", "neovide"],
  "global_classes": ["firefox", "Google-chrome", "mpv", "vlc"],
  "class_patterns": {
    "pwa-": "global",
    "terminal": "scoped",
    "editor": "scoped"
  }
}
```

---

## Runtime Entities (Not Persisted)

### 7. TUIState

**Purpose**: Runtime state for the TUI application (screen navigation, selections).

**Storage**: In-memory only (not persisted)

**Python Definition**:

```python
from textual.reactive import reactive

@dataclass
class TUIState:
    """TUI application state (runtime only)."""

    # Screen navigation
    active_screen: str = "browser"       # "browser", "editor", "monitor", "layout", "wizard"
    screen_history: List[str] = field(default_factory=list)

    # Project browser state
    selected_project: Optional[str] = None
    filter_text: str = ""
    sort_by: str = "modified"            # "name", "modified", "directory"
    sort_descending: bool = True

    # Project editor state
    editing_project: Optional[str] = None
    unsaved_changes: bool = False

    # Layout manager state
    selected_layout: Optional[str] = None

    # Daemon connection
    daemon_connected: bool = False
    active_project: Optional[str] = None  # From daemon

    def push_screen(self, screen_name: str) -> None:
        """Navigate to a new screen."""
        self.screen_history.append(self.active_screen)
        self.active_screen = screen_name

    def pop_screen(self) -> Optional[str]:
        """Return to previous screen."""
        if self.screen_history:
            self.active_screen = self.screen_history.pop()
            return self.active_screen
        return None

    def reset_filters(self) -> None:
        """Reset browser filters."""
        self.filter_text = ""
        self.sort_by = "modified"
        self.sort_descending = True
```

---

## Entity Relationships

### Project ↔ SavedLayout (1:N)

- One project can have multiple saved layouts
- Each layout belongs to exactly one project
- Cascade delete: Deleting a project deletes all its layouts

**Implementation**:

```python
class Project:
    def get_layouts(self) -> List[str]:
        """Get all saved layout names for this project."""
        return SavedLayout.list_for_project(self.name)

    def delete_with_layouts(self) -> None:
        """Delete project and all its layouts."""
        # Delete layouts
        layout_dir = Path.home() / ".config/i3/layouts" / self.name
        if layout_dir.exists():
            for layout_file in layout_dir.glob("*.json"):
                layout_file.unlink()
            layout_dir.rmdir()

        # Delete project
        self.delete()
```

### Project ↔ AutoLaunchApp (1:N)

- One project can have multiple auto-launch applications
- Auto-launch configs are embedded in the project JSON (not separate entities)

### SavedLayout ↔ WorkspaceLayout (1:N)

- One layout contains multiple workspace layouts
- Workspace layouts are embedded in the layout JSON

### WorkspaceLayout ↔ LayoutWindow (1:N)

- One workspace layout contains multiple windows
- Windows are embedded in the workspace layout

---

## Validation Schema

**JSON Schema** (for config validation):

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "i3 Project Configuration",
  "type": "object",
  "required": ["name", "directory", "scoped_classes"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9_-]+$",
      "minLength": 1,
      "maxLength": 64
    },
    "directory": {
      "type": "string",
      "minLength": 1
    },
    "display_name": {
      "type": "string"
    },
    "icon": {
      "type": "string",
      "maxLength": 4
    },
    "scoped_classes": {
      "type": "array",
      "items": {"type": "string"},
      "minItems": 1,
      "uniqueItems": true
    },
    "workspace_preferences": {
      "type": "object",
      "patternProperties": {
        "^[1-9]|10$": {
          "type": "string",
          "enum": ["primary", "secondary", "tertiary"]
        }
      }
    },
    "auto_launch": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["command"],
        "properties": {
          "command": {"type": "string", "minLength": 1},
          "workspace": {"type": "integer", "minimum": 1, "maximum": 10},
          "env": {"type": "object"},
          "wait_for_mark": {"type": "string"},
          "wait_timeout": {"type": "number", "minimum": 0.1, "maximum": 30.0},
          "launch_delay": {"type": "number", "minimum": 0, "maximum": 10.0}
        }
      }
    },
    "saved_layouts": {
      "type": "array",
      "items": {"type": "string"}
    },
    "created_at": {"type": "string", "format": "date-time"},
    "modified_at": {"type": "string", "format": "date-time"}
  }
}
```

---

## Storage Layout

```
~/.config/i3/
├── projects/                   # Project configurations
│   ├── nixos.json             # Project: NixOS
│   ├── stacks.json            # Project: Stacks
│   └── personal.json          # Project: Personal
│
├── layouts/                    # Saved layouts
│   ├── nixos/
│   │   ├── default.json       # Default layout for NixOS project
│   │   ├── debugging.json     # Debugging layout
│   │   └── testing.json       # Testing layout
│   ├── stacks/
│   │   └── default.json
│   └── personal/
│       └── default.json
│
└── app-classes.json           # Global app classification

~/.cache/i3pm/                  # Runtime cache
├── project-list.txt           # Cached project names (for completions)
└── daemon-socket              # Daemon IPC socket (if used)
```

---

## Data Migration Strategy

### From Existing Format (Feature 015)

**Old format** (`~/.config/i3/projects/nixos.json`):

```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS",
  "icon": "❄️",
  "scoped_classes": ["Ghostty", "Code"]
}
```

**New format** (adds `auto_launch`, `workspace_preferences`, `saved_layouts`):

```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS",
  "icon": "❄️",
  "scoped_classes": ["Ghostty", "Code"],
  "workspace_preferences": {},
  "auto_launch": [],
  "saved_layouts": [],
  "created_at": "2025-10-20T10:00:00Z",
  "modified_at": "2025-10-20T10:00:00Z"
}
```

**Migration function**:

```python
def migrate_project_v1_to_v2(old_data: dict) -> dict:
    """Migrate project from v1 to v2 format."""
    new_data = old_data.copy()

    # Add new fields with defaults
    new_data.setdefault("workspace_preferences", {})
    new_data.setdefault("auto_launch", [])
    new_data.setdefault("saved_layouts", [])
    new_data.setdefault("created_at", datetime.now().isoformat())
    new_data.setdefault("modified_at", datetime.now().isoformat())

    return new_data
```

---

## Summary

**Total Entities**: 7 (4 persisted, 3 runtime)

**Storage Files**:
- `~/.config/i3/projects/*.json` - Project configurations
- `~/.config/i3/layouts/{project}/*.json` - Saved layouts
- `~/.config/i3/app-classes.json` - Global app classification

**Validation**:
- JSON Schema for project configs
- Python dataclass validation for runtime entities
- Filesystem validation for directories and paths

**Next Steps**:
1. Create API contracts (CLI, TUI, daemon)
2. Implement core CRUD operations in `core/project.py`
3. Implement layout save/restore in `core/layout.py`
