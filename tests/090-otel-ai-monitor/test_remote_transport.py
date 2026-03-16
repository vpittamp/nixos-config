import asyncio
import importlib.util
import json
import sys
from pathlib import Path

import pytest


def _load_otel_monitor_package():
    pkg_dir = (
        Path(__file__).resolve().parents[2]
        / "scripts"
        / "otel-ai-monitor"
    )
    spec = importlib.util.spec_from_file_location(
        "otel_ai_monitor",
        pkg_dir / "__init__.py",
        submodule_search_locations=[str(pkg_dir)],
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load otel_ai_monitor package")
    module = importlib.util.module_from_spec(spec)
    sys.modules["otel_ai_monitor"] = module
    spec.loader.exec_module(module)
    return module


_load_otel_monitor_package()
from otel_ai_monitor.remote_transport import (  # type: ignore  # noqa: E402
    RemoteSessionPushClient,
    RemoteSessionSinkStore,
)


def _build_payload(
    *,
    sequence: int,
    payload_hash: str,
    session_id: str,
    source_boot_id: str = "boot-1",
    sent_at: str = "2026-02-23T20:00:00+00:00",
) -> dict:
    return {
        "schema_version": "1",
        "source": {
            "connection_key": "vpittamp@ryzen:22",
            "host_name": "ryzen",
        },
        "source_boot_id": source_boot_id,
        "sequence": sequence,
        "payload_hash": payload_hash,
        "sent_at": sent_at,
        "sessions_payload": {
            "schema_version": "10",
            "updated_at": "2026-02-23T20:00:00+00:00",
            "timestamp": 1898126400,
            "has_working": True,
            "sessions": [
                {
                    "tool": "codex",
                    "state": "working",
                    "project": "PittampalliOrg/workflow-builder:main",
                    "session_id": session_id,
                    "updated_at": "2026-02-23T20:00:00+00:00",
                }
            ],
        },
    }


@pytest.mark.asyncio
async def test_sink_accepts_monotonic_sequences(tmp_path):
    sink_file = tmp_path / "remote-otel-sink.json"
    sink = RemoteSessionSinkStore(sink_file)
    await sink.start()
    try:
        accepted, reason, status = await sink.ingest(_build_payload(sequence=1, payload_hash="h1", session_id="sid-1"))
        assert accepted is True
        assert reason == "accepted"
        assert status == 200

        accepted, reason, status = await sink.ingest(_build_payload(sequence=2, payload_hash="h2", session_id="sid-2"))
        assert accepted is True
        assert reason == "accepted"
        assert status == 200

        payload = json.loads(sink_file.read_text())
        source = payload["sources"]["vpittamp@ryzen:22"]
        assert int(source["sequence"]) == 2
        assert str(source["payload_hash"]) == "h2"
        assert source["sessions"][0]["session_id"] == "sid-2"
    finally:
        await sink.stop()


@pytest.mark.asyncio
async def test_sink_rejects_stale_sequence(tmp_path):
    sink_file = tmp_path / "remote-otel-sink.json"
    sink = RemoteSessionSinkStore(sink_file)
    await sink.start()
    try:
        accepted, _, _ = await sink.ingest(_build_payload(sequence=5, payload_hash="h5", session_id="sid-5"))
        assert accepted is True

        accepted, reason, status = await sink.ingest(_build_payload(sequence=4, payload_hash="h4", session_id="sid-4"))
        assert accepted is False
        assert reason == "stale_sequence"
        assert status == 202

        payload = json.loads(sink_file.read_text())
        source = payload["sources"]["vpittamp@ryzen:22"]
        assert int(source["sequence"]) == 5
        assert source["sessions"][0]["session_id"] == "sid-5"
    finally:
        await sink.stop()


@pytest.mark.asyncio
async def test_sink_accepts_same_sequence_heartbeat(tmp_path):
    sink_file = tmp_path / "remote-otel-sink.json"
    sink = RemoteSessionSinkStore(sink_file)
    await sink.start()
    try:
        accepted, _, _ = await sink.ingest(_build_payload(sequence=3, payload_hash="h3", session_id="sid-3"))
        assert accepted is True

        first_payload = json.loads(sink_file.read_text())
        first_received_at = float(first_payload["sources"]["vpittamp@ryzen:22"]["received_at"])

        await asyncio.sleep(0.02)
        accepted, reason, status = await sink.ingest(_build_payload(sequence=3, payload_hash="h3", session_id="sid-3"))
        assert accepted is True
        assert reason == "accepted"
        assert status == 200

        second_payload = json.loads(sink_file.read_text())
        second_received_at = float(second_payload["sources"]["vpittamp@ryzen:22"]["received_at"])
        assert second_received_at >= first_received_at
    finally:
        await sink.stop()


@pytest.mark.asyncio
async def test_sink_rejects_conflicting_same_sequence(tmp_path):
    sink_file = tmp_path / "remote-otel-sink.json"
    sink = RemoteSessionSinkStore(sink_file)
    await sink.start()
    try:
        accepted, _, _ = await sink.ingest(_build_payload(sequence=7, payload_hash="h7", session_id="sid-7"))
        assert accepted is True

        accepted, reason, status = await sink.ingest(_build_payload(sequence=7, payload_hash="DIFFERENT", session_id="sid-new"))
        assert accepted is False
        assert reason == "conflicting_same_sequence"
        assert status == 409
    finally:
        await sink.stop()


@pytest.mark.asyncio
async def test_sink_accepts_new_boot_epoch_when_sequence_restarts(tmp_path):
    sink_file = tmp_path / "remote-otel-sink.json"
    sink = RemoteSessionSinkStore(sink_file)
    await sink.start()
    try:
        accepted, _, _ = await sink.ingest(
            _build_payload(
                sequence=9,
                payload_hash="old-hash",
                session_id="sid-old",
                source_boot_id="boot-old",
                sent_at="2026-02-23T20:00:09+00:00",
            )
        )
        assert accepted is True

        accepted, reason, status = await sink.ingest(
            _build_payload(
                sequence=1,
                payload_hash="new-hash",
                session_id="sid-new",
                source_boot_id="boot-new",
                sent_at="2026-02-23T20:01:00+00:00",
            )
        )
        assert accepted is True
        assert reason == "accepted"
        assert status == 200

        payload = json.loads(sink_file.read_text())
        source = payload["sources"]["vpittamp@ryzen:22"]
        assert source["source_boot_id"] == "boot-new"
        assert int(source["sequence"]) == 1
        assert source["sessions"][0]["session_id"] == "sid-new"
    finally:
        await sink.stop()


@pytest.mark.asyncio
async def test_sink_rejects_new_boot_with_non_reset_sequence(tmp_path):
    sink_file = tmp_path / "remote-otel-sink.json"
    sink = RemoteSessionSinkStore(sink_file)
    await sink.start()
    try:
        accepted, _, _ = await sink.ingest(
            _build_payload(
                sequence=5,
                payload_hash="old-hash",
                session_id="sid-old",
                source_boot_id="boot-old",
                sent_at="2026-02-23T20:00:09+00:00",
            )
        )
        assert accepted is True

        accepted, reason, status = await sink.ingest(
            _build_payload(
                sequence=2,
                payload_hash="new-hash",
                session_id="sid-new",
                source_boot_id="boot-new",
                sent_at="2026-02-23T20:01:00+00:00",
            )
        )
        assert accepted is False
        assert reason == "invalid_boot_sequence"
        assert status == 202
    finally:
        await sink.stop()


@pytest.mark.asyncio
async def test_sink_rejects_stale_boot_epoch_timestamp(tmp_path):
    sink_file = tmp_path / "remote-otel-sink.json"
    sink = RemoteSessionSinkStore(sink_file)
    await sink.start()
    try:
        accepted, _, _ = await sink.ingest(
            _build_payload(
                sequence=4,
                payload_hash="old-hash",
                session_id="sid-old",
                source_boot_id="boot-old",
                sent_at="2026-02-23T20:02:00+00:00",
            )
        )
        assert accepted is True

        accepted, reason, status = await sink.ingest(
            _build_payload(
                sequence=1,
                payload_hash="new-hash",
                session_id="sid-new",
                source_boot_id="boot-new",
                sent_at="2026-02-23T20:01:00+00:00",
            )
        )
        assert accepted is False
        assert reason == "stale_boot_epoch"
        assert status == 202
    finally:
        await sink.stop()


@pytest.mark.asyncio
async def test_push_logs_endpoint_and_exception_detail(caplog):
    class _ExplodingSession:
        def post(self, *args, **kwargs):
            raise TimeoutError()

    client = RemoteSessionPushClient(
        endpoint_url="http://thinkpad:4320/v1/i3pm/remote-sessions",
        source_connection_key="vpittamp@ryzen:22",
        source_host_name="ryzen",
    )
    client._session = _ExplodingSession()
    client._latest_payload = {"schema_version": "6", "sessions": [{"session_id": "sid-1"}]}
    client._latest_payload_hash = "hash-1"
    client._sequence = 1

    with caplog.at_level("WARNING"):
        await client._send_if_needed()

    assert "endpoint=http://thinkpad:4320/v1/i3pm/remote-sessions" in caplog.text
    assert "source=vpittamp@ryzen:22" in caplog.text
    assert "TimeoutError" in caplog.text
