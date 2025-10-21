# Textual Framework Patterns - Research Findings

**Date**: 2025-10-20
**Context**: Building unified i3 project management TUI with 5 screens (Browser, Editor, Monitor, Layout Manager, Wizard)
**Framework**: Textual v0.80+ (Python TUI framework)

---

## Executive Summary

Textual is a mature, production-ready TUI framework with comprehensive async support, reactive data binding, and excellent testing tools. Based on research of official documentation, real-world applications, and community best practices, here are the key decisions and patterns for building a multi-screen i3 project management application.

---

## 1. Screen Management Patterns

### Decision: Use `push_screen`/`pop_screen` Stack Pattern

**Rationale**:
- Stack-based navigation provides natural hierarchical flow (Browser → Editor → nested modals)
- Built-in back navigation with screen history
- Modal screens work seamlessly with stack pattern
- Easier state management - screens can return results to callers

**Alternative Considered**: `switch_screen` (replaces current screen)
- **Rejected**: Less intuitive for nested navigation, loses screen history

### Implementation Pattern

```python
from textual.app import App
from textual.screen import Screen, ModalScreen

class ProjectBrowserScreen(Screen):
    """Main screen - project list"""
    BINDINGS = [
        ("e", "edit_project", "Edit Project"),
        ("n", "new_project", "New Project"),
    ]

    def action_edit_project(self) -> None:
        # Get selected project
        project = self.query_one(DataTable).get_row_at(self.cursor_row)
        # Push editor screen with callback
        self.app.push_screen(
            ProjectEditorScreen(project),
            callback=self.on_project_edited
        )

    def on_project_edited(self, result: dict | None) -> None:
        """Called when editor screen is dismissed"""
        if result:
            self.refresh_project_list()

class ProjectEditorScreen(Screen):
    """Editor screen - form for editing project"""
    BINDINGS = [
        ("escape", "cancel", "Cancel"),
        ("ctrl+s", "save", "Save"),
    ]

    def __init__(self, project: dict) -> None:
        super().__init__()
        self.project = project

    def action_save(self) -> None:
        # Validate and collect form data
        updated_project = self.collect_form_data()
        # Dismiss screen with result
        self.dismiss(updated_project)

    def action_cancel(self) -> None:
        self.dismiss(None)  # No changes

class ConfirmDeleteModal(ModalScreen[bool]):
    """Confirmation modal - returns bool"""

    def compose(self) -> ComposeResult:
        yield Container(
            Label("Delete this project?"),
            Horizontal(
                Button("Delete", variant="error", id="confirm"),
                Button("Cancel", id="cancel"),
            ),
            id="dialog"
        )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "confirm":
            self.dismiss(True)
        else:
            self.dismiss(False)
```

### Screen Installation

```python
class I3ProjectApp(App):
    """Install screens at app initialization"""

    SCREENS = {
        "browser": ProjectBrowserScreen,
        "editor": ProjectEditorScreen,
        "monitor": MonitorScreen,
        "layout": LayoutManagerScreen,
    }

    def on_mount(self) -> None:
        # Start with browser screen
        self.push_screen("browser")
```

### Best Practices

1. **Always provide screen type hints** for ModalScreen callbacks: `ModalScreen[bool]`, `ModalScreen[dict]`
2. **Use callbacks for screen results** instead of global state
3. **Keep screen stack shallow** (3-4 levels max) to avoid user confusion
4. **Provide escape routes** - always bind `escape` to go back
5. **Use ModalScreen for temporary dialogs** that don't need full navigation

---

## 2. Reactive Data Binding

### Decision: Use Reactive Attributes + Watch Methods

**Rationale**:
- Declarative - clear data flow
- Automatic refresh triggers
- Type-safe with proper hints
- Validation support built-in

**Alternative Considered**: Manual refresh calls
- **Rejected**: Error-prone, requires manual refresh tracking, harder to maintain

### Implementation Pattern

```python
from textual.reactive import reactive, var
from textual.widgets import DataTable, Label

class ProjectBrowserScreen(Screen):
    """Screen with reactive project list"""

    # Reactive attributes
    projects: reactive[list[dict]] = reactive([], init=False)
    filter_text: reactive[str] = reactive("")
    selected_project: reactive[dict | None] = reactive(None)

    def compose(self) -> ComposeResult:
        yield Input(placeholder="Filter projects...", id="filter")
        yield DataTable(id="projects-table")
        yield Label(id="status")

    def on_mount(self) -> None:
        # Initialize data
        self.load_projects()

    @work(exclusive=True)
    async def load_projects(self) -> None:
        """Load projects asynchronously"""
        # Fetch from i3 IPC or file system
        projects = await fetch_projects_async()
        self.projects = projects  # Triggers watch_projects

    def watch_projects(self, projects: list[dict]) -> None:
        """Called when self.projects changes"""
        table = self.query_one(DataTable)
        table.clear()

        # Filter by search text
        filtered = [
            p for p in projects
            if self.filter_text.lower() in p["name"].lower()
        ]

        # Update table
        for project in filtered:
            table.add_row(
                project["name"],
                project["directory"],
                project["status"],
                key=project["id"]
            )

    def watch_filter_text(self, filter_text: str) -> None:
        """Re-filter when search changes"""
        self.watch_projects(self.projects)  # Re-run filter

    def on_input_changed(self, event: Input.Changed) -> None:
        """Update filter on input"""
        if event.input.id == "filter":
            self.filter_text = event.value

    def watch_selected_project(self, project: dict | None) -> None:
        """Update status label when selection changes"""
        label = self.query_one("#status", Label)
        if project:
            label.update(f"Selected: {project['name']}")
        else:
            label.update("No project selected")
```

### Computed Reactive Values

```python
class MonitorScreen(Screen):
    """Real-time monitoring with computed reactives"""

    # Raw data from i3 IPC
    workspace_data: reactive[dict] = reactive({})
    window_data: reactive[list] = reactive([])

    # Computed from raw data
    active_workspace: reactive[str] = var("")
    window_count: reactive[int] = var(0)

    def compute_window_count(self) -> int:
        """Automatically recomputed when window_data changes"""
        return len(self.window_data)

    def compute_active_workspace(self) -> str:
        """Automatically recomputed when workspace_data changes"""
        for ws in self.workspace_data.get("workspaces", []):
            if ws.get("focused"):
                return ws["name"]
        return "unknown"
```

### Best Practices

1. **Use `reactive[Type]` type hints** for IDE support and validation
2. **Keep watch methods pure** - avoid side effects beyond UI updates
3. **Use `init=False`** for reactives that need async initialization
4. **Batch updates** - change multiple reactives before any watch fires
5. **Avoid recompose for stateful widgets** (DataTable, Input) - use update methods instead
6. **Use computed reactives** for derived values to avoid manual sync

---

## 3. Modal Dialogs and Wizard Patterns

### Decision: ModalScreen for Dialogs, Multi-Screen Push for Wizards

**Rationale**:
- ModalScreen has built-in dimming and focus management
- Type-safe result passing with generics
- Wizards need full screen space and navigation history

### Simple Confirmation Dialog

```python
class ConfirmDialog(ModalScreen[bool]):
    """Simple yes/no confirmation"""

    def __init__(self, message: str, title: str = "Confirm") -> None:
        super().__init__()
        self.message = message
        self.title = title

    def compose(self) -> ComposeResult:
        yield Grid(
            Label(self.title, id="title"),
            Label(self.message, id="message"),
            Horizontal(
                Button("Yes", variant="primary", id="yes"),
                Button("No", variant="default", id="no"),
                classes="buttons"
            ),
            id="dialog"
        )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "yes")

# Usage
async def delete_project(self) -> None:
    confirmed = await self.app.push_screen_wait(
        ConfirmDialog("Delete this project?", "Confirm Delete")
    )
    if confirmed:
        # Proceed with deletion
        pass
```

### Multi-Step Wizard Pattern

```python
from dataclasses import dataclass, field

@dataclass
class WizardState:
    """Shared state across wizard steps"""
    name: str = ""
    directory: str = ""
    icon: str = ""
    scoped_classes: list[str] = field(default_factory=list)
    step: int = 1

class WizardStep1Screen(Screen):
    """Step 1: Basic project info"""

    BINDINGS = [
        ("escape", "cancel", "Cancel"),
        ("ctrl+n", "next", "Next"),
    ]

    def __init__(self, state: WizardState) -> None:
        super().__init__()
        self.state = state

    def compose(self) -> ComposeResult:
        yield Container(
            Label("Step 1 of 3: Basic Information"),
            Label("Project Name:"),
            Input(value=self.state.name, id="name"),
            Label("Project Directory:"),
            Input(value=self.state.directory, id="directory"),
            Horizontal(
                Button("Cancel", id="cancel"),
                Button("Next", variant="primary", id="next"),
            )
        )

    def action_next(self) -> None:
        # Validate and save
        self.state.name = self.query_one("#name", Input).value
        self.state.directory = self.query_one("#directory", Input).value

        if self.validate_step1():
            # Push next step
            self.app.push_screen(WizardStep2Screen(self.state))

    def action_cancel(self) -> None:
        # Pop back to browser
        self.app.pop_screen()

class WizardStep2Screen(Screen):
    """Step 2: Application configuration"""

    BINDINGS = [
        ("escape", "back", "Back"),
        ("ctrl+n", "next", "Next"),
    ]

    def __init__(self, state: WizardState) -> None:
        super().__init__()
        self.state = state

    def compose(self) -> ComposeResult:
        yield Container(
            Label("Step 2 of 3: Application Configuration"),
            Label("Select scoped window classes:"),
            *[
                Checkbox(cls, value=cls in self.state.scoped_classes)
                for cls in ["Ghostty", "Code", "yazi", "lazygit"]
            ],
            Horizontal(
                Button("Back", id="back"),
                Button("Next", variant="primary", id="next"),
            )
        )

    def action_back(self) -> None:
        # Save state and go back
        self.save_checkbox_state()
        self.app.pop_screen()

    def action_next(self) -> None:
        self.save_checkbox_state()
        self.app.push_screen(WizardStep3Screen(self.state))

class WizardStep3Screen(Screen):
    """Step 3: Review and confirm"""

    BINDINGS = [
        ("escape", "back", "Back"),
        ("ctrl+s", "finish", "Create Project"),
    ]

    def action_finish(self) -> None:
        # Create project and return to browser
        create_project(self.state)
        # Pop all wizard screens
        self.app.pop_screen()  # Step 3
        self.app.pop_screen()  # Step 2
        self.app.pop_screen()  # Step 1
        # Or: navigate back to named screen
        self.app.switch_screen("browser")
```

### Best Practices

1. **Use push_screen_wait() for simple modals** that need async results
2. **Share state via constructor** for wizard steps
3. **Validate each step** before allowing forward navigation
4. **Allow backward navigation** in wizards to fix mistakes
5. **Provide progress indicators** (Step X of Y)
6. **Use Container with Grid/Vertical** for consistent modal layouts

---

## 4. Keyboard Shortcuts

### Decision: Priority Bindings for Global, Screen-Specific for Context

**Rationale**:
- Priority bindings work regardless of focus
- Screen bindings override when screen is active
- Footer automatically shows available shortcuts
- Clear separation of concerns

### Implementation Pattern

```python
class I3ProjectApp(App):
    """Application-level global shortcuts"""

    CSS_PATH = "app.tcss"

    BINDINGS = [
        # Global shortcuts (priority=True means always active)
        Binding("ctrl+q", "quit", "Quit", priority=True),
        Binding("ctrl+p", "show_palette", "Command Palette", priority=True),
        Binding("f1", "help", "Help", priority=True),

        # Navigation shortcuts (not priority - screen can override)
        Binding("ctrl+b", "goto_browser", "Browser"),
        Binding("ctrl+e", "goto_editor", "Editor"),
        Binding("ctrl+m", "goto_monitor", "Monitor"),

        # Hidden system bindings
        Binding("ctrl+c", "quit", show=False),  # Standard Ctrl+C
    ]

    def action_goto_browser(self) -> None:
        """Global navigation to browser"""
        self.switch_screen("browser")

    def action_show_palette(self) -> None:
        """Show command palette modal"""
        self.push_screen(CommandPalette())

class ProjectBrowserScreen(Screen):
    """Screen-specific shortcuts"""

    BINDINGS = [
        # These override app bindings when this screen is active
        Binding("n", "new_project", "New Project"),
        Binding("e", "edit_project", "Edit Project"),
        Binding("d", "delete_project", "Delete"),
        Binding("r", "refresh", "Refresh"),
        Binding("/", "focus_search", "Search"),

        # Custom key display in footer
        Binding("ctrl+s", "save", "Save", key_display="^S"),

        # Hidden shortcut (useful but don't clutter footer)
        Binding("?", "toggle_help", show=False),
    ]

    def action_focus_search(self) -> None:
        """Focus search input"""
        self.query_one("#filter", Input).focus()

class MonitorScreen(Screen):
    """Monitor has different shortcuts"""

    BINDINGS = [
        Binding("p", "pause_updates", "Pause"),
        Binding("c", "clear_events", "Clear"),
        Binding("f", "toggle_filter", "Filter"),

        # Override global binding for this screen
        Binding("ctrl+e", "export_events", "Export"),  # Instead of goto_editor
    ]
```

### Footer Widget Integration

```python
from textual.widgets import Footer

class ProjectBrowserScreen(Screen):
    def compose(self) -> ComposeResult:
        yield Header()
        yield Container(...)
        yield Footer()  # Automatically shows BINDINGS

# Footer displays:
# ^Q Quit | ^P Command Palette | F1 Help | N New Project | E Edit | ...
```

### Conditional Bindings

```python
class MonitorScreen(Screen):
    is_paused: reactive[bool] = reactive(False)

    def watch_is_paused(self, paused: bool) -> None:
        """Update bindings when state changes"""
        # Remove old binding
        self.remove_binding("p")

        # Add new binding based on state
        if paused:
            self.add_binding("p", "resume_updates", "Resume")
        else:
            self.add_binding("p", "pause_updates", "Pause")
```

### Best Practices

1. **Use priority=True sparingly** - only for critical app-level shortcuts
2. **Keep footer clean** - hide system bindings with `show=False`
3. **Use consistent key patterns** across screens (e.g., always use `/` for search)
4. **Provide key_display** for complex keys (e.g., `"^S"` instead of `"ctrl+s"`)
5. **Document shortcuts** in help screen (F1)
6. **Use single keys for common actions** (n, e, d) and Ctrl+ for global navigation
7. **Always bind `escape`** to go back or cancel

---

## 5. Testing Strategy

### Decision: Unit Tests for Widgets, Snapshot Tests for Screens, Integration Tests for Flows

**Rationale**:
- Unit tests fast, focused on logic
- Snapshot tests catch visual regressions
- Integration tests verify user workflows
- pytest-asyncio + pytest-textual-snapshot provide excellent tooling

### Unit Test Pattern (Widgets)

```python
# tests/test_project_widget.py
import pytest
from textual.pilot import Pilot
from your_app.widgets import ProjectListWidget

@pytest.mark.asyncio
async def test_project_widget_filters():
    """Test project filtering logic"""
    widget = ProjectListWidget()

    # Test with pilot
    async with widget.run_test() as pilot:
        # Set initial data
        widget.projects = [
            {"name": "NixOS", "dir": "/etc/nixos"},
            {"name": "Stacks", "dir": "/home/user/stacks"},
        ]

        # Simulate typing in filter
        await pilot.press("tab")  # Focus filter input
        await pilot.press("n", "i", "x")

        # Verify filtered results
        table = widget.query_one(DataTable)
        assert table.row_count == 1
        assert "NixOS" in table.get_row_at(0)

@pytest.mark.asyncio
async def test_project_widget_selection():
    """Test project selection behavior"""
    widget = ProjectListWidget()
    widget.projects = [{"name": "Test", "dir": "/test"}]

    async with widget.run_test() as pilot:
        # Simulate down arrow to select
        await pilot.press("down")

        # Verify selection reactive updated
        assert widget.selected_project is not None
        assert widget.selected_project["name"] == "Test"
```

### Snapshot Test Pattern (Screens)

```python
# tests/test_screens_snapshots.py
import pytest

@pytest.mark.asyncio
async def test_browser_screen_initial_state(snap_compare):
    """Snapshot test for browser screen initial render"""
    assert snap_compare("src/app.py", terminal_size=(120, 40))

@pytest.mark.asyncio
async def test_browser_screen_with_projects(snap_compare):
    """Snapshot test with data loaded"""

    async def setup_data(pilot: Pilot):
        """Load test data before snapshot"""
        app = pilot.app
        screen = app.query_one(ProjectBrowserScreen)
        screen.projects = [
            {"name": "NixOS", "dir": "/etc/nixos", "status": "active"},
            {"name": "Stacks", "dir": "/stacks", "status": "inactive"},
        ]
        await pilot.pause()  # Let reactive updates complete

    assert snap_compare(
        "src/app.py",
        terminal_size=(120, 40),
        run_before=setup_data
    )

@pytest.mark.asyncio
async def test_editor_screen_validation_error(snap_compare):
    """Snapshot test showing validation error state"""

    async def trigger_error(pilot: Pilot):
        # Navigate to editor
        await pilot.press("e")
        # Clear required field
        await pilot.press("tab", "ctrl+a", "delete")
        # Trigger validation
        await pilot.press("ctrl+s")

    assert snap_compare(
        "src/app.py",
        press=["n"],  # Press 'n' to open new project screen
        run_before=trigger_error
    )
```

### Integration Test Pattern (User Flows)

```python
# tests/test_workflows.py
import pytest
from textual.pilot import Pilot

@pytest.mark.asyncio
async def test_create_project_workflow():
    """Test complete project creation flow"""
    from your_app.app import I3ProjectApp

    app = I3ProjectApp()
    async with app.run_test() as pilot:
        # Start at browser screen
        assert isinstance(app.screen, ProjectBrowserScreen)

        # Press 'n' to start wizard
        await pilot.press("n")
        assert isinstance(app.screen, WizardStep1Screen)

        # Fill in step 1
        await pilot.press("tab")  # Focus name input
        await pilot.press(*"Test Project")
        await pilot.press("tab")  # Focus directory input
        await pilot.press(*"/tmp/test")
        await pilot.press("ctrl+n")  # Next

        # Verify moved to step 2
        assert isinstance(app.screen, WizardStep2Screen)

        # Select checkboxes
        await pilot.press("space")  # Check first item
        await pilot.press("down", "space")  # Check second
        await pilot.press("ctrl+n")  # Next

        # Verify step 3 (review)
        assert isinstance(app.screen, WizardStep3Screen)

        # Finish wizard
        await pilot.press("ctrl+s")

        # Verify back at browser with new project
        assert isinstance(app.screen, ProjectBrowserScreen)
        browser = app.screen
        assert any(p["name"] == "Test Project" for p in browser.projects)

@pytest.mark.asyncio
async def test_navigation_shortcuts():
    """Test global navigation shortcuts"""
    from your_app.app import I3ProjectApp

    app = I3ProjectApp()
    async with app.run_test() as pilot:
        # Test Ctrl+M goes to monitor
        await pilot.press("ctrl+m")
        assert isinstance(app.screen, MonitorScreen)

        # Test Ctrl+B goes back to browser
        await pilot.press("ctrl+b")
        assert isinstance(app.screen, ProjectBrowserScreen)

        # Test escape on modal
        await pilot.press("?")  # Open help modal
        await pilot.press("escape")
        assert isinstance(app.screen, ProjectBrowserScreen)  # Modal closed
```

### Mock i3 IPC for Tests

```python
# tests/conftest.py
import pytest
from unittest.mock import AsyncMock, MagicMock

@pytest.fixture
def mock_i3_connection():
    """Mock i3 IPC connection for tests"""
    conn = AsyncMock()

    # Mock common i3 IPC responses
    conn.get_tree = AsyncMock(return_value={
        "nodes": [
            {"name": "workspace 1", "focused": True},
            {"name": "workspace 2", "focused": False},
        ]
    })

    conn.get_workspaces = AsyncMock(return_value=[
        {"name": "1", "focused": True, "output": "eDP-1"},
        {"name": "2", "focused": False, "output": "HDMI-1"},
    ])

    conn.subscribe = AsyncMock()

    return conn

@pytest.mark.asyncio
async def test_monitor_with_mock_i3(mock_i3_connection):
    """Test monitor screen with mocked i3"""
    screen = MonitorScreen(i3_conn=mock_i3_connection)

    async with screen.run_test() as pilot:
        # Trigger refresh
        await pilot.press("r")

        # Verify i3 was called
        mock_i3_connection.get_tree.assert_called_once()

        # Verify UI updated
        table = screen.query_one(DataTable)
        assert table.row_count == 2
```

### Best Practices

1. **Use async/await properly** - always `@pytest.mark.asyncio` for async tests
2. **Separate concerns** - unit test logic, snapshot test appearance, integration test workflows
3. **Mock external dependencies** (i3 IPC, file system) for fast, reliable tests
4. **Use pilot.pause()** after reactive updates to ensure UI settled
5. **Test keyboard shortcuts explicitly** - they're the primary interface
6. **Keep snapshot terminal size consistent** (e.g., 120x40) across tests
7. **Update snapshots carefully** - review diffs before `--snapshot-update`
8. **Test error states** not just happy paths

---

## 6. Async Performance and i3 IPC Integration

### Decision: Workers for i3 IPC, Reactive Updates for UI

**Rationale**:
- i3 IPC calls can block (50-200ms)
- Workers keep UI responsive
- Reactive attributes handle UI updates automatically
- Event subscriptions use workers for background monitoring

### Worker Pattern for i3 IPC Queries

```python
from textual.worker import Worker, work
from textual.widgets import DataTable, Label
from i3ipc.aio import Connection
import asyncio

class MonitorScreen(Screen):
    """Real-time i3 monitoring screen"""

    # Reactive state
    workspaces: reactive[list[dict]] = reactive([])
    windows: reactive[list[dict]] = reactive([])
    events: reactive[list[str]] = reactive([])
    is_loading: reactive[bool] = reactive(False)

    def __init__(self) -> None:
        super().__init__()
        self.i3: Connection | None = None
        self._update_worker: Worker | None = None

    async def on_mount(self) -> None:
        """Initialize i3 connection and start updates"""
        # Connect to i3
        self.i3 = await Connection(auto_reconnect=True).connect()

        # Start periodic updates
        self.start_monitoring()

    @work(exclusive=True, thread=False)  # Async worker, not thread
    async def start_monitoring(self) -> None:
        """Background worker that updates i3 state"""
        while True:
            try:
                self.is_loading = True

                # Parallel i3 IPC queries
                workspaces, tree = await asyncio.gather(
                    self.i3.get_workspaces(),
                    self.i3.get_tree()
                )

                # Update reactive state (triggers UI update)
                self.workspaces = workspaces
                self.windows = self.extract_windows(tree)

                self.is_loading = False

                # Update every 500ms
                await asyncio.sleep(0.5)

            except Exception as e:
                self.events.append(f"Error: {e}")
                await asyncio.sleep(1)

    def watch_workspaces(self, workspaces: list[dict]) -> None:
        """Update workspace table when data changes"""
        table = self.query_one("#workspace-table", DataTable)
        table.clear()

        for ws in workspaces:
            table.add_row(
                ws["name"],
                ws["output"],
                "✓" if ws["focused"] else "",
                key=ws["name"]
            )

    def watch_windows(self, windows: list[dict]) -> None:
        """Update window table when data changes"""
        table = self.query_one("#window-table", DataTable)
        table.clear()

        for win in windows:
            table.add_row(
                win.get("name", ""),
                win.get("window_class", ""),
                win.get("workspace", ""),
                key=str(win["id"])
            )

    def on_unmount(self) -> None:
        """Clean up when screen is closed"""
        # Cancel worker
        if self._update_worker:
            self._update_worker.cancel()

        # Close i3 connection
        if self.i3:
            asyncio.create_task(self.i3.disconnect())
```

### Event Subscription Worker

```python
class EventMonitorScreen(Screen):
    """Monitor i3 events in real-time"""

    events: reactive[list[dict]] = reactive([])

    async def on_mount(self) -> None:
        self.i3 = await Connection().connect()

        # Subscribe to i3 events
        self.i3.on("window::new", self.on_window_event)
        self.i3.on("workspace::focus", self.on_workspace_event)
        self.i3.on("binding", self.on_binding_event)

        # Start event loop worker
        self.start_event_listener()

    @work(exclusive=True)
    async def start_event_listener(self) -> None:
        """Worker that processes i3 events"""
        await self.i3.main()  # Blocks waiting for events

    def on_window_event(self, i3: Connection, event) -> None:
        """Called when window event occurs"""
        # Append to reactive list (triggers UI update)
        self.events = [
            {
                "type": "window::new",
                "window": event.container.name,
                "timestamp": time.time()
            },
            *self.events[:100]  # Keep last 100
        ]

    def watch_events(self, events: list[dict]) -> None:
        """Update event list in UI"""
        container = self.query_one("#events", VerticalScroll)
        container.remove_children()

        for event in events:
            container.mount(
                Label(f"[{event['timestamp']}] {event['type']}: {event['window']}")
            )
```

### Optimized i3 IPC Query Pattern

```python
class ProjectSwitcher:
    """Optimized i3 queries for project switching"""

    @work(exclusive=True)
    async def switch_project(self, project_name: str) -> None:
        """Switch project with minimal i3 queries"""
        i3 = await Connection().connect()

        try:
            # Single query to get all marks (efficient)
            marks = await i3.get_marks()

            # Find project-scoped windows
            scoped_marks = [
                m for m in marks
                if m.startswith(f"project_{project_name}_")
            ]

            # Batch show/hide operations
            if scoped_marks:
                # Use i3 command batching (single IPC call)
                commands = [
                    f"[con_mark={mark}] move to workspace current, scratchpad show"
                    for mark in scoped_marks
                ]
                await i3.command("; ".join(commands))

            # Update status (reactive)
            self.current_project = project_name

        finally:
            await i3.disconnect()
```

### Performance Best Practices

1. **Use async workers, not threads** for i3 IPC (i3ipc.aio is async)
2. **Batch i3 commands** - combine with `;` for single IPC call
3. **Cache when possible** - don't query i3 every keystroke
4. **Use `exclusive=True`** to cancel previous queries if user acts faster
5. **Parallel queries** - use `asyncio.gather()` for independent i3 calls
6. **Limit update frequency** - 500ms is enough for monitoring
7. **Subscribe to events** instead of polling when possible
8. **Clean up workers** in `on_unmount()` to prevent leaks
9. **Use reactive updates** - don't manually refresh widgets
10. **Profile with `time` module** - ensure i3 queries stay <50ms

### Responsive Keyboard Input (<50ms)

```python
class ResponsiveScreen(Screen):
    """Pattern for instant keyboard response"""

    BINDINGS = [
        ("j", "select_down", "Down"),
        ("k", "select_up", "Up"),
        ("r", "refresh", "Refresh"),
    ]

    def action_select_down(self) -> None:
        """Instant action - no async needed"""
        table = self.query_one(DataTable)
        table.move_cursor(row=table.cursor_row + 1)
        # UI updates synchronously - <1ms

    def action_refresh(self) -> None:
        """Trigger background refresh without blocking"""
        # Don't await - fire and forget
        self.refresh_data()
        # Show loading indicator immediately
        self.is_loading = True
        # Returns instantly - user can keep typing

    @work(exclusive=True)
    async def refresh_data(self) -> None:
        """Background refresh - doesn't block UI"""
        try:
            data = await fetch_from_i3()
            self.data = data  # Reactive update
        finally:
            self.is_loading = False
```

---

## 7. Widget Hierarchy for Complex Forms

### Decision: VerticalScroll + Grid for Forms, Container for Grouping

**Rationale**:
- VerticalScroll handles overflow automatically
- Grid provides consistent alignment
- Container for logical grouping with CSS
- Compose method keeps hierarchy declarative

### Editor Screen Form Pattern

```python
from textual.containers import Container, Grid, VerticalScroll, Horizontal
from textual.widgets import Input, Checkbox, Label, Button, DataTable

class ProjectEditorScreen(Screen):
    """Complex form with tables, inputs, checkboxes"""

    CSS = """
    #editor {
        height: 100%;
    }

    .form-section {
        border: solid $primary;
        padding: 1 2;
        margin: 1 0;
    }

    .form-grid {
        grid-size: 2;
        grid-gutter: 1 2;
        padding: 1 0;
    }

    .label {
        width: 20;
        text-align: right;
        padding-right: 2;
    }

    .field {
        width: 1fr;
    }

    .buttons {
        dock: bottom;
        height: 3;
        padding: 1;
    }
    """

    def compose(self) -> ComposeResult:
        with VerticalScroll(id="editor"):
            # Section 1: Basic Info
            with Container(classes="form-section"):
                yield Label("Basic Information", classes="section-title")
                with Grid(classes="form-grid"):
                    yield Label("Project Name:", classes="label")
                    yield Input(id="name", classes="field")

                    yield Label("Directory:", classes="label")
                    yield Input(id="directory", classes="field")

                    yield Label("Icon:", classes="label")
                    yield Input(id="icon", classes="field", placeholder="  ")

                    yield Label("Display Name:", classes="label")
                    yield Input(id="display_name", classes="field")

            # Section 2: Application Classes
            with Container(classes="form-section"):
                yield Label("Scoped Application Classes", classes="section-title")
                yield DataTable(id="classes-table", show_header=True)
                with Horizontal():
                    yield Button("Add Class", id="add-class", variant="primary")
                    yield Button("Remove Selected", id="remove-class")

            # Section 3: Options
            with Container(classes="form-section"):
                yield Label("Options", classes="section-title")
                with Grid(classes="form-grid"):
                    yield Label("Auto-activate:", classes="label")
                    yield Checkbox(id="auto_activate", classes="field")

                    yield Label("Show in launcher:", classes="label")
                    yield Checkbox(id="show_launcher", classes="field")

        # Bottom buttons (docked)
        with Horizontal(classes="buttons"):
            yield Button("Cancel", id="cancel")
            yield Button("Save", id="save", variant="primary")

    def on_mount(self) -> None:
        """Initialize form with project data"""
        # Populate inputs
        self.query_one("#name", Input).value = self.project["name"]
        self.query_one("#directory", Input).value = self.project["directory"]

        # Populate table
        table = self.query_one("#classes-table", DataTable)
        table.add_columns("Class", "Include Globally")
        for cls in self.project.get("scoped_classes", []):
            table.add_row(cls, "No")
```

### Wizard Step Form Pattern

```python
class WizardStepScreen(Screen):
    """Reusable wizard step with consistent layout"""

    CSS = """
    #wizard-container {
        height: 100%;
    }

    #progress {
        dock: top;
        height: 3;
        background: $panel;
    }

    #content {
        height: 1fr;
        padding: 2 4;
    }

    #wizard-buttons {
        dock: bottom;
        height: 3;
    }
    """

    def __init__(self, step: int, total_steps: int, title: str) -> None:
        super().__init__()
        self.step = step
        self.total_steps = total_steps
        self.title = title

    def compose(self) -> ComposeResult:
        with Container(id="wizard-container"):
            # Progress indicator
            with Container(id="progress"):
                yield Label(f"Step {self.step} of {self.total_steps}: {self.title}")

            # Form content (override in subclass)
            with VerticalScroll(id="content"):
                yield from self.compose_content()

            # Navigation buttons
            with Horizontal(id="wizard-buttons"):
                if self.step > 1:
                    yield Button("← Back", id="back")
                yield Button("Cancel", id="cancel")
                if self.step < self.total_steps:
                    yield Button("Next →", id="next", variant="primary")
                else:
                    yield Button("Finish", id="finish", variant="success")

    def compose_content(self) -> ComposeResult:
        """Override in subclass to add form fields"""
        raise NotImplementedError
```

### Best Practices

1. **Use VerticalScroll as root** for forms longer than screen
2. **Grid for label/input pairs** - consistent alignment
3. **Container for sections** - group related fields
4. **Dock buttons to bottom** - always visible
5. **Use CSS grid-size: 2** for two-column label/field layout
6. **Set width: 1fr on fields** - fill available space
7. **Use classes for styling** - avoid inline styles
8. **Compose method is declarative** - easy to read hierarchy

---

## 8. Recommended Project Structure

```
i3_project_tui/
├── src/
│   ├── i3_project_tui/
│   │   ├── __init__.py
│   │   ├── app.py                    # Main App class
│   │   │
│   │   ├── screens/
│   │   │   ├── __init__.py
│   │   │   ├── browser.py            # ProjectBrowserScreen
│   │   │   ├── editor.py             # ProjectEditorScreen
│   │   │   ├── monitor.py            # MonitorScreen
│   │   │   ├── layout_manager.py     # LayoutManagerScreen
│   │   │   └── wizard/
│   │   │       ├── __init__.py
│   │   │       ├── step1_basic.py
│   │   │       ├── step2_apps.py
│   │   │       └── step3_review.py
│   │   │
│   │   ├── widgets/
│   │   │   ├── __init__.py
│   │   │   ├── project_list.py       # Reusable ProjectList widget
│   │   │   ├── event_stream.py       # EventStream widget
│   │   │   └── workspace_grid.py     # WorkspaceGrid widget
│   │   │
│   │   ├── modals/
│   │   │   ├── __init__.py
│   │   │   ├── confirm.py            # ConfirmDialog
│   │   │   ├── input_dialog.py       # InputDialog
│   │   │   └── command_palette.py    # CommandPalette
│   │   │
│   │   ├── services/
│   │   │   ├── __init__.py
│   │   │   ├── i3_client.py          # i3 IPC wrapper
│   │   │   ├── project_manager.py    # Project CRUD operations
│   │   │   └── config_manager.py     # Config file handling
│   │   │
│   │   ├── models/
│   │   │   ├── __init__.py
│   │   │   ├── project.py            # Project dataclass
│   │   │   └── workspace.py          # Workspace dataclass
│   │   │
│   │   └── styles/
│   │       ├── app.tcss              # Main app styles
│   │       ├── screens.tcss          # Screen-specific styles
│   │       └── widgets.tcss          # Widget styles
│   │
│   └── i3_project_tui.py             # Entry point script
│
├── tests/
│   ├── __init__.py
│   ├── conftest.py                   # Pytest fixtures
│   ├── unit/
│   │   ├── test_project_manager.py
│   │   ├── test_i3_client.py
│   │   └── test_widgets.py
│   ├── integration/
│   │   ├── test_workflows.py
│   │   └── test_screen_navigation.py
│   └── snapshots/
│       ├── test_screens.py
│       └── __snapshots__/            # SVG snapshots
│
├── pyproject.toml
├── README.md
└── .gitignore
```

---

## 9. Key Dependencies

```toml
[project]
name = "i3-project-tui"
version = "0.1.0"
dependencies = [
    "textual>=0.80.0",          # TUI framework
    "i3ipc>=2.2.1",             # i3 IPC (async support)
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0.0",
    "pytest-asyncio>=0.24.0",
    "pytest-textual-snapshot>=1.0.0",
    "pytest-cov>=6.0.0",
    "ruff>=0.7.0",              # Linting
    "mypy>=1.10.0",             # Type checking
]
```

---

## 10. Quick Start Code Template

```python
# app.py
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Header, Footer
from textual.screen import Screen

from .screens.browser import ProjectBrowserScreen
from .screens.editor import ProjectEditorScreen
from .screens.monitor import MonitorScreen
from .screens.layout_manager import LayoutManagerScreen

class I3ProjectApp(App):
    """Unified i3 Project Management TUI"""

    CSS_PATH = "styles/app.tcss"

    TITLE = "i3 Project Manager"
    SUB_TITLE = "Manage your i3 project workspaces"

    SCREENS = {
        "browser": ProjectBrowserScreen,
        "editor": ProjectEditorScreen,
        "monitor": MonitorScreen,
        "layout": LayoutManagerScreen,
    }

    BINDINGS = [
        Binding("ctrl+q", "quit", "Quit", priority=True),
        Binding("ctrl+b", "goto_browser", "Browser"),
        Binding("ctrl+m", "goto_monitor", "Monitor"),
        Binding("ctrl+l", "goto_layout", "Layout"),
        Binding("f1", "help", "Help", priority=True),
    ]

    def on_mount(self) -> None:
        self.push_screen("browser")

    def action_goto_browser(self) -> None:
        self.switch_screen("browser")

    def action_goto_monitor(self) -> None:
        self.switch_screen("monitor")

    def action_goto_layout(self) -> None:
        self.switch_screen("layout")

    def action_help(self) -> None:
        self.push_screen(HelpScreen())

def main():
    app = I3ProjectApp()
    app.run()

if __name__ == "__main__":
    main()
```

---

## 11. Performance Benchmarks

Based on Textual documentation and real-world apps:

| Operation | Target Latency | Pattern |
|-----------|---------------|---------|
| Keyboard press response | <10ms | Sync action methods |
| Screen navigation | <50ms | push_screen/pop_screen |
| i3 IPC query (single) | <50ms | Async worker |
| i3 IPC query (batch) | <100ms | asyncio.gather() |
| Table update (100 rows) | <20ms | DataTable.clear() + add_row() |
| Reactive update | <5ms | watch_* methods |
| Event subscription | <1ms | i3 event callback |
| Full screen render | <16ms | 60fps target |

---

## 12. Additional Resources

### Official Documentation
- **Textual Guide**: https://textual.textualize.io/guide/
- **Textual API Ref**: https://textual.textualize.io/api/
- **pytest-textual-snapshot**: https://github.com/Textualize/pytest-textual-snapshot

### Real-World Examples
- **awesome-textualize-projects**: https://github.com/oleksis/awesome-textualize-projects
- **Posting** (API client): https://github.com/darrenburns/posting
- **Harlequin** (SQL IDE): https://github.com/tconbeer/harlequin
- **Textual Examples**: https://github.com/Textualize/textual/tree/main/examples

### Community
- **Textual Discord**: https://discord.gg/Enf6Z3qhVr
- **Textual Discussions**: https://github.com/Textualize/textual/discussions

---

## 13. Summary of Key Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| **Screen Navigation** | push_screen/pop_screen stack | Natural flow, history, modal support |
| **Data Binding** | Reactive attributes + watch methods | Declarative, automatic refresh, type-safe |
| **Modal Dialogs** | ModalScreen for simple, push for wizards | Built-in dimming, type-safe results |
| **Keyboard Shortcuts** | Priority for global, screen for context | Clear separation, automatic footer |
| **Testing** | Unit + Snapshot + Integration | Fast feedback, visual regression, workflow validation |
| **i3 IPC** | Async workers + reactive updates | Responsive UI, non-blocking queries |
| **Form Layout** | VerticalScroll + Grid + Container | Consistent, scrollable, grouped |
| **Performance** | <50ms i3 queries, <10ms keyboard | Responsive feel, async workers |

---

**Next Steps**:
1. Review decisions with team
2. Create proof-of-concept for one screen (Browser)
3. Set up pytest infrastructure with mocks
4. Implement i3 IPC service layer
5. Build remaining screens following patterns
6. Add snapshot tests for each screen
7. Integration test critical workflows

---

*Research completed: 2025-10-20*
*Framework version: Textual 0.80+*
*Target Python: 3.11+*
