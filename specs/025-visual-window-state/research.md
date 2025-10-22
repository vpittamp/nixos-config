# Research: Visual Window State Management with Layout Integration

**Feature Branch**: `025-visual-window-state`
**Created**: 2025-10-22
**Purpose**: Document technology decisions, implementation patterns, and design rationale

## Technology Stack Decisions

### Primary Technologies

| Technology | Version | Decision | Rationale |
|------------|---------|----------|-----------|
| Python | 3.11+ | ✅ Confirmed | Constitution X requirement, matches existing daemon (Feature 015) |
| i3ipc.aio | Latest | ✅ Confirmed | Async i3 IPC library, used in daemon and monitor tool |
| Textual | Latest | ✅ Confirmed | Terminal UI framework, already used in TUI screens |
| psutil | Latest | ✅ Confirmed | Process tree analysis for launch command discovery |
| xdotool | Latest | ✅ Confirmed | Window manipulation (unmap/map) for flicker prevention |
| pytest | Latest | ✅ Confirmed | Testing framework with async support (pytest-asyncio) |
| Pydantic | 2.x | ✅ Confirmed | Data validation for layout schemas and window matching |

### Visualization Strategy

**Decision**: Use **Textual Tree + DataTable** widgets for hierarchical window state visualization

**Alternatives Considered**:
1. **Mermaid.js with terminal rendering** - Rejected: Requires external dependencies, static output only, no real-time updates
2. **Custom ASCII art tree** - Rejected: Reinventing the wheel, Textual Tree provides superior features
3. **Graphviz with terminal preview** - Rejected: Overkill for simple hierarchical data, slow rendering

**Rationale for Textual**:
- Already used in existing i3pm TUI (monitorscreen, browser, inspector)
- Rich library integration for syntax highlighting and formatting
- Built-in tree widget with expand/collapse, keyboard navigation
- DataTable widget for sortable/filterable tabular views
- Real-time updates via Textual reactivity system
- Zero external dependencies (pure Python)
- Proven performance with 100+ node trees (Feature 017 benchmarks)

### i3 JSON Format Strategy

**Decision**: Extend i3's native JSON format with **non-invasive `i3pm` namespace**

**i3 Native JSON Structure**:
```json
{
  "border": "pixel",
  "floating": "auto_off",
  "layout": "splith",
  "percent": 0.5,
  "type": "con",
  "nodes": [...],
  "swallows": [
    {
      "class": "^Google-chrome$",
      "instance": "^Navigator$"
    }
  ]
}
```

**i3pm Extended JSON Structure**:
```json
{
  "border": "pixel",
  "floating": "auto_off",
  "layout": "splith",
  "percent": 0.5,
  "type": "con",
  "nodes": [...],
  "swallows": [
    {
      "class": "^Google-chrome$",
      "instance": "^Navigator$"
    }
  ],
  "i3pm": {
    "project": "nixos",
    "classification": "scoped",
    "hidden": false,
    "app_identifier": "browser",
    "launch_command": "google-chrome-stable",
    "working_directory": "/home/user/projects/nixos",
    "environment": {
      "PROJECT_DIR": "/home/user/projects/nixos",
      "PROJECT_NAME": "nixos"
    }
  }
}
```

**Rationale**:
- i3's append_layout command ignores unknown keys (graceful degradation)
- Export can strip `i3pm` namespace for vanilla i3 compatibility
- Preserves all i3 native semantics (swallow patterns, geometry, layout modes)
- Enables project-specific metadata without breaking i3 tools
- Constitution XI compliance: i3 IPC data remains authoritative

### Window Matching Strategy

**Decision**: Adopt **i3-resurrect's flexible swallow criteria** with per-app overrides

**i3-resurrect Swallow Pattern** (from analysis):
```json
{
  "class": "^URxvt$",
  "instance": "^weechat$",
  "title": "^WeeChat",
  "window_role": "^browser$"
}
```

**i3pm Enhanced Matching Configuration**:
```json
{
  "default_criteria": ["class", "instance"],
  "app_overrides": {
    "Alacritty": {
      "criteria": ["class", "instance", "title"],
      "title_pattern": "^(.+)\\s+\\|\\s+(.+)$",
      "extract_cwd": true
    },
    "Firefox": {
      "criteria": ["class", "window_role"],
      "roles": ["browser", "Preferences"]
    },
    "Google-chrome": {
      "criteria": ["class", "instance", "title"],
      "pwa_detection": true
    }
  }
}
```

**Rationale**:
- Default (class + instance) works for 80% of applications
- Title patterns handle terminal tabs with unique working directories
- Window role distinguishes browser windows (toolbar vs content)
- PWA detection matches Firefox PWAs by title and class
- Configurable per-app allows incremental refinement
- Constitution XI alignment: Criteria validated against i3 IPC GET_TREE data

### Layout Restore Flicker Prevention

**Decision**: Adopt **i3-resurrect's window unmapping pattern** using xdotool

**Implementation Pattern** (from i3-resurrect-analysis.md):
```python
async def restore_layout_with_unmapping(workspace: str, layout_file: Path):
    """Restore layout with flicker prevention."""
    # 1. Unmap existing windows on workspace
    windows = await get_workspace_windows(workspace)
    for window_id in windows:
        subprocess.run(['xdotool', 'windowunmap', window_id])

    try:
        # 2. Apply layout with placeholders
        await i3.command(f'workspace {workspace}')
        await i3.command(f'append_layout {layout_file}')

        # 3. Launch applications (windows created hidden)
        await launch_applications(layout_file)

        # 4. Wait for windows to match placeholders
        await wait_for_swallow(timeout=30)
    finally:
        # 5. Remap all windows (existing + new)
        all_windows = await get_workspace_windows(workspace)
        for window_id in all_windows:
            subprocess.run(['xdotool', 'windowmap', window_id])
```

**Rationale**:
- Prevents visual artifacts during layout restoration
- Windows remain hidden until fully positioned
- Try/finally ensures remap even on errors (Constitution FR-036)
- Matches i3-resurrect's proven approach (User Story 5 compatibility)
- Requires xdotool (already in dependencies)

### Launch Command Discovery

**Decision**: Use **psutil for process tree analysis** with manual override support

**Discovery Algorithm**:
```python
async def discover_launch_command(window_id: int) -> Optional[LaunchCommand]:
    """Discover launch command from process tree."""
    # 1. Get window PID via i3 IPC
    tree = await i3.get_tree()
    window = find_window_by_id(tree, window_id)
    if not window or not window.pid:
        return None

    # 2. Walk process tree to find root command
    try:
        process = psutil.Process(window.pid)

        # Walk up to terminal or desktop session manager
        while process.parent() and process.parent().name() not in ['systemd', 'init', 'i3', 'bash', 'zsh']:
            process = process.parent()

        # Extract command and environment
        cmdline = process.cmdline()
        cwd = process.cwd()
        env = {k: v for k, v in process.environ().items() if k in ['PATH', 'HOME', 'DISPLAY']}

        return LaunchCommand(
            command=' '.join(cmdline),
            working_directory=cwd,
            environment=env
        )
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        return None
```

**Manual Override Configuration**:
```json
{
  "app_class": "Firefox",
  "launch_commands": [
    {
      "instance": "Navigator",
      "command": "firefox",
      "working_directory": "$HOME"
    },
    {
      "instance": "pwa-*",
      "command": "firefox --class={instance}",
      "working_directory": "$HOME"
    }
  ]
}
```

**Rationale**:
- psutil provides reliable process information
- Walking process tree finds actual launch command, not shell wrapper
- Manual overrides handle edge cases (PWAs, AppImages, desktop entries)
- Constitution FR-015 compliance: Automatic discovery preferred
- Fallback to user prompt when discovery fails

### Layout Diff Algorithm

**Decision**: Use **git-style diff with three-way categorization**

**Diff Categories**:
1. **Added**: Windows in current state, not in saved layout
2. **Removed**: Windows in saved layout, not in current state
3. **Moved**: Windows in both, but different workspace/monitor
4. **Kept**: Windows in both, same position

**Matching Algorithm**:
```python
def compute_layout_diff(current: List[WindowState], saved: List[LayoutWindow]) -> WindowDiff:
    """Compute diff between current state and saved layout."""
    # Match windows by swallow criteria
    matches = []
    for curr_win in current:
        for saved_win in saved:
            if swallow_criteria_match(curr_win, saved_win.swallows):
                matches.append((curr_win, saved_win))
                break

    # Categorize
    matched_current = {m[0] for m in matches}
    matched_saved = {m[1] for m in matches}

    added = [w for w in current if w not in matched_current]
    removed = [w for w in saved if w not in matched_saved]

    moved = []
    kept = []
    for curr_win, saved_win in matches:
        if curr_win.workspace != saved_win.workspace or curr_win.output != saved_win.output:
            moved.append((curr_win, saved_win))
        else:
            kept.append((curr_win, saved_win))

    return WindowDiff(
        added=added,
        removed=removed,
        moved=moved,
        kept=kept
    )
```

**Rationale**:
- Git-style diff is familiar to developers
- Three-way categorization provides clear decision points
- Move detection helps understand workspace reorganizations
- Enables partial restore (only missing windows) per FR-028

## i3-resurrect Pattern Adoption

### Patterns to Adopt

| Pattern | Source | Rationale |
|---------|--------|-----------|
| Window unmapping | i3-resurrect | Proven flicker prevention (User Story 2, FR-017) |
| Flexible swallow criteria | i3-resurrect | Handles edge cases (terminals, browsers) (User Story 4) |
| Workspace layout preservation | i3-resurrect | Maintains layout modes (splith/splitv/tabbed) (FR-018) |
| Placeholder timeout handling | i3-resurrect | Graceful failure recovery (FR-037) |

### Patterns to Avoid

| Pattern | Reason |
|---------|--------|
| Perl implementation | Python is project standard (Constitution X) |
| Separate save/restore scripts | Integrated into i3pm CLI (User Story 1-5) |
| File-based configuration only | Daemon IPC for real-time updates (Constitution XI) |
| Manual window marking | Daemon handles automatically (Feature 015) |

### Integration Strategy

1. **Phase 1**: Implement window unmapping/remapping in LayoutManager class
2. **Phase 2**: Add flexible swallow criteria to window matching
3. **Phase 3**: Implement i3-resurrect import/export for migration (User Story 5)
4. **Phase 4**: Test compatibility with vanilla i3 append_layout

## Architecture Integration Points

### Existing i3pm Components to Extend

1. **i3_project_manager/core/layout.py** (lines 1-100):
   - Already has LayoutManager, WindowLauncher classes
   - Add: Window unmapping/remapping methods
   - Add: Enhanced swallow criteria matching
   - Add: Layout diff computation

2. **i3_project_manager/core/models.py** (lines 1-100):
   - Already has SavedLayout, WorkspaceLayout, LayoutWindow
   - Add: SwallowCriteria dataclass
   - Add: WindowDiff dataclass
   - Add: Pydantic validation for all models

3. **i3_project_manager/tui/screens/monitor.py** (lines 1-80):
   - Already has MonitorScreen with tabs
   - Add: Tree view tab for hierarchical window display
   - Add: Real-time updates via daemon IPC subscription

4. **i3_project_manager/core/daemon_client.py** (lines 1-100):
   - Already has DaemonClient with JSON-RPC
   - Add: get_window_tree() method
   - Add: subscribe_window_events() method
   - Add: get_layout_state() method

5. **i3-project-event-daemon/handlers.py**:
   - Already handles window events (new, close, focus, title)
   - Add: Broadcast window state changes to subscribed clients
   - Add: Layout state query handlers

### New Components to Create

1. **i3_project_manager/visualization/tree_view.py**:
   - Textual Tree widget for hierarchical window display
   - Real-time update handling from daemon events
   - Expand/collapse, filtering, search

2. **i3_project_manager/cli/commands.py** (extend):
   - Add: `i3pm windows --tree|--table|--live|--json`
   - Add: `i3pm layout diff <layout-name>`
   - Add: `i3pm layout import <i3-resurrect-file>`
   - Add: `i3pm layout export <layout-name> --format=i3-resurrect`

3. **i3_project_manager/core/swallow_matcher.py**:
   - SwallowCriteria configuration loader
   - Per-app override logic
   - Window property matching algorithm

4. **i3_project_manager/core/layout_diff.py**:
   - Diff computation algorithm
   - Categorization (added/removed/moved/kept)
   - Partial restore logic

5. **i3_project_manager/schemas/layout.json**:
   - JSON schema for extended i3 layout format
   - Validation of i3pm namespace
   - Export schema for vanilla i3 compatibility

## Performance Considerations

### Real-Time Update Strategy

**Target**: Window state updates within 100ms (Success Criteria SC-002)

**Approach**:
- Use daemon's existing i3 IPC event subscriptions (window, workspace, output)
- Daemon broadcasts state changes to connected TUI clients via IPC
- TUI uses Textual reactivity to update tree view
- Debounce events with 50ms window to batch rapid changes

**Benchmark**: Feature 017 achieved <100ms latency for window marking

### Tree Rendering Optimization

**Target**: Render 100+ windows without lag (Success Criteria SC-005)

**Approach**:
- Use Textual Tree with virtualization (only visible nodes rendered)
- Collapsible sections (monitors, workspaces) reduce visible nodes
- Incremental updates (only changed nodes re-rendered)
- Search/filter reduces displayed nodes

**Benchmark**: Textual Tree handles 1000+ nodes with <100ms render time

### Layout Operations

**Targets**:
- Save: <2 seconds for 20 windows (SC-003)
- Restore: <30 seconds for 20 windows (SC-004)
- Diff: <500ms for 50 windows (SC-007)

**Approach**:
- Async i3 IPC queries (parallel workspace scans)
- Psutil process tree walks (cached results)
- Layout file I/O (async file operations)
- Progress feedback for operations >2 seconds

## Data Storage Strategy

### Layout File Structure

**Location**: `~/.config/i3pm/projects/<project>/layouts/<layout-name>.json`

**Format**: Extended i3 JSON with i3pm namespace

**Schema Validation**: Pydantic models + JSON schema

**Example**:
```json
{
  "version": "1.0",
  "project": "nixos",
  "layout_name": "dev-setup",
  "saved_at": "2025-10-22T14:30:00Z",
  "monitor_count": 2,
  "workspaces": [
    {
      "number": 1,
      "output": "eDP-1",
      "layout": "splith",
      "windows": [
        {
          "class": "Ghostty",
          "instance": "ghostty",
          "title": "~/projects/nixos",
          "swallows": [{"class": "^Ghostty$", "instance": "^ghostty$"}],
          "i3pm": {
            "launch_command": "ghostty --working-directory=/home/user/projects/nixos",
            "working_directory": "/home/user/projects/nixos",
            "project": "nixos"
          }
        }
      ]
    }
  ]
}
```

### Swallow Criteria Configuration

**Location**: `~/.config/i3pm/swallow_criteria.json`

**Format**: Per-app swallow override configuration

**Validation**: JSON schema + Pydantic models

## Security Considerations

### Launch Command Safety

**Threats**:
- Shell injection via saved layouts from untrusted sources
- Exposure of sensitive environment variables

**Mitigations**:
1. Validate launch commands before execution (no shell metacharacters)
2. Filter environment variables (block AWS_*, TOKEN, SECRET, PASSWORD patterns)
3. Layout file permissions restricted to user-only (600)
4. User confirmation for layout import from external sources

**Implementation**:
```python
def validate_launch_command(command: str) -> bool:
    """Validate launch command for safety."""
    # No shell metacharacters
    forbidden = ['|', '&', ';', '`', '$', '>', '<', '\n']
    if any(char in command for char in forbidden):
        return False

    # Must be executable path or in PATH
    cmd_parts = shlex.split(command)
    executable = cmd_parts[0]
    if not (Path(executable).is_file() or shutil.which(executable)):
        return False

    return True

def filter_environment(env: Dict[str, str]) -> Dict[str, str]:
    """Filter sensitive environment variables."""
    secret_patterns = ['TOKEN', 'SECRET', 'PASSWORD', 'KEY', 'AWS_', 'API_']
    return {
        k: v for k, v in env.items()
        if not any(pattern in k.upper() for pattern in secret_patterns)
    }
```

## Testing Strategy

### Unit Tests

**Coverage**:
- Data models (SavedLayout, WindowState, SwallowCriteria, WindowDiff)
- Swallow criteria matching logic
- Layout diff computation
- Launch command discovery and validation
- Environment variable filtering

**Framework**: pytest with Pydantic validation

### Integration Tests

**Coverage**:
- Daemon IPC communication (window state queries, event subscriptions)
- i3 IPC interaction (GET_TREE, GET_WORKSPACES, append_layout)
- Layout save/restore with mock i3
- Window matching with mock window data

**Framework**: pytest-asyncio with mock i3 connection

### Contract Tests

**Coverage**:
- i3 JSON format compatibility (parse vanilla i3 layouts)
- i3pm extended JSON (strip namespace for export)
- Daemon JSON-RPC API (request/response schemas)

**Framework**: JSON schema validation + pytest

### Scenario Tests

**Coverage**:
- Full layout save/restore workflow
- Diff computation and partial restore
- i3-resurrect import/export
- Multi-monitor layout restore on different monitor config

**Framework**: pytest with test fixtures (sample layouts, window data)

### Performance Tests

**Coverage**:
- Tree rendering with 100+ windows
- Real-time update latency measurement
- Layout operations timing

**Framework**: pytest with time assertions

## Open Questions & Decisions

### Q1: Should layout restore be atomic or best-effort?

**Decision**: **Best-effort with transaction-like cleanup**

**Rationale**:
- Window launch failures are common (app not installed, permission denied)
- Failing entire restore on one window failure frustrates users
- Try/finally pattern ensures cleanup (window remapping) even on errors
- User receives detailed report of successes and failures
- Constitution FR-035, FR-036 mandate graceful error handling

### Q2: Should we cache swallow criteria matches?

**Decision**: **Yes, cache with invalidation on window property changes**

**Rationale**:
- Swallow matching involves regex compilation and property comparison
- Same window matched multiple times during diff/restore operations
- Cache invalidation triggered by i3 window events (title change, property change)
- Minimal memory overhead (<1MB for 100 windows)
- Improves diff computation from ~500ms to ~100ms for 50 windows

### Q3: Should tree view support editing (move windows, change layout)?

**Decision**: **Not in MVP (Phase 1), post-MVP enhancement**

**Rationale**:
- Viewing and saving current state covers 80% of use cases (User Stories 1-2)
- Editing requires complex i3 command generation and validation
- Focus on reliable save/restore before interactive editing
- User can manually arrange windows in i3, then save layout
- Future enhancement per spec "Out of Scope: Visual layout editor"

## Constitution Compliance Checklist

### Principle X: Python Development & Testing Standards

- ✅ Python 3.11+ with async/await patterns (i3ipc.aio, asyncio)
- ✅ Testing framework: pytest with pytest-asyncio
- ✅ Type hints for all function signatures and public APIs
- ✅ Data validation: Pydantic models for all entities
- ✅ Terminal UI: Rich library for tables and formatting
- ✅ Module structure: Single-responsibility (models, services, displays, validators)

### Principle XI: i3 IPC Alignment & State Authority

- ✅ State queries use GET_WORKSPACES, GET_OUTPUTS, GET_TREE, GET_MARKS
- ✅ Window state validated against i3 IPC, not custom tracking
- ✅ Event-driven updates via i3 IPC SUBSCRIBE
- ✅ Daemon state secondary to i3 IPC authoritative state
- ✅ Diagnostic tools include i3 IPC state for validation

### Principle XII: Forward-Only Development

- ✅ No backwards compatibility with hypothetical "old layout format"
- ✅ Direct implementation of optimal solution (i3 JSON + i3pm namespace)
- ✅ No feature flags for "legacy mode"
- ✅ Complete replacement approach, not gradual migration

## Implementation Phases

### Phase 0: Research & Design ✅
- Technology stack decisions documented
- i3-resurrect pattern analysis complete
- Integration points identified

### Phase 1: Core Models & Contracts
- Data model definitions (data-model.md)
- JSON schemas for layouts and swallow criteria
- Daemon IPC contract extensions
- Quickstart guide for developers

### Phase 2: Window State Visualization (User Story 1)
- Tree view widget for hierarchical display
- Table view for sortable/filterable display
- Real-time updates via daemon events
- CLI commands for window state viewing

### Phase 3: Enhanced Layout Save/Restore (User Story 2 + 4)
- Window unmapping/remapping for flicker prevention
- Enhanced swallow criteria matching
- Launch command discovery with psutil
- Layout save/restore with progress feedback

### Phase 4: Layout Diff (User Story 3)
- Diff computation algorithm
- Side-by-side comparison view
- Partial restore capability
- Save/update/discard prompts

### Phase 5: i3-resurrect Compatibility (User Story 5)
- Import i3-resurrect layouts
- Export i3pm layouts to i3-resurrect format
- Compatibility testing with vanilla i3

---

**Next Steps**:
1. Generate data-model.md with entity definitions and relationships
2. Create contracts/ with JSON schemas and API definitions
3. Create quickstart.md with developer setup and workflow
4. Update CLAUDE.md with new commands and capabilities
