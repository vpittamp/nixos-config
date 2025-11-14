# MarkManager Service API Contract

**Feature**: 076-mark-based-app-identification
**Service**: MarkManager
**Location**: `home-modules/desktop/i3-project-event-daemon/services/mark_manager.py`
**Purpose**: Manage Sway mark injection, query, and cleanup for window classification

## Service Interface

### inject_marks()

**Purpose**: Inject structured marks onto a window for classification

**Signature**:
```python
async def inject_marks(
    self,
    window_id: int,
    app_name: str,
    project: Optional[str] = None,
    workspace: Optional[int] = None,
    scope: Optional[str] = None,
    custom: Optional[dict[str, str]] = None,
) -> MarkMetadata:
    """Inject marks onto window via Sway IPC.

    Args:
        window_id: Sway container ID
        app_name: Application name from app-registry
        project: Project context (if scoped app)
        workspace: Workspace number for validation
        scope: "scoped" or "global" classification
        custom: Custom metadata key-value pairs

    Returns:
        MarkMetadata instance with injected marks

    Raises:
        ValueError: If app_name invalid or window_id not found
        IPCError: If Sway IPC command fails
    """
```

**Behavior**:
1. Validate inputs (app_name format, workspace range)
2. Create MarkMetadata instance
3. Generate Sway mark strings via `MarkMetadata.to_sway_marks()`
4. Execute IPC commands: `swaymsg [con_id=<window_id>] mark <mark>`
5. Return MarkMetadata instance

**Performance**: <25ms for typical mark set (3-5 marks)

**Example**:
```python
mark_metadata = await mark_manager.inject_marks(
    window_id=12345,
    app_name="terminal",
    project="nixos",
    workspace=1,
    scope="scoped",
)
# Injects marks: i3pm_app:terminal, i3pm_project:nixos, i3pm_ws:1, i3pm_scope:scoped
```

---

### get_window_marks()

**Purpose**: Query all i3pm_* marks for a specific window

**Signature**:
```python
async def get_window_marks(self, window_id: int) -> list[str]:
    """Get all i3pm_* marks for a window.

    Args:
        window_id: Sway container ID

    Returns:
        List of mark strings (e.g., ["i3pm_app:terminal", "i3pm_project:nixos"])

    Raises:
        ValueError: If window_id not found
    """
```

**Behavior**:
1. Query Sway tree via `GET_TREE`
2. Find window container by ID
3. Extract marks field from container
4. Filter for marks starting with "i3pm_"
5. Return filtered mark list

**Performance**: <10ms (single GET_TREE query)

**Example**:
```python
marks = await mark_manager.get_window_marks(12345)
# Returns: ["i3pm_app:terminal", "i3pm_project:nixos", "i3pm_ws:1"]
```

---

### get_mark_metadata()

**Purpose**: Parse MarkMetadata from window marks

**Signature**:
```python
async def get_mark_metadata(self, window_id: int) -> Optional[MarkMetadata]:
    """Get structured mark metadata for a window.

    Args:
        window_id: Sway container ID

    Returns:
        MarkMetadata instance or None if no i3pm_* marks found

    Raises:
        ValueError: If window_id not found or marks malformed
    """
```

**Behavior**:
1. Query marks via `get_window_marks()`
2. Parse marks via `MarkMetadata.from_sway_marks()`
3. Return MarkMetadata instance or None

**Performance**: <10ms (dominated by GET_TREE query)

**Example**:
```python
metadata = await mark_manager.get_mark_metadata(12345)
# Returns: MarkMetadata(app="terminal", project="nixos", workspace="1", scope="scoped")
```

---

### find_windows()

**Purpose**: Find all windows matching mark query criteria

**Signature**:
```python
async def find_windows(self, query: WindowMarkQuery) -> list[int]:
    """Find windows matching mark query.

    Args:
        query: WindowMarkQuery with filter criteria

    Returns:
        List of window IDs matching all query filters

    Raises:
        ValueError: If query is empty (no filters)
    """
```

**Behavior**:
1. Validate query (at least one filter must be set)
2. Query Sway tree via `GET_TREE`
3. Walk tree to find all windows with PIDs
4. For each window:
   - Extract marks
   - Parse MarkMetadata
   - Check if matches ALL query filters
5. Return list of matching window IDs

**Performance**: <30ms for typical session (10-20 windows)

**Example**:
```python
query = WindowMarkQuery(app="terminal", project="nixos")
window_ids = await mark_manager.find_windows(query)
# Returns: [12345, 12346, 12347] (all terminals in nixos project)
```

---

### cleanup_marks()

**Purpose**: Remove all i3pm_* marks from a window

**Signature**:
```python
async def cleanup_marks(self, window_id: int) -> int:
    """Remove all i3pm_* marks from window.

    Args:
        window_id: Sway container ID

    Returns:
        Number of marks removed

    Raises:
        ValueError: If window_id not found
    """
```

**Behavior**:
1. Query marks via `get_window_marks()`
2. For each i3pm_* mark:
   - Execute IPC: `swaymsg [con_id=<window_id>] unmark <mark>`
3. Return count of removed marks

**Performance**: <25ms for typical mark set (3-5 marks)

**Example**:
```python
removed_count = await mark_manager.cleanup_marks(12345)
# Returns: 4 (removed i3pm_app:terminal, i3pm_project:nixos, i3pm_ws:1, i3pm_scope:scoped)
```

---

### count_instances()

**Purpose**: Count running instances of an app (for idempotent restore)

**Signature**:
```python
async def count_instances(self, app_name: str, workspace: Optional[int] = None, project: Optional[str] = None) -> int:
    """Count running instances of an app.

    Args:
        app_name: Application name from app-registry
        workspace: Optional workspace filter
        project: Optional project filter

    Returns:
        Number of matching windows
    """
```

**Behavior**:
1. Build WindowMarkQuery from parameters
2. Call `find_windows(query)`
3. Return length of result list

**Performance**: <30ms (delegated to find_windows)

**Example**:
```python
count = await mark_manager.count_instances("terminal", workspace=1, project="nixos")
# Returns: 3 (three terminals on workspace 1 in nixos project)
```

---

## Integration Points

### AppLauncher Integration

**Location**: `services/app_launcher.py`

**Modification**:
```python
async def launch_app(self, app_name: str, workspace: int, cwd: Optional[Path], project: str):
    # EXISTING: Launch app via wrapper
    proc = await self._launch_subprocess(app_name, cwd, project)

    # EXISTING: Wait for window appearance
    window = await self._wait_for_window(app_name, timeout=30)

    # NEW: Inject marks
    mark_metadata = await self.mark_manager.inject_marks(
        window_id=window.id,
        app_name=app_name,
        project=project if is_scoped_app(app_name) else None,
        workspace=workspace,
        scope="scoped" if is_scoped_app(app_name) else "global",
    )

    logger.info(f"Injected marks for {app_name}: {mark_metadata.to_sway_marks()}")

    return window
```

---

### Daemon Event Handler Integration

**Location**: `daemon.py`

**Modification**:
```python
async def on_window_close(self, event: WindowEvent):
    """Handle window::close event for mark cleanup."""
    window_id = event.container.id

    try:
        removed = await self.mark_manager.cleanup_marks(window_id)
        logger.debug(f"Cleaned up {removed} marks for window {window_id}")
    except ValueError:
        logger.warning(f"Window {window_id} not found for mark cleanup (already destroyed)")
    except Exception as e:
        logger.error(f"Failed to cleanup marks for window {window_id}: {e}")

# Register event handler
await self.sway_connection.on(Event.WINDOW_CLOSE, self.on_window_close)
```

---

### Layout Persistence Integration

**Location**: `layout/persistence.py`

**Modification**:
```python
async def save_layout(name: str, project: str):
    # EXISTING: Query Sway tree
    tree = await sway_connection.get_tree()

    windows = []
    for window in walk_windows(tree):
        # EXISTING: Extract window data
        window_data = extract_window_data(window)

        # NEW: Get mark metadata
        try:
            mark_metadata = await mark_manager.get_mark_metadata(window.id)
            if mark_metadata:
                window_data["marks"] = mark_metadata.dict()
        except Exception as e:
            logger.warning(f"Failed to get marks for window {window.id}: {e}")

        windows.append(window_data)

    # EXISTING: Save to layout file
    save_to_file(name, project, windows)
```

---

### Layout Restore Integration

**Location**: `layout/restore.py`

**Modification**:
```python
async def restore_workflow(layout: LayoutSnapshot, project: str):
    # NEW: Detect running apps via marks (primary method)
    running_apps_by_mark = {}

    for window in walk_all_windows():
        try:
            metadata = await mark_manager.get_mark_metadata(window.id)
            if metadata:
                key = (metadata.app, metadata.project or "", metadata.workspace or "")
                running_apps_by_mark.setdefault(key, []).append(window.id)
        except Exception as e:
            logger.debug(f"Failed to get marks for window {window.id}: {e}")

    # EXISTING: Detect running apps via /proc (fallback)
    running_apps_by_proc = await detect_running_apps()  # Feature 075 logic

    # NEW: Merge detection results (marks take precedence)
    running_apps = merge_detection_results(running_apps_by_mark, running_apps_by_proc)

    # EXISTING: Filter layout, launch missing apps
    for saved_window in layout.windows:
        if saved_window.marks:
            # Mark-based detection (fast, deterministic)
            key = (saved_window.marks.app, saved_window.marks.project or "", str(saved_window.workspace))
            count_running = len(running_apps_by_mark.get(key, []))
        else:
            # Fallback to /proc detection (backward compatibility)
            count_running = count_running_by_proc(saved_window.app_registry_name)

        instances_to_launch = saved_window.count - count_running

        for _ in range(instances_to_launch):
            await app_launcher.launch_app(...)  # Marks injected here
```

---

## Error Handling

### IPCError Handling

**Scenario**: Sway IPC command fails (connection lost, command timeout)

**Behavior**:
- Log error with context (operation, window_id, mark)
- Raise IPCError with original exception
- Caller decides retry strategy

**Example**:
```python
try:
    await mark_manager.inject_marks(window_id, "terminal")
except IPCError as e:
    logger.error(f"Failed to inject marks: {e}")
    # Retry once
    await asyncio.sleep(0.1)
    await mark_manager.inject_marks(window_id, "terminal")
```

---

### Window Not Found

**Scenario**: Window destroyed between query and mark operation

**Behavior**:
- Raise ValueError("Window {window_id} not found")
- Caller should handle gracefully (window may close during operation)

**Example**:
```python
try:
    await mark_manager.cleanup_marks(window_id)
except ValueError:
    logger.debug(f"Window {window_id} already destroyed")
    # Not an error - window closed before cleanup
```

---

### Malformed Marks

**Scenario**: Marks don't follow i3pm_<key>:<value> format

**Behavior**:
- Skip malformed marks during parsing
- Log warning with mark string
- Continue with valid marks

**Example**:
```python
# Marks: ["i3pm_app:terminal", "invalid_mark", "i3pm_project:nixos"]
metadata = await mark_manager.get_mark_metadata(window_id)
# Returns: MarkMetadata(app="terminal", project="nixos")
# Logs: WARNING: Skipping malformed mark 'invalid_mark'
```

---

## Testing Contract

### Unit Tests (pytest)

**Location**: `tests/mark-based-app-identification/unit/test_mark_manager.py`

**Coverage**:
- Mark injection with various parameter combinations
- Mark parsing from Sway mark strings
- Query building and filtering logic
- Error handling (window not found, IPC failure)

---

### Integration Tests (pytest-asyncio)

**Location**: `tests/mark-based-app-identification/integration/test_mark_injection.py`

**Coverage**:
- AppLauncher + MarkManager integration
- Mark persistence through layout save/load cycle
- Mark cleanup on window close event

---

### End-to-End Tests (sway-test)

**Location**: `tests/mark-based-app-identification/sway-tests/*.json`

**Coverage**:
- Mark injection verification after app launch
- Mark cleanup verification after window close
- Layout restore using saved marks

---

## Performance Guarantees

| Operation | Latency Target | Measured |
|-----------|----------------|----------|
| inject_marks() | <25ms | TBD |
| get_window_marks() | <10ms | TBD |
| get_mark_metadata() | <10ms | TBD |
| find_windows() | <30ms | TBD |
| cleanup_marks() | <25ms | TBD |
| count_instances() | <30ms | TBD |

**Scaling**:
- Mark injection: O(m) where m = marks per window (3-5)
- Mark query: O(n) where n = total windows (10-20 typical)
- Mark cleanup: O(m) where m = marks per window (3-5)

**Constraints**:
- Max windows per session: 100
- Max marks per window: 20
- Max custom metadata keys: 10
