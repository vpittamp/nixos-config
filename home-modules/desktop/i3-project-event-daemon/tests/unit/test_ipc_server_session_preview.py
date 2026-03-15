"""Unit tests for daemon-owned AI session preview target resolution."""

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


ipc_server_module = importlib.import_module("i3_project_daemon.ipc_server")

IPCServer = ipc_server_module.IPCServer


class DummyLaunchRegistry:
    def get_stats(self):
        return SimpleNamespace(total_pending=0)


class DummyStateManager:
    def __init__(self):
        self.state = SimpleNamespace(
            active_project="global",
            window_map={},
            launch_registry=DummyLaunchRegistry(),
        )
        self.launch_registry = self.state.launch_registry

    async def get_active_project(self):
        return self.state.active_project

    async def remove_window(self, _window_id: int):
        return None


@pytest.fixture
def server():
    return IPCServer(DummyStateManager())


def make_session(**overrides):
    session = {
        "session_key": "session-local",
        "tool": "codex",
        "project_name": "vpittamp/nixos-config:main",
        "host_name": "thinkpad",
        "connection_key": "local@thinkpad",
        "execution_mode": "local",
        "focus_mode": "local",
        "window_id": 1001,
        "pane_label": "editor",
        "pane_title": "editor",
        "tmux_session": "nixos-config/main",
        "tmux_window": "0:main",
        "tmux_pane": "%17",
        "surface_key": "pane::%17",
        "session_phase": "working",
        "session_phase_label": "Working",
        "status_reason": "pulse_working",
        "is_current_host": True,
        "source_is_current_host": True,
        "terminal_context": {
            "execution_mode": "local",
            "tmux_session": "nixos-config/main",
            "tmux_window": "0:main",
            "tmux_pane": "%17",
        },
    }
    session.update(overrides)
    return session


@pytest.mark.asyncio
async def test_session_preview_returns_live_local_stream_for_current_host_tmux_session(server):
    server._session_list = AsyncMock(return_value={"sessions": [make_session()]})

    result = await server._session_preview({"session_key": "session-local", "lines": 120})

    assert result["success"] is True
    assert result["preview_mode"] == "local_stream"
    assert result["preview_reason"] == "ok"
    assert result["is_live"] is True
    assert result["is_remote"] is False
    assert result["lines"] == 120
    assert result["tmux_pane"] == "%17"


@pytest.mark.asyncio
async def test_session_preview_returns_ssh_stream_for_remote_session(server, monkeypatch):
    remote_session = make_session(
        session_key="session-remote",
        project_name="vpittamp/nixos-config:main",
        host_name="ryzen",
        connection_key="local@ryzen",
        focus_connection_key="vpittamp@ryzen:22",
        execution_mode="local",
        focus_mode="ssh_attach",
        is_current_host=False,
        source_is_current_host=False,
        terminal_context={
            "execution_mode": "local",
            "tmux_session": "nixos-config/main",
            "tmux_window": "0:main",
            "tmux_pane": "%21",
            "tmux_socket": "/tmp/tmux-1000/default",
        },
        tmux_pane="%21",
    )
    server._session_list = AsyncMock(return_value={"sessions": [remote_session]})
    monkeypatch.setattr(server, "_resolve_remote_attach_profile", lambda _session: {
        "remote_user": "vpittamp",
        "remote_host": "ryzen",
        "remote_port": 22,
    })

    result = await server._session_preview({"session_key": "session-remote"})

    assert result["preview_mode"] == "ssh_stream"
    assert result["preview_reason"] == "remote_host"
    assert result["is_live"] is True
    assert result["is_remote"] is True
    assert result["remote_host"] == "ryzen"
    assert result["remote_user"] == "vpittamp"
    assert result["tmux_socket"] == "/tmp/tmux-1000/default"


@pytest.mark.asyncio
async def test_session_preview_prefers_remote_source_connection_for_bound_remote_session(server, monkeypatch):
    remote_session = make_session(
        session_key="session-remote-bound",
        project_name="vpittamp/nixos-config:main",
        host_name="thinkpad",
        connection_key="local@thinkpad",
        source_connection_key="vpittamp@thinkpad:22",
        focus_connection_key="vpittamp@ryzen:22",
        execution_mode="local",
        focus_mode="local",
        window_id=52,
        is_current_host=True,
        source_is_current_host=False,
        terminal_context={
            "execution_mode": "local",
            "tmux_session": "nixos-config/main",
            "tmux_window": "0:main",
            "tmux_pane": "%21",
            "tmux_socket": "/run/user/1000/tmux-1000/default",
        },
        tmux_pane="%21",
    )
    server._session_list = AsyncMock(return_value={"sessions": [remote_session]})

    def resolve_attach_profile(session):
        assert session["source_connection_key"] == "vpittamp@thinkpad:22"
        return {
            "remote_user": "vpittamp",
            "remote_host": "thinkpad",
            "remote_port": 22,
        }

    monkeypatch.setattr(server, "_resolve_remote_attach_profile", resolve_attach_profile)

    result = await server._session_preview({"session_key": "session-remote-bound"})

    assert result["preview_mode"] == "ssh_stream"
    assert result["remote_host"] == "thinkpad"
    assert result["remote_user"] == "vpittamp"


@pytest.mark.asyncio
async def test_session_preview_reports_missing_tmux_identity(server):
    missing_tmux = make_session(
        session_key="session-missing",
        pane_label="detached",
        tmux_session="",
        tmux_window="",
        tmux_pane="",
        terminal_context={"execution_mode": "local"},
    )
    server._session_list = AsyncMock(return_value={"sessions": [missing_tmux]})

    result = await server._session_preview({"session_key": "session-missing", "lines": 500})

    assert result["preview_mode"] == "unavailable"
    assert result["preview_reason"] == "missing_tmux_identity"
    assert result["is_live"] is False
    assert result["lines"] == 200
