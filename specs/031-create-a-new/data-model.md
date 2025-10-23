# Data Model: Automated Window Rules Discovery and Validation

**Feature**: 031-create-a-new
**Date**: 2025-10-23
**Language**: Python 3.11+ with Pydantic v2

## Overview

This document defines the data models for window pattern discovery, validation, and configuration management. All models use Pydantic for validation and type safety (Constitution Principle X - Python Development Standards).

## Core Entities

### 1. Window

Represents an i3 window with properties captured from i3 IPC GET_TREE.

```python
from pydantic import BaseModel, Field
from typing import Optional

class Window(BaseModel):
    """Represents an i3 window with properties from i3 IPC."""

    id: int = Field(..., description="i3 container ID")
    window_id: Optional[int] = Field(None, description="X11 window ID")
    window_class: str = Field(..., description="WM_CLASS class property")
    window_instance: str = Field(..., description="WM_CLASS instance property")
    title: str = Field(..., description="WM_NAME window title")
    workspace_num: int = Field(..., description="Workspace number (1-9)")
    workspace_name: str = Field(..., description="Workspace name from i3")
    output: str = Field(..., description="Output/monitor name (e.g., HDMI-0)")
    window_type: Optional[str] = Field(None, description="Window type (_NET_WM_WINDOW_TYPE)")
    floating: bool = Field(False, description="Whether window is floating")
    marks: list[str] = Field(default_factory=list, description="i3 marks applied to window")
    focused: bool = Field(False, description="Whether window has focus")

    # Derived properties
    is_terminal: bool = Field(False, description="Whether window is a known terminal emulator")
    is_pwa: bool = Field(False, description="Whether window is a Firefox PWA (FFPWA-*)")

    @classmethod
    def from_i3_container(cls, container) -> "Window":
        """Create Window from i3ipc Container object."""
        window_class = container.window_class or "Unknown"
        window_instance = container.window_instance or "Unknown"
        title = container.name or ""

        # Detect terminal emulators
        terminal_classes = ["ghostty", "Alacritty", "kitty", "URxvt", "XTerm", "st"]
        is_terminal = any(term.lower() in window_class.lower() for term in terminal_classes)

        # Detect PWAs
        is_pwa = window_class.startswith("FFPWA-")

        return cls(
            id=container.id,
            window_id=container.window,
            window_class=window_class,
            window_instance=window_instance,
            title=title,
            workspace_num=container.workspace().num if container.workspace() else 0,
            workspace_name=container.workspace().name if container.workspace() else "",
            output=container.workspace().ipc_data.get("output", "") if container.workspace() else "",
            window_type=container.window_type,
            floating=container.floating == "user_on" or container.floating == "auto_on",
            marks=container.marks if container.marks else [],
            focused=container.focused,
            is_terminal=is_terminal,
            is_pwa=is_pwa,
        )
```

**Validation Rules**:
- `window_class` must not be empty (use "Unknown" fallback)
- `workspace_num` must be 0-9 (0 for scratchpad)
- `marks` must be list of valid mark strings (alphanumeric + underscore)

**State Transitions**: None (immutable snapshot)

### 2. Pattern

Represents a window matching pattern with type and matching logic.

```python
from enum import Enum
from pydantic import BaseModel, Field, field_validator

class PatternType(str, Enum):
    """Type of pattern matching to apply."""
    CLASS = "class"              # Exact WM_CLASS match
    TITLE = "title"              # Title substring match
    TITLE_REGEX = "title_regex"  # Title regex match
    PWA = "pwa"                  # PWA ID match (FFPWA-*)

class Pattern(BaseModel):
    """Window matching pattern."""

    type: PatternType = Field(..., description="Type of pattern matching")
    value: str = Field(..., description="Pattern value (class name, title substring, or regex)")
    description: Optional[str] = Field(None, description="Human-readable description of what this pattern matches")

    # Metadata
    priority: int = Field(10, description="Pattern priority (lower = higher priority, 0-100)")
    case_sensitive: bool = Field(True, description="Whether matching is case-sensitive")

    @field_validator("value")
    @classmethod
    def validate_value(cls, v: str) -> str:
        """Ensure value is not empty."""
        if not v or not v.strip():
            raise ValueError("Pattern value cannot be empty")
        return v.strip()

    def matches(self, window: Window) -> bool:
        """Check if this pattern matches the given window."""
        import re

        if self.type == PatternType.CLASS:
            target = window.window_class
            pattern = self.value
            if not self.case_sensitive:
                target = target.lower()
                pattern = pattern.lower()
            return target == pattern

        elif self.type == PatternType.TITLE:
            target = window.title
            pattern = self.value
            if not self.case_sensitive:
                target = target.lower()
                pattern = pattern.lower()
            return pattern in target

        elif self.type == PatternType.TITLE_REGEX:
            flags = 0 if self.case_sensitive else re.IGNORECASE
            return bool(re.search(self.value, window.title, flags))

        elif self.type == PatternType.PWA:
            return window.window_class == self.value and window.is_pwa

        return False
```

**Validation Rules**:
- `value` must not be empty or whitespace-only
- `priority` must be 0-100 (lower = higher priority)
- `type` must be valid PatternType enum value

**Relationships**:
- Used by `WindowRule` for workspace assignment
- Generated by `DiscoveryResult` during pattern discovery

### 3. WindowRule

Associates a pattern with workspace assignment and scope classification.

```python
from pydantic import BaseModel, Field

class Scope(str, Enum):
    """Application scope classification."""
    SCOPED = "scoped"   # Project-specific, hidden when project inactive
    GLOBAL = "global"   # Always visible across all projects

class WindowRule(BaseModel):
    """Associates a pattern with workspace assignment."""

    pattern: Pattern = Field(..., description="Pattern to match windows")
    workspace: int = Field(..., description="Target workspace number (1-9)")
    scope: Scope = Field(..., description="Application scope (scoped/global)")
    enabled: bool = Field(True, description="Whether this rule is active")

    # Metadata
    application_name: str = Field(..., description="Friendly application name (e.g., 'VSCode', 'Firefox')")
    notes: Optional[str] = Field(None, description="Additional notes about this rule")

    @field_validator("workspace")
    @classmethod
    def validate_workspace(cls, v: int) -> int:
        """Ensure workspace is valid (1-9)."""
        if not 1 <= v <= 9:
            raise ValueError("Workspace must be between 1 and 9")
        return v
```

**Validation Rules**:
- `workspace` must be 1-9 (9 valid workspaces)
- `pattern` must be valid Pattern object
- `application_name` must not be empty

**State Transitions**:
- `enabled` can toggle true/false to temporarily disable rules

**Relationships**:
- Contains one `Pattern`
- Stored in `window-rules.json` configuration file
- Referenced by daemon during window::new event handling

### 4. ApplicationDefinition

Describes an application with launch command, pattern expectations, and configuration.

```python
from pydantic import BaseModel, Field
from typing import Optional

class ApplicationDefinition(BaseModel):
    """Defines an application with launch command and pattern expectations."""

    name: str = Field(..., description="Application name (e.g., 'vscode', 'firefox')")
    display_name: str = Field(..., description="Human-readable name (e.g., 'VS Code', 'Firefox')")

    # Launch configuration
    command: str = Field(..., description="Base launch command (e.g., 'code', 'firefox')")
    rofi_name: Optional[str] = Field(None, description="Name as it appears in rofi (if different from display_name)")
    parameters: Optional[str] = Field(None, description="Additional command parameters (e.g., '$PROJECT_DIR')")

    # Pattern expectations
    expected_pattern_type: PatternType = Field(..., description="Expected pattern type (class/title/pwa)")
    expected_class: Optional[str] = Field(None, description="Expected WM_CLASS (if known)")
    expected_title_contains: Optional[str] = Field(None, description="Expected title substring (if known)")

    # Classification
    scope: Scope = Field(..., description="Application scope (scoped/global)")
    preferred_workspace: Optional[int] = Field(None, description="Preferred workspace number (1-9)")

    # NixOS integration
    desktop_file_path: Optional[str] = Field(None, description="Path to .desktop file for customization")
    nix_package: Optional[str] = Field(None, description="NixOS package name (e.g., 'pkgs.vscode')")

    @field_validator("command")
    @classmethod
    def validate_command(cls, v: str) -> str:
        """Ensure command is not empty."""
        if not v or not v.strip():
            raise ValueError("Command cannot be empty")
        return v.strip()

    def get_full_command(self, **kwargs) -> str:
        """Get full launch command with parameter substitution."""
        cmd = self.command
        if self.parameters:
            # Substitute parameters (e.g., $PROJECT_DIR)
            params = self.parameters
            for key, value in kwargs.items():
                params = params.replace(f"${key.upper()}", str(value))
            cmd = f"{cmd} {params}"
        return cmd
```

**Validation Rules**:
- `command` must not be empty
- `preferred_workspace` if set must be 1-9
- At least one of `expected_class` or `expected_title_contains` should be set

**Relationships**:
- Used by discovery service to launch applications
- Generates `DiscoveryResult` with captured pattern
- Used by migration service to create `WindowRule` entries

### 5. DiscoveryResult

Contains captured window properties and generated pattern from discovery process.

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class DiscoveryResult(BaseModel):
    """Result of discovering a window pattern for an application."""

    application_name: str = Field(..., description="Application name that was launched")
    launch_command: str = Field(..., description="Command used to launch application")
    launch_method: str = Field(..., description="Launch method (rofi/direct/manual)")

    # Captured window
    window: Optional[Window] = Field(None, description="Captured window (None if window didn't appear)")
    capture_time: datetime = Field(default_factory=datetime.now, description="When window was captured")
    wait_duration: float = Field(..., description="How long waited for window (seconds)")

    # Generated pattern
    generated_pattern: Optional[Pattern] = Field(None, description="Generated pattern (None if discovery failed)")
    confidence: float = Field(0.0, description="Confidence score 0.0-1.0")

    # Issues
    success: bool = Field(False, description="Whether discovery succeeded")
    warnings: list[str] = Field(default_factory=list, description="Warnings during discovery")
    errors: list[str] = Field(default_factory=list, description="Errors during discovery")

    @field_validator("confidence")
    @classmethod
    def validate_confidence(cls, v: float) -> float:
        """Ensure confidence is 0.0-1.0."""
        if not 0.0 <= v <= 1.0:
            raise ValueError("Confidence must be between 0.0 and 1.0")
        return v
```

**Validation Rules**:
- `confidence` must be 0.0-1.0
- `wait_duration` must be >= 0
- If `success` is True, `window` and `generated_pattern` must not be None

**State Transitions**: None (immutable result)

**Relationships**:
- Contains one `Window` (if captured)
- Contains one `Pattern` (if generated)
- Used by validation service to test discovered patterns

### 6. ValidationResult

Reports pattern match status and workspace assignment verification.

```python
from enum import Enum
from pydantic import BaseModel, Field
from typing import Optional

class ValidationStatus(str, Enum):
    """Validation result status."""
    SUCCESS = "success"              # Pattern matched correctly
    FALSE_POSITIVE = "false_positive"  # Pattern matched wrong window
    FALSE_NEGATIVE = "false_negative"  # Pattern didn't match intended window
    WRONG_WORKSPACE = "wrong_workspace"  # Matched but on wrong workspace
    NO_WINDOW = "no_window"          # No window found to test against

class ValidationResult(BaseModel):
    """Result of validating a pattern against windows."""

    pattern: Pattern = Field(..., description="Pattern being validated")
    application_name: str = Field(..., description="Expected application name")

    # Validation outcome
    status: ValidationStatus = Field(..., description="Validation status")
    matched_window: Optional[Window] = Field(None, description="Window that matched (if any)")

    # Workspace verification
    expected_workspace: Optional[int] = Field(None, description="Expected workspace from rule")
    actual_workspace: Optional[int] = Field(None, description="Actual workspace where window appeared")
    workspace_correct: bool = Field(False, description="Whether workspace assignment is correct")

    # Discrepancies
    false_positive_windows: list[Window] = Field(default_factory=list, description="Other windows incorrectly matched")
    message: str = Field("", description="Human-readable validation message")
```

**Validation Rules**:
- If `status` is SUCCESS, `matched_window` must not be None
- If `status` is WRONG_WORKSPACE, both `expected_workspace` and `actual_workspace` must be set
- `expected_workspace` and `actual_workspace` if set must be 1-9

**Relationships**:
- Contains one `Pattern` being validated
- Contains `Window` objects for matches and false positives
- Generated by validation service during pattern testing

### 7. ConfigurationBackup

Timestamped snapshot of configuration files before modifications.

```python
from pydantic import BaseModel, Field
from datetime import datetime
from pathlib import Path

class ConfigurationBackup(BaseModel):
    """Backup of configuration files before modification."""

    timestamp: datetime = Field(default_factory=datetime.now, description="When backup was created")
    backup_dir: Path = Field(..., description="Directory containing backups")

    # Backup file paths
    window_rules_backup: Path = Field(..., description="Backup of window-rules.json")
    app_classes_backup: Path = Field(..., description="Backup of app-classes.json")

    # Metadata
    reason: str = Field(..., description="Reason for backup (e.g., 'migration', 'manual update')")
    rules_count: int = Field(0, description="Number of rules in backup")

    def restore(self) -> None:
        """Restore configuration from backup."""
        import shutil

        # Restore window-rules.json
        target = Path.home() / ".config/i3/window-rules.json"
        shutil.copy2(self.window_rules_backup, target)

        # Restore app-classes.json
        target = Path.home() / ".config/i3/app-classes.json"
        shutil.copy2(self.app_classes_backup, target)
```

**Validation Rules**:
- `backup_dir` must exist and be writable
- `window_rules_backup` and `app_classes_backup` must exist
- `rules_count` must be >= 0

**State Transitions**: None (immutable record)

**Relationships**:
- Created by migration service before modifying configuration
- Contains paths to backed-up JSON files

## Configuration File Schemas

### window-rules.json

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "version": { "type": "string", "description": "Schema version" },
    "rules": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "pattern": {
            "type": "object",
            "properties": {
              "type": { "enum": ["class", "title", "title_regex", "pwa"] },
              "value": { "type": "string", "minLength": 1 },
              "description": { "type": "string" },
              "priority": { "type": "integer", "minimum": 0, "maximum": 100 },
              "case_sensitive": { "type": "boolean" }
            },
            "required": ["type", "value"]
          },
          "workspace": { "type": "integer", "minimum": 1, "maximum": 9 },
          "scope": { "enum": ["scoped", "global"] },
          "enabled": { "type": "boolean" },
          "application_name": { "type": "string", "minLength": 1 },
          "notes": { "type": "string" }
        },
        "required": ["pattern", "workspace", "scope", "application_name"]
      }
    }
  },
  "required": ["version", "rules"]
}
```

### app-classes.json

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "version": { "type": "string" },
    "scoped_classes": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Window classes for project-scoped applications"
    },
    "global_classes": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Window classes for globally visible applications"
    }
  },
  "required": ["version", "scoped_classes", "global_classes"]
}
```

### application-registry.json (New)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "version": { "type": "string" },
    "applications": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "display_name": { "type": "string" },
          "command": { "type": "string" },
          "rofi_name": { "type": "string" },
          "parameters": { "type": "string" },
          "expected_pattern_type": { "enum": ["class", "title", "title_regex", "pwa"] },
          "expected_class": { "type": "string" },
          "expected_title_contains": { "type": "string" },
          "scope": { "enum": ["scoped", "global"] },
          "preferred_workspace": { "type": "integer", "minimum": 1, "maximum": 9 },
          "desktop_file_path": { "type": "string" },
          "nix_package": { "type": "string" }
        },
        "required": ["name", "display_name", "command", "expected_pattern_type", "scope"]
      }
    }
  },
  "required": ["version", "applications"]
}
```

## Model Relationships Diagram

```
ApplicationDefinition
    |
    | (launches)
    v
DiscoveryResult
    |
    | (contains)
    |-- Window
    |-- Pattern
    |
    | (validates)
    v
ValidationResult
    |
    | (contains)
    |-- Pattern
    |-- Window (matched_window)
    |-- Window[] (false_positive_windows)
    |
    | (creates)
    v
WindowRule
    |
    | (contains)
    |-- Pattern
    |
    | (stored in)
    v
window-rules.json
    |
    | (backed up to)
    v
ConfigurationBackup
```

## Usage Examples

### Discovering a Pattern

```python
from i3_window_rules.discovery import DiscoveryService
from i3_window_rules.models import ApplicationDefinition, PatternType, Scope

app_def = ApplicationDefinition(
    name="vscode",
    display_name="VS Code",
    command="code",
    parameters="$PROJECT_DIR",
    expected_pattern_type=PatternType.CLASS,
    expected_class="Code",
    scope=Scope.SCOPED,
    preferred_workspace=1
)

service = DiscoveryService()
result = await service.discover(app_def, launch_method="direct", timeout=10.0)

if result.success:
    print(f"Pattern: {result.generated_pattern.type} = {result.generated_pattern.value}")
    print(f"Confidence: {result.confidence}")
else:
    print(f"Errors: {result.errors}")
```

### Validating a Pattern

```python
from i3_window_rules.validation import ValidationService
from i3_window_rules.models import Pattern, PatternType

pattern = Pattern(
    type=PatternType.CLASS,
    value="Code",
    description="VSCode editor",
    priority=10
)

service = ValidationService()
result = await service.validate_pattern(pattern, application_name="VSCode", expected_workspace=1)

print(f"Status: {result.status}")
print(f"Workspace correct: {result.workspace_correct}")
if result.false_positive_windows:
    print(f"False positives: {len(result.false_positive_windows)}")
```

---

**Data Model Complete**: All entities defined with validation rules, relationships, and state transitions. Ready for contract generation.
