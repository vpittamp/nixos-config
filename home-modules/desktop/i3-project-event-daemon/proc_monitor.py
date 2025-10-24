"""Process monitoring module for i3pm event system.

This module provides functionality to monitor the /proc filesystem for new processes
and create EventEntry objects for interesting development-related processes.

Feature: 029-linux-system-log
User Story: US2 - Monitor Background Process Activity
"""

import asyncio
import logging
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional, Set

logger = logging.getLogger(__name__)


# Import EventEntry model
from .models import EventEntry


# Allowlist of interesting process names for development monitoring
# Feature 029: Task T028 - Process filtering allowlist
INTERESTING_PROCESSES = {
    # Language servers
    "rust-analyzer",
    "gopls",
    "pyright",
    "typescript-language-server",
    "clangd",

    # Build tools and compilers
    "cargo",
    "rustc",
    "go",
    "gcc",
    "clang",
    "make",
    "cmake",
    "ninja",

    # Runtimes
    "node",
    "python",
    "python3",
    "deno",
    "bun",

    # Container tools
    "docker",
    "podman",
    "kubectl",
    "helm",

    # Databases
    "postgres",
    "mysql",
    "redis-server",
    "mongodb",

    # Dev tools
    "git",
    "npm",
    "yarn",
    "pnpm",
}


class ProcessMonitor:
    """Monitor /proc filesystem for new process starts.

    Feature 029: Tasks T025-T032

    Scans /proc directory at regular intervals to detect new processes,
    filters for interesting development tools, and creates EventEntry objects.
    """

    def __init__(self, poll_interval: float = 0.5):
        """Initialize process monitor.

        Args:
            poll_interval: Polling interval in seconds (default 500ms)
        """
        self.poll_interval = poll_interval
        self.seen_pids: Set[int] = set()
        self.running = False
        self._monitor_task: Optional[asyncio.Task] = None
        self.event_callback: Optional[callable] = None

        logger.info(f"ProcessMonitor initialized (poll_interval={poll_interval}s)")

    async def start(self, event_callback: callable) -> None:
        """Start monitoring /proc for new processes.

        Feature 029: Task T025 - ProcessMonitor class with async start

        Args:
            event_callback: Async function to call with new EventEntry objects
        """
        if self.running:
            logger.warning("ProcessMonitor already running")
            return

        self.event_callback = event_callback
        self.running = True

        # Initialize seen_pids with current processes
        await self._scan_initial_pids()

        # Start monitoring loop
        self._monitor_task = asyncio.create_task(self._monitoring_loop())
        logger.info("ProcessMonitor started")

    async def stop(self) -> None:
        """Stop process monitoring."""
        if not self.running:
            return

        self.running = False

        if self._monitor_task:
            self._monitor_task.cancel()
            try:
                await self._monitor_task
            except asyncio.CancelledError:
                pass

        logger.info("ProcessMonitor stopped")

    async def _scan_initial_pids(self) -> None:
        """Scan /proc to initialize seen_pids set with existing processes."""
        try:
            proc_path = Path("/proc")
            for entry in proc_path.iterdir():
                if entry.name.isdigit():
                    try:
                        pid = int(entry.name)
                        self.seen_pids.add(pid)
                    except (ValueError, OSError):
                        continue

            logger.debug(f"Initial scan: {len(self.seen_pids)} existing processes")
        except Exception as e:
            logger.error(f"Error scanning initial PIDs: {e}")

    async def _monitoring_loop(self) -> None:
        """Main monitoring loop - scans /proc at regular intervals.

        Feature 029: Task T026 - PID detection and tracking
        """
        logger.info("Process monitoring loop started")

        while self.running:
            try:
                await self._scan_for_new_processes()
                await asyncio.sleep(self.poll_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}", exc_info=True)
                await asyncio.sleep(self.poll_interval)

    async def _scan_for_new_processes(self) -> None:
        """Scan /proc directory for new PIDs.

        Feature 029: Task T026 - PID detection
        """
        try:
            proc_path = Path("/proc")
            current_pids: Set[int] = set()

            # Scan /proc for numeric directories (PIDs)
            for entry in proc_path.iterdir():
                if not entry.name.isdigit():
                    continue

                try:
                    pid = int(entry.name)
                    current_pids.add(pid)

                    # Check if this is a new PID
                    if pid not in self.seen_pids:
                        await self._handle_new_process(pid, entry)
                        self.seen_pids.add(pid)

                except (ValueError, OSError):
                    # PID may have disappeared or other error
                    continue

            # Clean up PIDs that no longer exist (garbage collection)
            disappeared_pids = self.seen_pids - current_pids
            if disappeared_pids:
                self.seen_pids -= disappeared_pids
                logger.debug(f"Cleaned up {len(disappeared_pids)} disappeared PIDs")

        except Exception as e:
            logger.error(f"Error scanning for new processes: {e}")

    async def _handle_new_process(self, pid: int, proc_dir: Path) -> None:
        """Handle detection of a new process.

        Feature 029: Tasks T027-T031

        Args:
            pid: Process ID
            proc_dir: Path to /proc/{pid} directory
        """
        try:
            # Read process details
            process_info = await self._read_process_details(pid, proc_dir)

            if not process_info:
                return

            # Filter: only interesting processes
            # Feature 029: Task T028 - Process filtering
            process_name = process_info.get("process_name", "")
            # Skip processes with empty names (short-lived/zombie processes)
            if not process_name or not self._is_interesting_process(process_name):
                return

            # Create EventEntry
            event = self._create_process_event(process_info)

            # Send event to callback
            if self.event_callback:
                await self.event_callback(event)

        except Exception as e:
            # Feature 029: Task T032 - Error handling
            # Silently skip processes we can't read (permissions, race conditions)
            logger.debug(f"Could not process PID {pid}: {e}")

    async def _read_process_details(self, pid: int, proc_dir: Path) -> Optional[Dict[str, Any]]:
        """Read process details from /proc/{pid}/ files.

        Feature 029: Task T027 - Process detail reading

        Args:
            pid: Process ID
            proc_dir: Path to /proc/{pid} directory

        Returns:
            Dictionary with process details or None if read failed
        """
        try:
            # Read /proc/{pid}/comm (process name)
            comm_path = proc_dir / "comm"
            process_name = comm_path.read_text().strip() if comm_path.exists() else ""

            # Read /proc/{pid}/cmdline (full command line)
            cmdline_path = proc_dir / "cmdline"
            if cmdline_path.exists():
                cmdline_raw = cmdline_path.read_bytes()
                # Arguments are null-separated, convert to space-separated
                cmdline = cmdline_raw.decode('utf-8', errors='replace').replace('\x00', ' ').strip()
            else:
                cmdline = ""

            # Read /proc/{pid}/stat for parent PID and start time
            stat_path = proc_dir / "stat"
            parent_pid = None
            start_time = None

            if stat_path.exists():
                stat_content = stat_path.read_text()
                # Parse stat file: pid (comm) state ppid ...
                # Field 4 is PPID, field 22 is starttime
                parts = stat_content.split()
                if len(parts) >= 4:
                    try:
                        parent_pid = int(parts[3])
                    except (ValueError, IndexError):
                        pass

                # starttime is field 22 (0-indexed: parts[21])
                if len(parts) >= 22:
                    try:
                        # starttime is in clock ticks since boot
                        # We'll use current time as approximation
                        start_time = datetime.now()
                    except (ValueError, IndexError):
                        pass

            if not start_time:
                start_time = datetime.now()

            # Sanitize command line
            # Feature 029: Task T029 - Command line sanitization
            sanitized_cmdline = self._sanitize_cmdline(cmdline)

            # Truncate command line
            # Feature 029: Task T030 - Command line truncation
            if len(sanitized_cmdline) > 500:
                sanitized_cmdline = sanitized_cmdline[:497] + "..."

            return {
                "process_pid": pid,
                "process_name": process_name,
                "process_cmdline": sanitized_cmdline,
                "process_parent_pid": parent_pid,
                "process_start_time": start_time,
            }

        except (FileNotFoundError, PermissionError, OSError) as e:
            # Feature 029: Task T032 - Error handling for /proc access
            logger.debug(f"Cannot read process {pid}: {e}")
            return None

    def _is_interesting_process(self, process_name: str) -> bool:
        """Check if process name matches allowlist.

        Feature 029: Task T028 - Process filtering

        Args:
            process_name: Process name from /proc/{pid}/comm

        Returns:
            True if process is on allowlist
        """
        return process_name in INTERESTING_PROCESSES

    def _sanitize_cmdline(self, cmdline: str) -> str:
        """Sanitize command line to remove sensitive data.

        Feature 029: Task T029 - Command line sanitization

        Replaces common sensitive patterns:
        - password=*
        - token=*
        - key=*
        - secret=*
        - api_key=*
        - auth=*

        Args:
            cmdline: Raw command line string

        Returns:
            Sanitized command line with secrets replaced by "***"
        """
        # Patterns for sensitive data (case-insensitive)
        patterns = [
            r'(password|passwd|pwd)=[^\s]+',
            r'(token|bearer)=[^\s]+',
            r'(key|apikey|api_key)=[^\s]+',
            r'(secret|auth)=[^\s]+',
            r'(credentials|creds)=[^\s]+',
        ]

        sanitized = cmdline
        for pattern in patterns:
            # Replace the value part with ***
            sanitized = re.sub(pattern, r'\1=***', sanitized, flags=re.IGNORECASE)

        return sanitized

    def _create_process_event(self, process_info: Dict[str, Any]) -> EventEntry:
        """Create EventEntry from process information.

        Feature 029: Task T031 - EventEntry creation for process events

        Args:
            process_info: Dictionary with process details

        Returns:
            EventEntry with source="proc" and process fields populated
        """
        return EventEntry(
            event_id=0,  # Will be assigned by event buffer
            timestamp=process_info["process_start_time"],
            event_type="process::start",
            source="proc",
            processing_duration_ms=0.0,

            # Process-specific fields
            process_pid=process_info["process_pid"],
            process_name=process_info["process_name"],
            process_cmdline=process_info["process_cmdline"],
            process_parent_pid=process_info["process_parent_pid"],
            process_start_time=process_info["process_start_time"],
        )
