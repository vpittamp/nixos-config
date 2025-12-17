# Contract: eBPF Event Structure

**Feature**: 119-explore-ebpf-monitor
**Date**: 2025-12-16

## Overview

This contract defines the data structure passed from kernel eBPF probes to the userspace daemon via BPF perf buffer.

## BPF C Structure

```c
// Syscall type identifiers
#define SYSCALL_READ   0
#define SYSCALL_POLL   1
#define SYSCALL_SELECT 2
#define SYSCALL_EXIT   3

struct ebpf_event_t {
    u32 pid;           // Process ID
    u32 tgid;          // Thread group ID
    u32 fd;            // File descriptor (0 = stdin)
    u8  syscall;       // Syscall type (see defines above)
    u64 timestamp;     // bpf_ktime_get_ns() value
    char comm[16];     // Process name (null-terminated)
} __attribute__((packed));
```

## Python ctypes Mapping

```python
import ctypes

class EBPFEvent(ctypes.Structure):
    _fields_ = [
        ("pid", ctypes.c_uint32),
        ("tgid", ctypes.c_uint32),
        ("fd", ctypes.c_uint32),
        ("syscall", ctypes.c_uint8),
        ("timestamp", ctypes.c_uint64),
        ("comm", ctypes.c_char * 16),
    ]

# Syscall type constants
SYSCALL_READ = 0
SYSCALL_POLL = 1
SYSCALL_SELECT = 2
SYSCALL_EXIT = 3
```

## Field Specifications

| Field | Size | Description | Source |
|-------|------|-------------|--------|
| `pid` | 4 bytes | Process ID | `bpf_get_current_pid_tgid() & 0xFFFFFFFF` |
| `tgid` | 4 bytes | Thread group ID | `bpf_get_current_pid_tgid() >> 32` |
| `fd` | 4 bytes | File descriptor | `args->fd` from tracepoint |
| `syscall` | 1 byte | Syscall identifier | Set by probe attachment point |
| `timestamp` | 8 bytes | Nanoseconds since boot | `bpf_ktime_get_ns()` |
| `comm` | 16 bytes | Process name | `bpf_get_current_comm()` |

## Tracepoint Attachments

| Syscall Type | Tracepoint | Purpose |
|--------------|------------|---------|
| READ (0) | `tracepoint:syscalls:sys_enter_read` | Detect stdin read entry |
| READ (0) | `tracepoint:syscalls:sys_exit_read` | Detect stdin read completion |
| POLL (1) | `tracepoint:syscalls:sys_enter_poll` | Alternative input wait detection |
| SELECT (2) | `tracepoint:syscalls:sys_enter_select` | Alternative input wait detection |
| EXIT (3) | `tracepoint:sched:sched_process_exit` | Detect process termination |

## Filtering (Kernel Space)

Events are filtered in kernel space before submission to perf buffer:

1. **File descriptor filter**: `args->fd == 0` (stdin only)
2. **Process name filter**: `comm` matches target list ("claude", "codex")

```c
TRACEPOINT_PROBE(syscalls, sys_enter_read) {
    // Filter: stdin only
    if (args->fd != 0)
        return 0;

    // Get process name
    char comm[16];
    bpf_get_current_comm(&comm, sizeof(comm));

    // Filter: target processes only
    // (Implementation uses BPF hash map for O(1) lookup)
    if (!is_target_process(comm))
        return 0;

    // Build and submit event
    struct ebpf_event_t event = {};
    event.pid = bpf_get_current_pid_tgid() & 0xFFFFFFFF;
    event.tgid = bpf_get_current_pid_tgid() >> 32;
    event.fd = args->fd;
    event.syscall = SYSCALL_READ;
    event.timestamp = bpf_ktime_get_ns();
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    events.perf_submit(args, &event, sizeof(event));
    return 0;
}
```

## Event Delivery

- **Mechanism**: BPF_PERF_OUTPUT (perf buffer)
- **Per-CPU buffers**: Yes (standard perf buffer behavior)
- **Lost events**: Logged but not fatal (daemon handles gracefully)
- **Polling**: `b.perf_buffer_poll()` with configurable timeout

## Backward Compatibility

This is a new internal contract. No backward compatibility requirements.

## Versioning

If structure changes are needed in future:
1. Add version field as first u8
2. Handle both versions in userspace during transition
3. Remove old version support after migration complete
