"""Desktop notification integration.

This module provides notification functionality using notify-send
to deliver desktop notifications to the user's session.

Architecture:
    Since the daemon runs as root, notifications are sent using
    sudo -u <user> to deliver to the correct user session.
"""

import logging
import os
import subprocess
from typing import Optional

from .models import MonitoredProcess

logger = logging.getLogger(__name__)


class Notifier:
    """Send desktop notifications for AI agent state changes.

    This class handles sending notifications via notify-send,
    properly routing them to the target user's session when
    the daemon runs as root.

    Example:
        >>> notifier = Notifier(user="vpittamp")
        >>> notifier.send_completion_notification(process)
    """

    def __init__(
        self,
        user: str,
        app_name: str = "AI Monitor",
        urgency: str = "normal",
    ):
        """Initialize notifier.

        Args:
            user: Username to send notifications to.
            app_name: Application name shown in notification.
            urgency: Notification urgency (low, normal, critical).
        """
        self.user = user
        self.app_name = app_name
        self.urgency = urgency
        self._uid: Optional[int] = None
        self._dbus_address: Optional[str] = None

    def _get_user_uid(self) -> int:
        """Get UID for target user.

        Returns:
            User's UID.

        Raises:
            ValueError: If user not found.
        """
        if self._uid is not None:
            return self._uid

        try:
            import pwd

            user_info = pwd.getpwnam(self.user)
            self._uid = user_info.pw_uid
            return self._uid
        except KeyError:
            raise ValueError(f"User not found: {self.user}")

    def _get_dbus_address(self) -> str:
        """Get D-Bus session address for target user.

        Returns:
            D-Bus address string.
        """
        if self._dbus_address is not None:
            return self._dbus_address

        uid = self._get_user_uid()
        # Standard XDG runtime dir pattern
        self._dbus_address = f"unix:path=/run/user/{uid}/bus"
        return self._dbus_address

    def send_notification(
        self,
        summary: str,
        body: str = "",
        icon: str = "dialog-information",
        timeout_ms: int = 5000,
        category: str = "im.received",
    ) -> bool:
        """Send a desktop notification.

        Args:
            summary: Notification title.
            body: Notification body text.
            icon: Icon name or path.
            timeout_ms: Display timeout in milliseconds.
            category: Notification category hint.

        Returns:
            True if notification was sent successfully.
        """
        uid = self._get_user_uid()
        dbus_address = self._get_dbus_address()

        # Build notify-send command
        cmd = [
            "sudo",
            "-u",
            self.user,
            "env",
            f"DBUS_SESSION_BUS_ADDRESS={dbus_address}",
            "notify-send",
            "--app-name",
            self.app_name,
            "--urgency",
            self.urgency,
            "--icon",
            icon,
            "--expire-time",
            str(timeout_ms),
            "--category",
            category,
            summary,
        ]

        if body:
            cmd.append(body)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=10,
            )

            if result.returncode != 0:
                logger.error("notify-send failed: %s", result.stderr)
                return False

            logger.debug("Notification sent: %s", summary)
            return True

        except subprocess.TimeoutExpired:
            logger.error("notify-send timed out")
            return False
        except FileNotFoundError:
            logger.error("notify-send not found")
            return False
        except Exception as e:
            logger.error("Failed to send notification: %s", e)
            return False

    def send_completion_notification(
        self,
        process: MonitoredProcess,
    ) -> bool:
        """Send notification that an AI agent has completed.

        Args:
            process: The MonitoredProcess that completed.

        Returns:
            True if notification was sent successfully.
        """
        # Map process name to display name
        agent_names = {
            "claude": "Claude Code",
            "codex": "Codex CLI",
        }
        agent_name = agent_names.get(process.comm, process.comm.title())

        # Build summary and body
        summary = f"{agent_name} Ready"
        if process.project_name:
            body = f"Project: {process.project_name}\nWaiting for input"
        else:
            body = "Waiting for input"

        return self.send_notification(
            summary=summary,
            body=body,
            icon="dialog-information",
            category="im.received",
        )

    def send_error_notification(
        self,
        title: str,
        message: str,
    ) -> bool:
        """Send an error notification.

        Args:
            title: Error title.
            message: Error details.

        Returns:
            True if notification was sent successfully.
        """
        return self.send_notification(
            summary=title,
            body=message,
            icon="dialog-error",
            urgency="critical",
            category="device.error",
        )
