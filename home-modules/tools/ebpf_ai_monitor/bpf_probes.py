"""BCC-based eBPF program definitions and management.

This module provides the BPF C programs and the BPFProbeManager class
for loading and managing eBPF tracepoint attachments.

Architecture:
    - BPF programs run in kernel space, filtering events efficiently
    - Events are delivered to userspace via perf buffer
    - Process name filtering happens in kernel for minimal overhead

Tracepoints:
    - tracepoint:syscalls:sys_enter_read - Detect stdin read entry
    - tracepoint:syscalls:sys_exit_read - Detect stdin read completion
    - tracepoint:sched:sched_process_exit - Detect process termination
"""

import ctypes
import logging
from typing import Callable, Optional

from .models import EBPFEvent, SYSCALL_READ, SYSCALL_EXIT

logger = logging.getLogger(__name__)


# =============================================================================
# BPF C Program - Syscall Tracing
# =============================================================================

BPF_PROGRAM = r"""
#include <uapi/linux/ptrace.h>
#include <linux/sched.h>

// Syscall type identifiers
#define SYSCALL_READ       0
#define SYSCALL_POLL       1
#define SYSCALL_SELECT     2
#define SYSCALL_EXIT       3
#define SYSCALL_READ_EXIT  4  // sys_exit_read event

// Event structure passed to userspace
struct ebpf_event_t {
    u32 pid;
    u32 tgid;
    u32 fd;
    u8  syscall;
    u64 timestamp;
    char comm[16];
} __attribute__((packed));

// Key structure for process name lookup
struct proc_key_t {
    char name[16];
};

// Perf buffer for event delivery to userspace
BPF_PERF_OUTPUT(events);

// Hash map for O(1) process name lookup (populated from userspace)
// Key: process name struct, Value: 1 if target
BPF_HASH(target_procs, struct proc_key_t, u8, 16);

// Hash map for tracking PIDs currently in read syscall
// Key: PID, Value: entry timestamp (nanoseconds)
BPF_HASH(read_pids, u32, u64, 10240);

// Hash map for per-PID entry timestamps (for timeout detection)
// Key: PID, Value: timestamp when read started
BPF_HASH(pid_timestamps, u32, u64, 10240);

// Helper: Check if process name is a monitoring target
static inline int is_target_process(char *comm) {
    struct proc_key_t key = {};
    bpf_probe_read_kernel(&key.name, sizeof(key.name), comm);
    u8 *val = target_procs.lookup(&key);
    return val != NULL;
}

// Tracepoint: sys_enter_read
// Fires when a process enters the read() syscall
TRACEPOINT_PROBE(syscalls, sys_enter_read) {
    // Filter: stdin only (fd == 0)
    if (args->fd != 0)
        return 0;

    // Get process info
    u64 pid_tgid = bpf_get_current_pid_tgid();
    u32 pid = pid_tgid & 0xFFFFFFFF;
    u32 tgid = pid_tgid >> 32;

    // Get process name
    char comm[16];
    bpf_get_current_comm(&comm, sizeof(comm));

    // Filter: target processes only
    if (!is_target_process(comm))
        return 0;

    // Record timestamp for this PID (for timeout detection)
    u64 ts = bpf_ktime_get_ns();
    read_pids.update(&pid, &ts);

    // Build and submit event
    struct ebpf_event_t event = {};
    event.pid = pid;
    event.tgid = tgid;
    event.fd = args->fd;
    event.syscall = SYSCALL_READ;
    event.timestamp = ts;
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    events.perf_submit(args, &event, sizeof(event));
    return 0;
}

// Tracepoint: sys_exit_read
// Fires when a process exits the read() syscall
TRACEPOINT_PROBE(syscalls, sys_exit_read) {
    u64 pid_tgid = bpf_get_current_pid_tgid();
    u32 pid = pid_tgid & 0xFFFFFFFF;
    u32 tgid = pid_tgid >> 32;

    // Check if we were tracking this PID
    u64 *entry_ts = read_pids.lookup(&pid);
    if (entry_ts == NULL)
        return 0;

    // Remove from tracking
    read_pids.delete(&pid);
    pid_timestamps.delete(&pid);

    // Get process name for filtering
    char comm[16];
    bpf_get_current_comm(&comm, sizeof(comm));

    if (!is_target_process(comm))
        return 0;

    // Submit sys_exit_read event so userspace knows read completed
    struct ebpf_event_t event = {};
    event.pid = pid;
    event.tgid = tgid;
    event.fd = 0;
    event.syscall = SYSCALL_READ_EXIT;
    event.timestamp = bpf_ktime_get_ns();
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    events.perf_submit(args, &event, sizeof(event));
    return 0;
}

// Tracepoint: sched_process_exit
// Fires when a process terminates
TRACEPOINT_PROBE(sched, sched_process_exit) {
    u64 pid_tgid = bpf_get_current_pid_tgid();
    u32 pid = pid_tgid & 0xFFFFFFFF;
    u32 tgid = pid_tgid >> 32;

    // Get process name
    char comm[16];
    bpf_get_current_comm(&comm, sizeof(comm));

    // Filter: target processes only
    if (!is_target_process(comm))
        return 0;

    // Clean up any read tracking
    read_pids.delete(&pid);

    // Build and submit exit event
    struct ebpf_event_t event = {};
    event.pid = pid;
    event.tgid = tgid;
    event.fd = 0;
    event.syscall = SYSCALL_EXIT;
    event.timestamp = bpf_ktime_get_ns();
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    events.perf_submit(args, &event, sizeof(event));
    return 0;
}
"""


# =============================================================================
# BPF Probe Manager
# =============================================================================


class BPFProbeManager:
    """Manager for BCC eBPF program loading and event handling.

    This class handles:
    - Loading and compiling BPF programs
    - Attaching to tracepoints
    - Populating target process name map
    - Polling perf buffer for events
    - Graceful cleanup on shutdown

    Example:
        >>> manager = BPFProbeManager(target_processes={"claude", "codex"})
        >>> manager.load()
        >>> manager.poll(callback=handle_event)
        >>> manager.cleanup()
    """

    def __init__(
        self,
        target_processes: set[str],
        perf_buffer_pages: int = 64,
    ):
        """Initialize BPF probe manager.

        Args:
            target_processes: Set of process names to monitor.
            perf_buffer_pages: Number of pages for perf buffer (power of 2).
        """
        self.target_processes = target_processes
        self.perf_buffer_pages = perf_buffer_pages
        self._bpf: Optional[object] = None
        self._loaded = False

    def load(self) -> None:
        """Load and attach BPF programs.

        Raises:
            ImportError: If BCC is not available.
            Exception: If BPF program fails to load.
        """
        import os
        try:
            from bcc import BPF
        except ImportError as e:
            logger.error("BCC library not available: %s", e)
            raise ImportError(
                "BCC (BPF Compiler Collection) is required. "
                "Install via: programs.bcc.enable = true in NixOS"
            ) from e

        logger.info("Loading BPF programs...")

        # Build cflags from CPATH environment variable
        # NixOS sets CPATH with kernel header include directories
        cflags = []
        cpath = os.environ.get("CPATH", "")
        if cpath:
            for path in cpath.split(":"):
                if path:
                    cflags.append(f"-I{path}")
            logger.debug("Using include paths from CPATH: %s", cflags)

        # Also check BCC_KERNEL_SOURCE for kernel source directory
        kernel_source = os.environ.get("BCC_KERNEL_SOURCE", "")
        if kernel_source:
            cflags.extend([
                f"-I{kernel_source}/include",
                f"-I{kernel_source}/include/uapi",
                f"-I{kernel_source}/arch/x86/include",
                f"-I{kernel_source}/arch/x86/include/uapi",
            ])
            logger.debug("Added kernel source includes from BCC_KERNEL_SOURCE: %s", kernel_source)

        self._bpf = BPF(text=BPF_PROGRAM, cflags=cflags if cflags else None)

        # Populate target process name map
        # The key is a struct proc_key_t { char name[16]; }
        target_procs = self._bpf["target_procs"]
        for proc_name in self.target_processes:
            # Create the key struct - BCC expects a ctypes-compatible key
            # Key must be exactly 16 bytes (padded with nulls)
            key = target_procs.Key()
            key.name = proc_name.encode().ljust(16, b"\x00")
            target_procs[key] = target_procs.Leaf(1)
            logger.debug("Added target process: %s", proc_name)

        self._loaded = True
        logger.info(
            "BPF programs loaded. Monitoring: %s",
            ", ".join(self.target_processes),
        )

    def open_perf_buffer(
        self,
        callback: Callable[[int, bytes, int], None],
        lost_callback: Optional[Callable[[int], None]] = None,
    ) -> None:
        """Open perf buffer for event delivery.

        Args:
            callback: Function(cpu, data, size) called for each event.
            lost_callback: Function(lost_count) called when events are lost.
        """
        if not self._loaded or self._bpf is None:
            raise RuntimeError("BPF programs not loaded. Call load() first.")

        def _lost_cb(lost_count: int) -> None:
            logger.warning("Lost %d events from perf buffer", lost_count)
            if lost_callback:
                lost_callback(lost_count)

        self._bpf["events"].open_perf_buffer(
            callback,
            page_cnt=self.perf_buffer_pages,
            lost_cb=_lost_cb,
        )
        logger.debug("Perf buffer opened with %d pages", self.perf_buffer_pages)

    def poll(self, timeout_ms: int = 100) -> None:
        """Poll perf buffer for events.

        This is a blocking call that waits for events up to timeout_ms.
        Call this in a loop to continuously process events.

        Args:
            timeout_ms: Maximum time to wait for events in milliseconds.
        """
        if not self._loaded or self._bpf is None:
            raise RuntimeError("BPF programs not loaded. Call load() first.")

        self._bpf.perf_buffer_poll(timeout=timeout_ms)

    def parse_event(self, data: bytes) -> EBPFEvent:
        """Parse raw event data into EBPFEvent structure.

        Uses ctypes.cast to convert raw bytes to our EBPFEvent structure
        which includes the get_comm() helper method.

        Args:
            data: Raw bytes from perf buffer.

        Returns:
            Parsed EBPFEvent instance with get_comm() method.
        """
        if not self._loaded or self._bpf is None:
            raise RuntimeError("BPF programs not loaded. Call load() first.")

        # Cast raw bytes directly to our EBPFEvent ctypes structure
        # This gives us access to the get_comm() helper method
        return ctypes.cast(data, ctypes.POINTER(EBPFEvent)).contents

    def cleanup(self) -> None:
        """Clean up BPF resources.

        Call this on shutdown to properly release BPF programs.
        """
        if self._bpf is not None:
            logger.info("Cleaning up BPF resources...")
            # BCC handles cleanup automatically when object is garbage collected
            # but we can explicitly clear maps
            try:
                self._bpf["target_procs"].clear()
                self._bpf["read_pids"].clear()
            except Exception as e:
                logger.warning("Error during BPF cleanup: %s", e)
            self._bpf = None
            self._loaded = False
            logger.info("BPF cleanup complete")

    @property
    def is_loaded(self) -> bool:
        """Check if BPF programs are loaded."""
        return self._loaded
