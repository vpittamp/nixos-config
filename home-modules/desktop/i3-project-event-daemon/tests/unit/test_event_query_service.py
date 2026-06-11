"""Unit tests for event query payload shaping."""

from __future__ import annotations

import importlib
import importlib.util
import sys
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


event_query_module = importlib.import_module("i3_project_daemon.services.event_query_service")
models_module = importlib.import_module("i3_project_daemon.models")

EventEntry = models_module.EventEntry
EventQueryService = event_query_module.EventQueryService
event_data = event_query_module.event_data


class _EventBuffer:
    def __init__(self, events):
        self.events = events
        self.calls = []

    def get_events(self, **kwargs):
        self.calls.append(kwargs)
        events = list(self.events)
        source = kwargs.get("source")
        event_type = kwargs.get("event_type")
        since_id = kwargs.get("since_id")
        if source:
            events = [event for event in events if event.source == source]
        if event_type:
            events = [event for event in events if event.event_type.startswith(event_type)]
        if since_id is not None:
            events = [event for event in events if event.event_id > since_id]
        return events[: kwargs.get("limit", 100)]

    def get_stats(self):
        return {
            "total_events": len(self.events),
            "buffer_size": len(self.events),
            "max_size": 500,
        }


def _event(**overrides):
    values = {
        "event_id": 1,
        "event_type": "window::focus",
        "timestamp": datetime(2026, 1, 1, 12, 0, 0),
        "source": "i3",
        "processing_duration_ms": 1.5,
    }
    values.update(overrides)
    return EventEntry(**values)


@pytest.mark.asyncio
async def test_get_events_queries_buffer_serializes_and_logs() -> None:
    buffer = _EventBuffer(
        [
            _event(
                event_id=3,
                window_id=42,
                window_class="Alacritty",
                workspace_name="2",
            ),
            _event(event_id=2, source="ipc", event_type="query::status"),
        ]
    )
    logged = []

    async def log_ipc_event(**kwargs):
        logged.append(kwargs)

    service = EventQueryService(
        event_buffer_provider=lambda: buffer,
        log_ipc_event=log_ipc_event,
    )

    result = await service.get_events(
        {"limit": 10, "source": "i3", "event_type": "window", "since_id": 1}
    )

    assert buffer.calls == [
        {"limit": 10, "event_type": "window", "source": "i3", "since_id": 1}
    ]
    assert result["stats"] == {"total_events": 2, "buffer_size": 2, "max_size": 500}
    assert result["events"] == [
        {
            "event_id": 3,
            "event_type": "window::focus",
            "timestamp": "2026-01-01T12:00:00",
            "source": "i3",
            "processing_duration_ms": 1.5,
            "window_id": 42,
            "window_class": "Alacritty",
            "workspace_name": "2",
        }
    ]
    assert logged[0]["event_type"] == "query::events"
    assert logged[0]["result_count"] == 1


@pytest.mark.asyncio
async def test_get_events_merges_injected_systemd_events_for_all_source() -> None:
    buffer = _EventBuffer(
        [
            _event(event_id=1, timestamp=datetime(2026, 1, 1, 12, 0, 0)),
        ]
    )
    systemd_event = _event(
        event_id=2,
        source="systemd",
        event_type="systemd::unit",
        timestamp=datetime(2026, 1, 1, 12, 1, 0),
        systemd_unit="i3-project-daemon.service",
        systemd_message="Started",
    )

    def query_systemd(**kwargs):
        assert kwargs == {"since": "5 minutes ago", "limit": 5}
        return [systemd_event]

    service = EventQueryService(
        event_buffer_provider=lambda: buffer,
        systemd_query=query_systemd,
    )

    result = await service.get_events(
        {"source": "all", "since": "5 minutes ago", "limit": 5}
    )

    assert [event["event_id"] for event in result["events"]] == [1, 2]
    assert result["events"][1]["systemd_unit"] == "i3-project-daemon.service"
    assert result["events"][1]["systemd_message"] == "Started"


def test_event_data_serializes_dataclass_and_to_dict_events() -> None:
    entry = _event(event_id=7, query_method="daemon.status")
    custom = SimpleNamespace(
        to_dict=lambda: {"timestamp": datetime(2026, 1, 1, 12, 0, 0)}
    )

    assert event_data(entry)["timestamp"] == "2026-01-01T12:00:00"
    assert event_data(entry)["query_method"] == "daemon.status"
    assert event_data(custom) == {"timestamp": "2026-01-01T12:00:00"}
