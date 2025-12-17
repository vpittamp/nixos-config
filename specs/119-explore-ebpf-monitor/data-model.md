# Data Model: eBPF-Based AI Agent Process Monitor

**Feature**: 119-explore-ebpf-monitor
**Date**: 2025-12-16

## Entity Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   eBPFEvent     │────▶│ MonitoredProcess│────▶│   BadgeState    │
│  (kernel space) │     │  (daemon state) │     │  (file system)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                      │                       │
         │                      │                       │
         ▼                      ▼                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ ProcessStateChange │  │  Notification   │     │   EWW Panel     │
│    (internal)      │  │   (SwayNC)      │     │   (consumer)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Entities

### 1. eBPFEvent

Raw event from kernel eBPF probes. Minimal structure for efficient kernel→userspace transfer.

**Source**: BPF perf buffer output

| Field | Type | Description |
|-------|------|-------------|
| `pid` | u32 | Process ID that triggered the event |
| `tgid` | u32 | Thread group ID (usually same as PID for main thread) |
| `fd` | u32 | File descriptor (0 = stdin) |
| `syscall` | u8 | Syscall type: 0=read, 1=poll, 2=select, 3=exit |
| `timestamp` | u64 | Kernel timestamp (nanoseconds since boot) |
| `comm` | char[16] | Process name (truncated to 16 chars) |

**BPF Structure**:
```c
struct ebpf_event_t {
    u32 pid;
    u32 tgid;
    u32 fd;
    u8 syscall;
    u64 timestamp;
    char comm[16];
};
```

**Python ctypes mapping**:
```python
class EBPFEvent(ctypes.Structure):
    _fields_ = [
        ("pid", ctypes.c_uint32),
        ("tgid", ctypes.c_uint32),
        ("fd", ctypes.c_uint32),
        ("syscall", ctypes.c_uint8),
        ("timestamp", ctypes.c_uint64),
        ("comm", ctypes.c_char * 16),
    ]
```

### 2. MonitoredProcess

Daemon-side state for a tracked AI process. Maintained in memory, reconstructed on service restart.

**Source**: Created when target process detected, updated on state changes

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `pid` | int | Process ID | > 0 |
| `comm` | str | Process name ("claude" or "codex") | Non-empty, max 16 chars |
| `window_id` | int | Sway container ID | > 0, resolved via IPC |
| `project_name` | str | Project from I3PM_PROJECT_NAME | May be empty |
| `state` | ProcessState | Current state | Enum value |
| `last_state_change` | float | Unix timestamp of last transition | > 0 |
| `read_entry_time` | float | Timestamp when entered read syscall | 0 if not in read |
| `parent_chain` | list[int] | PIDs: [self, parent, grandparent, ...] | Non-empty |

**State Machine**:
```
                    ┌─────────────────┐
                    │    UNKNOWN      │
                    │ (initial state) │
                    └────────┬────────┘
                             │ process_detected
                             ▼
       ┌────────────────────────────────────────┐
       │                WORKING                  │
       │  (process running, not waiting input)  │
       └─────────────┬──────────────────────────┘
                     │
    sys_enter_read   │    sys_exit_read or
    (fd=0) +         │    other activity
    timeout          │
                     ▼
       ┌────────────────────────────────────────┐
       │                WAITING                  │
       │  (blocked on stdin read > threshold)   │◀─────┐
       └─────────────┬──────────────────────────┘      │
                     │                                  │
    process_exit     │    sys_exit_read                 │
                     │    (brief, restarts read)        │
                     ▼                                  │
       ┌────────────────────────────────────────┐      │
       │                EXITED                   │      │
       │  (process terminated)                   │      │
       └────────────────────────────────────────┘      │
                                                        │
       User interacts → sys_exit_read ──────────────────┘
```

**Pydantic Model**:
```python
from enum import Enum
from pydantic import BaseModel, Field
from typing import Optional

class ProcessState(str, Enum):
    UNKNOWN = "unknown"
    WORKING = "working"
    WAITING = "waiting"
    EXITED = "exited"

class MonitoredProcess(BaseModel):
    pid: int = Field(..., gt=0)
    comm: str = Field(..., max_length=16)
    window_id: int = Field(..., gt=0)
    project_name: str = ""
    state: ProcessState = ProcessState.UNKNOWN
    last_state_change: float = Field(..., gt=0)
    read_entry_time: float = 0.0
    parent_chain: list[int] = Field(..., min_length=1)

    def transition_to(self, new_state: ProcessState) -> None:
        """Transition to new state with timestamp update."""
        if self.state != new_state:
            self.state = new_state
            self.last_state_change = time.time()

    def is_waiting_timeout(self, threshold_ms: int) -> bool:
        """Check if process has been in read syscall longer than threshold."""
        if self.read_entry_time == 0:
            return False
        elapsed_ms = (time.time() - self.read_entry_time) * 1000
        return elapsed_ms >= threshold_ms
```

### 3. BadgeState (Existing Entity)

Badge file written to filesystem. **Must match existing format** for compatibility with eww panel.

**Source**: Written by daemon, consumed by eww monitoring panel

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `window_id` | int | Sway container ID | > 0 |
| `state` | str | "working" or "stopped" | Enum value |
| `source` | str | Agent type identifier | "claude-code" or "codex" |
| `project` | str | Project name | May be empty |
| `count` | int | Notification count | 1-9999 |
| `timestamp` | float | Unix timestamp | > 0 |
| `needs_attention` | bool | Show attention indicator | - |
| `session_started` | float | When session began | > 0 |

**File Location**: `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`

**JSON Schema** (contracts/badge-state.json):
```json
{
  "window_id": 12345,
  "state": "working",
  "source": "claude-code",
  "project": "nixos-config",
  "count": 1,
  "timestamp": 1734355200.5,
  "needs_attention": false,
  "session_started": 1734355100.0
}
```

**State Mapping**:
| MonitoredProcess.state | BadgeState.state | BadgeState.needs_attention |
|------------------------|------------------|----------------------------|
| WORKING | "working" | false |
| WAITING | "stopped" | true |
| EXITED | (delete badge file) | - |

### 4. ProcessStateChange

Internal event representing a state transition. Used for notification triggering and logging.

| Field | Type | Description |
|-------|------|-------------|
| `pid` | int | Process ID |
| `old_state` | ProcessState | Previous state |
| `new_state` | ProcessState | Current state |
| `window_id` | int | Sway container ID |
| `project_name` | str | Project name |
| `timestamp` | float | When transition occurred |
| `comm` | str | Process name |

**Notification Rules**:
- WORKING → WAITING: Trigger notification "Agent ready for input"
- WAITING → WORKING: Clear needs_attention flag (user resumed)
- * → EXITED: Log process exit, delete badge file

### 5. DaemonState

Top-level daemon state container. Reconstructed on service startup.

| Field | Type | Description |
|-------|------|-------------|
| `tracked_processes` | dict[int, MonitoredProcess] | PID → process mapping |
| `target_user_uid` | int | UID for badge file ownership |
| `target_user_name` | str | Username for notifications |
| `badge_directory` | Path | Badge file directory |
| `wait_threshold_ms` | int | Threshold for WAITING state |
| `target_process_names` | set[str] | Process names to monitor |

**Pydantic Model**:
```python
class DaemonState(BaseModel):
    tracked_processes: dict[int, MonitoredProcess] = {}
    target_user_uid: int
    target_user_name: str
    badge_directory: Path
    wait_threshold_ms: int = 1000
    target_process_names: set[str] = {"claude", "codex"}

    def get_process(self, pid: int) -> Optional[MonitoredProcess]:
        return self.tracked_processes.get(pid)

    def add_process(self, process: MonitoredProcess) -> None:
        self.tracked_processes[process.pid] = process

    def remove_process(self, pid: int) -> Optional[MonitoredProcess]:
        return self.tracked_processes.pop(pid, None)

    def rebuild_from_system(self) -> None:
        """Scan system for existing AI processes on startup."""
        # Implementation scans /proc for target process names
        pass
```

## Relationships

```
eBPFEvent --[triggers]--> ProcessStateChange
    |
    v
MonitoredProcess --[writes]--> BadgeState (file)
    |                               |
    |                               v
    |                          EWW Panel (inotify consumer)
    |
    +--[triggers]--> SwayNC Notification (on WORKING→WAITING)
```

## Data Flow

1. **eBPF Probe fires** → eBPFEvent arrives via perf buffer
2. **Daemon processes event**:
   - Look up or create MonitoredProcess by PID
   - Update read_entry_time or state based on syscall type
3. **State transition detected** → Create ProcessStateChange
4. **Badge file update**:
   - WORKING/WAITING: Write/update badge JSON
   - EXITED: Delete badge file
5. **Notification trigger** (WORKING→WAITING only):
   - Send D-Bus notification to user session
   - Set needs_attention = true in badge

## File Persistence

### Badge Files (Existing Format)
- **Location**: `$XDG_RUNTIME_DIR/i3pm-badges/<window_id>.json`
- **Ownership**: Target user (chown after write)
- **Lifetime**: Deleted on process exit or window close
- **Consumers**: eww monitoring panel, notification callbacks

### No Additional Persistence
- Daemon state is in-memory only
- On restart: Rebuild state by scanning /proc for target processes
- Badge files serve as crash recovery hint (existing badges = existing sessions)

## Validation Rules

### eBPFEvent
- `pid` > 0
- `fd` == 0 (filter in kernel space)
- `comm` matches target process names (filter in kernel space)

### MonitoredProcess
- `window_id` must be valid Sway container (verify via IPC)
- `parent_chain` must include process, parent, up to Ghostty

### BadgeState
- `state` must be "working" or "stopped"
- `source` must be "claude-code" or "codex"
- `window_id` must match filename
