"""Unit tests for trace RPC payload shaping."""

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


trace_module = importlib.import_module("i3_project_daemon.services.trace_service")
TraceService = trace_module.TraceService


class _Tracer:
    def __init__(self) -> None:
        self.started = []
        self.traces = {}
        self.cross_reference_buffer = None

    async def start_trace(self, **kwargs):
        self.started.append(kwargs)
        return "trace-1"

    async def start_app_trace(self, app_name, timeout=30.0):
        self.started.append({"app_name": app_name, "timeout": timeout})
        return "trace-app"

    async def get_trace(self, trace_id):
        return self.traces.get(trace_id)

    async def get_cross_reference(self, event_id, event_buffer):
        self.cross_reference_buffer = event_buffer
        return {"has_trace": True, "event_id": event_id}

    async def list_traces(self):
        return [{"trace_id": "trace-1", "is_active": True}]

    async def query_window_traces_with_log_refs(self, **kwargs):
        return [{"trace_id": "trace-1", "event_buffer": kwargs.get("event_buffer") is not None}]


def _service(**overrides):
    defaults = {
        "i3_connection_provider": lambda: None,
        "event_buffer_provider": lambda: None,
    }
    defaults.update(overrides)
    return TraceService(**defaults)


@pytest.mark.asyncio
async def test_start_finds_matching_window_and_starts_trace(monkeypatch) -> None:
    tracer = _Tracer()
    monkeypatch.setattr(trace_module, "get_tracer", lambda: tracer)
    window = SimpleNamespace(
        id=42,
        app_id="",
        window_class="Alacritty",
        name="Codex",
        pid=123,
    )
    tree = SimpleNamespace(leaves=lambda: [window])

    async def get_tree():
        return tree

    connection = SimpleNamespace(conn=True, get_tree=get_tree)
    service = _service(i3_connection_provider=lambda: connection)

    result = await service.start({"class": "alacritty"})

    assert result == {
        "success": True,
        "trace_id": "trace-1",
        "matcher": {"class": "alacritty"},
        "window_id": 42,
        "window_found": True,
    }
    assert tracer.started == [{
        "matcher": {"class": "alacritty"},
        "window_id": 42,
        "initial_container": window,
    }]


@pytest.mark.asyncio
async def test_events_by_trace_uses_late_bound_event_buffer(monkeypatch) -> None:
    tracer = _Tracer()
    event_time = datetime(2026, 1, 1, 12, 0, 0)
    trace_event = SimpleNamespace(timestamp=event_time.timestamp())
    tracer.traces["trace-1"] = SimpleNamespace(
        window_id=42,
        started_at=event_time.timestamp() - 1,
        stopped_at=event_time.timestamp() + 1,
        events=[trace_event],
    )
    monkeypatch.setattr(trace_module, "get_tracer", lambda: tracer)
    event = SimpleNamespace(
        event_id="evt-1",
        event_type="window::focus",
        timestamp=event_time,
        window_id=42,
        trace_id="",
    )
    late_buffer = {"value": SimpleNamespace(events=[event])}
    service = _service(event_buffer_provider=lambda: late_buffer["value"])

    result = await service.events_by_trace({"trace_id": "trace-1", "limit": 10})

    assert result == {
        "trace_id": "trace-1",
        "events": [{
            "event_id": "evt-1",
            "event_type": "window::focus",
            "timestamp": "2026-01-01T12:00:00",
            "window_id": 42,
            "trace_event_index": 0,
        }],
        "total_count": 1,
    }


@pytest.mark.asyncio
async def test_cross_reference_uses_late_bound_event_buffer(monkeypatch) -> None:
    tracer = _Tracer()
    monkeypatch.setattr(trace_module, "get_tracer", lambda: tracer)
    event_buffer = SimpleNamespace(events=[])
    service = _service(event_buffer_provider=lambda: event_buffer)

    result = await service.get_cross_reference({"event_id": 12})

    assert result == {"has_trace": True, "event_id": 12}
    assert tracer.cross_reference_buffer is event_buffer


@pytest.mark.asyncio
async def test_causality_chain_formats_events_from_late_bound_buffer() -> None:
    root = SimpleNamespace(
        event_id="evt-root",
        event_type="project::switch",
        timestamp=datetime(2026, 1, 1, 12, 0, 0),
        causality_depth=0,
        window_id=None,
        correlation_id="corr-1",
    )
    child = SimpleNamespace(
        event_id="evt-child",
        event_type="visibility::hidden",
        timestamp=datetime(2026, 1, 1, 12, 0, 1),
        causality_depth=1,
        window_id=42,
        correlation_id="corr-1",
    )
    service = _service(event_buffer_provider=lambda: SimpleNamespace(events=[child, root]))

    result = await service.causality_chain({"correlation_id": "corr-1"})

    assert result["correlation_id"] == "corr-1"
    assert result["root_event_id"] == "evt-root"
    assert result["event_count"] == 2
    assert result["duration_ms"] == 1000.0
    assert result["depth"] == 1
    assert result["summary"] == "project::switch -> 2 events, 1000.0ms"
    assert [event["event_id"] for event in result["events"]] == ["evt-root", "evt-child"]


@pytest.mark.asyncio
async def test_query_window_traces_passes_late_bound_event_buffer(monkeypatch) -> None:
    tracer = _Tracer()
    monkeypatch.setattr(trace_module, "get_tracer", lambda: tracer)
    service = _service(event_buffer_provider=lambda: SimpleNamespace(events=[]))

    result = await service.query_window_traces({"include_log_refs": True})

    assert result == {"traces": [{"trace_id": "trace-1", "event_buffer": True}]}
