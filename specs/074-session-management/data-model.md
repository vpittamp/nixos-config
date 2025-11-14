# Data Model: Session Management

**Feature**: 074-session-management
**Date**: 2025-01-14
**Phase**: 1 (Design & Contracts)

## Purpose

Define Pydantic data models for session management, extending existing layout system with workspace focus tracking, terminal working directory preservation, and mark-based correlation.

## Model Extensions

### 1. WindowPlaceholder (Extended)

**Location**: `home-modules/desktop/i3-project-event-daemon/layout/models.py`

**Existing Model**:
```python
class WindowPlaceholder(BaseModel):
    window_class: Optional[str] = None
    instance: Optional[str] = None
    title_pattern: Optional[str] = None
    launch_command: str = Field(..., min_length=1)
    geometry: WindowGeometry
    floating: bool = False
    marks: list[str] = Field(default_factory=list)
```

**Extensions** (FR-039, FR-040):
```python
class WindowPlaceholder(BaseModel):
    # ... existing fields unchanged

    # NEW: Terminal working directory tracking (FR-039)
    cwd: Optional[Path] = None

    # NEW: Focused state tracking (FR-040)
    focused: bool = False

    # NEW: Temporary restoration mark for Sway correlation
    restoration_mark: Optional[str] = None

    # NEW: App registry name for wrapper-based restoration (Feature 057 integration)
    # This field stores the app name from I3PM_APP_NAME environment variable
    # Examples: "yazi", "claude-pwa", "code", "scratchpad-terminal"
    # When present, restoration uses AppLauncher service instead of raw launch_command
    # This ensures consistent wrapper injection of I3PM_* environment variables
    app_registry_name: Optional[str] = None

    @field_validator('cwd')
    @classmethod
    def validate_cwd_absolute(cls, v: Optional[Path]) -> Optional[Path]:
        """Ensure cwd is absolute path if provided."""
        if v is not None and not v.is_absolute():
            raise ValueError(f"Working directory must be absolute: {v}")
        return v

    def is_terminal(self) -> bool:
        """Check if this placeholder represents a terminal application."""
        TERMINAL_CLASSES = {"ghostty", "Alacritty", "kitty", "foot", "WezTerm"}
        return self.window_class in TERMINAL_CLASSES

    def get_launch_env(self, project: str) -> dict[str, str]:
        """Generate environment variables for window launch with correlation mark."""
        import uuid
        import os

        # Generate unique restoration mark if not already set
        if not self.restoration_mark:
            self.restoration_mark = f"i3pm-restore-{uuid.uuid4().hex[:8]}"

        env = {
            **os.environ,
            "I3PM_RESTORE_MARK": self.restoration_mark,
            "I3PM_PROJECT": project,
        }

        return env
```

**Backward Compatibility** (FR-041):
- `cwd`, `focused`, and `app_registry_name` are optional fields with `None` default
- Existing saved layouts will deserialize successfully with these fields as `None`
- When `app_registry_name` is None, system falls back to direct `launch_command` execution
- Pydantic v2 handles missing fields gracefully

### 2. LayoutSnapshot (Extended)

**Location**: `home-modules/desktop/i3-project-event-daemon/layout/models.py`

**Existing Model**:
```python
class LayoutSnapshot(BaseModel):
    name: str = Field(..., pattern=r'^[a-z0-9-]+$', min_length=1, max_length=50)
    project: str = Field(..., pattern=r'^[a-z0-9-]+$')
    created_at: datetime = Field(default_factory=datetime.now)
    monitor_config: MonitorConfiguration
    workspace_layouts: list[WorkspaceLayout] = Field(min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)
```

**Extension** (FR-038):
```python
class LayoutSnapshot(BaseModel):
    # ... existing fields unchanged

    # NEW: Focused workspace tracking (FR-038)
    focused_workspace: Optional[int] = Field(default=None, ge=1, le=70)

    @model_validator(mode='after')
    def validate_focused_workspace_exists(self) -> 'LayoutSnapshot':
        """Ensure focused workspace exists in workspace_layouts if specified."""
        if self.focused_workspace is not None:
            workspace_nums = {wl.workspace_num for wl in self.workspace_layouts}
            if self.focused_workspace not in workspace_nums:
                raise ValueError(
                    f"Focused workspace {self.focused_workspace} not in layout workspaces: {workspace_nums}"
                )
        return self

    def is_auto_save(self) -> bool:
        """Check if this is an auto-saved layout (name starts with 'auto-')."""
        return self.name.startswith("auto-")

    def get_timestamp(self) -> Optional[str]:
        """Extract timestamp from auto-save name (format: auto-YYYYMMDD-HHMMSS)."""
        if not self.is_auto_save():
            return None
        # Extract timestamp portion after "auto-"
        return self.name[5:] if len(self.name) > 5 else None
```

### 3. DaemonState (Extended)

**Location**: `home-modules/desktop/i3-project-event-daemon/models/legacy.py`

**Existing Model**:
```python
@dataclass
class DaemonState:
    active_project: Optional[str] = None
    window_map: Dict[int, WindowInfo] = field(default_factory=dict)
    workspace_map: Dict[str, WorkspaceInfo] = field(default_factory=dict)
    scoped_classes: set[str] = field(default_factory=set)
    global_classes: set[str] = field(default_factory=set)
    start_time: datetime = field(default_factory=datetime.now)
    event_count: int = 0
    error_count: int = 0
```

**Extension** (FR-001, FR-003):
```python
@dataclass
class DaemonState:
    # ... existing fields unchanged

    # NEW: Per-project focused workspace tracking (FR-001, FR-003)
    project_focused_workspace: Dict[str, int] = field(default_factory=dict)

    # NEW: Per-workspace focused window tracking (FR-013)
    workspace_focused_window: Dict[int, int] = field(default_factory=dict)  # workspace_num → window_id

    def get_focused_workspace(self, project: str) -> Optional[int]:
        """Get focused workspace for a project."""
        return self.project_focused_workspace.get(project)

    def set_focused_workspace(self, project: str, workspace_num: int) -> None:
        """Set focused workspace for a project."""
        self.project_focused_workspace[project] = workspace_num

    def get_focused_window(self, workspace_num: int) -> Optional[int]:
        """Get focused window ID for a workspace."""
        return self.workspace_focused_window.get(workspace_num)

    def set_focused_window(self, workspace_num: int, window_id: int) -> None:
        """Set focused window for a workspace."""
        self.workspace_focused_window[workspace_num] = window_id

    def to_json(self) -> dict:
        """Serialize state to JSON-compatible dict for persistence."""
        return {
            "active_project": self.active_project,
            "project_focused_workspace": self.project_focused_workspace,
            "workspace_focused_window": {
                str(k): v for k, v in self.workspace_focused_window.items()
            },
            "start_time": self.start_time.isoformat(),
            "event_count": self.event_count,
            "error_count": self.error_count,
        }

    @classmethod
    def from_json(cls, data: dict) -> 'DaemonState':
        """Deserialize state from JSON."""
        state = cls()
        state.active_project = data.get("active_project")
        state.project_focused_workspace = data.get("project_focused_workspace", {})
        state.workspace_focused_window = {
            int(k): v for k, v in data.get("workspace_focused_window", {}).items()
        }
        state.start_time = datetime.fromisoformat(data["start_time"]) if "start_time" in data else datetime.now()
        state.event_count = data.get("event_count", 0)
        state.error_count = data.get("error_count", 0)
        return state
```

### 4. RestoreCorrelation (New Model)

**Location**: `home-modules/desktop/i3-project-event-daemon/layout/models.py`

**Purpose**: Track mark-based correlation state during window restoration

```python
from enum import Enum
from uuid import UUID, uuid4

class CorrelationStatus(str, Enum):
    """Status of window correlation attempt"""
    PENDING = "pending"      # Waiting for window to appear
    MATCHED = "matched"      # Window successfully matched
    TIMEOUT = "timeout"      # Window did not appear within timeout
    FAILED = "failed"        # Matching failed due to error

class RestoreCorrelation(BaseModel):
    """Tracks correlation state for a single window restoration"""

    correlation_id: UUID = Field(default_factory=uuid4)
    restoration_mark: str = Field(..., pattern=r'^i3pm-restore-[0-9a-f]{8}$')
    placeholder: WindowPlaceholder
    status: CorrelationStatus = CorrelationStatus.PENDING
    started_at: datetime = Field(default_factory=datetime.now)
    completed_at: Optional[datetime] = None
    matched_window_id: Optional[int] = None
    error_message: Optional[str] = None

    @property
    def elapsed_seconds(self) -> float:
        """Time elapsed since correlation started."""
        end_time = self.completed_at or datetime.now()
        return (end_time - self.started_at).total_seconds()

    @property
    def is_complete(self) -> bool:
        """Check if correlation has finished (matched, timeout, or failed)."""
        return self.status != CorrelationStatus.PENDING

    def mark_matched(self, window_id: int) -> None:
        """Mark correlation as successfully matched."""
        self.status = CorrelationStatus.MATCHED
        self.matched_window_id = window_id
        self.completed_at = datetime.now()

    def mark_timeout(self) -> None:
        """Mark correlation as timed out."""
        self.status = CorrelationStatus.TIMEOUT
        self.completed_at = datetime.now()
        self.error_message = f"No window appeared with mark {self.restoration_mark} within timeout"

    def mark_failed(self, error: str) -> None:
        """Mark correlation as failed with error message."""
        self.status = CorrelationStatus.FAILED
        self.completed_at = datetime.now()
        self.error_message = error
```

### 5. ProjectConfiguration (New Model)

**Location**: `home-modules/desktop/i3-project-event-daemon/models/config.py`

**Purpose**: Per-project session management settings (loaded from Nix registry)

```python
class ProjectConfiguration(BaseModel):
    """Session management configuration for a project"""

    name: str = Field(..., pattern=r'^[a-z0-9-]+$')
    directory: Path
    auto_save: bool = Field(default=True)
    auto_restore: bool = Field(default=False)
    default_layout: Optional[str] = Field(default=None, pattern=r'^[a-z0-9-]+$')
    max_auto_saves: int = Field(default=10, ge=1, le=100)

    @field_validator('directory')
    @classmethod
    def directory_must_exist(cls, v: Path) -> Path:
        """Warn if directory doesn't exist (non-fatal for config loading)."""
        if not v.exists():
            logger.warning(f"Project directory does not exist: {v}")
        return v.absolute()

    def get_layouts_dir(self) -> Path:
        """Get directory where layouts are stored for this project."""
        layouts_dir = Path.home() / ".local/share/i3pm/layouts" / self.name
        layouts_dir.mkdir(parents=True, exist_ok=True)
        return layouts_dir

    def get_auto_save_name(self) -> str:
        """Generate auto-save layout name with current timestamp."""
        from datetime import datetime
        return f"auto-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

    def list_auto_saves(self) -> list[Path]:
        """List all auto-saved layouts, sorted newest first."""
        layouts_dir = self.get_layouts_dir()
        auto_saves = sorted(
            layouts_dir.glob("auto-*.json"),
            key=lambda f: f.stat().st_mtime,
            reverse=True
        )
        return auto_saves

    def get_latest_auto_save(self) -> Optional[str]:
        """Get name of most recent auto-save layout (without .json extension)."""
        auto_saves = self.list_auto_saves()
        if auto_saves:
            return auto_saves[0].stem
        return None
```

### 6. AppLauncher Service (New Service)

**Location**: `home-modules/desktop/i3-project-event-daemon/services/app_launcher.py`

**Purpose**: Unified application launcher for consistent wrapper-based launches across Walker, restore, daemon, and CLI

**Integration with Feature 057**: This service ensures all app launches use the wrapper system that injects I3PM_* environment variables, maintaining the 100% deterministic window matching achieved in Feature 057.

**Key Methods**:
```python
class AppLauncher:
    """Unified app launcher using app registry definitions.

    Ensures all app launches (Walker, restore, daemon, CLI) use the same
    wrapper system with I3PM_* environment variable injection.
    """

    def __init__(self, registry_path: Path = Path.home() / ".local/share/i3pm/app-registry.json"):
        """Initialize with app registry JSON."""
        self.registry = self._load_registry(registry_path)

    async def launch_app(
        self,
        app_name: str,
        project: Optional[str] = None,
        cwd: Optional[Path] = None,
        extra_env: Optional[Dict[str, str]] = None,
        restore_mark: Optional[str] = None
    ) -> subprocess.Popen:
        """Launch application via wrapper system.

        Args:
            app_name: App name from registry (e.g., "yazi", "claude-pwa", "code")
            project: Project context for I3PM_PROJECT
            cwd: Working directory for terminals
            extra_env: Additional environment variables
            restore_mark: I3PM_RESTORE_MARK for layout correlation

        Returns:
            subprocess.Popen instance
        """
        # 1. Look up app in registry
        # 2. Build command with $PROJECT_DIR/$CWD substitution
        # 3. Build environment with I3PM_APP_NAME, I3PM_PROJECT, etc.
        # 4. Launch subprocess with full environment
        pass

    def get_app_info(self, app_name: str) -> Optional[Dict[str, Any]]:
        """Get app registry entry (for validation)."""
        pass

    def list_apps(self, scope: Optional[str] = None) -> list[Dict[str, Any]]:
        """List all apps, optionally filtered by scope."""
        pass
```

**Launch Flow**:
1. **Walker/Rofi** → `launch <app-name>` → AppLauncher.launch_app() → subprocess with I3PM_* env
2. **Layout Restore** → WindowPlaceholder.app_registry_name → AppLauncher.launch_app() → subprocess with I3PM_RESTORE_MARK
3. **Daemon Scratchpad** → AppLauncher.launch_app("scratchpad-terminal") → subprocess with I3PM_* env
4. **CLI Testing** → `i3pm launch <app-name>` → AppLauncher.launch_app() → subprocess with I3PM_* env

**Why This Matters**:
- **PWA Support**: PWAs require `launch-pwa-by-name <ULID>` wrapper - direct launch fails
- **Terminal Apps**: Need proper ghostty wrapper with parameters like `-e yazi $PROJECT_DIR`
- **Feature 057 Alignment**: I3PM_APP_NAME must be injected for daemon window correlation
- **Consistency**: Same launch path for all sources (Walker, restore, daemon, CLI)

## Persistence Files

### 1. Project Focus State

**Path**: `~/.config/i3/project-focus-state.json`

**Purpose**: Persist focused workspace per project (FR-003)

**Format**:
```json
{
  "nixos": 3,
  "dotfiles": 5,
  "personal-site": 12
}
```

### 2. Workspace Focus State

**Path**: `~/.config/i3/workspace-focus-state.json` (optional)

**Purpose**: Persist focused window per workspace (FR-015)

**Format**:
```json
{
  "1": 12345,
  "2": 67890,
  "3": 11111
}
```

### 3. Layout Snapshot Files

**Path**: `~/.local/share/i3pm/layouts/{project}/{layout-name}.json`

**Purpose**: Persist complete layout snapshots

**Format** (Pydantic serialization):
```json
{
  "name": "main",
  "project": "nixos",
  "created_at": "2025-01-14T10:30:00",
  "focused_workspace": 3,
  "monitor_config": {
    "name": "dual-monitor",
    "monitors": [
      {
        "name": "eDP-1",
        "active": true,
        "primary": true,
        "resolution": {"width": 1920, "height": 1080},
        "position": {"x": 0, "y": 0}
      }
    ],
    "workspace_assignments": {
      "1": "eDP-1",
      "2": "eDP-1",
      "3": "eDP-1"
    }
  },
  "workspace_layouts": [
    {
      "workspace_num": 3,
      "workspace_name": "3",
      "output": "eDP-1",
      "layout_mode": "splith",
      "windows": [
        {
          "window_class": "ghostty",
          "instance": "ghostty",
          "title_pattern": ".*",
          "launch_command": "ghostty",
          "geometry": {"x": 0, "y": 0, "width": 1920, "height": 1080},
          "floating": false,
          "marks": ["scoped:nixos:12345"],
          "cwd": "/etc/nixos",
          "focused": true
        }
      ]
    }
  ],
  "metadata": {}
}
```

## State Transitions

### Workspace Focus State Machine

```
[Initial] → [Project Active] → [Workspace Focused] → [Focus Tracked]
    ↓              ↓                    ↓                    ↓
  None      set active_project    capture ws number    persist to JSON
                                  + update state
```

### Window Correlation State Machine

```
[Launch Command]
    ↓
[Generate Mark]
    ↓
[Inject Environment]
    ↓
[Execute Process]
    ↓
[Poll for Window] ──────→ [Window Found] → [Apply Geometry] → [Remove Mark] → [MATCHED]
    ↓                            ↑
    └─[Timeout 30s]──────────────┘
         ↓
    [TIMEOUT]
```

### Auto-Save Lifecycle

```
[Project Switch Triggered]
    ↓
[Check auto_save Config]
    ↓
[Capture Current Layout]
    ↓
[Generate auto-YYYYMMDD-HHMMSS Name]
    ↓
[Save to JSON File]
    ↓
[List Existing Auto-Saves]
    ↓
[Prune if > max_auto_saves]
```

## Validation Rules

### Data Integrity

1. **Workspace Numbers**: Must be 1-70 (Sway standard)
2. **Project Names**: Lowercase alphanumeric with hyphens only
3. **Layout Names**: Lowercase alphanumeric with hyphens only
4. **Restoration Marks**: Format `i3pm-restore-{8-char-hex}`
5. **Working Directories**: Must be absolute paths if specified
6. **Focus State**: Focused workspace must exist in layout

### Cross-Model Consistency

1. **DaemonState.project_focused_workspace keys** must match active projects
2. **LayoutSnapshot.focused_workspace** must exist in workspace_layouts
3. **WindowPlaceholder.focused** - only one per workspace can be true
4. **RestoreCorrelation.matched_window_id** must exist in Sway tree when status=MATCHED

## Migration Strategy

### Backward Compatibility

**Existing layouts without new fields**:
- Load successfully (Pydantic optional fields default to None)
- Display warning: "Layout missing focus state, using defaults"
- Focus state falls back to workspace 1

**Upgrading layouts**:
- First save after upgrade will include new fields
- Old layouts remain usable but without focus restoration
- No automatic migration needed (forward-compatible)

### Forward Compatibility

**New layouts on old daemon**:
- Unknown fields ignored by Pydantic
- Core layout restoration still works
- Focus restoration features unavailable (graceful degradation)

## Next Steps

Proceed to contracts generation (API/IPC endpoints) and quickstart documentation.
