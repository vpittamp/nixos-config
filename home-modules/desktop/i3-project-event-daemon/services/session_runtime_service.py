"""Herdr session runtime loading and reconciliation service."""

from __future__ import annotations

import copy
from typing import Any, Awaitable, Callable, Dict, List, Set


class SessionRuntimeService:
    """Own session row cloning/sorting and stale bridge reconciliation."""

    def __init__(
        self,
        *,
        stale_remote_bridge_windows: Callable[[Dict[str, Any], List[Dict[str, Any]]], List[Dict[str, Any]]],
        prune_invalid_overrides: Callable[..., Dict[str, Any]],
        close_managed_window: Callable[[int], Awaitable[bool]],
        remove_window: Callable[[int], Awaitable[Any]],
        invalidate_window_tree_cache: Callable[[], None],
    ) -> None:
        self._stale_remote_bridge_windows = stale_remote_bridge_windows
        self._prune_invalid_overrides = prune_invalid_overrides
        self._close_managed_window = close_managed_window
        self._remove_window = remove_window
        self._invalidate_window_tree_cache = invalidate_window_tree_cache

    @staticmethod
    def stale_bridge_close_reasons() -> Set[str]:
        """Return stale bridge reasons that are safe to close automatically."""
        return {
            "missing_remote_session",
            "remote_surface_mismatch",
            "remote_session_mismatch",
            "tmux_server_key_mismatch",
            "tmux_session_mismatch",
            "tmux_window_mismatch",
            "tmux_pane_mismatch",
        }

    @staticmethod
    def load_session_items(runtime_snapshot: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Return Herdr-native AI session items for an existing runtime snapshot."""
        sessions_raw = runtime_snapshot.get("sessions", [])
        if not isinstance(sessions_raw, list):
            return []
        sessions = [copy.deepcopy(session) for session in sessions_raw if isinstance(session, dict)]
        sessions.sort(key=lambda session: (
            0 if bool(session.get("focused", False)) else 1,
            str(session.get("workspace_name") or session.get("workspace_id") or ""),
            str(session.get("tab_title") or session.get("tab_id") or ""),
            str(session.get("agent") or session.get("tool") or ""),
            str(session.get("pane_id") or session.get("session_key") or ""),
        ))
        return sessions

    async def reconcile_runtime_state(
        self,
        runtime_snapshot: Dict[str, Any],
        sessions: List[Dict[str, Any]],
        *,
        close_windows: bool,
    ) -> Dict[str, Any]:
        """Prune stale bridge windows and clear overrides that no longer resolve."""
        tracked_windows = list(runtime_snapshot.get("tracked_windows", []) or [])
        stale_bridges = self._stale_remote_bridge_windows(runtime_snapshot, sessions)
        live_window_ids = {
            int(window.get("window_id") or window.get("id") or 0)
            for window in tracked_windows
            if isinstance(window, dict) and int(window.get("window_id") or window.get("id") or 0) > 0
        }
        live_session_keys = {
            str(session.get("session_key") or "").strip()
            for session in sessions
            if isinstance(session, dict) and str(session.get("session_key") or "").strip()
        }
        stale_window_ids = {
            int(item.get("window_id") or 0)
            for item in stale_bridges
            if int(item.get("window_id") or 0) > 0
        }

        focus_cleanup = self._prune_invalid_overrides(
            live_session_keys=live_session_keys,
            live_window_ids=live_window_ids,
            stale_window_ids=stale_window_ids,
        )

        cleaned_windows: List[Dict[str, Any]] = []
        close_reasons = self.stale_bridge_close_reasons()
        if close_windows:
            for item in stale_bridges:
                window_id = int(item.get("window_id") or 0)
                if window_id <= 0:
                    continue
                reason = str(item.get("reason") or "").strip()
                if reason not in close_reasons:
                    continue
                closed = await self._close_managed_window(window_id)
                await self._remove_window(window_id)
                cleaned_windows.append({
                    "window_id": window_id,
                    "closed": bool(closed),
                    "reason": reason,
                })
            if cleaned_windows:
                self._invalidate_window_tree_cache()

        return {
            "stale_bridge_count": len(stale_bridges),
            "stale_bridges": stale_bridges,
            "cleaned_window_count": len(cleaned_windows),
            "cleaned_windows": cleaned_windows,
            "cleared_session_override": bool(focus_cleanup.get("cleared_session_override", False)),
            "cleared_window_override": bool(focus_cleanup.get("cleared_window_override", False)),
        }
