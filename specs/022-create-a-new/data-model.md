# Data Model: Enhanced i3pm TUI with Comprehensive Management & Automated Testing

**Date**: 2025-10-21
**Feature Branch**: `022-create-a-new`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md)

## Entity Overview

This feature extends existing data models with minimal additions for enhanced layout management and testing capabilities. Most entities already exist in `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py`.

### Entity Categories

1. **Core Entities** (Existing): Project, AutoLaunchApp, WorkspaceLayout, SavedLayout
2. **Extended Entities** (Modified): LayoutWindow (4 new fields)
3. **New Entities**: TestScenario, TestAssertion, BreadcrumbPath
4. **Configuration Entities** (Existing): AppClassification, PatternRule, MonitorConfig

---

## Core Entities (Existing)

### Project

**Purpose**: Represents a project configuration with associated applications, layouts, and workspace preferences.

**Location**: `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py` (lines 74-282)

**Fields**:
```python
@dataclass
class Project:
    # Primary fields (required)
    name: str                              # Unique identifier (filesystem-safe)
    directory: Path                        # Project working directory

    # Display fields
    display_name: Optional[str] = None     # Human-readable name
    icon: Optional[str] = None             # Unicode emoji/icon for UI

    # Application associations
    scoped_classes: List[str] = field(default_factory=list)  # Project-specific app classes

    # Workspace configuration
    workspace_preferences: Dict[int, str] = field(default_factory=dict)  # {ws_num: output_role}

    # Auto-launch configuration
    auto_launch: List[AutoLaunchApp] = field(default_factory=list)

    # Saved layouts
    saved_layouts: List[str] = field(default_factory=list)  # Layout names

    # Metadata
    created_at: datetime = field(default_factory=datetime.now)
    modified_at: datetime = field(default_factory=datetime.now)
```

**Relationships**:
- Has many `AutoLaunchApp` entries (composition)
- Has many `SavedLayout` references by name
- References workspace preferences for monitor roles
- References scoped application classes

**Storage**: `~/.config/i3/projects/{project_name}.json`

**Validation**:
- Name must be alphanumeric with `-` or `_`
- Directory must exist
- At least one scoped application class required
- Workspace preferences must map 1-10 to valid output roles

**Methods**:
- `save()`: Persist to disk with atomic write
- `load(name)`: Load from disk by name
- `list_all()`: List all projects sorted by modified_at
- `delete()`: Remove project file
- `delete_with_layouts()`: Cascading delete including layouts

**No Changes Needed**: Existing model fully supports all requirements.

---

### AutoLaunchApp

**Purpose**: Configuration for automatic application launch when switching to a project.

**Location**: `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py` (lines 26-71)

**Fields**:
```python
@dataclass
class AutoLaunchApp:
    command: str                           # Shell command to execute
    workspace: Optional[int] = None        # Target workspace (1-10)
    env: Dict[str, str] = field(default_factory=dict)  # Additional environment variables
    wait_for_mark: Optional[str] = None    # Expected mark (e.g., "project:nixos")
    wait_timeout: float = 5.0              # Timeout in seconds
    launch_delay: float = 0.5              # Delay before launch (seconds)
```

**Relationships**:
- Belongs to `Project` (composition)
- Uses project context for environment variables

**Validation**:
- Command cannot be empty
- Workspace must be 1-10 if specified
- Timeout must be 0.1-30.0 seconds

**Methods**:
- `get_full_env(project)`: Returns environment dict with PROJECT_DIR, PROJECT_NAME, I3_PROJECT, and custom env vars
- `to_json()`: Serialize to JSON
- `from_json(data)`: Deserialize from JSON

**No Changes Needed**: Existing model fully supports FR-019 through FR-023 (auto-launch configuration).

---

### SavedLayout

**Purpose**: Saved project layout with workspace configurations and window arrangements.

**Location**: `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py` (lines 352-451)

**Fields**:
```python
@dataclass
class SavedLayout:
    layout_version: str = "1.0"            # Layout format version
    project_name: str = ""                 # Associated project
    layout_name: str = "default"           # Layout name
    workspaces: List[WorkspaceLayout] = field(default_factory=list)
    saved_at: datetime = field(default_factory=datetime.now)
    monitor_config: str = "single"         # "single", "dual", "triple"
    total_windows: int = 0                 # Total window count
```

**Relationships**:
- Belongs to `Project` by name reference
- Has many `WorkspaceLayout` entries (composition)

**Storage**: `~/.config/i3/layouts/{project_name}/{layout_name}.json`

**Validation**:
- Layout version must be "1.0"
- Layout name must be alphanumeric with `-` or `_`

**Methods**:
- `save()`: Persist to disk
- `load(project_name, layout_name)`: Load from disk
- `list_for_project(project_name)`: List all layouts for a project
- `to_json()`: Serialize to JSON
- `from_json(data)`: Deserialize from JSON

**No Changes Needed**: Existing model supports FR-001, FR-005, FR-006, FR-007 (layout management).

---

### WorkspaceLayout

**Purpose**: Workspace layout configuration containing window arrangements.

**Location**: `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py` (lines 314-349)

**Fields**:
```python
@dataclass
class WorkspaceLayout:
    number: int                            # Workspace number (1-10)
    output_role: str = "primary"           # "primary", "secondary", "tertiary"
    windows: List[LayoutWindow] = field(default_factory=list)
    split_orientation: Optional[str] = None  # "horizontal", "vertical", None
```

**Relationships**:
- Belongs to `SavedLayout` (composition)
- Has many `LayoutWindow` entries (composition)

**Validation**:
- Workspace number must be 1-10
- Output role must be primary/secondary/tertiary
- Split orientation must be horizontal/vertical or None

**Methods**:
- `to_json()`: Serialize to JSON
- `from_json(data)`: Deserialize from JSON

**No Changes Needed**: Existing model supports workspace-level layout configuration.

---

## Extended Entities (Modified)

### LayoutWindow

**Purpose**: Window configuration in a layout with application lifecycle management capabilities.

**Location**: `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py` (lines 284-312)

**Current Fields** (Existing):
```python
@dataclass
class LayoutWindow:
    window_class: str                      # WM_CLASS (e.g., "Ghostty", "Code")
    window_title: Optional[str] = None     # Window title (for matching)
    geometry: Optional[Dict[str, int]] = None  # {"width": 1920, "height": 1080, "x": 0, "y": 0}
    layout_role: Optional[str] = None      # "main", "editor", "terminal", "browser"
    split_before: Optional[str] = None     # "horizontal", "vertical", None
    launch_command: str = ""               # Command to launch this window
    launch_env: Dict[str, str] = field(default_factory=dict)  # Environment variables
    expected_marks: List[str] = field(default_factory=list)  # e.g., ["project:nixos"]
```

**New Fields** (To Add):
```python
    # Application relaunching support (from Research Question 3)
    cwd: Optional[str] = None              # Working directory for launch
    launch_timeout: float = 5.0            # Timeout for window appearance (seconds)
    max_retries: int = 3                   # Retry attempts if launch fails
    retry_delay: float = 1.0               # Delay between retries (seconds)
```

**Relationships**:
- Belongs to `WorkspaceLayout` (composition)
- References application by window_class

**Validation**:
- Window class cannot be empty
- Split orientation must be horizontal/vertical or None
- Launch timeout must be positive
- Max retries must be non-negative

**Methods**:
- `to_json()`: Serialize to JSON (includes new fields)
- `from_json(data)`: Deserialize from JSON (handles missing new fields with defaults)

**Backward Compatibility**: All new fields have default values. Existing saved layouts will deserialize correctly with default values for new fields.

**Change Rationale**: Supports FR-002 (layout restoration with application relaunching), FR-003 (Restore All action), and edge case handling for missing applications.

---

## New Entities

### TestScenario

**Purpose**: Automated test definition for TUI interaction simulation and state verification.

**Location**: To be created in `/etc/nixos/tests/i3pm/scenarios/` (new file per scenario)

**Fields**:
```python
@dataclass
class TestScenario:
    name: str                              # Test scenario name
    description: str                       # Human-readable description
    preconditions: List[str]               # Setup requirements
    actions: List[TestAction]              # Sequence of user actions
    assertions: List[TestAssertion]        # Expected outcomes
    timeout: float = 30.0                  # Maximum execution time
    cleanup: List[str] = field(default_factory=list)  # Cleanup actions
```

**Relationships**:
- Has many `TestAction` entries (composition)
- Has many `TestAssertion` entries (composition)

**Validation**:
- Name must be unique within test suite
- Timeout must be positive
- At least one action required
- At least one assertion required

**Usage Example**:
```python
scenario = TestScenario(
    name="test_layout_save_restore",
    description="User saves current layout and restores it after changes",
    preconditions=[
        "Project 'test-project' exists",
        "3 windows open (Ghostty, Code, Firefox)",
        "Daemon is running"
    ],
    actions=[
        PressKey("l"),  # Open layout manager
        PressKey("s"),  # Save layout
        TypeText("coding-layout"),
        PressKey("enter"),
        # ... change window arrangement ...
        PressKey("r"),  # Restore layout
        SelectRow("coding-layout"),
        PressKey("enter")
    ],
    assertions=[
        AssertLayoutExists("test-project", "coding-layout"),
        AssertWindowCount(3),
        AssertWindowPosition("Ghostty", workspace=1, x=0, y=0)
    ],
    timeout=10.0
)
```

**Methods**:
- `execute(pilot)`: Run test scenario using Textual Pilot
- `validate()`: Check scenario is well-formed
- `to_json()`: Serialize for test reports

**Supports**: FR-029 through FR-033 (automated testing framework).

---

### TestAssertion

**Purpose**: Verification condition for test scenarios.

**Location**: To be created in `/etc/nixos/tests/i3pm/fixtures/assertions.py`

**Fields**:
```python
@dataclass
class TestAssertion:
    assertion_type: str                    # "file_exists", "state_equals", "event_triggered", "timing"
    target: str                            # What to check (file path, widget ID, event name)
    expected: Any                          # Expected value
    operator: str = "equals"               # "equals", "contains", "less_than", "matches_regex"
    timeout: Optional[float] = None        # Wait timeout for condition
    description: str = ""                  # Human-readable assertion description
```

**Assertion Types**:
- `file_exists`: Check file/directory exists
- `state_equals`: Check widget state matches expected
- `event_triggered`: Check daemon event was triggered
- `timing`: Check operation completed within time limit
- `table_row_count`: Check DataTable row count
- `input_value`: Check Input widget value
- `screen_active`: Check active screen name

**Example Assertions**:
```python
# File existence
AssertFileExists("~/.config/i3/layouts/nixos/coding-layout.json")

# State verification
AssertStateEquals(widget_id="projects", property="row_count", expected=5)

# Event verification
AssertEventTriggered(event_type="layout::saved", project="nixos", layout="coding-layout")

# Timing verification
AssertTiming(operation="layout_restore", max_duration=2.0)

# Table content
AssertTableContains(table_id="projects", column="Name", value="NixOS")
```

**Methods**:
- `check()`: Evaluate assertion and return Pass/Fail
- `wait_for_condition(timeout)`: Poll until condition met or timeout
- `format_failure()`: Generate detailed failure message with diff

**Supports**: FR-031 (state verification assertions), SC-007, SC-008 (test coverage and regression detection).

---

### BreadcrumbPath

**Purpose**: Navigation path display for TUI screens.

**Location**: To be created in `/etc/nixos/home-modules/tools/i3_project_manager/tui/widgets/breadcrumb.py`

**Fields**:
```python
@dataclass
class BreadcrumbPath:
    segments: List[str]                    # Path segments (e.g., ["Projects", "NixOS", "Edit"])
    separator: str = " > "                 # Separator between segments
    max_length: int = 80                   # Maximum display length
```

**Methods**:
- `render()`: Generate breadcrumb string for display
- `push(segment)`: Add segment to path
- `pop()`: Remove last segment
- `truncate()`: Shorten path if exceeds max_length (middle ellipsis)

**Usage Example**:
```python
breadcrumb = BreadcrumbPath(["Projects", "NixOS-Configuration-Management", "Layouts"])
breadcrumb.render()  # "Projects > NixOS-Configu... > Layouts"
```

**Supports**: FR-026 (breadcrumb navigation display).

---

## Configuration Entities (Existing)

### AppClassification

**Purpose**: Global application classification with pattern-based matching.

**Location**: `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py` (lines 453-575)

**Fields**:
```python
@dataclass
class AppClassification:
    scoped_classes: List[str] = field(default_factory=list)  # Default scoped classes
    global_classes: List[str] = field(default_factory=list)  # Always global
    class_patterns: List[PatternRule] = field(default_factory=list)  # Pattern rules
```

**Storage**: `~/.config/i3/app-classes.json`

**Methods**:
- `is_scoped(window_class, project)`: Determine if window class is scoped
- `save()`: Persist to disk
- `load()`: Load from disk (creates default if not exists)
- `to_json()`: Serialize to JSON
- `from_json(data)`: Deserialize from JSON

**No Changes Needed**: Existing model supports FR-014 through FR-018 (window classification).

---

### PatternRule

**Purpose**: Pattern-based window class matching rule.

**Location**: `/etc/nixos/home-modules/tools/i3_project_manager/models/pattern.py` (imported in models.py)

**Fields**:
```python
@dataclass
class PatternRule:
    pattern: str                           # Regex or glob pattern
    scope: str                             # "scoped" or "global"
    priority: int = 100                    # Matching priority (lower = higher priority)
    description: str = ""                  # Human-readable description
```

**Validation**:
- Pattern must be valid regex
- Scope must be "scoped" or "global"
- Priority must be positive integer

**Methods**:
- `matches(window_class)`: Test if pattern matches window class
- `to_json()`: Serialize to JSON
- `from_json(data)`: Deserialize from JSON

**No Changes Needed**: Existing model supports FR-016 through FR-018 (pattern-based matching).

---

### MonitorConfig

**Purpose**: Monitor/output configuration from i3 IPC.

**Location**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_manager.py` (lines 8-88)

**Fields**:
```python
@dataclass
class MonitorConfig:
    name: str                              # Output name (e.g., "DP-1", "HDMI-1")
    rect: Dict[str, int]                   # {"x": 0, "y": 0, "width": 1920, "height": 1080}
    active: bool                           # Whether output is currently active
    primary: bool                          # Whether output is marked as primary
    role: str                              # "primary", "secondary", "tertiary"
```

**Validation**:
- Role must be primary/secondary/tertiary
- Rect must contain x, y, width, height keys

**Methods**:
- `from_i3_output(output, role)`: Create from i3ipc OutputReply
- `to_json()`: Serialize to JSON

**No Changes Needed**: Existing model supports FR-012, FR-013 (monitor configuration display and workspace redistribution).

---

## Entity Relationships

### Core Relationship Diagram

```
Project
├── auto_launch: List[AutoLaunchApp]
├── saved_layouts: List[str] → SavedLayout (by name reference)
├── workspace_preferences: Dict[int, str]
└── scoped_classes: List[str]

SavedLayout
├── project_name: str → Project (by name reference)
└── workspaces: List[WorkspaceLayout]

WorkspaceLayout
├── output_role: str → MonitorConfig.role (logical reference)
└── windows: List[LayoutWindow]

LayoutWindow
├── window_class: str → AppClassification (for matching)
├── launch_command: str
└── launch_env: Dict[str, str]

AppClassification
├── scoped_classes: List[str]
├── global_classes: List[str]
└── class_patterns: List[PatternRule]

TestScenario
├── actions: List[TestAction]
└── assertions: List[TestAssertion]
```

### Storage Hierarchy

```
~/.config/i3/
├── projects/
│   ├── nixos.json                    # Project configuration
│   ├── stacks.json
│   └── personal.json
├── layouts/
│   ├── nixos/
│   │   ├── coding-layout.json        # SavedLayout
│   │   └── debugging-layout.json
│   └── stacks/
│       └── default.json
├── app-classes.json                  # AppClassification
└── pattern-rules.json                # PatternRule list (if separate)

/etc/nixos/tests/i3pm/
├── scenarios/
│   ├── test_layout_workflow.py       # TestScenario implementations
│   └── test_window_classification.py
└── fixtures/
    ├── assertions.py                 # TestAssertion implementations
    └── sample_projects.py
```

---

## Data Flow Patterns

### Layout Save Flow

1. User presses 's' in Layout Manager
2. TUI queries i3 via GET_TREE to get all windows
3. For each window with project mark:
   - Extract window_class, window_title, geometry
   - Determine workspace and output_role
   - Capture launch_command from window (if available) or infer from window_class
4. Create WorkspaceLayout for each workspace
5. Create SavedLayout with all WorkspaceLayouts
6. Serialize to `~/.config/i3/layouts/{project}/{layout_name}.json`
7. Update Project.saved_layouts list
8. Notify user of success

### Layout Restore Flow

1. User selects layout and presses 'r' in Layout Manager
2. Load SavedLayout from disk
3. For each LayoutWindow in each WorkspaceLayout:
   - Check if window with window_class exists in i3 tree
   - If missing:
     - Launch via i3 exec with launch_command, launch_env, and cwd
     - Wait for window to appear (launch_timeout with 100ms polling)
     - Retry up to max_retries times if launch fails
   - Once window exists:
     - Move to correct workspace
     - Apply geometry (resize and position)
     - Apply split_orientation if specified
4. Verify all windows positioned correctly
5. Notify user of completion (with any failures)

### Monitor Change Flow

1. i3 emits "output" event (monitor connected/disconnected)
2. Daemon receives event via subscription
3. Daemon queries GET_OUTPUTS to get updated monitor list
4. Daemon calls `get_monitor_configs()` to assign roles
5. If workspace redistribution needed:
   - Calculate new workspace-to-output assignments
   - Send i3 commands to move workspaces
6. If TUI is open:
   - Send notification to TUI via IPC
   - TUI refreshes Monitor Dashboard display
7. Log event to daemon event history

### Test Execution Flow

1. Test runner loads TestScenario from file
2. Check preconditions (project exists, daemon running, etc.)
3. Initialize Textual Pilot with app instance
4. For each TestAction in scenario:
   - Execute action (key press, mouse click, etc.)
   - Wait for Textual to process messages
5. For each TestAssertion in scenario:
   - Evaluate assertion against current state
   - Record Pass/Fail with details
6. Execute cleanup actions
7. Generate test report (human-readable + JSON)
8. Return Pass/Fail status

---

## Data Validation Rules

### Project Validation
- Name: Alphanumeric with `-` or `_` only
- Directory: Must exist and be readable
- Scoped classes: At least one required
- Workspace preferences: Keys 1-10, values primary/secondary/tertiary

### SavedLayout Validation
- Layout name: Alphanumeric with `-` or `_` only
- Workspaces: Each workspace number 1-10, unique within layout
- Total windows: Must match actual window count in all workspaces
- Monitor config: Must be "single", "dual", or "triple"

### LayoutWindow Validation
- Window class: Non-empty string
- Launch command: Non-empty if window should be relaunched
- Launch timeout: Positive number (0.1-30.0 seconds)
- Max retries: Non-negative integer (0-10)
- Geometry: If specified, must have width, height, x, y keys

### AutoLaunchApp Validation
- Command: Non-empty string
- Workspace: If specified, must be 1-10
- Wait timeout: 0.1-30.0 seconds
- Launch delay: 0.0-10.0 seconds

### TestScenario Validation
- Name: Unique within test suite, alphanumeric with `-` or `_`
- Actions: At least one required
- Assertions: At least one required
- Timeout: Positive number (1.0-300.0 seconds)

---

## Migration Strategy

### Backward Compatibility

**LayoutWindow Extensions**:
- All new fields have default values
- Existing saved layouts will deserialize with:
  - `cwd: None`
  - `launch_timeout: 5.0`
  - `max_retries: 3`
  - `retry_delay: 1.0`
- No layout version bump required (additive change)

**Testing**:
- Load existing layout JSON files
- Verify deserialization with defaults
- Verify serialization includes new fields
- Verify backward compatibility with old daemon versions (graceful degradation)

**Migration Not Required**: All changes are additive with sensible defaults.

---

## Summary

### Entities by Status

**Existing (No Changes)**: 8 entities
- Project
- AutoLaunchApp
- SavedLayout
- WorkspaceLayout
- AppClassification
- PatternRule
- MonitorConfig
- TUIState

**Modified**: 1 entity
- LayoutWindow (4 new fields with defaults)

**New**: 3 entities
- TestScenario
- TestAssertion
- BreadcrumbPath

### Key Design Decisions

1. **Minimal Model Changes**: Only LayoutWindow needs modification (4 fields)
2. **Backward Compatibility**: All new fields have default values
3. **Testing Infrastructure**: New test entities support FR-029 through FR-033
4. **Reuse Existing Patterns**: Leverage existing MonitorConfig, AppClassification, etc.
5. **Clear Separation**: Test entities separate from production models

### Implementation Readiness

All entities are well-defined and ready for Phase 2 (contract generation). No ambiguities or missing requirements identified.

---

**Status**: ✅ **COMPLETED** - Data model design complete. Ready for contract generation.
