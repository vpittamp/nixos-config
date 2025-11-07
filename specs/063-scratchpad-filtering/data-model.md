# Data Model: Scratchpad Terminal Filtering

**Feature**: 063-scratchpad-filtering
**Date**: 2025-11-07
**Status**: Phase 1 Design

## Overview

This document defines the data structures and state models for implementing reliable scratchpad terminal filtering across all window management code paths.

## Core Entities

### 1. WindowEnvironment

**Purpose**: Validated representation of I3PM environment variables for a window process.

**Source**: `/proc/<pid>/environ` parsing

**Fields**:
```python
@dataclass
class WindowEnvironment:
    """Validated I3PM environment variables from window process."""

    # Core identification
    app_id: str  # I3PM_APP_ID (e.g., "scratchpad-nixos-1699564800")
    app_name: str  # I3PM_APP_NAME (e.g., "scratchpad-terminal", "vscode")
    scope: str  # I3PM_SCOPE ("scoped" | "global")

    # Project association
    project_name: Optional[str]  # I3PM_PROJECT_NAME (None for global apps)
    project_dir: Optional[str]  # I3PM_PROJECT_DIR

    # Scratchpad-specific (only for scratchpad terminals)
    is_scratchpad: bool  # I3PM_SCRATCHPAD == "true"
    working_dir: Optional[str]  # I3PM_WORKING_DIR (scratchpad-specific)

    # Validation metadata
    validated_at: float  # Timestamp when environment was read
    validation_source: str  # "proc_environ" | "cache"

    @classmethod
    def from_pid(cls, pid: int) -> Optional["WindowEnvironment"]:
        """
        Read and parse I3PM environment variables from process.

        Returns None if:
        - Process doesn't exist
        - /proc/<pid>/environ is not readable
        - No I3PM_* variables present
        """
        pass

    @property
    def is_scoped(self) -> bool:
        """Window is project-scoped (filtered during project switches)."""
        return self.scope == "scoped"

    @property
    def is_global(self) -> bool:
        """Window is global (always visible regardless of project)."""
        return self.scope == "global"

    def matches_project(self, project_name: str) -> bool:
        """Check if window belongs to the given project."""
        return self.project_name == project_name
```

**Validation Rules**:
- `app_id` MUST be present and non-empty
- `app_name` MUST be present and non-empty
- `scope` MUST be "scoped" or "global"
- If `scope == "scoped"`, `project_name` MUST be present
- If `is_scratchpad == True`, `app_name` MUST be "scratchpad-terminal"
- If `is_scratchpad == True`, `project_name` MUST be present

**Usage**:
```python
# Read environment from window PID
env = WindowEnvironment.from_pid(window.pid)

# Check if window should be filtered
if env and env.is_scoped and not env.matches_project(active_project):
    # Hide window (filtered out)
    pass
```

---

### 2. WindowFilterCriteria

**Purpose**: Unified filtering criteria used across all code paths to ensure consistency.

**Fields**:
```python
@dataclass
class WindowFilterCriteria:
    """Criteria for determining window visibility during project switching."""

    active_project: str  # Current project name
    window_id: int  # Sway window container ID
    window_marks: List[str]  # Sway window marks
    window_pid: Optional[int]  # Process ID (for environment lookup)

    # Validation metadata
    evaluated_at: float  # Timestamp when criteria was evaluated
    code_path: str  # "ipc_server" | "window_filter" | "handlers_tick"

    def should_hide(self) -> bool:
        """
        Determine if window should be hidden for active_project.

        Evaluation order:
        1. Check for project mark (project:{name}:)
        2. Check for scratchpad mark (scratchpad:{name})
        3. If no marks, check environment variables via PID
        4. Default: global (don't hide)
        """
        pass

    def get_window_project(self) -> Optional[str]:
        """Extract project name from marks or environment."""
        # Check marks first (fast)
        for mark in self.window_marks:
            if mark.startswith("project:"):
                return mark.split(":")[1]
            elif mark.startswith("scratchpad:"):
                return mark.split(":")[1]

        # Fallback to environment (slower)
        if self.window_pid:
            env = WindowEnvironment.from_pid(self.window_pid)
            return env.project_name if env else None

        return None  # Global window

    def is_scratchpad_terminal(self) -> bool:
        """Check if window is a scratchpad terminal."""
        # Check mark first (fast)
        for mark in self.window_marks:
            if mark.startswith("scratchpad:"):
                return True

        # Fallback to environment
        if self.window_pid:
            env = WindowEnvironment.from_pid(self.window_pid)
            return env.is_scratchpad if env else False

        return False
```

**Validation Rules**:
- `active_project` MUST be non-empty
- `window_id` MUST be valid Sway container ID
- `window_marks` MAY be empty (for newly created windows)
- `window_pid` SHOULD be provided for environment-based filtering
- `code_path` MUST match one of the three known paths

**Usage**:
```python
# Create criteria from Sway window container
criteria = WindowFilterCriteria(
    active_project="nixos",
    window_id=window.id,
    window_marks=window.marks,
    window_pid=window.pid,
    evaluated_at=time.time(),
    code_path="window_filter",
)

# Determine visibility
if criteria.should_hide():
    await hide_window(criteria.window_id)
```

---

### 3. FilteringDecision

**Purpose**: Audit trail and debugging support for filtering decisions.

**Fields**:
```python
@dataclass
class FilteringDecision:
    """Record of a filtering decision for debugging and validation."""

    # Input
    window_id: int
    window_marks: List[str]
    active_project: str
    code_path: str  # Which filtering code path made this decision

    # Decision
    should_hide: bool
    reason: str  # Human-readable reason (e.g., "scratchpad for different project")
    window_project: Optional[str]  # Project associated with window

    # Metadata
    decided_at: float  # Timestamp
    environment_checked: bool  # True if /proc/<pid>/environ was read
    mark_checked: bool  # True if window marks were evaluated

    def to_log_message(self) -> str:
        """Format decision as log message."""
        action = "HIDE" if self.should_hide else "SHOW"
        return f"[{self.code_path}] {action} window {self.window_id}: {self.reason}"
```

**Usage**:
```python
# Record filtering decision
decision = FilteringDecision(
    window_id=window.id,
    window_marks=window.marks,
    active_project="nixos",
    code_path="ipc_server",
    should_hide=True,
    reason="scratchpad terminal for project 'stacks'",
    window_project="stacks",
    decided_at=time.time(),
    environment_checked=True,
    mark_checked=True,
)

logger.debug(decision.to_log_message())
```

---

### 4. ScratchpadTerminal (Existing - Enhancements)

**Purpose**: In-memory registry entry for active scratchpad terminals.

**Existing Fields** (from Feature 062):
```python
@dataclass
class ScratchpadTerminal:
    project_name: str
    window_id: int
    pid: int
    working_dir: Path
    created_at: float
    last_shown_at: Optional[float]
    mark: str  # e.g., "scratchpad:nixos"
```

**NEW: Validation Enhancements**:
```python
    def validate_environment(self) -> bool:
        """
        Validate terminal has correct I3PM_* environment variables.

        Checks:
        - I3PM_SCRATCHPAD == "true"
        - I3PM_PROJECT_NAME == self.project_name
        - I3PM_APP_NAME == "scratchpad-terminal"
        - I3PM_SCOPE == "scoped"

        Returns False if:
        - Process no longer exists
        - Environment variables missing/incorrect
        """
        env = WindowEnvironment.from_pid(self.pid)

        if not env:
            return False

        return (
            env.is_scratchpad
            and env.app_name == "scratchpad-terminal"
            and env.project_name == self.project_name
            and env.is_scoped
        )

    def is_process_running(self) -> bool:
        """Check if terminal process is still alive."""
        try:
            os.kill(self.pid, 0)
            return True
        except (OSError, ProcessLookupError):
            return False
```

---

## State Transitions

### Window Lifecycle During Project Switch

```
[Project A Active, Scratchpad Terminal Visible]
                │
                │ User switches to Project B
                ↓
[Filtering Logic Evaluates Window]
                │
                ├─→ Mark: "scratchpad:projectA" ──→ HIDE (different project)
                ├─→ Mark: "scratchpad:projectB" ──→ SHOW (current project)
                ├─→ Mark: "project:projectA:*" ──→ HIDE (different project)
                └─→ No mark, check environment ──→ Read /proc/<pid>/environ
                                │
                                ├─→ I3PM_PROJECT_NAME=projectA ──→ HIDE
                                ├─→ I3PM_PROJECT_NAME=projectB ──→ SHOW
                                └─→ I3PM_SCOPE=global ──→ SHOW (always visible)
```

### Terminal Creation (Duplicate Prevention)

```
[User requests scratchpad toggle for Project A]
                │
                ↓
[Check ScratchpadManager.terminals dict]
                │
                ├─→ Project A exists ──→ Toggle existing terminal (show/hide)
                │
                └─→ Project A missing ──→ Create new terminal
                                          │
                                          ├─→ Launch Ghostty with I3PM_* env vars
                                          ├─→ Wait for window (discriminate via env)
                                          ├─→ Apply mark "scratchpad:projectA"
                                          └─→ Add to terminals dict
```

---

## Relationships

```
WindowEnvironment ←─── read via PID ───── ScratchpadTerminal
       │                                           │
       │ provides                                  │ has
       ↓                                           ↓
WindowFilterCriteria ────── evaluates ────→ FilteringDecision
       │
       │ used by
       ↓
[ipc_server.py, window_filter.py, handlers.py]
```

---

## Data Flow Across Code Paths

### Path 1: handlers.py (TICK event)
```python
# Input: Tick event "project:switch:nixos"
async def _switch_project(project_name: str):
    # Uses window_filter.py helper
    result = await filter_windows_by_project(conn, project_name, workspace_tracker)
    # Result contains hide/show decisions
```

### Path 2: window_filter.py (Shared Logic)
```python
async def filter_windows_by_project(conn, project_name, workspace_tracker):
    for window in tree.descendants():
        criteria = WindowFilterCriteria(
            active_project=project_name,
            window_id=window.id,
            window_marks=window.marks,
            window_pid=window.pid,
            code_path="window_filter",
        )

        if criteria.should_hide():
            await conn.command(f'[con_id={window.id}] move scratchpad')
```

### Path 3: ipc_server.py (JSON-RPC)
```python
async def _hide_windows(self, project_name: str):
    for window in tree.descendants():
        criteria = WindowFilterCriteria(
            active_project=project_name,
            window_id=window.id,
            window_marks=window.marks,
            window_pid=window.pid,
            code_path="ipc_server",
        )

        if criteria.should_hide():
            await self.sway.command(f'[con_id={window.id}] move scratchpad')
```

**Key Insight**: All three paths MUST use the same `WindowFilterCriteria.should_hide()` logic to ensure consistency.

---

## Performance Considerations

### Optimization Strategy

1. **Mark-first evaluation** (fast path):
   - Check window marks before reading environment
   - Marks are immediately available from Sway IPC tree
   - ~99% of cases handled by marks alone

2. **Environment fallback** (slow path):
   - Only read `/proc/<pid>/environ` when marks are missing
   - Cache environment readings (with TTL) to avoid repeated file reads
   - Expected: <5% of filtering decisions need environment lookup

3. **Batch operations**:
   - Process all windows in single Sway IPC tree query
   - Group hide/show commands to minimize IPC round-trips

### Expected Latency

- **Mark-based filtering**: < 10ms for 20 windows
- **Environment-based filtering**: < 50ms for 20 windows (with caching)
- **Total project switch**: < 200ms (target from success criteria)

---

## Testing Strategy

### Unit Tests

1. **WindowEnvironment**:
   - Parse valid environment → Success
   - Parse environment with missing variables → Validation error
   - Parse environment from non-existent PID → None

2. **WindowFilterCriteria**:
   - Mark-based project match → Show window
   - Mark-based project mismatch → Hide window
   - Scratchpad mark match → Show window
   - Scratchpad mark mismatch → Hide window
   - No marks, environment match → Show window
   - No marks, environment mismatch → Hide window

3. **FilteringDecision**:
   - Log message formatting → Correct format
   - Audit trail storage → All fields populated

### Integration Tests

1. **Cross-path consistency**:
   - Same window, same project → All paths make same decision
   - Scratchpad terminal → All paths recognize scratchpad mark
   - Global window → All paths skip hiding

2. **State synchronization**:
   - Terminal created → Mark applied correctly
   - Terminal hidden → Mark persists
   - Terminal shown → Mark still present

### End-to-End Tests

See `spec.md` test protocol section for full automated test script.

---

**Model Version**: 1.0.0
**Last Updated**: 2025-11-07
