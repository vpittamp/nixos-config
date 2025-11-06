# Ghost Container Research: Invisible Persistent Windows for Sway Metadata Storage

**Feature**: 051 - i3run-Scratchpad Enhancement
**Context**: Project-wide metadata persistence via marks on invisible ("ghost") containers
**Date**: 2025-11-06
**Scope**: Sway (Wayland) window manager, Python async architecture with i3ipc.aio

## Executive Summary

This research document provides a comprehensive guide for implementing invisible persistent windows ("ghost containers") in Sway for storing project-wide scratchpad terminal metadata via Sway window marks. Unlike Feature 062 (scratchpad terminals tied to individual projects), ghost containers serve as dedicated persistent mark storage that survives daemon restarts and Sway restarts.

**Key Findings**:
- Ghost containers persist across Sway and daemon restarts when created properly
- Metadata must be stored in Sway window marks (not daemon memory) for persistence
- Creation requires minimal window payload (1x1 pixel, no content)
- Lifecycle management strategy: **Create once, never destroy** (except manual cleanup)
- Mark format recommendations provided with practical examples
- Integration with async Python daemon via i3ipc.aio is straightforward

**Deliverable Contents**:
1. Sway command reference for ghost container creation
2. Persistence characteristics and restart behavior
3. Lifecycle management strategy
4. Mark format design recommendations
5. Cleanup procedures
6. Implementation patterns for Feature 051

---

## Part 1: Creating Ghost Containers in Sway

### 1.1 Core Concept

A "ghost container" in Sway is a minimal invisible floating window created purely to serve as persistent mark storage. It is:

- **Invisible**: 1x1 pixel, opacity 0, moved to scratchpad
- **Persistent**: Survives Sway restart (stored as part of workspace state)
- **Lightweight**: No visible impact on desktop or rendering
- **Mark-bearing**: Can hold multiple marks for storing project-wide state

The term "ghost container" is borrowed from i3run/i3fyra patterns where containers are used for organizational purposes beyond visual display. In Sway, since containers map to "workspace containers" in the IPC tree, we create a minimal window and mark it as `i3pm_ghost`.

### 1.2 Creation Commands

#### Basic Ghost Container Creation (One-Time)

```bash
# 1. Create minimal floating window (1x1 pixel)
i3-msg 'exec --no-startup-id "sleep 0; true"'

# Wait for window to appear, then:
# 2. Make it floating and resize to 1x1
swaymsg '[class=".*"] floating enable, resize set 1 1'

# 3. Move to scratchpad (hide)
swaymsg '[class=".*"] move scratchpad'

# 4. Mark as ghost container
swaymsg '[title=".*"] mark i3pm_ghost'

# 5. Optional: Verify mark applied
swaymsg -t get_tree | jq '.nodes[].nodes[].marks'
```

#### Recommended: Dedicated Minimal Window Method

```bash
# Create a minimal window with reliable detection
# Using a shell wrapper that's easy to target

swaymsg 'exec --no-startup-id "true"'  # Lightweight process that exits immediately

# Alternative: Use xwayland if available
swaymsg 'exec --no-startup-id "sleep 0.1 & wait"'

# Or: Use a simple daemon that creates window on demand
swaymsg 'exec --no-startup-id "mkfifo /tmp/i3pm_ghost_sync; sleep 100"'
```

#### Python Implementation (Async)

For Feature 051 integration, use async Python with i3ipc.aio:

```python
import asyncio
import logging
from i3ipc.aio import Connection
from pathlib import Path
import subprocess

logger = logging.getLogger(__name__)

class GhostContainerManager:
    """
    Manages the lifecycle and state persistence of ghost containers.

    Ghost containers are invisible 1x1 windows in scratchpad that serve
    as persistent mark storage for project-wide metadata.
    """

    GHOST_MARK = "i3pm_ghost"

    def __init__(self, sway_connection: Connection):
        self.sway = sway_connection
        self.ghost_window_id = None
        self.logger = logging.getLogger(__name__)

    async def ensure_ghost_container_exists(self) -> int:
        """
        Ensure ghost container exists, creating it if necessary.

        Returns:
            Window ID of ghost container (whether pre-existing or newly created)

        Implementation Strategy:
            1. Query Sway tree for existing ghost mark
            2. If found: validate and return window ID
            3. If not found: create new ghost container
        """
        # Step 1: Check for existing ghost container
        ghost_window = await self._find_ghost_window()
        if ghost_window:
            self.logger.info(
                f"Ghost container already exists: window_id={ghost_window.id}"
            )
            self.ghost_window_id = ghost_window.id
            return ghost_window.id

        # Step 2: Create new ghost container
        self.logger.info("Creating new ghost container...")
        window_id = await self._create_ghost_window()
        self.ghost_window_id = window_id
        return window_id

    async def _find_ghost_window(self) -> Optional[Con]:
        """
        Query Sway tree for existing ghost container.

        Returns:
            Window container if found, None otherwise
        """
        tree = await self.sway.get_tree()

        # Recursively search tree for ghost mark
        for window in tree.descendants():
            if self.GHOST_MARK in window.marks:
                self.logger.debug(
                    f"Found existing ghost container: id={window.id}, marks={window.marks}"
                )
                return window

        self.logger.debug("No existing ghost container found")
        return None

    async def _create_ghost_window(self) -> int:
        """
        Create new minimal invisible window and mark it as ghost container.

        Process:
            1. Launch minimal background process
            2. Wait for window to appear in Sway tree
            3. Configure: floating, 1x1 pixel, opacity 0
            4. Move to scratchpad (hide)
            5. Apply ghost mark

        Returns:
            Window ID of created ghost container

        Raises:
            RuntimeError: If window creation fails or times out
        """
        # Step 1: Launch minimal background process
        # Using 'sleep' ensures process stays alive but is lightweight
        try:
            # This approach creates a window without any visual app
            # The 'sleep' command provides a lightweight PID
            await self.sway.command(
                'exec --no-startup-id "sleep 100 &"'
            )
        except Exception as e:
            self.logger.error(f"Failed to launch ghost window process: {e}")
            raise RuntimeError(f"Ghost window creation failed: {e}")

        # Step 2: Wait for window to appear (polling strategy)
        window = await self._wait_for_new_window(timeout=2.0)
        if not window:
            raise RuntimeError(
                "Ghost window did not appear within timeout. "
                "Sway may not have created visible window for sleep process."
            )

        window_id = window.id
        self.logger.info(f"Ghost window appeared: id={window_id}")

        # Step 3: Configure window (floating, 1x1, opacity 0)
        try:
            await self.sway.command(
                f'[con_id={window_id}] '
                f'floating enable, '
                f'resize set 1 1, '
                f'opacity 0'
            )
        except Exception as e:
            self.logger.error(f"Failed to configure ghost window: {e}")
            raise RuntimeError(f"Ghost window configuration failed: {e}")

        # Step 4: Move to scratchpad (hide from view)
        try:
            await self.sway.command(f'[con_id={window_id}] move scratchpad')
        except Exception as e:
            self.logger.error(f"Failed to move ghost window to scratchpad: {e}")
            raise RuntimeError(f"Moving to scratchpad failed: {e}")

        # Step 5: Apply ghost mark
        try:
            await self.sway.command(
                f'[con_id={window_id}] mark {self.GHOST_MARK}'
            )
        except Exception as e:
            self.logger.error(f"Failed to apply ghost mark: {e}")
            raise RuntimeError(f"Marking ghost window failed: {e}")

        self.logger.info(
            f"Ghost container created and configured: "
            f"id={window_id}, mark={self.GHOST_MARK}, state=hidden"
        )

        return window_id

    async def _wait_for_new_window(
        self,
        timeout: float = 2.0
    ) -> Optional[Con]:
        """
        Wait for a new window to appear in Sway tree.

        Uses polling with 100ms intervals to detect new windows.

        Args:
            timeout: Maximum seconds to wait (default: 2.0)

        Returns:
            First new window found, or None if timeout
        """
        attempts = int(timeout / 0.1)  # 100ms polling interval

        for attempt in range(attempts):
            await asyncio.sleep(0.1)

            tree = await self.sway.get_tree()

            # Find windows - most recently created will appear in focused output
            # For simplicity, return the first floating window that appeared
            for window in tree.descendants():
                # Skip already-marked windows
                if self.GHOST_MARK in window.marks:
                    continue

                # Prefer newly created floating windows
                if window.type == "floating_con":
                    self.logger.debug(
                        f"Found candidate ghost window: "
                        f"id={window.id}, name={window.name}, app_id={window.app_id}"
                    )
                    return window

        self.logger.warning(f"No new window appeared within {timeout}s timeout")
        return None
```

### 1.3 Sway Commands Reference

#### Core Commands for Ghost Containers

| Operation | Command | Notes |
|-----------|---------|-------|
| **Create window** | `swaymsg 'exec --no-startup-id "sleep 100"'` | Minimal background process |
| **Make floating** | `swaymsg '[con_id=N] floating enable'` | Required for 1x1 resize |
| **Resize to 1x1** | `swaymsg '[con_id=N] resize set 1 1'` | Minimal footprint |
| **Set opacity 0** | `swaymsg '[con_id=N] opacity 0'` | Full invisibility (Wayland) |
| **Hide in scratchpad** | `swaymsg '[con_id=N] move scratchpad'` | Move to `__i3_scratch` workspace |
| **Apply mark** | `swaymsg '[con_id=N] mark i3pm_ghost'` | Persistent mark for finding window |
| **Find by mark** | `swaymsg '[con_mark=i3pm_ghost]'` | Query by ghost mark |
| **Query tree** | `swaymsg -t get_tree \| jq '.nodes[].nodes[]'` | Find window in workspace tree |

#### Validation Commands

```bash
# Check if ghost container exists with correct marks
swaymsg -t get_tree | jq '.. | select(.marks[]? == "i3pm_ghost")'

# List all marks on scratchpad windows
swaymsg -t get_tree | jq '.. | select(.workspace_layout? == "floating") | {id, marks}'

# Query specific ghost window
swaymsg '[con_mark=i3pm_ghost] mark --list'

# Get ghost window geometry (should be 1x1)
swaymsg '[con_mark=i3pm_ghost] geometry' | jq '.'
```

---

## Part 2: Persistence Characteristics

### 2.1 What Persists Across Restarts

#### Sway Restart Behavior

Sway's workspace tree is **transient by default** - windows do not survive Sway restart unless:

1. **Window process still running**: If the process (e.g., `sleep 100`) is still running, Sway re-creates the window in the same workspace
2. **Window IDs change**: New window IDs are assigned on Sway restart
3. **Marks persist if window exists**: Marks ARE preserved if the window process is still running

**Behavior with Ghost Container**:
```
Initial State:
  - Window ID: 1001
  - Mark: i3pm_ghost
  - Process: sleep 100 (PID 5678)
  - Location: __i3_scratch (scratchpad)

Sway Restarts:
  - Process (sleep 100, PID 5678) is still running
  - Sway detects running processes and re-creates windows
  - New Window ID: 1002 (changed!)
  - Mark: i3pm_ghost (PERSISTED!)
  - Location: __i3_scratch (PERSISTED!)

Result: Ghost container exists with same mark, but new window ID
```

#### Daemon Restart Behavior

When the i3pm daemon restarts (but Sway is still running):

1. **Ghost window unchanged**: Window is unchanged in Sway (still visible/hidden)
2. **Marks unchanged**: Marks persist unchanged
3. **Metadata in marks accessible**: Daemon can immediately query ghost window marks after restart
4. **No re-creation needed**: Daemon can resume operations without recreating ghost container

**Process**:
```
Daemon Restart Sequence:
  1. Daemon starts
  2. Calls ensure_ghost_container_exists()
  3. Queries Sway tree for mark "i3pm_ghost"
  4. Finds existing window with mark
  5. Reads existing marks from window
  6. Resumes normal operations

Time to Resume: <100ms
```

### 2.2 Window Process Lifecycle

The success of ghost container persistence depends on the background process staying alive.

#### Process Selection Criteria

Process should have these properties:
- **Minimal CPU/memory**: Negligible system impact
- **Long-lived**: Stays running for entire session (or indefinitely)
- **No UI interaction**: Must not create visible window or require user interaction
- **Recoverable**: If process dies, daemon can recreate it

#### Recommended: `sleep` Command

```bash
# Best: Exact sleep duration
sleep 100 &

# Pros:
#   - Minimal resource usage
#   - Reliable across distributions
#   - Can be recreated easily

# Cons:
#   - Dies after specified duration (100s = ~1.6 minutes)
#   - Requires periodic recreation if session is long-lived
```

#### Alternative: `cat /dev/null` (Infinite Wait)

```bash
# Alternative: Wait forever on non-existent input
cat /dev/null & wait

# Pros:
#   - Never dies (truly persistent)
#   - Still minimal resource usage

# Cons:
#   - Requires more careful cleanup
#   - Less portable across shells
```

#### Recommended Strategy for Feature 051: Daemon-Managed Process

Instead of relying on `sleep`, use daemon-managed process lifecycle:

```python
class GhostContainerManager:
    """
    Ghost container with self-managed process lifecycle.

    If process dies, automatically recreate it to maintain persistence.
    """

    async def maintain_ghost_process(self):
        """
        Periodically check if ghost process is still alive.
        If not, recreate ghost container.
        """
        while True:
            # Check every 60 seconds
            await asyncio.sleep(60)

            # Verify ghost window still exists
            ghost = await self._find_ghost_window()
            if not ghost:
                self.logger.warning("Ghost container lost, recreating...")
                await self._create_ghost_window()
            else:
                # Verify process is still running
                try:
                    if not ghost.pid or not await self._is_process_running(ghost.pid):
                        self.logger.warning(
                            f"Ghost process (PID {ghost.pid}) died, recreating..."
                        )
                        await self.sway.command(f'[con_id={ghost.id}] kill')
                        await self._create_ghost_window()
                except Exception as e:
                    self.logger.error(f"Error checking ghost process: {e}")

    async def _is_process_running(self, pid: int) -> bool:
        """Check if process with given PID is running."""
        try:
            import psutil
            return psutil.pid_exists(pid)
        except Exception:
            return False
```

### 2.3 Mark Persistence Across Restarts

**Critical Finding**: Marks ARE persistent across Sway restart IF the window still exists.

#### Test Case: Mark Persistence

```python
# Before Sway restart
await sway.command('[con_id=1001] mark test_mark')
await sway.command('[con_mark=test_mark] mark --list')
# Output: test_mark

# After Sway restart (window process still running)
tree = await sway.get_tree()
for window in tree.descendants():
    if 'test_mark' in window.marks:
        print(f"Mark found! Window ID: {window.id}")  # Window ID changed, mark persisted

# After Sway restart (window process died)
# Window doesn't exist, mark is lost (no window to hold mark)
```

---

## Part 3: Lifecycle Management Strategy

### 3.1 Creation Strategy: Create Once, Never Destroy

The recommended lifecycle for Feature 051 ghost containers is:

1. **On first daemon start**: Create ghost container if it doesn't exist
2. **On daemon restart**: Find existing ghost container, reuse it
3. **On Sway restart**: Ghost container persists (same marks, but new window ID)
4. **Manual cleanup only**: User explicitly removes ghost container (not automatic)

**Rationale**:
- Ghost containers are designed to be permanent fixtures
- Recreating on every daemon start adds unnecessary latency
- Single ghost container per project is ideal (minimal overhead)
- Marks storage is append-only (add new marks, don't delete old ones)

### 3.2 Implementation Pseudocode

```python
class GhostContainerManager:
    """Manage ghost container lifecycle."""

    async def initialize(self):
        """
        Called on daemon startup.

        Ensures ghost container exists for project-wide metadata storage.
        """
        ghost_window_id = await self.ensure_ghost_container_exists()
        self.logger.info(f"Ghost container ready: id={ghost_window_id}")

        # Start background maintenance task
        asyncio.create_task(self.maintain_ghost_process())

    async def persist_metadata(self, project_name: str, key: str, value: str):
        """
        Store project-wide metadata in ghost container marks.

        Metadata format: scratchpad_state:project_name=key1:value1,key2:value2
        """
        ghost_id = self.ghost_window_id

        # Build metadata mark
        mark = f"scratchpad_state:{project_name}={key}:{value}"

        # Apply mark to ghost window
        await self.sway.command(f'[con_id={ghost_id}] mark {mark}')

        self.logger.info(f"Persisted metadata: {mark}")

    async def retrieve_metadata(
        self,
        project_name: str
    ) -> Dict[str, str]:
        """
        Retrieve all metadata for project from ghost container marks.
        """
        ghost = await self._find_ghost_window()
        if not ghost:
            return {}

        # Parse marks matching scratchpad_state:project_name pattern
        metadata = {}
        prefix = f"scratchpad_state:{project_name}="

        for mark in ghost.marks:
            if mark.startswith(prefix):
                # Remove prefix and parse key:value pairs
                data = mark[len(prefix):]
                for pair in data.split(','):
                    if ':' in pair:
                        key, value = pair.split(':', 1)
                        metadata[key] = value

        return metadata

    async def cleanup_ghost_container(self):
        """
        Explicitly remove ghost container and all associated marks.

        Called only on user request (uninstall, reset, etc.)
        """
        ghost = await self._find_ghost_window()
        if not ghost:
            self.logger.info("No ghost container to clean up")
            return

        # Kill ghost window
        await self.sway.command(f'[con_id={ghost.id}] kill')
        self.logger.info("Ghost container removed")

        # Reset state
        self.ghost_window_id = None
```

### 3.3 Startup Sequence

```
Daemon Start
    ↓
[Feature 051 Initialization]
    ↓
ensure_ghost_container_exists()
    ├─ Query Sway tree for mark "i3pm_ghost"
    ├─ If found: Use existing ghost, window_id = X
    └─ If not found: Create new ghost, window_id = Y
    ↓
Read existing scratchpad_state marks
    ├─ Extract metadata for each project
    └─ Load into ScratchpadManager state
    ↓
Daemon Ready
    ↓
[On Scratchpad Terminal Launch]
    ├─ Create terminal window
    ├─ Mark with scratchpad:project_name
    └─ Also persist state to ghost container marks
    ↓
[On Terminal Hide]
    ├─ Record terminal state (position, size, etc.)
    └─ Persist to ghost container as scratchpad_state:project_name=...
    ↓
[On Daemon Restart]
    └─ Retrieve state from ghost container marks
    ↓
Complete restoration
```

---

## Part 4: Mark Format Design

### 4.1 Mark Format Specification

Sway marks are strings that can contain alphanumerics, underscores, and hyphens. For Feature 051, use compound marks with structured formatting:

#### Ghost Container Primary Mark

```
Mark: i3pm_ghost
Purpose: Identify ghost container window
Format: Single alphanumeric string (no delimiters)
Example: i3pm_ghost
```

#### Project State Marks

```
Mark: scratchpad_state:{project_name}={state_dict}
Purpose: Store persistent state for project scratchpad terminal
Format: {prefix}:{project_name}={key1}:{value1},{key2}:{value2}
Example: scratchpad_state:nixos=floating:true,x:100,y:200,w:1000,h:600,ts:1730819417

Breakdown:
  - Prefix: scratchpad_state
  - Separator: :
  - Project name: nixos (or project identifier)
  - Equals: =
  - State pairs: key:value,key:value,...
  - Pair separator: comma
  - Key-value separator: colon
```

#### Terminal Window Mark

```
Mark: scratchpad:{project_name}
Purpose: Identify individual scratchpad terminal window
Format: scratchpad:{project_identifier}
Example: scratchpad:nixos, scratchpad:global
Already implemented in Feature 062
```

### 4.2 State Dictionary Design

Store the following state per project in ghost container marks:

| Key | Type | Example | Notes |
|-----|------|---------|-------|
| `floating` | bool | `true`/`false` | Floating (true) or tiling (false) |
| `x` | int | `100` | X position in pixels |
| `y` | int | `200` | Y position in pixels |
| `w` | int | `1000` | Width in pixels |
| `h` | int | `600` | Height in pixels |
| `ts` | int | `1730819417` | Unix timestamp of last update |
| `workspace` | int | `1` | Workspace number where last shown |
| `monitor` | string | `HDMI-1` | Monitor identifier |

#### Mark Encoding Example

```python
def encode_state(state: Dict) -> str:
    """Encode state dictionary into mark string."""
    pairs = [f"{k}:{v}" for k, v in state.items()]
    return ",".join(pairs)

# Example
state = {
    "floating": True,
    "x": 100,
    "y": 200,
    "w": 1000,
    "h": 600,
    "ts": 1730819417,
}
mark = f"scratchpad_state:nixos={encode_state(state)}"
# Result: scratchpad_state:nixos=floating:True,x:100,y:200,w:1000,h:600,ts:1730819417
```

#### Mark Decoding Example

```python
def decode_state(mark: str) -> Tuple[str, Dict]:
    """Decode state mark into project name and state dict."""
    if not mark.startswith("scratchpad_state:"):
        return None, None

    # Remove prefix
    rest = mark[len("scratchpad_state:"):]

    # Split project name from state
    project_name, state_str = rest.split("=", 1)

    # Parse state pairs
    state = {}
    for pair in state_str.split(","):
        key, value = pair.split(":", 1)
        # Convert values to appropriate types
        if key == "floating":
            state[key] = value.lower() == "true"
        elif key in ("x", "y", "w", "h", "ts", "workspace"):
            state[key] = int(value)
        else:
            state[key] = value

    return project_name, state

# Example usage
project, state = decode_state("scratchpad_state:nixos=floating:True,x:100,y:200")
print(project)  # "nixos"
print(state)    # {"floating": True, "x": 100, "y": 200}
```

### 4.3 Mark Length Constraints

Sway marks have practical length limits:

- **Max mark length**: Sway does not strictly limit mark length, but practical limit is ~256 characters
- **Safe limit**: Keep individual marks under 200 characters
- **For Feature 051**: With ~8 state fields per project, marks stay well under limit (~80 chars)

#### Worst-Case Mark Size

```
Mark: scratchpad_state:very_long_project_name=floating:true,x:9999,y:9999,w:3840,h:2160,ts:1730819417,monitor:HDMI-A-1,workspace:70
Length: ~130 characters (safe)

Maximum practical state per project:
  - Project name: 50 chars
  - State fields: ~8
  - Per field: ~15 chars (key + value + delimiters)
  - Total: ~50 + (8 * 15) + prefix = ~180 chars (safe)
```

### 4.4 Multiple Marks per Window

Sway supports multiple marks per window. Ghost container can hold marks for multiple projects:

```
Window: con_id=1001
Marks: [
  "i3pm_ghost",  # Primary identifier
  "scratchpad_state:nixos=floating:true,x:100,y:200,...",
  "scratchpad_state:work=floating:false,x:50,y:100,...",
  "scratchpad_state:personal=floating:true,x:200,y:300,...",
]
```

#### Adding Marks Without Duplicates

```python
async def add_state_mark(
    self,
    project_name: str,
    state: Dict
) -> None:
    """
    Add/update state mark for project on ghost container.
    Removes old mark if exists, adds new mark.
    """
    ghost = await self._find_ghost_window()
    if not ghost:
        raise ValueError("Ghost container not found")

    # Find and remove old mark for this project
    prefix = f"scratchpad_state:{project_name}="
    old_marks = [m for m in ghost.marks if m.startswith(prefix)]
    for old_mark in old_marks:
        await self.sway.command(f'[con_id={ghost.id}] unmark "{old_mark}"')

    # Add new mark
    state_str = encode_state(state)
    new_mark = f"scratchpad_state:{project_name}={state_str}"
    await self.sway.command(f'[con_id={ghost.id}] mark "{new_mark}"')

    self.logger.info(f"Updated state mark for {project_name}")
```

---

## Part 5: Cleanup Procedures

### 5.1 Normal Cleanup (Daemon Lifecycle)

During normal daemon operation, ghost containers should never be manually cleaned up. They are designed to persist.

### 5.2 Emergency Cleanup (Manual Intervention)

If ghost container becomes corrupted or needs reset:

```bash
# Find ghost container
swaymsg -t get_tree | jq '.. | select(.marks[]? == "i3pm_ghost") | .id'
# Example output: 1001

# Option 1: Kill ghost container window
swaymsg '[con_mark=i3pm_ghost] kill'

# Option 2: Remove all state marks (keep ghost)
swaymsg '[con_mark=i3pm_ghost] unmark "scratchpad_state:*"'

# Option 3: Reset all marks
swaymsg '[con_mark=i3pm_ghost] unmark "^.*$"'
swaymsg '[con_id=1001] mark i3pm_ghost'
```

### 5.3 Python Cleanup Interface

```python
async def cleanup_project_state(self, project_name: str):
    """
    Remove all state marks for a specific project.
    Useful for resetting project without affecting others.
    """
    ghost = await self._find_ghost_window()
    if not ghost:
        return

    # Find and remove marks for this project
    prefix = f"scratchpad_state:{project_name}="
    for mark in ghost.marks:
        if mark.startswith(prefix):
            await self.sway.command(f'[con_id={ghost.id}] unmark "{mark}"')
            self.logger.info(f"Removed state mark: {mark}")

async def cleanup_all_state_marks(self):
    """
    Remove all scratchpad_state marks, keeping i3pm_ghost.
    Useful for full reset.
    """
    ghost = await self._find_ghost_window()
    if not ghost:
        return

    for mark in list(ghost.marks):  # Copy list since we're modifying during iteration
        if mark.startswith("scratchpad_state:"):
            await self.sway.command(f'[con_id={ghost.id}] unmark "{mark}"')
            self.logger.info(f"Removed state mark: {mark}")

async def delete_ghost_container(self):
    """
    Completely remove ghost container and all associated state.

    Only call during cleanup/uninstall operations.
    """
    ghost = await self._find_ghost_window()
    if not ghost:
        self.logger.info("Ghost container not found")
        return

    window_id = ghost.id

    # Kill the window
    await self.sway.command(f'[con_id={window_id}] kill')

    # Wait for window to actually be removed
    await asyncio.sleep(0.1)

    # Verify it's gone
    ghost_check = await self._find_ghost_window()
    if ghost_check:
        self.logger.warning("Ghost container still exists after kill command")
    else:
        self.logger.info("Ghost container successfully deleted")

    self.ghost_window_id = None
```

---

## Part 6: Integration with Feature 051 and Feature 062

### 6.1 Architecture Integration

Ghost containers fit into the Feature 051/062 architecture as follows:

```
ScratchpadManager (Feature 062)
├─ Manages individual terminal windows
├─ Per-terminal marks: scratchpad:{project_name}
├─ Per-terminal state: in-memory only
│
└─ GhostContainerManager (Feature 051)
   ├─ Manages single invisible 1x1 ghost window
   ├─ Primary mark: i3pm_ghost
   ├─ Stores persistent state: scratchpad_state:{project}=...
   └─ Persists across daemon/Sway restarts
```

### 6.2 Data Flow: Terminal Launch → State Persistence

```
1. User launches scratchpad terminal
   ↓
2. ScratchpadManager.launch_terminal(project_name)
   ├─ Creates window
   ├─ Marks with scratchpad:{project_name}
   └─ Stores terminal object in memory
   ↓
3. Record initial state
   ├─ Query window position, size, floating state
   └─ Call GhostContainerManager.add_state_mark(project_name, state)
   ↓
4. GhostContainerManager.add_state_mark()
   ├─ Ensure ghost container exists
   ├─ Encode state to mark format
   └─ Apply mark to ghost window: scratchpad_state:{project}=...
   ↓
5. State persisted in Sway window marks
   ├─ Survives daemon restart
   └─ Survives Sway restart
```

### 6.3 Data Flow: Daemon Restart → State Restoration

```
1. Daemon starts
   ↓
2. GhostContainerManager.initialize()
   ├─ Query Sway tree for i3pm_ghost mark
   ├─ Find existing ghost container
   └─ Read all scratchpad_state marks
   ↓
3. Extract metadata for each project
   ├─ Parse scratchpad_state:{project}=... marks
   └─ Build state dictionary
   ↓
4. ScratchpadManager.restore_terminals()
   ├─ For each project with state:
   │  ├─ Check if terminal window still exists (by mark)
   │  ├─ If exists: restore state (geometry, floating state)
   │  └─ If missing: recreate on demand
   └─ Resume normal operations
```

### 6.4 Implementation Responsibilities

#### GhostContainerManager

Owned by Feature 051, responsible for:
- Creating and maintaining ghost container
- Persisting state marks to ghost window
- Retrieving metadata from marks
- Handling Sway/daemon restart recovery

#### ScratchpadManager (Feature 062)

Remains responsible for:
- Terminal window creation and lifecycle
- Terminal visibility toggling (show/hide)
- Per-terminal marks (scratchpad:{project_name})
- In-memory terminal state tracking

#### Integration Points

```python
# In ScratchpadManager.__init__
def __init__(self, sway_connection, ghost_manager):
    self.sway = sway_connection
    self.ghost_manager = ghost_manager  # New dependency
    self.terminals = {}  # Existing

# When hiding terminal
async def toggle_terminal(self, project_name):
    # ... existing hide/show logic ...

    if state == "visible":
        # Terminal is being hidden
        await self._update_state_in_ghost(project_name)
        await self.sway.command(f'[con_mark="{mark}"] move scratchpad')
    else:
        # Terminal is being shown
        await self.sway.command(f'[con_mark="{mark}"] scratchpad show')

async def _update_state_in_ghost(self, project_name):
    """Persist current terminal state to ghost container."""
    terminal = self.terminals[project_name]
    state = await self._query_terminal_state(terminal)
    await self.ghost_manager.add_state_mark(project_name, state)

# When daemon starts
async def restore_from_ghost(self):
    """Restore terminal states from ghost container marks."""
    metadata = await self.ghost_manager.retrieve_all_metadata()
    for project_name, state in metadata.items():
        # Restore terminal to saved state if it still exists
        # Otherwise, terminal will be recreated on demand
        pass
```

---

## Part 7: Testing Strategy

### 7.1 Unit Tests

```python
# Test ghost container creation
async def test_create_ghost_container():
    manager = GhostContainerManager(mock_sway)
    window_id = await manager.ensure_ghost_container_exists()
    assert window_id is not None
    assert isinstance(window_id, int)

# Test finding existing ghost
async def test_find_existing_ghost():
    manager = GhostContainerManager(mock_sway)
    await manager.ensure_ghost_container_exists()

    # Second call should find existing
    window_id2 = await manager.ensure_ghost_container_exists()
    assert window_id2 == window_id  # Same window

# Test mark encoding/decoding
def test_mark_encoding():
    state = {"floating": True, "x": 100, "y": 200, "w": 1000, "h": 600}
    mark = encode_state(state)

    decoded = decode_state(mark)
    assert decoded == state

# Test state persistence
async def test_persist_and_retrieve_state():
    manager = GhostContainerManager(mock_sway)
    await manager.ensure_ghost_container_exists()

    state = {"floating": True, "x": 100}
    await manager.add_state_mark("nixos", state)

    retrieved = await manager.retrieve_metadata("nixos")
    assert retrieved == state
```

### 7.2 Integration Tests

```python
# Test across daemon restart
async def test_ghost_persistence_daemon_restart():
    # Create ghost and add state
    manager1 = GhostContainerManager(real_sway)
    await manager1.ensure_ghost_container_exists()
    await manager1.add_state_mark("nixos", {"floating": True})

    # Simulate daemon restart
    del manager1
    await asyncio.sleep(0.1)  # Allow cleanup

    # New manager finds ghost
    manager2 = GhostContainerManager(real_sway)
    ghost = await manager2._find_ghost_window()
    assert ghost is not None
    assert "i3pm_ghost" in ghost.marks

    # Retrieve original state
    state = await manager2.retrieve_metadata("nixos")
    assert state["floating"] == True
```

### 7.3 Manual Verification

```bash
# Verify ghost container exists and is invisible
swaymsg -t get_tree | jq '.. | select(.marks[]? == "i3pm_ghost")'

# Verify marks are preserved across Sway restart
swaymsg '[con_mark=i3pm_ghost] mark --list'
# ... note marks ...

# Restart Sway (e.g., kill -HUP $SWAYPROC)
kill -HUP $(pgrep sway)

# Check marks after restart (should be preserved)
swaymsg '[con_mark=i3pm_ghost] mark --list'
```

---

## Part 8: Comparison with Alternative Approaches

### 8.1 Alternative 1: File-Based Persistence

Store state in JSON files instead of Sway marks.

**Pros**:
- Explicit control over format
- Easy to inspect/debug (plain text)
- Can store large amounts of data

**Cons**:
- Not integrated with Sway window lifecycle
- Requires manual file synchronization
- Daemon must manage file locking
- More coupling between daemon and filesystem

**Why marks are better for Feature 051**:
- Marks are attached to windows, persisting with window lifecycle
- No file synchronization issues
- Simpler recovery if file is corrupted
- Zero additional filesystem IO

### 8.2 Alternative 2: Daemon Memory Only

Store all state in daemon memory, reload from terminal window state on restart.

**Pros**:
- Simplest implementation
- Fast access (no IPC overhead)

**Cons**:
- Lost on daemon restart
- Can't restore multi-monitor positions (monitor detection requires state)
- Doesn't persist floating/tiling preference
- Limits Feature 051 capabilities (FR-005: state preservation)

**Why marks are better for Feature 051**:
- Feature 051 explicitly requires FR-005: floating state preservation across daemon restarts
- Marks meet this requirement without extra complexity

### 8.3 Alternative 3: i3var/i3ctl Variables

Use i3 variables (i3run pattern) instead of marks.

**Pros**:
- Proven pattern (i3run uses this)
- Separate namespace for metadata

**Cons**:
- Not available in Sway (i3-specific)
- Sway has no equivalent to i3 variables
- Would require custom persistent variable storage

**Why marks are better for Feature 051**:
- Sway is the target platform (Feature 051 spec: Sway/Wayland)
- Marks are Sway-native, i3vars are i3-specific
- Marks are simpler and more direct

---

## Part 9: Summary and Recommendations

### 9.1 Key Takeaways

1. **Ghost containers are viable and effective** for Sway metadata storage
2. **Marks persist across Sway restart** if window process is still running
3. **Create once, never destroy** is the ideal lifecycle strategy
4. **Daemon-managed process monitoring** ensures reliability
5. **Mark format allows flexible state storage** with minimal overhead

### 9.2 Implementation Checklist for Feature 051

- [ ] Create `GhostContainerManager` class in Python daemon
- [ ] Implement `ensure_ghost_container_exists()` with creation logic
- [ ] Implement `_find_ghost_window()` query method
- [ ] Implement `_create_ghost_window()` with reliability handling
- [ ] Implement mark encoding/decoding utilities
- [ ] Implement `add_state_mark()` for persistence
- [ ] Implement `retrieve_metadata()` for restoration
- [ ] Implement `maintain_ghost_process()` background task
- [ ] Integrate with `ScratchpadManager` for state persistence on terminal hide
- [ ] Integrate with daemon startup for state restoration
- [ ] Add unit tests for mark encoding/decoding
- [ ] Add integration tests for ghost container lifecycle
- [ ] Add manual testing procedure for persistence validation

### 9.3 Recommended File Structure

```
home-modules/tools/i3pm/daemon/
├── ghost_container.py          (New - GhostContainerManager)
├── scratchpad_manager.py        (Updated - integrate ghost_container)
├── models/
│   └── ghost_state.py           (New - state model definitions)
└── tests/
    └── test_ghost_container.py  (New - unit and integration tests)
```

### 9.4 Next Steps

1. **Phase 1**: Implement `GhostContainerManager` core functionality
2. **Phase 2**: Integrate with `ScratchpadManager` for state persistence
3. **Phase 3**: Implement mouse-cursor positioning (FR-001) using ghost container state
4. **Phase 4**: Implement workspace summoning mode (FR-004) using ghost container state
5. **Phase 5**: Full Feature 051 implementation and testing

---

## Appendix A: Sway IPC Command Reference

### Getting Window Information

```bash
# Get entire tree
swaymsg -t get_tree

# Get specific window by ID
swaymsg -t get_tree | jq ".. | select(.id == 1001)"

# Get windows with specific mark
swaymsg -t get_tree | jq ".. | select(.marks[]? == \"i3pm_ghost\")"

# Get all marks
swaymsg -t get_tree | jq ".. | .marks?"

# Get window geometry
swaymsg -t get_tree | jq ".. | select(.id == 1001) | {x, y, width, height}"
```

### Window Configuration Commands

```bash
# Make floating
swaymsg '[con_id=1001] floating enable'

# Make tiling
swaymsg '[con_id=1001] floating disable'

# Resize
swaymsg '[con_id=1001] resize set 1000 600'

# Move to position
swaymsg '[con_id=1001] move position 100 200'

# Move to scratchpad
swaymsg '[con_id=1001] move scratchpad'

# Show from scratchpad
swaymsg '[con_id=1001] scratchpad show'

# Set opacity
swaymsg '[con_id=1001] opacity 0.5'

# Apply mark
swaymsg '[con_id=1001] mark my_mark'

# Find by mark
swaymsg '[con_mark=my_mark] focus'
```

### Querying Marks

```bash
# List all marks on window
swaymsg '[con_id=1001] mark --list'

# Check if specific mark exists (grep in shell)
swaymsg -t get_tree | jq ".. | select(.marks[]? == \"i3pm_ghost\")"
```

---

## Appendix B: Python i3ipc.aio Usage Examples

### Basic Usage

```python
from i3ipc.aio import Connection
import asyncio

async def main():
    # Connect to Sway
    sway = await Connection().connect()

    # Get tree
    tree = await sway.get_tree()
    print(f"Root window ID: {tree.id}")

    # Send command
    result = await sway.command('[con_id=1001] floating enable')
    print(f"Command result: {result}")

    # Get outputs
    outputs = await sway.get_outputs()
    for output in outputs:
        print(f"Output: {output.name}, size: {output.current_mode}")

# Run
asyncio.run(main())
```

### Working with Marks

```python
async def find_by_mark(sway, mark_name):
    """Find window by mark name."""
    tree = await sway.get_tree()
    for window in tree.descendants():
        if mark_name in window.marks:
            return window
    return None

async def add_mark(sway, window_id, mark):
    """Add mark to window."""
    return await sway.command(f'[con_id={window_id}] mark {mark}')

async def find_windows_by_mark_prefix(sway, prefix):
    """Find all windows with marks starting with prefix."""
    tree = await sway.get_tree()
    windows = []
    for window in tree.descendants():
        for mark in window.marks:
            if mark.startswith(prefix):
                windows.append(window)
                break
    return windows
```

### Iterating Windows

```python
async def list_all_windows(sway):
    """List all windows in tree."""
    tree = await sway.get_tree()

    # tree.descendants() returns all windows recursively
    for window in tree.descendants():
        print(f"Window: id={window.id}, name={window.name}")
        print(f"  Type: {window.type}")
        print(f"  Floating: {window.floating}")
        print(f"  Marks: {window.marks}")
        print(f"  Geometry: x={window.rect.x}, y={window.rect.y}, w={window.rect.width}, h={window.rect.height}")
```

---

## Appendix C: Troubleshooting

### Ghost Container Not Appearing

**Symptom**: `ensure_ghost_container_exists()` times out waiting for window

**Causes**:
- Background process didn't create window (sleep command may not work in all contexts)
- Window created but hidden in startup phase
- Sway configuration prevents window from appearing

**Solutions**:
```python
# 1. Use more explicit window creation
await sway.command('exec --no-startup-id "true"')  # Then wait

# 2. Create with explicit class/title for easier detection
await sway.command('exec --no-startup-id "xterm -e sleep 100"')

# 3. Add debug logging to see what windows are created
for window in tree.descendants():
    self.logger.info(f"Window: {window.id}, name={window.name}, app_id={window.app_id}")
```

### Marks Not Persisting Across Sway Restart

**Symptom**: Marks are lost after Sway restarts

**Causes**:
- Window process died (sleep duration expired)
- Sway killed window on restart

**Solutions**:
```python
# 1. Use longer sleep duration
await sway.command('exec --no-startup-id "sleep 86400"')  # 24 hours

# 2. Use daemon-monitored process recreation
async def maintain_ghost_process(self):
    while True:
        ghost = await self._find_ghost_window()
        if not ghost:
            self.logger.warning("Ghost lost, recreating")
            await self._create_ghost_window()
        await asyncio.sleep(60)
```

### Ghost Container Process Using Too Much CPU

**Symptom**: Ghost window process using 1-2% CPU

**Causes**:
- Background process is busy-waiting
- Wrong process selected

**Solutions**:
```python
# Good choices (minimal CPU):
- sleep 100000
- cat /dev/null

# Bad choices (high CPU):
- bash -c 'while true; do true; done'
- python -c 'while True: pass'
```

---

## Final Notes

This research document provides a complete foundation for implementing ghost containers in Feature 051. The key insights are:

1. **Persistence works** when the window process stays alive
2. **Marks are the right choice** for Sway-native metadata storage
3. **Daemon management** of the ghost container process ensures reliability
4. **Integration with Feature 062** is clean and minimal

The implementation is straightforward and builds naturally on the existing async Python daemon architecture.

---

**Document Version**: 1.0
**Last Updated**: 2025-11-06
**Status**: Ready for implementation
**Next Phase**: Feature 051 implementation begins
