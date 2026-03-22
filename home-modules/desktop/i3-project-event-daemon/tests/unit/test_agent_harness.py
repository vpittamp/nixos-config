"""Unit tests for agent harness session normalization and lifecycle handling."""

from __future__ import annotations

import asyncio
import importlib
import importlib.util
import sys
from pathlib import Path
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


agent_harness_module = importlib.import_module("i3_project_daemon.services.agent_harness")

CodexHarnessSession = agent_harness_module.CodexHarnessSession
CodexHarnessManager = agent_harness_module.CodexHarnessManager


@pytest.mark.asyncio
async def test_process_exit_marks_session_error_and_fails_pending_requests():
    on_change = AsyncMock()
    session = CodexHarnessSession(cwd="/tmp", context={}, on_change=on_change)
    session.thread_id = "thread-1"
    session.session_key = "codex:thread-1"
    session.thread_status = "active"
    session.current_turn_id = "turn-1"

    future = asyncio.get_running_loop().create_future()
    session._pending_responses[1] = future

    await session._handle_process_exit(101)

    assert session.last_error == "Codex app-server exited with code 101"
    assert session.session_phase == "error"
    assert session.turn_owner == "user"
    assert session.activity_substate == "error"
    assert session.snapshot()["can_send"] is False
    assert future.done() is True
    assert isinstance(future.exception(), RuntimeError)
    on_change.assert_awaited_once()


@pytest.mark.asyncio
async def test_thread_item_normalization_sets_display_kind_preview_and_state_labels():
    session = CodexHarnessSession(cwd="/tmp/project-root", context={}, on_change=AsyncMock())
    session.thread_id = "thread-1"
    session.session_key = "codex:thread-1"

    session._upsert_thread_item({
        "type": "userMessage",
        "id": "user-1",
        "content": [{"type": "text", "text": "Inspect the repo", "text_elements": []}],
    })
    session._upsert_thread_item({
        "type": "agentMessage",
        "id": "agent-1",
        "text": "Working through the files.",
        "phase": "commentary",
    })
    session._upsert_thread_item({
        "type": "commandExecution",
        "id": "tool-1",
        "command": "rg foo",
        "cwd": "/tmp/project-root",
        "aggregatedOutput": "src/main.ts:1:foo",
        "status": "completed",
        "durationMs": 24,
    })
    session._recompute_phase()

    snapshot = session.snapshot()
    assert snapshot["provider_label"] == "Codex"
    assert snapshot["state_label"] == "Done"
    assert snapshot["title"] == "Inspect the repo"
    assert snapshot["preview"] == "src/main.ts:1:foo"
    assert snapshot["session_phase"] == "done"

    assert snapshot["transcript"][0]["display_kind"] == "user"
    assert snapshot["transcript"][1]["display_kind"] == "assistant_commentary"
    assert snapshot["transcript"][1]["label"] == "Commentary"
    assert snapshot["transcript"][2]["display_kind"] == "tool"
    assert snapshot["transcript"][2]["preview"] == "src/main.ts:1:foo"


@pytest.mark.asyncio
async def test_server_request_marks_pending_and_resolved_approval():
    session = CodexHarnessSession(cwd="/tmp", context={}, on_change=AsyncMock())
    session.thread_id = "thread-1"
    session.session_key = "codex:thread-1"

    await session._handle_server_request(
        "item/commandExecution/requestApproval",
        {
            "command": "rm -rf /tmp/example",
            "cwd": "/tmp",
            "reason": "Need cleanup",
        },
        7,
    )
    session._recompute_phase()

    snapshot = session.snapshot()
    approval = snapshot["transcript"][0]
    assert snapshot["session_phase"] == "needs_attention"
    assert snapshot["pending_approval"] is True
    assert approval["display_kind"] == "approval"
    assert approval["is_pending"] is True
    assert approval["preview"] == "rm -rf /tmp/example\n/tmp\nNeed cleanup"

    session._mark_approval_resolved("7", "approve")
    session._pending_approvals.pop("7")
    session.thread_status = "idle"
    session._recompute_phase()

    resolved = session.snapshot()["transcript"][0]
    assert resolved["status"] == "resolved"
    assert resolved["is_pending"] is False


@pytest.mark.asyncio
async def test_manager_emits_sequenced_session_events():
    on_change = AsyncMock()
    manager = CodexHarnessManager(on_change=on_change)
    session = CodexHarnessSession(
        cwd="/tmp/project-root",
        context={"qualified_name": "vpittamp/nixos-config:main"},
        on_change=manager._emit_change,
    )
    session.session_key = "codex:thread-1"
    session.thread_id = "thread-1"
    session._upsert_thread_item({
        "type": "userMessage",
        "id": "user-1",
        "content": [{"type": "text", "text": "Inspect the repo", "text_elements": []}],
    })

    await session._notify_change({"type": "session_updated", "reason": "item/started"})

    on_change.assert_awaited_once()
    payload = on_change.await_args.args[0]
    assert payload["sequence"] == 1
    assert payload["type"] == "session_updated"
    assert payload["reason"] == "item/started"
    assert payload["session"]["session_key"] == "codex:thread-1"
    assert payload["session"]["session_revision"] == 1
    assert payload["session"]["title"] == "Inspect the repo"


@pytest.mark.asyncio
async def test_session_revision_increments_per_notified_change():
    on_change = AsyncMock()
    session = CodexHarnessSession(cwd="/tmp/project-root", context={}, on_change=on_change)
    session.thread_id = "thread-1"
    session.session_key = "codex:thread-1"

    session._upsert_thread_item({
        "type": "userMessage",
        "id": "user-1",
        "content": [{"type": "text", "text": "First prompt", "text_elements": []}],
    })
    await session._notify_change({"type": "session_updated", "reason": "userMessage"})

    first_snapshot = session.snapshot()

    session._append_agent_delta({
        "itemId": "agent-1",
        "delta": "Working",
    })
    await session._notify_change({"type": "session_updated", "reason": "item/agentMessage/delta"})

    second_snapshot = session.snapshot()

    assert first_snapshot["session_revision"] == 1
    assert second_snapshot["session_revision"] == 2
    assert second_snapshot["session_revision"] > first_snapshot["session_revision"]
