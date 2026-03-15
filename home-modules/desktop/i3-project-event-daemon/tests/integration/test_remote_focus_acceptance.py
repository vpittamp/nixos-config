"""Host-backed acceptance checks for daemon-to-daemon focus convergence."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
from dataclasses import dataclass
from typing import Any

import pytest


RUN_HOST_ACCEPTANCE = os.environ.get("I3PM_RUN_HOST_ACCEPTANCE", "").strip() == "1"
I3PM_BIN = os.environ.get("I3PM_BIN", "i3pm").strip() or "i3pm"
PREFERRED_REMOTE_HOST = os.environ.get("I3PM_REMOTE_HOST", "ryzen").strip().lower()
SOAK_ITERATIONS = max(2, int(os.environ.get("I3PM_REMOTE_FOCUS_ITERATIONS", "4") or "4"))

pytestmark = [
    pytest.mark.host_acceptance,
    pytest.mark.skipif(
        not RUN_HOST_ACCEPTANCE,
        reason="set I3PM_RUN_HOST_ACCEPTANCE=1 to run host-backed remote focus acceptance tests",
    ),
]


@dataclass(frozen=True)
class RemoteSessionTarget:
    session_key: str
    project_name: str
    focus_connection_key: str
    focus_target_host: str
    remote_window_id: int


def run_json(command: list[str], *, check: bool = True) -> dict[str, Any]:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout: {result.stdout}\n"
            f"stderr: {result.stderr}"
        )
    payload = (result.stdout or "").strip()
    if not payload:
        raise RuntimeError(f"command produced no JSON: {' '.join(command)}")
    return json.loads(payload)


def parse_connection_key(connection_key: str) -> tuple[str, str, int]:
    normalized = str(connection_key or "").strip()
    if "@" not in normalized:
        raise RuntimeError(f"invalid connection key: {normalized}")
    user, host_part = normalized.split("@", 1)
    if ":" in host_part:
        host, port_raw = host_part.rsplit(":", 1)
        port = int(port_raw or 22)
    else:
        host = host_part
        port = 22
    return user, host, port


def ssh_json(connection_key: str, remote_args: list[str]) -> dict[str, Any]:
    user, host, port = parse_connection_key(connection_key)
    remote_command = " ".join(shlex.quote(part) for part in remote_args)
    command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=3",
        "-p",
        str(port),
        f"{user}@{host}",
        f"bash -lc {shlex.quote(remote_command)}",
    ]
    return run_json(command)


def local_daemon_call(method: str, params: dict[str, Any]) -> dict[str, Any]:
    return run_json([
        I3PM_BIN,
        "daemon",
        "call",
        method,
        "--params-json",
        json.dumps(params),
        "--json",
    ])


def remote_focus_state(connection_key: str) -> dict[str, Any]:
    return ssh_json(connection_key, [I3PM_BIN, "daemon", "call", "focus.state", "--json"])


def remote_session_list(connection_key: str) -> dict[str, Any]:
    return ssh_json(connection_key, [I3PM_BIN, "session", "list", "--json"])


def select_remote_session_pair() -> tuple[str, RemoteSessionTarget, RemoteSessionTarget]:
    session_list = run_json([I3PM_BIN, "session", "list", "--json"])
    sessions = list(session_list.get("sessions", []) or [])
    grouped: dict[str, list[dict[str, Any]]] = {}
    for session in sessions:
        if not isinstance(session, dict):
            continue
        if str(session.get("focus_mode") or "").strip() != "remote_handoff":
            continue
        focus_connection_key = str(
            session.get("focus_connection_key")
            or session.get("connection_key")
            or ""
        ).strip()
        if not focus_connection_key:
            continue
        session_key = str(session.get("session_key") or "").strip()
        project_name = str(session.get("project_name") or session.get("project") or "").strip()
        if str(session.get("execution_mode") or "").strip() != "local":
            continue
        if not str(session.get("connection_key") or "").strip().startswith("local@"):
            continue
        if not str(session.get("tmux_session") or "").strip():
            continue
        if not str(session.get("tmux_window") or "").strip():
            continue
        if not (session_key and project_name):
            continue
        grouped.setdefault(focus_connection_key, []).append({
            "session_key": session_key,
            "project_name": project_name,
            "focus_connection_key": focus_connection_key,
            "focus_target_host": str(session.get("focus_target_host") or "").strip().lower(),
        })

    ordered_groups = sorted(
        grouped.items(),
        key=lambda item: (
            item[1][0]["focus_target_host"] != PREFERRED_REMOTE_HOST,
            item[1][0]["focus_target_host"],
            item[0],
        ),
    )
    for connection_key, target_specs in ordered_groups:
        remote_session_payload = remote_session_list(connection_key)
        remote_sessions = {
            str(session.get("session_key") or "").strip(): session
            for session in remote_session_payload.get("sessions", [])
            if isinstance(session, dict)
        }
        unique_targets = []
        seen = set()
        for spec in target_specs:
            session_key = str(spec["session_key"] or "").strip()
            remote_session = remote_sessions.get(session_key)
            if session_key in seen or not isinstance(remote_session, dict):
                continue
            remote_window_id = int(remote_session.get("window_id") or 0)
            if str(remote_session.get("focus_mode") or "").strip() != "local" or remote_window_id <= 0:
                continue
            seen.add(session_key)
            unique_targets.append(
                RemoteSessionTarget(
                    session_key=session_key,
                    project_name=str(spec["project_name"] or "").strip(),
                    focus_connection_key=str(spec["focus_connection_key"] or "").strip(),
                    focus_target_host=str(spec["focus_target_host"] or "").strip(),
                    remote_window_id=remote_window_id,
                )
            )
        if len(unique_targets) < 2:
            continue
        return connection_key, unique_targets[0], unique_targets[1]
    pytest.skip("no remote host with at least two focusable AI sessions is currently available")


def assert_remote_session_converged(target: RemoteSessionTarget) -> None:
    focus_state = remote_focus_state(target.focus_connection_key)
    assert focus_state["current_ai_session_key"] == target.session_key
    assert int(focus_state["focused_window_id"]) == target.remote_window_id

    session_list = remote_session_list(target.focus_connection_key)
    current_sessions = [
        session for session in session_list.get("sessions", [])
        if isinstance(session, dict) and bool(session.get("is_current_window", False))
    ]
    assert len(current_sessions) == 1
    assert str(current_sessions[0].get("session_key") or "") == target.session_key


def restore_remote_session(session_key: str, connection_key: str) -> None:
    if not session_key:
        return
    local_daemon_call("session.focus", {"session_key": session_key})
    assert remote_focus_state(connection_key)["current_ai_session_key"] == session_key


def test_remote_session_focus_converges_over_ssh() -> None:
    connection_key, first_target, second_target = select_remote_session_pair()
    original_remote_state = remote_focus_state(connection_key)
    original_session_key = str(original_remote_state.get("current_ai_session_key") or "").strip()
    restore_target = first_target
    if original_session_key == second_target.session_key:
        restore_target = second_target
    elif original_session_key == first_target.session_key:
        restore_target = first_target

    target = second_target if restore_target.session_key == first_target.session_key else first_target

    try:
        result = local_daemon_call("session.focus", {"session_key": target.session_key})
        assert result["success"] is True
        assert result["verification"]["success"] is True
        assert result["current_ai_session_key_after"] == target.session_key
        assert int(result["focused_window_id_after"]) == target.remote_window_id
        assert_remote_session_converged(target)
    finally:
        restore_remote_session(restore_target.session_key, connection_key)


def test_remote_window_focus_converges_over_ssh() -> None:
    connection_key, first_target, second_target = select_remote_session_pair()
    original_remote_state = remote_focus_state(connection_key)
    original_session_key = str(original_remote_state.get("current_ai_session_key") or "").strip()
    restore_target = first_target
    if original_session_key == second_target.session_key:
        restore_target = second_target
    elif original_session_key == first_target.session_key:
        restore_target = first_target

    target = second_target if restore_target.session_key == first_target.session_key else first_target

    try:
        result = local_daemon_call("window.focus", {
            "window_id": target.remote_window_id,
            "project_name": target.project_name,
            "target_variant": "ssh",
            "connection_key": target.focus_connection_key,
        })
        assert result["success"] is True
        assert result["verification"]["success"] is True
        assert int(result["focused_window_id_after"]) == target.remote_window_id
        assert remote_focus_state(target.focus_connection_key)["focused_window_id"] == target.remote_window_id
    finally:
        restore_remote_session(restore_target.session_key, connection_key)


def test_remote_session_focus_soak_converges_every_iteration() -> None:
    connection_key, first_target, second_target = select_remote_session_pair()
    original_remote_state = remote_focus_state(connection_key)
    original_session_key = str(original_remote_state.get("current_ai_session_key") or "").strip()
    restore_target = first_target
    if original_session_key == second_target.session_key:
        restore_target = second_target
    elif original_session_key == first_target.session_key:
        restore_target = first_target

    sequence = [first_target, second_target] * SOAK_ITERATIONS
    try:
        for target in sequence:
            result = local_daemon_call("session.focus", {"session_key": target.session_key})
            assert result["success"] is True
            assert result["verification"]["success"] is True
            assert result["current_ai_session_key_after"] == target.session_key
            assert int(result["focused_window_id_after"]) == target.remote_window_id
            assert_remote_session_converged(target)
    finally:
        restore_remote_session(restore_target.session_key, connection_key)
