"""Tests for the legacy Python daemon IPC client."""

from pathlib import Path

import pytest

from i3_project_manager.core import daemon_client
from i3_project_manager.core.daemon_client import (
    DEFAULT_STREAM_LIMIT_BYTES,
    DaemonClient,
)


class DummyWriter:
    def close(self) -> None:
        pass

    async def wait_closed(self) -> None:
        pass


@pytest.mark.asyncio
async def test_connect_uses_large_default_stream_limit(monkeypatch):
    observed = {}

    async def fake_open_unix_connection(path: str, *, limit: int):
        observed["path"] = path
        observed["limit"] = limit
        return object(), DummyWriter()

    monkeypatch.setattr(
        daemon_client.asyncio,
        "open_unix_connection",
        fake_open_unix_connection,
    )

    client = DaemonClient(socket_path=Path("/tmp/i3pm.sock"))
    await client.connect()

    assert observed == {
        "path": "/tmp/i3pm.sock",
        "limit": DEFAULT_STREAM_LIMIT_BYTES,
    }


@pytest.mark.asyncio
async def test_connect_honors_custom_stream_limit(monkeypatch):
    observed = {}

    async def fake_open_unix_connection(path: str, *, limit: int):
        observed["limit"] = limit
        return object(), DummyWriter()

    monkeypatch.setattr(
        daemon_client.asyncio,
        "open_unix_connection",
        fake_open_unix_connection,
    )

    client = DaemonClient(
        socket_path=Path("/tmp/i3pm.sock"),
        stream_limit_bytes=123456,
    )
    await client.connect()

    assert observed["limit"] == 123456
