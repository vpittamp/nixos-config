"""Main daemon loop with eBPF integration.

This module provides the EBPFDaemon class that:
- Loads and manages BPF programs
- Polls perf buffer for events
- Tracks process state transitions
- Triggers notifications and badge updates
- Integrates with OTEL monitor for enrichment
- Handles graceful shutdown
"""

import logging
import os
import pwd
import signal
import sys
import time
from pathlib import Path
from typing import Optional

from .badge_writer import BadgeWriter
from .bpf_probes import BPFProbeManager
from .models import (
    DaemonState,
    EBPFEvent,
    MonitoredProcess,
    OTELSessionData,
    ProcessState,
    SYSCALL_READ,
    SYSCALL_READ_EXIT,
    SYSCALL_EXIT,
)
from .notifier import Notifier
from .otel_subscriber import OTELSubscriber
from .process_tracker import ProcessTracker

logger = logging.getLogger(__name__)


class EBPFDaemon:
    """Main daemon for eBPF-based AI agent monitoring.

    This daemon:
    1. Loads BPF programs to trace syscalls
    2. Scans for existing AI processes on startup
    3. Polls perf buffer for new events
    4. Tracks process state (WORKING/WAITING/EXITED)
    5. Sends notifications on state transitions
    6. Writes badge files for eww panel

    Example:
        >>> daemon = EBPFDaemon(
        ...     user="vpittamp",
        ...     threshold_ms=1000,
        ...     target_processes={"claude", "codex"},
        ... )
        >>> daemon.run()
    """

    def __init__(
        self,
        user: str,
        threshold_ms: int = 1000,
        target_processes: Optional[set[str]] = None,
        poll_interval_ms: int = 100,
    ):
        """Initialize daemon.

        Args:
            user: Username to monitor and send notifications to.
            threshold_ms: Milliseconds before considering process as waiting.
            target_processes: Process names to monitor (default: claude, codex).
            poll_interval_ms: Perf buffer poll interval in milliseconds.
        """
        self.user = user
        self.threshold_ms = threshold_ms
        self.target_processes = target_processes or {"claude", "codex"}
        self.poll_interval_ms = poll_interval_ms

        # Resolve user info
        try:
            user_info = pwd.getpwnam(user)
            self._uid = user_info.pw_uid
            self._gid = user_info.pw_gid
        except KeyError:
            raise ValueError(f"User not found: {user}")

        # Badge directory (XDG_RUNTIME_DIR for user)
        self._badge_dir = Path(f"/run/user/{self._uid}/i3pm-badges")

        # Initialize components
        self._state = DaemonState(
            target_user_uid=self._uid,
            target_user_name=user,
            badge_directory=self._badge_dir,
            wait_threshold_ms=threshold_ms,
            target_process_names=self.target_processes,
        )

        self._bpf_manager: Optional[BPFProbeManager] = None
        self._notifier = Notifier(user=user)
        self._process_tracker = ProcessTracker(target_processes=self.target_processes)
        self._badge_writer = BadgeWriter(
            badge_dir=self._badge_dir,
            uid=self._uid,
            gid=self._gid,
        )

        # Feature 119/123: OTEL enrichment integration
        # Store OTEL session data keyed by window_id for badge enrichment
        self._otel_sessions: dict[int, OTELSessionData] = {}
        self._otel_subscriber: Optional[OTELSubscriber] = None

        # Shutdown flag
        self._running = False

    def run(self) -> int:
        """Main daemon loop.

        Returns:
            Exit code (0 for clean shutdown, non-zero for errors).
        """
        logger.info("Starting eBPF AI Monitor daemon")
        logger.info("Monitoring user: %s (UID=%d)", self.user, self._uid)
        logger.info("Target processes: %s", ", ".join(self.target_processes))
        logger.info("Wait threshold: %dms", self.threshold_ms)

        # Setup signal handlers
        self._setup_signal_handlers()

        try:
            # Initialize BPF
            self._bpf_manager = BPFProbeManager(
                target_processes=self.target_processes,
            )
            self._bpf_manager.load()
            self._bpf_manager.open_perf_buffer(
                callback=self._handle_event,
                lost_callback=self._handle_lost_events,
            )

            # Recover state from existing badge files
            self._recover_state_from_badges()

            # Scan for existing processes
            self._scan_existing_processes()

            # Feature 119/123: Start OTEL subscriber for enrichment
            self._start_otel_subscriber()

            # Main loop
            self._running = True
            logger.info("Daemon started, entering main loop")

            while self._running:
                # Poll for BPF events
                self._bpf_manager.poll(timeout_ms=self.poll_interval_ms)

                # Check for waiting timeouts
                self._check_waiting_timeouts()

            logger.info("Daemon shutting down cleanly")
            return 0

        except ImportError as e:
            logger.error("BCC not available: %s", e)
            return 1
        except PermissionError as e:
            logger.error("Permission denied (need root): %s", e)
            return 1
        except Exception as e:
            logger.exception("Daemon error: %s", e)
            return 1
        finally:
            self._cleanup()

    def _setup_signal_handlers(self) -> None:
        """Setup handlers for SIGTERM and SIGINT."""

        def signal_handler(signum: int, frame) -> None:
            sig_name = signal.Signals(signum).name
            logger.info("Received %s, initiating shutdown", sig_name)
            self._running = False

        signal.signal(signal.SIGTERM, signal_handler)
        signal.signal(signal.SIGINT, signal_handler)

    def _scan_existing_processes(self) -> None:
        """Scan for existing AI processes on startup."""
        logger.info("Scanning for existing AI processes...")
        existing = self._process_tracker.scan_existing()

        for process in existing:
            self._state.add_process(process)
            logger.info(
                "Found existing process: %s (PID=%d, window=%d, project=%s)",
                process.comm,
                process.pid,
                process.window_id,
                process.project_name or "(none)",
            )

            # Write badge for existing process (with OTEL enrichment if available)
            otel_data = self._otel_sessions.get(process.window_id)
            self._badge_writer.write_badge(process, otel_data=otel_data)

        logger.info("Found %d existing AI processes", len(existing))

    def _recover_state_from_badges(self) -> None:
        """Recover state by scanning existing badge files.

        Called on startup to understand state from previous run.
        This helps maintain continuity after daemon restart.
        """
        logger.info("Scanning for existing badge files...")
        existing_badges = self._badge_writer.scan_existing_badges()

        if not existing_badges:
            logger.info("No existing badge files found")
            return

        # For each badge, try to find corresponding process
        for window_id, badge in existing_badges.items():
            logger.debug(
                "Found badge: window=%d, state=%s, source=%s",
                window_id,
                badge.state,
                badge.source,
            )

            # Badge files without matching process should be cleaned up
            # by the process scan (if process exists, badge is recreated;
            # if process doesn't exist, badge is orphaned and should be deleted)
            # For now, we leave them - they'll be cleaned up when we detect
            # the process doesn't exist anymore

        logger.info("Found %d existing badge files", len(existing_badges))

    def _handle_event(self, cpu: int, data: bytes, size: int) -> None:
        """Handle event from BPF perf buffer.

        Args:
            cpu: CPU that generated the event.
            data: Raw event data.
            size: Size of event data.
        """
        if self._bpf_manager is None:
            return

        try:
            event = self._bpf_manager.parse_event(data)
            self._process_event(event)
        except Exception as e:
            logger.error("Error processing event: %s", e)

    def _handle_lost_events(self, lost_count: int) -> None:
        """Handle lost events from perf buffer.

        Args:
            lost_count: Number of events that were lost.
        """
        logger.warning("Lost %d events from perf buffer", lost_count)

    def _process_event(self, event: EBPFEvent) -> None:
        """Process a parsed BPF event.

        Args:
            event: Parsed EBPFEvent.
        """
        pid = event.pid
        comm = event.get_comm()
        syscall = event.syscall

        logger.debug(
            "Event: syscall=%d, pid=%d, comm=%s",
            syscall,
            pid,
            comm,
        )

        if syscall == SYSCALL_READ:
            self._handle_read_event(pid, comm)
        elif syscall == SYSCALL_READ_EXIT:
            self._handle_read_exit_event(pid, comm)
        elif syscall == SYSCALL_EXIT:
            self._handle_exit_event(pid, comm)

    def _handle_read_event(self, pid: int, comm: str) -> None:
        """Handle sys_enter_read event for stdin.

        Args:
            pid: Process ID.
            comm: Process name.
        """
        process = self._state.get_process(pid)

        if process is None:
            # New process detected - try to create MonitoredProcess
            logger.info("New AI process detected: %s (PID=%d)", comm, pid)
            process = self._process_tracker.create_monitored_process(pid, comm)

            if process is None:
                logger.warning(
                    "Could not resolve window for PID %d, skipping",
                    pid,
                )
                return

            self._state.add_process(process)
            logger.info(
                "Tracking new process: %s (PID=%d, window=%d, project=%s)",
                process.comm,
                process.pid,
                process.window_id,
                process.project_name or "(none)",
            )

            # Write initial badge (WORKING state, with OTEL enrichment if available)
            otel_data = self._otel_sessions.get(process.window_id)
            self._badge_writer.write_badge(process, otel_data=otel_data)

        # If process was WAITING and now got another read event,
        # it means user resumed interaction
        if process.state == ProcessState.WAITING:
            self._transition_to_working(process)

        # Record read entry time for timeout detection
        process.enter_read()

    def _handle_read_exit_event(self, pid: int, comm: str) -> None:
        """Handle sys_exit_read event.

        This indicates the read syscall completed (user provided input).
        If the process was in WAITING state, transition back to WORKING.

        Args:
            pid: Process ID.
            comm: Process name.
        """
        process = self._state.get_process(pid)
        if process is None:
            return

        # Clear read entry time
        process.exit_read()

        # If was waiting, user has resumed
        if process.state == ProcessState.WAITING:
            self._transition_to_working(process)

    def _handle_exit_event(self, pid: int, comm: str) -> None:
        """Handle process exit event.

        Args:
            pid: Process ID.
            comm: Process name.
        """
        process = self._state.remove_process(pid)

        if process is not None:
            logger.info(
                "Process exited: %s (PID=%d, window=%d)",
                process.comm,
                process.pid,
                process.window_id,
            )
            process.transition_to(ProcessState.EXITED)

            # Delete badge file
            self._badge_writer.delete_badge(process.window_id)

    def _check_waiting_timeouts(self) -> None:
        """Check for processes that have exceeded the waiting threshold."""
        for process in list(self._state.tracked_processes.values()):
            if process.state == ProcessState.WORKING:
                if process.is_waiting_timeout(self.threshold_ms):
                    self._transition_to_waiting(process)

    def _transition_to_waiting(self, process: MonitoredProcess) -> None:
        """Transition a process to WAITING state.

        Args:
            process: Process to transition.
        """
        if process.transition_to(ProcessState.WAITING):
            logger.info(
                "Process waiting for input: %s (PID=%d, window=%d)",
                process.comm,
                process.pid,
                process.window_id,
            )

            # Send notification
            if self._notifier.send_completion_notification(process):
                logger.debug("Notification sent for PID %d", process.pid)
            else:
                logger.warning("Failed to send notification for PID %d", process.pid)

            # Update badge with needs_attention=true and increment count (with OTEL enrichment)
            otel_data = self._otel_sessions.get(process.window_id)
            self._badge_writer.write_badge(process, increment_count=True, otel_data=otel_data)

    def _transition_to_working(self, process: MonitoredProcess) -> None:
        """Transition a process back to WORKING state.

        Called when a process that was WAITING gets a new read event,
        indicating the user has resumed interaction.

        Args:
            process: Process to transition.
        """
        if process.transition_to(ProcessState.WORKING):
            logger.info(
                "Process resumed: %s (PID=%d, window=%d)",
                process.comm,
                process.pid,
                process.window_id,
            )

            # Update badge - clear needs_attention (with OTEL enrichment)
            otel_data = self._otel_sessions.get(process.window_id)
            self._badge_writer.write_badge(process, otel_data=otel_data)

    # =========================================================================
    # OTEL Enrichment (Feature 119/123)
    # =========================================================================

    def _start_otel_subscriber(self) -> None:
        """Start OTEL subscriber for session enrichment.

        Connects to the otel-ai-monitor named pipe if available.
        OTEL data enriches badge files with token metrics and session IDs.
        """
        pipe_path = Path(f"/run/user/{self._uid}/otel-ai-monitor.pipe")

        if not pipe_path.exists():
            logger.info(
                "OTEL pipe not found at %s - enrichment disabled",
                pipe_path,
            )
            return

        try:
            self._otel_subscriber = OTELSubscriber(
                pipe_path=pipe_path,
                on_session_update=self._handle_otel_update,
            )
            self._otel_subscriber.start()
            logger.info("OTEL subscriber started for enrichment")
        except Exception as e:
            logger.warning("Failed to start OTEL subscriber: %s", e)
            self._otel_subscriber = None

    def _handle_otel_update(self, data: OTELSessionData) -> None:
        """Handle OTEL session data update.

        Stores OTEL data keyed by window_id for badge enrichment.
        If we have a tracked process for this window, updates its badge.

        Args:
            data: OTELSessionData from the OTEL monitor pipe.
        """
        if data.window_id is None:
            logger.debug("OTEL update without window_id: %s", data.session_id)
            return

        # Store OTEL data for enrichment
        self._otel_sessions[data.window_id] = data

        logger.debug(
            "OTEL update: window=%d, tool=%s, tokens=%d/%d",
            data.window_id,
            data.tool,
            data.input_tokens,
            data.output_tokens,
        )

        # If we have a tracked process for this window, update its badge
        for process in self._state.tracked_processes.values():
            if process.window_id == data.window_id:
                self._badge_writer.write_badge(process, otel_data=data)
                break

    def _get_otel_data(self, window_id: int) -> Optional[OTELSessionData]:
        """Get OTEL enrichment data for a window.

        Args:
            window_id: Sway container ID.

        Returns:
            OTELSessionData if available, None otherwise.
        """
        return self._otel_sessions.get(window_id)

    def _cleanup(self) -> None:
        """Clean up resources on shutdown."""
        # Stop OTEL subscriber
        if self._otel_subscriber is not None:
            self._otel_subscriber.stop()
            self._otel_subscriber = None

        # Cleanup BPF
        if self._bpf_manager is not None:
            self._bpf_manager.cleanup()
            self._bpf_manager = None

        logger.info("Cleanup complete")


def run_daemon(
    user: str,
    threshold_ms: int = 1000,
    target_processes: Optional[set[str]] = None,
) -> int:
    """Convenience function to run the daemon.

    Args:
        user: Username to monitor.
        threshold_ms: Wait threshold in milliseconds.
        target_processes: Process names to monitor.

    Returns:
        Exit code.
    """
    daemon = EBPFDaemon(
        user=user,
        threshold_ms=threshold_ms,
        target_processes=target_processes,
    )
    return daemon.run()
