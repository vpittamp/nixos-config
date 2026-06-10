"""Dashboard worktree row cache and hydration service."""

from __future__ import annotations

import time
from typing import Any, Awaitable, Callable, Dict, List, Optional

from .dashboard_model import build_dashboard_worktree_rows


class DashboardWorktreeService:
    """Own cached dashboard worktree rows for runtime shell snapshots."""

    def __init__(
        self,
        *,
        repo_list: Callable[[], Awaitable[Dict[str, Any]]],
        load_usage_map: Callable[[], Dict[str, Dict[str, Any]]],
        flatten_runtime_windows: Callable[[Dict[str, Any]], List[Dict[str, Any]]],
        cache_fingerprint: Callable[[Dict[str, Any]], Dict[str, Any]],
        normalize_target_host: Callable[[Optional[str]], str],
        local_host_alias: Callable[[], str],
        canonical_project_name: Callable[..., str],
        get_worktree_host_profile: Callable[[str], Optional[Dict[str, Any]]],
        ttl: float = 10.0,
        timestamp: Callable[[], float] = time.time,
    ) -> None:
        self._repo_list = repo_list
        self._load_usage_map = load_usage_map
        self._flatten_runtime_windows = flatten_runtime_windows
        self._cache_fingerprint = cache_fingerprint
        self._normalize_target_host = normalize_target_host
        self._local_host_alias = local_host_alias
        self._canonical_project_name = canonical_project_name
        self._get_worktree_host_profile = get_worktree_host_profile
        self._ttl = ttl
        self._timestamp = timestamp
        self._cache: Optional[List[Dict[str, Any]]] = None
        self._cache_time: float = 0.0
        self._cache_fingerprint_value: Dict[str, Any] = {}

    def invalidate(self) -> None:
        """Invalidate cached dashboard worktree rows."""
        self._cache = None
        self._cache_time = 0.0
        self._cache_fingerprint_value = {}

    async def build_worktrees(self, runtime_snapshot: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Build a compact worktree list for the runtime shell."""
        now = self._timestamp()
        active_context = runtime_snapshot.get("active_context", {}) if isinstance(runtime_snapshot, dict) else {}
        active_qualified = str(active_context.get("qualified_name") or active_context.get("project_name") or "").strip()
        active_target_host = self._normalize_target_host(
            active_context.get("target_host") or self._local_host_alias()
        )
        cache_fingerprint = self._cache_fingerprint(runtime_snapshot)
        if (
            self._cache is not None
            and (now - self._cache_time) < self._ttl
            and self._cache_fingerprint_value == cache_fingerprint
        ):
            cached_active = next(
                (
                    str(item.get("qualified_name") or "").strip()
                    for item in self._cache
                    if isinstance(item, dict) and bool(item.get("is_active", False))
                ),
                "",
            )
            if cached_active == active_qualified:
                return [dict(item) for item in self._cache]

        repo_result = await self._repo_list()
        repositories = list(repo_result.get("repositories", []) or [])
        worktrees = build_dashboard_worktree_rows(
            runtime_snapshot=runtime_snapshot,
            repositories=repositories,
            usage_map=self._load_usage_map(),
            runtime_windows=self._flatten_runtime_windows(runtime_snapshot),
            active_target_host=active_target_host,
            canonical_project_name=self._canonical_project_name,
            get_worktree_host_profile=self._get_worktree_host_profile,
        )
        self._cache = [dict(item) for item in worktrees]
        self._cache_time = now
        self._cache_fingerprint_value = cache_fingerprint
        return worktrees
