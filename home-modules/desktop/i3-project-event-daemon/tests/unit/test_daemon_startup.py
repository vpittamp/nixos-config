"""Unit tests for daemon startup resilience."""

from __future__ import annotations

import asyncio
import importlib
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

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


daemon_module = importlib.import_module("i3_project_daemon.daemon")
I3ProjectDaemon = daemon_module.I3ProjectDaemon


@pytest.mark.asyncio
async def test_startup_monitor_sync_writes_profile_state_without_sway_ipc(monkeypatch):
    daemon = I3ProjectDaemon()
    profile = object()
    saved = {}

    daemon.monitor_profile_service = SimpleNamespace(
        get_current_profile=lambda: "single",
        get_profile=lambda name: profile if name == "single" else None,
        _desired_output_states=lambda current_profile: {
            "DP-1": True,
            "DP-2": False,
        } if current_profile is profile else {},
    )
    monkeypatch.setattr(
        daemon_module,
        "load_output_states",
        lambda: SimpleNamespace(set_output_enabled=lambda name, enabled: saved.__setitem__(name, enabled)),
    )
    monkeypatch.setattr(daemon_module, "save_output_states", lambda _states: True)

    await daemon._sync_startup_monitor_state()

    assert saved == {"DP-1": True, "DP-2": False}
