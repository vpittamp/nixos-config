"""Unit tests for daemon startup construction."""

from __future__ import annotations

import importlib


daemon_module = importlib.import_module("i3_project_daemon.daemon")
I3ProjectDaemon = daemon_module.I3ProjectDaemon


def test_daemon_can_be_constructed_with_current_startup_dependencies() -> None:
    daemon = I3ProjectDaemon()

    assert daemon.state_manager is None
    assert daemon.connection is None
    assert daemon.ipc_server is None
    assert daemon.monitor_profile_service is None
