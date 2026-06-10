"""Herdr service boundary for local event subscription and cache invalidation."""

from __future__ import annotations

import asyncio
import copy
import json
import logging
import os
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, Optional

logger = logging.getLogger(__name__)

HERDR_EVENT_SUBSCRIPTION_TYPES = (
    "workspace.created",
    "workspace.updated",
    "workspace.renamed",
    "workspace.closed",
    "workspace.focused",
    "tab.created",
    "tab.closed",
    "tab.focused",
    "tab.renamed",
    "pane.created",
    "pane.closed",
    "pane.focused",
    "pane.exited",
    "pane.agent_detected",
)


class HerdrService:
    """Own local Herdr event subscription lifecycle and notification coalescing."""

    def __init__(
        self,
        *,
        notify_state_change: Callable[[str], Awaitable[None]],
        invalidate_snapshot_cache: Optional[Callable[[], None]] = None,
        socket_env_var: str = "I3PM_HERDR_SOCKET",
        subscription_initial_backoff: float = 0.5,
        subscription_max_backoff: float = 30.0,
        notify_delay: float = 0.05,
        snapshot_cache_ttl: float = 0.5,
        remote_snapshot_cache_ttl: float = 10.0,
    ) -> None:
        self._notify_state_change = notify_state_change
        self._external_invalidate_snapshot_cache = invalidate_snapshot_cache
        self._socket_env_var = socket_env_var
        self.subscription_initial_backoff = subscription_initial_backoff
        self.subscription_max_backoff = subscription_max_backoff
        self.notify_delay = notify_delay
        self.subscription_task: Optional[asyncio.Task] = None
        self.notify_task: Optional[asyncio.Task] = None
        self.local_herdr_generation: int = 0
        self.remote_herdr_generation: Dict[str, int] = {}
        self.snapshot_cache: Dict[str, Any] = {}
        self.snapshot_cache_time: float = 0.0
        self.snapshot_cache_ttl: float = snapshot_cache_ttl
        self.remote_snapshot_cache_ttl: float = remote_snapshot_cache_ttl

    @staticmethod
    def normalize_host_key(host: Any) -> str:
        """Normalize a Herdr host key for generation tracking."""
        return str(host or "").strip().lower()

    def bump_local_generation(self) -> int:
        """Advance and return the local Herdr generation."""
        self.local_herdr_generation += 1
        return self.local_herdr_generation

    def bump_remote_generation(self, host: Any) -> int:
        """Advance and return a remote Herdr host generation."""
        host_key = self.normalize_host_key(host)
        if not host_key:
            return 0
        generation = int(self.remote_herdr_generation.get(host_key, 0)) + 1
        self.remote_herdr_generation[host_key] = generation
        return generation

    def remote_generation_for(self, host: Any) -> int:
        """Return the current generation for a remote Herdr host."""
        host_key = self.normalize_host_key(host)
        if not host_key:
            return 0
        return int(self.remote_herdr_generation.get(host_key, 0))

    def remote_generations_snapshot(self) -> Dict[str, int]:
        """Return a copy of remote Herdr host generations."""
        return {
            str(host): int(generation)
            for host, generation in self.remote_herdr_generation.items()
        }

    def generations_snapshot(self) -> Dict[str, Any]:
        """Return local and remote Herdr generation counters."""
        return {
            "local_herdr_generation": int(self.local_herdr_generation),
            "remote_herdr_generation": self.remote_generations_snapshot(),
        }

    def cache_ttl(self, *, has_remote_targets: bool) -> float:
        """Return the active Herdr snapshot cache TTL."""
        if has_remote_targets:
            return float(self.remote_snapshot_cache_ttl)
        return float(self.snapshot_cache_ttl)

    def cached_snapshot(
        self,
        *,
        now: float,
        has_remote_targets: bool,
    ) -> Optional[Dict[str, Any]]:
        """Return a copy of a valid cached Herdr snapshot."""
        if not self.snapshot_cache:
            return None
        if now - self.snapshot_cache_time > self.cache_ttl(has_remote_targets=has_remote_targets):
            return None
        return copy.deepcopy(self.snapshot_cache)

    def store_snapshot(self, snapshot: Dict[str, Any], *, now: float) -> Dict[str, Any]:
        """Store and return a defensive copy of a Herdr snapshot."""
        self.snapshot_cache = copy.deepcopy(snapshot)
        self.snapshot_cache_time = float(now)
        return copy.deepcopy(self.snapshot_cache)

    def touch_snapshot_cache(self, *, now: float) -> None:
        """Refresh the cache timestamp after in-place cache reconciliation."""
        self.snapshot_cache_time = float(now)

    def invalidate_snapshot_cache(self) -> None:
        """Clear cached Herdr snapshots so the next read fetches fresh state."""
        self.snapshot_cache = {}
        self.snapshot_cache_time = 0.0
        if self._external_invalidate_snapshot_cache is not None:
            self._external_invalidate_snapshot_cache()

    def socket_path(self) -> Path:
        """Return the local Herdr API socket path."""
        override = str(os.environ.get(self._socket_env_var) or "").strip()
        if override:
            return Path(os.path.expanduser(override))
        return Path.home() / ".config" / "herdr" / "herdr.sock"

    def event_subscribe_payload(self) -> Dict[str, Any]:
        """Return the JSON-RPC payload for Herdr's event stream API."""
        return {
            "id": "i3pm-herdr-events",
            "method": "events.subscribe",
            "params": {
                "subscriptions": [
                    {"type": event_type}
                    for event_type in HERDR_EVENT_SUBSCRIPTION_TYPES
                ],
            },
        }

    async def write_json_line(
        self,
        writer: asyncio.StreamWriter,
        payload: Dict[str, Any],
    ) -> None:
        writer.write(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n")
        await writer.drain()

    async def read_json_line(
        self,
        reader: asyncio.StreamReader,
        *,
        timeout: Optional[float] = None,
    ) -> Dict[str, Any]:
        if timeout:
            line = await asyncio.wait_for(reader.readline(), timeout=timeout)
        else:
            line = await reader.readline()
        if not line:
            raise ConnectionError("Herdr event stream closed")
        payload = json.loads(line.decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("Herdr event stream returned non-object JSON")
        return payload

    async def connect_subscription_once(self) -> None:
        """Connect once to the local Herdr event stream and process events until close."""
        socket_path = self.socket_path()
        reader, writer = await asyncio.open_unix_connection(str(socket_path))
        try:
            request = self.event_subscribe_payload()
            await self.write_json_line(writer, request)
            ack = await self.read_json_line(reader, timeout=3.0)
            result = ack.get("result") if isinstance(ack, dict) else {}
            if (
                ack.get("id") != request["id"]
                or not isinstance(result, dict)
                or result.get("type") != "subscription_started"
            ):
                raise RuntimeError(f"Herdr event subscription failed: {ack}")
            logger.info("Subscribed to local Herdr events at %s", socket_path)

            while True:
                event = await self.read_json_line(reader)
                await self.handle_subscription_event(event)
        finally:
            writer.close()
            await self._close_writer(writer)

    async def run_subscription(self) -> None:
        """Maintain a local Herdr event subscription with bounded reconnect backoff."""
        backoff = self.subscription_initial_backoff
        while True:
            try:
                await self.connect_subscription_once()
                backoff = self.subscription_initial_backoff
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.debug("Local Herdr event subscription unavailable: %s", exc)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, self.subscription_max_backoff)

    def start_subscription(self) -> None:
        """Start the local Herdr event subscription task."""
        if self.subscription_task and not self.subscription_task.done():
            return
        self.subscription_task = asyncio.create_task(
            self.run_subscription(),
            name="i3pm-herdr-event-subscription",
        )

    async def stop_subscription(self) -> None:
        """Cancel Herdr event subscription and pending notification tasks."""
        notify_task = self.notify_task
        self.notify_task = None
        if notify_task and not notify_task.done():
            notify_task.cancel()
            await asyncio.gather(notify_task, return_exceptions=True)

        task = self.subscription_task
        self.subscription_task = None
        if not task or task.done():
            return
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)

    async def handle_subscription_event(self, event: Dict[str, Any]) -> None:
        """Invalidate Herdr-derived dashboard state after a local Herdr event."""
        if not isinstance(event, dict):
            return
        self.bump_local_generation()
        self.invalidate_snapshot_cache()
        self.schedule_state_change_notification()

    def schedule_state_change_notification(self) -> None:
        """Coalesce bursts of local Herdr socket events into one dashboard update."""
        task = self.notify_task
        if task is not None and not task.done():
            return

        async def notify_later() -> None:
            try:
                delay = max(0.0, float(self.notify_delay))
                if delay > 0:
                    await asyncio.sleep(delay)
                await self._notify_state_change("ai_session_herdr_changed")
            except asyncio.CancelledError:
                raise
            finally:
                current = self.notify_task
                if current is task_ref:
                    self.notify_task = None

        task_ref = asyncio.create_task(
            notify_later(),
            name="i3pm-herdr-event-notify",
        )
        self.notify_task = task_ref

    @staticmethod
    async def _close_writer(writer: asyncio.StreamWriter) -> None:
        try:
            await asyncio.wait_for(writer.wait_closed(), timeout=0.5)
        except TimeoutError:
            logger.debug("Timed out waiting for Herdr event socket to close; continuing")
