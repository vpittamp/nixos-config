"""Unit tests for MonitorRole enum validation and parsing.

Tests the MonitorRole enum (primary/secondary/tertiary) validation
and case-insensitive string parsing.
"""

import pytest
import sys

# Add daemon path to sys.path for imports
sys.path.insert(0, "/etc/nixos/home-modules/desktop/i3-project-event-daemon")

from models.monitor_config import MonitorRole


class TestMonitorRoleEnum:
    """Test cases for MonitorRole enum values."""

    def test_all_role_values(self):
        """Test all three monitor role values exist."""
        assert MonitorRole.PRIMARY == "primary"
        assert MonitorRole.SECONDARY == "secondary"
        assert MonitorRole.TERTIARY == "tertiary"

    def test_role_count(self):
        """Test there are exactly three monitor roles."""
        roles = list(MonitorRole)
        assert len(roles) == 3

    def test_role_string_representation(self):
        """Test role string values are lowercase."""
        for role in MonitorRole:
            assert role.value == role.value.lower()


class TestMonitorRoleFromString:
    """Test cases for MonitorRole.from_str() parsing."""

    def test_parse_lowercase(self):
        """Test parsing lowercase role names."""
        assert MonitorRole.from_str("primary") == MonitorRole.PRIMARY
        assert MonitorRole.from_str("secondary") == MonitorRole.SECONDARY
        assert MonitorRole.from_str("tertiary") == MonitorRole.TERTIARY

    def test_parse_uppercase(self):
        """Test parsing uppercase role names (case-insensitive)."""
        assert MonitorRole.from_str("PRIMARY") == MonitorRole.PRIMARY
        assert MonitorRole.from_str("SECONDARY") == MonitorRole.SECONDARY
        assert MonitorRole.from_str("TERTIARY") == MonitorRole.TERTIARY

    def test_parse_mixed_case(self):
        """Test parsing mixed case role names."""
        assert MonitorRole.from_str("Primary") == MonitorRole.PRIMARY
        assert MonitorRole.from_str("SeCoNdArY") == MonitorRole.SECONDARY
        assert MonitorRole.from_str("TeRtIaRy") == MonitorRole.TERTIARY

    def test_parse_invalid_role(self):
        """Test parsing invalid role name raises ValueError."""
        with pytest.raises(ValueError) as exc_info:
            MonitorRole.from_str("quaternary")

        error_msg = str(exc_info.value).lower()
        assert "invalid monitor role" in error_msg
        assert "quaternary" in error_msg
        assert "primary" in error_msg
        assert "secondary" in error_msg
        assert "tertiary" in error_msg

    def test_parse_empty_string(self):
        """Test parsing empty string raises ValueError."""
        with pytest.raises(ValueError):
            MonitorRole.from_str("")

    def test_parse_whitespace(self):
        """Test parsing whitespace-only string raises ValueError."""
        with pytest.raises(ValueError):
            MonitorRole.from_str("   ")

    def test_parse_partial_match(self):
        """Test parsing partial role names raises ValueError."""
        with pytest.raises(ValueError):
            MonitorRole.from_str("prim")  # Partial "primary"

        with pytest.raises(ValueError):
            MonitorRole.from_str("sec")  # Partial "secondary"


class TestMonitorRoleFallbackChain:
    """Test cases for monitor role fallback logic (conceptual).

    Note: Actual fallback implementation is in MonitorRoleResolver,
    but these tests document the expected fallback order.
    """

    def test_fallback_order(self):
        """Test conceptual fallback chain: tertiary → secondary → primary."""
        # This documents the expected fallback order for reference
        fallback_chain = {
            MonitorRole.TERTIARY: MonitorRole.SECONDARY,  # tertiary falls back to secondary
            MonitorRole.SECONDARY: MonitorRole.PRIMARY,  # secondary falls back to primary
            MonitorRole.PRIMARY: None,  # primary has no fallback (always available)
        }

        assert fallback_chain[MonitorRole.TERTIARY] == MonitorRole.SECONDARY
        assert fallback_chain[MonitorRole.SECONDARY] == MonitorRole.PRIMARY
        assert fallback_chain[MonitorRole.PRIMARY] is None

    def test_no_circular_fallback(self):
        """Test there are no circular fallbacks."""
        # Fallback chain should be: tertiary → secondary → primary → None
        # No cycles allowed
        visited = set()
        current = MonitorRole.TERTIARY

        fallback_map = {
            MonitorRole.TERTIARY: MonitorRole.SECONDARY,
            MonitorRole.SECONDARY: MonitorRole.PRIMARY,
            MonitorRole.PRIMARY: None,
        }

        while current is not None:
            assert current not in visited, "Circular fallback detected"
            visited.add(current)
            current = fallback_map.get(current)

        # Should visit all 3 roles before reaching None
        assert len(visited) == 3


class TestMonitorRoleComparison:
    """Test cases for MonitorRole enum comparison."""

    def test_equality(self):
        """Test monitor role equality comparison."""
        assert MonitorRole.PRIMARY == MonitorRole.PRIMARY
        assert MonitorRole.SECONDARY == MonitorRole.SECONDARY
        assert MonitorRole.TERTIARY == MonitorRole.TERTIARY

    def test_inequality(self):
        """Test monitor role inequality comparison."""
        assert MonitorRole.PRIMARY != MonitorRole.SECONDARY
        assert MonitorRole.SECONDARY != MonitorRole.TERTIARY
        assert MonitorRole.TERTIARY != MonitorRole.PRIMARY

    def test_string_equality(self):
        """Test monitor role can be compared to string values."""
        assert MonitorRole.PRIMARY == "primary"
        assert MonitorRole.SECONDARY == "secondary"
        assert MonitorRole.TERTIARY == "tertiary"

    def test_string_inequality(self):
        """Test monitor role string inequality."""
        assert MonitorRole.PRIMARY != "secondary"
        assert MonitorRole.SECONDARY != "tertiary"
        assert MonitorRole.TERTIARY != "primary"


class TestMonitorRoleUsageInDict:
    """Test cases for using MonitorRole as dict keys."""

    def test_role_as_dict_key(self):
        """Test MonitorRole can be used as dictionary key."""
        role_map = {
            MonitorRole.PRIMARY: "HEADLESS-1",
            MonitorRole.SECONDARY: "HEADLESS-2",
            MonitorRole.TERTIARY: "HEADLESS-3",
        }

        assert role_map[MonitorRole.PRIMARY] == "HEADLESS-1"
        assert role_map[MonitorRole.SECONDARY] == "HEADLESS-2"
        assert role_map[MonitorRole.TERTIARY] == "HEADLESS-3"

    def test_role_dict_iteration(self):
        """Test iterating over MonitorRole dict keys."""
        role_map = {
            MonitorRole.PRIMARY: "output1",
            MonitorRole.SECONDARY: "output2",
            MonitorRole.TERTIARY: "output3",
        }

        roles = list(role_map.keys())
        assert len(roles) == 3
        assert MonitorRole.PRIMARY in roles
        assert MonitorRole.SECONDARY in roles
        assert MonitorRole.TERTIARY in roles
