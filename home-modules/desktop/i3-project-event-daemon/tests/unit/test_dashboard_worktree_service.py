"""Unit tests for dashboard worktree row cache service."""

from __future__ import annotations

from typing import Any, Dict, List
from unittest.mock import AsyncMock

import pytest

from i3_project_daemon.services.dashboard_worktree_service import DashboardWorktreeService


def make_worktree(branch: str, **overrides: Any) -> Dict[str, Any]:
    data = {
        "branch": branch,
        "path": f"/tmp/vpittamp/nixos-config/{branch}",
        "is_main": branch == "main",
        "is_clean": True,
        "is_stale": False,
        "has_conflicts": False,
        "ahead": 0,
        "behind": 0,
        "staged_count": 0,
        "modified_count": 0,
        "untracked_count": 0,
        "last_commit_message": f"commit for {branch}",
    }
    data.update(overrides)
    return data


def make_service(
    *,
    repo_list: AsyncMock,
    usage_map: Dict[str, Dict[str, Any]] | None = None,
    runtime_windows: List[Dict[str, Any]] | None = None,
    fingerprint: Dict[str, Any] | None = None,
    now: float = 100.0,
) -> DashboardWorktreeService:
    return DashboardWorktreeService(
        repo_list=repo_list,
        load_usage_map=lambda: dict(usage_map or {}),
        flatten_runtime_windows=lambda _snapshot: list(runtime_windows or []),
        cache_fingerprint=lambda _snapshot: dict(fingerprint or {"repos": (1, 1), "usage": (1, 1)}),
        normalize_target_host=lambda value: str(value or "local").strip(),
        local_host_alias=lambda: "local",
        canonical_project_name=lambda value, **_kwargs: str(value or "").strip(),
        get_worktree_host_profile=lambda _qualified_name: None,
        ttl=10.0,
        timestamp=lambda: now,
    )


@pytest.mark.asyncio
async def test_build_worktrees_reuses_fresh_cache_for_same_active_context() -> None:
    repo_list = AsyncMock(return_value={
        "repositories": [{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [make_worktree("main")],
        }],
    })
    service = make_service(repo_list=repo_list)
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "target_host": "local",
        },
        "tracked_windows": [],
    }

    first = await service.build_worktrees(runtime_snapshot)
    second = await service.build_worktrees(runtime_snapshot)

    repo_list.assert_awaited_once()
    assert first == second
    assert first is not second
    assert second[0]["qualified_name"] == "vpittamp/nixos-config:main"


@pytest.mark.asyncio
async def test_build_worktrees_rebuilds_when_cached_active_context_is_stale() -> None:
    repo_list = AsyncMock(return_value={
        "repositories": [{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [make_worktree("main")],
        }],
    })
    service = make_service(repo_list=repo_list)
    service._cache = [{
        "qualified_name": "PittampalliOrg/stacks:main",
        "is_active": True,
    }]
    service._cache_time = 100.0
    service._cache_fingerprint_value = {"repos": (1, 1), "usage": (1, 1)}

    worktrees = await service.build_worktrees({
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "target_host": "local",
        },
        "tracked_windows": [],
    })

    repo_list.assert_awaited_once()
    assert len(worktrees) == 1
    assert worktrees[0]["qualified_name"] == "vpittamp/nixos-config:main"
    assert worktrees[0]["is_active"] is True


@pytest.mark.asyncio
async def test_invalidate_forces_next_build_to_fetch_repositories() -> None:
    repo_list = AsyncMock(return_value={
        "repositories": [{
            "account": "vpittamp",
            "name": "nixos-config",
            "worktrees": [make_worktree("main")],
        }],
    })
    service = make_service(repo_list=repo_list)
    runtime_snapshot = {
        "active_context": {
            "qualified_name": "vpittamp/nixos-config:main",
            "target_host": "local",
        },
        "tracked_windows": [],
    }

    await service.build_worktrees(runtime_snapshot)
    service.invalidate()
    await service.build_worktrees(runtime_snapshot)

    assert repo_list.await_count == 2
