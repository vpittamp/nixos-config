"""Regression tests for managed window move handling."""

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


@pytest.mark.asyncio
async def test_window_move_without_workspace_preserves_transient_binding():
    state_manager = SimpleNamespace(
        update_window=AsyncMock(),
        increment_error_count=AsyncMock(),
        get_active_project=AsyncMock(return_value="vpittamp/nixos-config:main"),
    )
    ipc_server = SimpleNamespace(
        invalidate_window_tree_cache=Mock(),
        notify_state_change=AsyncMock(),
    )

    container = SimpleNamespace(
        id=101,
        floating="user_on",
        parent=None,
        workspace=lambda: None,
    )
    event = SimpleNamespace(container=container)

    await handlers_module.on_window_move(
        conn=None,
        event=event,
        state_manager=state_manager,
        workspace_tracker=None,
        event_buffer=None,
        ipc_server=ipc_server,
    )

    state_manager.update_window.assert_awaited_once_with(
        101,
        binding_state="transient_unbound",
        workspace="",
        is_floating=True,
    )


@pytest.mark.asyncio
async def test_window_move_into_scratchpad_marks_hidden_binding():
    state_manager = SimpleNamespace(
        update_window=AsyncMock(),
        increment_error_count=AsyncMock(),
        get_active_project=AsyncMock(return_value="vpittamp/nixos-config:main"),
    )
    ipc_server = SimpleNamespace(
        invalidate_window_tree_cache=Mock(),
        notify_state_change=AsyncMock(),
    )

    scratchpad_parent = SimpleNamespace(scratchpad_state="changed", parent=None)
    container = SimpleNamespace(
        id=102,
        floating="auto_on",
        parent=scratchpad_parent,
        workspace=lambda: None,
    )
    event = SimpleNamespace(container=container)

    await handlers_module.on_window_move(
        conn=None,
        event=event,
        state_manager=state_manager,
        workspace_tracker=None,
        event_buffer=None,
        ipc_server=ipc_server,
    )

    state_manager.update_window.assert_awaited_once_with(
        102,
        binding_state="scratchpad_hidden",
        workspace="scratchpad",
        is_floating=True,
    )


@pytest.mark.asyncio
async def test_workspace_move_notifies_dashboard_consumers():
    state_manager = SimpleNamespace(
        add_workspace=AsyncMock(),
        increment_error_count=AsyncMock(),
    )
    ipc_server = SimpleNamespace(
        invalidate_window_tree_cache=Mock(),
        notify_state_change=AsyncMock(),
    )

    current = SimpleNamespace(
        name="158",
        num=158,
        ipc_data={"output": "HDMI-A-1", "visible": True, "focused": False},
    )
    old = SimpleNamespace(ipc_data={"output": "DP-2"})
    event = SimpleNamespace(current=current, old=old)

    await handlers_module.on_workspace_move(
        conn=None,
        event=event,
        state_manager=state_manager,
        ipc_server=ipc_server,
    )

    state_manager.add_workspace.assert_awaited_once()
    ipc_server.invalidate_window_tree_cache.assert_called_once()
    ipc_server.notify_state_change.assert_awaited_once_with("workspace::move")


@pytest.mark.asyncio
async def test_workspace_focus_notifies_dashboard_consumers():
    focus_tracker = SimpleNamespace(track_workspace_focus=AsyncMock())
    state_manager = SimpleNamespace(
        get_active_project=AsyncMock(return_value="vpittamp/nixos-config:main"),
        focus_tracker=focus_tracker,
        increment_error_count=AsyncMock(),
    )
    ipc_server = SimpleNamespace(
        invalidate_window_tree_cache=Mock(),
        notify_state_change=AsyncMock(),
    )

    current = SimpleNamespace(
        name="158",
        num=158,
        ipc_data={"output": "DP-2", "visible": True, "focused": True},
    )
    event = SimpleNamespace(current=current)

    await handlers_module.on_workspace_focus(
        conn=None,
        event=event,
        state_manager=state_manager,
        ipc_server=ipc_server,
    )

    focus_tracker.track_workspace_focus.assert_awaited_once_with("vpittamp/nixos-config:main", 158)
    ipc_server.invalidate_window_tree_cache.assert_called_once()
    ipc_server.notify_state_change.assert_awaited_once_with("workspace::focus")
