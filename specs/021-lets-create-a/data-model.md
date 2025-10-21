# Data Model: Dynamic Window Management System

**Feature**: 021-lets-create-a
**Date**: 2025-10-21

## Model Overview

This feature extends existing i3pm models and adds new models for window rule management and workspace configuration.

### Model Hierarchy

```
Existing Models (Reused/Enhanced)
├── Project (core/models.py) - No changes, used for scoped_classes
├── AppClassification (core/models.py) - Enhanced: class_patterns field
└── PatternRule (models/pattern.py) - Reused as-is

New Models
├── WindowRule (daemon/window_rules.py) - References PatternRule
├── WorkspaceConfig (models/workspace.py) - Workspace metadata
├── Classification (daemon/pattern_resolver.py) - Classification result
└── MonitorConfig (daemon/workspace_manager.py) - Monitor state
```

## Existing Models (Preserved)

### Project

**Location**: `home-modules/tools/i3_project_manager/core/models.py` (lines 69-277)

**Purpose**: Project configuration with directory, display name, scoped classes, and workspace preferences

**Fields** (relevant to this feature):
```python
@dataclass
class Project:
    name: str                                    # Unique identifier
    directory: Path                               # Project working directory
    display_name: Optional[str] = None            # Human-readable name
    icon: Optional[str] = None                    # Unicode emoji/icon
    scoped_classes: List[str] = field(default_factory=list)  # **INTEGRATION POINT**
    workspace_preferences: Dict[int, str] = field(default_factory=dict)  # **INTEGRATION POINT**
    # ... other fields (auto_launch, saved_layouts, metadata)
```

**Integration**:
- `scoped_classes`: Priority 1000 - Highest precedence for window classification
- `workspace_preferences`: Overrides global workspace-to-output assignments
  - Key: workspace number (1-9)
  - Value: output role ("primary", "secondary", "tertiary")

**Example JSON**:
```json
{
  "name": "nixos",
  "directory": "/etc/nixos",
  "display_name": "NixOS Config",
  "icon": "󱄅",
  "scoped_classes": ["Code", "Ghostty", "neovide"],
  "workspace_preferences": {
    "1": "primary",
    "2": "secondary",
    "5": "secondary"
  }
}
```

**No Changes Required** - Used as-is for classification precedence

---

### AppClassification

**Location**: `home-modules/tools/i3_project_manager/core/models.py` (lines 448-537)

**Purpose**: Global application classification with pattern support

**Current Fields**:
```python
@dataclass
class AppClassification:
    scoped_classes: List[str] = field(default_factory=list)     # Default scoped
    global_classes: List[str] = field(default_factory=list)     # Always global
    class_patterns: Dict[str, str] = field(default_factory=dict)  # **CURRENTLY IGNORED**
```

**Enhancement** (FR-027):
```python
@dataclass
class AppClassification:
    scoped_classes: List[str] = field(default_factory=list)
    global_classes: List[str] = field(default_factory=list)

    # ENHANCED: Support both dict and List[PatternRule]
    class_patterns: Union[Dict[str, str], List[PatternRule]] = field(default_factory=list)

    def __post_init__(self):
        """Convert dict patterns to PatternRule list for uniform handling."""
        if isinstance(self.class_patterns, dict):
            # Backward compatibility: convert dict to PatternRule list
            self.class_patterns = [
                PatternRule(pattern=pattern, scope=scope, priority=100, description=f"Global pattern: {pattern}")
                for pattern, scope in self.class_patterns.items()
            ]
        elif isinstance(self.class_patterns, list) and self.class_patterns:
            # Validate list contains PatternRule instances
            if not all(isinstance(p, PatternRule) for p in self.class_patterns):
                # Convert dict items to PatternRule
                self.class_patterns = [PatternRule(**p) if isinstance(p, dict) else p for p in self.class_patterns]
```

**Migration**:
- Old JSON format (still supported):
  ```json
  {
    "scoped_classes": ["Code", "Ghostty"],
    "global_classes": ["firefox", "mpv"],
    "class_patterns": {
      "pwa-": "global",
      "terminal": "scoped"
    }
  }
  ```
- New JSON format (recommended):
  ```json
  {
    "scoped_classes": ["Code", "Ghostty"],
    "global_classes": ["firefox", "mpv"],
    "class_patterns": [
      {"pattern": "glob:pwa-*", "scope": "global", "priority": 100, "description": "Firefox PWAs"},
      {"pattern": "glob:*terminal*", "scope": "scoped", "priority": 90, "description": "Terminal apps"}
    ]
  }
  ```

**Integration**: Priority 100 - Used after window-rules.json, before literal lists

---

### PatternRule

**Location**: `home-modules/tools/i3_project_manager/models/pattern.py` (lines 10-91)

**Purpose**: Pattern-based window class matching with validation

**Fields**:
```python
@dataclass(frozen=True)
class PatternRule:
    pattern: str                                    # glob:*, regex:^...$, or literal
    scope: Literal["scoped", "global"]              # Classification scope
    priority: int = 0                                # Precedence for matching
    description: str = ""                            # Human-readable description

    def matches(self, window_class: str) -> bool:
        """Test if window class matches this pattern."""
        pattern_type, raw_pattern = self._parse_pattern()
        if pattern_type == "literal":
            return window_class == raw_pattern
        elif pattern_type == "glob":
            return fnmatch.fnmatch(window_class, raw_pattern)
        else:  # regex
            return bool(re.search(raw_pattern, window_class))
```

**Pattern Syntax**:
- `glob:pwa-*` - Glob pattern (shell-style wildcards)
- `regex:^vim$` - Regular expression
- `Code` - Literal match (no prefix)

**No Changes Required** - Reused as-is by WindowRule

---

## New Models

### WindowRule

**Location**: `home-modules/desktop/i3-project-event-daemon/window_rules.py` (NEW)

**Purpose**: Window classification rule with pattern, workspace assignment, and optional command

**Fields**:
```python
@dataclass
class WindowRule:
    """Window classification rule with pattern matching and actions."""

    pattern_rule: PatternRule                       # Reuses existing PatternRule
    workspace: Optional[int] = None                 # Target workspace (1-9)
    command: Optional[str] = None                   # i3 command to execute
    modifier: Optional[str] = None                  # GLOBAL, DEFAULT, ON_CLOSE, TITLE
    blacklist: List[str] = field(default_factory=list)  # For GLOBAL rules

    def __post_init__(self):
        """Validate window rule configuration."""
        if self.workspace is not None and not (1 <= self.workspace <= 9):
            raise ValueError(f"Workspace must be 1-9, got {self.workspace}")

        if self.modifier and self.modifier not in ["GLOBAL", "DEFAULT", "ON_CLOSE", "TITLE"]:
            raise ValueError(f"Invalid modifier: {self.modifier}")

        if self.blacklist and self.modifier != "GLOBAL":
            raise ValueError("Blacklist only valid with GLOBAL modifier")

    def matches(self, window_class: str, window_title: str = "") -> bool:
        """Check if this rule matches the window."""
        # Check pattern match
        if not self.pattern_rule.matches(window_class):
            return False

        # Check blacklist (for GLOBAL rules)
        if self.modifier == "GLOBAL" and window_class in self.blacklist:
            return False

        return True

    @property
    def priority(self) -> int:
        """Get priority from pattern rule."""
        return self.pattern_rule.priority

    @property
    def scope(self) -> str:
        """Get scope from pattern rule."""
        return self.pattern_rule.scope
```

**JSON Schema**:
```json
{
  "type": "array",
  "items": {
    "type": "object",
    "required": ["pattern_rule"],
    "properties": {
      "pattern_rule": {
        "type": "object",
        "required": ["pattern", "scope"],
        "properties": {
          "pattern": {"type": "string", "minLength": 1},
          "scope": {"type": "string", "enum": ["scoped", "global"]},
          "priority": {"type": "integer", "minimum": 0, "default": 0},
          "description": {"type": "string", "default": ""}
        }
      },
      "workspace": {"type": "integer", "minimum": 1, "maximum": 9},
      "command": {"type": "string"},
      "modifier": {"type": "string", "enum": ["GLOBAL", "DEFAULT", "ON_CLOSE", "TITLE"]},
      "blacklist": {"type": "array", "items": {"type": "string"}}
    }
  }
}
```

**Example JSON** (`~/.config/i3/window-rules.json`):
```json
[
  {
    "pattern_rule": {
      "pattern": "glob:FFPWA-*",
      "scope": "global",
      "priority": 200,
      "description": "Firefox PWAs (all global)"
    },
    "workspace": 4
  },
  {
    "pattern_rule": {
      "pattern": "title:^Yazi:.*",
      "scope": "scoped",
      "priority": 300,
      "description": "Yazi file manager in terminal"
    },
    "workspace": 5
  },
  {
    "pattern_rule": {
      "pattern": "Code",
      "scope": "scoped",
      "priority": 250,
      "description": "VS Code editor"
    },
    "workspace": 2
  }
]
```

**File Location**: `~/.config/i3/window-rules.json`

---

### WorkspaceConfig

**Location**: `home-modules/tools/i3_project_manager/models/workspace.py` (NEW)

**Purpose**: Workspace metadata (name, icon, default output role)

**Fields**:
```python
@dataclass
class WorkspaceConfig:
    """Workspace configuration with metadata."""

    number: int                                      # Workspace number (1-9)
    name: Optional[str] = None                       # Workspace name
    icon: Optional[str] = None                       # Unicode icon
    default_output_role: str = "auto"                # auto, primary, secondary, tertiary

    def __post_init__(self):
        """Validate workspace configuration."""
        if not (1 <= self.number <= 9):
            raise ValueError(f"Workspace number must be 1-9, got {self.number}")

        if self.default_output_role not in ["auto", "primary", "secondary", "tertiary"]:
            raise ValueError(f"Invalid output role: {self.default_output_role}")

    def to_json(self) -> dict:
        """Serialize to JSON."""
        return {
            "number": self.number,
            "name": self.name,
            "icon": self.icon,
            "default_output_role": self.default_output_role
        }

    @classmethod
    def from_json(cls, data: dict) -> "WorkspaceConfig":
        """Deserialize from JSON."""
        return cls(**data)
```

**Example JSON** (`~/.config/i3/workspace-config.json`):
```json
[
  {"number": 1, "name": "Terminal", "icon": "󰨊", "default_output_role": "primary"},
  {"number": 2, "name": "Editor", "icon": "", "default_output_role": "primary"},
  {"number": 3, "name": "Browser", "icon": "󰈹", "default_output_role": "secondary"},
  {"number": 4, "name": "Media", "icon": "", "default_output_role": "secondary"},
  {"number": 5, "name": "Files", "icon": "󰉋", "default_output_role": "secondary"},
  {"number": 6, "name": "Chat", "icon": "󰭹", "default_output_role": "tertiary"},
  {"number": 7, "name": "Email", "icon": "󰇮", "default_output_role": "tertiary"},
  {"number": 8, "name": "Music", "icon": "󰝚", "default_output_role": "tertiary"},
  {"number": 9, "name": "Misc", "icon": "󰇙", "default_output_role": "tertiary"}
]
```

**File Location**: `~/.config/i3/workspace-config.json`

---

### Classification

**Location**: `home-modules/desktop/i3-project-event-daemon/pattern_resolver.py` (NEW)

**Purpose**: Result of window classification with source attribution

**Fields**:
```python
@dataclass
class Classification:
    """Window classification result."""

    scope: Literal["scoped", "global"]              # Classification scope
    workspace: Optional[int]                        # Target workspace (1-9 or None)
    source: Literal["project", "window_rule", "app_classes", "default"]  # Rule source
    matched_rule: Optional[WindowRule] = None       # For debugging

    def __post_init__(self):
        """Validate classification."""
        if self.workspace is not None and not (1 <= self.workspace <= 9):
            raise ValueError(f"Workspace must be 1-9, got {self.workspace}")
```

**Usage**:
```python
classification = classify_window(window, active_project)
print(f"Window classified as {classification.scope} from {classification.source}")
if classification.workspace:
    print(f"Assigned to workspace {classification.workspace}")
```

**Source Values**:
- `"project"`: Matched Project.scoped_classes (priority 1000)
- `"window_rule"`: Matched window-rules.json entry (priority 200-500)
- `"app_classes"`: Matched AppClassification.class_patterns (priority 100)
- `"default"`: No match, defaulted to global (priority 0)

---

### MonitorConfig

**Location**: `home-modules/desktop/i3-project-event-daemon/workspace_manager.py` (NEW)

**Purpose**: Monitor/output configuration from i3 GET_OUTPUTS

**Fields**:
```python
@dataclass
class MonitorConfig:
    """Monitor configuration from i3 IPC."""

    name: str                                        # Output name (e.g., "DP-1")
    rect: Dict[str, int]                             # {"x": 0, "y": 0, "width": 1920, "height": 1080}
    active: bool                                     # Is output currently active
    primary: bool                                    # Is primary output
    role: str                                        # "primary", "secondary", "tertiary"

    @classmethod
    def from_i3_output(cls, output: i3ipc.aio.OutputReply, role: str) -> "MonitorConfig":
        """Create from i3 IPC output reply."""
        return cls(
            name=output.name,
            rect={"x": output.rect.x, "y": output.rect.y, "width": output.rect.width, "height": output.rect.height},
            active=output.active,
            primary=output.primary,
            role=role
        )
```

**Usage**:
```python
async def get_monitor_configs(i3: i3ipc.aio.Connection) -> List[MonitorConfig]:
    """Get active monitor configurations with role assignments."""
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    # Assign roles based on count and primary flag
    if len(active_outputs) == 1:
        return [MonitorConfig.from_i3_output(active_outputs[0], "primary")]
    elif len(active_outputs) == 2:
        primary = next((o for o in active_outputs if o.primary), active_outputs[0])
        secondary = next((o for o in active_outputs if o != primary), active_outputs[1])
        return [
            MonitorConfig.from_i3_output(primary, "primary"),
            MonitorConfig.from_i3_output(secondary, "secondary")
        ]
    else:  # 3+ monitors
        # ... role assignment logic
```

---

## Model Relationships

```
Project
├── scoped_classes: List[str] ────────────► Priority 1000 classification
└── workspace_preferences: Dict[int, str] ─► Workspace-to-output overrides

AppClassification
├── scoped_classes: List[str] ────────────► Priority 50 classification (fallback)
├── global_classes: List[str] ────────────► Priority 50 classification (fallback)
└── class_patterns: List[PatternRule] ────► Priority 100 classification

WindowRule
├── pattern_rule: PatternRule ────────────► Pattern matching logic
├── workspace: Optional[int] ─────────────► Workspace assignment
└── priority (from pattern_rule) ─────────► Priority 200-500 classification

Classification
├── scope: str ───────────────────────────► "scoped" or "global"
├── workspace: Optional[int] ─────────────► Target workspace
├── source: str ──────────────────────────► "project", "window_rule", "app_classes", "default"
└── matched_rule: Optional[WindowRule] ───► For debugging

WorkspaceConfig
├── number: int ──────────────────────────► Workspace number (1-9)
├── name: Optional[str] ──────────────────► Display name
├── icon: Optional[str] ──────────────────► Unicode icon
└── default_output_role: str ─────────────► "auto", "primary", "secondary", "tertiary"

MonitorConfig
├── name: str ────────────────────────────► Output name (from i3)
├── active: bool ─────────────────────────► Is output active (from i3)
└── role: str ────────────────────────────► "primary", "secondary", "tertiary" (assigned)
```

## File Storage

| Model | File Location | Format |
|-------|---------------|--------|
| Project | `~/.config/i3/projects/{name}.json` | Existing - no changes |
| AppClassification | `~/.config/i3/app-classes.json` | Enhanced - class_patterns field |
| WindowRule (list) | `~/.config/i3/window-rules.json` | NEW - array of WindowRule |
| WorkspaceConfig (list) | `~/.config/i3/workspace-config.json` | NEW - array of WorkspaceConfig |
| Classification | Runtime only (not persisted) | N/A |
| MonitorConfig | Runtime only (queried from i3) | N/A |
