from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
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


connection_module = importlib.import_module("i3_project_daemon.connection")
state_module = importlib.import_module("i3_project_daemon.state")
models_module = importlib.import_module("i3_project_daemon.models")


@pytest.mark.asyncio
async def test_validate_and_reconnect_returns_false_for_healthy_connection(tmp_path, monkeypatch):
    socket_path = tmp_path / "sway-ipc.test.sock"
    socket_path.write_text("")
    monkeypatch.setenv("SWAYSOCK", str(socket_path))
    monkeypatch.setenv("I3SOCK", str(socket_path))

    connection = connection_module.ResilientI3Connection(SimpleNamespace())
    healthy_conn = SimpleNamespace(get_tree=AsyncMock())
    connection.conn = healthy_conn

    reconnected = await connection.validate_and_reconnect_if_needed()

    assert reconnected is False
    healthy_conn.get_tree.assert_awaited_once()


@pytest.mark.asyncio
async def test_update_window_accepts_title_alias_without_warning():
    state_manager = state_module.StateManager()
    window = models_module.WindowInfo(
        window_id=101,
        con_id=101,
        window_class="google-chrome",
        window_title="Old Title",
        window_instance="google-chrome",
        app_identifier="google-chrome",
    )

    await state_manager.add_window(window)
    await state_manager.update_window(101, title="New Title")

    updated = await state_manager.get_window(101)
    assert updated is not None
    assert updated.window_title == "New Title"
