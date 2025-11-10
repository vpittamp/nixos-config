"""Integration tests for monitor fallback logic (Feature 001 - User Story 2).

Tests automatic workspace reassignment when monitors disconnect:
- Tertiary → Secondary fallback
- Secondary → Primary fallback
- Automatic workspace restoration on reconnect

Test environment: 3 mock outputs (PRIMARY, SECONDARY, TERTIARY)
"""

import pytest
from typing import List, Dict
from unittest.mock import AsyncMock, MagicMock

# Import Feature 001 components
import sys
from pathlib import Path

# Add daemon directory to path for imports
daemon_dir = Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_dir))

from monitor_role_resolver import MonitorRoleResolver
from models.monitor_config import (
    MonitorRole,
    OutputInfo,
    MonitorRoleConfig,
    MonitorRoleAssignment,
)


@pytest.fixture
def three_outputs() -> List[OutputInfo]:
    """Three active outputs for full monitor setup."""
    return [
        OutputInfo(name="HEADLESS-1", active=True, width=1920, height=1200, scale=1.0),
        OutputInfo(name="HEADLESS-2", active=True, width=1920, height=1200, scale=1.0),
        OutputInfo(name="HEADLESS-3", active=True, width=1920, height=1200, scale=1.0),
    ]


@pytest.fixture
def two_outputs() -> List[OutputInfo]:
    """Two active outputs (tertiary disconnected)."""
    return [
        OutputInfo(name="HEADLESS-1", active=True, width=1920, height=1200, scale=1.0),
        OutputInfo(name="HEADLESS-2", active=True, width=1920, height=1200, scale=1.0),
    ]


@pytest.fixture
def one_output() -> List[OutputInfo]:
    """One active output (secondary and tertiary disconnected)."""
    return [
        OutputInfo(name="HEADLESS-1", active=True, width=1920, height=1200, scale=1.0),
    ]


@pytest.fixture
def sample_configs() -> List[MonitorRoleConfig]:
    """Sample app configurations with monitor role preferences."""
    return [
        # WS 1: Terminal on primary (explicit)
        MonitorRoleConfig(
            app_name="terminal",
            preferred_workspace=1,
            preferred_monitor_role=MonitorRole.PRIMARY,
            source="app-registry"
        ),
        # WS 6: Thunar on tertiary (explicit)
        MonitorRoleConfig(
            app_name="thunar",
            preferred_workspace=6,
            preferred_monitor_role=MonitorRole.TERTIARY,
            source="app-registry"
        ),
        # WS 7: btop on tertiary (inferred)
        MonitorRoleConfig(
            app_name="btop",
            preferred_workspace=7,
            preferred_monitor_role=None,  # Will be inferred as tertiary
            source="app-registry"
        ),
        # WS 50: YouTube PWA on tertiary (explicit)
        MonitorRoleConfig(
            app_name="youtube-pwa",
            preferred_workspace=50,
            preferred_monitor_role=MonitorRole.TERTIARY,
            source="pwa-sites"
        ),
    ]


class TestTertiaryToSecondaryFallback:
    """Test tertiary→secondary fallback when tertiary monitor disconnects."""

    def test_tertiary_workspace_falls_back_to_secondary(
        self,
        three_outputs: List[OutputInfo],
        two_outputs: List[OutputInfo],
        sample_configs: List[MonitorRoleConfig]
    ):
        """Test WS 6 (tertiary) falls back to secondary when tertiary disconnects."""
        resolver = MonitorRoleResolver()

        # Initial state: 3 monitors, WS 6 on tertiary (HEADLESS-3)
        role_assignments_3mon = resolver.resolve_role(sample_configs, three_outputs)

        assert MonitorRole.TERTIARY in role_assignments_3mon
        tertiary_output_3mon = role_assignments_3mon[MonitorRole.TERTIARY].output
        assert tertiary_output_3mon == "HEADLESS-3"

        ws6_output_3mon = resolver.get_output_for_workspace(
            workspace_num=6,
            role_assignments=role_assignments_3mon,
            config=sample_configs[1]  # Thunar on WS 6
        )
        assert ws6_output_3mon == "HEADLESS-3"

        # Tertiary monitor disconnects: 2 monitors remain
        role_assignments_2mon = resolver.resolve_role(sample_configs, two_outputs)

        assert MonitorRole.TERTIARY not in role_assignments_2mon  # Tertiary unavailable
        assert MonitorRole.SECONDARY in role_assignments_2mon
        secondary_output = role_assignments_2mon[MonitorRole.SECONDARY].output
        assert secondary_output == "HEADLESS-2"

        # Apply fallback for WS 6
        ws6_output_fallback = resolver.apply_fallback(role_assignments_2mon, MonitorRole.TERTIARY)
        assert ws6_output_fallback == "HEADLESS-2"  # Falls back to secondary

    def test_tertiary_workspace_with_inferred_role_falls_back(
        self,
        three_outputs: List[OutputInfo],
        two_outputs: List[OutputInfo],
        sample_configs: List[MonitorRoleConfig]
    ):
        """Test WS 7 (inferred tertiary) falls back to secondary."""
        resolver = MonitorRoleResolver()

        # Initial: 3 monitors, WS 7 inferred as tertiary
        inferred_role = resolver.infer_monitor_role_from_workspace(7)
        assert inferred_role == MonitorRole.TERTIARY

        role_assignments_3mon = resolver.resolve_role(sample_configs, three_outputs)
        ws7_output_3mon = resolver.get_output_for_workspace(
            workspace_num=7,
            role_assignments=role_assignments_3mon,
            config=sample_configs[2]  # btop on WS 7, role=None
        )
        assert ws7_output_3mon == "HEADLESS-3"

        # After disconnect: WS 7 should fall back to secondary
        role_assignments_2mon = resolver.resolve_role(sample_configs, two_outputs)
        ws7_output_fallback = resolver.get_output_for_workspace(
            workspace_num=7,
            role_assignments=role_assignments_2mon,
            config=sample_configs[2]
        )
        assert ws7_output_fallback == "HEADLESS-2"


class TestSecondaryToPrimaryFallback:
    """Test secondary→primary fallback when secondary monitor disconnects."""

    def test_secondary_workspace_falls_back_to_primary(
        self,
        two_outputs: List[OutputInfo],
        one_output: List[OutputInfo],
        sample_configs: List[MonitorRoleConfig]
    ):
        """Test WS 3-5 (secondary) fall back to primary when secondary disconnects."""
        resolver = MonitorRoleResolver()

        # Create config for WS 3 (secondary)
        ws3_config = MonitorRoleConfig(
            app_name="firefox",
            preferred_workspace=3,
            preferred_monitor_role=MonitorRole.SECONDARY,
            source="app-registry"
        )

        # Initial: 2 monitors, WS 3 on secondary (HEADLESS-2)
        role_assignments_2mon = resolver.resolve_role([ws3_config], two_outputs)
        ws3_output_2mon = resolver.get_output_for_workspace(
            workspace_num=3,
            role_assignments=role_assignments_2mon,
            config=ws3_config
        )
        assert ws3_output_2mon == "HEADLESS-2"

        # Secondary disconnects: 1 monitor remains
        role_assignments_1mon = resolver.resolve_role([ws3_config], one_output)

        assert MonitorRole.PRIMARY in role_assignments_1mon
        assert MonitorRole.SECONDARY not in role_assignments_1mon

        # Apply fallback for WS 3
        ws3_output_fallback = resolver.apply_fallback(role_assignments_1mon, MonitorRole.SECONDARY)
        assert ws3_output_fallback == "HEADLESS-1"  # Falls back to primary


class TestPrimaryNoFallback:
    """Test primary monitor has no fallback (must be present)."""

    def test_primary_workspace_has_no_fallback(
        self,
        one_output: List[OutputInfo],
        sample_configs: List[MonitorRoleConfig]
    ):
        """Test WS 1 (primary) returns None if primary disconnects."""
        resolver = MonitorRoleResolver()

        # Edge case: No active outputs
        empty_outputs: List[OutputInfo] = []
        role_assignments_empty = resolver.resolve_role(sample_configs, empty_outputs)

        assert role_assignments_empty == {}

        # Primary should have no fallback
        fallback_output = resolver.apply_fallback(role_assignments_empty, MonitorRole.PRIMARY)
        assert fallback_output is None


class TestMultipleWorkspaceFallback:
    """Test multiple workspaces fall back simultaneously."""

    def test_all_tertiary_workspaces_fall_back_together(
        self,
        three_outputs: List[OutputInfo],
        two_outputs: List[OutputInfo]
    ):
        """Test WS 6, 7, 8, 9, 50+ all fall back to secondary when tertiary disconnects."""
        resolver = MonitorRoleResolver()

        tertiary_workspaces = [6, 7, 8, 9, 50, 51, 52]
        configs = [
            MonitorRoleConfig(
                app_name=f"app-ws{ws}",
                preferred_workspace=ws,
                preferred_monitor_role=None,  # Will be inferred as tertiary
                source="app-registry"
            )
            for ws in tertiary_workspaces
        ]

        # Initial: All on HEADLESS-3
        role_assignments_3mon = resolver.resolve_role(configs, three_outputs)
        for config in configs:
            output = resolver.get_output_for_workspace(
                workspace_num=config.preferred_workspace,
                role_assignments=role_assignments_3mon,
                config=config
            )
            assert output == "HEADLESS-3"

        # After disconnect: All fall back to HEADLESS-2
        role_assignments_2mon = resolver.resolve_role(configs, two_outputs)
        for config in configs:
            output = resolver.get_output_for_workspace(
                workspace_num=config.preferred_workspace,
                role_assignments=role_assignments_2mon,
                config=config
            )
            assert output == "HEADLESS-2"


class TestWorkspaceRestoration:
    """Test automatic workspace restoration when monitors reconnect."""

    def test_workspace_restores_to_preferred_role_on_reconnect(
        self,
        three_outputs: List[OutputInfo],
        two_outputs: List[OutputInfo],
        sample_configs: List[MonitorRoleConfig]
    ):
        """Test WS 6 returns to tertiary when monitor reconnects."""
        resolver = MonitorRoleResolver()

        # Initial: WS 6 on tertiary
        role_assignments_initial = resolver.resolve_role(sample_configs, three_outputs)
        ws6_config = sample_configs[1]  # Thunar on WS 6, role=tertiary
        ws6_output_initial = resolver.get_output_for_workspace(
            workspace_num=6,
            role_assignments=role_assignments_initial,
            config=ws6_config
        )
        assert ws6_output_initial == "HEADLESS-3"

        # Disconnect tertiary: WS 6 falls back to secondary
        role_assignments_fallback = resolver.resolve_role(sample_configs, two_outputs)
        ws6_output_fallback = resolver.get_output_for_workspace(
            workspace_num=6,
            role_assignments=role_assignments_fallback,
            config=ws6_config
        )
        assert ws6_output_fallback == "HEADLESS-2"

        # Reconnect tertiary: WS 6 should restore to HEADLESS-3
        role_assignments_restored = resolver.resolve_role(sample_configs, three_outputs)
        ws6_output_restored = resolver.get_output_for_workspace(
            workspace_num=6,
            role_assignments=role_assignments_restored,
            config=ws6_config
        )
        assert ws6_output_restored == "HEADLESS-3"
