import asyncio
import importlib
import importlib.util
import json
import logging
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


def test_herdr_service_status_subscription_payload_targets_one_pane():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    payload = service.status_event_subscribe_payload("pane-a")

    assert payload == {
        "id": "i3pm-herdr-status-pane-a",
        "method": "events.subscribe",
        "params": {
            "subscriptions": [{
                "type": "pane.agent_status_changed",
                "pane_id": "pane-a",
            }],
        },
    }


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


def test_herdr_service_resolves_project_for_cwd_with_worktree_fallback():
    def resolve_worktree(path):
        if path == "/repo/main":
            return {
                "qualified_name": "vpittamp/nixos-config:main",
                "path": "/repo/main",
            }
        return None

    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        normalize_project_path=lambda path: str(path or "").rstrip("/") or None,
        resolve_worktree_for_path=resolve_worktree,
    )

    assert service.project_for_cwd("/repo/main") == {
        "project_name": "vpittamp/nixos-config:main",
        "project_path": "/repo/main",
    }
    assert service.project_for_cwd("/tmp/work/") == {
        "project_name": "global",
        "project_path": "/tmp/work",
    }


@pytest.mark.asyncio
async def test_herdr_service_remote_proxy_event_payload_updates_cached_remote_sessions():
    notifications = []
    invalidations = 0

    async def notify_state_change(event_type):
        notifications.append(event_type)

    def invalidate_snapshot_cache():
        nonlocal invalidations
        invalidations += 1

    service = HerdrService(
        notify_state_change=notify_state_change,
        invalidate_snapshot_cache=invalidate_snapshot_cache,
        notify_delay=0.0,
    )
    service.store_snapshot(
        {
            "sessions": [
                {"session_key": "local", "pane_id": "local-a", "is_current_host": True},
                {
                    "session_key": "herdr:ryzen:pane:remote-a",
                    "pane_id": "remote-a",
                    "herdr_host": "ryzen",
                    "focused": True,
                    "connection_key": "vpittamp@ryzen:22",
                },
            ],
            "remote_snapshots": [
                {
                    "host": "ryzen",
                    "ssh_target": "ryzen",
                    "connection_key": "vpittamp@ryzen:22",
                    "sessions": [{"session_key": "herdr:ryzen:pane:remote-a"}],
                }
            ],
        },
        now=100.0,
    )

    await service.handle_remote_proxy_event(
        {"host": "ryzen", "ssh_target": "ryzen", "connection_key": "vpittamp@ryzen:22"},
        {
            "schema_version": "i3pm.herdr_proxy.event.v1",
            "protocol_version": 1,
            "event_type": "herdr.changed",
            "generation": 7,
            "snapshot_version": 7,
            "changed_keys": ["focus_state", "active_ai_sessions", "herdr"],
            "payload": {
                "active_ai_sessions": [
                    {
                        "session_key": "herdr:pane:remote-b",
                        "pane_id": "remote-b",
                        "agent": "codex",
                        "focused": True,
                        "is_current_window": True,
                        "host_name": "ryzen",
                        "connection_key": "local@ryzen",
                        "execution_mode": "local",
                        "is_current_host": True,
                        "close_target": {
                            "method": "herdr.pane.close",
                            "params": {"pane_id": "remote-b"},
                        },
                    }
                ],
                "herdr": {
                    "herdr_generation": 42,
                    "local_herdr_generation": 42,
                    "status": {"server": {"running": True}},
                },
            },
        },
    )
    await asyncio.sleep(0)

    assert service.remote_generation_for("ryzen") == 42
    assert service.remote_proxy_event_generation_for("ryzen") == 7
    assert invalidations == 0
    assert notifications == ["ai_session_herdr_changed"]
    assert [row["session_key"] for row in service.snapshot_cache["sessions"]] == [
        "herdr:ryzen:pane:remote-b",
        "local",
    ]
    remote_session = service.snapshot_cache["sessions"][0]
    assert remote_session["execution_mode"] == "ssh"
    assert remote_session["connection_key"] == "vpittamp@ryzen:22"
    assert remote_session["is_remote_herdr"] is True
    assert remote_session["is_current_host"] is False
    assert remote_session["focus_target"] == {
        "method": "herdr.remote.pane.focus",
        "params": {
            "pane_id": "remote-b",
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
            "app_name": "herdr-ryzen",
        },
    }
    assert remote_session["close_target"] == {}
    assert service.snapshot_cache["remote_snapshots"][0]["sessions"][0]["session_key"] == "herdr:ryzen:pane:remote-b"

    await service.handle_remote_proxy_event(
        {"host": "ryzen", "ssh_target": "ryzen", "connection_key": "vpittamp@ryzen:22"},
        {
            "schema_version": "i3pm.herdr_proxy.event.v1",
            "protocol_version": 1,
            "event_type": "herdr.changed",
            "generation": 6,
            "snapshot_version": 6,
            "changed_keys": ["active_ai_sessions"],
            "payload": {"active_ai_sessions": []},
        },
    )
    await asyncio.sleep(0)

    assert service.remote_proxy_event_generation_for("ryzen") == 7
    assert notifications == ["ai_session_herdr_changed"]
    assert service.snapshot_cache["sessions"][0]["session_key"] == "herdr:ryzen:pane:remote-b"


@pytest.mark.asyncio
async def test_herdr_service_remote_proxy_event_without_payload_invalidates_for_recovery():
    notifications = []
    invalidations = 0

    async def notify_state_change(event_type):
        notifications.append(event_type)

    def invalidate_snapshot_cache():
        nonlocal invalidations
        invalidations += 1

    service = HerdrService(
        notify_state_change=notify_state_change,
        invalidate_snapshot_cache=invalidate_snapshot_cache,
        notify_delay=0.0,
    )
    service.store_snapshot({"sessions": [{"pane_id": "stale"}]}, now=100.0)

    await service.handle_remote_proxy_event(
        {"host": "ryzen", "ssh_target": "ryzen"},
        {
            "schema_version": "i3pm.herdr_proxy.event.v1",
            "protocol_version": 1,
            "event_type": "herdr.changed",
            "generation": 42,
            "changed_keys": ["herdr"],
        },
    )
    await asyncio.sleep(0)

    assert service.remote_generation_for("ryzen") == 1
    assert service.snapshot_cache == {}
    assert invalidations == 1
    assert notifications == ["ai_session_herdr_changed"]


@pytest.mark.asyncio
async def test_herdr_service_ignores_unknown_remote_proxy_event_schema():
    notifications = []
    service = HerdrService(
        notify_state_change=lambda event_type: notifications.append(event_type) or asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        notify_delay=0.0,
    )

    await service.handle_remote_proxy_event(
        {"host": "ryzen", "ssh_target": "ryzen"},
        {"schema_version": "unexpected", "event_type": "herdr.changed"},
    )
    await asyncio.sleep(0)

    assert service.remote_generation_for("ryzen") == 0
    assert notifications == []


@pytest.mark.asyncio
async def test_herdr_service_syncs_remote_proxy_subscription_tasks(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    created_targets = []

    async def fake_run_remote_proxy_subscription(target):
        created_targets.append(target)
        await asyncio.Event().wait()

    monkeypatch.setattr(service, "run_remote_proxy_subscription", fake_run_remote_proxy_subscription)

    service.sync_remote_proxy_subscriptions([
        {
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
        }
    ])
    await asyncio.sleep(0)

    assert list(service.remote_subscription_tasks.keys()) == ["vpittamp@ryzen:22"]
    assert created_targets == [{
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }]

    task = service.remote_subscription_tasks["vpittamp@ryzen:22"]
    service.sync_remote_proxy_subscriptions([])
    await asyncio.gather(task, return_exceptions=True)
    assert service.remote_subscription_tasks == {}


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
    assert remote_sessions[0]["is_current_window"] is False
    assert remote_sessions[0]["pane_active"] is False
    assert remote_sessions[1]["focused"] is True
    assert remote_sessions[1]["is_current_window"] is True
    assert remote_sessions[1]["pane_active"] is True


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


def test_herdr_service_loads_remote_targets_with_configured_resolvers(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        parse_remote_target=lambda value: ("vpittamp", value, 2200),
        normalize_connection_key=lambda value: value.strip().lower(),
    )
    monkeypatch.setenv("I3PM_HERDR_REMOTE_TARGETS", json.dumps([
        {"ssh_target": "Ryzen"},
    ]))

    assert service.load_remote_targets() == [{
        "host": "ryzen",
        "ssh_target": "Ryzen",
        "connection_key": "vpittamp@ryzen:2200",
    }]


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

    assert service.normalize_agent_status("NeedsInput") == "NeedsInput"
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
        "NeedsInput": "waiting",
        "working": "running",
        "mystery": "ignored",
    }


def test_herdr_service_strips_retired_tmux_and_lifecycle_fields_from_sessions():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    row = {
        "pane_id": "pane-1",
        "workspace_id": "workspace-1",
        "agent": "codex",
        "agent_status": "working",
        "cwd": "/repo/main",
        "focused": True,
        "session_phase": "working",
        "turn_owner": "llm",
        "activity_substate": "thinking",
        "status_reason": "otel",
        "terminal_anchor_id": "anchor-1",
        "terminal_context": {"tmux_pane": "%0"},
        "tmux_session": "i3pm-main",
        "tmux_window": "0:main",
        "tmux_pane": "%0",
        "tmux_session_name": "i3pm-main",
        "native_session_id": "native-1",
        "session_id": "legacy-session",
        "process_running": True,
        "activity_freshness": "fresh",
    }

    session = service.normalize_session_row(
        row,
        local_host="thinkpad",
        normalize_connection_key=lambda value: value,
        project_for_cwd=lambda cwd: {
            "project_name": "vpittamp/nixos-config:main",
            "project_path": cwd,
        },
    )

    assert session["schema"] == "herdr.ai_session.v1"
    assert session["session_key"] == "herdr:pane:pane-1"
    assert session["pane_id"] == "pane-1"
    assert session["agent_status"] == "working"
    assert session["agent_status_state"] == "working"
    for retired_field in (
        "session_phase",
        "turn_owner",
        "activity_substate",
        "status_reason",
        "terminal_anchor_id",
        "terminal_context",
        "tmux_session",
        "tmux_window",
        "tmux_pane",
        "tmux_session_name",
        "native_session_id",
        "session_id",
        "process_running",
        "activity_freshness",
    ):
        assert retired_field not in session


def test_herdr_service_sanitizes_existing_session_rows():
    rows = HerdrService.sanitize_session_rows([
        {
            "session_key": "herdr:pane:pane-1",
            "pane_id": "pane-1",
            "source": "herdr",
            "tmux_session": "legacy",
            "terminal_context": {"tmux_pane": "%1"},
            "session_phase": "working",
        },
        "invalid",
    ])

    assert rows == [{
        "session_key": "herdr:pane:pane-1",
        "pane_id": "pane-1",
        "source": "herdr",
    }]


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

    def fake_git_probe(path, args, *, ssh_target="", timeout=0.75):
        calls.append((path, tuple(args), ssh_target, timeout))
        return responses.get(tuple(args), "")

    # git_probe is the primitive; git_run is a thin wrapper over it, so patching
    # here covers both call styles.
    monkeypatch.setattr(service, "git_probe", fake_git_probe)

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


def test_herdr_service_failed_git_probe_is_not_memoized(monkeypatch):
    """A timed-out git probe must not pin "not a repo" for the whole TTL."""
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    probe_ok = {"value": False}

    def fake_git_probe(path, args, *, ssh_target="", timeout=0.75):
        if not probe_ok["value"]:
            return None  # git could not run (timeout / lock contention)
        return {
            ("rev-parse", "--is-inside-work-tree"): "true",
            ("rev-parse", "--show-toplevel"): "/repo/main",
            ("rev-parse", "--git-common-dir"): ".git",
            ("config", "--get", "remote.origin.url"): "git@github.com:acme/repo.git",
            ("branch", "--show-current"): "main",
        }.get(tuple(args), "")

    monkeypatch.setattr(service, "git_probe", fake_git_probe)

    assert service.path_is_git_worktree("/repo/main") is False
    assert service.git_space_metadata("/repo/main", normalize_connection_key=lambda v: v) == {}
    # Nothing was memoized, so recovery is immediate rather than TTL-bound.
    assert service.git_worktree_cache == {}
    assert service.git_metadata_cache == {}

    probe_ok["value"] = True
    assert service.path_is_git_worktree("/repo/main") is True
    metadata = service.git_space_metadata("/repo/main", normalize_connection_key=lambda v: v)
    assert metadata["branch_label"] == "main"


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
                "session_phase": "working",
                "turn_owner": "llm",
                "activity_substate": "thinking",
                "status_reason": "legacy",
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
    assert local_rows[0]["agent_status"] == "NeedsInput"
    assert local_rows[0]["agent_status_state"] == "blocked"
    for retired_field in ("session_phase", "turn_owner", "activity_substate", "status_reason"):
        assert retired_field not in local_rows[0]
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
            "session_phase": "working",
            "session_phase_label": "Working",
            "turn_owner": "llm",
            "turn_owner_label": "LLM",
            "activity_substate": "thinking",
            "activity_substate_label": "Thinking",
            "stage_visual_state": "working",
            "needs_user_action": False,
            "output_ready": False,
            "output_unseen": False,
            "review_pending": False,
            "status_reason": "legacy",
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
    assert remote_row["agent_status_state"] == "blocked"
    for retired_field in (
        "session_phase",
        "session_phase_label",
        "turn_owner",
        "turn_owner_label",
        "activity_substate",
        "activity_substate_label",
        "stage_visual_state",
        "needs_user_action",
        "output_ready",
        "output_unseen",
        "review_pending",
        "status_reason",
    ):
        assert retired_field not in remote_row
    assert remote_row["execution_mode"] == "ssh"
    assert remote_row["is_current_host"] is False
    assert remote_row["focus_target"] == {
        "method": "herdr.remote.pane.focus",
        "params": {
            "pane_id": "pane-r",
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
            "app_name": "herdr-ryzen",
        },
    }


def test_herdr_service_builds_spaces_with_worktree_groups():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    snapshot = {
        "workspaces": [
            {
                "workspace_id": "main-ws",
                "name": "nixos-config",
                "focused": False,
                "repo_key": "vpittamp/nixos-config",
                "repo_name": "nixos-config",
                "repo_root": "/repo/nixos-config",
                "checkout_path": "/repo/nixos-config/main",
                "is_linked_worktree": False,
            },
            {
                "workspace_id": "feature-ws",
                "name": "feature",
                "focused": True,
                "repo_key": "vpittamp/nixos-config",
                "repo_name": "nixos-config",
                "repo_root": "/repo/nixos-config",
                "checkout_path": "/repo/nixos-config/worktree/feature",
                "is_linked_worktree": True,
                "branch_label": "feature",
            },
        ],
        "agents": [{"workspace_id": "feature-ws", "herdr_host": "thinkpad"}],
        "panes": [{"workspace_id": "feature-ws", "herdr_host": "thinkpad"}],
        "tabs": [{"workspace_id": "feature-ws", "herdr_host": "thinkpad"}],
        "worktrees": [],
    }
    sessions = [{
        "source": "herdr",
        "workspace_id": "feature-ws",
        "project_name": "vpittamp/nixos-config:feature",
        "agent_status": "NeedsInput",
        "focused": True,
        "herdr_host": "thinkpad",
        "is_current_host": True,
    }]

    spaces = service.build_spaces(
        snapshot,
        sessions,
        local_host="thinkpad",
        normalize_connection_key=lambda value: value,
    )
    by_workspace = {space["workspace_id"]: space for space in spaces}

    assert by_workspace["main-ws"]["is_group_parent"] is True
    assert by_workspace["main-ws"]["group_member_count"] == 2
    assert by_workspace["feature-ws"]["group_key"] == "thinkpad:vpittamp/nixos-config"
    assert by_workspace["feature-ws"]["is_linked_worktree"] is True
    assert by_workspace["feature-ws"]["focused"] is True
    assert by_workspace["feature-ws"]["agent_status"] == "NeedsInput"
    assert by_workspace["feature-ws"]["agent_status_state"] == "blocked"
    assert by_workspace["feature-ws"]["agent_count"] == 1
    assert by_workspace["feature-ws"]["pane_count"] == 1
    assert by_workspace["feature-ws"]["tab_count"] == 1


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

    proxy_calls = []

    async def fake_run_proxy_json(_target, args, timeout=2.5):
        proxy_calls.append(args)
        return {
            "success": True,
            "schema_version": "i3pm.herdr_proxy.v1",
            "protocol_version": 1,
            "status": {"success": True, "result": {"protocol": 13}},
            "agents": [{
                "pane_id": "pane-r",
                "workspace_id": "workspace-r",
                "agent": "codex",
                "agent_status": "NeedsInput",
                "focused": True,
                "execution_mode": "local",
                "connection_key": "local@ryzen",
            }],
            "panes": [{
                "pane_id": "pane-r",
                "workspace_id": "workspace-r",
                "cwd": "/repo/remote",
                "execution_mode": "local",
                "connection_key": "local@ryzen",
            }],
            "workspaces": [{"workspace_id": "workspace-r", "focused": True}],
            "tabs": [],
            "worktrees": [],
            "errors": [],
            "command": ["ssh", "ryzen", "i3pm", "herdr-proxy", *args],
        }

    monkeypatch.setattr(service, "run_proxy_json", fake_run_proxy_json)
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
    assert snapshot["proxy_schema_version"] == "i3pm.herdr_proxy.v1"
    assert proxy_calls == [["snapshot", "--json"]]
    assert snapshot["agents"][0]["herdr_host"] == "ryzen"
    assert snapshot["agents"][0]["execution_mode"] == "ssh"
    assert snapshot["agents"][0]["connection_key"] == "vpittamp@ryzen:22"
    assert snapshot["sessions"][0]["session_key"] == "herdr:ryzen:pane:pane-r"
    assert snapshot["sessions"][0]["agent_status"] == "NeedsInput"
    assert snapshot["sessions"][0]["agent_status_state"] == "blocked"
    assert snapshot["sessions"][0]["focus_target"]["method"] == "herdr.remote.pane.focus"
    assert snapshot["sessions"][0]["is_remote_herdr"] is True
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
async def test_herdr_service_builds_local_proxy_snapshot(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    async def fake_local_snapshot(**kwargs):
        assert kwargs["local_host"] == "Ryzen"
        return {
            "success": True,
            "herdr_generation": 3,
            "local_herdr_generation": 3,
            "remote_herdr_generation": {},
            "status": {"success": True},
            "agents": [],
            "panes": [],
            "workspaces": [],
            "tabs": [],
            "worktrees": [],
            "sessions": [],
            "errors": [],
        }

    monkeypatch.setattr(service, "local_snapshot", fake_local_snapshot)

    snapshot = await service.proxy_snapshot(
        {"refresh": True},
        local_host="Ryzen",
        normalize_connection_key=lambda value: value.lower(),
        project_for_cwd=lambda path: {"project_name": "global", "project_path": path},
    )

    assert snapshot["success"] is True
    assert snapshot["schema_version"] == "i3pm.herdr_proxy.v1"
    assert snapshot["protocol_version"] == 1
    assert snapshot["proxy_host"] == "ryzen"
    assert snapshot["refresh"] is True


@pytest.mark.asyncio
async def test_herdr_service_proxy_pane_focus_adds_proxy_metadata(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    async def fake_pane_focus(params):
        assert params == {"pane_id": "pane-a"}
        return {"success": True, "pane_id": "pane-a", "herdr": {"success": True}}

    monkeypatch.setattr(service, "pane_focus", fake_pane_focus)

    result = await service.proxy_pane_focus({"pane_id": "pane-a"}, local_host="Ryzen")

    assert result == {
        "success": True,
        "pane_id": "pane-a",
        "herdr": {"success": True},
        "schema_version": "i3pm.herdr_proxy.v1",
        "protocol_version": 1,
        "proxy_host": "ryzen",
    }


@pytest.mark.asyncio
async def test_herdr_service_combined_snapshot_merges_and_caches_remote_rows(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        remote_snapshot_cache_ttl=10.0,
    )
    remote_target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }

    async def fake_local_snapshot(**_kwargs):
        return {
            "success": True,
            "herdr_generation": 1,
            "local_herdr_generation": 1,
            "remote_herdr_generation": {},
            "status": {"success": True},
            "agents": [],
            "panes": [],
            "workspaces": [],
            "tabs": [],
            "worktrees": [],
            "sessions": [{
                "session_key": "herdr:pane:local",
                "focused": False,
                "is_current_host": True,
                "herdr_host": "thinkpad",
            }],
            "errors": [],
        }

    async def fake_remote_snapshot(target, **_kwargs):
        assert target == remote_target
        return {
            "success": True,
            "remote": True,
            "host": "ryzen",
            "agents": [{"pane_id": "remote"}],
            "panes": [{"pane_id": "remote"}],
            "workspaces": [],
            "tabs": [],
            "worktrees": [],
            "sessions": [{
                "session_key": "herdr:ryzen:pane:remote",
                "focused": True,
                "is_current_host": False,
                "herdr_host": "ryzen",
            }],
            "errors": [],
        }

    monkeypatch.setattr(service, "local_snapshot", fake_local_snapshot)
    monkeypatch.setattr(service, "remote_snapshot", fake_remote_snapshot)

    snapshot = await service.snapshot(
        {"refresh": True},
        remote_targets=[remote_target],
        local_host="thinkpad",
        normalize_connection_key=lambda value: value,
        project_for_cwd=lambda path: {"project_name": "global", "project_path": path},
    )
    cached = await service.snapshot(
        {},
        remote_targets=[remote_target],
        local_host="thinkpad",
        normalize_connection_key=lambda value: value,
        project_for_cwd=lambda path: {"project_name": "global", "project_path": path},
    )

    assert [row["session_key"] for row in snapshot["sessions"]] == [
        "herdr:ryzen:pane:remote",
        "herdr:pane:local",
    ]
    assert snapshot["agents"] == [{"pane_id": "remote"}]
    assert snapshot["remote_targets"] == [remote_target]
    assert snapshot["remote_snapshots"][0]["host"] == "ryzen"
    assert snapshot["remote_errors"] == []
    assert cached == snapshot
    assert cached is not service.snapshot_cache


@pytest.mark.asyncio
async def test_herdr_service_remote_snapshot_reports_status_failure(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    async def fake_run_proxy_json(_target, args, timeout=2.5):
        return {
            "success": False,
            "error": "timeout",
            "command": ["ssh", "ryzen", "i3pm", "herdr-proxy", *args],
            "returncode": None,
        }

    monkeypatch.setattr(service, "run_proxy_json", fake_run_proxy_json)

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
        "command": ["ssh", "ryzen", "i3pm", "herdr-proxy", "snapshot", "--json"],
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
async def test_herdr_service_runs_remote_proxy_command(monkeypatch):
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
            stdout='{"success":true,"schema_version":"i3pm.herdr_proxy.v1","agents":[]}\n',
            stderr="",
        )

    monkeypatch.setattr(herdr_service_module.shutil, "which", lambda name: f"/bin/{name}")
    monkeypatch.setattr(herdr_service_module.subprocess, "run", fake_run)

    result = await service.run_proxy_json(
        {
            "host": "ryzen",
            "ssh_target": "ryzen",
            "connection_key": "vpittamp@ryzen:22",
        },
        ["snapshot", "--json"],
        timeout=1.25,
    )

    assert result["success"] is True
    assert result["schema_version"] == "i3pm.herdr_proxy.v1"
    assert result["command"] == ["ssh", "ryzen", "i3pm", "herdr-proxy", "snapshot", "--json"]
    assert result["herdr_host"] == "ryzen"
    assert result["ssh_target"] == "ryzen"
    assert result["connection_key"] == "vpittamp@ryzen:22"
    assert calls[0][0][-4:] == ["i3pm", "herdr-proxy", "snapshot", "--json"]
    assert calls[0][0][:2] == ["ssh", "-o"]
    assert calls[0][1]["timeout"] == 1.25


@pytest.mark.asyncio
async def test_herdr_service_reports_remote_transport_errors(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    missing_target = await service.run_proxy_json({}, ["snapshot", "--json"])
    assert missing_target == {
        "success": False,
        "error": "missing_ssh_target",
        "command": ["ssh", "", "i3pm", "herdr-proxy", "snapshot", "--json"],
    }

    monkeypatch.setattr(herdr_service_module.shutil, "which", lambda _name: None)
    missing_ssh = await service.run_proxy_json(
        {"ssh_target": "ryzen"},
        ["snapshot", "--json"],
    )
    assert missing_ssh == {
        "success": False,
        "error": "ssh_not_found",
        "command": ["ssh", "ryzen", "i3pm", "herdr-proxy", "snapshot", "--json"],
    }


@pytest.mark.asyncio
async def test_herdr_service_local_pane_actions_own_generations_and_cache(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    socket_calls = []

    async def fake_run_socket_json(*, method, params=None, timeout=0.5):
        socket_calls.append((method, params))
        return {"success": True, "socket": True, "result": {"ok": True}}

    monkeypatch.setattr(service, "run_socket_json", fake_run_socket_json)
    service.store_snapshot({"sessions": [{"pane_id": "stale"}]}, now=100.0)

    focus_result = await service.pane_focus({"pane_id": "pane-a"})
    service.store_snapshot({"sessions": [{"pane_id": "stale"}]}, now=101.0)
    close_result = await service.pane_close({"pane_id": "pane-a"})
    workspace_result = await service.workspace_focus({"workspace_id": "ws-a"})
    tab_result = await service.tab_focus({"tab_id": "tab-a"})

    assert socket_calls == [
        ("agent.focus", {"target": "pane-a"}),
        ("pane.close", {"pane_id": "pane-a"}),
        ("workspace.focus", {"workspace_id": "ws-a"}),
        ("tab.focus", {"tab_id": "tab-a"}),
    ]
    assert focus_result["success"] is True
    assert close_result["success"] is True
    assert workspace_result["workspace_id"] == "ws-a"
    assert tab_result["tab_id"] == "tab-a"
    assert service.local_herdr_generation == 4
    assert service.snapshot_cache == {}


@pytest.mark.asyncio
async def test_herdr_service_local_focus_raises_local_herdr_window(monkeypatch):
    """Local pane/tab/workspace focus must raise the local 'herdr' Ghostty window."""
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    async def fake_run_socket_json(*, method, params=None, timeout=0.5):
        return {"success": True, "socket": True}

    monkeypatch.setattr(service, "run_socket_json", fake_run_socket_json)

    launch_calls = []

    async def fake_launch_open(payload):
        launch_calls.append(payload)
        return {"success": True, "reused_existing": True}

    pane_result = await service.pane_focus(
        {"pane_id": "pane-a", "__intent_epoch": 3}, launch_open=fake_launch_open
    )
    await service.tab_focus({"tab_id": "tab-a"}, launch_open=fake_launch_open)
    await service.workspace_focus({"workspace_id": "ws-a"}, launch_open=fake_launch_open)

    # Every local focus targets the single local "herdr" registry app (not a
    # remote herdr-<host> window), and threads the user-intent epoch through.
    assert launch_calls == [
        {"app_name": "herdr", "focus_fast": True, "__intent_epoch": 3},
        {"app_name": "herdr", "focus_fast": True, "__intent_epoch": 0},
        {"app_name": "herdr", "focus_fast": True, "__intent_epoch": 0},
    ]
    assert pane_result["launch"] == {"success": True, "reused_existing": True}


def test_herdr_service_remote_app_name_is_per_host():
    """Remote window app name maps deterministically from herdr_host."""
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    assert service.herdr_local_app_name() == "herdr"
    assert service.herdr_remote_app_name("ryzen") == "herdr-ryzen"
    assert service.herdr_remote_app_name("Ryzen") == "herdr-ryzen"
    assert service.herdr_remote_app_name("host.example") == "herdr-host_example"
    assert service.herdr_remote_app_name("") == "herdr"


@pytest.mark.asyncio
async def test_herdr_service_local_focus_falls_back_to_cli_when_socket_unavailable(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    cli_calls = []

    async def fake_run_socket_json(*, method, params=None, timeout=0.5):
        return {"success": False, "transport_error": True, "error": "socket_unavailable"}

    async def fake_run_json(args, timeout=2.0):
        cli_calls.append(args)
        return {"success": True, "result": {"ok": True}}

    monkeypatch.setattr(service, "run_socket_json", fake_run_socket_json)
    monkeypatch.setattr(service, "run_json", fake_run_json)

    result = await service.pane_focus({"pane_id": "pane-a"})

    assert cli_calls == [["agent", "focus", "pane-a"]]
    assert result["success"] is True
    assert service.local_herdr_generation == 1


@pytest.mark.asyncio
async def test_herdr_service_pane_focus_falls_back_to_tab_when_agent_not_found(monkeypatch):
    """A pane with no live agent binding must still switch via tab.focus.

    ``agent.focus`` reports ``agent_not_found`` for panes Herdr no longer binds
    to an agent (idle/exited). Without the tab fallback the click is silently
    swallowed, which is the "clicking doesn't switch reliably" bug.
    """
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    socket_calls = []

    async def fake_run_socket_json(*, method, params=None, timeout=0.5):
        socket_calls.append((method, params))
        if method == "agent.focus":
            return {"success": False, "socket": True, "error": "agent_not_found"}
        if method == "pane.get":
            return {
                "success": True,
                "socket": True,
                "result": {"pane": {"pane_id": "pane-a", "tab_id": "tab-a"}},
            }
        if method == "tab.focus":
            return {"success": True, "socket": True, "result": {"ok": True}}
        raise AssertionError(f"unexpected method {method}")

    monkeypatch.setattr(service, "run_socket_json", fake_run_socket_json)
    service.store_snapshot({"sessions": [{"pane_id": "stale"}]}, now=100.0)

    result = await service.pane_focus({"pane_id": "pane-a"})

    assert socket_calls == [
        ("agent.focus", {"target": "pane-a"}),
        ("pane.get", {"pane_id": "pane-a"}),
        ("tab.focus", {"tab_id": "tab-a"}),
    ]
    assert result["success"] is True
    assert result["focus_via"] == "tab"
    # Success via the fallback still bumps the generation and clears the cache.
    assert service.local_herdr_generation == 1
    assert service.snapshot_cache == {}


@pytest.mark.asyncio
async def test_herdr_service_pane_focus_keeps_agent_failure_when_tab_unresolved(monkeypatch):
    """When the tab_id can't be resolved, keep the original agent.focus failure."""
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    socket_calls = []

    async def fake_run_socket_json(*, method, params=None, timeout=0.5):
        socket_calls.append((method, params))
        if method == "agent.focus":
            return {"success": False, "socket": True, "error": "agent_not_found"}
        if method == "pane.get":
            return {"success": True, "socket": True, "result": {"pane": {}}}
        raise AssertionError(f"unexpected method {method}")

    monkeypatch.setattr(service, "run_socket_json", fake_run_socket_json)

    result = await service.pane_focus({"pane_id": "pane-a"})

    assert socket_calls == [
        ("agent.focus", {"target": "pane-a"}),
        ("pane.get", {"pane_id": "pane-a"}),
    ]
    assert result["success"] is False
    assert result["focus_via"] == "agent"
    assert service.local_herdr_generation == 0


@pytest.mark.asyncio
async def test_herdr_service_remote_pane_focus_owns_transport_cache_and_launch(monkeypatch):
    notifications = []
    service = HerdrService(
        notify_state_change=lambda event_type: notifications.append(event_type) or asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    target = {
        "host": "ryzen",
        "ssh_target": "ryzen",
        "connection_key": "vpittamp@ryzen:22",
    }
    service.snapshot_cache = {
        "sessions": [
            {
                "session_key": "herdr:ryzen:pane:remote-a",
                "herdr_host": "ryzen",
                "pane_id": "remote-a",
                "focused": True,
                "connection_key": "vpittamp@ryzen:22",
            },
            {
                "session_key": "herdr:ryzen:pane:remote-b",
                "herdr_host": "ryzen",
                "pane_id": "remote-b",
                "focused": False,
                "connection_key": "vpittamp@ryzen:22",
            },
        ],
    }
    proxy_calls = []
    launch_calls = []
    focus_overrides = []
    action_order = []

    async def fake_run_proxy_json(remote_target, args, timeout=2.5):
        action_order.append("proxy-start")
        await asyncio.sleep(0.01)
        action_order.append("proxy-end")
        proxy_calls.append((remote_target, args))
        return {"success": True, "result": {"focused": True}}

    async def fake_launch_open(params):
        action_order.append("launch")
        launch_calls.append(params)
        return {"success": True, "launch": {"reused_existing": True}}

    monkeypatch.setattr(service, "run_proxy_json", fake_run_proxy_json)

    result = await service.remote_pane_focus(
        {
            "pane_id": "remote-b",
            "host": "ryzen",
            "__intent_epoch": 9,
        },
        targets=[target],
        parse_remote_target=lambda value: ("", value, 22),
        normalize_connection_key=lambda value: value,
        launch_open=fake_launch_open,
        set_focus_overrides=lambda **kwargs: focus_overrides.append(kwargs),
    )

    assert proxy_calls == [(target, ["focus", "remote-b", "--json"])]
    assert action_order.index("launch") < action_order.index("proxy-end")
    assert launch_calls == [{
        "app_name": "herdr-ryzen",
        "__intent_epoch": 9,
        "focus_fast": True,
    }]
    assert focus_overrides == [{
        "session_key": "herdr:ryzen:pane:remote-b",
        "window_id": 0,
        "connection_key": "vpittamp@ryzen:22",
    }]
    assert notifications == ["focus_changed", "ai_session_herdr_changed"]
    assert service.remote_generation_for("ryzen") == 1
    assert result["success"] is True
    assert service.snapshot_cache["sessions"][0]["focused"] is False
    assert service.snapshot_cache["sessions"][1]["focused"] is True
    assert service.snapshot_cache["sessions"][1]["pane_active"] is True


def _local_snapshot_payload(*, success=True, sessions=None):
    return {
        "success": success,
        "herdr_generation": 1,
        "local_herdr_generation": 1,
        "remote_herdr_generation": {},
        "status": {"success": success},
        "agents": [],
        "panes": [],
        "workspaces": [],
        "tabs": [],
        "worktrees": [],
        "sessions": list(sessions or []),
        "errors": [],
    }


@pytest.mark.asyncio
async def test_herdr_service_subscription_backoff_resets_after_long_lived_connection(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        subscription_initial_backoff=0.5,
        subscription_max_backoff=30.0,
    )
    clock = {"now": 1000.0}
    monkeypatch.setattr(herdr_service_module.time, "monotonic", lambda: clock["now"])

    attempts = {"count": 0}

    async def fake_connect():
        attempts["count"] += 1
        if attempts["count"] <= 3:
            clock["now"] += 0.01
            raise ConnectionError("fast failure")
        if attempts["count"] == 4:
            clock["now"] += 120.0
            raise ConnectionError("dropped after long uptime")
        raise asyncio.CancelledError

    sleeps = []

    async def fake_sleep(delay):
        sleeps.append(delay)

    monkeypatch.setattr(service, "connect_subscription_once", fake_connect)
    monkeypatch.setattr(herdr_service_module.asyncio, "sleep", fake_sleep)

    with pytest.raises(asyncio.CancelledError):
        await service.run_subscription()

    # Fast failures double the backoff; a connection that survived longer than
    # the max backoff resets it to the initial value when it finally drops.
    assert sleeps == [0.5, 1.0, 2.0, 0.5]


@pytest.mark.asyncio
async def test_herdr_service_subscription_backoff_grows_and_warns_on_persistent_failures(monkeypatch, caplog):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        subscription_initial_backoff=0.5,
        subscription_max_backoff=4.0,
    )
    attempts = {"count": 0}

    async def fake_connect():
        attempts["count"] += 1
        if attempts["count"] > 6:
            raise asyncio.CancelledError
        raise ConnectionError("connection refused")

    sleeps = []

    async def fake_sleep(delay):
        sleeps.append(delay)

    monkeypatch.setattr(service, "connect_subscription_once", fake_connect)
    monkeypatch.setattr(herdr_service_module.asyncio, "sleep", fake_sleep)

    with caplog.at_level(logging.DEBUG, logger=herdr_service_module.logger.name):
        with pytest.raises(asyncio.CancelledError):
            await service.run_subscription()

    assert sleeps == [0.5, 1.0, 2.0, 4.0, 4.0, 4.0]
    warnings = [record for record in caplog.records if record.levelno == logging.WARNING]
    assert len(warnings) == 1
    assert "consecutive failures" in warnings[0].getMessage()


@pytest.mark.asyncio
async def test_herdr_service_read_json_line_skips_malformed_lines():
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    reader = asyncio.StreamReader()
    reader.feed_data(b"not-json\n")
    reader.feed_data(b"[1,2]\n")
    reader.feed_data(b'{"event":"pane.focused"}\n')
    reader.feed_eof()

    payload = await service.read_json_line(reader)

    assert payload == {"event": "pane.focused"}
    with pytest.raises(ConnectionError):
        await service.read_json_line(reader)


@pytest.mark.asyncio
async def test_herdr_service_event_during_snapshot_build_is_not_clobbered(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        notify_delay=0.0,
    )
    release = asyncio.Event()
    builds = {"count": 0}

    async def fake_local_snapshot(**_kwargs):
        builds["count"] += 1
        await release.wait()
        return _local_snapshot_payload(sessions=[{
            "session_key": "herdr:pane:pane-a",
            "pane_id": "pane-a",
            "agent_status": "working",
        }])

    monkeypatch.setattr(service, "local_snapshot", fake_local_snapshot)
    snapshot_kwargs = {
        "remote_targets": [],
        "local_host": "thinkpad",
        "normalize_connection_key": lambda value: value,
        "project_for_cwd": lambda path: {"project_name": "global", "project_path": path},
    }

    build = asyncio.create_task(service.snapshot({"refresh": True}, **snapshot_kwargs))
    await asyncio.sleep(0)
    await service.handle_subscription_event({
        "event": "pane.agent_status_changed",
        "data": {"pane_id": "pane-a", "agent_status": "done"},
    })
    release.set()
    snapshot = await build

    # The fresh build is returned and cached only provisionally: it may already
    # be one event behind, so it must not be served for a full TTL — but
    # discarding it would make every read during a burst pay a full rebuild.
    assert snapshot["sessions"][0]["pane_id"] == "pane-a"
    assert service.snapshot_cache_is_provisional is True

    # Within the short failure TTL the provisional snapshot still serves.
    await service.snapshot({}, **snapshot_kwargs)
    assert builds["count"] == 1

    # Past it, the next read rebuilds on top of the mid-build event.
    service.snapshot_cache_built_at -= service.snapshot_provisional_cache_ttl + 1.0
    release.set()
    await service.snapshot({}, **snapshot_kwargs)
    assert builds["count"] == 2
    await asyncio.sleep(0)


@pytest.mark.asyncio
async def test_herdr_service_failed_snapshot_is_cached_with_short_failure_ttl(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        snapshot_cache_ttl=5.0,
    )
    clock = {"now": 100.0}
    monkeypatch.setattr(herdr_service_module.time, "time", lambda: clock["now"])
    herdr_ok = {"value": False}
    builds = {"count": 0}

    async def fake_local_snapshot(**_kwargs):
        builds["count"] += 1
        return _local_snapshot_payload(success=herdr_ok["value"])

    monkeypatch.setattr(service, "local_snapshot", fake_local_snapshot)
    snapshot_kwargs = {
        "remote_targets": [],
        "local_host": "thinkpad",
        "normalize_connection_key": lambda value: value,
        "project_for_cwd": lambda path: {"project_name": "global", "project_path": path},
    }

    failed = await service.snapshot({}, **snapshot_kwargs)
    assert failed["success"] is False
    assert builds["count"] == 1

    clock["now"] = 100.1
    served = await service.snapshot({}, **snapshot_kwargs)
    assert served["success"] is False
    assert builds["count"] == 1

    # herdr recovers: the failure snapshot expires after ~0.25s even though the
    # normal 5s TTL has not elapsed, so recovery is immediate.
    herdr_ok["value"] = True
    clock["now"] = 100.4
    recovered = await service.snapshot({}, **snapshot_kwargs)
    assert recovered["success"] is True
    assert builds["count"] == 2


@pytest.mark.asyncio
async def test_herdr_service_local_snapshot_retains_agents_on_partial_failure(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    agent_ok = {"value": True}

    async def fake_run_json(args, timeout=2.0):
        key = tuple(args)
        if key == ("agent", "list"):
            if agent_ok["value"]:
                return {
                    "success": True,
                    "result": {"agents": [{
                        "pane_id": "pane-l",
                        "agent": "codex",
                        "agent_status": "working",
                        "cwd": "/repo/local",
                    }]},
                }
            return {
                "success": False,
                "error": "timeout",
                "command": ["herdr", "agent", "list"],
            }
        if key == ("status", "--json"):
            return {"success": True, "result": {"protocol": 13}}
        if key == ("pane", "list"):
            return {
                "success": True,
                "result": {"panes": [{
                    "pane_id": "pane-l",
                    "workspace_id": "workspace-l",
                    "cwd": "/repo/local",
                }]},
            }
        return {"success": True, "result": {"workspaces": [], "tabs": [], "worktrees": []}}

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
    snapshot_kwargs = {
        "local_host": "thinkpad",
        "normalize_connection_key": lambda value: value.lower(),
        "project_for_cwd": lambda path: {"project_name": "global", "project_path": path},
    }

    first = await service.local_snapshot(**snapshot_kwargs)
    assert [row["pane_id"] for row in first["agents"]] == ["pane-l"]

    agent_ok["value"] = False
    second = await service.local_snapshot(**snapshot_kwargs)

    # The failed agent list reuses the last-known-good rows instead of
    # blanking the panel, and the failure stays visible in errors.
    assert [row["pane_id"] for row in second["agents"]] == ["pane-l"]
    assert second["sessions"][0]["session_key"] == "herdr:pane:pane-l"
    assert any(error.get("error") == "timeout" for error in second["errors"])


@pytest.mark.asyncio
async def test_herdr_service_local_fallback_is_bounded(monkeypatch):
    """A dead herdr must empty the panel rather than serve ghost sessions."""
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )
    clock = {"now": 500.0}
    monkeypatch.setattr(herdr_service_module.time, "monotonic", lambda: clock["now"])
    herdr_up = {"value": True}

    async def fake_run_json(args, timeout=2.0):
        key = tuple(args)
        if not herdr_up["value"]:
            return {"success": False, "error": "connection refused", "command": ["herdr", *args]}
        if key == ("agent", "list"):
            return {
                "success": True,
                "result": {"agents": [{
                    "pane_id": "pane-l",
                    "agent": "codex",
                    "agent_status": "working",
                    "cwd": "/repo/local",
                }]},
            }
        if key == ("status", "--json"):
            return {"success": True, "result": {"protocol": 13}}
        if key == ("pane", "list"):
            return {
                "success": True,
                "result": {"panes": [{
                    "pane_id": "pane-l",
                    "workspace_id": "workspace-l",
                    "cwd": "/repo/local",
                }]},
            }
        return {"success": True, "result": {"workspaces": [], "tabs": [], "worktrees": []}}

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
    snapshot_kwargs = {
        "local_host": "thinkpad",
        "normalize_connection_key": lambda value: value.lower(),
        "project_for_cwd": lambda path: {"project_name": "global", "project_path": path},
    }

    primed = await service.local_snapshot(**snapshot_kwargs)
    assert [row["pane_id"] for row in primed["agents"]] == ["pane-l"]

    # herdr itself is unreachable: the herd is genuinely gone, so the stored
    # rows must not be resurrected even though the list call "just failed".
    herdr_up["value"] = False
    down = await service.local_snapshot(**snapshot_kwargs)
    assert down["agents"] == []
    assert down["sessions"] == []
    assert service.local_collection_fallbacks == {}

    # And a stale fallback expires even while herdr answers status but not lists.
    herdr_up["value"] = True
    await service.local_snapshot(**snapshot_kwargs)
    assert "agents" in service.local_collection_fallbacks

    async def status_only_run_json(args, timeout=2.0):
        if tuple(args) == ("status", "--json"):
            return {"success": True, "result": {"protocol": 13}}
        return {"success": False, "error": "timeout", "command": ["herdr", *args]}

    monkeypatch.setattr(service, "run_json", status_only_run_json)
    clock["now"] += service.local_collection_fallback_ttl + 1.0
    expired = await service.local_snapshot(**snapshot_kwargs)
    assert expired["agents"] == []


@pytest.mark.asyncio
async def test_herdr_service_status_events_do_not_extend_cache_ttl(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
        snapshot_cache_ttl=0.5,
        notify_delay=0.0,
    )
    clock = {"now": 100.0}
    monkeypatch.setattr(herdr_service_module.time, "time", lambda: clock["now"])
    builds = {"count": 0}

    async def fake_local_snapshot(**_kwargs):
        builds["count"] += 1
        return _local_snapshot_payload(sessions=[{
            "session_key": "herdr:pane:pane-a",
            "pane_id": "pane-a",
            "agent_status": "working",
            "agent_status_state": "working",
        }])

    monkeypatch.setattr(service, "local_snapshot", fake_local_snapshot)
    snapshot_kwargs = {
        "remote_targets": [],
        "local_host": "thinkpad",
        "normalize_connection_key": lambda value: value,
        "project_for_cwd": lambda path: {"project_name": "global", "project_path": path},
    }

    await service.snapshot({}, **snapshot_kwargs)
    assert builds["count"] == 1

    # Status patches keep landing but must not extend the rebuild deadline.
    for offset in (0.2, 0.4):
        clock["now"] = 100.0 + offset
        await service.handle_subscription_event({
            "event": "pane.agent_status_changed",
            "data": {"pane_id": "pane-a", "agent_status": "done"},
        })

    clock["now"] = 100.45
    patched = await service.snapshot({}, **snapshot_kwargs)
    assert patched["sessions"][0]["agent_status"] == "done"
    assert builds["count"] == 1

    clock["now"] = 100.7
    await service.snapshot({}, **snapshot_kwargs)
    assert builds["count"] == 2
    await asyncio.sleep(0)


@pytest.mark.asyncio
async def test_herdr_service_local_snapshot_reconciles_status_subscription_tasks(monkeypatch):
    service = HerdrService(
        notify_state_change=lambda event_type: asyncio.sleep(0),
        invalidate_snapshot_cache=lambda: None,
    )

    async def wait_forever():
        await asyncio.Event().wait()

    gone_task = asyncio.create_task(wait_forever())
    kept_task = asyncio.create_task(wait_forever())
    service.status_subscription_tasks["gone"] = gone_task
    service.status_subscription_tasks["pane-l"] = kept_task

    async def fake_run_json(args, timeout=2.0):
        key = tuple(args)
        if key == ("status", "--json"):
            return {"success": True, "result": {"protocol": 13}}
        if key == ("agent", "list"):
            return {
                "success": True,
                "result": {"agents": [{"pane_id": "pane-l", "agent": "codex"}]},
            }
        if key == ("pane", "list"):
            return {
                "success": True,
                "result": {"panes": [{"pane_id": "pane-l", "workspace_id": "workspace-l"}]},
            }
        return {"success": True, "result": {"workspaces": [], "tabs": [], "worktrees": []}}

    monkeypatch.setattr(service, "run_json", fake_run_json)
    monkeypatch.setattr(
        service,
        "effective_cwd",
        lambda row, *, ssh_target="": "",
    )
    monkeypatch.setattr(
        service,
        "git_space_metadata",
        lambda path, *, ssh_target="", normalize_connection_key: {},
    )

    await service.local_snapshot(
        local_host="thinkpad",
        normalize_connection_key=lambda value: value,
        project_for_cwd=lambda path: {"project_name": "global", "project_path": path},
    )

    # The pane that vanished without a pane.closed event loses its retry task;
    # the still-present pane keeps its subscription.
    assert set(service.status_subscription_tasks.keys()) == {"pane-l"}
    await asyncio.gather(gone_task, return_exceptions=True)
    assert gone_task.cancelled()

    kept_task.cancel()
    await asyncio.gather(kept_task, return_exceptions=True)
