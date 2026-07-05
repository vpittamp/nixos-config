"""Dashboard snapshot and event orchestration service."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any, Awaitable, Callable, Dict, List, Optional, Set, Tuple

from .dashboard_model import (
    DASHBOARD_EVENT_SCHEMA_VERSION,
    DASHBOARD_SCHEMA_VERSION,
    advance_dashboard_event_state_for_batch,
    build_dashboard_snapshot_payload,
    dashboard_event_notification,
    dashboard_event_payload_from_snapshot,
    dashboard_invalidated_payload,
    validate_dashboard_payload,
)

logger = logging.getLogger(__name__)


class DashboardService:
    """Own daemon dashboard generations, snapshots, validation, and events."""

    def __init__(
        self,
        *,
        runtime_loader: Callable[..., Awaitable[Tuple[Dict[str, Any], List[Dict[str, Any]], Dict[str, Any]]]],
        display_snapshot: Callable[[], Awaitable[Dict[str, Any]]],
        build_projects: Callable[[Dict[str, Any], List[Dict[str, Any]]], List[Dict[str, Any]]],
        build_worktrees: Callable[[Dict[str, Any]], Awaitable[List[Dict[str, Any]]]],
        build_focus_state: Callable[..., Dict[str, Any]],
        build_herdr_spaces: Callable[[Dict[str, Any], List[Dict[str, Any]]], List[Dict[str, Any]]],
        list_launches: Callable[..., List[Dict[str, Any]]],
        invalidate_worktree_cache: Callable[[], None],
        build_lightweight_focus_state: Optional[Callable[..., Dict[str, Any]]] = None,
        timestamp: Callable[[], float] = time.time,
        schema_version: str = DASHBOARD_SCHEMA_VERSION,
        event_schema_version: str = DASHBOARD_EVENT_SCHEMA_VERSION,
    ) -> None:
        self._runtime_loader = runtime_loader
        self._display_snapshot = display_snapshot
        self._build_projects = build_projects
        self._build_worktrees = build_worktrees
        self._build_focus_state = build_focus_state
        self._build_lightweight_focus_state = build_lightweight_focus_state
        self._build_herdr_spaces = build_herdr_spaces
        self._list_launches = list_launches
        self._invalidate_worktree_cache = invalidate_worktree_cache
        self._timestamp = timestamp
        self.schema_version = schema_version
        self.event_schema_version = event_schema_version
        self.subscribers: Set[asyncio.StreamWriter] = set()
        self.snapshot_version = 0
        self.session_generation = 0
        self.display_generation = 0
        self.focus_generation = 0
        self._last_snapshot: Dict[str, Any] = {}

    def subscribe(self, writer: asyncio.StreamWriter) -> Dict[str, Any]:
        """Subscribe a client to typed dashboard events."""
        self.subscribers.add(writer)
        subscriber_count = len(self.subscribers)
        logger.info("Client subscribed to dashboard events (total: %s)", subscriber_count)
        return {
            "subscribed": True,
            "subscriber_count": subscriber_count,
        }

    def discard_subscriber(self, writer: asyncio.StreamWriter) -> None:
        """Remove a client from dashboard event subscribers."""
        self.subscribers.discard(writer)

    async def snapshot(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return the daemon-owned dashboard payload consumed by QuickShell."""
        runtime_snapshot, sessions, _cleanup = await self._runtime_loader(params or {})
        display_snapshot = await self._display_snapshot()
        herdr_snapshot = runtime_snapshot.get("herdr", {})
        if not isinstance(herdr_snapshot, dict):
            herdr_snapshot = {}

        projects = self._build_projects(runtime_snapshot, sessions)
        worktrees = list(runtime_snapshot.get("dashboard_worktrees", []) or [])
        if not worktrees:
            worktrees = await self._build_worktrees(runtime_snapshot)
        focus_state = self._build_focus_state(
            runtime_snapshot,
            sessions,
            generation=int(self.focus_generation or self.snapshot_version or 0),
        )
        sessions = self._sessions_with_authoritative_focus(
            sessions,
            current_session_key=str(focus_state.get("current_session_key") or "").strip(),
        )
        payload = build_dashboard_snapshot_payload(
            runtime_snapshot=runtime_snapshot,
            display_snapshot=display_snapshot,
            projects=projects,
            worktrees=worktrees,
            sessions=sessions,
            focus_state=focus_state,
            herdr_spaces=self._build_herdr_spaces(
                herdr_snapshot,
                sessions,
            ),
            launches=self._list_launches(limit=12),
            snapshot_version=self.snapshot_version,
            session_generation=self.session_generation,
            display_generation=self.display_generation,
            focus_generation=self.focus_generation,
            timestamp=int(self._timestamp()),
            schema_version=self.schema_version,
        )
        self._last_snapshot = payload
        return payload

    @staticmethod
    def _sessions_with_authoritative_focus(
        sessions: List[Dict[str, Any]],
        *,
        current_session_key: str,
    ) -> List[Dict[str, Any]]:
        current_key = str(current_session_key or "").strip()
        normalized: List[Dict[str, Any]] = []
        for row in sessions:
            if not isinstance(row, dict):
                continue
            session = dict(row)
            is_current = bool(
                current_key
                and str(session.get("session_key") or "").strip() == current_key
            )
            session["is_current_window"] = is_current
            if str(session.get("source") or "").strip() == "herdr":
                session["focused"] = is_current
                session["pane_active"] = is_current
                session["window_active"] = is_current
            normalized.append(session)
        return normalized

    async def validate(self, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Return dashboard invariant status without exposing validation internals."""
        payload = await self.snapshot(params or {})
        invariants = payload.get("dashboard_invariants")
        if not isinstance(invariants, dict):
            invariants = validate_dashboard_payload(
                payload,
                schema_version=self.schema_version,
            )
        focus_state = payload.get("focus_state")
        focus_schema_version = (
            str(focus_state.get("schema_version") or "")
            if isinstance(focus_state, dict)
            else ""
        )
        return {
            "success": bool(invariants.get("ok", False)),
            "schema_version": str(payload.get("schema_version") or ""),
            "focus_schema_version": focus_schema_version,
            "generation": int(payload.get("generation") or 0),
            "snapshot_version": int(payload.get("snapshot_version") or 0),
            "session_generation": int(payload.get("session_generation") or 0),
            "display_generation": int(payload.get("display_generation") or 0),
            "focus_generation": int(payload.get("focus_generation") or 0),
            "issues": list(invariants.get("issues", []) or []),
            "warnings": list(invariants.get("warnings", []) or []),
        }

    async def event_payload(self, changed_keys: List[str]) -> Dict[str, Any]:
        """Build a partial dashboard payload for a typed state-change event."""
        normalized_changed_keys = [str(key or "").strip() for key in changed_keys]
        if normalized_changed_keys == ["focus_state"] and self._build_lightweight_focus_state:
            snapshot = self._last_snapshot if isinstance(self._last_snapshot, dict) else {}
            base_focus_state = (
                snapshot.get("focus_state")
                if isinstance(snapshot.get("focus_state"), dict)
                else {}
            )
            focus_state = self._build_lightweight_focus_state(
                generation=int(self.focus_generation or self.snapshot_version or 0),
                base_focus_state=base_focus_state,
            )
            active_ai_sessions: List[Dict[str, Any]] = []
            active_session: Dict[str, Any] = {}
            current_session_key = str(focus_state.get("current_session_key") or "").strip()
            for row in snapshot.get("active_ai_sessions", []) or []:
                if not isinstance(row, dict):
                    continue
                session = dict(row)
                is_current = bool(
                    current_session_key
                    and str(session.get("session_key") or "").strip() == current_session_key
                )
                session["is_current_window"] = is_current
                if str(session.get("source") or "").strip() == "herdr":
                    session["focused"] = is_current
                    session["pane_active"] = is_current
                    session["window_active"] = is_current
                if is_current:
                    active_session = dict(session)
                active_ai_sessions.append(session)
            if active_session:
                focus_state = dict(focus_state)
                focus_state["current_herdr_pane_id"] = str(active_session.get("pane_id") or "").strip()
                focus_state["current_herdr_host"] = str(
                    active_session.get("host_name")
                    or active_session.get("herdr_host")
                    or ""
                ).strip()
                focus_state["active_session"] = {
                    "session_key": str(active_session.get("session_key") or "").strip(),
                    "herdr_session": str(active_session.get("herdr_session") or "").strip(),
                    "workspace_id": str(active_session.get("workspace_id") or "").strip(),
                    "tab_id": str(active_session.get("tab_id") or "").strip(),
                    "pane_id": str(active_session.get("pane_id") or "").strip(),
                    "terminal_id": str(active_session.get("terminal_id") or "").strip(),
                    "agent": str(active_session.get("agent") or active_session.get("tool") or "").strip(),
                    "agent_status": str(active_session.get("agent_status") or "").strip(),
                    "agent_status_state": str(active_session.get("agent_status_state") or "").strip(),
                    "focused": bool(active_session.get("focused", False)),
                    "window_id": int(active_session.get("window_id") or 0),
                    "project_name": str(
                        active_session.get("project_name")
                        or active_session.get("project")
                        or ""
                    ).strip(),
                    "execution_mode": str(active_session.get("execution_mode") or "").strip(),
                    "connection_key": str(active_session.get("connection_key") or "").strip(),
                    "focus_connection_key": str(active_session.get("focus_connection_key") or "").strip(),
                    "host_name": str(active_session.get("host_name") or "").strip(),
                }
            payload = {
                "status": str(snapshot.get("status") or "ok"),
                "schema_version": str(snapshot.get("schema_version") or self.schema_version),
                "timestamp": int(self._timestamp()),
                "generation": self.snapshot_version,
                "snapshot_version": self.snapshot_version,
                "session_generation": self.session_generation,
                "display_generation": self.display_generation,
                "focus_generation": self.focus_generation,
                "focus_state": focus_state,
            }
            if active_ai_sessions:
                payload["active_ai_sessions"] = active_ai_sessions
            return payload
        git_bearing_keys = {"active_ai_sessions", "herdr", "worktrees"}
        skip_git_hydration = not any(
            key in git_bearing_keys for key in normalized_changed_keys
        )
        snapshot = await self.snapshot({"skip_git_hydration": skip_git_hydration})
        return dashboard_event_payload_from_snapshot(
            snapshot,
            changed_keys,
            schema_version=self.schema_version,
        )

    async def notify_state_change(self, event_type="dashboard_invalidated") -> None:
        """Notify subscribed clients with a typed dashboard event.

        `event_type` may be a single event string or an iterable of event types
        coalesced into one notification. For a batch, the emitted delta is the
        lossless union of every event's changed keys and generation bumps, so a
        membership change (e.g. window::close / workspace::empty) batched with a
        focus switch still ships `outputs` instead of being downgraded to a
        focus-only delta.
        """
        if isinstance(event_type, str):
            event_types = [event_type]
        else:
            event_types = [str(item) for item in event_type] or ["dashboard_invalidated"]
        event_state = advance_dashboard_event_state_for_batch(
            event_types=event_types,
            snapshot_version=self.snapshot_version,
            session_generation=self.session_generation,
            display_generation=self.display_generation,
            focus_generation=self.focus_generation,
        )
        self.snapshot_version = int(event_state.get("snapshot_version") or 0)
        self.session_generation = int(event_state.get("session_generation") or 0)
        self.display_generation = int(event_state.get("display_generation") or 0)
        self.focus_generation = int(event_state.get("focus_generation") or 0)
        normalized_type = str(event_state.get("type") or "dashboard_invalidated")
        changed_keys = list(event_state.get("changed_keys", []) or [])
        if bool(event_state.get("invalidate_worktree_cache", False)):
            self._invalidate_worktree_cache()

        if not self.subscribers:
            return

        try:
            event_payload = await self.event_payload(changed_keys)
        except Exception as exc:
            logger.warning("Failed to build dashboard event payload for %s: %s", normalized_type, exc)
            event_state = dict(event_state)
            event_state["event_type"] = "dashboard.invalidated"
            changed_keys = ["dashboard"]
            event_state["changed_keys"] = changed_keys
            event_payload = dashboard_invalidated_payload(
                error=exc,
                snapshot_version=self.snapshot_version,
                session_generation=self.session_generation,
                display_generation=self.display_generation,
                focus_generation=self.focus_generation,
                schema_version=self.schema_version,
            )

        notification = json.dumps(dashboard_event_notification(
            state=event_state,
            payload=event_payload,
            timestamp=self._timestamp(),
            event_schema_version=self.event_schema_version,
        ))

        dead_clients = set()
        for writer in list(self.subscribers):
            try:
                writer.write((notification + "\n").encode())
                transport = getattr(writer, "transport", None)
                get_buffer_size = getattr(transport, "get_write_buffer_size", None)
                if callable(get_buffer_size) and int(get_buffer_size() or 0) > 1_000_000:
                    logger.warning("Dropping slow dashboard event subscriber with oversized write buffer")
                    dead_clients.add(writer)
            except (ConnectionResetError, BrokenPipeError, ConnectionError):
                dead_clients.add(writer)
            except Exception as exc:
                logger.warning("Error notifying dashboard event subscriber: %s", exc)
                dead_clients.add(writer)

        self.subscribers -= dead_clients
        if dead_clients:
            logger.debug("Removed %s dead dashboard event subscribers", len(dead_clients))
