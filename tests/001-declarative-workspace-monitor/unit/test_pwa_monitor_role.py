"""Unit tests for PWA monitor role parsing (Feature 001 - User Story 3).

Tests parsing and validation of PWA-specific monitor role preferences from
pwa-sites.nix declarations.
"""

import pytest
from pathlib import Path

# Import Feature 001 components
import sys
daemon_dir = Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_dir))

from models.monitor_config import MonitorRole, MonitorRoleConfig


class TestPWAMonitorRoleParsing:
    """Test PWA monitor role configuration parsing."""

    def test_pwa_with_explicit_monitor_role(self):
        """Test PWA with explicitly declared monitor role."""
        config = MonitorRoleConfig(
            app_name="youtube-pwa",
            preferred_workspace=50,
            preferred_monitor_role=MonitorRole.TERTIARY,
            source="pwa-sites"
        )

        assert config.app_name == "youtube-pwa"
        assert config.preferred_workspace == 50
        assert config.preferred_monitor_role == MonitorRole.TERTIARY
        assert config.source == "pwa-sites"

    def test_pwa_without_monitor_role(self):
        """Test PWA without explicit monitor role (should be None for inference)."""
        config = MonitorRoleConfig(
            app_name="spotify-pwa",
            preferred_workspace=51,
            preferred_monitor_role=None,
            source="pwa-sites"
        )

        assert config.app_name == "spotify-pwa"
        assert config.preferred_workspace == 51
        assert config.preferred_monitor_role is None  # Will be inferred later
        assert config.source == "pwa-sites"

    def test_pwa_role_validation(self):
        """Test that invalid monitor roles are rejected."""
        with pytest.raises(ValueError, match="Invalid monitor role"):
            # MonitorRole.from_str() should raise ValueError for invalid roles
            MonitorRole.from_str("quaternary")

    def test_pwa_source_must_be_pwa_sites(self):
        """Test that PWA configurations have source='pwa-sites'."""
        config = MonitorRoleConfig(
            app_name="github-pwa",
            preferred_workspace=52,
            preferred_monitor_role=MonitorRole.SECONDARY,
            source="pwa-sites"
        )

        assert config.source == "pwa-sites"

    def test_multiple_pwas_same_role(self):
        """Test multiple PWAs can share the same monitor role."""
        configs = [
            MonitorRoleConfig(
                app_name="youtube-pwa",
                preferred_workspace=50,
                preferred_monitor_role=MonitorRole.TERTIARY,
                source="pwa-sites"
            ),
            MonitorRoleConfig(
                app_name="spotify-pwa",
                preferred_workspace=51,
                preferred_monitor_role=MonitorRole.TERTIARY,
                source="pwa-sites"
            ),
        ]

        # All should have tertiary role
        for config in configs:
            assert config.preferred_monitor_role == MonitorRole.TERTIARY

    def test_pwa_workspace_range_validation(self):
        """Test PWA workspace numbers are validated (1-70)."""
        # Valid workspace
        config = MonitorRoleConfig(
            app_name="gmail-pwa",
            preferred_workspace=53,
            preferred_monitor_role=MonitorRole.TERTIARY,
            source="pwa-sites"
        )
        assert config.preferred_workspace == 53

        # Invalid workspace (too high)
        with pytest.raises(ValueError):
            MonitorRoleConfig(
                app_name="invalid-pwa",
                preferred_workspace=71,  # > 70
                preferred_monitor_role=MonitorRole.TERTIARY,
                source="pwa-sites"
            )

        # Invalid workspace (too low)
        with pytest.raises(ValueError):
            MonitorRoleConfig(
                app_name="invalid-pwa",
                preferred_workspace=0,  # < 1
                preferred_monitor_role=MonitorRole.TERTIARY,
                source="pwa-sites"
            )
