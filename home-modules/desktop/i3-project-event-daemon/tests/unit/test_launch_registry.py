"""Unit tests for deterministic launch-registry matching."""

import asyncio
import importlib.util
import sys
import time
from pathlib import Path

DAEMON_ROOT = Path(__file__).parent.parent.parent
spec = importlib.util.spec_from_file_location(
    "i3_project_event_daemon",
    DAEMON_ROOT / "__init__.py",
    submodule_search_locations=[str(DAEMON_ROOT)],
)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

from i3_project_event_daemon.models import LaunchWindowInfo, PendingLaunch
from i3_project_event_daemon.services.launch_registry import LaunchRegistry


def test_find_by_window_signature_matches_dynamic_pwa_class():
    registry = LaunchRegistry()
    launch = PendingLaunch(
        app_name="google-ai-pwa",
        project_name="global",
        project_directory=Path.home(),
        launcher_pid=1000,
        workspace_number=51,
        timestamp=time.time(),
        expected_class="WebApp-01K665SPD8EPMP3JTW02JM1M0Z",
        pwa_match_domains=["google.com"],
        terminal_anchor_id="google-ai-pwa-global-1000-1",
    )
    asyncio.run(registry.add(launch))

    window = LaunchWindowInfo(
        window_id=1,
        window_class="chrome-google.com__ai-Default",
        window_instance="",
        window_pid=2000,
        workspace_number=51,
        timestamp=time.time(),
    )

    matched = asyncio.run(registry.find_by_window_signature(window))
    assert matched is not None
    assert matched.app_name == "google-ai-pwa"
    assert matched.matched is True


def test_find_by_window_signature_rejects_ambiguous_matches():
    registry = LaunchRegistry()
    launch_one = PendingLaunch(
        app_name="gmail-pwa",
        project_name="global",
        project_directory=Path.home(),
        launcher_pid=1001,
        workspace_number=56,
        timestamp=time.time(),
        expected_class="WebApp-01JCYF9K4Q9V6X8YJ1MNSPT0D7",
        pwa_match_domains=["mail.google.com"],
        terminal_anchor_id="gmail-pwa-global-1001-1",
    )
    launch_two = PendingLaunch(
        app_name="gmail-secondary-pwa",
        project_name="global",
        project_directory=Path.home(),
        launcher_pid=1002,
        workspace_number=57,
        timestamp=time.time(),
        expected_class="WebApp-01JCYF9K4Q9V6X8YJ1MNSPT0D7",
        pwa_match_domains=["mail.google.com"],
        terminal_anchor_id="gmail-pwa-global-1002-1",
    )
    asyncio.run(registry.add(launch_one))
    asyncio.run(registry.add(launch_two))

    window = LaunchWindowInfo(
        window_id=2,
        window_class="chrome-mail.google.com__-Default",
        window_instance="",
        window_pid=2001,
        workspace_number=60,
        timestamp=time.time(),
    )

    matched = asyncio.run(registry.find_by_window_signature(window))
    assert matched is None


def test_find_by_app_name_matches_unique_pending_launch():
    registry = LaunchRegistry()
    launch = PendingLaunch(
        app_name="gmail-pwa",
        project_name="global",
        project_directory=Path.home(),
        launcher_pid=1001,
        workspace_number=56,
        timestamp=time.time(),
        expected_class="WebApp-01JCYF9K4Q9V6X8YJ1MNSPT0D7",
        pwa_match_domains=["mail.google.com"],
        terminal_anchor_id="gmail-pwa-global-1001-1",
    )
    asyncio.run(registry.add(launch))

    matched = asyncio.run(
        registry.find_by_app_name("gmail-pwa", workspace_number=56, project_name="global")
    )
    assert matched is not None
    assert matched.app_name == "gmail-pwa"
    assert matched.matched is True
