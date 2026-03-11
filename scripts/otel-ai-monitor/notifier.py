"""Desktop notification support for OpenTelemetry AI Assistant Monitor.

This module provides desktop notification functionality using libnotify
(notify-send) for SwayNC integration.

Notifications are sent when AI sessions complete, with actions to
focus the terminal window.
"""

import asyncio
import json
import logging
import os
import shutil
import socket
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import Session

logger = logging.getLogger(__name__)
DAEMON_SOCKET = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}",
    "i3-project-daemon",
    "ipc.sock",
)


async def _daemon_rpc(method: str, params: dict[str, object]) -> dict[str, object]:
    """Send a single JSON-RPC request to the i3pm daemon."""
    def _call() -> dict[str, object]:
        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1,
        }
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(1.5)
            sock.connect(DAEMON_SOCKET)
            sock.sendall((json.dumps(request) + "\n").encode("utf-8"))
            response = sock.makefile("r", encoding="utf-8").readline()
        payload = json.loads(response or "{}")
        if "error" in payload:
            raise RuntimeError(str(payload["error"]))
        result = payload.get("result")
        return result if isinstance(result, dict) else {}

    return await asyncio.to_thread(_call)


async def _handle_notification_response(session: "Session", cmd: list[str]) -> None:
    """Run notify-send and handle its action response in the background."""
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await process.communicate()
        action = stdout.decode().strip()

        if action == "focus":
            await focus_terminal_action(session)
    except Exception as e:
        logger.error(f"Error handling notification response: {e}")

async def send_completion_notification(session: "Session") -> None:
    """Send desktop notification for completed AI session.

    Uses notify-send with SwayNC-compatible options and action buttons.
    Runs asynchronously so it doesn't block the telemetry receiver loop.

    Args:
        session: Completed session to notify about
    """
    notify_send = shutil.which("notify-send")
    if not notify_send:
        logger.warning("notify-send not found, skipping notification")
        return

    # Build notification title
    tool_names = {
        "claude-code": "Claude Code",
        "codex": "Codex",
        "gemini": "Gemini CLI"
    }
    tool_name = tool_names.get(session.tool, "AI Assistant")
    title = f"{tool_name} Ready"

    # Build notification body
    body_parts = []
    if session.project:
        body_parts.append(f"📁 {session.project}")
    else:
        body_parts.append("Task completed")
        
    if session.cost_usd > 0:
        cost = f"${session.cost_usd:.4f}"
        if session.cost_estimated:
            cost += " (est)"
        body_parts.append(f"💰 {cost}")
        
    body_parts.append("Click 'Return to Window' to resume")
    body = "\n\n".join(body_parts)

    # Build notify-send command with -w to wait and -A for actions
    cmd = [
        notify_send,
        "-u", "normal",
        "-a", "AI Monitor",
        "-w",
        "--transient",
        "-A", "focus=🖥️ Return to Window",
        title,
        body,
    ]

    # Run in background task to avoid blocking the OTEL receiver loop
    asyncio.create_task(_handle_notification_response(session, cmd))

async def focus_terminal_action(session: "Session") -> None:
    """Focus the terminal window and tmux pane associated with the session.

    Args:
        session: The session to focus
    """
    if session.window_id:
        try:
            result = await _daemon_rpc(
                "window.focus",
                {
                    "window_id": int(session.window_id),
                    "project_name": str(session.project or ""),
                    "target_variant": str(getattr(session, "execution_mode", "") or ""),
                },
            )
            if result.get("success") is True:
                logger.debug("Focused daemon-managed window %s", session.window_id)
            else:
                logger.error("Daemon focus failed for %s: %s", session.window_id, result)
        except Exception as e:
            logger.error(f"Error focusing daemon-managed window: {e}")

    tmux = shutil.which("tmux")
    tc = session.terminal_context
    if tmux and tc and tc.tmux_session and tc.tmux_window:
        try:
            # Select tmux window
            cmd = [tmux, "select-window", "-t", f"{tc.tmux_session}:{tc.tmux_window}"]
            process = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL
            )
            await process.wait()
            
            # Select tmux pane if available
            if tc.tmux_pane:
                cmd = [tmux, "select-pane", "-t", tc.tmux_pane]
                process = await asyncio.create_subprocess_exec(
                    *cmd, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL
                )
                await process.wait()
            
            logger.debug(f"Selected tmux pane {tc.tmux_session}:{tc.tmux_window}.{tc.tmux_pane}")
        except Exception as e:
            logger.error(f"Error selecting tmux pane: {e}")
