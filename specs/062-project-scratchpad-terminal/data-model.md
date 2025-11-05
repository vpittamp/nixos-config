# Data Model: Project-Scoped Scratchpad Terminal

**Feature**: 062-project-scratchpad-terminal
**Date**: 2025-11-05

## Entity Overview

This feature introduces one primary entity and one manager class:

1. **ScratchpadTerminal** - Represents a single project-scoped terminal instance
2. **ScratchpadManager** - Manages lifecycle and state of all scratchpad terminals

## Entity Definitions

### ScratchpadTerminal

Represents a single scratchpad terminal associated with a project.

**Attributes**:

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `project_name` | `str` | Yes | Project identifier or "global" for global terminal | Non-empty string, alphanumeric + hyphens |
| `pid` | `int` | Yes | Process ID of Alacritty terminal | Positive integer, must exist in process table |
| `window_id` | `int` | Yes | Sway window container ID | Positive integer, must exist in Sway tree |
| `mark` | `str` | Yes | Sway window mark for identification | Format: `scratchpad:{project_name}` |
| `working_dir` | `Path` | Yes | Initial working directory (project root) | Valid absolute path, directory must exist |
| `created_at` | `float` | Yes | Unix timestamp of terminal creation | Positive float |
| `last_shown_at` | `float` | No | Unix timestamp of last show operation | Positive float, can be None |

**Relationships**:
- Belongs to exactly one project (1:1)
- Associated with one Sway window (1:1)
- Tracked by one ScratchpadManager (N:1)

**Lifecycle States**:
- **Created**: Terminal launched, window marked, tracked in daemon state
- **Visible**: Window visible on current workspace
- **Hidden**: Window in Sway scratchpad (`__i3_scratch` workspace)
- **Terminated**: Process exited, window closed, removed from daemon state

**Pydantic Model**:

```python
from pydantic import BaseModel, Field, field_validator
from pathlib import Path
from typing import Optional
import psutil
import time

class ScratchpadTerminal(BaseModel):
    """Represents a project-scoped scratchpad terminal."""

    project_name: str = Field(
        ...,
        description="Project identifier or 'global' for global terminal",
        min_length=1,
        max_length=100,
    )

    pid: int = Field(
        ...,
        description="Process ID of the Alacritty terminal",
        gt=0,
    )

    window_id: int = Field(
        ...,
        description="Sway window container ID",
        gt=0,
    )

    mark: str = Field(
        ...,
        description="Sway window mark in format 'scratchpad:{project_name}'",
        pattern=r"^scratchpad:.+$",
    )

    working_dir: Path = Field(
        ...,
        description="Initial working directory (project root)",
    )

    created_at: float = Field(
        default_factory=time.time,
        description="Unix timestamp of terminal creation",
    )

    last_shown_at: Optional[float] = Field(
        None,
        description="Unix timestamp of last show operation",
    )

    @field_validator("project_name")
    @classmethod
    def validate_project_name(cls, v: str) -> str:
        """Validate project name contains only alphanumeric characters and hyphens."""
        if not v.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Project name must be alphanumeric with optional hyphens/underscores")
        return v

    @field_validator("working_dir")
    @classmethod
    def validate_working_dir(cls, v: Path) -> Path:
        """Validate working directory is absolute path."""
        if not v.is_absolute():
            raise ValueError("Working directory must be absolute path")
        return v

    def is_process_running(self) -> bool:
        """Check if the terminal process is still running."""
        return psutil.pid_exists(self.pid)

    def mark_shown(self) -> None:
        """Update last_shown_at timestamp to current time."""
        self.last_shown_at = time.time()

    @classmethod
    def create_mark(cls, project_name: str) -> str:
        """Generate Sway mark for project scratchpad terminal."""
        return f"scratchpad:{project_name}"

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "project_name": self.project_name,
            "pid": self.pid,
            "window_id": self.window_id,
            "mark": self.mark,
            "working_dir": str(self.working_dir),
            "created_at": self.created_at,
            "last_shown_at": self.last_shown_at,
        }
```

**Invariants**:
- `mark` must always equal `f"scratchpad:{project_name}"`
- `pid` must reference a running process for terminal to be valid
- `window_id` must exist in Sway IPC tree for terminal to be valid
- `created_at` <= `last_shown_at` (if last_shown_at is not None)

---

### ScratchpadManager

Manages lifecycle and state of all scratchpad terminals in the daemon.

**Attributes**:

| Field | Type | Description |
|-------|------|-------------|
| `terminals` | `Dict[str, ScratchpadTerminal]` | Mapping of project_name → ScratchpadTerminal |
| `sway` | `i3ipc.aio.Connection` | Async Sway IPC connection |
| `logger` | `logging.Logger` | Logger instance for diagnostics |

**Methods**:

```python
class ScratchpadManager:
    """Manages scratchpad terminal lifecycle and state."""

    def __init__(self, sway: i3ipc.aio.Connection):
        self.terminals: Dict[str, ScratchpadTerminal] = {}
        self.sway = sway
        self.logger = logging.getLogger(__name__)

    async def launch_terminal(
        self,
        project_name: str,
        working_dir: Path,
    ) -> ScratchpadTerminal:
        """
        Launch new scratchpad terminal for project.

        Args:
            project_name: Project identifier or "global"
            working_dir: Initial working directory for terminal

        Returns:
            ScratchpadTerminal instance

        Raises:
            RuntimeError: If terminal launch fails
            ValueError: If project already has scratchpad terminal
        """

    async def validate_terminal(self, project_name: str) -> bool:
        """
        Validate scratchpad terminal exists and is still running.

        Args:
            project_name: Project identifier

        Returns:
            True if terminal is valid, False otherwise

        Side Effects:
            Removes terminal from state if invalid (process dead or window missing)
        """

    async def toggle_terminal(self, project_name: str) -> str:
        """
        Toggle scratchpad terminal visibility (show if hidden, hide if visible).

        Args:
            project_name: Project identifier

        Returns:
            "shown" or "hidden" indicating resulting state

        Raises:
            ValueError: If terminal doesn't exist or is invalid
        """

    async def get_terminal_state(self, project_name: str) -> Optional[str]:
        """
        Get current visibility state of scratchpad terminal.

        Args:
            project_name: Project identifier

        Returns:
            "visible", "hidden", or None if terminal doesn't exist
        """

    def get_terminal(self, project_name: str) -> Optional[ScratchpadTerminal]:
        """
        Retrieve scratchpad terminal for project.

        Args:
            project_name: Project identifier

        Returns:
            ScratchpadTerminal instance or None if not found
        """

    async def cleanup_invalid_terminals(self) -> int:
        """
        Remove invalid terminals from state (dead processes, missing windows).

        Returns:
            Count of terminals cleaned up
        """

    async def list_terminals(self) -> List[ScratchpadTerminal]:
        """
        List all tracked scratchpad terminals.

        Returns:
            List of ScratchpadTerminal instances
        """
```

**Manager State Transitions**:

```
[No Terminal] --launch_terminal()--> [Terminal Visible]
[Terminal Visible] --toggle_terminal()--> [Terminal Hidden]
[Terminal Hidden] --toggle_terminal()--> [Terminal Visible]
[Terminal *] --window_close_event--> [No Terminal]
[Terminal *] --validate_terminal() fails--> [No Terminal]
```

---

## State Synchronization

### Daemon State vs Sway IPC State

The daemon maintains in-memory state (`ScratchpadManager.terminals`), but **Sway IPC is authoritative** (Constitution Principle XI).

**Synchronization Rules**:

1. **On Launch**: Daemon launches terminal → waits for window event → marks window → adds to state
2. **On Toggle**: Daemon validates via Sway IPC → issues command → updates last_shown_at
3. **On Window Close**: Sway fires event → daemon removes from state
4. **On Validation**: Daemon queries Sway IPC tree → verifies window exists → removes if missing

**Validation Logic**:

```python
async def validate_terminal(self, project_name: str) -> bool:
    """Validate terminal against Sway IPC authoritative state."""
    terminal = self.terminals.get(project_name)
    if not terminal:
        return False

    # Check 1: Process still running
    if not terminal.is_process_running():
        self.logger.warning(f"Terminal process {terminal.pid} not running for project {project_name}")
        del self.terminals[project_name]
        return False

    # Check 2: Window exists in Sway tree
    tree = await self.sway.get_tree()
    window = tree.find_by_id(terminal.window_id)
    if not window:
        self.logger.warning(f"Terminal window {terminal.window_id} not found in Sway tree for project {project_name}")
        del self.terminals[project_name]
        return False

    # Check 3: Window has correct mark
    if terminal.mark not in window.marks:
        self.logger.warning(f"Terminal window {terminal.window_id} missing mark {terminal.mark}")
        # Re-apply mark
        await self.sway.command(f'[con_id={terminal.window_id}] mark {terminal.mark}')

    return True
```

---

## Environment Variables

Scratchpad terminals receive injected environment variables for identification and integration.

**Injected Variables**:

| Variable | Value | Purpose |
|----------|-------|---------|
| `I3PM_SCRATCHPAD` | `"true"` | Identifies window as scratchpad terminal |
| `I3PM_PROJECT_NAME` | `project_name` or `"global"` | Associates terminal with project |
| `I3PM_WORKING_DIR` | `/path/to/project` | Records initial working directory |
| `I3PM_APP_ID` | `scratchpad-{project}-{timestamp}` | Unique identifier for launch |
| `I3PM_APP_NAME` | `"scratchpad-terminal"` | Application name for i3pm registry |
| `I3PM_SCOPE` | `"scoped"` | Indicates window should be project-scoped |

**Reading Environment Variables** (from `/proc/<pid>/environ`):

```python
def read_process_environ(pid: int) -> Dict[str, str]:
    """
    Read environment variables from process.

    Args:
        pid: Process ID

    Returns:
        Dictionary of environment variables

    Raises:
        ProcessLookupError: If process doesn't exist
        PermissionError: If unable to read process environ
    """
    environ_path = Path(f"/proc/{pid}/environ")
    try:
        environ_bytes = environ_path.read_bytes()
        environ_str = environ_bytes.decode("utf-8", errors="ignore")
        env_pairs = environ_str.split("\x00")
        env_dict = {}
        for pair in env_pairs:
            if "=" in pair:
                key, value = pair.split("=", 1)
                env_dict[key] = value
        return env_dict
    except FileNotFoundError:
        raise ProcessLookupError(f"Process {pid} not found")
    except PermissionError:
        raise PermissionError(f"Cannot read environ for process {pid}")
```

---

## Window Marks

Sway window marks uniquely identify scratchpad terminals across hide/show operations.

**Mark Format**: `scratchpad:{project_name}`

**Examples**:
- Project "nixos" → `scratchpad:nixos`
- Project "dotfiles" → `scratchpad:dotfiles`
- Global terminal → `scratchpad:global`

**Mark Operations**:

```python
# Apply mark to window
mark = ScratchpadTerminal.create_mark(project_name)
await sway.command(f'[con_id={window_id}] mark {mark}')

# Query windows by mark
tree = await sway.get_tree()
marked_windows = [w for w in tree.descendants() if mark in w.marks]

# Remove mark (on cleanup)
await sway.command(f'[con_mark="{mark}"] unmark {mark}')
```

**Mark Uniqueness**: Enforced by allowing only one scratchpad terminal per project. Launch validation checks for existing mark before creating new terminal.

---

## JSON Serialization

For daemon state persistence (future) and RPC responses.

**ScratchpadTerminal JSON Schema**:

```json
{
  "project_name": "nixos",
  "pid": 123456,
  "window_id": 94489280339584,
  "mark": "scratchpad:nixos",
  "working_dir": "/etc/nixos",
  "created_at": 1730815200.123,
  "last_shown_at": 1730815300.456
}
```

**ScratchpadManager State Snapshot**:

```json
{
  "terminals": {
    "nixos": {
      "project_name": "nixos",
      "pid": 123456,
      "window_id": 94489280339584,
      "mark": "scratchpad:nixos",
      "working_dir": "/etc/nixos",
      "created_at": 1730815200.123,
      "last_shown_at": 1730815300.456
    },
    "dotfiles": {
      "project_name": "dotfiles",
      "pid": 123457,
      "window_id": 94489280339600,
      "mark": "scratchpad:dotfiles",
      "working_dir": "/home/user/dotfiles",
      "created_at": 1730815250.789,
      "last_shown_at": null
    }
  },
  "count": 2
}
```

---

## Validation Rules

### Terminal Validation (on every operation)

```python
async def validate_terminal(terminal: ScratchpadTerminal, sway: Connection) -> bool:
    """Validate terminal against all requirements."""

    # Rule 1: Process must be running
    if not psutil.pid_exists(terminal.pid):
        return False

    # Rule 2: Window must exist in Sway tree
    tree = await sway.get_tree()
    window = tree.find_by_id(terminal.window_id)
    if not window:
        return False

    # Rule 3: Window must have correct mark
    if terminal.mark not in window.marks:
        # Re-apply mark (recoverable)
        await sway.command(f'[con_id={terminal.window_id}] mark {terminal.mark}')

    # Rule 4: Window app_id must be Alacritty
    if window.app_id and "alacritty" not in window.app_id.lower():
        return False

    return True
```

### Launch Validation (before creating terminal)

```python
async def validate_launch_request(project_name: str, working_dir: Path) -> None:
    """Validate launch request meets requirements."""

    # Rule 1: Project name must be valid
    if not project_name or not project_name.replace("-", "").replace("_", "").isalnum():
        raise ValueError(f"Invalid project name: {project_name}")

    # Rule 2: Working directory must exist
    if not working_dir.exists() or not working_dir.is_dir():
        raise ValueError(f"Working directory does not exist: {working_dir}")

    # Rule 3: No existing terminal for project
    mark = ScratchpadTerminal.create_mark(project_name)
    tree = await sway.get_tree()
    existing = [w for w in tree.descendants() if mark in w.marks]
    if existing:
        raise ValueError(f"Scratchpad terminal already exists for project: {project_name}")
```

---

## Error Handling

### Terminal Launch Errors

| Error Condition | Exception | Recovery Action |
|----------------|-----------|-----------------|
| Alacritty not found | `FileNotFoundError` | Fail fast, log error, notify user |
| Working dir doesn't exist | `ValueError` | Fail fast, validate project configuration |
| Terminal already exists | `ValueError` | Validate and reuse existing, or fail |
| Window creation timeout | `RuntimeError` | Retry once after 1s, then fail |

### Terminal Toggle Errors

| Error Condition | Exception | Recovery Action |
|----------------|-----------|-----------------|
| Terminal doesn't exist | `ValueError` | Launch new terminal instead |
| Terminal process dead | `ProcessLookupError` | Remove from state, launch new |
| Window missing from Sway | `RuntimeError` | Remove from state, launch new |
| Sway command fails | `RuntimeError` | Log error, retry once, then fail |

---

## Future Extensions

**Out of scope for initial implementation, documented for future reference**:

1. **Multiple terminals per project**: Extend model with terminal ID/name, change key from project_name to (project_name, terminal_id)
2. **Configurable terminal dimensions**: Add `width` and `height` fields to ScratchpadTerminal, expose via config file
3. **Terminal persistence across restarts**: Serialize state to JSON file, restore on daemon startup (with validation)
4. **Terminal auto-hide on project switch**: Add configuration flag, implement via project switch event handler
5. **Custom terminal emulator support**: Abstract terminal launcher interface, implement for different emulators
6. **Terminal session restoration**: Integrate with tmux/sesh for session preservation across restarts
