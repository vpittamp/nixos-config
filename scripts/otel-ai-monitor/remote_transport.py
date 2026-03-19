"""Deterministic remote session push/sink transport for OTEL AI sessions.

This module provides:
1) Source-side push client: sends session snapshots to a remote sink endpoint.
2) Sink-side store: validates sequence ordering and persists latest snapshots.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import re
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Any, Optional

logger = logging.getLogger(__name__)
AI_SESSION_SCHEMA_VERSION = "11"

if TYPE_CHECKING:
    from aiohttp import ClientSession


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_iso_epoch(value: str) -> float:
    raw = str(value or "").strip()
    if not raw:
        return 0.0
    try:
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        return float(datetime.fromisoformat(raw).timestamp())
    except ValueError:
        return 0.0


def _normalize_connection_key(value: str) -> str:
    raw = str(value or "").strip().lower()
    if not raw:
        return "unknown"
    return re.sub(r"[^a-z0-9@._:-]+", "-", raw)


def _format_exception_detail(exc: Exception) -> str:
    """Return a useful log string even for blank exception messages."""
    detail = str(exc).strip()
    if detail:
        return f"{exc.__class__.__name__}: {detail}"
    return exc.__class__.__name__


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path: Optional[Path] = None
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=str(path.parent),
        )
        temp_path = Path(tmp_name)
        with os.fdopen(fd, "w") as f:
            json.dump(payload, f, separators=(",", ":"), sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, path)
        temp_path = None
    finally:
        if temp_path and temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass


class RemoteSessionPushClient:
    """Pushes session snapshots to a remote sink endpoint with sequence ordering."""

    def __init__(
        self,
        *,
        endpoint_url: str,
        source_connection_key: str,
        source_host_name: str,
        auth_token: str = "",
        max_interval_sec: float = 8.0,
        request_timeout_sec: float = 5.0,
    ) -> None:
        self.endpoint_url = str(endpoint_url or "").strip()
        self.source_connection_key = _normalize_connection_key(source_connection_key)
        self.source_host_name = str(source_host_name or "").strip() or "unknown"
        self.auth_token = str(auth_token or "").strip()
        self.max_interval_sec = max(1.0, float(max_interval_sec))
        self.request_timeout_sec = max(0.5, float(request_timeout_sec))

        self.boot_id = str(uuid.uuid4())
        self._lock = asyncio.Lock()
        self._running = False
        self._event = asyncio.Event()
        self._worker_task: Optional[asyncio.Task] = None
        self._session: Optional["ClientSession"] = None

        self._latest_payload: Optional[dict[str, Any]] = None
        self._latest_payload_hash: Optional[str] = None
        self._sequence = 0

        self._last_sent_monotonic = 0.0
        self._last_sent_hash: Optional[str] = None
        self._last_sent_sequence = 0

    async def start(self) -> None:
        if self._running:
            return
        from aiohttp import ClientSession, ClientTimeout

        self._running = True
        timeout = ClientTimeout(total=self.request_timeout_sec)
        self._session = ClientSession(timeout=timeout)
        self._worker_task = asyncio.create_task(self._worker_loop())
        logger.info(
            "Remote OTEL push enabled: endpoint=%s source=%s",
            self.endpoint_url,
            self.source_connection_key,
        )

    async def stop(self) -> None:
        if not self._running:
            return
        self._running = False
        self._event.set()
        if self._worker_task:
            self._worker_task.cancel()
            try:
                await self._worker_task
            except asyncio.CancelledError:
                pass
        if self._session:
            await self._session.close()
            self._session = None
        logger.info("Remote OTEL push stopped")

    async def publish_snapshot(self, payload: dict[str, Any], payload_hash: str) -> None:
        """Publish latest snapshot into sender queue.

        Sequence increments only when payload content changes.
        """
        if not self._running:
            return
        async with self._lock:
            changed = payload_hash != self._latest_payload_hash
            self._latest_payload = payload
            self._latest_payload_hash = payload_hash
            if changed:
                self._sequence += 1
        self._event.set()

    async def _worker_loop(self) -> None:
        while self._running:
            try:
                try:
                    await asyncio.wait_for(self._event.wait(), timeout=self.max_interval_sec)
                    self._event.clear()
                except asyncio.TimeoutError:
                    pass
                if not self._running:
                    break
                await self._send_if_needed()
            except asyncio.CancelledError:
                break
            except Exception as exc:
                logger.warning(
                    "Remote OTEL push worker error for %s: %s",
                    self.endpoint_url,
                    _format_exception_detail(exc),
                )

    async def _send_if_needed(self) -> None:
        now = time.monotonic()
        async with self._lock:
            payload = dict(self._latest_payload or {})
            payload_hash = str(self._latest_payload_hash or "")
            sequence = int(self._sequence)

        if not payload or not payload_hash or sequence <= 0:
            return

        force_heartbeat = (now - self._last_sent_monotonic) >= self.max_interval_sec
        changed = (payload_hash != self._last_sent_hash) or (sequence != self._last_sent_sequence)
        if not changed and not force_heartbeat:
            return

        envelope = {
            "schema_version": "1",
            "source": {
                "connection_key": self.source_connection_key,
                "host_name": self.source_host_name,
            },
            "source_boot_id": self.boot_id,
            "sequence": sequence,
            "payload_hash": payload_hash,
            "sent_at": _utc_now_iso(),
            "sessions_payload": {
                "schema_version": str(payload.get("schema_version", AI_SESSION_SCHEMA_VERSION)),
                "updated_at": str(payload.get("updated_at", "")),
                "timestamp": int(payload.get("timestamp", 0) or 0),
                "has_working": bool(payload.get("has_working", False)),
                "sessions": [
                    item
                    for item in payload.get("sessions", [])
                    if isinstance(item, dict)
                ],
            },
        }

        headers = {"Content-Type": "application/json"}
        if self.auth_token:
            headers["Authorization"] = f"Bearer {self.auth_token}"

        if not self._session:
            return
        try:
            async with self._session.post(self.endpoint_url, json=envelope, headers=headers) as response:
                if 200 <= response.status < 300:
                    self._last_sent_monotonic = time.monotonic()
                    self._last_sent_hash = payload_hash
                    self._last_sent_sequence = sequence
                    return
                body = await response.text()
                logger.warning(
                    "Remote OTEL push rejected: status=%s body=%s",
                    response.status,
                    body[:300],
                )
        except Exception as exc:
            logger.warning(
                "Remote OTEL push failed: endpoint=%s source=%s detail=%s",
                self.endpoint_url,
                self.source_connection_key,
                _format_exception_detail(exc),
            )


class RemoteSessionSinkStore:
    """Accepts pushed remote session snapshots and persists deterministic source map."""

    def __init__(self, sink_file_path: Path, auth_token: str = "") -> None:
        self.sink_file_path = Path(sink_file_path)
        self.auth_token = str(auth_token or "").strip()
        self._lock = asyncio.Lock()
        self._state: dict[str, Any] = {
            "schema_version": "1",
            "updated_at": _utc_now_iso(),
            "sources": {},
        }

    async def start(self) -> None:
        self.sink_file_path.parent.mkdir(parents=True, exist_ok=True)
        if self.sink_file_path.exists():
            try:
                with open(self.sink_file_path, "r") as f:
                    payload = json.load(f)
                if isinstance(payload, dict):
                    self._state = payload
            except (json.JSONDecodeError, OSError):
                pass
        logger.info("Remote OTEL sink enabled: file=%s", self.sink_file_path)

    async def stop(self) -> None:
        logger.info("Remote OTEL sink stopped")

    async def ingest(
        self,
        payload: dict[str, Any],
        authorization_header: str = "",
    ) -> tuple[bool, str, int]:
        """Validate + persist remote source payload.

        Returns: (accepted, reason, http_status)
        """
        if self.auth_token:
            token = ""
            raw = str(authorization_header or "").strip()
            if raw.lower().startswith("bearer "):
                token = raw[7:].strip()
            if token != self.auth_token:
                return False, "unauthorized", 401

        if not isinstance(payload, dict):
            return False, "invalid_payload", 400

        source = payload.get("source", {}) or {}
        if not isinstance(source, dict):
            return False, "invalid_source", 400

        source_connection_key = _normalize_connection_key(source.get("connection_key", ""))
        if source_connection_key in {"", "unknown"}:
            return False, "missing_source_connection_key", 400

        source_host = str(source.get("host_name") or "").strip() or "unknown"
        source_boot_id = str(payload.get("source_boot_id") or "").strip()
        if not source_boot_id:
            return False, "missing_source_boot_id", 400
        payload_hash = str(payload.get("payload_hash") or "").strip()

        try:
            sequence = int(payload.get("sequence", 0) or 0)
        except (TypeError, ValueError):
            return False, "invalid_sequence", 400
        if sequence <= 0:
            return False, "invalid_sequence", 400

        sessions_payload = payload.get("sessions_payload", {}) or {}
        if not isinstance(sessions_payload, dict):
            return False, "invalid_sessions_payload", 400

        sessions_raw = sessions_payload.get("sessions", [])
        sessions = [item for item in sessions_raw if isinstance(item, dict)]
        has_working = bool(sessions_payload.get("has_working", False))
        timestamp = int(sessions_payload.get("timestamp", 0) or 0)
        session_schema = str(sessions_payload.get("schema_version", ""))
        if session_schema != AI_SESSION_SCHEMA_VERSION:
            return False, "unsupported_session_schema", 409
        updated_at = str(sessions_payload.get("updated_at", ""))
        sent_at = str(payload.get("sent_at", ""))
        sent_at_epoch = _parse_iso_epoch(sent_at)
        received_at = time.time()

        async with self._lock:
            sources = self._state.get("sources")
            if not isinstance(sources, dict):
                sources = {}
                self._state["sources"] = sources

            existing = sources.get(source_connection_key, {})
            if not isinstance(existing, dict):
                existing = {}

            existing_boot = str(existing.get("source_boot_id") or "")
            existing_seq = int(existing.get("sequence", 0) or 0)
            existing_hash = str(existing.get("payload_hash") or "")
            existing_sent_epoch = _parse_iso_epoch(str(existing.get("sent_at") or ""))

            # Deterministic monotonic sequence validation.
            if source_boot_id and existing_boot and source_boot_id == existing_boot:
                if sequence < existing_seq:
                    return False, "stale_sequence", 202
                if sequence == existing_seq and payload_hash and existing_hash and payload_hash != existing_hash:
                    return False, "conflicting_same_sequence", 409
            elif source_boot_id and existing_boot and source_boot_id != existing_boot:
                # New boot epochs must restart sequence from 1 and be newer than
                # the currently tracked epoch when sent_at is available.
                if sequence != 1:
                    return False, "invalid_boot_sequence", 202
                if (
                    sent_at_epoch > 0
                    and existing_sent_epoch > 0
                    and sent_at_epoch <= existing_sent_epoch
                ):
                    return False, "stale_boot_epoch", 202

            sources[source_connection_key] = {
                "connection_key": source_connection_key,
                "host_name": source_host,
                "source_boot_id": source_boot_id,
                "sequence": sequence,
                "payload_hash": payload_hash,
                "session_schema_version": session_schema,
                "updated_at": updated_at,
                "sent_at": sent_at,
                "received_at": received_at,
                "timestamp": timestamp,
                "has_working": has_working,
                "sessions": sessions,
            }
            self._state["schema_version"] = "1"
            self._state["updated_at"] = _utc_now_iso()

            _atomic_write_json(self.sink_file_path, self._state)

        return True, "accepted", 200
