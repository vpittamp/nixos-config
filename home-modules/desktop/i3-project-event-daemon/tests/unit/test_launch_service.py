"""Unit tests for launch persistence service."""

from __future__ import annotations

import importlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict


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


launch_service_module = importlib.import_module("i3_project_daemon.services.launch_service")

LaunchService = launch_service_module.LaunchService


def load_json_file(path: Path) -> Dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        return payload if isinstance(payload, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def parse_context_target_host(value: Any) -> str:
    text = str(value or "").strip()
    if "::host::" in text:
        return text.rsplit("::host::", 1)[1]
    if "::ssh::" in text:
        return text.rsplit("::ssh::", 1)[1]
    if "::local::" in text:
        return text.rsplit("::local::", 1)[1].removeprefix("local@")
    return ""


def make_service(tmp_path: Path) -> LaunchService:
    return LaunchService(
        runtime_dir=lambda: tmp_path,
        load_json_file=load_json_file,
        normalize_target_host=lambda value: str(value or "").strip().lower(),
        parse_context_target_host=parse_context_target_host,
        transport_kind_for_target_host=lambda value: "local_process" if str(value or "") == "thinkpad" else "ssh",
        local_host_alias=lambda: "thinkpad",
    )


def test_write_status_persists_normalized_launch_payload(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    result = service.write_status(
        launch_id="launch-1",
        status="running",
        spec={
            "project_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::host::ryzen",
            "connection_key": "vpittamp@ryzen:22",
            "terminal_anchor_id": "anchor-1",
            "launch_kind": "open_project_terminal",
        },
        reason="window_bound",
        extra={"window_id": 12},
    )

    assert result["launch_id"] == "launch-1"
    assert result["status"] == "running"
    assert result["target_host"] == "ryzen"
    assert result["transport_kind"] == "ssh"
    assert result["window_id"] == 12
    assert service.read_status("launch-1")["reason"] == "window_bound"


def test_list_statuses_returns_newest_first_and_honors_limit(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    service.write_status(launch_id="launch-a", status="queued")
    service.write_status(launch_id="launch-b", status="running")

    statuses = service.list_statuses(limit=1)

    assert len(statuses) == 1
    assert statuses[0]["launch_id"] == "launch-b"


def test_write_local_spec_persists_spec_and_initial_status(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    spec_path = service.write_local_spec(
        spec={
            "launch": {"launch_id": "launch-local"},
            "project_name": "vpittamp/nixos-config:main",
            "target_host": "thinkpad",
            "transport_kind": "local_process",
            "connection_key": "local@thinkpad",
            "project_directory": "/repo",
            "local_project_directory": "/repo",
            "terminal_anchor_id": "anchor-local",
            "tmux_session_name": "i3pm-main",
            "terminal_role": "project-main",
            "terminal_launch": {"mode": "managed_project_terminal"},
            "environment": {"I3PM_CONTEXT_KEY": "ctx"},
            "launch_transport": "local_helper",
        },
        launch_kind="open_project_terminal",
    )

    payload = load_json_file(spec_path)
    status = service.read_status("launch-local")

    assert payload["launch_id"] == "launch-local"
    assert payload["terminal_role"] == "project-main"
    assert payload["status_file"] == str(service.status_file("launch-local"))
    assert status["status"] == "queued"
    assert status["reason"] == "queued"
    assert status["target_host"] == "thinkpad"


def test_write_remote_spec_persists_remote_payload(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    spec_path = service.write_remote_spec(
        spec={
            "launch": {"launch_id": "launch-remote"},
            "project_name": "vpittamp/nixos-config:main",
            "context_key": "vpittamp/nixos-config:main::host::ryzen",
            "transport_kind": "ssh",
            "connection_key": "vpittamp@ryzen:22",
            "project_directory": "/srv/repo",
            "local_project_directory": "/home/repo",
            "terminal_anchor_id": "anchor-remote",
            "tmux_session_name": "i3pm-remote",
            "terminal_launch": {"mode": "managed_project_terminal"},
            "environment": {"I3PM_CONTEXT_KEY": "ctx"},
            "launch_transport": "remote_helper",
        },
        launch_kind="open_project_terminal",
    )

    payload = load_json_file(spec_path)
    status = service.read_status("launch-remote")

    assert payload["target_host"] == "ryzen"
    assert payload["launch_transport"] == "remote_helper"
    assert payload["status_file"] == str(service.status_file("launch-remote"))
    assert status["connection_key"] == "vpittamp@ryzen:22"
    assert status["launch_kind"] == "open_project_terminal"
