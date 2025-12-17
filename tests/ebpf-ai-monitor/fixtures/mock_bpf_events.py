"""Mock eBPF events for testing without kernel access.

These fixtures simulate the events that would be received from
BPF perf buffer during real eBPF tracing.
"""

import ctypes
import time
from typing import Iterator


# Syscall type constants (matching bpf_probes.py)
SYSCALL_READ = 0
SYSCALL_POLL = 1
SYSCALL_SELECT = 2
SYSCALL_EXIT = 3


class MockEBPFEvent(ctypes.Structure):
    """Mock eBPF event structure matching the kernel-space definition."""

    _fields_ = [
        ("pid", ctypes.c_uint32),
        ("tgid", ctypes.c_uint32),
        ("fd", ctypes.c_uint32),
        ("syscall", ctypes.c_uint8),
        ("timestamp", ctypes.c_uint64),
        ("comm", ctypes.c_char * 16),
    ]


def make_read_event(
    pid: int,
    comm: str = "claude",
    fd: int = 0,
) -> MockEBPFEvent:
    """Create a mock stdin read event.

    Args:
        pid: Process ID.
        comm: Process name (max 16 chars).
        fd: File descriptor (0 for stdin).

    Returns:
        Mock eBPF event for sys_enter_read.
    """
    event = MockEBPFEvent()
    event.pid = pid
    event.tgid = pid
    event.fd = fd
    event.syscall = SYSCALL_READ
    event.timestamp = int(time.monotonic_ns())
    event.comm = comm.encode()[:16]
    return event


def make_exit_event(pid: int, comm: str = "claude") -> MockEBPFEvent:
    """Create a mock process exit event.

    Args:
        pid: Process ID.
        comm: Process name.

    Returns:
        Mock eBPF event for sched_process_exit.
    """
    event = MockEBPFEvent()
    event.pid = pid
    event.tgid = pid
    event.fd = 0
    event.syscall = SYSCALL_EXIT
    event.timestamp = int(time.monotonic_ns())
    event.comm = comm.encode()[:16]
    return event


def generate_session_events(
    pid: int,
    comm: str = "claude",
    work_duration_ns: int = 5_000_000_000,  # 5 seconds
) -> Iterator[MockEBPFEvent]:
    """Generate a sequence of events simulating an AI session.

    Simulates: process starts working -> completes -> waits for input.

    Args:
        pid: Process ID.
        comm: Process name.
        work_duration_ns: Simulated work duration in nanoseconds.

    Yields:
        Sequence of mock eBPF events.
    """
    base_ts = int(time.monotonic_ns())

    # Initial read event (process starts)
    event1 = MockEBPFEvent()
    event1.pid = pid
    event1.tgid = pid
    event1.fd = 0
    event1.syscall = SYSCALL_READ
    event1.timestamp = base_ts
    event1.comm = comm.encode()[:16]
    yield event1

    # Read event after work completes (waiting for input)
    event2 = MockEBPFEvent()
    event2.pid = pid
    event2.tgid = pid
    event2.fd = 0
    event2.syscall = SYSCALL_READ
    event2.timestamp = base_ts + work_duration_ns
    event2.comm = comm.encode()[:16]
    yield event2
