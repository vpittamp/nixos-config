"""Unit tests for daemon status/health payload shaping."""

from __future__ import annotations

import importlib
import importlib.util
import json
import sys
import time
from datetime import datetime, timezone
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
models_module = importlib.import_module("i3_project_daemon.models")

DaemonStatusService = status_module.DaemonStatusService
EventEntry = models_module.EventEntry


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
        self.buffer = events
        self.max_size = 500

    def get_recent(self, limit=20):
        return self.events[:limit]

    def get_events(self, limit=20):
        return self.events[:limit]


class _Event:
    def __init__(
        self,
        *,
        event_id: str,
        source: str,
        event_type: str,
        timestamp: datetime,
        data: dict,
        correlation_id: str | None = None,
        confidence_score: float | None = None,
    ) -> None:
        self.event_id = event_id
        self.source = source
        self.event_type = event_type
        self.timestamp = timestamp
        self.data = data
        self.correlation_id = correlation_id
        self.confidence_score = confidence_score

    def to_dict(self):
        return self.data


def _new_service(**overrides):
    params = {
        "state_manager": _StateManager(),
        "event_buffer": None,
        "i3_connection_provider": lambda: None,
        "socket_path_provider": lambda: "/tmp/i3pm.sock",
        "ipc_stats_provider": lambda: {},
    }
    params.update(overrides)
    return DaemonStatusService(**params)


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


@pytest.mark.asyncio
async def test_status_rpc_logs_query_event(monkeypatch) -> None:
    health_metrics = SimpleNamespace(
        uptime_seconds=88,
        memory_rss_mb=123.4,
        total_events_processed=12,
        total_errors=2,
        last_event_time=1_767_225_600,
        i3_connected=True,
        update_resource_usage=lambda: None,
    )
    monkeypatch.setattr(health_module, "get_health_metrics", lambda: health_metrics)
    logged = []

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _new_service(
        log_ipc_event=log_ipc_event,
        i3_connection_provider=lambda: SimpleNamespace(is_connected=True),
    )

    status = await service.status_rpc()

    assert status["running"] is True
    assert logged
    assert logged[0]["event_type"] == "query::daemon_status"
    assert logged[0]["duration_ms"] >= 0


@pytest.mark.asyncio
async def test_events_rpc_filters_late_bound_buffer_and_logs_query() -> None:
    now = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    older = datetime(2026, 1, 1, 11, 59, 0, tzinfo=timezone.utc)
    buffer_slot = {
        "value": _EventBuffer(
            [
                _Event(
                    event_id="event-1",
                    source="i3",
                    event_type="window::focus",
                    timestamp=now,
                    data={"container_id": 42},
                    correlation_id="corr-1",
                    confidence_score=0.75,
                ),
                _Event(
                    event_id="event-2",
                    source="i3",
                    event_type="workspace::focus",
                    timestamp=now,
                    data={"workspace": "2"},
                ),
                _Event(
                    event_id="event-3",
                    source="systemd",
                    event_type="window::focus",
                    timestamp=older,
                    data={"unit": "ignored"},
                ),
            ]
        )
    }
    logged = []

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _new_service(
        event_buffer_provider=lambda: buffer_slot["value"],
        log_ipc_event=log_ipc_event,
    )

    result = await service.events_rpc(
        {
            "source": "i3",
            "event_type": "window::focus",
            "since": "2026-01-01T12:00:00Z",
            "correlate": True,
            "limit": 10,
        }
    )

    assert result["total_events"] == 3
    assert result["buffer_size"] == 500
    assert result["events"] == [
        {
            "event_id": "event-1",
            "source": "i3",
            "event_type": "window::focus",
            "timestamp": "2026-01-01T12:00:00+00:00",
            "data": {"container_id": 42},
            "correlation_id": "corr-1",
            "confidence_score": 0.75,
        }
    ]
    assert logged
    assert logged[0]["event_type"] == "query::daemon_events"
    assert logged[0]["result_count"] == 1


@pytest.mark.asyncio
async def test_events_rpc_serializes_real_event_entry_without_to_dict() -> None:
    timestamp = datetime(2026, 1, 1, 12, 0, 0)
    service = _new_service(
        event_buffer_provider=lambda: _EventBuffer(
            [
                EventEntry(
                    event_id=7,
                    source="ipc",
                    event_type="query::daemon_status",
                    timestamp=timestamp,
                    query_method="daemon.status",
                    query_result_count=1,
                )
            ]
        )
    )

    result = await service.events_rpc({"limit": 5})

    assert result["events"][0]["event_id"] == "7"
    assert result["events"][0]["event_type"] == "query::daemon_status"
    assert result["events"][0]["data"]["timestamp"] == "2026-01-01T12:00:00"
    assert result["events"][0]["data"]["query_method"] == "daemon.status"
    assert result["events"][0]["data"]["query_result_count"] == 1


@pytest.mark.asyncio
async def test_apps_rpc_reads_registry_filters_and_logs_query(tmp_path) -> None:
    registry_path = tmp_path / "application-registry.json"
    registry_path.write_text(
        json.dumps(
            {
                "version": "2026.06",
                "applications": [
                    {
                        "name": "Herdr",
                        "scope": "global",
                        "preferred_workspace": "33",
                    },
                    {
                        "name": "Browser",
                        "scope": "project",
                        "preferred_workspace": "2",
                    },
                ],
            }
        )
    )
    logged = []

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = _new_service(
        registry_path=registry_path,
        log_ipc_event=log_ipc_event,
    )

    result = await service.apps_rpc({"scope": "global", "workspace": "33"})

    assert result["version"] == "2026.06"
    assert result["count"] == 1
    assert result["registry_path"] == str(registry_path)
    assert result["applications"][0]["name"] == "Herdr"
    assert logged
    assert logged[0]["event_type"] == "query::daemon_apps"
