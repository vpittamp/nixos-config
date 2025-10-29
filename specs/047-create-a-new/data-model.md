# Data Model: Dynamic Sway Configuration Management

**Feature**: 047-create-a-new
**Date**: 2025-10-29

## Overview

This document defines the data models for dynamic Sway configuration management, including configuration entities, validation rules, and state transitions.

## Core Entities

### 1. KeybindingConfig

Represents a keyboard shortcut mapping to a Sway command.

**Fields**:
- `key_combo` (string, required): Key combination in Sway syntax (e.g., "Mod+Return", "Control+1")
- `command` (string, required): Sway command to execute (e.g., "exec terminal", "workspace number 1")
- `description` (string, optional): Human-readable description for documentation
- `source` (enum: "nix"|"runtime"|"project", required): Configuration source attribution
- `mode` (string, optional): Sway mode name for context-specific bindings (default: "default")

**Validation Rules**:
- `key_combo` must match Sway keybinding syntax pattern: `(Mod|Shift|Control|Alt)+[a-zA-Z0-9_-]+`
- `command` must not be empty
- `source` must be one of: "nix", "runtime", "project"
- Mode bindings require valid mode name (alphanumeric + underscore)

**Example**:
```toml
[keybindings]
"Mod+Return" = { command = "exec terminal", description = "Open terminal", mode = "default" }
"Control+1" = { command = "workspace number 1", description = "Switch to workspace 1" }
```

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, validator
from enum import Enum

class ConfigSource(str, Enum):
    NIX = "nix"
    RUNTIME = "runtime"
    PROJECT = "project"

class KeybindingConfig(BaseModel):
    key_combo: str = Field(..., description="Key combination (e.g., Mod+Return)")
    command: str = Field(..., description="Sway command to execute")
    description: str | None = Field(None, description="Human-readable description")
    source: ConfigSource = Field(..., description="Configuration source")
    mode: str = Field("default", description="Sway mode for binding")

    @validator('key_combo')
    def validate_key_combo(cls, v):
        # Validate against Sway keybinding pattern
        import re
        pattern = r'^(Mod|Shift|Control|Alt)(\+(Mod|Shift|Control|Alt))*\+[a-zA-Z0-9_-]+$'
        if not re.match(pattern, v):
            raise ValueError(f"Invalid key combo syntax: {v}")
        return v

    @validator('command')
    def validate_command(cls, v):
        if not v.strip():
            raise ValueError("Command cannot be empty")
        return v.strip()
```

---

### 2. WindowRule

Defines behavior for windows matching specific criteria.

**Fields**:
- `id` (string, required): Unique rule identifier (auto-generated UUID)
- `criteria` (object, required): Window matching criteria
  - `app_id` (string, optional): Application ID pattern (regex)
  - `window_class` (string, optional): Window class pattern (regex, X11 compat)
  - `title` (string, optional): Window title pattern (regex)
  - `window_role` (string, optional): Window role pattern (X11 compat)
- `actions` (array of strings, required): Sway commands to apply (e.g., ["floating enable", "move position center"])
- `scope` (enum: "global"|"project", required): Rule application scope
- `project_name` (string, optional): Project name if scope="project"
- `priority` (integer, required): Rule precedence (higher = applied later, default: 100)
- `source` (enum: "nix"|"runtime"|"project", required): Configuration source

**Validation Rules**:
- At least one criteria field must be specified
- `actions` array cannot be empty
- If `scope="project"`, `project_name` must be specified and reference valid project
- `priority` must be 0-1000
- Regex patterns in criteria must be valid

**Example**:
```json
{
  "id": "rule-001",
  "criteria": {
    "app_id": "^org\\.gnome\\.Calculator$"
  },
  "actions": ["floating enable", "resize set 400 300"],
  "scope": "global",
  "priority": 100,
  "source": "runtime"
}
```

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, validator
from typing import Optional
from enum import Enum
import re

class RuleScope(str, Enum):
    GLOBAL = "global"
    PROJECT = "project"

class WindowCriteria(BaseModel):
    app_id: Optional[str] = Field(None, description="Application ID regex pattern")
    window_class: Optional[str] = Field(None, description="Window class regex pattern")
    title: Optional[str] = Field(None, description="Window title regex pattern")
    window_role: Optional[str] = Field(None, description="Window role pattern")

    @validator('app_id', 'window_class', 'title', 'window_role')
    def validate_regex(cls, v):
        if v is not None:
            try:
                re.compile(v)
            except re.error as e:
                raise ValueError(f"Invalid regex pattern: {e}")
        return v

    def has_criteria(self) -> bool:
        return any([self.app_id, self.window_class, self.title, self.window_role])

class WindowRule(BaseModel):
    id: str = Field(..., description="Unique rule identifier")
    criteria: WindowCriteria = Field(..., description="Window matching criteria")
    actions: list[str] = Field(..., min_items=1, description="Sway commands to apply")
    scope: RuleScope = Field(..., description="Rule application scope")
    project_name: Optional[str] = Field(None, description="Project name (if scope=project)")
    priority: int = Field(100, ge=0, le=1000, description="Rule precedence (0-1000)")
    source: ConfigSource = Field(..., description="Configuration source")

    @validator('criteria')
    def validate_criteria(cls, v):
        if not v.has_criteria():
            raise ValueError("At least one criteria field must be specified")
        return v

    @validator('project_name', always=True)
    def validate_project_scope(cls, v, values):
        if values.get('scope') == RuleScope.PROJECT and not v:
            raise ValueError("project_name required when scope=project")
        return v
```

---

### 3. WorkspaceAssignment

Maps workspace numbers to output names with fallback behavior.

**Fields**:
- `workspace_number` (integer, required): Workspace number (1-70)
- `primary_output` (string, required): Primary output name (e.g., "HDMI-A-1", "eDP-1")
- `fallback_outputs` (array of strings, optional): Fallback outputs if primary unavailable
- `auto_reassign` (boolean, required): Automatically reassign when outputs change (default: true)
- `source` (enum: "nix"|"runtime", required): Configuration source (project scope not applicable)

**Validation Rules**:
- `workspace_number` must be 1-70
- `primary_output` must not be empty
- Fallback outputs must not include primary output
- Output names validated against current Sway outputs (semantic validation)

**Example**:
```json
{
  "workspace_number": 3,
  "primary_output": "HDMI-A-1",
  "fallback_outputs": ["eDP-1"],
  "auto_reassign": true,
  "source": "runtime"
}
```

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, validator
from typing import List, Optional

class WorkspaceAssignment(BaseModel):
    workspace_number: int = Field(..., ge=1, le=70, description="Workspace number (1-70)")
    primary_output: str = Field(..., description="Primary output name")
    fallback_outputs: List[str] = Field(default_factory=list, description="Fallback outputs")
    auto_reassign: bool = Field(True, description="Auto-reassign on output changes")
    source: ConfigSource = Field(..., description="Configuration source")

    @validator('primary_output')
    def validate_primary_output(cls, v):
        if not v.strip():
            raise ValueError("Primary output cannot be empty")
        return v.strip()

    @validator('fallback_outputs')
    def validate_fallbacks(cls, v, values):
        primary = values.get('primary_output')
        if primary and primary in v:
            raise ValueError("Fallback outputs must not include primary output")
        return v
```

---

### 4. ProjectWindowRuleOverride

Project-specific window rule that overrides global rules.

**Fields**:
- `project_name` (string, required): Project identifier
- `base_rule_id` (string, optional): ID of global rule to override (null = new rule)
- `override_properties` (object, required): Properties to override
  - Subset of WindowRule fields (criteria, actions, priority)
- `enabled` (boolean, required): Whether override is active (default: true)

**Validation Rules**:
- `project_name` must reference valid project
- If `base_rule_id` specified, must reference existing global rule
- `override_properties` must contain at least one valid WindowRule field

**Example**:
```json
{
  "project_name": "nixos",
  "base_rule_id": "rule-001",
  "override_properties": {
    "actions": ["floating enable", "resize set 800 600"]
  },
  "enabled": true
}
```

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, validator
from typing import Optional, Dict, Any

class ProjectWindowRuleOverride(BaseModel):
    project_name: str = Field(..., description="Project identifier")
    base_rule_id: Optional[str] = Field(None, description="Global rule ID to override")
    override_properties: Dict[str, Any] = Field(..., description="Properties to override")
    enabled: bool = Field(True, description="Override active status")

    @validator('override_properties')
    def validate_override_properties(cls, v):
        valid_fields = {'criteria', 'actions', 'priority'}
        if not any(k in valid_fields for k in v.keys()):
            raise ValueError(f"Override must contain at least one of: {valid_fields}")
        return v
```

---

### 5. ConfigurationVersion

Snapshot of configuration state for rollback.

**Fields**:
- `commit_hash` (string, required): Git commit SHA
- `timestamp` (datetime, required): Commit timestamp
- `message` (string, required): Commit message
- `files_changed` (array of strings, required): List of modified config files
- `author` (string, optional): Commit author
- `is_active` (boolean, required): Currently active version

**Validation Rules**:
- `commit_hash` must be valid git SHA (40-char hex)
- `timestamp` must be valid ISO 8601 datetime
- `files_changed` cannot be empty

**Pydantic Model**:
```python
from pydantic import BaseModel, Field, validator
from datetime import datetime
import re

class ConfigurationVersion(BaseModel):
    commit_hash: str = Field(..., description="Git commit SHA")
    timestamp: datetime = Field(..., description="Commit timestamp")
    message: str = Field(..., description="Commit message")
    files_changed: List[str] = Field(..., min_items=1, description="Modified config files")
    author: Optional[str] = Field(None, description="Commit author")
    is_active: bool = Field(False, description="Currently active version")

    @validator('commit_hash')
    def validate_commit_hash(cls, v):
        if not re.match(r'^[0-9a-f]{40}$', v):
            raise ValueError("Invalid git SHA format")
        return v
```

---

### 6. ConfigurationSourceAttribution

Tracks which system owns each configuration setting.

**Fields**:
- `setting_path` (string, required): Dot-notation path to setting (e.g., "keybindings.Mod+Return")
- `source_system` (enum: "nix"|"runtime"|"project", required): Owning system
- `precedence_level` (integer, required): Precedence tier (1=nix, 2=runtime, 3=project)
- `last_modified` (datetime, required): Last modification timestamp
- `file_path` (string, required): Source file absolute path

**Pydantic Model**:
```python
from pydantic import BaseModel, Field
from datetime import datetime

class ConfigurationSourceAttribution(BaseModel):
    setting_path: str = Field(..., description="Dot-notation setting path")
    source_system: ConfigSource = Field(..., description="Owning system")
    precedence_level: int = Field(..., ge=1, le=3, description="Precedence tier (1-3)")
    last_modified: datetime = Field(..., description="Last modification time")
    file_path: str = Field(..., description="Source file absolute path")
```

---

## Relationships

```
ProjectWindowRuleOverride
  ├─ references → WindowRule (via base_rule_id)
  └─ belongs_to → Project (via project_name)

WindowRule
  └─ has_many → ProjectWindowRuleOverride

WorkspaceAssignment
  └─ validated_against → Sway Outputs (via IPC)

ConfigurationVersion
  └─ contains_snapshot_of → [KeybindingConfig, WindowRule, WorkspaceAssignment]

ConfigurationSourceAttribution
  ├─ tracks → KeybindingConfig
  ├─ tracks → WindowRule
  └─ tracks → WorkspaceAssignment
```

## State Transitions

### Configuration Reload Lifecycle

```
[User Edits File]
  ↓
[File Watcher Detects Change]
  ↓
[Validation Phase]
  ├─ Structural Validation (JSON Schema)
  ├─ Semantic Validation (Sway IPC state check)
  └─ Conflict Detection (precedence rules)
  ↓
[VALIDATION SUCCESS?]
  ├─ NO → [Reject Changes, Display Errors, Retain Current Config]
  └─ YES → [Merge Phase]
          ↓
[Merge Configuration]
  ├─ Load Nix Base
  ├─ Apply Runtime Overrides
  └─ Apply Project Overrides (if active project)
  ↓
[Apply Phase]
  ├─ Write Merged Config
  ├─ Execute Sway Reload (keybindings)
  └─ Update Daemon Rules (window rules, workspaces)
  ↓
[APPLY SUCCESS?]
  ├─ NO → [Auto-Rollback to Previous Version]
  └─ YES → [Commit to Git, Update .config-version]
          ↓
[Reload Complete]
```

### Configuration Rollback Flow

```
[User Executes: i3pm config rollback <commit>]
  ↓
[Git Checkout Commit]
  ↓
[Trigger Daemon Reload via IPC]
  ↓
[Follow Configuration Reload Lifecycle]
  ↓
[Rollback Complete]
```

## File Storage Schema

### `~/.config/sway/keybindings.toml`
```toml
# User-editable keybinding configuration
# Source: runtime
# Precedence: Overrides Nix base, overridden by project-specific

[keybindings]
"Mod+Return" = { command = "exec terminal", description = "Open terminal" }
"Control+1" = { command = "workspace number 1", description = "Workspace 1" }
# ... more keybindings
```

### `~/.config/sway/window-rules.json`
```json
{
  "version": "1.0",
  "rules": [
    {
      "id": "rule-001",
      "criteria": { "app_id": "^org\\.gnome\\.Calculator$" },
      "actions": ["floating enable"],
      "scope": "global",
      "priority": 100,
      "source": "runtime"
    }
  ]
}
```

### `~/.config/sway/workspace-assignments.json`
```json
{
  "version": "1.0",
  "assignments": [
    {
      "workspace_number": 1,
      "primary_output": "eDP-1",
      "fallback_outputs": [],
      "auto_reassign": true,
      "source": "runtime"
    }
  ]
}
```

### `~/.config/sway/projects/nixos.json`
```json
{
  "project_name": "nixos",
  "directory": "/etc/nixos",
  "icon": "🔧",
  "window_rule_overrides": [
    {
      "base_rule_id": "rule-001",
      "override_properties": {
        "actions": ["floating enable", "resize set 800 600"]
      },
      "enabled": true
    }
  ],
  "keybinding_overrides": {
    "Mod+g": { "command": "exec lazygit", "description": "Git UI" }
  }
}
```

### `~/.config/sway/.config-version`
```json
{
  "commit_hash": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0",
  "timestamp": "2025-10-29T14:30:00Z",
  "message": "Update keybindings for project workflow",
  "files_changed": ["keybindings.toml"],
  "is_active": true
}
```

## Validation Error Format

All validation errors follow structured format for CLI display:

```python
from pydantic import BaseModel
from typing import List, Optional

class ValidationError(BaseModel):
    file_path: str
    line_number: Optional[int]
    error_type: str  # "syntax", "semantic", "conflict"
    message: str
    suggestion: Optional[str]

class ValidationResult(BaseModel):
    valid: bool
    errors: List[ValidationError]
    warnings: List[ValidationError]
```

Example output:
```
❌ Validation Failed: keybindings.toml

Line 15: Syntax Error
  Invalid key combo: "Mod++Return"
  → Suggestion: Use single + between modifiers (e.g., "Mod+Return")

Line 23: Semantic Error
  Referenced workspace 15 does not exist
  → Suggestion: Available workspaces: 1-9. Create workspace 15 first.

⚠️  1 Warning

Line 8: Conflict Warning
  Keybinding "Control+1" defined in both Nix and runtime config
  → Using runtime config (higher precedence)
```
