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


window_filter_module = importlib.import_module("i3_project_daemon.services.window_filter")
window_tracer_module = importlib.import_module("i3_project_daemon.services.window_tracer")

WindowTracer = window_tracer_module.WindowTracer
CommandType = window_filter_module.CommandType
WindowCommand = window_filter_module.WindowCommand
_record_command_queued = window_filter_module._record_command_queued
_record_filter_decision = window_filter_module._record_filter_decision


@pytest.mark.asyncio
async def test_window_tracer_active_trace_count_tracks_trace_lifecycle():
    tracer = WindowTracer()

    assert tracer.has_active_traces() is False

    trace_id = await tracer.start_trace({"id": "42"})
    assert tracer.has_active_traces() is True

    await tracer.stop_trace(trace_id)
    assert tracer.has_active_traces() is False


@pytest.mark.asyncio
async def test_window_tracer_active_trace_count_tracks_pending_trace_expiry():
    tracer = WindowTracer()

    await tracer.start_app_trace("terminal", timeout=0.01)
    assert tracer.has_active_traces() is True

    await asyncio.sleep(0.05)
    assert tracer.has_active_traces() is False


class _InactiveTracer:
    def has_active_traces(self) -> bool:
        return False

    async def record_event(self, *args, **kwargs):
        raise AssertionError("record_event should not be called when there are no active traces")

    async def record_window_event(self, *args, **kwargs):
        raise AssertionError(
            "record_window_event should not be called when there are no active traces"
        )


@pytest.mark.asyncio
async def test_window_filter_trace_helpers_skip_inactive_tracer(monkeypatch):
    monkeypatch.setattr(window_filter_module, "get_tracer", lambda: _InactiveTracer())

    window = SimpleNamespace(id=101)
    command = WindowCommand(
        window_id=101,
        command_type=CommandType.MOVE_SCRATCHPAD,
        params={},
    )

    await _record_filter_decision(
        window=window,
        should_show=True,
        reason="project match",
        window_scope="scoped",
        window_project="vpittamp/nixos-config:main",
        window_app="terminal",
        active_project="vpittamp/nixos-config:main",
    )
    await _record_command_queued(window_id=101, command=command, phase="hide")
