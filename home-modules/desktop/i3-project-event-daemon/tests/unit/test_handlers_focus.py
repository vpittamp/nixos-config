"""Regression tests: sway focus tracking on workspace::focus / window::focus."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

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


handlers_module = importlib.import_module("i3_project_daemon.handlers")


def _state_manager(**state_fields):
    fields = {"currently_focused_window": 699, "currently_focused_workspace": "33"}
    fields.update(state_fields)
    state = SimpleNamespace(**fields)
    return SimpleNamespace(
        state=state,
        update_window=AsyncMock(),
        increment_error_count=AsyncMock(),
        get_active_project=AsyncMock(return_value=None),
        get_window=AsyncMock(return_value=None),
        focus_tracker=None,
    )


def _ipc_server():
    return SimpleNamespace(
        invalidate_window_tree_cache=Mock(),
        notify_state_change=AsyncMock(),
        refresh_focus_from_sway=AsyncMock(return_value={"refreshed": True}),
    )


def _workspace(name: str, focused_leaf_id: int | None):
    leaf = SimpleNamespace(id=focused_leaf_id, focused=True) if focused_leaf_id else None
    return SimpleNamespace(
        name=name,
        num=int(name),
        ipc_data={"output": "DP-2", "visible": True},
        find_focused=lambda: leaf,
    )


@pytest.mark.asyncio
async def test_workspace_focus_on_empty_workspace_clears_focused_window():
    # The live bug: a transient 1Password window on empty workspace 22 closed,
    # sway focused the bare workspace (no window::focus follows), and the daemon
    # kept reporting the herdr window (699) — and its pane — as focused.
    state_manager = _state_manager()
    ipc_server = _ipc_server()

    await handlers_module.on_workspace_focus(
        conn=None,
        event=SimpleNamespace(current=_workspace("22", None), old=None),
        state_manager=state_manager,
        ipc_server=ipc_server,
    )

    assert state_manager.state.currently_focused_window == 0
    assert state_manager.state.currently_focused_workspace == "22"
    ipc_server.refresh_focus_from_sway.assert_awaited_once()
    ipc_server.notify_state_change.assert_awaited_once_with("workspace::focus")
    ipc_server.invalidate_window_tree_cache.assert_not_called()


@pytest.mark.asyncio
async def test_workspace_focus_records_focused_leaf_of_target_workspace():
    state_manager = _state_manager()
    ipc_server = _ipc_server()

    await handlers_module.on_workspace_focus(
        conn=None,
        event=SimpleNamespace(current=_workspace("15", 679), old=None),
        state_manager=state_manager,
        ipc_server=ipc_server,
    )

    assert state_manager.state.currently_focused_window == 679
    assert state_manager.state.currently_focused_workspace == "15"
    ipc_server.refresh_focus_from_sway.assert_awaited_once()


def test_sync_focus_leaves_state_alone_when_subtree_is_unreadable():
    state_manager = _state_manager()

    def boom():
        raise RuntimeError("no tree")

    workspace = SimpleNamespace(name="22", find_focused=boom)
    result = handlers_module.sync_focused_window_from_workspace_event(state_manager, workspace)

    assert result is None
    assert state_manager.state.currently_focused_window == 699
    # The workspace name is known from the event header even if the subtree is not.
    assert state_manager.state.currently_focused_workspace == "22"


@pytest.mark.asyncio
async def test_window_focus_records_workspace_and_refreshes_focus_before_notify():
    state_manager = _state_manager(currently_focused_window=None, currently_focused_workspace=None)
    calls: list[str] = []
    ipc_server = SimpleNamespace(
        invalidate_window_tree_cache=Mock(),
        notify_state_change=AsyncMock(side_effect=lambda *_: calls.append("notify")),
        refresh_focus_from_sway=AsyncMock(side_effect=lambda: calls.append("refresh")),
    )
    workspace = SimpleNamespace(name="33", num=33)
    container = SimpleNamespace(
        id=699,
        app_id="com.herdr.ryzen",
        window_class=None,
        window_instance=None,
        name="herdr:ryzen",
        workspace=lambda: workspace,
        ipc_data={},
    )

    await handlers_module.on_window_focus(
        conn=None,
        event=SimpleNamespace(container=container),
        state_manager=state_manager,
        event_buffer=None,
        ipc_server=ipc_server,
    )

    assert state_manager.state.currently_focused_window == 699
    assert state_manager.state.currently_focused_workspace == "33"
    assert calls == ["refresh", "notify"]
