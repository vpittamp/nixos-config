"""Integration tests for output preference assignment and fallback.

Tests the interaction between output_preferences configuration and
MonitorRoleResolver to ensure preferred outputs are assigned correctly.
"""

import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch
from typing import List

# Add daemon path to sys.path for imports
sys.path.insert(0, "/etc/nixos/home-modules/desktop/i3-project-event-daemon")

from models.monitor_config import MonitorRole, OutputInfo, MonitorRoleAssignment
from monitor_role_resolver import MonitorRoleResolver


class TestPreferredOutputAssignment:
    """Test cases for preferred output assignment logic."""

    @pytest.fixture
    def resolver(self):
        """Create MonitorRoleResolver with mock connection."""
        conn = AsyncMock()
        return MonitorRoleResolver(conn)

    @pytest.fixture
    def connected_outputs(self) -> List[OutputInfo]:
        """Mock connected outputs in specific order."""
        return [
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=1.0),
            OutputInfo(name="HDMI-A-1", active=True, primary=False, connected_at=2.0),
            OutputInfo(name="DP-1", active=True, primary=False, connected_at=3.0),
        ]

    def test_preferred_output_overrides_connection_order(self, resolver, connected_outputs):
        """Test that output preferences override connection order."""
        # Configure preference: HDMI-A-1 should be primary
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }
        resolver.output_preferences = preferences

        # Resolve roles (eDP-1 connected first but HDMI-A-1 preferred)
        assignments = resolver.resolve_all_roles(connected_outputs)

        # HDMI-A-1 should get primary role despite connecting second
        primary_assignment = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)
        assert primary_assignment.output_name == "HDMI-A-1"
        assert primary_assignment.preferred_output is True

    def test_preferred_output_not_connected_fallback(self, resolver, connected_outputs):
        """Test fallback when preferred output is not connected."""
        # Configure preference: DVI-I-1 preferred but not connected
        preferences = {
            MonitorRole.PRIMARY: ["DVI-I-1"]
        }
        resolver.output_preferences = preferences

        # Resolve roles (should fall back to connection order)
        assignments = resolver.resolve_all_roles(connected_outputs)

        # Should use connection order (first connected output)
        primary_assignment = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)
        assert primary_assignment.output_name == "eDP-1"
        assert primary_assignment.preferred_output is False
        assert primary_assignment.fallback_applied is False  # Not a monitor role fallback

    def test_multiple_roles_with_preferences(self, resolver, connected_outputs):
        """Test assignment when multiple roles have output preferences."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"],
            MonitorRole.SECONDARY: ["DP-1"],
            MonitorRole.TERTIARY: ["eDP-1"]
        }
        resolver.output_preferences = preferences

        assignments = resolver.resolve_all_roles(connected_outputs)

        # Verify each role gets its preferred output
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)
        secondary = next(a for a in assignments if a.monitor_role == MonitorRole.SECONDARY)
        tertiary = next(a for a in assignments if a.monitor_role == MonitorRole.TERTIARY)

        assert primary.output_name == "HDMI-A-1"
        assert secondary.output_name == "DP-1"
        assert tertiary.output_name == "eDP-1"

    def test_no_preferences_uses_connection_order(self, resolver, connected_outputs):
        """Test that missing preferences defaults to connection order."""
        # No preferences configured
        resolver.output_preferences = {}

        assignments = resolver.resolve_all_roles(connected_outputs)

        # Should use connection order
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)
        secondary = next(a for a in assignments if a.monitor_role == MonitorRole.SECONDARY)
        tertiary = next(a for a in assignments if a.monitor_role == MonitorRole.TERTIARY)

        assert primary.output_name == "eDP-1"      # Connected first
        assert secondary.output_name == "HDMI-A-1"  # Connected second
        assert tertiary.output_name == "DP-1"       # Connected third


class TestPreferredOutputFallbackChain:
    """Test cases for fallback chain when preferred outputs are disconnected."""

    @pytest.fixture
    def resolver(self):
        """Create MonitorRoleResolver with mock connection."""
        conn = AsyncMock()
        return MonitorRoleResolver(conn)

    def test_fallback_to_second_preferred_output(self, resolver):
        """Test fallback to second output in preference list."""
        connected_outputs = [
            OutputInfo(name="DP-1", active=True, primary=False, connected_at=1.0),
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=2.0),
        ]

        # HDMI-A-1 not connected, should use DP-1 (second preference)
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1", "eDP-1"]
        }
        resolver.output_preferences = preferences

        assignments = resolver.resolve_all_roles(connected_outputs)
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)

        assert primary.output_name == "DP-1"  # Second in preference list
        assert primary.preferred_output is True

    def test_exhaust_all_preferences_fallback_to_connection_order(self, resolver):
        """Test fallback to connection order when all preferences disconnected."""
        connected_outputs = [
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=1.0),
        ]

        # None of the preferred outputs are connected
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1", "DP-2"]
        }
        resolver.output_preferences = preferences

        assignments = resolver.resolve_all_roles(connected_outputs)
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)

        # Should fall back to connection order (only eDP-1 available)
        assert primary.output_name == "eDP-1"
        assert primary.preferred_output is False

    def test_partial_preference_match(self, resolver):
        """Test when some roles match preferences, others don't."""
        connected_outputs = [
            OutputInfo(name="HDMI-A-1", active=True, primary=False, connected_at=1.0),
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=2.0),
        ]

        # Primary has preference, secondary uses connection order
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"],
            # Secondary not specified → use connection order
        }
        resolver.output_preferences = preferences

        assignments = resolver.resolve_all_roles(connected_outputs)
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)
        secondary = next(a for a in assignments if a.monitor_role == MonitorRole.SECONDARY)

        assert primary.output_name == "HDMI-A-1"
        assert primary.preferred_output is True
        assert secondary.output_name == "eDP-1"
        assert secondary.preferred_output is False


class TestOutputPreferencePriority:
    """Test cases for output preference priority vs other assignment mechanisms."""

    @pytest.fixture
    def resolver(self):
        """Create MonitorRoleResolver with mock connection."""
        conn = AsyncMock()
        return MonitorRoleResolver(conn)

    def test_output_preference_higher_priority_than_connection_order(self, resolver):
        """Test that output preferences take priority over connection order."""
        connected_outputs = [
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=1.0),
            OutputInfo(name="HDMI-A-1", active=True, primary=False, connected_at=2.0),
        ]

        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }
        resolver.output_preferences = preferences

        assignments = resolver.resolve_all_roles(connected_outputs)
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)

        # HDMI-A-1 preferred despite eDP-1 connecting first
        assert primary.output_name == "HDMI-A-1"

    def test_output_preference_with_single_monitor(self, resolver):
        """Test output preference when only one monitor connected."""
        connected_outputs = [
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=1.0),
        ]

        # Prefer HDMI-A-1 but only eDP-1 connected
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }
        resolver.output_preferences = preferences

        assignments = resolver.resolve_all_roles(connected_outputs)
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)

        # Should assign eDP-1 (only available output)
        assert primary.output_name == "eDP-1"


class TestOutputPreferenceWithMonitorDisconnect:
    """Test cases for output preference interaction with monitor disconnect."""

    @pytest.fixture
    def resolver(self):
        """Create MonitorRoleResolver with mock connection."""
        conn = AsyncMock()
        return MonitorRoleResolver(conn)

    def test_disconnect_preferred_output_fallback_to_next(self, resolver):
        """Test fallback when preferred output disconnects."""
        # Initial: Three monitors, HDMI-A-1 is preferred primary
        initial_outputs = [
            OutputInfo(name="HDMI-A-1", active=True, primary=False, connected_at=1.0),
            OutputInfo(name="DP-1", active=True, primary=False, connected_at=2.0),
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=3.0),
        ]

        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1", "eDP-1"]
        }
        resolver.output_preferences = preferences

        # Initial assignment
        assignments = resolver.resolve_all_roles(initial_outputs)
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)
        assert primary.output_name == "HDMI-A-1"

        # HDMI-A-1 disconnects
        updated_outputs = [
            OutputInfo(name="DP-1", active=True, primary=False, connected_at=2.0),
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=3.0),
        ]

        # Re-resolve roles
        new_assignments = resolver.resolve_all_roles(updated_outputs)
        new_primary = next(a for a in new_assignments if a.monitor_role == MonitorRole.PRIMARY)

        # Should fall back to second preference (DP-1)
        assert new_primary.output_name == "DP-1"
        assert new_primary.preferred_output is True

    def test_reconnect_preferred_output_restores_assignment(self, resolver):
        """Test that reconnecting preferred output restores assignment."""
        # Start with fallback output (DP-1)
        fallback_outputs = [
            OutputInfo(name="DP-1", active=True, primary=False, connected_at=1.0),
        ]

        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1"]
        }
        resolver.output_preferences = preferences

        # Initial assignment (fallback to DP-1)
        assignments = resolver.resolve_all_roles(fallback_outputs)
        primary = next(a for a in assignments if a.monitor_role == MonitorRole.PRIMARY)
        assert primary.output_name == "DP-1"

        # HDMI-A-1 reconnects
        restored_outputs = [
            OutputInfo(name="DP-1", active=True, primary=False, connected_at=1.0),
            OutputInfo(name="HDMI-A-1", active=True, primary=False, connected_at=2.0),
        ]

        # Re-resolve roles
        new_assignments = resolver.resolve_all_roles(restored_outputs)
        new_primary = next(a for a in new_assignments if a.monitor_role == MonitorRole.PRIMARY)

        # Should restore preferred output (HDMI-A-1)
        assert new_primary.output_name == "HDMI-A-1"
        assert new_primary.preferred_output is True


class TestOutputPreferenceLogging:
    """Test cases for logging output preference matches and misses."""

    @pytest.fixture
    def resolver(self):
        """Create MonitorRoleResolver with mock connection."""
        conn = AsyncMock()
        return MonitorRoleResolver(conn)

    def test_log_preferred_output_match(self, resolver, caplog):
        """Test logging when preferred output matches connected output."""
        connected_outputs = [
            OutputInfo(name="HDMI-A-1", active=True, primary=False, connected_at=1.0),
        ]

        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }
        resolver.output_preferences = preferences

        with caplog.at_level("INFO"):
            assignments = resolver.resolve_all_roles(connected_outputs)

        # Should log successful match
        assert any("HDMI-A-1" in record.message and "primary" in record.message.lower()
                   for record in caplog.records)

    def test_log_preferred_output_miss(self, resolver, caplog):
        """Test logging when preferred output is not connected."""
        connected_outputs = [
            OutputInfo(name="eDP-1", active=True, primary=False, connected_at=1.0),
        ]

        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }
        resolver.output_preferences = preferences

        with caplog.at_level("WARNING"):
            assignments = resolver.resolve_all_roles(connected_outputs)

        # Should log fallback warning
        assert any("HDMI-A-1" in record.message or "preferred" in record.message.lower()
                   for record in caplog.records)
