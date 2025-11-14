# Data Model: Idempotent Layout Restoration

**Feature**: 075-layout-restore-production
**Phase**: 1 (Design)
**Date**: 2025-11-14
**Related**: [spec.md](spec.md) | [plan.md](plan.md) | [research.md](research.md)

## Overview

This document defines the data models for app-registry-based layout restoration. Models use Pydantic for validation and type safety, following Python 3.11+ standards (Constitution Principle X).

---

## Entity: RunningApp

**Purpose**: Represents a currently running application detected from Sway window tree.

**Source**: Derived from Sway IPC `GET_TREE` command + `/proc/<pid>/environ` inspection.

**Lifecycle**: Created during detection phase, discarded after restore completes.

### Schema

```python
from pydantic import BaseModel, Field
from typing import Optional

class RunningApp(BaseModel):
    """Represents a running application detected in workspace."""
    
    app_name: str = Field(
        ...,
        description="Application name from I3PM_APP_NAME environment variable",
        examples=["terminal", "lazygit", "chatgpt-pwa"]
    )
    
    window_id: int = Field(
        ...,
        description="Sway container ID (not Wayland window ID)",
        gt=0
    )
    
    pid: int = Field(
        ...,
        description="Process ID for environment reading",
        gt=0
    )
    
    workspace: int = Field(
        ...,
        description="Current workspace number",
        ge=1,
        le=70
    )
    
    app_id: Optional[str] = Field(
        default=None,
        description="Wayland app_id or X11 window class (for diagnostics)"
    )
```

### Example Instance

```python
RunningApp(
    app_name="lazygit",
    window_id=84,
    pid=224082,
    workspace=5,
    app_id="com.mitchellh.ghostty"
)
```

### Usage

```python
async def detect_running_apps() -> set[str]:
    """Detect running apps by reading I3PM_APP_NAME from environments."""
    tree = await conn.get_tree()
    running_apps = set()
    
    for node in walk_tree(tree):
        if node.pid and node.pid > 0:
            app_name = read_env_var(node.pid, "I3PM_APP_NAME")
            if app_name:
                running_apps.add(app_name)
    
    return running_apps
```

---

## Entity: SavedWindow

**Purpose**: Represents a window configuration from saved layout file.

**Source**: Loaded from JSON layout file (`~/.local/share/i3pm/layouts/<project>/<name>.json`).

**Lifecycle**: Persists in layout file, loaded on restore command.

### Schema

```python
from pydantic import BaseModel, Field
from typing import Optional
from pathlib import Path

class SavedWindow(BaseModel):
    """Represents window configuration from saved layout."""
    
    app_registry_name: str = Field(
        ...,
        description="Key from app-registry-data.nix (e.g., 'terminal', 'claude-pwa')",
        examples=["terminal", "code", "lazygit", "chatgpt-pwa"]
    )
    
    workspace: int = Field(
        ...,
        description="Target workspace number for restoration",
        ge=1,
        le=70,
        alias="workspace_num"  # Support both field names
    )
    
    cwd: Optional[Path] = Field(
        default=None,
        description="Working directory for terminal applications (None for non-terminals)"
    )
    
    focused: bool = Field(
        default=False,
        description="Whether this window was focused when layout was saved"
    )
    
    # Phase 2 fields (unused in MVP)
    geometry: Optional[dict] = Field(
        default=None,
        description="Window geometry (x, y, width, height) - Phase 2 feature"
    )
    
    floating: Optional[bool] = Field(
        default=False,
        description="Whether window was floating - Phase 2 feature"
    )
```

### Example Instance

```python
SavedWindow(
    app_registry_name="lazygit",
    workspace=5,
    cwd=Path("/etc/nixos"),
    focused=False,
    geometry={"x": 3840, "y": 20, "width": 1920, "height": 1126},
    floating=False
)
```

### Usage

```python
async def restore_layout(project: str, layout_name: str):
    """Restore saved layout for project."""
    layout = load_layout(project, layout_name)
    
    for ws_layout in layout["workspace_layouts"]:
        for window_data in ws_layout["windows"]:
            saved_window = SavedWindow(**window_data)
            # Use saved_window.app_registry_name, saved_window.workspace, etc.
```

---

## Entity: RestoreResult

**Purpose**: Represents the outcome of a layout restore operation.

**Source**: Generated during restore execution, returned to caller.

**Lifecycle**: Created at restore start, populated during execution, returned as IPC response.

### Schema

```python
from pydantic import BaseModel, Field
from typing import List

class RestoreResult(BaseModel):
    """Represents outcome of layout restore operation."""
    
    status: str = Field(
        ...,
        description="Overall status: 'success', 'partial', or 'failed'",
        pattern="^(success|partial|failed)$"
    )
    
    apps_already_running: List[str] = Field(
        default_factory=list,
        description="Apps skipped because already present (idempotent behavior)"
    )
    
    apps_launched: List[str] = Field(
        default_factory=list,
        description="Apps successfully launched during restore"
    )
    
    apps_failed: List[str] = Field(
        default_factory=list,
        description="Apps that failed to launch (not in registry, launch error, etc.)"
    )
    
    elapsed_seconds: float = Field(
        ...,
        description="Total restore duration in seconds",
        ge=0.0
    )
    
    # Computed properties
    @property
    def total_apps(self) -> int:
        """Total apps in saved layout."""
        return len(self.apps_already_running) + len(self.apps_launched) + len(self.apps_failed)
    
    @property
    def success_rate(self) -> float:
        """Percentage of apps successfully handled (running + launched)."""
        if self.total_apps == 0:
            return 100.0
        successful = len(self.apps_already_running) + len(self.apps_launched)
        return (successful / self.total_apps) * 100
```

### Example Instance

```python
RestoreResult(
    status="success",
    apps_already_running=["terminal", "chatgpt-pwa"],
    apps_launched=["lazygit", "code"],
    apps_failed=[],
    elapsed_seconds=4.2
)

# Computed properties
result.total_apps  # → 4
result.success_rate  # → 100.0
```

### Status Logic

```python
def determine_status(result: RestoreResult) -> str:
    """Determine overall restore status."""
    if result.apps_failed:
        if result.apps_launched or result.apps_already_running:
            return "partial"  # Some succeeded, some failed
        else:
            return "failed"  # All failed
    else:
        return "success"  # No failures
```

---

## Data Flow

### Detection Phase

```
Sway IPC GET_TREE
    ↓
Extract PIDs
    ↓
Read /proc/<pid>/environ
    ↓
Extract I3PM_APP_NAME
    ↓
set[str] (running apps)
```

### Restore Phase

```
Load layout JSON
    ↓
Parse SavedWindow instances
    ↓
Detect running apps (set[str])
    ↓
Filter: skip if in running set
    ↓
Launch missing apps
    ↓
Build RestoreResult
    ↓
Return to caller
```

---

## Type Aliases

```python
from typing import TypeAlias

# Type aliases for clarity
AppName: TypeAlias = str  # e.g., "terminal", "lazygit"
WorkspaceNum: TypeAlias = int  # 1-70
ContainerId: TypeAlias = int  # Sway container ID
ProcessId: TypeAlias = int  # Linux PID
```

---

## Validation Rules

### App Name Validation

- **Format**: Lowercase alphanumeric + hyphens (kebab-case or reverse-domain)
- **Pattern**: `^[a-z0-9.-]+$`
- **Examples**: `terminal`, `chatgpt-pwa`, `com.mitchellh.ghostty`
- **Validated by**: Nix build (app-registry-data.nix lines 383-394)

### Workspace Number Validation

- **Range**: 1-70 (inclusive)
- **Rationale**: Standard workspaces (1-49) + PWA workspaces (50-64) + buffer
- **Validated by**: Pydantic `ge=1, le=70` constraint

### Path Validation

- **Type**: `pathlib.Path` (preferred over `str` for type safety)
- **Relative paths**: Resolved relative to `I3PM_PROJECT_DIR`
- **Example**: `cwd="."` → resolved to `/etc/nixos` for nixos project

---

## Error Handling

### Invalid App Name

```python
try:
    saved_window = SavedWindow(**window_data)
except ValidationError as e:
    logger.error(f"Invalid window data: {e}")
    # Skip window, add to apps_failed
    result.apps_failed.append(window_data.get("app_registry_name", "unknown"))
```

### Missing I3PM_APP_NAME

```python
try:
    env_text = Path(f"/proc/{pid}/environ").read_bytes()
except FileNotFoundError:
    # Process died - skip gracefully
    continue
except PermissionError:
    # Permission denied - skip gracefully
    logger.warning(f"Cannot read environ for PID {pid}")
    continue
```

---

## Testing Considerations

### Unit Tests

```python
def test_running_app_validation():
    """Test RunningApp Pydantic validation."""
    app = RunningApp(
        app_name="terminal",
        window_id=84,
        pid=224082,
        workspace=5
    )
    assert app.app_name == "terminal"
    assert app.workspace == 5

def test_restore_result_computed_properties():
    """Test RestoreResult computed properties."""
    result = RestoreResult(
        status="success",
        apps_already_running=["terminal", "firefox"],
        apps_launched=["code"],
        apps_failed=[],
        elapsed_seconds=3.5
    )
    assert result.total_apps == 3
    assert result.success_rate == 100.0
```

### Integration Tests

```python
async def test_detect_and_launch_idempotent():
    """Test complete detect → launch → verify flow."""
    # Setup: Launch terminal
    await launch_app("terminal", workspace=1)
    
    # Detect running apps
    running = await detect_running_apps()
    assert "terminal" in running
    
    # Restore layout (should skip terminal)
    result = await restore_layout("nixos", "test-layout")
    assert "terminal" in result.apps_already_running
    assert "terminal" not in result.apps_launched
```

---

## Summary

| Entity | Purpose | Source | Lifetime |
|--------|---------|--------|----------|
| RunningApp | Current window state | Sway IPC + /proc | Ephemeral (per restore) |
| SavedWindow | Desired window state | Layout JSON file | Persistent |
| RestoreResult | Restore outcome | Generated | Ephemeral (returned to caller) |

**Key Insights**:
- Set-based detection uses `set[str]` not `List[RunningApp]` (performance)
- SavedWindow uses `app_registry_name` not `I3PM_APP_NAME` (registry key)
- RestoreResult provides both lists and computed metrics (success rate)

**Next**: Define IPC API contract in [contracts/restore-api.md](contracts/restore-api.md)
