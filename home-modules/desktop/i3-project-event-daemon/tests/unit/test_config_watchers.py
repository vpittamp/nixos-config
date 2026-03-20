from __future__ import annotations

import asyncio
import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

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


config_module = importlib.import_module("i3_project_daemon.config")
DebouncedReloadHandler = config_module.DebouncedReloadHandler
WindowRulesWatcher = config_module.WindowRulesWatcher


@pytest.mark.asyncio
async def test_debounced_reload_handler_ignores_unrelated_files():
    callback = Mock()
    handler = DebouncedReloadHandler(
        callback,
        debounce_ms=1,
        target_filename="window-rules.json",
    )
    handler.set_event_loop(asyncio.get_running_loop())

    handler.on_modified(
        SimpleNamespace(
            is_directory=False,
            src_path="/tmp/window-workspace-map.json",
        )
    )
    await asyncio.sleep(0.02)

    callback.assert_not_called()


@pytest.mark.asyncio
async def test_debounced_reload_handler_triggers_for_atomic_save_move():
    callback = Mock()
    handler = DebouncedReloadHandler(
        callback,
        debounce_ms=1,
        target_filename="window-rules.json",
    )
    handler.set_event_loop(asyncio.get_running_loop())

    handler.on_moved(
        SimpleNamespace(
            is_directory=False,
            src_path="/tmp/.window-rules.json.tmp",
            dest_path="/tmp/window-rules.json",
        )
    )
    await asyncio.sleep(0.02)

    callback.assert_called_once_with()


def test_window_rules_watcher_scopes_to_rules_filename():
    watcher = WindowRulesWatcher(Path("/tmp/window-rules.json"), lambda: [])

    assert watcher.handler.target_filename == "window-rules.json"
