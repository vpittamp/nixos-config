"""Desktop notification support for OpenTelemetry AI Assistant Monitor.

This module provides desktop notification functionality using libnotify
(notify-send) for SwayNC integration.

Notifications are sent when AI sessions complete, with actions to
focus the terminal window.
"""

import asyncio
import logging
import shutil
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import Session

logger = logging.getLogger(__name__)


async def send_completion_notification(session: "Session") -> None:
    """Send desktop notification for completed AI session.

    Uses notify-send with SwayNC-compatible options:
    - App name for grouping
    - Normal urgency

    Note: We don't use --action flag as it blocks waiting for user interaction.

    Args:
        session: Completed session to notify about
    """
    # Check if notify-send is available
    notify_send = shutil.which("notify-send")
    if not notify_send:
        logger.warning("notify-send not found, skipping notification")
        return

    # Build notification title based on tool
    if session.tool == "claude-code":
        title = "Claude Code Ready"
    elif session.tool == "codex":
        title = "Codex Ready"
    else:
        title = "AI Assistant Ready"

    # Build notification body
    if session.project:
        body = f"Task completed in {session.project}"
    else:
        body = "Task completed"

    # Build notify-send command (no --action flag - it blocks waiting for interaction)
    cmd = [
        notify_send,
        "--app-name=AI Monitor",
        "--urgency=normal",
        title,
        body,
    ]

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await process.wait()
        logger.debug(f"Sent notification: {title}")
    except Exception as e:
        logger.error(f"Error sending notification: {e}")


async def _send_simple_notification(notify_send: str, title: str, body: str) -> None:
    """Send simple notification without actions.

    Fallback for systems that don't support --action.

    Args:
        notify_send: Path to notify-send binary
        title: Notification title
        body: Notification body
    """
    cmd = [
        notify_send,
        "--app-name=AI Monitor",
        "--urgency=normal",
        title,
        body,
    ]

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await process.wait()
        logger.debug(f"Sent simple notification: {title}")
    except Exception as e:
        logger.error(f"Error sending simple notification: {e}")


async def focus_terminal_action() -> None:
    """Focus the terminal window (callback for notification action).

    This function is called when user clicks "Focus Terminal" action.
    Uses swaymsg to focus the most recent terminal window.
    """
    swaymsg = shutil.which("swaymsg")
    if not swaymsg:
        logger.warning("swaymsg not found, cannot focus terminal")
        return

    # Focus the terminal - adjust criteria as needed
    # This focuses windows with app_id containing "ghostty" or "foot" or "alacritty"
    cmd = [
        swaymsg,
        "[app_id=ghostty] focus",
    ]

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await process.wait()
        logger.debug("Focused terminal window")
    except Exception as e:
        logger.error(f"Error focusing terminal: {e}")
