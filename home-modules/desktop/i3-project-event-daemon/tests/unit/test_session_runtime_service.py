"""Unit tests for Herdr session runtime service."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

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


runtime_module = importlib.import_module("i3_project_daemon.services.session_runtime_service")

SessionRuntimeService = runtime_module.SessionRuntimeService


def _service(*, stale_bridges=None, close_window=None, remove_window=None) -> SessionRuntimeService:
    return SessionRuntimeService(
        stale_remote_bridge_windows=MagicMock(return_value=list(stale_bridges or [])),
        prune_invalid_overrides=MagicMock(return_value={
            "cleared_session_override": False,
            "cleared_window_override": False,
        }),
        close_managed_window=close_window or AsyncMock(return_value=True),
        remove_window=remove_window or AsyncMock(return_value=None),
        invalidate_window_tree_cache=MagicMock(),
    )


def test_load_session_items_deep_copies_and_sorts_focused_first() -> None:
    runtime_snapshot = {
        "sessions": [
            {"session_key": "b", "focused": False, "workspace_name": "2"},
            {"session_key": "a", "focused": True, "workspace_name": "1"},
        ],
    }

    result = SessionRuntimeService.load_session_items(runtime_snapshot)

    assert [item["session_key"] for item in result] == ["a", "b"]
    assert result[0] is not runtime_snapshot["sessions"][1]


@pytest.mark.asyncio
async def test_reconcile_runtime_closes_safe_stale_bridge_reason() -> None:
    close_window = AsyncMock(return_value=True)
    remove_window = AsyncMock(return_value=None)
    service = _service(
        stale_bridges=[{"window_id": 101, "reason": "missing_remote_session"}],
        close_window=close_window,
        remove_window=remove_window,
    )
    runtime_snapshot = {"tracked_windows": [{"window_id": 101}]}

    result = await service.reconcile_runtime_state(runtime_snapshot, [], close_windows=True)

    assert result["stale_bridge_count"] == 1
    assert result["cleaned_window_count"] == 1
    assert result["cleaned_windows"] == [
        {"window_id": 101, "closed": True, "reason": "missing_remote_session"}
    ]
    close_window.assert_awaited_once_with(101)
    remove_window.assert_awaited_once_with(101)
    service._invalidate_window_tree_cache.assert_called_once()


@pytest.mark.asyncio
async def test_reconcile_runtime_does_not_close_stale_remote_source() -> None:
    close_window = AsyncMock(return_value=True)
    remove_window = AsyncMock(return_value=None)
    service = _service(
        stale_bridges=[{"window_id": 202, "reason": "stale_remote_source"}],
        close_window=close_window,
        remove_window=remove_window,
    )
    runtime_snapshot = {"tracked_windows": [{"window_id": 202}]}

    result = await service.reconcile_runtime_state(runtime_snapshot, [], close_windows=True)

    assert result["stale_bridge_count"] == 1
    assert result["cleaned_window_count"] == 0
    close_window.assert_not_awaited()
    remove_window.assert_not_awaited()
    service._invalidate_window_tree_cache.assert_not_called()
