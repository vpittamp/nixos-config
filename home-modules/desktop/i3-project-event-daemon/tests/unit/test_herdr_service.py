import asyncio
import importlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

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

herdr_service_module = importlib.import_module(
    "i3_project_daemon.services.herdr_service"
)

HERDR_EVENT_SUBSCRIPTION_TYPES = herdr_service_module.HERDR_EVENT_SUBSCRIPTION_TYPES
HerdrService = herdr_service_module.HerdrService


@pytest.mark.asyncio
async def test_herdr_service_invalidates_and_coalesces_notifications():
    invalidations = 0
    notifications = []

    async def notify_state_change(event_type):
        notifications.append(event_type)

    def invalidate_snapshot_cache():
        nonlocal invalidations
        invalidations += 1

    service = HerdrService(
        notify_state_change=notify_state_change,
        invalidate_snapshot_cache=invalidate_snapshot_cache,
        notify_delay=0.01,
    )

    await service.handle_subscription_event({"event": "pane.focused"})
    await service.handle_subscription_event({"event": "pane.agent_detected"})
    await service.handle_subscription_event({"event": "workspace.updated"})
    await asyncio.sleep(0.03)

    assert invalidations == 3
    assert service.local_herdr_generation == 3
    assert notifications == ["ai_session_herdr_changed"]


def test_herdr_service_subscription_payload_covers_local_agent_events():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    payload = service.event_subscribe_payload()
    subscriptions = {
        subscription["type"]
        for subscription in payload["params"]["subscriptions"]
    }

    assert payload["id"] == "i3pm-herdr-events"
    assert payload["method"] == "events.subscribe"
    assert subscriptions == set(HERDR_EVENT_SUBSCRIPTION_TYPES)
    assert "workspace.updated" in subscriptions
    assert "pane.agent_detected" in subscriptions


def test_herdr_service_tracks_remote_generations_by_host():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    assert service.remote_generation_for("ryzen") == 0
    assert service.bump_remote_generation("Ryzen") == 1
    assert service.bump_remote_generation("ryzen") == 2

    assert service.generations_snapshot() == {
        "local_herdr_generation": 0,
        "remote_herdr_generation": {"ryzen": 2},
    }


def test_herdr_service_owns_snapshot_cache_with_local_and_remote_ttls():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        snapshot_cache_ttl=1.0,
        remote_snapshot_cache_ttl=10.0,
    )
    snapshot = {"sessions": [{"pane_id": "a"}]}

    returned = service.store_snapshot(snapshot, now=100.0)
    returned["sessions"][0]["pane_id"] = "mutated"
    snapshot["sessions"][0]["pane_id"] = "source-mutated"

    local_cached = service.cached_snapshot(now=100.5, has_remote_targets=False)
    remote_cached = service.cached_snapshot(now=105.0, has_remote_targets=True)

    assert local_cached == {"sessions": [{"pane_id": "a"}]}
    assert remote_cached == {"sessions": [{"pane_id": "a"}]}
    assert service.cached_snapshot(now=101.1, has_remote_targets=False) is None
    assert service.cached_snapshot(now=110.1, has_remote_targets=True) is None


def test_herdr_service_invalidates_snapshot_cache():
    invalidations = 0

    def external_invalidate():
        nonlocal invalidations
        invalidations += 1

    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=external_invalidate,
    )
    service.store_snapshot({"sessions": []}, now=100.0)

    service.invalidate_snapshot_cache()

    assert service.snapshot_cache == {}
    assert service.snapshot_cache_time == 0.0
    assert invalidations == 1


def test_herdr_service_applies_remote_focus_cache():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    service.snapshot_cache = {
        "sessions": [
            {
                "session_key": "herdr:ryzen:pane:a",
                "herdr_host": "ryzen",
                "pane_id": "a",
                "focused": True,
                "connection_key": "vpittamp@ryzen:22",
            },
            {
                "session_key": "herdr:ryzen:pane:b",
                "herdr_host": "ryzen",
                "pane_id": "b",
                "focused": False,
                "connection_key": "vpittamp@ryzen:22",
            },
        ],
        "panes": [
            {"herdr_host": "ryzen", "pane_id": "a", "focused": True},
            {"herdr_host": "ryzen", "pane_id": "b", "focused": False},
        ],
        "remote_snapshots": [{
            "host": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
            "sessions": [
                {"pane_id": "a", "focused": True},
                {"pane_id": "b", "focused": False},
            ],
        }],
    }
    service.snapshot_cache_time = 100.0

    result = service.apply_remote_focus_cache(
        target={
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
        },
        pane_id="b",
        normalize_connection_key=lambda value: value,
        now=200.0,
    )

    assert result == {
        "updated": True,
        "focused_session_key": "herdr:ryzen:pane:b",
        "connection_key": "vpittamp@ryzen:22",
    }
    assert service.snapshot_cache_time == 200.0
    assert service.snapshot_cache["sessions"][0]["focused"] is False
    assert service.snapshot_cache["sessions"][1]["focused"] is True
    assert service.snapshot_cache["sessions"][1]["is_current_window"] is True
    assert service.snapshot_cache["panes"][0]["focused"] is False
    assert service.snapshot_cache["panes"][1]["focused"] is True
    remote_sessions = service.snapshot_cache["remote_snapshots"][0]["sessions"]
    assert remote_sessions[0]["focused"] is False
    assert remote_sessions[1]["focused"] is True


def test_herdr_service_loads_remote_targets_from_env(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    monkeypatch.setenv("USER", "vpittamp")
    monkeypatch.setenv("I3PM_HERDR_REMOTE_TARGETS", json.dumps([
        {"host": "Ryzen", "sshTarget": "ryzen"},
        {"host": "ryzen", "ssh_target": "ryzen"},
        {"ssh_target": "other-user@desktop:2200", "connectionKey": "custom@desktop:22"},
        {"ssh_target": ""},
        "invalid",
    ]))

    targets = service.load_remote_targets(
        parse_remote_target=lambda value: (
            value.split("@", 1)[0] if "@" in value else "",
            value.rsplit("@", 1)[-1].split(":", 1)[0],
            int(value.rsplit(":", 1)[-1]) if ":" in value else 22,
        ),
        normalize_connection_key=lambda value: value.strip().lower(),
    )

    assert targets == [
        {
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
        },
        {
            "host": "desktop",
            "ssh_target": "other-user@desktop:2200",
            "connection_key": "custom@desktop:22",
        },
    ]
    assert service.load_remote_targets(
        parse_remote_target=lambda value: ("", value, 22),
        normalize_connection_key=lambda value: value,
    ) == targets


def test_herdr_service_loads_remote_targets_from_file(tmp_path, monkeypatch):
    target_file = tmp_path / "targets.json"
    target_file.write_text(json.dumps([
        {"ssh_target": "vpittamp@ryzen:2222"},
    ]))
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    monkeypatch.delenv("I3PM_HERDR_REMOTE_TARGETS", raising=False)
    monkeypatch.setenv("I3PM_HERDR_REMOTE_TARGETS_FILE", str(target_file))

    targets = service.load_remote_targets(
        parse_remote_target=lambda value: ("vpittamp", "ryzen", 2222),
        normalize_connection_key=lambda value: value,
    )

    assert targets == [{
        "host": "ryzen",
        "ssh_target": "vpittamp@ryzen:2222",
        "connection_key": "vpittamp@ryzen:2222",
    }]


def test_herdr_service_resolves_remote_action_target_from_params():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }

    assert service.resolve_remote_action_target(
        {"host": "ryzen"},
        targets=[target],
        parse_remote_target=lambda value: ("vpittamp", value, 22),
        normalize_connection_key=lambda value: value,
    ) == target

    assert service.resolve_remote_action_target(
        {"ssh_target": "devbox"},
        targets=[],
        parse_remote_target=lambda value: ("", value, 22),
        normalize_connection_key=lambda value: value,
    ) == {
        "host": "devbox",
        "ssh_target": "devbox",
        "connection_key": "vpittamp@devbox:22",
    }


def test_herdr_service_normalizes_result_arrays_and_status_labels():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    assert service.result_array({
        "result": {
            "panes": [
                {"pane_id": "a"},
                "invalid",
                {"pane_id": "b"},
            ],
        },
    }, "panes") == [{"pane_id": "a"}, {"pane_id": "b"}]
    assert service.worktree_result_array({
        "result": {
            "source": {
                "repo_key": "vpittamp/nixos-config",
                "repo_name": "nixos-config",
                "repo_root": "/repo",
            },
            "worktrees": [{
                "path": "/repo/main",
                "branch": "main",
                "open_workspace_id": "workspace-a",
            }],
        },
    }) == [{
        "path": "/repo/main",
        "branch": "main",
        "open_workspace_id": "workspace-a",
        "workspace_id": "workspace-a",
        "repo_key": "vpittamp/nixos-config",
        "repo_name": "nixos-config",
        "repo_root": "/repo",
        "checkout_path": "/repo/main",
        "branch_label": "main",
    }]

    assert service.normalize_agent_status("NeedsInput") == "unknown"
    assert service.normalize_agent_status("NeedsInput", preserve_raw=True) == "NeedsInput"
    assert service.agent_status_state("NeedsInput") == "blocked"
    assert service.agent_status_state("tool-running") == "working"
    assert service.agent_status_rank("NeedsInput") > service.agent_status_rank("working")
    assert service.normalize_state_labels({
        "NeedsInput": "waiting",
        "working": "running",
        "mystery": "ignored",
        "done": "",
    }) == {
        "blocked": "waiting",
        "working": "running",
    }


def test_herdr_service_annotates_rows_with_host_context():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    assert service.annotate_rows(
        [{"pane_id": "a"}],
        host="Ryzen",
        execution_mode="ssh",
        connection_key="VPITTAMP@RYZEN:22",
        ssh_target="ryzen",
        is_remote=True,
        normalize_connection_key=lambda value: value.lower(),
    ) == [{
        "pane_id": "a",
        "host_name": "ryzen",
        "herdr_host": "ryzen",
        "target_host": "ryzen",
        "execution_mode": "ssh",
        "connection_key": "vpittamp@ryzen:22",
        "ssh_target": "ryzen",
        "remote_target": "ryzen",
        "is_remote_herdr": True,
        "is_current_host": False,
    }]


def test_herdr_service_normalizes_repo_urls_and_effective_cwd(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    assert service.normalize_repo_url("git@github.com:PittampalliOrg/workflow-builder.git") == (
        "PittampalliOrg/workflow-builder"
    )
    assert service.normalize_repo_url("https://github.com/vpittamp/nixos-config.git") == (
        "vpittamp/nixos-config"
    )

    checked = []

    def fake_is_worktree(path, *, ssh_target=""):
        checked.append((path, ssh_target))
        return path == "/repo/foreground"

    monkeypatch.setattr(service, "path_is_git_worktree", fake_is_worktree)

    assert service.effective_cwd(
        {"cwd": "/repo/cwd", "foreground_cwd": "/repo/foreground"},
        ssh_target="ryzen",
    ) == "/repo/foreground"
    assert checked == [("/repo/foreground", "ryzen")]


def test_herdr_service_git_space_metadata_is_cached(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    calls = []

    responses = {
        ("rev-parse", "--is-inside-work-tree"): "true",
        ("rev-parse", "--show-toplevel"): "/repo/workflow-builder/main",
        ("rev-parse", "--git-common-dir"): "../.bare",
        ("config", "--get", "remote.origin.url"): "git@github.com:PittampalliOrg/workflow-builder.git",
        ("branch", "--show-current"): "feature/focus",
    }

    def fake_git_run(path, args, *, ssh_target="", timeout=0.75):
        calls.append((path, tuple(args), ssh_target, timeout))
        return responses.get(tuple(args), "")

    monkeypatch.setattr(service, "git_run", fake_git_run)

    metadata = service.git_space_metadata(
        "/repo/workflow-builder/main",
        normalize_connection_key=lambda value: value,
    )
    cached = service.git_space_metadata(
        "/repo/workflow-builder/main",
        normalize_connection_key=lambda value: value,
    )

    assert metadata == {
        "repo_key": "PittampalliOrg/workflow-builder",
        "repo_name": "workflow-builder",
        "repo_root": "/repo/workflow-builder/main/../.bare",
        "checkout_path": "/repo/workflow-builder/main",
        "is_linked_worktree": False,
        "branch_label": "feature/focus",
    }
    assert cached == metadata
    assert [call[1] for call in calls].count(("rev-parse", "--show-toplevel")) == 1


def test_herdr_service_normalizes_local_and_remote_sessions(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    monkeypatch.setattr(
        service,
        "effective_cwd",
        lambda row, *, ssh_target="": str(row.get("foreground_cwd") or row.get("cwd") or ""),
    )
    monkeypatch.setattr(
        service,
        "git_space_metadata",
        lambda path, *, ssh_target="", normalize_connection_key: {
            "repo_key": "PittampalliOrg/workflow-builder",
            "repo_name": "workflow-builder",
            "repo_root": "/repo",
            "checkout_path": path,
            "branch_label": "feature/service",
        } if path else {},
    )

    def project_for_cwd(path):
        return {
            "project_name": "PittampalliOrg/workflow-builder:main" if path else "global",
            "project_path": path,
        }

    local_rows = service.normalize_sessions(
        {
            "agents": [{
                "pane_id": "pane-a",
                "agent": "codex",
                "agent_status": "NeedsInput",
                "focused": True,
            }],
            "panes": [{
                "pane_id": "pane-a",
                "workspace_id": "workspace-a",
                "tab_id": "tab-a",
                "cwd": "/repo/main",
                "foreground_cwd": "/repo/main",
            }, {
                "pane_id": "plain",
                "workspace_id": "workspace-a",
            }],
        },
        local_host="thinkpad",
        normalize_connection_key=lambda value: value.lower(),
        project_for_cwd=project_for_cwd,
    )

    assert len(local_rows) == 1
    assert local_rows[0]["session_key"] == "herdr:pane:pane-a"
    assert local_rows[0]["agent_status"] == "unknown"
    assert local_rows[0]["focus_target"] == {
        "method": "herdr.pane.focus",
        "params": {"pane_id": "pane-a"},
    }
    assert local_rows[0]["repo_key"] == "PittampalliOrg/workflow-builder"

    remote_row = service.normalize_session_row(
        {
            "pane_id": "pane-r",
            "workspace_id": "workspace-r",
            "agent": "claude",
            "agent_status": "NeedsInput",
            "focused": True,
            "cwd": "/repo/remote",
        },
        remote_target={
            "host": "Ryzen",
            "ssh_target": "ryzen",
            "connection_key": "VPITTAMP@RYZEN:22",
        },
        local_host="thinkpad",
        normalize_connection_key=lambda value: value.lower(),
        project_for_cwd=project_for_cwd,
    )

    assert remote_row["session_key"] == "herdr:ryzen:pane:pane-r"
    assert remote_row["agent_status"] == "NeedsInput"
    assert remote_row["execution_mode"] == "ssh"
    assert remote_row["is_current_host"] is False
    assert remote_row["focus_target"] == {
        "method": "herdr.remote.pane.focus",
        "params": {
            "pane_id": "pane-r",
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
            "app_name": "herdr",
        },
    }


@pytest.mark.asyncio
async def test_herdr_service_builds_remote_snapshot(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "VPITTAMP@RYZEN:22",
    }

    payloads = {
        ("status", "--json"): {"success": True, "result": {"protocol": 13}},
        ("agent", "list"): {
            "success": True,
            "result": {
                "agents": [{
                    "pane_id": "pane-r",
                    "workspace_id": "workspace-r",
                    "agent": "codex",
                    "agent_status": "NeedsInput",
                    "focused": True,
                }],
            },
        },
        ("pane", "list"): {
            "success": True,
            "result": {
                "panes": [{
                    "pane_id": "pane-r",
                    "workspace_id": "workspace-r",
                    "cwd": "/repo/remote",
                }],
            },
        },
        ("workspace", "list"): {
            "success": True,
            "result": {"workspaces": [{"workspace_id": "workspace-r", "focused": True}]},
        },
        ("tab", "list"): {"success": True, "result": {"tabs": []}},
        ("worktree", "list"): {"success": True, "result": {"worktrees": []}},
    }

    async def fake_run_ssh_json(_target, args, timeout=2.5):
        payload = dict(payloads[tuple(args)])
        payload["command"] = ["ssh", "ryzen", "herdr", *args]
        return payload

    monkeypatch.setattr(service, "run_ssh_json", fake_run_ssh_json)
    monkeypatch.setattr(
        service,
        "effective_cwd",
        lambda row, *, ssh_target="": str(row.get("cwd") or ""),
    )
    monkeypatch.setattr(
        service,
        "git_space_metadata",
        lambda path, *, ssh_target="", normalize_connection_key: {},
    )

    snapshot = await service.remote_snapshot(
        target,
        local_host="thinkpad",
        normalize_connection_key=lambda value: value.lower(),
        project_for_cwd=lambda path: {"project_name": "global", "project_path": path},
    )

    assert snapshot["success"] is True
    assert snapshot["remote"] is True
    assert snapshot["herdr_generation"] == 1
    assert snapshot["agents"][0]["herdr_host"] == "ryzen"
    assert snapshot["agents"][0]["connection_key"] == "vpittamp@ryzen:22"
    assert snapshot["sessions"][0]["session_key"] == "herdr:ryzen:pane:pane-r"
    assert snapshot["sessions"][0]["agent_status"] == "NeedsInput"
    assert snapshot["sessions"][0]["focus_target"]["method"] == "herdr.remote.pane.focus"
    assert snapshot["errors"] == []


@pytest.mark.asyncio
async def test_herdr_service_builds_local_snapshot(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    service.bump_local_generation()

    payloads = {
        ("status", "--json"): {"success": True, "result": {"protocol": 13}},
        ("agent", "list"): {
            "success": True,
            "result": {
                "agents": [{
                    "pane_id": "pane-l",
                    "workspace_id": "workspace-l",
                    "agent": "codex",
                    "agent_status": "blocked",
                    "focused": True,
                    "cwd": "/repo/local",
                }],
            },
        },
        ("pane", "list"): {
            "success": True,
            "result": {
                "panes": [{
                    "pane_id": "pane-l",
                    "workspace_id": "workspace-l",
                    "cwd": "/repo/local",
                }],
            },
        },
        ("workspace", "list"): {
            "success": True,
            "result": {"workspaces": [{"workspace_id": "workspace-l"}]},
        },
        ("tab", "list"): {"success": True, "result": {"tabs": []}},
        ("worktree", "list"): {"success": True, "result": {"worktrees": []}},
    }

    async def fake_run_json(args, timeout=2.0):
        payload = dict(payloads[tuple(args)])
        payload["command"] = ["herdr", *args]
        return payload

    monkeypatch.setattr(service, "run_json", fake_run_json)
    monkeypatch.setattr(
        service,
        "effective_cwd",
        lambda row, *, ssh_target="": str(row.get("cwd") or ""),
    )
    monkeypatch.setattr(
        service,
        "git_space_metadata",
        lambda path, *, ssh_target="", normalize_connection_key: {},
    )

    snapshot = await service.local_snapshot(
        local_host="ThinkPad",
        normalize_connection_key=lambda value: value.lower(),
        project_for_cwd=lambda path: {"project_name": "global", "project_path": path},
    )

    assert snapshot["success"] is True
    assert snapshot["herdr_generation"] == 1
    assert snapshot["local_herdr_generation"] == 1
    assert snapshot["agents"][0]["herdr_host"] == "thinkpad"
    assert snapshot["agents"][0]["connection_key"] == "local@thinkpad"
    assert snapshot["sessions"][0]["session_key"] == "herdr:pane:pane-l"
    assert snapshot["sessions"][0]["focus_target"] == {
        "method": "herdr.pane.focus",
        "params": {"pane_id": "pane-l"},
    }
    assert snapshot["errors"] == []


@pytest.mark.asyncio
async def test_herdr_service_remote_snapshot_reports_status_failure(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    async def fake_run_ssh_json(_target, args, timeout=2.5):
        if args == ["status", "--json"]:
            return {
                "success": False,
                "error": "timeout",
                "command": ["ssh", "ryzen", "herdr", *args],
                "returncode": None,
            }
        return {"success": True, "result": {}, "command": ["ssh", "ryzen", "herdr", *args]}

    monkeypatch.setattr(service, "run_ssh_json", fake_run_ssh_json)

    snapshot = await service.remote_snapshot(
        {
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
        },
        local_host="thinkpad",
        normalize_connection_key=lambda value: value,
        project_for_cwd=lambda path: {"project_name": "global", "project_path": path},
    )

    assert snapshot["success"] is False
    assert snapshot["herdr_generation"] == 0
    assert snapshot["sessions"] == []
    assert snapshot["errors"] == [{
        "remote": True,
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
        "command": ["ssh", "ryzen", "herdr", "status", "--json"],
        "error": "timeout",
        "returncode": None,
    }]


@pytest.mark.asyncio
async def test_herdr_service_runs_local_json_command(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    calls = []

    def fake_run(command, **kwargs):
        calls.append((command, kwargs))
        return subprocess.CompletedProcess(
            command,
            0,
            stdout='{"success":true,"result":{"ok":true}}\n',
            stderr="",
        )

    monkeypatch.setattr(herdr_service_module.shutil, "which", lambda name: f"/bin/{name}")
    monkeypatch.setattr(herdr_service_module.subprocess, "run", fake_run)

    result = await service.run_json(["status", "--json"], timeout=1.5)

    assert result["success"] is True
    assert result["result"] == {"ok": True}
    assert result["command"] == ["herdr", "status", "--json"]
    assert calls[0][0] == ["herdr", "status", "--json"]
    assert calls[0][1]["timeout"] == 1.5


@pytest.mark.asyncio
async def test_herdr_service_reports_missing_local_binary(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    monkeypatch.setattr(herdr_service_module.shutil, "which", lambda _name: None)

    result = await service.run_json(["status", "--json"])

    assert result == {
        "success": False,
        "error": "herdr_not_found",
        "command": ["herdr", "status", "--json"],
    }


@pytest.mark.asyncio
async def test_herdr_service_runs_remote_json_command(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    calls = []

    def fake_run(command, **kwargs):
        calls.append((command, kwargs))
        return subprocess.CompletedProcess(
            command,
            0,
            stdout='{"success":true,"result":{"agents":[]}}\n',
            stderr="",
        )

    monkeypatch.setattr(herdr_service_module.shutil, "which", lambda name: f"/bin/{name}")
    monkeypatch.setattr(herdr_service_module.subprocess, "run", fake_run)

    result = await service.run_ssh_json(
        {
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
        },
        ["agent", "list"],
        timeout=1.25,
    )

    assert result["success"] is True
    assert result["result"] == {"agents": []}
    assert result["command"] == ["ssh", "ryzen", "herdr", "agent", "list"]
    assert result["herdr_host"] == "ryzen"
    assert result["ssh_target"] == "ryzen"
    assert result["connection_key"] == "vpittamp@ryzen:22"
    assert calls[0][0][-3:] == ["herdr", "agent", "list"]
    assert calls[0][0][:2] == ["ssh", "-o"]
    assert calls[0][1]["timeout"] == 1.25


@pytest.mark.asyncio
async def test_herdr_service_reports_remote_transport_errors(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    missing_target = await service.run_ssh_json({}, ["agent", "list"])
    assert missing_target == {
        "success": False,
        "error": "missing_ssh_target",
        "command": ["ssh", "", "herdr", "agent", "list"],
    }

    monkeypatch.setattr(herdr_service_module.shutil, "which", lambda _name: None)
    missing_ssh = await service.run_ssh_json(
        {"ssh_target": "ryzen"},
        ["agent", "list"],
    )
    assert missing_ssh == {
        "success": False,
        "error": "ssh_not_found",
        "command": ["ssh", "ryzen", "herdr", "agent", "list"],
    }
