"""
Tests for notification click navigation.
Feature 079: Preview Pane User Experience - US9 (T063-T064)
"""

import pytest
import sys
from pathlib import Path

# Add daemon directory to path for imports
daemon_dir = Path(__file__).parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"
sys.path.insert(0, str(daemon_dir))

from models.notification_context import NotificationContext


class TestNotificationContextWindowIdentifier:
    """T063: Unit test for NotificationContext.window_identifier()"""

    def test_window_identifier_with_tmux_session(self):
        """Verify window identifier format 'session:window'."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session="nixos",
            tmux_window=0,
            working_dir="/home/vpittamp/nixos",
        )

        identifier = context.window_identifier()

        assert identifier == "nixos:0"

    def test_window_identifier_with_different_window(self):
        """Verify window identifier with non-zero window index."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session="dotfiles",
            tmux_window=3,
            working_dir="/home/vpittamp/dotfiles",
        )

        identifier = context.window_identifier()

        assert identifier == "dotfiles:3"

    def test_window_identifier_without_tmux(self):
        """Verify empty identifier when not in tmux."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session=None,
            tmux_window=None,
            working_dir="/home/vpittamp",
        )

        identifier = context.window_identifier()

        assert identifier == ""

    def test_window_identifier_with_only_session(self):
        """Verify empty identifier when window is missing."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session="nixos",
            tmux_window=None,
            working_dir="/home/vpittamp",
        )

        identifier = context.window_identifier()

        assert identifier == ""


class TestNotifyFunctionArgs:
    """T064: Unit test for to_notify_send_args() with action flags"""

    def test_notify_args_includes_return_action(self):
        """Verify notify-send args include 'Return to Window' action."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session="nixos",
            tmux_window=0,
            working_dir="/home/vpittamp/nixos",
        )

        args = context.to_notify_send_args("Task complete")

        assert "-A" in args
        assert "focus=Return to Window" in " ".join(args)

    def test_notify_args_includes_dismiss_action(self):
        """Verify notify-send args include 'Dismiss' action."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session="nixos",
            tmux_window=0,
            working_dir="/home/vpittamp/nixos",
        )

        args = context.to_notify_send_args("Task complete")

        assert "dismiss=Dismiss" in " ".join(args)

    def test_notify_args_includes_wait_flag(self):
        """Verify notify-send args include -w (wait) flag."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session="nixos",
            tmux_window=0,
            working_dir="/home/vpittamp/nixos",
        )

        args = context.to_notify_send_args("Task complete")

        assert "-w" in args

    def test_notify_args_includes_source_info(self):
        """Verify notification body includes source window info."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session="nixos",
            tmux_window=0,
            working_dir="/home/vpittamp/nixos",
        )

        args = context.to_notify_send_args("Task complete")

        # Find the body argument (last positional arg)
        body = args[-1]
        assert "Source: nixos:0" in body

    def test_notify_args_without_tmux(self):
        """Verify notify-send args work without tmux context."""
        context = NotificationContext(
            window_id=12345,
            terminal_pid=67890,
            tmux_session=None,
            tmux_window=None,
            working_dir="/home/vpittamp",
        )

        args = context.to_notify_send_args("Task complete")

        # Should still have basic args
        assert "-w" in args
        # But no source info
        body = args[-1]
        assert "Source:" not in body
