"""Herdr service boundary for local event subscription and cache invalidation."""

from __future__ import annotations

import asyncio
import copy
import json
import logging
import os
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple

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
        self.remote_targets_cache: List[Dict[str, str]] = []
        self.remote_targets_cache_signature: Tuple[Any, ...] = ("", False, 0, 0)

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

    def apply_remote_focus_cache(
        self,
        *,
        target: Dict[str, str],
        pane_id: str,
        normalize_connection_key: Callable[[str], str],
        now: float,
    ) -> Dict[str, Any]:
        """Optimistically reflect remote pane focus in the cached Herdr snapshot."""
        pane_key = str(pane_id or "").strip()
        if not pane_key or not self.snapshot_cache:
            return {
                "updated": False,
                "focused_session_key": "",
                "connection_key": "",
            }

        host = self.normalize_host_key(target.get("host"))
        ssh_target = str(target.get("ssh_target") or "").strip()
        connection_key = normalize_connection_key(
            str(target.get("connection_key") or "").strip()
        )

        def matches_remote(item: Dict[str, Any]) -> bool:
            item_host = self.normalize_host_key(
                item.get("herdr_host") or item.get("host_name") or item.get("host")
            )
            item_ssh = str(item.get("ssh_target") or item.get("remote_target") or "").strip()
            item_connection = normalize_connection_key(str(item.get("connection_key") or "").strip())
            if host and item_host == host:
                return True
            if ssh_target and item_ssh == ssh_target:
                return True
            return bool(connection_key and item_connection == connection_key)

        focused_session_key = ""
        updated = False
        for collection_name in ("sessions", "panes", "agents"):
            rows = self.snapshot_cache.get(collection_name)
            if not isinstance(rows, list):
                continue
            for row in rows:
                if not isinstance(row, dict) or not matches_remote(row):
                    continue
                focused = str(row.get("pane_id") or "").strip() == pane_key
                row["focused"] = focused
                row["is_current_window"] = focused
                row["window_active"] = focused
                row["pane_active"] = focused
                updated = True
                if focused and collection_name == "sessions":
                    focused_session_key = str(
                        row.get("session_key") or row.get("herdr_session") or ""
                    ).strip()

        remote_snapshots = self.snapshot_cache.get("remote_snapshots")
        if isinstance(remote_snapshots, list):
            for remote_snapshot in remote_snapshots:
                if not isinstance(remote_snapshot, dict):
                    continue
                snapshot_target = {
                    "host": str(remote_snapshot.get("host") or "").strip(),
                    "ssh_target": str(remote_snapshot.get("ssh_target") or "").strip(),
                    "connection_key": normalize_connection_key(
                        str(remote_snapshot.get("connection_key") or "").strip()
                    ),
                }
                if not matches_remote(snapshot_target):
                    continue
                for collection_name in ("sessions", "panes", "agents"):
                    rows = remote_snapshot.get(collection_name)
                    if not isinstance(rows, list):
                        continue
                    for row in rows:
                        if not isinstance(row, dict):
                            continue
                        row["focused"] = str(row.get("pane_id") or "").strip() == pane_key
                        updated = True

        if updated:
            self.touch_snapshot_cache(now=now)

        return {
            "updated": updated,
            "focused_session_key": focused_session_key,
            "connection_key": connection_key,
        }

    def remote_targets_file(self) -> Path:
        """Return the configured remote Herdr target file path."""
        configured = str(os.environ.get("I3PM_HERDR_REMOTE_TARGETS_FILE") or "").strip()
        if configured:
            return Path(configured).expanduser()
        return Path.home() / ".config/i3/herdr-remote-targets.json"

    @staticmethod
    def file_signature(path: Path) -> Tuple[bool, int, int]:
        """Return a cheap file signature for remote target cache invalidation."""
        try:
            stat = path.stat()
        except OSError:
            return (False, 0, 0)
        return (True, int(stat.st_mtime_ns), int(stat.st_size))

    def connection_key_for_target(
        self,
        ssh_target: str,
        explicit: str = "",
        *,
        parse_remote_target: Callable[[str], Tuple[str, str, int]],
        normalize_connection_key: Callable[[str], str],
    ) -> str:
        """Return a normalized connection key for a remote Herdr target."""
        explicit_key = str(explicit or "").strip()
        if explicit_key:
            return normalize_connection_key(explicit_key)
        user, host, port = parse_remote_target(ssh_target)
        if not host:
            return "unknown"
        user = user or os.environ.get("USER") or "vpittamp"
        return normalize_connection_key(f"{user}@{host}:{port or 22}")

    def load_remote_targets(
        self,
        *,
        parse_remote_target: Callable[[str], Tuple[str, str, int]],
        normalize_connection_key: Callable[[str], str],
    ) -> List[Dict[str, str]]:
        """Load and normalize configured remote Herdr targets."""
        path = self.remote_targets_file()
        env_payload = str(os.environ.get("I3PM_HERDR_REMOTE_TARGETS") or "").strip()
        signature = (env_payload, *self.file_signature(path))
        if signature == self.remote_targets_cache_signature:
            return [dict(item) for item in self.remote_targets_cache]

        raw_targets: Any = []
        if env_payload:
            try:
                parsed = json.loads(env_payload)
                if isinstance(parsed, list):
                    raw_targets = parsed
            except json.JSONDecodeError:
                logger.warning("Ignoring invalid I3PM_HERDR_REMOTE_TARGETS JSON")
        elif path.exists():
            try:
                with path.open("r", encoding="utf-8") as handle:
                    parsed = json.load(handle)
                if isinstance(parsed, list):
                    raw_targets = parsed
            except (OSError, json.JSONDecodeError) as exc:
                logger.warning("Ignoring invalid Herdr remote target config %s: %s", path, exc)

        targets: List[Dict[str, str]] = []
        seen: set[str] = set()
        for item in raw_targets if isinstance(raw_targets, list) else []:
            if not isinstance(item, dict):
                continue
            host = str(item.get("host") or "").strip().lower()
            ssh_target = str(item.get("ssh_target") or item.get("sshTarget") or host).strip()
            if not ssh_target:
                continue
            if not host:
                _user, parsed_host, _port = parse_remote_target(ssh_target)
                host = parsed_host.lower()
            connection_key = self.connection_key_for_target(
                ssh_target,
                str(item.get("connection_key") or item.get("connectionKey") or ""),
                parse_remote_target=parse_remote_target,
                normalize_connection_key=normalize_connection_key,
            )
            dedupe_key = connection_key if connection_key != "unknown" else ssh_target.lower()
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            targets.append({
                "host": host or ssh_target.lower(),
                "ssh_target": ssh_target,
                "connection_key": connection_key,
            })

        self.remote_targets_cache_signature = signature
        self.remote_targets_cache = [dict(item) for item in targets]
        return [dict(item) for item in targets]

    def resolve_remote_action_target(
        self,
        params: Dict[str, Any],
        *,
        targets: List[Dict[str, str]],
        parse_remote_target: Callable[[str], Tuple[str, str, int]],
        normalize_connection_key: Callable[[str], str],
    ) -> Dict[str, str]:
        """Resolve a remote Herdr action target from request params and config."""
        host = str(params.get("host") or params.get("herdr_host") or "").strip().lower()
        ssh_target = str(params.get("ssh_target") or params.get("remote_target") or "").strip()
        connection_key = normalize_connection_key(str(params.get("connection_key") or "").strip())

        for target in targets:
            target_host = str(target.get("host") or "").strip().lower()
            target_ssh = str(target.get("ssh_target") or "").strip()
            target_connection = normalize_connection_key(str(target.get("connection_key") or "").strip())
            if ssh_target and target_ssh == ssh_target:
                return dict(target)
            if connection_key and target_connection == connection_key:
                return dict(target)
            if host and target_host == host:
                return dict(target)

        if ssh_target:
            return {
                "host": host or ssh_target.lower(),
                "ssh_target": ssh_target,
                "connection_key": connection_key or self.connection_key_for_target(
                    ssh_target,
                    parse_remote_target=parse_remote_target,
                    normalize_connection_key=normalize_connection_key,
                ),
            }

        raise ValueError("ssh_target is required for remote Herdr pane focus")

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
