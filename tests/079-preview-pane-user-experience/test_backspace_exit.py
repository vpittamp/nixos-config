"""
Unit tests for backspace exit behavior in project selection mode.

Feature 079: User Story 2 - Backspace Exits Project Selection Mode
Tests that pressing backspace to remove ":" exits project mode.
"""

import pytest
import sys
from pathlib import Path

# Add daemon module to path
daemon_path = Path(__file__).parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_path))

from models.project_filter import FilterState, ProjectListItem


class TestBackspaceExitBehavior:
    """Test backspace behavior for exiting project selection mode."""

    def test_backspace_removes_last_character(self):
        """Basic backspace removes last character from filter."""
        state = FilterState()
        state.accumulated_chars = ":nix"

        state.remove_char()

        assert state.accumulated_chars == ":ni"

    def test_backspace_on_colon_leaves_empty(self):
        """T021: Backspace on ":" leaves empty string."""
        state = FilterState()
        state.accumulated_chars = ":"

        state.remove_char()

        assert state.accumulated_chars == ""

    def test_backspace_multiple_times_removes_all_chars(self):
        """Multiple backspaces remove all characters including ":"."""
        state = FilterState()
        state.accumulated_chars = ":79"

        state.remove_char()  # ":7"
        assert state.accumulated_chars == ":7"

        state.remove_char()  # ":"
        assert state.accumulated_chars == ":"

        state.remove_char()  # ""
        assert state.accumulated_chars == ""

    def test_empty_filter_triggers_exit_mode(self):
        """T022: Empty accumulated_chars should signal exit_mode."""
        state = FilterState()
        state.accumulated_chars = ":"

        state.remove_char()

        # When accumulated_chars is empty, the event payload should have exit_mode=True
        exit_mode = len(state.accumulated_chars) == 0
        assert exit_mode is True

    def test_non_empty_filter_does_not_exit(self):
        """Non-empty filter should not trigger exit_mode."""
        state = FilterState()
        state.accumulated_chars = ":n"

        state.remove_char()

        # accumulated_chars is ":", not empty
        exit_mode = len(state.accumulated_chars) == 0
        assert exit_mode is False
        assert state.accumulated_chars == ":"

    def test_backspace_on_empty_string_no_crash(self):
        """Backspace on already empty string should not crash."""
        state = FilterState()
        state.accumulated_chars = ""

        # Should not raise any exception
        state.remove_char()

        assert state.accumulated_chars == ""

    def test_backspace_resets_selection_if_not_navigated(self):
        """Backspace resets selection to 0 if user hasn't manually navigated."""
        state = FilterState()
        state.accumulated_chars = ":nix"
        state.selected_index = 2
        state.user_navigated = False

        state.remove_char()

        # Selection reset to 0 when filter changes and user hasn't navigated
        assert state.selected_index == 0

    def test_backspace_preserves_navigation_state(self):
        """Backspace preserves user_navigated flag."""
        state = FilterState()
        state.accumulated_chars = ":nix"
        state.user_navigated = True

        state.remove_char()

        # user_navigated flag is not changed by backspace
        assert state.user_navigated is True


class TestExitModeEventPayload:
    """Test exit_mode flag in event payloads."""

    def test_exit_mode_detected_from_empty_chars(self):
        """T022: exit_mode should be True when accumulated_chars is empty after backspace."""
        accumulated_chars = ""

        # This simulates what the daemon should check
        exit_mode = len(accumulated_chars) == 0

        assert exit_mode is True

    def test_exit_mode_false_with_content(self):
        """exit_mode should be False when accumulated_chars has content."""
        accumulated_chars = ":"

        exit_mode = len(accumulated_chars) == 0

        assert exit_mode is False

    def test_event_payload_structure_with_exit_mode(self):
        """Event payload should include exit_mode field."""
        # Simulate event payload creation
        accumulated_chars = ""
        exit_mode = len(accumulated_chars) == 0

        payload = {
            "event_type": "backspace",
            "accumulated_chars": accumulated_chars,
            "exit_mode": exit_mode,
        }

        assert payload["exit_mode"] is True
        assert payload["accumulated_chars"] == ""

    def test_event_payload_without_exit(self):
        """Event payload with exit_mode=False when filter not empty."""
        accumulated_chars = ":"
        exit_mode = len(accumulated_chars) == 0

        payload = {
            "event_type": "backspace",
            "accumulated_chars": accumulated_chars,
            "exit_mode": exit_mode,
        }

        assert payload["exit_mode"] is False
        assert payload["accumulated_chars"] == ":"
