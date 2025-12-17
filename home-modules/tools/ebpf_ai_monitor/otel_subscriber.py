"""OTEL pipe subscriber for session enrichment.

This module subscribes to the otel-ai-monitor named pipe and provides
enrichment data (session_id, metrics, token counts) to the eBPF daemon.

The eBPF daemon is the authoritative source for working/waiting state
detection via syscall monitoring. OTEL data adds context like:
- Token counts (input, output, cache)
- Session IDs for correlation
- Tool identification

Architecture:
    otel-ai-monitor (OTLP receiver) → pipe → OTELSubscriber → eBPF daemon → badge files
"""

import json
import logging
import os
import select
import threading
from pathlib import Path
from typing import Callable, Optional

from .models import OTELSessionData

logger = logging.getLogger(__name__)


class OTELSubscriber:
    """Subscribe to otel-ai-monitor named pipe for session enrichment data.

    This subscriber reads JSON from the OTEL monitor's named pipe in a
    background thread and calls a callback with parsed session data.

    The pipe path is typically: $XDG_RUNTIME_DIR/otel-ai-monitor.pipe

    Example:
        >>> def on_update(data: OTELSessionData):
        ...     print(f"Session {data.session_id}: {data.tool}")
        >>> subscriber = OTELSubscriber(
        ...     pipe_path=Path("/run/user/1000/otel-ai-monitor.pipe"),
        ...     on_session_update=on_update,
        ... )
        >>> subscriber.start()
        >>> # ... later ...
        >>> subscriber.stop()
    """

    def __init__(
        self,
        pipe_path: Path,
        on_session_update: Callable[[OTELSessionData], None],
    ) -> None:
        """Initialize OTEL subscriber.

        Args:
            pipe_path: Path to the otel-ai-monitor named pipe.
            on_session_update: Callback for each session update received.
        """
        self.pipe_path = pipe_path
        self.on_session_update = on_session_update
        self._running = False
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        """Start reading from OTEL pipe in background thread."""
        if self._running:
            logger.warning("OTEL subscriber already running")
            return

        self._running = True
        self._thread = threading.Thread(
            target=self._read_loop,
            name="otel-subscriber",
            daemon=True,
        )
        self._thread.start()
        logger.info("OTEL subscriber started, watching: %s", self.pipe_path)

    def stop(self) -> None:
        """Stop reading from OTEL pipe."""
        self._running = False
        if self._thread is not None:
            # Thread is daemon, will exit when main thread exits
            # Give it a moment to clean up
            self._thread.join(timeout=1.0)
            self._thread = None
        logger.info("OTEL subscriber stopped")

    def _read_loop(self) -> None:
        """Continuously read JSON from pipe.

        Uses non-blocking I/O with select() to allow clean shutdown.
        Handles pipe reconnection if the pipe is recreated.
        """
        while self._running:
            try:
                if not self.pipe_path.exists():
                    logger.debug("OTEL pipe not found, waiting...")
                    self._sleep(1.0)
                    continue

                self._read_from_pipe()

            except Exception as e:
                logger.error("OTEL pipe error: %s", e)
                self._sleep(1.0)

    def _read_from_pipe(self) -> None:
        """Read lines from the pipe until EOF or shutdown."""
        try:
            # Open pipe in non-blocking read mode
            fd = os.open(str(self.pipe_path), os.O_RDONLY | os.O_NONBLOCK)
            try:
                with os.fdopen(fd, 'r') as pipe:
                    buffer = ""
                    while self._running:
                        # Use select with timeout for interruptibility
                        readable, _, _ = select.select([pipe], [], [], 0.5)

                        if not readable:
                            continue

                        try:
                            chunk = pipe.read(4096)
                            if not chunk:
                                # EOF - pipe closed, reconnect
                                logger.info("OTEL pipe EOF, reconnecting...")
                                break

                            logger.info("OTEL pipe read %d bytes", len(chunk))
                            buffer += chunk

                            # Process complete lines
                            while '\n' in buffer:
                                line, buffer = buffer.split('\n', 1)
                                if line.strip():
                                    self._process_line(line.strip())

                        except BlockingIOError:
                            # No data available, continue
                            continue

            except OSError:
                pass  # fd already closed

        except OSError as e:
            logger.debug("Could not open OTEL pipe: %s", e)

    def _process_line(self, line: str) -> None:
        """Process a JSON line from OTEL pipe.

        Parses session_list messages and calls the callback for each session.

        Args:
            line: JSON line to process.
        """
        try:
            data = json.loads(line)
            logger.info("OTEL pipe received: %s", line[:100])

            msg_type = data.get("type", "")

            if msg_type == "session_list":
                # Process each session in the list
                for session in data.get("sessions", []):
                    try:
                        otel_data = OTELSessionData.model_validate(session)
                        self.on_session_update(otel_data)
                    except Exception as e:
                        logger.debug("Failed to parse session: %s", e)

            elif msg_type == "session_update":
                # Single session update
                try:
                    otel_data = OTELSessionData.model_validate(data)
                    self.on_session_update(otel_data)
                except Exception as e:
                    logger.debug("Failed to parse session update: %s", e)

            elif msg_type == "error":
                logger.warning("OTEL monitor error: %s", data.get("error", "unknown"))

        except json.JSONDecodeError as e:
            logger.debug("Failed to parse OTEL JSON: %s", e)

    def _sleep(self, seconds: float) -> None:
        """Interruptible sleep.

        Args:
            seconds: Time to sleep.
        """
        import time
        start = time.monotonic()
        while self._running and (time.monotonic() - start) < seconds:
            time.sleep(0.1)
