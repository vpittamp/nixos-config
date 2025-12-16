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
    - Focus action (if supported)

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

    # Build notify-send command
    cmd = [
        notify_send,
        "--app-name=AI Monitor",
        "--urgency=normal",
        # Note: --action requires notify-send 0.8+ and SwayNC support
        # Using print action name format: "action_name=Action Label"
        "--action=focus=Focus Terminal",
        title,
        body,
    ]

    try:
        # Run notify-send asynchronously
        # Note: We don't use -w (wait) here as that blocks until dismissed
        # The action callback is handled by SwayNC separately
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await process.communicate()

        if process.returncode != 0:
            # notify-send may not support --action, try without
            logger.debug(f"notify-send with action failed, trying simple: {stderr}")
            await _send_simple_notification(notify_send, title, body)
        else:
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
