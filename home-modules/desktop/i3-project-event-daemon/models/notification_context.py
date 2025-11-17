"""
Notification context model for Claude Code stop hooks.
Feature 079: Preview Pane User Experience - US9 (T063-T064)

Provides structured context for notification generation with tmux integration.
"""

from typing import List, Optional
from pydantic import BaseModel


class NotificationContext(BaseModel):
    """Context for Claude Code stop notification (T063-T064).

    Attributes:
        window_id: Sway window container ID
        terminal_pid: PID of terminal process
        tmux_session: Name of tmux session (if running in tmux)
        tmux_window: Index of tmux window (if running in tmux)
        working_dir: Current working directory
    """

    window_id: int
    terminal_pid: int
    tmux_session: Optional[str] = None
    tmux_window: Optional[int] = None
    working_dir: str = ""

    def window_identifier(self) -> str:
        """Generate window identifier string 'session:window' (T063).

        Returns:
            Window identifier in format 'session_name:window_index'
            or empty string if not in tmux
        """
        if self.tmux_session is not None and self.tmux_window is not None:
            return f"{self.tmux_session}:{self.tmux_window}"
        return ""

    def to_notify_send_args(self, message: str) -> List[str]:
        """Generate notify-send command arguments with action flags (T064).

        Args:
            message: Main notification message

        Returns:
            List of command-line arguments for notify-send
        """
        args = [
            "-u", "normal",  # Urgency level
            "-w",  # Wait for action
            "--transient",  # Auto-dismiss
        ]

        # Add action buttons (T067)
        args.extend(["-A", "focus=Return to Window"])
        args.extend(["-A", "dismiss=Dismiss"])

        # Build notification body with source info
        body_parts = [message]

        # Add tmux source info if available
        window_id = self.window_identifier()
        if window_id:
            body_parts.append(f"\nSource: {window_id}")

        # Notification title and body
        args.append("Claude Code Ready")
        args.append("".join(body_parts))

        return args
