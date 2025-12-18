"""JSON stream output for OpenTelemetry AI Assistant Monitor.

This module handles writing NDJSON (newline-delimited JSON) output
to stdout or a named pipe for EWW deflisten consumption.

Additionally writes to a JSON file for widgets that can't share the pipe.

Output formats:
- SessionUpdate: Emitted on state changes for real-time UI updates
- SessionList: Broadcast periodically for initialization/recovery
"""

import asyncio
import json
import logging
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Optional, TextIO

from .models import SessionList, SessionUpdate

logger = logging.getLogger(__name__)


class OutputWriter:
    """NDJSON output writer for EWW consumption.

    Writes JSON objects as newline-delimited strings to stdout or named pipe.
    Also writes session list to a JSON file for multiple readers.
    Handles pipe creation, connection, and error recovery.
    """

    def __init__(self, pipe_path: Optional[Path] = None) -> None:
        """Initialize the output writer.

        Args:
            pipe_path: Path to named pipe (FIFO). If None, writes to stdout.
        """
        self.pipe_path = pipe_path
        self._output: Optional[TextIO] = None
        self._lock = asyncio.Lock()
        self._running = False
        # JSON file path for multiple readers (derived from pipe path)
        self.json_file_path = self._get_json_file_path()

    def _get_json_file_path(self) -> Path:
        """Get JSON file path for multiple readers.

        Returns path to JSON file in XDG_RUNTIME_DIR that can be read
        by multiple EWW widgets via defpoll.
        """
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        return Path(runtime_dir) / "otel-ai-sessions.json"

    async def start(self) -> None:
        """Start the output writer.

        Creates named pipe if specified, otherwise uses stdout.
        """
        self._running = True

        if self.pipe_path:
            await self._setup_pipe()
        else:
            self._output = sys.stdout
            logger.info("Output writer using stdout")

    async def stop(self) -> None:
        """Stop the output writer and cleanup resources."""
        self._running = False

        if self.pipe_path and self._output and self._output != sys.stdout:
            try:
                self._output.close()
            except Exception:
                pass

        logger.info("Output writer stopped")

    async def _setup_pipe(self) -> None:
        """Create and open the named pipe."""
        if not self.pipe_path:
            return

        # Create pipe directory if needed
        self.pipe_path.parent.mkdir(parents=True, exist_ok=True)

        # Reuse existing pipe if it's already a FIFO - don't delete and recreate
        # Deleting would orphan any existing readers (like EWW's deflisten)
        if self.pipe_path.exists():
            if stat.S_ISFIFO(self.pipe_path.stat().st_mode):
                logger.info(f"Reusing existing named pipe at {self.pipe_path}")
                return
            else:
                # Not a FIFO, remove it
                self.pipe_path.unlink()

        # Create FIFO
        os.mkfifo(self.pipe_path)
        logger.info(f"Created named pipe at {self.pipe_path}")

        # Note: Opening FIFO blocks until reader connects
        # We open in non-blocking mode to avoid deadlock
        # The actual open happens when we first write

    def _ensure_pipe_open(self) -> bool:
        """Ensure pipe is open for writing.

        Returns True if pipe is ready, False otherwise.
        Non-blocking open to handle case where no reader is connected.
        """
        if not self.pipe_path:
            return self._output is not None

        if self._output is not None:
            return True

        try:
            # Use O_RDWR to avoid FIFO deadlock where reader blocks in open()
            # waiting for writer, but writer's O_NONBLOCK fails because reader
            # hasn't completed its open(). O_RDWR opens without blocking.
            fd = os.open(str(self.pipe_path), os.O_RDWR | os.O_NONBLOCK)
            self._output = os.fdopen(fd, "w")
            logger.info(f"Opened pipe for writing: {self.pipe_path}")
            return True
        except OSError as e:
            logger.warning(f"Error opening pipe: {e}")
            return False

    async def write_update(self, update: SessionUpdate) -> None:
        """Write a session update event.

        Args:
            update: SessionUpdate to write as JSON
        """
        await self._write_json(update.model_dump())

    async def write_session_list(self, session_list: SessionList) -> None:
        """Write a full session list broadcast.

        Writes to both:
        1. Named pipe (for deflisten consumers - single reader)
        2. JSON file (for defpoll consumers - multiple readers)

        Args:
            session_list: SessionList to write as JSON
        """
        data = session_list.model_dump()
        # Write to pipe for deflisten (single reader like top-bar)
        await self._write_json(data)
        # Write to file for defpoll (multiple readers like monitoring-panel)
        await self._write_json_file(data)

    async def _write_json(self, data: dict) -> None:
        """Write JSON object as NDJSON line.

        Args:
            data: Dictionary to serialize and write
        """
        async with self._lock:
            if not self._running:
                return

            # For named pipe, ensure it's open
            if self.pipe_path and not self._ensure_pipe_open():
                # No reader connected, drop the message
                logger.debug("No pipe reader, dropping message")
                return

            if self._output is None:
                return

            try:
                line = json.dumps(data, separators=(",", ":")) + "\n"
                # CRITICAL: Use asyncio.to_thread for blocking I/O operations
                # Without this, write() and flush() can block the entire event loop
                # when the pipe buffer is full, causing Claude Code to hang
                await asyncio.wait_for(
                    asyncio.to_thread(self._sync_write, line),
                    timeout=1.0  # 1 second timeout to prevent indefinite blocking
                )
            except asyncio.TimeoutError:
                logger.warning("Pipe write timed out, dropping message")
            except BrokenPipeError:
                # Reader disconnected
                logger.warning("Pipe reader disconnected")
                if self._output != sys.stdout:
                    self._output = None
            except Exception as e:
                logger.error(f"Error writing output: {e}")

    def _sync_write(self, line: str) -> None:
        """Synchronous write helper for thread execution.

        Args:
            line: The line to write to output
        """
        if self._output is not None:
            self._output.write(line)
            self._output.flush()

    async def _write_json_file(self, data: dict) -> None:
        """Write JSON data to file atomically for multiple readers.

        Uses atomic write (temp file + rename) to prevent partial reads.
        This allows multiple EWW widgets to read via defpoll without
        conflicts that occur with named pipes (FIFO only supports one reader).

        Args:
            data: Dictionary to serialize and write
        """
        if not self._running:
            return

        try:
            json_content = json.dumps(data, separators=(",", ":"))
            await asyncio.to_thread(self._sync_write_file, json_content)
        except Exception as e:
            logger.error(f"Error writing JSON file: {e}")

    def _sync_write_file(self, content: str) -> None:
        """Synchronous atomic file write helper.

        Writes to temp file then renames for atomicity.

        Args:
            content: The JSON content to write
        """
        # Write to temp file in same directory for atomic rename
        temp_path = self.json_file_path.with_suffix(".tmp")
        try:
            temp_path.write_text(content)
            temp_path.rename(self.json_file_path)
        except Exception as e:
            # Clean up temp file on error
            if temp_path.exists():
                temp_path.unlink()
            raise e


def get_default_pipe_path() -> Path:
    """Get the default pipe path using XDG_RUNTIME_DIR.

    Returns:
        Path to the default named pipe location
    """
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    return Path(runtime_dir) / "otel-ai-monitor.pipe"
