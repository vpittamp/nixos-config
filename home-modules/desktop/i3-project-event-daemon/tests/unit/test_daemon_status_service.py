"""Unit tests for daemon status/health payload shaping."""

from __future__ import annotations

import importlib
import importlib.util
import sys
import time
from datetime import datetime
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


status_module = importlib.import_module("i3_project_daemon.services.daemon_status_service")
health_module = importlib.import_module("i3_project_daemon.monitoring.health")

DaemonStatusService = status_module.DaemonStatusService


class _StateManager:
    def __init__(self) -> None:
        self.daemon_start_time = time.time() - 10
        self.state = SimpleNamespace(
            is_connected=True,
            window_map={1: object(), 2: object()},
        )

    async def get_stats(self):
        return {
            "uptime_seconds": 42,
            "active_project": "vpittamp/nixos-config:main",
            "window_count": 2,
            "workspace_count": 4,
            "event_count": 9,
            "error_count": 1,
        }


class _EventBuffer:
    def __init__(self, events):
        self.events = events

    def get_recent(self, limit=20):
        return self.events[:limit]


@pytest.mark.asyncio
async def test_cli_status_uses_state_socket_and_ipc_stats() -> None:
    service = DaemonStatusService(
        state_manager=_StateManager(),
        event_buffer=None,
        i3_connection_provider=lambda: None,
        socket_path_provider=lambda: "/tmp/i3pm.sock",
        ipc_stats_provider=lambda: {"client_count": 3},
    )

    status = await service.cli_status()

    assert status["status"] == "running"
    assert status["connected"] is True
    assert status["uptime"] == 42
    assert status["active_project"] == "vpittamp/nixos-config:main"
    assert status["window_count"] == 2
    assert status["workspace_count"] == 4
    assert status["event_count"] == 9
    assert status["error_count"] == 1
    assert status["version"] == "1.0.0"
    assert status["socket_path"] == "/tmp/i3pm.sock"
    assert status["ipc_stats"] == {"client_count": 3}


def test_health_check_reports_event_subscriptions_and_window_count() -> None:
    now = datetime(2026, 1, 1, 12, 0, 0)
    event_buffer = _EventBuffer(
        [
            SimpleNamespace(event_type="window::focus", timestamp=now),
            SimpleNamespace(event_type="workspace::focus", timestamp=now),
            SimpleNamespace(event_type="tick::barrier", timestamp=now),
        ]
    )
    service = DaemonStatusService(
        state_manager=_StateManager(),
        event_buffer=event_buffer,
        i3_connection_provider=lambda: SimpleNamespace(is_connected=True),
        socket_path_provider=lambda: "/tmp/i3pm.sock",
        ipc_stats_provider=lambda: {},
    )

    health = service.health_check()

    assert health["daemon_version"] == "1.4.0"
    assert health["i3_ipc_connected"] is True
    assert health["json_rpc_server_running"] is True
    assert health["total_events_processed"] == 3
    assert health["total_windows"] == 2
    assert health["overall_status"] == "healthy"
    assert health["health_issues"] == []
    assert {entry["subscription_type"] for entry in health["event_subscriptions"]} == {
        "window",
        "workspace",
        "output",
        "tick",
    }


def test_health_check_uses_late_bound_event_buffer_provider() -> None:
    now = datetime(2026, 1, 1, 12, 0, 0)
    late_buffer = {
        "value": _EventBuffer([SimpleNamespace(event_type="window::focus", timestamp=now)])
    }
    service = DaemonStatusService(
        state_manager=_StateManager(),
        event_buffer=None,
        event_buffer_provider=lambda: late_buffer["value"],
        i3_connection_provider=lambda: SimpleNamespace(is_connected=True),
        socket_path_provider=lambda: "/tmp/i3pm.sock",
        ipc_stats_provider=lambda: {},
    )

    health = service.health_check()

    assert health["overall_status"] == "healthy"
    assert health["total_events_processed"] == 1
    assert health["event_subscriptions"][0]["event_count"] == 1


def test_health_check_reports_critical_when_i3_or_subscriptions_are_missing() -> None:
    service = DaemonStatusService(
        state_manager=_StateManager(),
        event_buffer=None,
        i3_connection_provider=lambda: None,
        socket_path_provider=lambda: "/tmp/i3pm.sock",
        ipc_stats_provider=lambda: {},
    )

    health = service.health_check()

    assert health["i3_ipc_connected"] is False
    assert health["event_subscriptions"] == []
    assert health["overall_status"] == "critical"
    assert "i3 IPC connection lost" in health["health_issues"]
    assert "No event subscriptions active" in health["health_issues"]


@pytest.mark.asyncio
async def test_socket_health_reports_disconnected_without_i3_connection() -> None:
    service = DaemonStatusService(
        state_manager=_StateManager(),
        event_buffer=None,
        i3_connection_provider=lambda: None,
        socket_path_provider=lambda: "/tmp/i3pm.sock",
        ipc_stats_provider=lambda: {},
    )

    health = await service.socket_health()

    assert health == {
        "status": "disconnected",
        "socket_path": None,
        "last_validated": None,
        "latency_ms": None,
        "reconnection_count": 0,
        "uptime_seconds": 0.0,
        "error": "No i3 connection manager available",
    }


@pytest.mark.asyncio
async def test_daemon_status_includes_recovery_and_reconnection(monkeypatch) -> None:
    health_metrics = SimpleNamespace(
        uptime_seconds=88,
        memory_rss_mb=123.4,
        total_events_processed=12,
        total_errors=2,
        last_event_time=1_767_225_600,
        i3_connected=False,
        update_resource_usage=lambda: None,
    )
    monkeypatch.setattr(health_module, "get_health_metrics", lambda: health_metrics)
    recovery = SimpleNamespace(
        success=True,
        actions_taken=["restored_state"],
        timestamp=datetime(2026, 1, 1, 12, 0, 0),
    )
    reconnection = SimpleNamespace(get_stats=lambda: {"is_connected": True, "reconnection_count": 2})
    service = DaemonStatusService(
        state_manager=_StateManager(),
        event_buffer=None,
        i3_connection_provider=lambda: SimpleNamespace(is_connected=True),
        socket_path_provider=lambda: "/tmp/i3pm.sock",
        ipc_stats_provider=lambda: {},
        startup_recovery_provider=lambda: recovery,
        reconnection_manager_provider=lambda: reconnection,
    )

    status = await service.daemon_status()

    assert status["running"] is True
    assert status["uptime_seconds"] == 88
    assert status["memory_mb"] == 123.4
    assert status["event_count"] == 12
    assert status["error_count"] == 2
    assert status["i3_connected"] is True
    assert status["active_project"] == "vpittamp/nixos-config:main"
    assert status["recovery"] == {
        "startup_recovery_performed": True,
        "startup_recovery_success": True,
        "actions_taken": ["restored_state"],
        "recovery_timestamp": "2026-01-01T12:00:00",
    }
    assert status["i3_reconnection"] == {"is_connected": True, "reconnection_count": 2}
