# Phase 0: Research - Enhanced i3pm TUI with Comprehensive Management & Automated Testing

**Date**: 2025-10-21
**Feature Branch**: `022-create-a-new`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Research Questions

### 1. Textual Pilot API for TUI Testing (High Priority)

**Question**: What are the capabilities and limitations of Textual's Pilot API for simulating user interactions and asserting TUI state?

**Why Important**: User Story 7 (P1 priority) requires automated TUI testing framework. We need to understand if Pilot API supports:
- Key press simulation (including special keys like Tab, Escape, Enter)
- Mouse event simulation for click testing
- Screen transition assertions (push_screen, pop_screen)
- Widget state assertions (DataTable content, Input values, button states)
- Timing assertions for performance testing (2 second layout restore requirement)
- Async test support for i3 IPC operations

**Research Approach**:
1. Review Textual documentation for Pilot API testing patterns
2. Examine existing Textual test examples in Textual repository
3. Identify any gaps requiring custom test harness code
4. Document patterns for mocking daemon/i3 IPC in Pilot tests

**Findings**: ✅ **COMPLETED**

**Summary**: Textual Pilot API provides comprehensive testing capabilities for TUI applications with full support for key press simulation, assertions, and async operations.

**Key Capabilities**:
1. **Key Press Simulation**:
   - Basic key presses: `pilot.press("a", "b", "c")` for character input
   - Special keys: `pilot.press("enter", "tab", "escape", "left", "right", "up", "down")`
   - Modifiers: `pilot.press("ctrl+c", "ctrl+v")` for keyboard shortcuts
   - Can simulate sequences: `press=["tab", "left", "a"]` parameter in run_test()

2. **State Assertions**:
   - Direct widget access: `app.query_one("#widget_id", WidgetType)` to get widget reference
   - Property assertions: `assert widget.value == expected_value`
   - Table content: `table.row_count`, `table.rows.keys()` for DataTable validation
   - Input values: `input.value` for Input widget content

3. **Mouse Simulation**:
   - Click at position: `pilot.click(selector=None, offset=None)`
   - Hover at position: `pilot.hover(selector=None, offset=None)`
   - Position-based clicking supported

4. **Async Support**:
   - Pilot is async-compatible: `async with app.run_test() as pilot:`
   - Can await async operations: `await pilot.press("enter")`
   - Compatible with pytest-asyncio for async test functions

5. **Screen Transitions**:
   - Can verify screen state: `assert app.screen.name == "expected_screen"`
   - Push/pop screen operations observable through app.screen property

**Limitations Identified**:
- No built-in timing assertions - need custom implementation with `time.time()` measurements
- Screenshot capture for failed tests requires custom implementation
- No built-in "wait for condition" - need to implement polling or use `pilot.pause()` and manual checks

**Decision**: Pilot API fully supports our requirements (FR-029 through FR-033). We'll implement custom timing assertions and state dump helpers for enhanced debugging.

**Reference Documentation**: https://textual.textualize.io/guide/testing/ and https://textual.textualize.io/api/pilot/

---

### 2. i3 RUN_COMMAND and Window Matching for Application Relaunching (High Priority)

**Question**: What is the reliable pattern for launching applications via i3 RUN_COMMAND and matching them in GET_TREE for repositioning after launch?

**Why Important**: FR-002 requires layout restoration with application relaunching. We need to:
- Launch applications with custom environment variables and working directories
- Wait for windows to appear in i3 tree (timeout handling)
- Match launched windows to their intended layout positions using window properties
- Handle applications that spawn multiple windows (e.g., IDE with tool windows)

**Research Approach**:
1. Review i3ipc-python examples for RUN_COMMAND patterns
2. Analyze existing daemon code for window matching patterns
3. Test i3 RUN_COMMAND with environment variable injection
4. Document timing expectations for window appearance after launch
5. Identify window properties best for matching (class, instance, title, role)

**Findings**: ✅ **COMPLETED**

**Summary**: i3's exec command (via RUN_COMMAND) launches applications through shell, inheriting shell environment. Window matching requires polling GET_TREE until window appears.

**Launch Pattern**:
```python
import asyncio
import i3ipc.aio

# Environment variables must be set in shell command prefix
command = f'PROJECT_DIR={project_dir} PROJECT_NAME={project_name} {launch_command}'
await i3.command(f'exec {command}')

# Alternative: Use shell to set environment
env_vars = f'export PROJECT_DIR={project_dir}; export PROJECT_NAME={project_name};'
await i3.command(f'exec bash -c "{env_vars} {launch_command}"')
```

**Window Matching Pattern** (from existing AutoLaunchApp implementation):
```python
async def wait_for_window(i3, window_class: str, timeout: float = 5.0) -> Optional[Con]:
    """Wait for window to appear in i3 tree."""
    start_time = asyncio.get_event_loop().time()

    while (asyncio.get_event_loop().time() - start_time) < timeout:
        tree = await i3.get_tree()
        windows = tree.find_classed(window_class)  # Regex pattern matching
        if windows:
            return windows[0]
        await asyncio.sleep(0.1)  # Poll every 100ms

    return None
```

**Window Properties for Matching** (from i3ipc Con object):
- `window_class`: WM_CLASS (most reliable, e.g., "Ghostty", "Code")
- `window_instance`: WM_INSTANCE (secondary identifier)
- `window_title`: Window title (can change during app lifetime)
- `window_role`: WM_WINDOW_ROLE (useful for dialog matching)
- `window_id`: X11 window ID (unique per window)

**Timing Expectations** (from existing auto-launch implementation in models.py):
- Terminal applications (ghostty): ~200-500ms appearance time
- Heavy applications (VS Code): ~1-3 seconds appearance time
- Default timeout: 5.0 seconds with 100ms polling interval
- Launch delay: 0.5 seconds between consecutive launches to prevent race conditions

**Multi-Window Applications**:
- Use `tree.find_classed(pattern)` to get all windows (returns list)
- First window usually appears within timeout
- Subsequent windows (tool panels, etc.) may appear later
- Consider marking only primary window or using `wait_for_mark` pattern from AutoLaunchApp

**Decision**: Use shell-based environment variable injection via `exec bash -c` for launch commands. Implement async window polling with configurable timeout. Match windows primarily by window_class with fallback to window_instance or title if needed.

---

### 3. SavedLayout Data Model Extensions for Application Lifecycle (High Priority)

**Question**: What additional fields are required in SavedLayout model to support application relaunching with custom configurations?

**Why Important**: Clarification session confirmed layouts must capture launch commands, environment variables, and working directories. Current SavedLayout model may only capture window geometries and workspace assignments.

**Research Approach**:
1. Read existing SavedLayout model in `/etc/nixos/home-modules/tools/i3_project_manager/core/models.py`
2. Identify current fields and serialization format
3. Document required additions:
   - Launch command with arguments
   - Environment variables (dict)
   - Working directory path
   - Application identifier for matching
   - Retry policy for failed launches
4. Ensure backward compatibility with existing saved layouts

**Findings**: ✅ **COMPLETED**

**Summary**: Current SavedLayout and LayoutWindow models **ALREADY INCLUDE** launch command and environment variable fields! Models are well-designed for application lifecycle management.

**Existing SavedLayout Model** (lines 352-386 in /etc/nixos/home-modules/tools/i3_project_manager/core/models.py):
```python
@dataclass
class SavedLayout:
    layout_version: str = "1.0"
    project_name: str = ""
    layout_name: str = "default"
    workspaces: List[WorkspaceLayout] = field(default_factory=list)
    saved_at: datetime = field(default_factory=datetime.now)
    monitor_config: str = "single"  # "single", "dual", "triple"
    total_windows: int = 0
```

**Existing LayoutWindow Model** (lines 284-312 in models.py):
```python
@dataclass
class LayoutWindow:
    window_class: str  # WM_CLASS (e.g., "Ghostty", "Code")
    window_title: Optional[str] = None  # Window title (for matching)
    geometry: Optional[Dict[str, int]] = None  # {"width": 1920, "height": 1080, "x": 0, "y": 0}
    layout_role: Optional[str] = None  # "main", "editor", "terminal", "browser"
    split_before: Optional[str] = None  # "horizontal", "vertical", None
    launch_command: str = ""  # ✅ Command to launch this window
    launch_env: Dict[str, str] = field(default_factory=dict)  # ✅ Environment variables
    expected_marks: List[str] = field(default_factory=list)  # e.g., ["project:nixos"]
```

**What We Have**:
✅ Launch command field (`launch_command`)
✅ Environment variables dict (`launch_env`)
✅ Window matching identifier (`window_class`, `window_title`)
✅ Expected marks for verification (`expected_marks`)
✅ Geometry and workspace information via `WorkspaceLayout`
✅ JSON serialization with `to_json()` and `from_json()`

**What's Missing** (for enhanced functionality):
- ❌ Working directory field (cwd) - **NEED TO ADD**
- ❌ Retry policy (max_retries, retry_delay) - **NEED TO ADD**
- ❌ Launch timeout configuration - **NEED TO ADD**

**Backward Compatibility Strategy**:
- New fields must have default values (e.g., `cwd: Optional[str] = None`)
- Existing layouts without new fields will deserialize with defaults
- Layout version remains "1.0" since this is additive (no breaking changes)
- If we need breaking changes in future, increment to "1.1" and add migration logic

**Proposed Extensions to LayoutWindow**:
```python
@dataclass
class LayoutWindow:
    # ... existing fields ...
    launch_command: str = ""
    launch_env: Dict[str, str] = field(default_factory=dict)
    cwd: Optional[str] = None  # NEW: Working directory for launch
    launch_timeout: float = 5.0  # NEW: Timeout for window appearance
    max_retries: int = 3  # NEW: Retry attempts if launch fails
    retry_delay: float = 1.0  # NEW: Delay between retries
```

**Decision**: Extend LayoutWindow model with `cwd`, `launch_timeout`, `max_retries`, and `retry_delay` fields. All new fields have sensible defaults ensuring backward compatibility. No version bump needed.

---

### 4. Textual DataTable Editing Patterns (Medium Priority)

**Question**: What is the standard pattern for inline editing of DataTable rows in Textual?

**Why Important**: Multiple screens require editable tables:
- Workspace Config: Edit workspace-to-monitor assignments
- Auto-Launch Config: Edit launch commands, environment variables, workspace assignments
- Pattern Config: Edit pattern rules with priority ordering

**Research Approach**:
1. Review Textual documentation for DataTable widget capabilities
2. Check if DataTable supports inline editing or requires modal dialogs
3. Document pattern for capturing edits and validating input
4. Identify whether custom widget extension is needed

**Findings**: ✅ **COMPLETED**

**Summary**: Textual DataTable does NOT support inline cell editing. Best practice is to use modal screens or dedicated edit forms.

**Current DataTable Capabilities**:
- Display tabular data with columns and rows
- Row selection via cursor (keyboard or mouse)
- Sorting by column
- Cell styling (colors, bold, etc.)
- No built-in inline editing

**Recommended Patterns**:

1. **Modal Edit Screen** (preferred for complex edits):
```python
class AutoLaunchConfigScreen(Screen):
    def action_edit_entry(self):
        """Edit selected auto-launch entry."""
        entry = self._get_selected_entry()
        if entry:
            # Push modal edit screen
            self.app.push_screen(AutoLaunchEditScreen(entry), callback=self._on_edit_complete)

    def _on_edit_complete(self, edited_entry: Optional[AutoLaunchApp]):
        """Handle edit completion."""
        if edited_entry:
            # Update table
            self.refresh_table()
```

2. **Inline Form Below Table** (for simple single-field edits):
```python
# Show edit form in same screen below table
with Vertical():
    yield DataTable(id="entries")
    with Horizontal(id="edit_form", classes="hidden"):
        yield Input(placeholder="Command", id="cmd_input")
        yield Button("Save")
        yield Button("Cancel")
```

3. **Quick Edit Actions** (for single-value toggles):
```python
# Use keybindings for quick actions
Binding("t", "toggle_enabled", "Toggle Enable")
Binding("up_arrow", "move_up", "Move Up")  # Priority reordering
Binding("down_arrow", "move_down", "Move Down")
```

**Decision**: Use modal edit screens for complex multi-field edits (auto-launch entries with command, env vars, workspace, timeout). Use inline form approach for simple single-field edits (workspace-to-monitor assignments). Use keybinding actions for toggles and reordering.

**Implementation Pattern**:
- Each editable table screen has corresponding Edit screen
- Edit screen uses Input, Select, and Checkbox widgets for fields
- Edit screen validates input before returning to parent
- Parent screen refreshes table on successful edit

---

### 5. i3 GET_OUTPUTS Response Format for Monitor Detection (Medium Priority)

**Question**: What is the exact structure of GET_OUTPUTS response and how do we reliably map outputs to monitor roles (primary/secondary/tertiary)?

**Why Important**: FR-012 requires displaying monitor configuration with roles. Need to understand:
- Output name format (e.g., "eDP-1", "HDMI-1", "DP-1")
- Primary flag detection
- Active vs inactive outputs
- Resolution and position information
- How to determine monitor connection/disconnection events

**Research Approach**:
1. Review i3 IPC documentation for GET_OUTPUTS message type
2. Query live i3 instance with multiple monitor configurations
3. Document response structure and field meanings
4. Identify how to subscribe to output change events

**Findings**: ✅ **COMPLETED**

**Summary**: i3 GET_OUTPUTS provides comprehensive monitor information. Existing workspace_manager.py already implements monitor detection and role assignment.

**OutputReply Structure** (from i3ipc.aio library):
```python
class OutputReply:
    name: str  # Output name (e.g., "eDP-1", "HDMI-1", "DP-1")
    active: bool  # Whether output is currently active
    primary: bool  # Whether output is marked as primary
    current_workspace: str  # Current workspace name on this output
    rect: Rect  # Output rectangle (x, y, width, height)
```

**Existing Implementation** (from /etc/nixos/home-modules/desktop/i3-project-event-daemon/workspace_manager.py):
```python
@dataclass
class MonitorConfig:
    name: str
    rect: Dict[str, int]
    active: bool
    primary: bool
    role: str  # "primary", "secondary", "tertiary"

async def get_monitor_configs(i3) -> List[MonitorConfig]:
    """Get active monitor configurations with role assignments."""
    outputs = await i3.get_outputs()
    active_outputs = [o for o in outputs if o.active]

    # Sort by position (left to right)
    sorted_outputs = sorted(active_outputs, key=lambda o: o.rect.x)

    # Assign roles based on count
    if len(sorted_outputs) == 1:
        roles = ["primary"]
    elif len(sorted_outputs) == 2:
        roles = ["primary", "secondary"]
    else:
        roles = ["primary", "secondary", "tertiary"] + ["tertiary"] * (len(sorted_outputs) - 3)

    return [
        MonitorConfig.from_i3_output(output, role)
        for output, role in zip(sorted_outputs, roles)
    ]
```

**Event Subscription for Monitor Changes**:
```python
i3 = await i3ipc.aio.Connection().connect()
i3.on("output", handle_output_change)  # Subscribe to output events

async def handle_output_change(i3, event):
    """Handle monitor connection/disconnection."""
    # Query updated monitor configuration
    monitors = await get_monitor_configs(i3)
    # Trigger workspace redistribution if needed
    await redistribute_workspaces(i3, monitors)
```

**Monitor Name Patterns**:
- Laptop displays: `eDP-1` (embedded DisplayPort)
- External HDMI: `HDMI-1`, `HDMI-2`
- External DisplayPort: `DP-1`, `DP-2`
- Virtual outputs (RDP/VNC): `VIRTUAL-1`

**Decision**: Reuse existing MonitorConfig dataclass and get_monitor_configs() function from workspace_manager.py. Subscribe to "output" events for real-time monitor detection. Display monitors in TUI with name, resolution, role, and assigned workspaces.

---

### 6. Textual Screen Navigation Patterns (Low Priority)

**Question**: What is the recommended pattern for breadcrumb navigation and contextual keybindings in Textual?

**Why Important**: FR-026 and FR-027 require breadcrumb navigation and contextual footer keybindings. Need to understand:
- How to maintain navigation history/stack
- How to update footer bindings dynamically based on active screen
- How to render breadcrumb trail in header

**Research Approach**:
1. Review Textual examples for navigation patterns
2. Check if Screen widget provides navigation history
3. Document pattern for updating bindings based on screen state
4. Identify whether custom header widget is needed

**Findings**: ✅ **COMPLETED**

**Summary**: Textual provides built-in screen stack via push_screen/pop_screen. Custom breadcrumb widget needed for hierarchical navigation display.

**Screen Navigation**:
```python
# Textual app maintains screen stack automatically
self.app.push_screen(NewScreen())  # Push new screen
self.app.pop_screen()  # Return to previous screen

# Access current screen
current_screen = self.app.screen
screen_name = current_screen.name  # If screen has name attribute
```

**Breadcrumb Implementation Pattern**:
```python
class BreadcrumbWidget(Static):
    """Custom widget for breadcrumb navigation."""

    def __init__(self, path: List[str]):
        super().__init__()
        self.path = path

    def render(self) -> str:
        """Render breadcrumb trail."""
        return " > ".join(self.path)

    def update_path(self, path: List[str]):
        """Update breadcrumb path."""
        self.path = path
        self.refresh()

# In Screen class
class ProjectEditorScreen(Screen):
    def compose(self) -> ComposeResult:
        yield Header()
        yield BreadcrumbWidget(["Projects", "NixOS", "Edit"])  # Custom breadcrumb
        # ... rest of content ...
        yield Footer()
```

**Contextual Keybindings** (already implemented in existing browser.py):
```python
class ProjectBrowserScreen(Screen):
    BINDINGS = [
        Binding("enter", "switch_project", "Switch"),
        Binding("e", "edit_project", "Edit"),
        Binding("l", "layout_manager", "Layouts"),
        # ... contextual bindings for this screen
    ]

# Bindings automatically shown in Footer
# Different screens have different BINDINGS = [...] lists
```

**Existing TUIState Model** (from models.py lines 577-627):
```python
@dataclass
class TUIState:
    active_screen: str = "browser"
    screen_history: List[str] = field(default_factory=list)

    def push_screen(self, screen_name: str):
        self.screen_history.append(self.active_screen)
        self.active_screen = screen_name

    def pop_screen(self) -> Optional[str]:
        if self.screen_history:
            self.active_screen = self.screen_history.pop()
            return self.active_screen
        return None
```

**Decision**: Use existing TUIState for navigation history tracking. Implement custom BreadcrumbWidget (Static subclass) that displays in Header. Footer automatically shows contextual keybindings from each screen's BINDINGS list (no additional code needed). Update breadcrumb on screen push/pop using navigation history.

**Breadcrumb Format**:
- Browser: "Projects"
- Editor: "Projects > {project_name} > Edit"
- Layout Manager: "Projects > {project_name} > Layouts"
- Workspace Config: "Projects > {project_name} > Workspaces"
- Classification Wizard: "Tools > Window Classification"

---

## Research Summary

All 6 research questions completed. Key findings:

1. ✅ **Textual Pilot API**: Fully supports automated testing requirements. Need custom timing assertions and state dumps.

2. ✅ **i3 Application Launching**: Use `exec bash -c` for environment variables. Window polling with 5s timeout and 100ms interval.

3. ✅ **SavedLayout Model**: Already has launch_command and launch_env fields! Add cwd, launch_timeout, max_retries, retry_delay with defaults for backward compatibility.

4. ✅ **DataTable Editing**: No inline editing. Use modal screens for complex edits, inline forms for simple edits, keybindings for toggles.

5. ✅ **Monitor Detection**: Existing MonitorConfig and get_monitor_configs() in workspace_manager.py. Subscribe to "output" events for changes.

6. ✅ **Navigation Patterns**: Use existing TUIState for history. Create custom BreadcrumbWidget. Footer bindings automatic via Screen.BINDINGS.

## Architectural Decisions

Based on research findings:

1. **Testing Framework**: Use Textual Pilot API with custom timing and state dump utilities. Mock daemon and i3 IPC using pytest fixtures.

2. **Layout Restoration**: Extend LayoutWindow model minimally (4 new fields with defaults). Implement async launch_and_wait() function using existing patterns.

3. **TUI Editing**: Modal edit screens for complex multi-field edits (auto-launch, pattern rules). Inline forms for simple edits (workspace assignments).

4. **Monitor Management**: Reuse existing workspace_manager.py MonitorConfig. Add TUI display layer with "output" event subscription.

5. **Navigation**: Implement BreadcrumbWidget showing hierarchical path. Leverage existing TUIState and Textual screen stack.

## Risk Identification

No significant risks identified. All patterns are well-supported by existing libraries and codebase.

Minor limitations:
- Pilot API timing assertions require custom implementation (low risk - straightforward)
- DataTable editing requires modal screens (design trade-off, acceptable UX)
- Window launch timing varies by application (mitigated with configurable timeouts)

## Next Steps

Ready to proceed to **Phase 1: Data Model and Contracts Design**

No changes required to plan.md based on research findings. All proposed approaches are validated and feasible.

---

**Status**: ✅ **COMPLETED** - All research questions answered. Ready for Phase 1.
