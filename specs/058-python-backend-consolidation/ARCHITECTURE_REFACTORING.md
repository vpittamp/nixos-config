# Architecture Refactoring: TypeScript → Python Backend Operations

## Analysis: Current Architecture Issues

### Problem: Backend Logic in TypeScript

Several TypeScript services are performing **backend/daemon operations** that should be in Python:

#### 1. **layout-engine.ts** - DUPLICATE /proc Reading! ❌

**Location**: `/etc/nixos/home-modules/tools/i3pm/src/services/layout-engine.ts`

**Backend operations in TypeScript** (lines 101-121):
```typescript
private async readProcEnvironment(pid: number): Promise<Record<string, string>> {
  const envPath = `/proc/${pid}/environ`;
  const data = await Deno.readFile(envPath);
  // ... parsing logic ...
}
```

**Problem**: This **duplicates** our new Python module `window_environment.py`!
- Same functionality: Read /proc/<pid>/environ
- Same parsing logic: Split on null bytes, parse key=value
- Different implementation: TypeScript vs Python
- Maintenance burden: Two codebases to keep in sync

**Additional backend operations**:
- `getWindowPid()`: Shell out to xprop (lines 70-96)
- `getWindowTree()`: Shell out to i3-msg (lines 126-138)
- `captureLayout()`: Window state extraction (lines 160+)
- `restoreLayout()`: Window positioning logic
- File I/O: Save/load layouts to JSON

**Should be**: Python daemon functionality with TypeScript CLI as thin wrapper

#### 2. **project-manager.ts** - File I/O & Business Logic ⚠️

**Location**: `/etc/nixos/home-modules/tools/i3pm/src/services/project-manager.ts`

**Backend operations**:
- File I/O: Read/write project JSON files
- Directory validation: Check if paths exist
- Project CRUD: Create, update, delete projects
- Active project state: Read/write active-project.json
- Business logic: Project name validation, directory expansion

**Current flow**:
```
TypeScript CLI → File I/O → JSON files
      ↓
Python Daemon reads same JSON files
```

**Problem**: Two sources of truth, potential race conditions

**Should be**: Python daemon owns project state, TypeScript CLI just displays it

#### 3. **registry.ts** - Application Registry Access ⚠️

**Location**: `/etc/nixos/home-modules/tools/i3pm/src/services/registry.ts`

**Likely doing**: Reading app-registry.json for application lookups

**Problem**: If daemon also reads registry, we have duplicate registry parsing

**Should be**: Daemon owns registry, CLI queries daemon for app info

### Current Architecture (Before Refactoring)

```
┌─────────────────────────────────────────────────────────────┐
│                    TypeScript/Deno CLI                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ layout-engine.ts                                      │  │
│  │  - Read /proc/<pid>/environ ❌ DUPLICATE              │  │
│  │  - Shell out to i3-msg                                │  │
│  │  - Shell out to xprop                                 │  │
│  │  - Window state capture/restore                       │  │
│  │  - Layout file I/O                                    │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ project-manager.ts                                    │  │
│  │  - Project file I/O (create/read/update/delete)      │  │
│  │  - Active project state management                    │  │
│  │  - Directory validation                               │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ daemon-client.ts ✅ OK - Just communication           │  │
│  │  - JSON-RPC client                                    │  │
│  │  - Socket connection                                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    Both read JSON files
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     Python Daemon                           │
│  - i3 event handling                                        │
│  - Window matching (uses window_environment.py)             │
│  - Project filtering                                        │
│  - Also reads same JSON files ❌ DUPLICATE                  │
└─────────────────────────────────────────────────────────────┘
```

**Problems**:
1. **Duplicate /proc reading**: TypeScript AND Python read environment
2. **Duplicate file I/O**: Both read project JSON files
3. **No single source of truth**: State managed in two places
4. **Shell overhead**: TypeScript shelling out to i3-msg, xprop inefficient
5. **Race conditions**: Both can write to JSON files

### Recommended Architecture (After Refactoring)

```
┌─────────────────────────────────────────────────────────────┐
│              TypeScript/Deno CLI (Thin Client)              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ UI/Display Layer ONLY                                 │  │
│  │  - Table rendering (Rich library equiv)              │  │
│  │  - TUI interfaces (live views, dashboards)           │  │
│  │  - CLI argument parsing                               │  │
│  │  - Output formatting (JSON, tables, trees)           │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ daemon-client.ts ✅ Communication Layer               │  │
│  │  - Request: "i3pm layout save nixos"                 │  │
│  │  - Daemon: Performs operation, returns result        │  │
│  │  - CLI: Formats result for display                   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓ JSON-RPC
┌─────────────────────────────────────────────────────────────┐
│           Python Daemon (Backend/API Layer)                 │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Layout Management (NEW)                               │  │
│  │  - layout_engine.py                                   │  │
│  │  - capture_layout(project_name)                       │  │
│  │  - restore_layout(project_name)                       │  │
│  │  - Uses window_environment.py (no duplication)        │  │
│  │  - Direct i3ipc.aio (no shell commands)              │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Project Management (MOVED FROM TS)                    │  │
│  │  - project_manager.py                                 │  │
│  │  - create_project(), list_projects()                 │  │
│  │  - set_active_project(), get_active_project()        │  │
│  │  - Single source of truth for project state          │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Window Environment (EXISTING)                         │  │
│  │  - window_environment.py ✅                           │  │
│  │  - window_filter.py ✅                                │  │
│  │  - window_matcher.py ✅                               │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ IPC Server (EXISTING)                                 │  │
│  │  - JSON-RPC 2.0 server                                │  │
│  │  - Exposes daemon operations to CLI                   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Benefits**:
1. **Single source of truth**: Daemon owns all state
2. **No duplication**: One implementation of /proc reading, layout logic, etc.
3. **Efficient**: Direct i3ipc.aio (no shell commands)
4. **Clean separation**: TypeScript = UI, Python = backend
5. **Better performance**: Native Python-i3 communication

## Refactoring Plan

### Phase 1: Move Layout Engine to Python

**Goal**: Replace `layout-engine.ts` with Python implementation

#### 1.1 Create `layout_engine.py` in Python daemon

**Location**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/layout_engine.py`

**Functionality**:
```python
from window_environment import get_window_environment, read_process_environ
import i3ipc.aio as i3ipc
import json
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict

@dataclass
class WindowSnapshot:
    """Window state snapshot for layout restore."""
    window_id: int
    app_id: str  # I3PM_APP_ID from environment
    app_name: str  # I3PM_APP_NAME
    window_class: str  # For validation
    title: str
    workspace: int
    output: str
    rect: Dict[str, int]  # x, y, width, height
    floating: bool
    focused: bool

@dataclass
class Layout:
    """Complete layout snapshot."""
    project_name: str
    layout_name: str
    timestamp: str
    windows: List[WindowSnapshot]

async def capture_layout(
    i3: i3ipc.Connection,
    project_name: str,
    layout_name: Optional[str] = None
) -> Layout:
    """
    Capture current window layout using environment-based identification.

    Uses I3PM_APP_ID and I3PM_APP_NAME from window_environment.py.
    No duplication - leverages existing Feature 057 modules.
    """
    tree = await i3.get_tree()
    windows = tree.leaves()

    snapshots = []
    for window in windows:
        if not window.pid:
            continue

        # Use Feature 057 modules (no duplication!)
        result = await get_window_environment(window.id, window.pid)
        if result.environment is None:
            continue

        env = result.environment

        snapshot = WindowSnapshot(
            window_id=window.id,
            app_id=env.app_id,
            app_name=env.app_name,
            window_class=window.window_class or "",
            title=window.name or "",
            workspace=window.workspace().num,
            output=window.ipc_data.get("output", ""),
            rect={
                "x": window.rect.x,
                "y": window.rect.y,
                "width": window.rect.width,
                "height": window.rect.height,
            },
            floating=window.floating != "auto_off",
            focused=window.focused,
        )
        snapshots.append(snapshot)

    layout = Layout(
        project_name=project_name,
        layout_name=layout_name or project_name,
        timestamp=datetime.now().isoformat(),
        windows=snapshots,
    )

    return layout

async def restore_layout(
    i3: i3ipc.Connection,
    layout: Layout
) -> Dict[str, Any]:
    """
    Restore layout by matching windows via I3PM_APP_ID.

    Uses environment-based matching - deterministic, no class ambiguity.
    """
    # Get current windows
    tree = await i3.get_tree()
    current_windows = tree.leaves()

    # Build map of current windows by APP_ID
    app_id_to_window = {}
    for window in current_windows:
        if not window.pid:
            continue

        result = await get_window_environment(window.id, window.pid)
        if result.environment:
            app_id_to_window[result.environment.app_id] = window

    # Restore each window from snapshot
    restored = 0
    missing = []

    for snapshot in layout.windows:
        if snapshot.app_id in app_id_to_window:
            window = app_id_to_window[snapshot.app_id]

            # Move to correct workspace
            await window.command(f"move to workspace number {snapshot.workspace}")

            # Restore floating state and geometry
            if snapshot.floating:
                await window.command("floating enable")
                rect = snapshot.rect
                await window.command(
                    f"resize set {rect['width']} px {rect['height']} px"
                )
                await window.command(
                    f"move absolute position {rect['x']} px {rect['y']} px"
                )

            restored += 1
        else:
            missing.append({
                "app_id": snapshot.app_id,
                "app_name": snapshot.app_name,
                "workspace": snapshot.workspace,
            })

    return {
        "restored": restored,
        "missing": missing,
        "total": len(layout.windows),
    }
```

#### 1.2 Add IPC methods to daemon

**Location**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/ipc_server.py`

```python
from .layout_engine import capture_layout, restore_layout, save_layout, load_layout

# Add to IPC method registry:
async def handle_layout_save(params):
    """Handle layout save request from CLI."""
    project_name = params["project_name"]
    layout_name = params.get("layout_name")

    layout = await capture_layout(self.i3, project_name, layout_name)
    await save_layout(layout)

    return {
        "project": project_name,
        "layout_name": layout.layout_name,
        "windows_captured": len(layout.windows),
    }

async def handle_layout_restore(params):
    """Handle layout restore request from CLI."""
    project_name = params["project_name"]
    layout_name = params.get("layout_name")

    layout = await load_layout(project_name, layout_name)
    result = await restore_layout(self.i3, layout)

    return result
```

#### 1.3 Update TypeScript CLI to be thin client

**Location**: `/etc/nixos/home-modules/tools/i3pm/src/commands/layout.ts`

**Before** (backend logic in TypeScript):
```typescript
// layout-engine.ts does all the work
const engine = new LayoutEngine();
await engine.captureLayout(projectName);  // ❌ Backend in TS
```

**After** (thin client, daemon does work):
```typescript
// Just request daemon to do the work
const client = new DaemonClient();
await client.connect();
const result = await client.request("layout_save", {
  project_name: projectName,
  layout_name: layoutName
});  // ✅ CLI just displays result

// Display result beautifully (TypeScript UI strength)
console.log(`✓ Layout saved: ${result.layout_name}`);
console.log(`  Windows captured: ${result.windows_captured}`);
```

### Phase 2: Move Project Management to Python

**Goal**: Replace `project-manager.ts` with Python implementation

#### 2.1 Create `project_manager.py`

**Location**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/project_manager.py`

```python
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
import json

@dataclass
class Project:
    """Project definition."""
    name: str
    directory: str
    display_name: str
    icon: str
    created_at: str
    updated_at: str

class ProjectManager:
    """Manage projects with single source of truth."""

    def __init__(self, config_dir: Path):
        self.projects_dir = config_dir / "projects"
        self.active_project_path = config_dir / "active-project.json"
        self.projects_dir.mkdir(parents=True, exist_ok=True)

    async def create_project(
        self,
        name: str,
        directory: str,
        display_name: str,
        icon: str
    ) -> Project:
        """Create new project (single source of truth)."""
        # Validation
        if not self._validate_name(name):
            raise ValueError(f"Invalid project name: {name}")

        if not Path(directory).exists():
            raise ValueError(f"Directory does not exist: {directory}")

        # Create project
        project = Project(
            name=name,
            directory=directory,
            display_name=display_name,
            icon=icon,
            created_at=datetime.now().isoformat(),
            updated_at=datetime.now().isoformat(),
        )

        # Save to file
        project_path = self.projects_dir / f"{name}.json"
        with open(project_path, "w") as f:
            json.dump(asdict(project), f, indent=2)

        return project

    async def list_projects(self) -> List[Project]:
        """List all projects."""
        projects = []
        for project_file in self.projects_dir.glob("*.json"):
            with open(project_file) as f:
                data = json.load(f)
                projects.append(Project(**data))
        return projects

    async def get_active_project(self) -> Optional[str]:
        """Get currently active project name."""
        if not self.active_project_path.exists():
            return None

        with open(self.active_project_path) as f:
            data = json.load(f)
            return data.get("name")

    async def set_active_project(self, project_name: Optional[str]) -> None:
        """Set active project (triggers window filtering)."""
        # Save active project
        with open(self.active_project_path, "w") as f:
            json.dump({"name": project_name}, f)

        # Trigger window filtering via window_filter.py
        from .window_filter import apply_project_filtering
        await apply_project_filtering(self.i3, project_name)
```

#### 2.2 Update TypeScript CLI

**Before**:
```typescript
const manager = new ProjectManager();
await manager.createProject({...});  // ❌ File I/O in TS
```

**After**:
```typescript
const client = new DaemonClient();
const result = await client.request("project_create", {
  name: "nixos",
  directory: "/etc/nixos",
  display_name: "NixOS",
  icon: "❄️"
});  // ✅ Daemon does the work

console.log(`✓ Project created: ${result.name}`);
```

### Phase 3: Remove Duplicate Code

After Phases 1-2:

1. **Delete** `layout-engine.ts` (replaced by Python)
2. **Delete** `project-manager.ts` (replaced by Python)
3. **Keep** `daemon-client.ts` (communication layer)
4. **Keep** UI/display TypeScript (tables, trees, formatting)

**Result**: ~1000+ lines of TypeScript deleted, replaced by ~500 lines of Python

### Phase 4: Verify No Other Duplications

**Files to check**:
- `registry.ts` - Should just query daemon for app info
- `validation.ts` - If backend validation, move to Python

## Expected Benefits

### Performance
- **Layout operations**: Direct i3ipc.aio (no shell commands) = 10-20x faster
- **Project operations**: In-process (no JSON-RPC roundtrip for daemon)
- **/proc reading**: No duplication (one implementation)

### Maintainability
- **Single source of truth**: Daemon owns state
- **No duplication**: One /proc reader, one layout engine, one project manager
- **Clear separation**: TypeScript = UI, Python = backend

### Code Quality
- **Less code**: ~1000 lines of TypeScript removed
- **Better types**: Python type hints + Pydantic validation
- **Better testing**: Python test suite (pytest) for backend logic

### Architecture
- **Clean layers**:
  - TypeScript: CLI argument parsing + display formatting
  - Python: Backend operations + state management
  - JSON-RPC: Clean contract between layers

## Migration Checklist

- [ ] Create `layout_engine.py` in Python daemon
- [ ] Add layout IPC methods to `ipc_server.py`
- [ ] Update `layout.ts` command to use daemon client
- [ ] Create `project_manager.py` in Python daemon
- [ ] Add project IPC methods to `ipc_server.py`
- [ ] Update `project.ts` command to use daemon client
- [ ] Test all CLI commands work via daemon
- [ ] Delete `layout-engine.ts`
- [ ] Delete `project-manager.ts`
- [ ] Update documentation
- [ ] Verify ~1000 lines removed from TypeScript

## Timeline

- **Phase 1** (Layout): 4-6 hours
- **Phase 2** (Projects): 3-4 hours
- **Phase 3** (Cleanup): 1-2 hours
- **Total**: 8-12 hours

**Priority**: High - Eliminates duplication, improves performance, better architecture

---

**Last Updated**: 2025-11-03
**Status**: Ready for implementation
**Estimated Effort**: 8-12 hours
**Estimated Lines Removed**: ~1000 TypeScript lines
**Estimated Lines Added**: ~500 Python lines
