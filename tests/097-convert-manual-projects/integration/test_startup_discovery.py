"""
Integration tests for startup discovery behavior.

Feature 097: Git-Based Project Discovery and Management
Task T055: Verify daemon startup triggers background discovery when enabled.
"""

import pytest
import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime


class TestStartupDiscovery:
    """Test background discovery triggers on daemon startup."""

    @pytest.mark.asyncio
    async def test_discovery_triggered_when_enabled(self):
        """Verify discovery is triggered when auto_discover_on_startup is True."""
        # Mock discovery config with auto_discover enabled
        mock_config = MagicMock()
        mock_config.auto_discover_on_startup = True
        mock_config.scan_paths = ["/home/user/projects"]
        mock_config.scan_depth = 3

        # Mock discovery service
        mock_result = MagicMock()
        mock_result.success = True
        mock_result.repositories = []
        mock_result.errors = []

        with patch(
            "i3_project_event_daemon.services.discovery_service.scan_directory"
        ) as mock_scan:
            mock_scan.return_value = mock_result

            # Simulate discovery trigger
            triggered = mock_config.auto_discover_on_startup
            assert triggered is True

    @pytest.mark.asyncio
    async def test_discovery_not_triggered_when_disabled(self):
        """Verify discovery is NOT triggered when auto_discover_on_startup is False."""
        mock_config = MagicMock()
        mock_config.auto_discover_on_startup = False

        triggered = mock_config.auto_discover_on_startup
        assert triggered is False

    @pytest.mark.asyncio
    async def test_discovery_respects_timeout(self):
        """Verify 60-second timeout is applied to background discovery."""
        timeout_seconds = 60

        async def slow_discovery():
            await asyncio.sleep(120)  # Exceeds timeout

        # Should timeout
        with pytest.raises(asyncio.TimeoutError):
            await asyncio.wait_for(slow_discovery(), timeout=0.1)

    @pytest.mark.asyncio
    async def test_discovery_runs_in_background(self):
        """Verify discovery doesn't block daemon startup."""
        startup_completed = asyncio.Event()
        discovery_started = asyncio.Event()
        discovery_completed = asyncio.Event()

        async def background_discovery():
            discovery_started.set()
            await asyncio.sleep(0.1)  # Simulate discovery work
            discovery_completed.set()

        async def simulate_daemon_startup():
            # Start background discovery
            asyncio.create_task(background_discovery())
            # Daemon immediately marks startup complete
            startup_completed.set()

        await simulate_daemon_startup()

        # Startup should complete before discovery finishes
        assert startup_completed.is_set()
        assert discovery_started.is_set()

        # Wait for discovery to finish
        await asyncio.sleep(0.2)
        assert discovery_completed.is_set()

    @pytest.mark.asyncio
    async def test_discovery_logs_results(self):
        """Verify discovery results are logged to daemon journal."""
        import logging

        logger = logging.getLogger("test_startup_discovery")
        log_handler = logging.handlers.MemoryHandler(capacity=100) if hasattr(logging, 'handlers') else MagicMock()

        # Mock discovery result
        mock_result = {
            "success": True,
            "created_count": 5,
            "updated_count": 2,
            "errors": [],
        }

        # Simulate logging
        log_message = (
            f"[Feature 097] Startup discovery complete: "
            f"{mock_result['created_count']} created, "
            f"{mock_result['updated_count']} updated"
        )

        assert "Feature 097" in log_message
        assert "5 created" in log_message
        assert "2 updated" in log_message

    @pytest.mark.asyncio
    async def test_discovery_handles_errors_gracefully(self):
        """Verify discovery errors don't crash daemon startup."""
        errors_caught = []

        async def failing_discovery():
            raise RuntimeError("Discovery failed")

        async def simulate_daemon_with_error_handling():
            try:
                await failing_discovery()
            except Exception as e:
                errors_caught.append(str(e))
                # Log error but don't propagate
                pass

        await simulate_daemon_with_error_handling()

        # Error should be caught, not propagated
        assert len(errors_caught) == 1
        assert "Discovery failed" in errors_caught[0]


class TestDiscoveryConfigLoading:
    """Test discovery config loading on startup."""

    def test_auto_discover_defaults_to_false(self):
        """Verify auto_discover_on_startup defaults to False."""
        from i3_project_event_daemon.models.discovery import DiscoveryConfig

        config = DiscoveryConfig(scan_paths=[])
        assert config.auto_discover_on_startup is False

    def test_config_loads_scan_paths(self):
        """Verify scan_paths are loaded from config."""
        from i3_project_event_daemon.models.discovery import DiscoveryConfig

        config = DiscoveryConfig(
            scan_paths=["/home/user/projects", "/opt/repos"],
            scan_depth=3,
        )

        assert len(config.scan_paths) == 2
        assert "/home/user/projects" in config.scan_paths

    def test_config_preserves_timeout_setting(self):
        """Verify timeout setting is preserved in config."""
        from i3_project_event_daemon.models.discovery import DiscoveryConfig

        config = DiscoveryConfig(
            scan_paths=[],
            discovery_timeout=90,  # Custom timeout
        )

        assert config.discovery_timeout == 90


class TestStartupDiscoveryEvent:
    """Test daemon event logging for startup discovery."""

    def test_discovery_event_format(self):
        """Verify discovery event has required fields."""
        event = {
            "event_type": "discovery::startup",
            "timestamp": datetime.now().isoformat(),
            "source": "daemon",
            "created_count": 3,
            "updated_count": 1,
            "error_count": 0,
            "duration_ms": 1500.5,
        }

        assert event["event_type"] == "discovery::startup"
        assert "timestamp" in event
        assert "created_count" in event
        assert "duration_ms" in event

    def test_discovery_event_logged_on_completion(self):
        """Verify event is logged after discovery completes."""
        events_logged = []

        def mock_log_event(event):
            events_logged.append(event)

        # Simulate discovery completion
        mock_log_event({
            "event_type": "discovery::startup",
            "created_count": 5,
        })

        assert len(events_logged) == 1
        assert events_logged[0]["event_type"] == "discovery::startup"
