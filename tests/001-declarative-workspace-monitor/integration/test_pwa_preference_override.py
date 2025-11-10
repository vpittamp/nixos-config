"""Integration tests for PWA preference priority (Feature 001 - User Story 3).

Tests that PWA-specific monitor preferences override app registry preferences
when both target the same workspace.
"""

import pytest
from typing import List
from pathlib import Path

# Import Feature 001 components
import sys
daemon_dir = Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_dir))

from monitor_role_resolver import MonitorRoleResolver
from models.monitor_config import (
    MonitorRole,
    OutputInfo,
    MonitorRoleConfig,
)


@pytest.fixture
def two_outputs() -> List[OutputInfo]:
    """Two active outputs (primary and secondary)."""
    return [
        OutputInfo(name="HEADLESS-1", active=True, width=1920, height=1200, scale=1.0),
        OutputInfo(name="HEADLESS-2", active=True, width=1920, height=1200, scale=1.0),
    ]


class TestPWAPreferenceOverride:
    """Test PWA preference priority over app registry preferences."""

    def test_pwa_overrides_app_same_workspace(self, two_outputs: List[OutputInfo]):
        """Test PWA preference wins when PWA and app both target WS 50."""
        resolver = MonitorRoleResolver()

        # App registry: workspace 50 → primary (hypothetical)
        app_config = MonitorRoleConfig(
            app_name="generic-app",
            preferred_workspace=50,
            preferred_monitor_role=MonitorRole.PRIMARY,
            source="app-registry"
        )

        # PWA sites: workspace 50 → secondary (overrides app)
        pwa_config = MonitorRoleConfig(
            app_name="youtube-pwa",
            preferred_workspace=50,
            preferred_monitor_role=MonitorRole.SECONDARY,
            source="pwa-sites"
        )

        # Process both configs (PWA should win)
        configs = [app_config, pwa_config]

        # Resolve monitor roles
        role_assignments = resolver.resolve_role(configs, two_outputs)

        # Both roles should exist
        assert MonitorRole.PRIMARY in role_assignments
        assert MonitorRole.SECONDARY in role_assignments

        # When building workspace assignments, PWA should win for WS 50
        # (This is done in workspace_manager.py by processing PWAs after apps)
        workspace_to_config = {}
        for config in configs:
            workspace_to_config[config.preferred_workspace] = config  # Last one wins

        # PWA should be the final config for WS 50
        assert workspace_to_config[50].app_name == "youtube-pwa"
        assert workspace_to_config[50].source == "pwa-sites"
        assert workspace_to_config[50].preferred_monitor_role == MonitorRole.SECONDARY

        # Verify output assignment uses PWA's preference
        output = resolver.get_output_for_workspace(
            workspace_num=50,
            role_assignments=role_assignments,
            config=workspace_to_config[50]
        )
        assert output == "HEADLESS-2"  # Secondary monitor

    def test_pwa_without_conflict(self, two_outputs: List[OutputInfo]):
        """Test PWA on unique workspace (no app conflict)."""
        resolver = MonitorRoleResolver()

        # App on WS 2
        app_config = MonitorRoleConfig(
            app_name="vscode",
            preferred_workspace=2,
            preferred_monitor_role=MonitorRole.PRIMARY,
            source="app-registry"
        )

        # PWA on WS 50 (no conflict)
        pwa_config = MonitorRoleConfig(
            app_name="youtube-pwa",
            preferred_workspace=50,
            preferred_monitor_role=MonitorRole.SECONDARY,
            source="pwa-sites"
        )

        configs = [app_config, pwa_config]
        role_assignments = resolver.resolve_role(configs, two_outputs)

        # Build workspace assignments
        workspace_to_config = {
            config.preferred_workspace: config
            for config in configs
        }

        # Both should coexist peacefully
        assert 2 in workspace_to_config
        assert 50 in workspace_to_config

        # Verify assignments
        vscode_output = resolver.get_output_for_workspace(
            workspace_num=2,
            role_assignments=role_assignments,
            config=workspace_to_config[2]
        )
        assert vscode_output == "HEADLESS-1"  # Primary

        youtube_output = resolver.get_output_for_workspace(
            workspace_num=50,
            role_assignments=role_assignments,
            config=workspace_to_config[50]
        )
        assert youtube_output == "HEADLESS-2"  # Secondary

    def test_multiple_pwas_no_override(self, two_outputs: List[OutputInfo]):
        """Test multiple PWAs on different workspaces (no conflicts)."""
        resolver = MonitorRoleResolver()

        configs = [
            MonitorRoleConfig(
                app_name="youtube-pwa",
                preferred_workspace=50,
                preferred_monitor_role=MonitorRole.SECONDARY,
                source="pwa-sites"
            ),
            MonitorRoleConfig(
                app_name="spotify-pwa",
                preferred_workspace=51,
                preferred_monitor_role=MonitorRole.SECONDARY,
                source="pwa-sites"
            ),
            MonitorRoleConfig(
                app_name="github-pwa",
                preferred_workspace=52,
                preferred_monitor_role=MonitorRole.SECONDARY,
                source="pwa-sites"
            ),
        ]

        role_assignments = resolver.resolve_role(configs, two_outputs)

        # All PWAs should map to secondary monitor
        for config in configs:
            output = resolver.get_output_for_workspace(
                workspace_num=config.preferred_workspace,
                role_assignments=role_assignments,
                config=config
            )
            assert output == "HEADLESS-2"  # All on secondary

    def test_pwa_ordering_determines_winner(self, two_outputs: List[OutputInfo]):
        """Test that last PWA wins when multiple PWAs target same workspace."""
        resolver = MonitorRoleResolver()

        # Two PWAs targeting WS 50 (unlikely but possible in misconfiguration)
        configs = [
            MonitorRoleConfig(
                app_name="youtube-pwa",
                preferred_workspace=50,
                preferred_monitor_role=MonitorRole.PRIMARY,
                source="pwa-sites"
            ),
            MonitorRoleConfig(
                app_name="spotify-pwa",
                preferred_workspace=50,  # Same workspace!
                preferred_monitor_role=MonitorRole.SECONDARY,
                source="pwa-sites"
            ),
        ]

        role_assignments = resolver.resolve_role(configs, two_outputs)

        # Last one wins (Spotify PWA)
        workspace_to_config = {}
        for config in configs:
            workspace_to_config[config.preferred_workspace] = config

        assert workspace_to_config[50].app_name == "spotify-pwa"
        assert workspace_to_config[50].preferred_monitor_role == MonitorRole.SECONDARY

        # Output should use Spotify's preference
        output = resolver.get_output_for_workspace(
            workspace_num=50,
            role_assignments=role_assignments,
            config=workspace_to_config[50]
        )
        assert output == "HEADLESS-2"  # Secondary
