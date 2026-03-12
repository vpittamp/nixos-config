"""Session list output for OpenTelemetry AI Assistant Monitor.

The monitoring panel now consumes a single canonical JSON file:
`$XDG_RUNTIME_DIR/otel-ai-sessions.json`.

This writer performs atomic writes and skips unchanged payloads to reduce
filesystem churn and downstream wakeups.
"""

import asyncio
import hashlib
import json
import logging
import os
from pathlib import Path
from typing import TYPE_CHECKING, Optional

from .models import SessionList, SessionUpdate
from .sway_helper import tmux_target_exists

logger = logging.getLogger(__name__)

if TYPE_CHECKING:
    from .remote_transport import RemoteSessionPushClient


class OutputWriter:
    """Atomic JSON writer for OTEL AI session state."""

    def __init__(
        self,
        json_file_path: Optional[Path] = None,
        remote_push_client: Optional["RemoteSessionPushClient"] = None,
    ) -> None:
        runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
        self.json_file_path = json_file_path or (runtime_dir / "otel-ai-sessions.json")
        self.remote_push_client = remote_push_client
        self._lock = asyncio.Lock()
        self._running = False
        self._last_payload_hash: Optional[str] = None

    async def start(self) -> None:
        """Start writer and ensure output directory exists."""
        self._running = True
        self.json_file_path.parent.mkdir(parents=True, exist_ok=True)
        if self.remote_push_client:
            await self.remote_push_client.start()
        logger.info("Output writer using %s", self.json_file_path)

    async def stop(self) -> None:
        """Stop writer."""
        self._running = False
        if self.remote_push_client:
            await self.remote_push_client.stop()
        logger.info("Output writer stopped")

    async def write_update(self, update: SessionUpdate) -> None:
        """Handle point updates.

        The UI consumes session list snapshots from file, so updates are only
        retained for optional debugging and no file write is performed here.
        """
        if not self._running:
            return
        logger.debug("Session update: %s state=%s", update.session_id, update.state)

    async def write_session_list(self, session_list: SessionList) -> None:
        """Write session list to JSON file with no-op suppression."""
        if not self._running:
            return

        data = session_list.model_dump()
        for item in data.get("sessions", []):
            if not isinstance(item, dict):
                continue
            terminal_context = item.get("terminal_context") or {}
            if not isinstance(terminal_context, dict):
                continue
            if str(terminal_context.get("execution_mode") or "").strip().lower() != "ssh":
                continue
            if not (
                terminal_context.get("tmux_session")
                or terminal_context.get("tmux_window")
                or terminal_context.get("tmux_pane")
                or terminal_context.get("pty")
            ):
                continue
            if tmux_target_exists(
                tmux_session=terminal_context.get("tmux_session"),
                tmux_window=terminal_context.get("tmux_window"),
                tmux_pane=terminal_context.get("tmux_pane"),
                pty=terminal_context.get("pty"),
            ):
                continue
            terminal_context["tmux_session"] = None
            terminal_context["tmux_window"] = None
            terminal_context["tmux_pane"] = None
            terminal_context["pty"] = None
        json_content = json.dumps(data, separators=(",", ":"), sort_keys=True)
        payload_hash = hashlib.sha256(json_content.encode("utf-8")).hexdigest()

        async with self._lock:
            should_write_file = payload_hash != self._last_payload_hash

            if should_write_file:
                try:
                    await asyncio.to_thread(self._sync_write_file, json_content)
                    self._last_payload_hash = payload_hash
                except Exception as e:
                    logger.error(f"Error writing JSON file: {e}")

        if self.remote_push_client:
            try:
                await self.remote_push_client.publish_snapshot(data, payload_hash)
            except Exception as e:
                logger.warning(f"Remote OTEL push publish failed: {e}")

    def _sync_write_file(self, content: str) -> None:
        """Write file atomically using temp file + rename."""
        temp_path = self.json_file_path.with_suffix(".tmp")
        temp_path.write_text(content, encoding="utf-8")
        temp_path.replace(self.json_file_path)
