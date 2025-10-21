# Data Model: App Discovery & Auto-Classification System

**Branch**: `020-update-our-spec` | **Date**: 2025-10-21 | **Plan**: [plan.md](plan.md)

## Overview

This document defines the data structures, validation rules, and relationships for the four app discovery enhancements. All models use Python dataclasses per [research.md](research.md) Decision 2.

---

## Entity 1: PatternRule

**Purpose**: Represents a glob or regex pattern for automatic window class classification.

**File**: `home-modules/tools/i3_project_manager/models/pattern.py`

### Fields

| Field | Type | Required | Default | Validation |
|-------|------|----------|---------|------------|
| `pattern` | `str` | Yes | - | Non-empty, must be valid glob/regex with optional prefix |
| `scope` | `Literal["scoped", "global"]` | Yes | - | Must be "scoped" or "global" |
| `priority` | `int` | No | `0` | Must be >= 0 |
| `description` | `str` | No | `""` | Arbitrary user-provided description |

### Dataclass Definition

```python
from dataclasses import dataclass
from typing import Literal
import re
import fnmatch

@dataclass
class PatternRule:
    """Pattern-based window class classification rule.

    Attributes:
        pattern: Pattern string with optional prefix (glob:, regex:, or literal)
        scope: Classification scope (scoped or global)
        priority: Precedence for matching (higher = evaluated first)
        description: Optional human-readable description
    """

    pattern: str
    scope: Literal["scoped", "global"]
    priority: int = 0
    description: str = ""

    def __post_init__(self):
        """Validate pattern syntax and priority."""
        if not self.pattern:
            raise ValueError("Pattern cannot be empty")

        if self.priority < 0:
            raise ValueError("Priority must be non-negative")

        # Validate pattern syntax
        pattern_type, raw_pattern = self._parse_pattern()

        if pattern_type == "regex":
            try:
                re.compile(raw_pattern)
            except re.error as e:
                raise ValueError(f"Invalid regex pattern '{raw_pattern}': {e}")

        # Glob patterns are validated by fnmatch.translate (no explicit check needed)

    def _parse_pattern(self) -> tuple[str, str]:
        """Parse pattern into (type, raw_pattern) tuple.

        Returns:
            ("glob", "pwa-*") for "glob:pwa-*"
            ("regex", "^vim$") for "regex:^vim$"
            ("literal", "Code") for "Code"
        """
        if self.pattern.startswith("glob:"):
            return ("glob", self.pattern[5:])
        elif self.pattern.startswith("regex:"):
            return ("regex", self.pattern[6:])
        else:
            return ("literal", self.pattern)

    def matches(self, window_class: str) -> bool:
        """Test if window class matches this pattern.

        Args:
            window_class: Window class string to test (e.g., "pwa-youtube")

        Returns:
            True if window class matches pattern, False otherwise
        """
        pattern_type, raw_pattern = self._parse_pattern()

        if pattern_type == "literal":
            return window_class == raw_pattern
        elif pattern_type == "glob":
            return fnmatch.fnmatch(window_class, raw_pattern)
        else:  # regex
            return bool(re.match(raw_pattern, window_class))
```

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["pattern", "scope"],
  "properties": {
    "pattern": {
      "type": "string",
      "minLength": 1,
      "description": "Pattern string with optional prefix (glob:, regex:, or literal)"
    },
    "scope": {
      "type": "string",
      "enum": ["scoped", "global"],
      "description": "Classification scope"
    },
    "priority": {
      "type": "integer",
      "minimum": 0,
      "default": 0,
      "description": "Precedence for matching (higher = evaluated first)"
    },
    "description": {
      "type": "string",
      "default": "",
      "description": "Optional human-readable description"
    }
  }
}
```

### Example Instances

```python
# Glob pattern for PWAs
pwa_pattern = PatternRule(
    pattern="glob:pwa-*",
    scope="global",
    priority=100,
    description="All PWAs are global apps"
)

# Regex pattern for Vim variants
vim_pattern = PatternRule(
    pattern="regex:^(neo)?vim$",
    scope="scoped",
    priority=90,
    description="Neovim and Vim are project-scoped"
)

# Literal pattern (no prefix)
ghostty_pattern = PatternRule(
    pattern="Ghostty",
    scope="scoped",
    priority=50,
    description="Ghostty terminal is project-scoped"
)
```

---

## Entity 2: DetectionResult

**Purpose**: Represents the result of automated window class detection via Xvfb.

**File**: `home-modules/tools/i3_project_manager/models/detection.py`

### Fields

| Field | Type | Required | Default | Validation |
|-------|------|----------|---------|------------|
| `desktop_file` | `str` | Yes | - | Must be valid .desktop file path |
| `app_name` | `str` | Yes | - | Non-empty application name |
| `detected_class` | `str \| None` | Yes | - | Window class if detected, None if failed |
| `detection_method` | `Literal["xvfb", "desktop_file", "heuristic", "failed"]` | Yes | - | Must be valid method |
| `confidence` | `float` | No | `1.0` | Must be in range [0.0, 1.0] |
| `error_message` | `str \| None` | No | `None` | Set if detection_method == "failed" |
| `timestamp` | `str` | No | `datetime.now().isoformat()` | ISO 8601 format |

### Dataclass Definition

```python
from dataclasses import dataclass, field
from typing import Literal, Optional
from datetime import datetime

@dataclass
class DetectionResult:
    """Result of automated window class detection.

    Attributes:
        desktop_file: Path to .desktop file (e.g., "/usr/share/applications/code.desktop")
        app_name: Application name from .desktop file (e.g., "Visual Studio Code")
        detected_class: Detected WM_CLASS (e.g., "Code") or None if detection failed
        detection_method: How window class was determined
        confidence: Confidence score [0.0, 1.0] for detection reliability
        error_message: Error details if detection_method == "failed"
        timestamp: ISO 8601 timestamp of detection
    """

    desktop_file: str
    app_name: str
    detected_class: Optional[str]
    detection_method: Literal["xvfb", "desktop_file", "heuristic", "failed"]
    confidence: float = 1.0
    error_message: Optional[str] = None
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())

    def __post_init__(self):
        """Validate detection result."""
        if not self.desktop_file:
            raise ValueError("desktop_file cannot be empty")

        if not self.app_name:
            raise ValueError("app_name cannot be empty")

        if not (0.0 <= self.confidence <= 1.0):
            raise ValueError(f"confidence must be in [0.0, 1.0], got {self.confidence}")

        if self.detection_method == "failed" and not self.error_message:
            raise ValueError("error_message required when detection_method is 'failed'")

        if self.detection_method != "failed" and not self.detected_class:
            raise ValueError(f"detected_class required when detection_method is '{self.detection_method}'")
```

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["desktop_file", "app_name", "detected_class", "detection_method"],
  "properties": {
    "desktop_file": {
      "type": "string",
      "minLength": 1,
      "description": "Path to .desktop file"
    },
    "app_name": {
      "type": "string",
      "minLength": 1,
      "description": "Application name from .desktop file"
    },
    "detected_class": {
      "type": ["string", "null"],
      "description": "Detected WM_CLASS or null if detection failed"
    },
    "detection_method": {
      "type": "string",
      "enum": ["xvfb", "desktop_file", "heuristic", "failed"],
      "description": "How window class was determined"
    },
    "confidence": {
      "type": "number",
      "minimum": 0.0,
      "maximum": 1.0,
      "default": 1.0,
      "description": "Confidence score for detection reliability"
    },
    "error_message": {
      "type": ["string", "null"],
      "default": null,
      "description": "Error details if detection_method is 'failed'"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 timestamp of detection"
    }
  }
}
```

### Example Instances

```python
# Successful Xvfb detection
success_result = DetectionResult(
    desktop_file="/usr/share/applications/code.desktop",
    app_name="Visual Studio Code",
    detected_class="Code",
    detection_method="xvfb",
    confidence=1.0,
    timestamp="2025-10-21T14:30:00Z"
)

# Detection from StartupWMClass in .desktop file
desktop_file_result = DetectionResult(
    desktop_file="/usr/share/applications/firefox.desktop",
    app_name="Firefox",
    detected_class="firefox",
    detection_method="desktop_file",
    confidence=1.0,
    timestamp="2025-10-21T14:30:01Z"
)

# Heuristic detection (guessed)
heuristic_result = DetectionResult(
    desktop_file="/usr/share/applications/slack.desktop",
    app_name="Slack",
    detected_class="Slack",  # Guessed from app name
    detection_method="heuristic",
    confidence=0.7,
    timestamp="2025-10-21T14:30:02Z"
)

# Failed detection
failed_result = DetectionResult(
    desktop_file="/usr/share/applications/broken.desktop",
    app_name="Broken App",
    detected_class=None,
    detection_method="failed",
    confidence=0.0,
    error_message="Xvfb process timed out after 10 seconds",
    timestamp="2025-10-21T14:30:03Z"
)
```

---

## Entity 3: AppClassification

**Purpose**: Represents the classification state of a discovered application in the wizard.

**File**: `home-modules/tools/i3_project_manager/models/classification.py`

### Fields

| Field | Type | Required | Default | Validation |
|-------|------|----------|---------|------------|
| `app_name` | `str` | Yes | - | Non-empty application name |
| `window_class` | `str` | Yes | - | Non-empty window class |
| `desktop_file` | `str` | Yes | - | Valid .desktop file path |
| `current_scope` | `Literal["scoped", "global", "unclassified"]` | Yes | - | Valid scope value |
| `suggested_scope` | `Literal["scoped", "global"] \| None` | No | `None` | Valid scope or None |
| `suggestion_reasoning` | `str` | No | `""` | Explanation for suggestion |
| `suggestion_confidence` | `float` | No | `0.0` | Must be in [0.0, 1.0] |
| `user_modified` | `bool` | No | `False` | True if user changed classification |

### Dataclass Definition

```python
from dataclasses import dataclass
from typing import Literal, Optional

@dataclass
class AppClassification:
    """Classification state of an application in the wizard.

    Attributes:
        app_name: Human-readable application name (e.g., "Visual Studio Code")
        window_class: WM_CLASS for i3 matching (e.g., "Code")
        desktop_file: Path to .desktop file
        current_scope: Current classification (scoped, global, or unclassified)
        suggested_scope: System-suggested classification (None if no suggestion)
        suggestion_reasoning: Explanation for suggestion
        suggestion_confidence: Confidence [0.0, 1.0] in suggestion
        user_modified: True if user explicitly changed classification
    """

    app_name: str
    window_class: str
    desktop_file: str
    current_scope: Literal["scoped", "global", "unclassified"]
    suggested_scope: Optional[Literal["scoped", "global"]] = None
    suggestion_reasoning: str = ""
    suggestion_confidence: float = 0.0
    user_modified: bool = False

    def __post_init__(self):
        """Validate classification state."""
        if not self.app_name:
            raise ValueError("app_name cannot be empty")

        if not self.window_class:
            raise ValueError("window_class cannot be empty")

        if not self.desktop_file:
            raise ValueError("desktop_file cannot be empty")

        if not (0.0 <= self.suggestion_confidence <= 1.0):
            raise ValueError(f"suggestion_confidence must be in [0.0, 1.0], got {self.suggestion_confidence}")

    def accept_suggestion(self):
        """Accept the system suggestion (update current_scope)."""
        if self.suggested_scope is None:
            raise ValueError("No suggestion to accept")

        self.current_scope = self.suggested_scope
        self.user_modified = True

    def classify_as(self, scope: Literal["scoped", "global"]):
        """Manually classify application (overrides suggestion)."""
        self.current_scope = scope
        self.user_modified = True
```

### Example Instances

```python
# Unclassified app with suggestion
ghostty = AppClassification(
    app_name="Ghostty Terminal",
    window_class="Ghostty",
    desktop_file="/usr/share/applications/ghostty.desktop",
    current_scope="unclassified",
    suggested_scope="scoped",
    suggestion_reasoning="Terminal emulator - typically project-scoped",
    suggestion_confidence=0.9,
    user_modified=False
)

# Classified app (user accepted suggestion)
ghostty.accept_suggestion()
# Now: current_scope="scoped", user_modified=True

# Manually classified app (user override)
firefox = AppClassification(
    app_name="Firefox",
    window_class="firefox",
    desktop_file="/usr/share/applications/firefox.desktop",
    current_scope="scoped",  # User chose this
    suggested_scope="global",  # System suggested global
    suggestion_reasoning="Web browser - typically global",
    suggestion_confidence=0.8,
    user_modified=True
)
```

---

## Entity 4: WizardState

**Purpose**: Represents the current state of the classification wizard session.

**File**: `home-modules/tools/i3_project_manager/models/classification.py`

### Fields

| Field | Type | Required | Default | Validation |
|-------|------|----------|---------|------------|
| `apps` | `list[AppClassification]` | Yes | `[]` | List of all discovered apps |
| `selected_indices` | `set[int]` | No | `set()` | Set of selected app indices |
| `filter_status` | `Literal["all", "unclassified", "scoped", "global"]` | No | `"all"` | Valid filter value |
| `sort_by` | `Literal["name", "class", "status", "confidence"]` | No | `"name"` | Valid sort field |
| `undo_stack` | `list[dict]` | No | `[]` | Stack of undo states (JSON snapshots) |
| `changes_made` | `bool` | No | `False` | True if any classifications changed |

### Dataclass Definition

```python
from dataclasses import dataclass, field
from typing import Literal

@dataclass
class WizardState:
    """State of the classification wizard session.

    Attributes:
        apps: List of all discovered applications
        selected_indices: Set of currently selected app indices
        filter_status: Current filter (all, unclassified, scoped, global)
        sort_by: Current sort field
        undo_stack: Stack of previous states for undo/redo
        changes_made: True if any classifications have been modified
    """

    apps: list[AppClassification] = field(default_factory=list)
    selected_indices: set[int] = field(default_factory=set)
    filter_status: Literal["all", "unclassified", "scoped", "global"] = "all"
    sort_by: Literal["name", "class", "status", "confidence"] = "name"
    undo_stack: list[dict] = field(default_factory=list)
    changes_made: bool = False

    def get_filtered_apps(self) -> list[AppClassification]:
        """Get apps matching current filter."""
        if self.filter_status == "all":
            return self.apps
        return [app for app in self.apps if app.current_scope == self.filter_status]

    def get_sorted_apps(self, apps: list[AppClassification]) -> list[AppClassification]:
        """Sort apps by current sort field."""
        if self.sort_by == "name":
            return sorted(apps, key=lambda a: a.app_name.lower())
        elif self.sort_by == "class":
            return sorted(apps, key=lambda a: a.window_class.lower())
        elif self.sort_by == "status":
            return sorted(apps, key=lambda a: a.current_scope)
        else:  # confidence
            return sorted(apps, key=lambda a: a.suggestion_confidence, reverse=True)

    def save_undo_state(self):
        """Save current state to undo stack."""
        state_snapshot = {
            "apps": [vars(app) for app in self.apps],
            "selected_indices": list(self.selected_indices),
            "filter_status": self.filter_status,
            "sort_by": self.sort_by
        }
        self.undo_stack.append(state_snapshot)

    def undo(self):
        """Restore previous state from undo stack."""
        if not self.undo_stack:
            raise ValueError("Nothing to undo")

        state_snapshot = self.undo_stack.pop()
        # Restore state from snapshot
        # (Implementation omitted for brevity)
```

---

## Entity 5: WindowProperties

**Purpose**: Represents comprehensive window properties for the inspector.

**File**: `home-modules/tools/i3_project_manager/models/inspector.py`

### Fields

| Field | Type | Required | Default | Validation |
|-------|------|----------|---------|------------|
| `window_id` | `int` | Yes | - | i3 container ID (con_id) |
| `window_class` | `str \| None` | Yes | - | WM_CLASS from X11 |
| `instance` | `str \| None` | Yes | - | WM_CLASS instance |
| `title` | `str` | Yes | - | Window title |
| `marks` | `list[str]` | No | `[]` | i3 marks on window |
| `workspace` | `str` | Yes | - | Current workspace name |
| `current_classification` | `Literal["scoped", "global", "unclassified"]` | Yes | - | Classification status |
| `suggested_classification` | `Literal["scoped", "global"] \| None` | No | `None` | Suggested classification |
| `reasoning` | `str` | No | `""` | Explanation for classification |

### Dataclass Definition

```python
from dataclasses import dataclass, field
from typing import Literal, Optional

@dataclass
class WindowProperties:
    """Comprehensive window properties from i3 IPC.

    Attributes:
        window_id: i3 container ID (con_id)
        window_class: WM_CLASS from X11
        instance: WM_CLASS instance
        title: Window title
        marks: List of i3 marks on window
        workspace: Current workspace name
        current_classification: Current classification status
        suggested_classification: System-suggested classification
        reasoning: Explanation for classification
    """

    window_id: int
    window_class: Optional[str]
    instance: Optional[str]
    title: str
    workspace: str
    current_classification: Literal["scoped", "global", "unclassified"]
    marks: list[str] = field(default_factory=list)
    suggested_classification: Optional[Literal["scoped", "global"]] = None
    reasoning: str = ""

    def __post_init__(self):
        """Validate window properties."""
        if self.window_id <= 0:
            raise ValueError(f"window_id must be positive, got {self.window_id}")

        if not self.title:
            raise ValueError("title cannot be empty")

        if not self.workspace:
            raise ValueError("workspace cannot be empty")
```

### Example Instance

```python
# Inspector examining a Ghostty terminal window
ghostty_window = WindowProperties(
    window_id=94489280512,
    window_class="Ghostty",
    instance="ghostty",
    title="nvim /etc/nixos/configuration.nix",
    marks=["nixos"],  # Project mark
    workspace="1",
    current_classification="scoped",
    suggested_classification="scoped",
    reasoning="Terminal emulator - project-scoped by default. Currently marked with project 'nixos'."
)
```

---

## Configuration File Formats

### app-classes.json

**Location**: `~/.config/i3/app-classes.json`

**Structure**:
```json
{
  "scoped_classes": ["Ghostty", "Code"],
  "global_classes": ["firefox", "pwa-youtube"],
  "class_patterns": [
    {
      "pattern": "glob:pwa-*",
      "scope": "global",
      "priority": 100,
      "description": "All PWAs are global apps"
    },
    {
      "pattern": "regex:^(neo)?vim$",
      "scope": "scoped",
      "priority": 90,
      "description": "Neovim and Vim are project-scoped"
    }
  ]
}
```

**Precedence** (FR-076):
1. `scoped_classes` (highest)
2. `global_classes`
3. `class_patterns` (sorted by priority, descending)
4. Heuristics (lowest)

### detected-classes.json

**Location**: `~/.cache/i3pm/detected-classes.json`

**Structure**:
```json
{
  "results": [
    {
      "desktop_file": "/usr/share/applications/code.desktop",
      "app_name": "Visual Studio Code",
      "detected_class": "Code",
      "detection_method": "xvfb",
      "confidence": 1.0,
      "error_message": null,
      "timestamp": "2025-10-21T14:30:00Z"
    }
  ],
  "cache_version": "1.0",
  "last_updated": "2025-10-21T14:30:05Z"
}
```

---

## Relationships

```
PatternRule (1) ──> (N) AppClassification
   │                      │
   │                      │
   └──────────────────────┴──> WindowProperties
                              (pattern matching
                               determines classification)

DetectionResult (1) ──> (1) AppClassification
   (provides window_class)

WizardState (1) ──> (N) AppClassification
   (manages classification session)
```

**Key Relationships**:
1. **PatternRule → AppClassification**: Patterns determine suggested classification
2. **DetectionResult → AppClassification**: Detection provides window_class for classification
3. **WizardState → AppClassification**: Wizard manages multiple app classifications
4. **AppClassification → WindowProperties**: Inspector shows classification for specific window

---

## Validation Summary

| Entity | Validation Rules | Error Cases |
|--------|------------------|-------------|
| `PatternRule` | Non-empty pattern, valid glob/regex syntax, priority >= 0 | Empty pattern, invalid regex, negative priority |
| `DetectionResult` | Non-empty desktop_file/app_name, confidence in [0.0, 1.0], error_message if failed | Missing fields, invalid confidence, failed without error |
| `AppClassification` | Non-empty app_name/window_class/desktop_file, confidence in [0.0, 1.0] | Empty fields, invalid confidence |
| `WizardState` | Valid filter/sort values | Invalid filter/sort enum |
| `WindowProperties` | Positive window_id, non-empty title/workspace | Zero/negative window_id, empty required fields |

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Phase**: 1 (Data Model) - COMPLETE
