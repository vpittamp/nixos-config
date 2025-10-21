# Technology Research & Decisions: i3 Project Management System

**Branch**: `019-re-explore-and` | **Date**: 2025-10-20 | **Phase**: Phase 0 Research
**Plan**: [plan.md](./plan.md) | **Spec**: [spec.md](./spec.md)

## Summary

This document consolidates research findings for five key technology decisions required to implement the unified i3 project management system (`i3pm`). All decisions prioritize alignment with existing Python development standards (Principle X) and i3 IPC integration patterns (Principle XI).

## Research Questions

1. **Textual Framework Patterns** - Multi-screen app navigation and async integration
2. **pytest-textual Best Practices** - TUI testing strategies
3. **Layout Serialization Format** - i3 native vs custom format
4. **Shell Completion Generation** - argcomplete vs manual scripting
5. **Migration Strategy** - Integrating existing i3-project-monitor code

---

## 1. Textual Framework Patterns for Multi-Screen Apps

### Decision: Use Screen Stack Pattern with Reactive Attributes

**Rationale**:
- Textual's screen stack (`push_screen`/`pop_screen`) provides clean navigation hierarchy
- Reactive attributes auto-update UI when data changes (no manual refresh)
- `@work` decorator handles async operations without blocking UI
- Built on Rich (already used in i3-project-monitor)

### Implementation Patterns

#### Screen Navigation

```python
from textual.app import App
from textual.screen import Screen

class I3PMApp(App):
    """Main TUI application."""

    def on_mount(self) -> None:
        """Show project browser on startup."""
        self.push_screen(ProjectBrowserScreen())

    def show_editor(self, project_name: str) -> None:
        """Navigate to project editor with callback."""
        def on_editor_closed(updated_project: Optional[Project]) -> None:
            if updated_project:
                self.refresh_browser()

        self.push_screen(
            ProjectEditorScreen(project_name),
            callback=on_editor_closed
        )

class ProjectBrowserScreen(Screen):
    """Default screen - project list."""

    def on_key(self, event: events.Key) -> None:
        """Handle keyboard shortcuts."""
        if event.key == "e":
            selected = self.query_one(ProjectTable).selected_project
            self.app.show_editor(selected)
        elif event.key == "q":
            self.app.exit()
```

#### Reactive Data Binding

```python
from textual.reactive import reactive
from textual.widgets import Static

class ProjectStatusWidget(Static):
    """Display active project with auto-updates."""

    # Reactive attribute - UI updates automatically
    active_project: reactive[Optional[str]] = reactive(None)

    def watch_active_project(self, old: Optional[str], new: Optional[str]) -> None:
        """Called when active_project changes."""
        if new:
            self.update(f"Active: {new}")
        else:
            self.update("No active project")

# Usage: widget.active_project = "nixos"  # UI updates automatically
```

#### Async Operations (Non-Blocking)

```python
from textual.worker import work
from textual.widgets import LoadingIndicator

class LayoutManagerScreen(Screen):
    """Layout save/restore screen."""

    @work(exclusive=True, thread=True)
    async def save_layout(self, project_name: str) -> ProjectLayout:
        """Save layout in background thread."""
        # Long-running i3 IPC queries won't block UI
        i3 = await i3ipc.aio.Connection().connect()
        tree = await i3.get_tree()

        # Process tree and create layout
        layout = await self._capture_layout(tree, project_name)
        return layout

    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle save button click."""
        if event.button.id == "save":
            # Show loading indicator
            self.query_one("#status", LoadingIndicator).visible = True

            # Start async worker
            worker = self.save_layout(self.project_name)
            worker.finished.connect(self.on_layout_saved)

    def on_layout_saved(self, layout: ProjectLayout) -> None:
        """Called when save completes."""
        self.query_one("#status", LoadingIndicator).visible = False
        self.notify(f"Layout saved: {layout.name}")
```

#### Data Table Pattern (Project Browser)

```python
from textual.widgets import DataTable

class ProjectBrowserScreen(Screen):
    """Project list with search/filter."""

    def compose(self) -> ComposeResult:
        """Build UI components."""
        yield Header()
        yield Input(placeholder="Search projects...", id="search")
        yield DataTable(id="projects")
        yield Footer()

    def on_mount(self) -> None:
        """Initialize table."""
        table = self.query_one("#projects", DataTable)
        table.add_columns("Name", "Directory", "Apps", "Modified")
        table.cursor_type = "row"

        # Load projects
        self.refresh_projects()

    async def refresh_projects(self, filter: str = "") -> None:
        """Load projects from disk."""
        table = self.query_one("#projects", DataTable)
        table.clear()

        projects = await load_all_projects()  # From core.project
        for p in projects:
            if filter.lower() in p.name.lower():
                table.add_row(
                    p.display_name,
                    p.directory,
                    str(len(p.scoped_classes)),
                    p.last_modified.strftime("%Y-%m-%d")
                )
```

### Key Patterns Summary

| Pattern | Use Case | Example |
|---------|----------|---------|
| Screen Stack | Multi-screen navigation | `push_screen(EditorScreen)` |
| Reactive Attributes | Auto-updating displays | `active_project: reactive[str]` |
| @work Decorator | Async operations | `@work async def save_layout()` |
| Callbacks | Screen results | `push_screen(Editor, callback=on_done)` |
| DataTable | Project/window lists | `DataTable.add_row(...)` |
| Input + Filter | Search functionality | `on_input_changed` event |

### Performance Considerations

- **Target**: <50ms keyboard response (SC-016)
- **Strategy**: Use `@work(thread=True)` for i3 IPC queries (offload to thread pool)
- **Validation**: Use Textual DevTools to measure render time

---

## 2. pytest-textual Best Practices for TUI Testing

### Decision: Multi-Layer Testing Strategy

**Test Layers**:
1. **Unit Tests** - Core logic (project CRUD, layout serialization)
2. **Snapshot Tests** - TUI screen rendering (visual regression)
3. **Integration Tests** - Full workflows (create project → edit → save)

### Implementation Strategy

#### Unit Tests (Fast, Isolated)

```python
# tests/test_core/test_project.py
import pytest
from i3_project_manager.core.project import Project, load_project, save_project

@pytest.mark.asyncio
async def test_project_crud():
    """Test project create/read/update/delete."""
    # Create
    project = Project(
        name="test-project",
        directory="/tmp/test",
        scoped_classes=["Ghostty", "Code"]
    )
    await save_project(project)

    # Read
    loaded = await load_project("test-project")
    assert loaded.name == "test-project"
    assert loaded.directory == "/tmp/test"

    # Update
    loaded.scoped_classes.append("firefox")
    await save_project(loaded)

    # Delete
    await delete_project("test-project")
    with pytest.raises(FileNotFoundError):
        await load_project("test-project")
```

#### Snapshot Tests (Screen Rendering)

```python
# tests/test_tui/test_browser.py
from textual.pilot import Pilot
from i3_project_manager.tui.app import I3PMApp

async def test_browser_screen_render(snap_compare):
    """Test project browser renders correctly."""
    app = I3PMApp()

    async with app.run_test() as pilot:
        # Take snapshot of initial render
        assert await snap_compare(app, "browser_initial.svg")

        # Navigate to editor
        await pilot.press("e")
        assert await snap_compare(app, "browser_editor_opened.svg")
```

**Rationale**: Snapshot tests catch visual regressions (layout changes, color schemes, alignment issues) that unit tests miss.

#### Integration Tests (Full Workflows)

```python
# tests/test_tui/test_project_workflow.py
import pytest
from textual.pilot import Pilot
from i3_project_manager.tui.app import I3PMApp

@pytest.mark.asyncio
async def test_create_and_edit_project():
    """Test full project creation workflow."""
    app = I3PMApp()

    async with app.run_test() as pilot:
        # Start wizard
        await pilot.press("n")

        # Step 1: Basic info
        await pilot.press(*"nixos")  # Type project name
        await pilot.press("tab")
        await pilot.press(*"/etc/nixos")  # Type directory
        await pilot.press("enter")

        # Step 2: Application selection
        await pilot.press("space")  # Select Ghostty
        await pilot.press("down", "space")  # Select Code
        await pilot.press("enter")

        # Step 3: Auto-launch
        await pilot.press("enter")  # Skip for now

        # Step 4: Review & save
        await pilot.press("enter")

        # Verify project was created
        from i3_project_manager.core.project import load_project
        project = await load_project("nixos")
        assert project.name == "nixos"
        assert project.directory == "/etc/nixos"
        assert "Ghostty" in project.scoped_classes
```

### Mocking Strategy

**Mock i3 IPC for predictable tests**:

```python
# tests/conftest.py
import pytest
from unittest.mock import AsyncMock, MagicMock

@pytest.fixture
def mock_i3_connection():
    """Mock i3ipc connection."""
    mock = AsyncMock()

    # Mock GET_TREE response
    mock.get_tree.return_value = MagicMock(
        nodes=[
            MagicMock(
                type="workspace",
                name="1",
                nodes=[
                    MagicMock(
                        window=12345,
                        window_class="Ghostty",
                        marks=["project:nixos"]
                    )
                ]
            )
        ]
    )

    # Mock GET_MARKS response
    mock.get_marks.return_value = ["project:nixos", "project:stacks"]

    return mock

@pytest.fixture(autouse=True)
def patch_i3_connection(monkeypatch, mock_i3_connection):
    """Auto-patch i3ipc for all tests."""
    monkeypatch.setattr(
        "i3ipc.aio.Connection",
        lambda: mock_i3_connection
    )
```

### Testing Checklist

- [ ] **Core Library**: 100% coverage of project.py, layout.py, config.py
- [ ] **CLI Commands**: Test all subcommands with `--help`, `--json`, error cases
- [ ] **TUI Screens**: Snapshot tests for all 5 screens + navigation paths
- [ ] **Integration**: End-to-end workflows (create → edit → save → restore)
- [ ] **Performance**: Assert async operations complete within SC targets (<50ms, <500ms, <5s)

---

## 3. Layout Serialization Format: i3 Native vs Custom

### Decision: Custom JSON Format Using i3ipc

**Rejected Alternative**: i3's native layout save/restore (`i3-save-tree`, `append_layout`)

**Reasons for Rejection**:
1. **Manual Editing Required**: i3's native format requires hand-editing JSON to add swallow rules
2. **No Mark Matching**: Cannot use i3 marks for window matching (only class/title/instance)
3. **Multi-Monitor Limitations**: Static output names don't adapt to monitor changes
4. **Complex Restore**: Requires precise window launch order and swallow timing

**Advantages of Custom Format**:
1. **Mark-Based Matching**: Use `project:name` marks for reliable window identification
2. **Adaptive Multi-Monitor**: Logical positions (primary/secondary) adapt to available monitors
3. **Programmatic Creation**: No manual JSON editing, generated from live i3 state
4. **Integrated Restoration**: Same Python code used for project switching

### Custom Format Structure

```json
{
  "layout_version": "1.0",
  "project_name": "nixos",
  "saved_at": "2025-10-20T14:30:00Z",
  "workspaces": [
    {
      "number": 1,
      "output_role": "primary",
      "windows": [
        {
          "class": "Ghostty",
          "title": "nvim /etc/nixos/flake.nix",
          "geometry": {
            "width": 1920,
            "height": 1080,
            "x": 0,
            "y": 0
          },
          "layout_role": "main",
          "launch_command": "ghostty",
          "launch_env": {
            "PROJECT_DIR": "/etc/nixos"
          },
          "expected_marks": ["project:nixos"]
        }
      ]
    },
    {
      "number": 2,
      "output_role": "secondary",
      "windows": [
        {
          "class": "Code",
          "title": "/etc/nixos - Visual Studio Code",
          "geometry": {"width": 2560, "height": 1440, "x": 1920, "y": 0},
          "layout_role": "editor",
          "launch_command": "code /etc/nixos",
          "expected_marks": ["project:nixos"]
        }
      ]
    }
  ],
  "metadata": {
    "total_windows": 2,
    "monitor_config": "dual",
    "created_by": "i3pm save-layout"
  }
}
```

### Restoration Algorithm

**Sequential Launch Approach** (not swallow-based):

```python
async def restore_layout(layout: ProjectLayout) -> None:
    """Restore layout by launching applications sequentially."""
    i3 = await i3ipc.aio.Connection().connect()

    # 1. Switch to project (marks windows automatically via daemon)
    await switch_project(layout.project_name)

    # 2. Get current output assignments
    outputs = await i3.get_outputs()
    output_map = assign_logical_outputs(outputs)  # primary/secondary mapping

    # 3. Launch applications workspace-by-workspace
    for ws_layout in layout.workspaces:
        target_output = output_map.get(ws_layout.output_role, "primary")

        # Focus workspace on target output
        await i3.command(f"workspace {ws_layout.number}")

        # Launch windows sequentially
        for window in ws_layout.windows:
            # Set environment for launch
            env = {**os.environ, **window.launch_env}

            # Launch application
            subprocess.Popen(window.launch_command, env=env, shell=True)

            # Wait for window to appear with project mark (via daemon)
            await wait_for_window_with_mark(
                f"project:{layout.project_name}",
                timeout=5.0
            )

            # Apply layout hints if needed
            if window.layout_role == "main":
                await i3.command("split h")

    # 4. Return to first workspace
    await i3.command("workspace 1")
```

### Trade-offs Accepted

| Trade-off | Impact | Mitigation |
|-----------|--------|------------|
| Not pixel-perfect restore | Windows may have different sizes | Use i3 layout commands (split h/v) for structure |
| Launch timing dependency | Must wait for windows to appear | 5s timeout with clear error messages |
| No cross-project layouts | Each layout tied to one project | Document this limitation in quickstart.md |

### Validation

- **Success Criteria**: SC-018 (Layout save/restore <5s for 10 windows)
- **Test Plan**: Automated test with mock i3 connection, measure sequential launch time
- **Error Handling**: If window doesn't appear within timeout, continue with next window + warning

---

## 4. Shell Completion Generation: argcomplete vs Manual

### Decision: Use argcomplete with Static Generation

**Rationale**:
1. **Auto-Sync**: Completions automatically match argparse structure (no manual maintenance)
2. **Dynamic Completion**: Can query project list, layout names at runtime
3. **Performance**: <50ms with static generation (meets SC-016 target)
4. **Standard Tool**: Widely used in Python CLI tools (e.g., pip, aws-cli)

### Implementation Pattern

#### CLI Setup with argcomplete

```python
# i3_project_manager/cli/commands.py
import argparse
import argcomplete

def create_parser() -> argparse.ArgumentParser:
    """Create CLI parser with completions."""
    parser = argparse.ArgumentParser(
        prog="i3pm",
        description="i3 project management CLI/TUI"
    )

    # Subcommands
    subparsers = parser.add_subparsers(dest="command", required=False)

    # i3pm switch <project>
    switch_parser = subparsers.add_parser("switch", help="Switch to project")
    switch_parser.add_argument(
        "project_name",
        help="Project to switch to"
    ).completer = complete_project_names  # Dynamic completion

    # i3pm edit <project>
    edit_parser = subparsers.add_parser("edit", help="Edit project configuration")
    edit_parser.add_argument("project_name").completer = complete_project_names

    # i3pm save-layout <project> <name>
    layout_parser = subparsers.add_parser("save-layout", help="Save current layout")
    layout_parser.add_argument("project_name").completer = complete_project_names
    layout_parser.add_argument("layout_name", help="Name for saved layout")

    # Enable argcomplete
    argcomplete.autocomplete(parser)

    return parser

def complete_project_names(prefix, parsed_args, **kwargs):
    """Dynamic completion for project names."""
    from i3_project_manager.core.project import list_projects
    projects = list_projects()  # Fast: just list ~/.config/i3/projects/*.json
    return [p.name for p in projects if p.name.startswith(prefix)]
```

#### Shell Integration

```bash
# In NixOS home-manager configuration
home.packages = [ pkgs.python3Packages.argcomplete ];

programs.bash.initExtra = ''
  # Enable i3pm completions
  eval "$(register-python-argcomplete i3pm)"
'';

# Generate static completions for faster startup (optional)
# register-python-argcomplete --shell bash i3pm > ~/.bash_completion.d/i3pm
```

### Performance Optimization

**Static Generation** (for common commands):

```bash
# Generate at build time
nix-shell -p python3Packages.argcomplete --run \
  "register-python-argcomplete i3pm > /etc/bash_completion.d/i3pm"
```

**Dynamic Completion** (for project/layout names):

```python
def complete_project_names(prefix, parsed_args, **kwargs):
    """Fast project name completion."""
    # Use cached project list (avoid slow JSON parsing)
    cache_file = Path.home() / ".cache/i3pm/project-list.txt"

    if cache_file.exists() and time.time() - cache_file.stat().st_mtime < 60:
        # Use cache if <60s old
        projects = cache_file.read_text().splitlines()
    else:
        # Regenerate cache
        projects = [p.stem for p in Path("~/.config/i3/projects").expanduser().glob("*.json")]
        cache_file.parent.mkdir(exist_ok=True)
        cache_file.write_text("\n".join(projects))

    return [p for p in projects if p.startswith(prefix)]
```

### Alternative Considered: Manual Scripts

**Rejected** because:
- Requires maintaining separate completion files for bash/zsh/fish
- Completions drift out of sync with argparse changes
- No support for dynamic completions (project names)

### Completion Coverage

| Command | Static | Dynamic | Example |
|---------|--------|---------|---------|
| `i3pm <subcommand>` | ✓ | - | `i3pm sw<TAB>` → `switch` |
| `i3pm switch <project>` | - | ✓ | `i3pm switch ni<TAB>` → `nixos` |
| `i3pm save-layout <project>` | - | ✓ | `i3pm save-layout st<TAB>` → `stacks` |
| `i3pm restore-layout <project> <layout>` | - | ✓ | `i3pm restore-layout nixos de<TAB>` → `default` |
| `i3pm --help` | ✓ | - | `i3pm --h<TAB>` → `--help` |

---

## 5. Migration Strategy for Existing i3-project-monitor Code

### Decision: Gradual Integration into Unified Package

**Approach**: Extract reusable components into `core/`, consolidate displays into single TUI screen

### Migration Map

#### Phase 1: Core Library Extraction (Week 1)

```
FROM: home-modules/tools/i3_project_monitor/
TO:   home-modules/tools/i3_project_manager/core/

daemon_client.py → core/daemon_client.py  (minor refactor)
  - Extract DaemonClient class
  - Add connection pooling for CLI commands
  - Keep JSON-RPC protocol unchanged

models.py → core/models.py  (extend)
  - Keep existing: MonitorState, EventRecord, WindowInfo
  - Add new: Project, SavedLayout, AutoLaunchApp

displays/*.py → tui/screens/monitor.py  (consolidate)
  - Merge 4 display modes into single screen with tabs
  - live_display.py → MonitorScreen(mode="live")
  - event_stream.py → MonitorScreen(mode="events")
  - history_view.py → MonitorScreen(mode="history")
  - tree_inspector.py → MonitorScreen(mode="tree")
```

#### Phase 2: CLI Command Migration (Week 2)

```
FROM: scripts/i3-project-*
TO:   i3_project_manager/cli/commands.py

i3-project-switch → i3pm switch
i3-project-list → i3pm list
i3-project-current → i3pm current
i3-project-monitor → i3pm monitor  (launches TUI)
```

#### Phase 3: Backward Compatibility (Optional)

```bash
# Create wrapper scripts in scripts/
#!/usr/bin/env bash
# scripts/i3-project-switch
exec i3pm switch "$@"

#!/usr/bin/env bash
# scripts/i3-project-monitor
exec i3pm monitor "$@"
```

**Note**: User said "don't worry about backwards compatibility" so this phase is optional.

### Code Reuse Strategy

#### DaemonClient (100% reusable)

```python
# core/daemon_client.py (extracted from i3_project_monitor)
import asyncio
import json
from pathlib import Path

class DaemonClient:
    """IPC client for i3-project-event-listener daemon."""

    def __init__(self, socket_path: Path = Path.home() / ".cache/i3-project/daemon.sock"):
        self.socket_path = socket_path
        self._reader: Optional[asyncio.StreamReader] = None
        self._writer: Optional[asyncio.StreamWriter] = None

    async def connect(self) -> None:
        """Connect to daemon socket."""
        self._reader, self._writer = await asyncio.open_unix_connection(self.socket_path)

    async def call(self, method: str, params: dict = None) -> dict:
        """Send JSON-RPC request to daemon."""
        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": 1
        }

        self._writer.write((json.dumps(request) + "\n").encode())
        await self._writer.drain()

        response_line = await self._reader.readline()
        response = json.loads(response_line.decode())

        if "error" in response:
            raise DaemonError(response["error"]["message"])

        return response["result"]

    async def get_status(self) -> dict:
        """Get daemon status."""
        return await self.call("get_status")

    async def get_active_project(self) -> Optional[str]:
        """Get current active project."""
        status = await self.call("get_status")
        return status.get("active_project")

    async def close(self) -> None:
        """Close connection."""
        if self._writer:
            self._writer.close()
            await self._writer.wait_closed()
```

#### Models (Extend existing)

```python
# core/models.py
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional
from pathlib import Path

# Existing models (keep unchanged)
@dataclass
class MonitorState:
    daemon_connected: bool
    daemon_uptime_seconds: float
    active_project: Optional[str] = None
    total_windows: int = 0
    tracked_windows: int = 0

@dataclass
class EventRecord:
    timestamp: datetime
    event_type: str
    details: dict

# New models for project management
@dataclass
class Project:
    name: str
    directory: Path
    scoped_classes: List[str]
    display_name: Optional[str] = None
    icon: Optional[str] = None
    auto_launch: List[dict] = None  # AutoLaunchApp configs
    saved_layouts: List[str] = None  # Layout names

    def to_json(self) -> dict:
        """Serialize for ~/.config/i3/projects/{name}.json."""
        return {
            "name": self.name,
            "directory": str(self.directory),
            "scoped_classes": self.scoped_classes,
            "display_name": self.display_name or self.name,
            "icon": self.icon or "",
            "auto_launch": self.auto_launch or [],
            "saved_layouts": self.saved_layouts or []
        }
```

#### Monitor Screen Consolidation

```python
# tui/screens/monitor.py (consolidate 4 old displays)
from textual.screen import Screen
from textual.widgets import TabbedContent, TabPane, DataTable, RichLog

class MonitorScreen(Screen):
    """Unified monitoring dashboard with tabs."""

    def compose(self) -> ComposeResult:
        """Build tabbed interface."""
        with TabbedContent():
            with TabPane("Live", id="live"):
                yield DataTable(id="live_table")  # From old live_display.py

            with TabPane("Events", id="events"):
                yield RichLog(id="event_stream")  # From old event_stream.py

            with TabPane("History", id="history"):
                yield DataTable(id="history_table")  # From old history_view.py

            with TabPane("Tree", id="tree"):
                yield RichLog(id="tree_view")  # From old tree_inspector.py

        yield Footer()

    def on_mount(self) -> None:
        """Start live updates."""
        self.set_interval(1.0, self.refresh_live_data)

    async def refresh_live_data(self) -> None:
        """Update live tab (only if visible)."""
        if self.query_one(TabbedContent).active == "live":
            # Reuse logic from old live_display.py
            status = await self.daemon_client.get_status()
            self.update_live_table(status)
```

### Breaking Changes

**Minimal** - only affects internal imports:

| Old Import | New Import |
|------------|------------|
| `from i3_project_monitor.daemon_client import DaemonClient` | `from i3_project_manager.core.daemon_client import DaemonClient` |
| `from i3_project_monitor.models import MonitorState` | `from i3_project_manager.core.models import MonitorState` |

**No changes** to:
- Daemon JSON-RPC protocol
- Project JSON format (`~/.config/i3/projects/*.json`)
- App classification format (`~/.config/i3/app-classes.json`)

### Testing Migration

```python
# tests/test_core/test_daemon_client.py
# Reuse existing tests from i3_project_monitor
import pytest
from i3_project_manager.core.daemon_client import DaemonClient

@pytest.mark.asyncio
async def test_daemon_get_status(mock_daemon):
    """Test daemon status query."""
    client = DaemonClient()
    await client.connect()

    status = await client.get_status()
    assert status["daemon_connected"] is True
    assert "uptime_seconds" in status
```

---

## Summary of Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| **TUI Framework Pattern** | Screen stack + reactive attributes | Clean navigation, auto-updating UI, async-native |
| **TUI Testing** | Multi-layer (unit + snapshot + integration) | Fast feedback, visual regression detection, workflow coverage |
| **Layout Format** | Custom JSON (not i3 native) | Mark-based matching, adaptive multi-monitor, no manual editing |
| **Shell Completions** | argcomplete with static generation | Auto-sync with argparse, dynamic project names, <50ms performance |
| **Migration Strategy** | Gradual integration (core → CLI → TUI) | Minimal breaking changes, reuse existing code, phased rollout |

## Constitution Compliance

- ✅ **Principle X**: All decisions use Python 3.11+, async patterns, pytest framework
- ✅ **Principle XI**: Layout restoration uses i3 IPC (GET_TREE, GET_OUTPUTS), mark-based window identification
- ✅ **Principle III**: Multi-layer testing prevents regressions, snapshot tests validate UI
- ✅ **Principle VI**: Custom layout format is declarative JSON, not imperative i3 commands

## Performance Validation

| Success Criterion | Technology Decision | Validation Method |
|-------------------|---------------------|-------------------|
| SC-016: TUI <50ms keyboard | Textual reactive updates, @work async | Textual DevTools profiling |
| SC-017: Config validation <500ms | JSON Schema with caching | pytest benchmark fixture |
| SC-018: Layout restore <5s | Sequential launch with 5s timeout | Automated test with 10 mock windows |

## Next Steps

1. ✅ **Research complete** - All 5 questions answered with implementation patterns
2. **Phase 1**: Create data-model.md with entity definitions
3. **Phase 1**: Create contracts/ with CLI/TUI/daemon API contracts
4. **Phase 1**: Create quickstart.md with user guide
5. **Phase 2**: Run `/speckit.tasks` to generate implementation tasks

---

**Research Status**: ✅ Complete
**Constitution Check**: ✅ PASS
**Next Phase**: Phase 1 Design Artifacts
