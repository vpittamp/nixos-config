"""Unit tests for MonitorRoleConfig parsing from Nix configuration.

Tests the parsing of monitor role preferences from app-registry-data.nix
and pwa-sites.nix into Pydantic models.
"""

import pytest
from pydantic import ValidationError
import sys
import os

# Add daemon path to sys.path for imports
sys.path.insert(0, "/etc/nixos/home-modules/desktop/i3-project-event-daemon")

from models.monitor_config import MonitorRoleConfig, MonitorRole


class TestMonitorRoleConfigParsing:
    """Test cases for parsing MonitorRoleConfig from Nix."""

    def test_parse_valid_config_with_role(self):
        """Test parsing valid config with explicit monitor role."""
        data = {
            "app_name": "code",
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        config = MonitorRoleConfig(**data)

        assert config.app_name == "code"
        assert config.preferred_workspace == 2
        assert config.preferred_monitor_role == MonitorRole.PRIMARY
        assert config.source == "app-registry"

    def test_parse_valid_config_null_role(self):
        """Test parsing config with null monitor role (will be inferred)."""
        data = {
            "app_name": "firefox",
            "preferred_workspace": 3,
            "preferred_monitor_role": None,
            "source": "app-registry",
        }

        config = MonitorRoleConfig(**data)

        assert config.app_name == "firefox"
        assert config.preferred_workspace == 3
        assert config.preferred_monitor_role is None
        assert config.source == "app-registry"

    def test_parse_pwa_source(self):
        """Test parsing from PWA sites configuration."""
        data = {
            "app_name": "youtube-pwa",
            "preferred_workspace": 50,
            "preferred_monitor_role": "tertiary",
            "source": "pwa-sites",
        }

        config = MonitorRoleConfig(**data)

        assert config.app_name == "youtube-pwa"
        assert config.preferred_workspace == 50
        assert config.preferred_monitor_role == MonitorRole.TERTIARY
        assert config.source == "pwa-sites"

    def test_parse_all_monitor_roles(self):
        """Test parsing all three monitor role values."""
        roles = ["primary", "secondary", "tertiary"]

        for role_str in roles:
            data = {
                "app_name": f"app-{role_str}",
                "preferred_workspace": 1,
                "preferred_monitor_role": role_str,
                "source": "app-registry",
            }

            config = MonitorRoleConfig(**data)
            assert config.preferred_monitor_role.value == role_str

    def test_parse_normalized_role_from_nix(self):
        """Test monitor role is normalized by Nix (receives lowercase)."""
        # Nix validateMonitorRole() normalizes to lowercase via lib.toLower
        # Python receives already-normalized values
        data = {
            "app_name": "code",
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",  # Already normalized by Nix
            "source": "app-registry",
        }

        config = MonitorRoleConfig(**data)
        assert config.preferred_monitor_role == MonitorRole.PRIMARY


class TestMonitorRoleConfigValidation:
    """Test cases for MonitorRoleConfig validation rules."""

    def test_reject_invalid_monitor_role(self):
        """Test validation fails for invalid monitor role."""
        data = {
            "app_name": "code",
            "preferred_workspace": 2,
            "preferred_monitor_role": "quaternary",  # Invalid
            "source": "app-registry",
        }

        with pytest.raises(ValidationError) as exc_info:
            MonitorRoleConfig(**data)

        # Pydantic V2 error includes field name and valid values
        error_str = str(exc_info.value).lower()
        assert "preferred_monitor_role" in error_str
        assert "primary" in error_str or "secondary" in error_str or "tertiary" in error_str

    def test_reject_workspace_below_range(self):
        """Test validation fails for workspace < 1."""
        data = {
            "app_name": "code",
            "preferred_workspace": 0,  # Invalid
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        with pytest.raises(ValidationError) as exc_info:
            MonitorRoleConfig(**data)

        assert "greater than or equal to 1" in str(exc_info.value)

    def test_reject_workspace_above_range(self):
        """Test validation fails for workspace > 70."""
        data = {
            "app_name": "code",
            "preferred_workspace": 71,  # Invalid
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        with pytest.raises(ValidationError) as exc_info:
            MonitorRoleConfig(**data)

        assert "less than or equal to 70" in str(exc_info.value)

    def test_reject_empty_app_name(self):
        """Test validation fails for empty app name."""
        data = {
            "app_name": "",  # Invalid
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        with pytest.raises(ValidationError) as exc_info:
            MonitorRoleConfig(**data)

        assert "app_name cannot be empty" in str(exc_info.value)

    def test_reject_invalid_source(self):
        """Test validation fails for invalid source."""
        data = {
            "app_name": "code",
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",
            "source": "unknown-source",  # Invalid
        }

        with pytest.raises(ValidationError) as exc_info:
            MonitorRoleConfig(**data)

        assert "source" in str(exc_info.value).lower()

    def test_reject_missing_required_field(self):
        """Test validation fails when required field is missing."""
        data = {
            # Missing app_name
            "preferred_workspace": 2,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        with pytest.raises(ValidationError) as exc_info:
            MonitorRoleConfig(**data)

        assert "app_name" in str(exc_info.value).lower()


class TestMonitorRoleConfigBoundaryConditions:
    """Test cases for boundary conditions."""

    def test_workspace_minimum_value(self):
        """Test workspace 1 (minimum valid value)."""
        data = {
            "app_name": "terminal",
            "preferred_workspace": 1,
            "preferred_monitor_role": "primary",
            "source": "app-registry",
        }

        config = MonitorRoleConfig(**data)
        assert config.preferred_workspace == 1

    def test_workspace_maximum_value(self):
        """Test workspace 70 (maximum valid value)."""
        data = {
            "app_name": "special-app",
            "preferred_workspace": 70,
            "preferred_monitor_role": "tertiary",
            "source": "app-registry",
        }

        config = MonitorRoleConfig(**data)
        assert config.preferred_workspace == 70

    def test_workspace_pwa_range(self):
        """Test PWA workspace range (50-70)."""
        for ws in [50, 60, 70]:
            data = {
                "app_name": f"pwa-{ws}",
                "preferred_workspace": ws,
                "preferred_monitor_role": "secondary",
                "source": "pwa-sites",
            }

            config = MonitorRoleConfig(**data)
            assert config.preferred_workspace == ws
            assert config.source == "pwa-sites"
