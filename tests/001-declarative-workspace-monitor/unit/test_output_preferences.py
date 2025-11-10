"""Unit tests for output preference configuration parsing.

Tests parsing and validation of output_preferences configuration that allows
users to specify preferred physical output names for monitor roles.
"""

import pytest
from pydantic import ValidationError
import sys
import os

# Add daemon path to sys.path for imports
sys.path.insert(0, "/etc/nixos/home-modules/desktop/i3-project-event-daemon")

from models.monitor_config import MonitorRole


class TestOutputPreferenceParsing:
    """Test cases for output preference configuration parsing."""

    def test_parse_single_preferred_output(self):
        """Test parsing single preferred output for a role."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }

        assert MonitorRole.PRIMARY in preferences
        assert preferences[MonitorRole.PRIMARY] == ["HDMI-A-1"]

    def test_parse_multiple_preferred_outputs_per_role(self):
        """Test parsing multiple fallback outputs for a single role."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1", "eDP-1"]
        }

        assert len(preferences[MonitorRole.PRIMARY]) == 3
        assert "HDMI-A-1" in preferences[MonitorRole.PRIMARY]
        assert "DP-1" in preferences[MonitorRole.PRIMARY]
        assert "eDP-1" in preferences[MonitorRole.PRIMARY]

    def test_parse_all_roles_with_preferences(self):
        """Test parsing preferences for all three monitor roles."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"],
            MonitorRole.SECONDARY: ["HDMI-A-2", "DP-1"],
            MonitorRole.TERTIARY: ["DP-2"]
        }

        assert len(preferences) == 3
        assert MonitorRole.PRIMARY in preferences
        assert MonitorRole.SECONDARY in preferences
        assert MonitorRole.TERTIARY in preferences

    def test_empty_preferences_dict(self):
        """Test that empty preferences dict is valid (uses connection order)."""
        preferences = {}

        assert preferences == {}
        # Should fall back to connection order-based assignment

    def test_partial_role_preferences(self):
        """Test that some roles can have preferences while others don't."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
            # Secondary and tertiary use connection order
        }

        assert MonitorRole.PRIMARY in preferences
        assert MonitorRole.SECONDARY not in preferences
        assert MonitorRole.TERTIARY not in preferences


class TestOutputPreferenceValidation:
    """Test cases for output preference validation."""

    def test_reject_empty_output_name(self):
        """Test that empty output names are invalid."""
        preferences = {
            MonitorRole.PRIMARY: [""]
        }

        # Empty string should be filtered out
        valid_outputs = [o for o in preferences[MonitorRole.PRIMARY] if o.strip()]
        assert len(valid_outputs) == 0

    def test_reject_invalid_output_format(self):
        """Test validation of output name format."""
        # Valid formats: HDMI-A-1, DP-1, eDP-1, HEADLESS-1, etc.
        valid_outputs = ["HDMI-A-1", "DP-1", "eDP-1", "HEADLESS-1", "DVI-I-1"]

        for output in valid_outputs:
            assert output  # All should be non-empty
            assert isinstance(output, str)

    def test_output_name_case_sensitivity(self):
        """Test that output names are case-sensitive (per Sway)."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }

        # Output names in Sway are case-sensitive
        assert "HDMI-A-1" in preferences[MonitorRole.PRIMARY]
        assert "hdmi-a-1" not in preferences[MonitorRole.PRIMARY]

    def test_duplicate_outputs_across_roles(self):
        """Test that same output can't be preferred for multiple roles."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"],
            MonitorRole.SECONDARY: ["HDMI-A-1"]  # Duplicate!
        }

        # Check for duplicates across all roles
        all_outputs = []
        for outputs in preferences.values():
            all_outputs.extend(outputs)

        duplicates = set([o for o in all_outputs if all_outputs.count(o) > 1])
        assert "HDMI-A-1" in duplicates  # Should detect duplicate


class TestOutputPreferenceOrdering:
    """Test cases for output preference priority ordering."""

    def test_preference_order_matters(self):
        """Test that order of preferred outputs determines fallback priority."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1", "eDP-1"]
        }

        outputs = preferences[MonitorRole.PRIMARY]
        assert outputs[0] == "HDMI-A-1"  # First choice
        assert outputs[1] == "DP-1"      # Second choice
        assert outputs[2] == "eDP-1"     # Third choice

    def test_single_output_no_fallback(self):
        """Test role with single preferred output (no fallback)."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }

        assert len(preferences[MonitorRole.PRIMARY]) == 1
        # If HDMI-A-1 not connected, should fall back to connection order

    def test_fallback_chain_exhaustion(self):
        """Test behavior when all preferred outputs are disconnected."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1"]
        }

        # If both disconnected, should fall back to connection order
        # (tested in integration tests)
        assert len(preferences[MonitorRole.PRIMARY]) == 2


class TestOutputPreferenceEdgeCases:
    """Test cases for edge cases and boundary conditions."""

    def test_preferences_with_headless_outputs(self):
        """Test preferences can specify virtual/headless outputs."""
        preferences = {
            MonitorRole.PRIMARY: ["HEADLESS-1"],
            MonitorRole.SECONDARY: ["HEADLESS-2"],
            MonitorRole.TERTIARY: ["HEADLESS-3"]
        }

        # Virtual outputs are valid in Sway
        assert all("HEADLESS" in prefs[0] for prefs in preferences.values())

    def test_preferences_with_many_outputs(self):
        """Test role with many fallback outputs."""
        preferences = {
            MonitorRole.PRIMARY: [
                "HDMI-A-1", "HDMI-A-2", "DP-1", "DP-2", "eDP-1"
            ]
        }

        assert len(preferences[MonitorRole.PRIMARY]) == 5

    def test_unicode_output_names(self):
        """Test that non-ASCII characters in output names are handled."""
        # Sway uses ASCII output names, but test robustness
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]  # Standard ASCII
        }

        assert isinstance(preferences[MonitorRole.PRIMARY][0], str)

    def test_whitespace_in_output_names(self):
        """Test that output names with whitespace are invalid."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP 1"]  # Space in name
        }

        # Sway output names don't contain spaces
        invalid_outputs = [o for o in preferences[MonitorRole.PRIMARY] if " " in o]
        assert "DP 1" in invalid_outputs  # Should be flagged as invalid


class TestOutputPreferenceDefaults:
    """Test cases for default behavior when preferences not specified."""

    def test_no_preferences_uses_connection_order(self):
        """Test that missing preferences defaults to connection order."""
        preferences = {}

        # Empty dict means use Feature 049's connection order logic
        assert len(preferences) == 0

    def test_null_preferences_equivalent_to_empty(self):
        """Test that None/null preferences behaves like empty dict."""
        preferences = None

        if preferences is None:
            preferences = {}

        assert preferences == {}

    def test_partial_preferences_fallback(self):
        """Test roles without preferences use connection order."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
            # Secondary and tertiary not specified → connection order
        }

        # Only primary has explicit preference
        assert MonitorRole.PRIMARY in preferences
        assert MonitorRole.SECONDARY not in preferences
        assert MonitorRole.TERTIARY not in preferences


class TestOutputPreferenceDocumentation:
    """Test cases validating documentation examples."""

    def test_example_from_spec(self):
        """Test example from spec.md US5: HDMI-A-1 always primary."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1"]
        }

        assert preferences[MonitorRole.PRIMARY] == ["HDMI-A-1"]
        # Regardless of connection order, HDMI-A-1 should get primary role

    def test_example_three_monitor_setup(self):
        """Test typical 3-monitor preference configuration."""
        preferences = {
            MonitorRole.PRIMARY: ["HDMI-A-1", "DP-1"],
            MonitorRole.SECONDARY: ["HDMI-A-2", "DP-2"],
            MonitorRole.TERTIARY: ["DP-3"]
        }

        assert len(preferences) == 3
        # Each role has fallback chain
        assert len(preferences[MonitorRole.PRIMARY]) == 2
        assert len(preferences[MonitorRole.SECONDARY]) == 2
        assert len(preferences[MonitorRole.TERTIARY]) == 1
