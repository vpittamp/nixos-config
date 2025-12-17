# Research: eBPF-Based AI Agent Process Monitor

**Feature**: 119-explore-ebpf-monitor
**Date**: 2025-12-16

## Decision Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| eBPF Framework | BCC (Python) | Easier development, mature Python bindings, sufficient for daemon use case |
| Alternative Tool | bpftrace scripts | For quick prototyping and validation |
| Privilege Model | **Revised**: Run as root via sudo | setcap on BCC/bpftrace is security risk (can read kernel memory) |
| Service Architecture | System-level systemd service | Required for root privileges; user service via polkit |
| Event Delivery | Perf Buffer | Kernel 5.8+ supports ring buffer, but perf buffer is simpler and sufficient |
| Process Detection | sys_enter_read tracepoint + fd==0 filter | Direct stdin monitoring |

## Research Findings

### 1. BCC vs bpftrace for Implementation

**Decision**: Use BCC (Python) for the daemon, bpftrace for prototyping

**Rationale**:
- BCC provides mature Python bindings ideal for daemon development with state management
- Best practice guidance: "BCC for complex tools and daemons, bpftrace for one-liners and short scripts"
- BCC allows embedding eBPF C code in Python with perf buffer event delivery
- The daemon needs to maintain state (tracked processes, window mappings), which Python handles well

**Alternatives Considered**:
- **Pure bpftrace**: Rejected - lacks state management, harder to integrate with Python ecosystem
- **libbpf-rs (Rust)**: Rejected - introduces new language to codebase, overkill for this use case
- **libbpf-bootstrap (C)**: Rejected - more complex, Python integration unclear

**Sources**:
- [Brendan Gregg's eBPF Tools](https://www.brendangregg.com/ebpf.html)
- [BCC Python Developer Tutorial](https://github.com/iovisor/bcc/blob/master/docs/tutorial_bcc_python_developer.md)

### 2. Privilege Model (CRITICAL REVISION)

**Decision**: Run the eBPF monitor as root via systemd system service, NOT using setcap

**Rationale**:
The original spec assumed setcap could grant CAP_BPF and CAP_PERFMON to bpftrace. Research reveals this is a security anti-pattern:

> "bpftool, bpftrace, bcc tools binaries should NOT be installed with CAP_BPF and CAP_PERFMON, since unpriv users will be able to read kernel secrets."
> — [Linux Kernel CAP_BPF Patch](https://lore.kernel.org/bpf/20200513230355.7858-2-alexei.starovoitov@gmail.com/)

> "CAP_PERFMON relaxes the verifier checks further - BPF progs can use pointer-to-integer conversions, speculation attack hardening measures are bypassed, bpf_probe_read to read arbitrary kernel memory is allowed"
> — [Introduction to CAP_BPF](https://mdaverde.com/posts/cap-bpf/)

**Revised Architecture**:
1. **System Service**: `ebpf-ai-monitor.service` runs as root
2. **Badge Files**: Written to user's `$XDG_RUNTIME_DIR` with correct ownership
3. **Notifications**: Triggered via `sudo -u $USER notify-send` or D-Bus to user session
4. **NixOS Module**: Uses `systemd.services` (system-level), not home-manager service

**Alternatives Considered**:
- **setcap on binaries**: Rejected - security risk, kernel memory readable
- **sudo wrapper**: Rejected - adds complexity, same privilege level as root service
- **User namespace BPF**: Not mature enough for production use

**Impact on Spec**:
- FR-010 needs revision: Service runs at system level, not user level
- Assumptions section update: No longer using setcap approach

### 3. NixOS Package Availability

**Decision**: Use nixpkgs `bcc` package with `programs.bcc.enable = true`

**Available Packages**:
| Package | Version | Purpose |
|---------|---------|---------|
| `bcc` | Active | BPF Compiler Collection with Python bindings |
| `bpftrace` | 0.23.5+ | High-level tracing scripts |
| `libbpf` | Active | Low-level BPF loading library |

**NixOS Configuration**:
```nix
{
  programs.bcc.enable = true;
  environment.systemPackages = with pkgs; [
    bpftrace
    bcc
  ];
}
```

**Sources**:
- [NixOS BCC Module](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/programs/bcc.nix)
- [nixpkgs bpftrace](https://mynixos.com/nixpkgs/package/bpftrace)

### 4. eBPF Syscall Tracing Pattern

**Decision**: Use `tracepoint:syscalls:sys_enter_read` with fd==0 filter

**BCC Program Structure**:
```c
TRACEPOINT_PROBE(syscalls, sys_enter_read) {
    // Filter for stdin only (fd == 0)
    if (args->fd != 0)
        return 0;

    u64 pid_tgid = bpf_get_current_pid_tgid();
    u32 pid = pid_tgid & 0xFFFFFFFF;

    // Get process name
    char comm[16];
    bpf_get_current_comm(&comm, sizeof(comm));

    // Filter for target processes (claude, codex)
    // ... process name matching logic

    // Send event to userspace
    struct event_t event = {};
    event.pid = pid;
    event.fd = args->fd;
    event.timestamp = bpf_ktime_get_ns();
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    events.perf_submit(args, &event, sizeof(event));
    return 0;
}
```

**Key eBPF Helpers**:
- `bpf_get_current_pid_tgid()` - Get PID (lower 32 bits) and TGID (upper 32 bits)
- `bpf_get_current_comm()` - Get process name (max 16 chars)
- `bpf_ktime_get_ns()` - Kernel timestamp
- `bpf_probe_read_user()` - Read user memory (if needed)

**Process Name Filtering**:
- Filter in kernel space for efficiency: only emit events for "claude" or "codex" processes
- Use BPF hash map to store target process names for O(1) lookup

**Sources**:
- [BCC Reference Guide](https://github.com/iovisor/bcc/blob/master/docs/reference_guide.md)
- [eBPF Tutorial - Tracing Syscalls](https://eunomia.dev/en/tutorials/4-opensnoop/)

### 5. Detecting "Waiting for Input" State

**Decision**: Monitor sys_enter_read with timing heuristics

**Detection Logic**:
1. Track when process enters `read(0, ...)` syscall (stdin read)
2. If read doesn't return within threshold (1 second), process is "waiting"
3. On syscall exit or process activity, transition back to "working"

**Implementation Approach**:
```python
# Userspace state machine
class ProcessState:
    UNKNOWN = "unknown"
    WORKING = "working"
    WAITING = "waiting"
    EXITED = "exited"

# State transitions:
# 1. Process spawns → WORKING (detected via process name scan)
# 2. sys_enter_read(fd=0) + timeout → WAITING
# 3. sys_exit_read or other syscalls → WORKING
# 4. Process exits → EXITED
```

**Timing Heuristic**:
- Track entry timestamp per PID in BPF hash map
- Userspace daemon polls for stale entries (>1s in read)
- Alternatively: Use bpf_timer (kernel 5.15+) for in-kernel timeout detection

### 6. Window ID Resolution

**Decision**: Use process tree traversal (PID → PPID chain → Ghostty → Sway)

**Resolution Steps**:
1. From monitored PID, walk parent chain: `claude → bash → tmux(server)`
2. Find tmux client PID associated with the session
3. Walk from tmux client to Ghostty terminal process
4. Query Sway IPC (`swaymsg -t get_tree`) for container with matching PID
5. Extract `id` field (Sway window ID)

**Existing Pattern** (from tmux-ai-monitor):
```bash
# Get window ID from process - walk the process tree
get_window_id_from_pane() {
    local pane_pid="$1"
    # Walk up process tree to find Ghostty
    local current_pid="$pane_pid"
    while [ "$current_pid" != "1" ]; do
        local proc_comm=$(cat "/proc/$current_pid/comm" 2>/dev/null)
        if [[ "$proc_comm" == "ghostty" ]]; then
            # Found Ghostty - query Sway for window ID
            swaymsg -t get_tree | jq -r ".. | select(.pid? == $current_pid) | .id"
            return
        fi
        current_pid=$(awk '{print $4}' "/proc/$current_pid/stat" 2>/dev/null)
    done
}
```

**Project Name Resolution**:
- Read `/proc/<pid>/environ` for `I3PM_PROJECT_NAME` variable
- This is injected by the app launcher wrapper

### 7. Event Delivery: Perf Buffer vs Ring Buffer

**Decision**: Use Perf Buffer (BPF_PERF_OUTPUT)

**Rationale**:
- Perf buffer is simpler and well-supported in BCC Python
- Ring buffer (kernel 5.8+) offers better efficiency but adds complexity
- Event rate is low (<100 events/sec) - perf buffer overhead is negligible

**BCC Perf Buffer Pattern**:
```python
# Define output buffer
bpf_text = """
BPF_PERF_OUTPUT(events);

TRACEPOINT_PROBE(...) {
    struct event_t e = {};
    // ... populate event
    events.perf_submit(args, &e, sizeof(e));
    return 0;
}
"""

# Python callback
def handle_event(cpu, data, size):
    event = b["events"].event(data)
    # Process event...

b = BPF(text=bpf_text)
b["events"].open_perf_buffer(handle_event)

while True:
    b.perf_buffer_poll()
```

### 8. Service Architecture

**Decision**: System-level systemd service with user notification bridge

**Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│                    System Level (root)                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  ebpf-ai-monitor.service                              │  │
│  │  - Loads eBPF programs                                │  │
│  │  - Monitors syscalls                                  │  │
│  │  - Writes badge files (chown to user)                 │  │
│  │  - Triggers notifications via D-Bus                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
          │
          │ Badge files written to:
          │ /run/user/<uid>/i3pm-badges/<window_id>.json
          │ (owned by user)
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│                    User Session                              │
│  ┌────────────────┐    ┌─────────────────────────────────┐  │
│  │  eww panel     │◄───│  inotify on badge directory     │  │
│  │  (existing)    │    │  (existing monitoring_data.py)  │  │
│  └────────────────┘    └─────────────────────────────────┘  │
│                                                              │
│  ┌────────────────┐    ┌─────────────────────────────────┐  │
│  │  SwayNC        │◄───│  notify-send (via D-Bus)        │  │
│  │  (existing)    │    │                                 │  │
│  └────────────────┘    └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**NixOS Module Structure**:
```nix
# modules/services/ebpf-ai-monitor.nix
{
  options.services.ebpf-ai-monitor = {
    enable = mkEnableOption "eBPF-based AI agent monitor";
    user = mkOption { type = types.str; description = "User to monitor"; };
    processes = mkOption {
      type = types.listOf types.str;
      default = ["claude" "codex"];
      description = "Process names to monitor";
    };
    waitThreshold = mkOption {
      type = types.int;
      default = 1000;
      description = "Milliseconds before considering process as waiting";
    };
  };

  config = mkIf cfg.enable {
    programs.bcc.enable = true;

    systemd.services.ebpf-ai-monitor = {
      description = "eBPF AI Agent Monitor";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python -m ebpf_ai_monitor --user ${cfg.user}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
```

## Unresolved Questions

| Question | Status | Action |
|----------|--------|--------|
| How to handle multiple users? | Deferred | Single-user for now; multi-user in future |
| Process crash detection | Resolved | Use sched:sched_process_exit tracepoint |
| Performance impact measurement | Deferred | Benchmark after implementation |

## References

### Official Documentation
- [BCC GitHub Repository](https://github.com/iovisor/bcc)
- [BCC Python Developer Tutorial](https://github.com/iovisor/bcc/blob/master/docs/tutorial_bcc_python_developer.md)
- [BCC Reference Guide](https://github.com/iovisor/bcc/blob/master/docs/reference_guide.md)
- [Linux Kernel eBPF Documentation](https://docs.kernel.org/bpf/)
- [Brendan Gregg's eBPF Tracing Tools](https://www.brendangregg.com/ebpf.html)

### Security References
- [Introduction to CAP_BPF](https://mdaverde.com/posts/cap-bpf/)
- [Linux Kernel CAP_BPF Patch](https://lore.kernel.org/bpf/20200513230355.7858-2-alexei.starovoitov@gmail.com/)
- [Using bpftrace with Limited Capabilities](https://medium.com/@techdevguides/using-bpftrace-with-limited-capabilities-inside-docker-a-capability-focused-guide-851695a13197)

### NixOS References
- [NixOS BCC Module](https://github.com/NixOS/nixpkgs/blob/release-25.11/nixos/modules/programs/bcc.nix)
- [nixpkgs bpftrace Package](https://mynixos.com/nixpkgs/package/bpftrace)

### Tutorials
- [Writing a System Call Tracer Using eBPF](https://sh4dy.com/2024/08/03/beetracer/)
- [eBPF Tutorial: Capturing Opening Files](https://eunomia.dev/en/tutorials/4-opensnoop/)
- [The Art of Writing eBPF Programs](https://www.sysdig.com/blog/the-art-of-writing-ebpf-programs-a-primer)
