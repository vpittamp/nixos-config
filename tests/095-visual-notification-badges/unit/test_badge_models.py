"""Unit tests for WindowBadge Pydantic model.

Feature 095: Visual Notification Badges in Monitoring Panel
Tests badge count increment, display formatting, and validation.
"""

import pytest
import time
import sys
from pathlib import Path

# Add daemon directory to path for imports
daemon_dir = Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_dir))

from badge_service import WindowBadge


class TestWindowBadge:
    """Test WindowBadge model creation, validation, and operations."""

    def test_create_badge_with_valid_data(self):
        """Test creating badge with all required fields."""
        badge = WindowBadge(
            window_id=12345,
            count=2,
            timestamp=1732450000.5,
            source="claude-code"
        )
        assert badge.window_id == 12345
        assert badge.count == 2
        assert badge.timestamp == 1732450000.5
        assert badge.source == "claude-code"

    def test_create_badge_with_defaults(self):
        """Test creating badge with default source and count."""
        badge = WindowBadge(
            window_id=67890,
            timestamp=time.time()
        )
        assert badge.window_id == 67890
        assert badge.count == 1  # Default count
        assert badge.source == "generic"  # Default source

    def test_create_badge_invalid_window_id(self):
        """Test validation fails for invalid window ID."""
        with pytest.raises(ValueError):
            WindowBadge(window_id=0, timestamp=time.time())  # window_id must be > 0

        with pytest.raises(ValueError):
            WindowBadge(window_id=-1, timestamp=time.time())  # Negative not allowed

    def test_create_badge_invalid_count(self):
        """Test validation fails for invalid badge count."""
        with pytest.raises(ValueError):
            WindowBadge(window_id=12345, count=0, timestamp=time.time())  # Count must be >= 1

        with pytest.raises(ValueError):
            WindowBadge(window_id=12345, count=10000, timestamp=time.time())  # Count must be <= 9999

    def test_create_badge_empty_source(self):
        """Test validation fails for empty source string."""
        with pytest.raises(ValueError):
            WindowBadge(window_id=12345, timestamp=time.time(), source="")  # Source must be non-empty

    def test_increment_badge_count(self):
        """Test incrementing badge count."""
        badge = WindowBadge(window_id=12345, count=1, timestamp=time.time(), source="test")

        badge.increment()
        assert badge.count == 2

        badge.increment()
        assert badge.count == 3

    def test_increment_badge_count_at_cap(self):
        """Test incrementing badge at 9999 cap stays at 9999."""
        badge = WindowBadge(window_id=12345, count=9999, timestamp=time.time(), source="test")

        badge.increment()
        assert badge.count == 9999  # Should not exceed 9999

        badge.increment()
        assert badge.count == 9999  # Still capped

    def test_display_count_single_digit(self):
        """Test display_count for single-digit counts."""
        badge = WindowBadge(window_id=12345, count=1, timestamp=time.time(), source="test")
        assert badge.display_count() == "1"

        badge.count = 5
        assert badge.display_count() == "5"

        badge.count = 9
        assert badge.display_count() == "9"

    def test_display_count_overflow(self):
        """Test display_count shows '9+' for counts > 9."""
        badge = WindowBadge(window_id=12345, count=10, timestamp=time.time(), source="test")
        assert badge.display_count() == "9+"

        badge.count = 50
        assert badge.display_count() == "9+"

        badge.count = 9999
        assert badge.display_count() == "9+"

    def test_badge_source_types(self):
        """Test badge creation with various source types."""
        sources = ["claude-code", "build", "test", "generic", "ghostty-notification", "tmux-alert", "cargo-build"]

        for source in sources:
            badge = WindowBadge(window_id=12345, timestamp=time.time(), source=source)
            assert badge.source == source

    def test_badge_timestamp_preservation(self):
        """Test badge timestamp is preserved correctly."""
        ts = time.time()
        badge = WindowBadge(window_id=12345, timestamp=ts, source="test")
        assert badge.timestamp == ts

        # Incrementing shouldn't change timestamp
        badge.increment()
        assert badge.timestamp == ts
