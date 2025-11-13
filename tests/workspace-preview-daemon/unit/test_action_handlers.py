"""Unit tests for workspace-preview-daemon action handlers (Feature 073).

Tests debouncing logic for window close operations to prevent duplicate actions
from rapid keypresses.
"""
import pytest
import time
import sys
from pathlib import Path

# Add sway-workspace-panel to Python path for imports
sys.path.insert(0, str(Path("/etc/nixos/home-modules/tools/sway-workspace-panel")))

from action_handlers import DebounceTracker, ActionType


class TestDebounceTracker:
    """Test suite for DebounceTracker (Feature 073: T015)."""

    def test_init_default_interval(self):
        """Test DebounceTracker initializes with default 100ms interval."""
        tracker = DebounceTracker()
        assert tracker.min_interval_ms == 100.0
        assert tracker._action_count == 0
        assert len(tracker._last_action_time) == 0

    def test_init_custom_interval(self):
        """Test DebounceTracker accepts custom minimum interval."""
        tracker = DebounceTracker(min_interval_ms=50.0)
        assert tracker.min_interval_ms == 50.0

    def test_first_action_always_allowed(self):
        """Test first action for a window is always allowed."""
        tracker = DebounceTracker()
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is True

    def test_rapid_duplicate_action_rejected(self):
        """Test duplicate action within 100ms is rejected."""
        tracker = DebounceTracker(min_interval_ms=100.0)

        # First action allowed
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is True

        # Immediate duplicate rejected (< 100ms)
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is False

    def test_action_after_interval_allowed(self):
        """Test action after minimum interval is allowed."""
        tracker = DebounceTracker(min_interval_ms=50.0)  # 50ms for faster test

        # First action
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is True

        # Wait for interval to pass
        time.sleep(0.06)  # 60ms > 50ms

        # Second action allowed
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is True

    def test_different_windows_independent(self):
        """Test debouncing is per-window (different windows don't interfere)."""
        tracker = DebounceTracker()

        # Close window 1
        assert tracker.should_allow(ActionType.CLOSE, window_id=111) is True

        # Immediately close window 2 (different window, should be allowed)
        assert tracker.should_allow(ActionType.CLOSE, window_id=222) is True

        # Duplicate close of window 1 rejected
        assert tracker.should_allow(ActionType.CLOSE, window_id=111) is False

    def test_different_action_types_independent(self):
        """Test debouncing is per-action-type (different actions don't interfere)."""
        tracker = DebounceTracker()

        # Close window
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is True

        # Immediately move same window (different action, should be allowed)
        assert tracker.should_allow(ActionType.MOVE, window_id=12345) is True

        # Duplicate close rejected
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is False

    def test_reset_clears_all_state(self):
        """Test reset() clears all debounce state."""
        tracker = DebounceTracker()

        # Add some actions
        tracker.should_allow(ActionType.CLOSE, window_id=111)
        tracker.should_allow(ActionType.CLOSE, window_id=222)
        tracker.should_allow(ActionType.MOVE, window_id=333)

        assert len(tracker._last_action_time) > 0
        assert tracker._action_count > 0

        # Reset
        tracker.reset()

        # State cleared
        assert len(tracker._last_action_time) == 0
        assert tracker._action_count == 0

    def test_cleanup_triggered_after_100_actions(self):
        """Test automatic cleanup is triggered after 100 actions."""
        tracker = DebounceTracker()

        # Perform 99 actions (cleanup not triggered)
        for i in range(99):
            tracker.should_allow(ActionType.CLOSE, window_id=i)

        assert tracker._action_count == 99

        # 100th action triggers cleanup
        tracker.should_allow(ActionType.CLOSE, window_id=999)

        # Action count reset
        assert tracker._action_count == 0

    def test_cleanup_removes_old_entries(self):
        """Test cleanup removes entries older than 10 seconds."""
        tracker = DebounceTracker()

        # Add action
        tracker.should_allow(ActionType.CLOSE, window_id=12345)

        # Manually set timestamp to 11 seconds ago (simulate old entry)
        key = (ActionType.CLOSE, 12345)
        tracker._last_action_time[key] = time.monotonic() - 11.0

        # Trigger cleanup by setting action count to 100
        tracker._action_count = 99
        tracker.should_allow(ActionType.CLOSE, window_id=99999)  # 100th action

        # Old entry should be removed (key not in dict)
        assert key not in tracker._last_action_time

    def test_100ms_interval_matches_spec(self):
        """Test default 100ms interval matches Feature 073 specification."""
        tracker = DebounceTracker()

        # Spec requires 100ms minimum between same actions
        assert tracker.min_interval_ms == 100.0

        # Verify actual timing
        tracker.should_allow(ActionType.CLOSE, window_id=12345)

        # 99ms should be rejected
        time.sleep(0.099)
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is False

        # 101ms should be allowed
        time.sleep(0.002)  # Total: 99 + 2 = 101ms
        assert tracker.should_allow(ActionType.CLOSE, window_id=12345) is True
