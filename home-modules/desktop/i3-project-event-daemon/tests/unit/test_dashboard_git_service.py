"""Unit tests for dashboard git snapshot helpers."""

from __future__ import annotations

import importlib
import importlib.util
import sys
import time
from pathlib import Path


PACKAGE_ROOT = Path(__file__).parent.parent.parent


if "i3_project_daemon" not in sys.modules:
    package_spec = importlib.util.spec_from_file_location(
        "i3_project_daemon",
        PACKAGE_ROOT / "__init__.py",
        submodule_search_locations=[str(PACKAGE_ROOT)],
    )
    package_module = importlib.util.module_from_spec(package_spec)
    sys.modules["i3_project_daemon"] = package_module
    assert package_spec.loader is not None
    package_spec.loader.exec_module(package_module)


dashboard_git_service_module = importlib.import_module("i3_project_daemon.services.dashboard_git_service")

DashboardGitService = dashboard_git_service_module.DashboardGitService


def test_parse_ahead_behind_and_snapshot_state() -> None:
    assert DashboardGitService.parse_ahead_behind("main...origin/main [ahead 2, behind 1]") == (2, 1)
    assert DashboardGitService.parse_ahead_behind("main") == (0, 0)
    assert DashboardGitService.snapshot_state(has_conflicts=True, dirty_count=0) == "conflicted"
    assert DashboardGitService.snapshot_state(has_conflicts=False, dirty_count=2) == "dirty"
    assert DashboardGitService.snapshot_state(has_conflicts=False, dirty_count=0) == "clean"


def test_decorate_cached_snapshot_adds_freshness_and_status_strings() -> None:
    service = DashboardGitService(ttl_current=10)
    snapshot = {
        "qualified_name": "vpittamp/nixos-config:main",
        "branch": "main",
        "head_oid_short": "abc1234",
        "state": "dirty",
        "dirty_count": 3,
        "staged_count": 1,
        "modified_count": 1,
        "untracked_count": 1,
        "ahead": 2,
        "behind": 1,
        "snapshot_at": int(time.time()),
        "probe_success": True,
    }

    decorated = service.decorate_cached_snapshot(
        snapshot,
        priority="current",
        attribution="exact_worktree",
    )

    assert decorated["freshness"] == "fresh"
    assert decorated["status_compact"] == "● 3 ↑2 ↓1"
    assert decorated["status_label"] == "Dirty"
    assert "Branch: main @ abc1234" in decorated["status_tooltip"]
    assert "Status: 1 staged, 1 modified, 1 untracked" in decorated["status_tooltip"]
    assert "Sync: 2 to push, 1 to pull" in decorated["status_tooltip"]
    assert decorated["show_chip"] is True


def test_cache_fingerprint_uses_stable_git_state_fields() -> None:
    base = {
        "qualified_name": "vpittamp/nixos-config:main",
        "branch": "main",
        "head_oid_short": "abc1234",
        "state": "clean",
        "has_conflicts": False,
        "staged_count": 0,
        "modified_count": 0,
        "untracked_count": 0,
        "dirty_count": 0,
        "ahead": 0,
        "behind": 0,
        "available": True,
        "probe_success": True,
        "ignored_runtime_field": "one",
    }
    same = dict(base, ignored_runtime_field="two")
    changed = dict(base, dirty_count=1, state="dirty")

    assert DashboardGitService.cache_fingerprint(base) == DashboardGitService.cache_fingerprint(same)
    assert DashboardGitService.cache_fingerprint(base) != DashboardGitService.cache_fingerprint(changed)


def test_apply_snapshot_to_session_and_worktree() -> None:
    snapshot = {
        "state": "dirty",
        "freshness": "fresh",
        "status_compact": "● 1",
        "status_tooltip": "Status: 1 modified",
        "attribution": "exact_worktree",
        "has_conflicts": False,
        "ahead": 2,
        "behind": 1,
        "staged_count": 0,
        "modified_count": 1,
        "untracked_count": 0,
        "dirty_count": 1,
    }
    session = {}
    worktree = {"is_clean": True}

    DashboardGitService.apply_snapshot_to_session(session, snapshot)
    DashboardGitService.apply_snapshot_to_worktree(worktree, snapshot)

    assert session["git_state"] == "dirty"
    assert session["git_compact"] == "● 1"
    assert session["git_attribution"] == "exact_worktree"
    assert worktree["git_state"] == "dirty"
    assert worktree["is_clean"] is False
    assert worktree["ahead"] == 2
    assert worktree["dirty_count"] == 1


def test_apply_missing_snapshot_to_session_clears_git_fields() -> None:
    session = {"git_state": "dirty"}

    DashboardGitService.apply_snapshot_to_session(session, None)

    assert session["git_snapshot"] == {}
    assert session["git_state"] == "unknown"
    assert session["git_compact"] == ""
