"""Tmux session management for test isolation.

This module provides utilities for creating and managing tmux sessions
for test execution, allowing isolated test environments with split panes
for monitoring and command execution.
"""

import asyncio
import logging
import subprocess
import uuid
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import List, Optional


logger = logging.getLogger(__name__)


class SessionStatus(str, Enum):
    """Tmux session status enumeration."""
    INITIALIZING = "initializing"
    READY = "ready"
    RUNNING = "running"
    CLEANING_UP = "cleaning_up"
    CLOSED = "closed"


@dataclass
class TmuxSession:
    """Represents a tmux session for test isolation.

    Attributes:
        session_id: Unique tmux session identifier
        monitor_pane_id: Pane running monitor tool
        command_pane_id: Pane for command execution
        created_at: Session creation time
        status: Current session status
    """
    session_id: str
    monitor_pane_id: Optional[str] = None
    command_pane_id: Optional[str] = None
    created_at: datetime = datetime.now()
    status: SessionStatus = SessionStatus.INITIALIZING


class TmuxManager:
    """Manager for tmux test sessions.

    Provides high-level interface for creating tmux sessions with split
    panes, executing commands, capturing output, and cleanup.

    Attributes:
        session_prefix: Prefix for tmux session names
        active_sessions: Currently active tmux sessions
    """

    def __init__(self, session_prefix: str = "i3-project-test-"):
        """Initialize tmux manager.

        Args:
            session_prefix: Prefix for session identifiers
        """
        self.session_prefix = session_prefix
        self.active_sessions: List[TmuxSession] = []

    async def create_session(self, name: Optional[str] = None) -> TmuxSession:
        """Create a new tmux session with split panes.

        Creates a tmux session with two panes:
        - Pane 0: Monitor pane (for i3-project-monitor)
        - Pane 1: Command pane (for test commands)

        Args:
            name: Optional session name (auto-generated if None)

        Returns:
            TmuxSession instance

        Raises:
            RuntimeError: If tmux session creation fails
        """
        # Generate session ID
        session_id = name or f"{self.session_prefix}{uuid.uuid4().hex[:8]}"

        session = TmuxSession(
            session_id=session_id,
            status=SessionStatus.INITIALIZING,
        )

        try:
            logger.info(f"Creating tmux session: {session_id}")

            # Create new detached session
            await self._run_command(
                ["tmux", "new-session", "-d", "-s", session_id]
            )

            # Split window horizontally (creates second pane)
            await self._run_command(
                ["tmux", "split-window", "-h", "-t", f"{session_id}:0"]
            )

            # Get pane IDs
            panes = await self._get_pane_ids(session_id)
            if len(panes) != 2:
                raise RuntimeError(f"Expected 2 panes, got {len(panes)}")

            session.monitor_pane_id = panes[0]
            session.command_pane_id = panes[1]
            session.status = SessionStatus.READY

            self.active_sessions.append(session)
            logger.info(f"Tmux session ready: {session_id} (panes: {panes})")

            return session

        except Exception as e:
            logger.error(f"Failed to create tmux session: {e}")
            # Attempt cleanup
            await self._kill_session_silent(session_id)
            raise RuntimeError(f"Failed to create tmux session: {e}")

    async def run_in_pane(
        self,
        session: TmuxSession,
        pane_id: str,
        command: str,
        wait: bool = False,
    ) -> Optional[str]:
        """Execute command in specified pane.

        Args:
            session: Tmux session
            pane_id: Target pane ID
            command: Command to execute
            wait: Whether to wait for command completion and capture output

        Returns:
            Command output if wait=True, None otherwise

        Raises:
            RuntimeError: If command execution fails
        """
        try:
            logger.debug(f"Running command in pane {pane_id}: {command}")

            # Send keys to pane
            await self._run_command(
                ["tmux", "send-keys", "-t", pane_id, command, "Enter"]
            )

            if wait:
                # Wait a moment for command to execute
                await asyncio.sleep(0.5)
                # Capture pane output
                return await self.capture_pane(session, pane_id)

            return None

        except Exception as e:
            logger.error(f"Failed to run command in pane: {e}")
            raise RuntimeError(f"Failed to run command: {e}")

    async def run_monitor(
        self,
        session: TmuxSession,
        mode: str = "live",
    ) -> None:
        """Start monitor tool in monitor pane.

        Args:
            session: Tmux session
            mode: Monitor mode (live, events, history, etc.)

        Raises:
            RuntimeError: If monitor cannot be started
        """
        if not session.monitor_pane_id:
            raise RuntimeError("Session has no monitor pane")

        command = f"i3-project-monitor {mode}"
        await self.run_in_pane(session, session.monitor_pane_id, command)
        session.status = SessionStatus.RUNNING
        logger.info(f"Started monitor in session {session.session_id}")

    async def run_command(
        self,
        session: TmuxSession,
        command: str,
        wait: bool = False,
    ) -> Optional[str]:
        """Execute command in command pane.

        Args:
            session: Tmux session
            command: Command to execute
            wait: Whether to wait and capture output

        Returns:
            Command output if wait=True, None otherwise

        Raises:
            RuntimeError: If command execution fails
        """
        if not session.command_pane_id:
            raise RuntimeError("Session has no command pane")

        return await self.run_in_pane(session, session.command_pane_id, command, wait)

    async def capture_pane(
        self,
        session: TmuxSession,
        pane_id: str,
        lines: int = 100,
    ) -> str:
        """Capture output from specified pane.

        Args:
            session: Tmux session
            pane_id: Pane to capture from
            lines: Number of lines to capture

        Returns:
            Pane content as string

        Raises:
            RuntimeError: If capture fails
        """
        try:
            result = await self._run_command(
                ["tmux", "capture-pane", "-t", pane_id, "-p", "-S", f"-{lines}"]
            )
            return result.stdout

        except Exception as e:
            logger.error(f"Failed to capture pane output: {e}")
            raise RuntimeError(f"Failed to capture pane: {e}")

    async def cleanup_session(self, session: TmuxSession) -> None:
        """Clean up and kill tmux session.

        Args:
            session: Tmux session to cleanup
        """
        if session.status == SessionStatus.CLOSED:
            logger.debug(f"Session {session.session_id} already closed")
            return

        session.status = SessionStatus.CLEANING_UP
        logger.info(f"Cleaning up tmux session: {session.session_id}")

        try:
            await self._kill_session(session.session_id)
            session.status = SessionStatus.CLOSED

            # Remove from active sessions
            if session in self.active_sessions:
                self.active_sessions.remove(session)

        except Exception as e:
            logger.error(f"Error cleaning up session: {e}")
            session.status = SessionStatus.CLOSED

    async def cleanup_all(self) -> None:
        """Clean up all active tmux sessions."""
        logger.info(f"Cleaning up {len(self.active_sessions)} active sessions")

        for session in list(self.active_sessions):
            await self.cleanup_session(session)

    # Helper methods

    async def _run_command(
        self,
        cmd: List[str],
        check: bool = True,
    ) -> subprocess.CompletedProcess:
        """Run shell command asynchronously.

        Args:
            cmd: Command and arguments
            check: Whether to raise on non-zero exit

        Returns:
            CompletedProcess instance

        Raises:
            RuntimeError: If command fails and check=True
        """
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            stdout, stderr = await process.communicate()

            result = subprocess.CompletedProcess(
                args=cmd,
                returncode=process.returncode,
                stdout=stdout.decode(),
                stderr=stderr.decode(),
            )

            if check and result.returncode != 0:
                raise RuntimeError(
                    f"Command failed: {' '.join(cmd)}\n"
                    f"Exit code: {result.returncode}\n"
                    f"Stderr: {result.stderr}"
                )

            return result

        except Exception as e:
            if check:
                raise RuntimeError(f"Command execution failed: {e}")
            return subprocess.CompletedProcess(args=cmd, returncode=1, stdout="", stderr=str(e))

    async def _get_pane_ids(self, session_id: str) -> List[str]:
        """Get pane IDs for a session.

        Args:
            session_id: Tmux session ID

        Returns:
            List of pane IDs

        Raises:
            RuntimeError: If unable to get pane IDs
        """
        result = await self._run_command(
            ["tmux", "list-panes", "-t", session_id, "-F", "#{pane_id}"]
        )

        panes = [line.strip() for line in result.stdout.split("\n") if line.strip()]
        return panes

    async def _kill_session(self, session_id: str) -> None:
        """Kill tmux session.

        Args:
            session_id: Session to kill

        Raises:
            RuntimeError: If kill fails
        """
        await self._run_command(["tmux", "kill-session", "-t", session_id])

    async def _kill_session_silent(self, session_id: str) -> None:
        """Kill tmux session without raising exceptions.

        Args:
            session_id: Session to kill
        """
        try:
            await self._run_command(
                ["tmux", "kill-session", "-t", session_id],
                check=False,
            )
        except Exception:
            pass

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        # Note: Can't use async in __exit__, caller must call cleanup_all manually
        pass
