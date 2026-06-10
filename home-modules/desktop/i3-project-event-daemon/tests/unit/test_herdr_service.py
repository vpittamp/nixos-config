import asyncio
import importlib
import importlib.util
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
