"""Unit tests for BadgeState operations.

Feature 095: Visual Notification Badges in Monitoring Panel
Tests badge creation, clearing, querying, and Eww format serialization.
"""

import pytest
import time
import sys
from pathlib import Path

# Add daemon directory to path for imports
daemon_dir = Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_dir))

from badge_service import BadgeState, WindowBadge


class TestBadgeState:
    """Test BadgeState manager operations."""

    def test_create_new_badge(self):
        """Test creating a new badge."""
        state = BadgeState()
        badge = state.create_badge(window_id=12345, source="claude-code")

        assert badge.window_id == 12345
        assert badge.count == 1
        assert badge.source == "claude-code"
        assert len(state.badges) == 1

    def test_create_badge_increments_existing(self):
        """Test creating badge for existing window increments count."""
        state = BadgeState()

        # Create first badge
        badge1 = state.create_badge(window_id=12345, source="claude-code")
        assert badge1.count == 1

        # Create second badge for same window - should increment
        badge2 = state.create_badge(window_id=12345, source="claude-code")
        assert badge2.count == 2
        assert len(state.badges) == 1  # Still only one badge

        # Create third time
        badge3 = state.create_badge(window_id=12345, source="claude-code")
        assert badge3.count == 3

    def test_create_badge_default_source(self):
        """Test creating badge with default source."""
        state = BadgeState()
        badge = state.create_badge(window_id=12345)

        assert badge.source == "generic"

    def test_create_multiple_badges(self):
        """Test creating badges for multiple windows."""
        state = BadgeState()

        badge1 = state.create_badge(window_id=12345, source="claude-code")
        badge2 = state.create_badge(window_id=67890, source="build")
        badge3 = state.create_badge(window_id=11111, source="test")

        assert len(state.badges) == 3
        assert state.badges[12345].source == "claude-code"
        assert state.badges[67890].source == "build"
        assert state.badges[11111].source == "test"

    def test_clear_existing_badge(self):
        """Test clearing an existing badge returns count."""
        state = BadgeState()
        state.create_badge(window_id=12345, source="test")
        state.create_badge(window_id=12345, source="test")  # Increment to 2

        cleared_count = state.clear_badge(window_id=12345)

        assert cleared_count == 2
        assert len(state.badges) == 0
        assert 12345 not in state.badges

    def test_clear_nonexistent_badge(self):
        """Test clearing non-existent badge returns 0."""
        state = BadgeState()

        cleared_count = state.clear_badge(window_id=99999)

        assert cleared_count == 0
        assert len(state.badges) == 0

    def test_has_badge(self):
        """Test checking if window has badge."""
        state = BadgeState()

        assert not state.has_badge(12345)

        state.create_badge(window_id=12345, source="test")
        assert state.has_badge(12345)

        state.clear_badge(window_id=12345)
        assert not state.has_badge(12345)

    def test_get_badge(self):
        """Test getting badge by window ID."""
        state = BadgeState()

        # Non-existent badge
        assert state.get_badge(12345) is None

        # Create badge
        state.create_badge(window_id=12345, source="test")
        badge = state.get_badge(12345)
        assert badge is not None
        assert badge.window_id == 12345

        # Clear badge
        state.clear_badge(12345)
        assert state.get_badge(12345) is None

    def test_get_all_badges(self):
        """Test getting all badges."""
        state = BadgeState()

        # Empty state
        assert state.get_all_badges() == []

        # Add badges
        state.create_badge(window_id=12345, source="claude-code")
        state.create_badge(window_id=67890, source="build")

        badges = state.get_all_badges()
        assert len(badges) == 2
        window_ids = {badge.window_id for badge in badges}
        assert window_ids == {12345, 67890}

    def test_cleanup_orphaned_badges(self):
        """Test removing orphaned badges."""
        state = BadgeState()

        # Create badges for windows 12345, 67890, 11111
        state.create_badge(window_id=12345, source="test")
        state.create_badge(window_id=67890, source="test")
        state.create_badge(window_id=11111, source="test")

        # Only windows 12345 and 11111 still exist
        valid_window_ids = {12345, 11111}
        orphaned_count = state.cleanup_orphaned(valid_window_ids)

        assert orphaned_count == 1  # Only 67890 was orphaned
        assert len(state.badges) == 2
        assert 67890 not in state.badges
        assert 12345 in state.badges
        assert 11111 in state.badges

    def test_cleanup_orphaned_no_orphans(self):
        """Test cleanup when no badges are orphaned."""
        state = BadgeState()

        state.create_badge(window_id=12345, source="test")
        state.create_badge(window_id=67890, source="test")

        valid_window_ids = {12345, 67890, 99999}  # All badges still valid
        orphaned_count = state.cleanup_orphaned(valid_window_ids)

        assert orphaned_count == 0
        assert len(state.badges) == 2

    def test_to_eww_format_empty(self):
        """Test Eww format serialization with no badges."""
        state = BadgeState()

        eww_data = state.to_eww_format()

        assert eww_data == {}

    def test_to_eww_format_single_badge(self):
        """Test Eww format serialization with one badge."""
        state = BadgeState()
        state.create_badge(window_id=12345, source="claude-code")

        eww_data = state.to_eww_format()

        assert "12345" in eww_data  # Key is stringified
        assert eww_data["12345"]["count"] == "1"
        assert eww_data["12345"]["source"] == "claude-code"
        assert "timestamp" in eww_data["12345"]

    def test_to_eww_format_multiple_badges(self):
        """Test Eww format serialization with multiple badges."""
        state = BadgeState()
        state.create_badge(window_id=12345, source="claude-code")
        state.create_badge(window_id=12345, source="claude-code")  # Increment to 2
        state.create_badge(window_id=67890, source="build")

        eww_data = state.to_eww_format()

        assert len(eww_data) == 2
        assert eww_data["12345"]["count"] == "2"
        assert eww_data["12345"]["source"] == "claude-code"
        assert eww_data["67890"]["count"] == "1"
        assert eww_data["67890"]["source"] == "build"

    def test_to_eww_format_display_count_overflow(self):
        """Test Eww format shows '9+' for counts > 9."""
        state = BadgeState()

        # Create badge with count > 9
        badge = state.create_badge(window_id=12345, source="test")
        for _ in range(11):  # Increment to 12
            badge.increment()

        eww_data = state.to_eww_format()

        assert eww_data["12345"]["count"] == "9+"

    def test_notification_agnostic_sources(self):
        """Test badge service accepts any notification source without validation."""
        state = BadgeState()

        # Various notification sources (notification-agnostic architecture)
        sources = [
            "swaync",
            "ghostty-notification",
            "tmux-alert",
            "cargo-build-failure",
            "custom-script-v2",
            "pytest-failure",
            "git-hook",
        ]

        for i, source in enumerate(sources, start=1):
            badge = state.create_badge(window_id=10000 + i, source=source)
            assert badge.source == source

        assert len(state.badges) == len(sources)
