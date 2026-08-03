"""Unit tests for dashboard git snapshot helpers."""

from __future__ import annotations

import importlib
import importlib.util
import sys
import time
from pathlib import Path
from typing import Any, Dict
from unittest.mock import AsyncMock

import pytest

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


@pytest.mark.asyncio
async def test_failed_status_probe_reports_unknown_state(tmp_path) -> None:
    # A failed/timed-out `git status` parses zero lines; that must surface as
    # 'unknown', never as a fake 'clean'.
    service = DashboardGitService()
    service.run_git_probe_command = AsyncMock(return_value=(-1, "", "timeout"))

    snapshot = await service.probe_git_snapshot(worktree_path=str(tmp_path))

    assert snapshot["state"] == "unknown"
    assert snapshot["probe_success"] is False
    assert snapshot["dirty_count"] == 0


def test_apply_failed_probe_snapshot_preserves_existing_counts() -> None:
    failed_snapshot = {
        "state": "unknown",
        "probe_success": False,
        "has_conflicts": False,
        "staged_count": 0,
        "modified_count": 0,
        "untracked_count": 0,
        "dirty_count": 0,
        "ahead": 0,
        "behind": 0,
    }
    # Session rows are rebuilt fresh on every snapshot and carry no prior git_*
    # keys, so this mirrors the real pipeline shape rather than a primed row.
    session: Dict[str, Any] = {}
    worktree = {
        "is_clean": False,
        "has_conflicts": False,
        "ahead": 1,
        "behind": 0,
        "staged_count": 1,
        "modified_count": 2,
        "untracked_count": 0,
        "dirty_count": 3,
    }

    DashboardGitService.apply_snapshot_to_session(session, failed_snapshot)
    DashboardGitService.apply_snapshot_to_worktree(worktree, failed_snapshot)

    # The failed probe publishes honest "unknown" state instead of fake-clean
    # data, but must not invent zeroed counts.
    assert session["git_state"] == "unknown"
    assert session["git_freshness"] == "stale"
    assert "git_compact" not in session
    assert "git_snapshot" not in session
    assert worktree["is_clean"] is False
    assert worktree["staged_count"] == 1
    assert worktree["modified_count"] == 2
    assert worktree["dirty_count"] == 3
    assert "git_state" not in worktree


def test_apply_missing_snapshot_to_session_clears_git_fields() -> None:
    session = {"git_state": "dirty"}

    DashboardGitService.apply_snapshot_to_session(session, None)

    assert session["git_snapshot"] == {}
    assert session["git_state"] == "unknown"
    assert session["git_compact"] == ""


@pytest.mark.asyncio
async def test_hydrate_runtime_git_state_probes_each_row_checkout_once() -> None:
    # Identity is the pane's own checkout, so two sessions sharing one checkout
    # share one probe and the current session upgrades the shared priority.
    service = DashboardGitService()
    runtime_snapshot = {"current_session_key": "session-1"}
    sessions = [
        {
            "session_key": "session-2",
            "project_name": "vpittamp/nixos-config:main",
            "checkout_path": "/tmp/nixos-config",
            "branch_label": "main",
        },
        {
            "session_key": "session-1",
            "project_name": "vpittamp/nixos-config:main",
            "checkout_path": "/tmp/nixos-config",
            "branch_label": "main",
        },
    ]
    get_snapshot = AsyncMock(return_value={
        "state": "dirty",
        "freshness": "fresh",
        "status_compact": "● 2",
        "status_tooltip": "Status: 2 modified",
        "attribution": "exact_worktree",
        "has_conflicts": False,
        "ahead": 0,
        "behind": 0,
        "staged_count": 0,
        "modified_count": 2,
        "untracked_count": 0,
        "dirty_count": 2,
    })

    await service.hydrate_runtime_git_state(
        runtime_snapshot,
        sessions,
        get_or_schedule_git_snapshot=get_snapshot,
    )

    get_snapshot.assert_awaited_once_with(
        worktree_path="/tmp/nixos-config",
        qualified_name="vpittamp/nixos-config:main",
        branch_hint="main",
        priority="current",
        attribution="exact_worktree",
    )
    assert sessions[0]["git_state"] == "dirty"
    assert sessions[1]["git_compact"] == "● 2"


@pytest.mark.asyncio
async def test_hydrate_runtime_git_state_skips_rows_without_a_checkout() -> None:
    # A row with no checkout is not inside a work tree; probing its cwd would
    # spend three git subprocesses to learn the "unknown" it already reports.
    service = DashboardGitService()
    sessions = [{
        "session_key": "session-1",
        "project_name": "global",
        "working_dir": "/tmp",
    }]
    get_snapshot = AsyncMock(return_value={})

    await service.hydrate_runtime_git_state(
        {"current_session_key": "session-1"},
        sessions,
        get_or_schedule_git_snapshot=get_snapshot,
    )

    get_snapshot.assert_not_awaited()
    assert sessions[0]["git_state"] == "unknown"


@pytest.mark.asyncio
async def test_hydrate_runtime_git_state_preserves_remote_herdr_git_fields() -> None:
    service = DashboardGitService()
    runtime_snapshot = {"current_session_key": "remote-session"}
    sessions = [{
        "session_key": "remote-session",
        "project_name": "vpittamp/nixos-config:main",
        "checkout_path": "/home/vpittamp/repos/vpittamp/nixos-config/main",
        "branch_label": "main",
        "is_remote_herdr": True,
        "git_state": "dirty",
        "git_compact": "● 6",
        "git_freshness": "fresh",
        "git_snapshot": {
            "state": "dirty",
            "dirty_count": 6,
            "status_compact": "● 6",
        },
    }]
    get_snapshot = AsyncMock(return_value={
        "state": "clean",
        "freshness": "fresh",
        "status_compact": "",
        "status_tooltip": "Status: clean",
        "attribution": "exact_worktree",
        "dirty_count": 0,
    })

    await service.hydrate_runtime_git_state(
        runtime_snapshot,
        sessions,
        get_or_schedule_git_snapshot=get_snapshot,
    )

    # The remote row's checkout only exists on the remote host, so it is never
    # probed locally and keeps the git fields the proxy supplied.
    get_snapshot.assert_not_awaited()
    assert sessions[0]["git_state"] == "dirty"
    assert sessions[0]["git_compact"] == "● 6"
    assert sessions[0]["git_snapshot"]["dirty_count"] == 6


@pytest.mark.asyncio
async def test_refresh_git_snapshot_notifies_only_after_cached_fingerprint_changes() -> None:
    service = DashboardGitService()
    base_snapshot = {
        "available": True,
        "worktree_path": "/tmp/nixos-config",
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
        "repo_root": "/tmp/nixos-config",
        "snapshot_at": int(time.time()),
        "source": "git_probe",
        "probe_success": True,
    }
    dirty_snapshot = dict(
        base_snapshot,
        state="dirty",
        modified_count=1,
        dirty_count=1,
    )
    service.probe_git_snapshot = AsyncMock(side_effect=[
        base_snapshot,
        dict(base_snapshot),
        dirty_snapshot,
    ])
    notifications: list[str] = []

    async def notify(event_type: str) -> None:
        notifications.append(event_type)

    await service.refresh_git_snapshot(
        worktree_path="/tmp/nixos-config",
        notify=True,
        notify_state_change=notify,
    )
    await service.refresh_git_snapshot(
        worktree_path="/tmp/nixos-config",
        notify=True,
        notify_state_change=notify,
    )
    await service.refresh_git_snapshot(
        worktree_path="/tmp/nixos-config",
        notify=True,
        notify_state_change=notify,
    )

    assert notifications == ["ai_session_git_changed"]


@pytest.mark.asyncio
async def test_hydrate_probes_agentless_herdr_space_checkout() -> None:
    # A space whose panes carry no agent produces no session rows. Walking only
    # sessions left it with no git chip at all (live: space wA). It owns a
    # checkout like any session, so it must be probed too.
    service = DashboardGitService()
    runtime_snapshot = {
        "current_session_key": "",
        "herdr": {
            "spaces": [
                {
                    "workspace_id": "wA",
                    "checkout_path": "/tmp/agentless-worktree",
                    "branch_label": "feat/no-agent",
                    "project_name": "acme/repo:feat/no-agent",
                }
            ]
        },
    }
    get_snapshot = AsyncMock(return_value={
        "state": "dirty",
        "status_compact": "● 2",
        "freshness": "fresh",
        "attribution": "exact_worktree",
    })

    await service.hydrate_runtime_git_state(
        runtime_snapshot,
        [],
        get_or_schedule_git_snapshot=get_snapshot,
    )

    get_snapshot.assert_awaited_once()
    assert get_snapshot.await_args.kwargs["worktree_path"] == "/tmp/agentless-worktree"
    assert get_snapshot.await_args.kwargs["branch_hint"] == "feat/no-agent"
    space = runtime_snapshot["herdr"]["spaces"][0]
    assert space["git_state"] == "dirty"
    assert space["git_compact"] == "● 2"


@pytest.mark.asyncio
async def test_hydrate_does_not_override_space_git_inherited_from_sessions() -> None:
    # build_spaces copies git fields down from a space's own sessions; that
    # inherited value is more specific than a re-probe of the space checkout.
    service = DashboardGitService()
    runtime_snapshot = {
        "current_session_key": "",
        "herdr": {
            "spaces": [
                {
                    "workspace_id": "wB",
                    "checkout_path": "/tmp/has-agent",
                    "git_state": "clean",
                }
            ]
        },
    }
    get_snapshot = AsyncMock(return_value={"state": "dirty", "status_compact": "● 9"})

    await service.hydrate_runtime_git_state(
        runtime_snapshot,
        [],
        get_or_schedule_git_snapshot=get_snapshot,
    )

    assert runtime_snapshot["herdr"]["spaces"][0]["git_state"] == "clean"
