"""Sway IPC helper for window discovery.

This module provides utilities for querying Sway to find window information,
particularly for correlating AI sessions with their originating terminal windows.
"""

import json
import logging
import os
import socket
from glob import glob
from typing import Optional

logger = logging.getLogger(__name__)


def get_sway_socket() -> Optional[str]:
    """Find the Sway IPC socket path.

    Returns:
        Socket path if found, None otherwise
    """
    # First try SWAYSOCK environment variable
    swaysock = os.environ.get("SWAYSOCK")
    if swaysock and os.path.exists(swaysock):
        return swaysock

    # Fallback: search for socket in runtime dir
    uid = os.getuid()
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    pattern = os.path.join(runtime_dir, "sway-ipc.*.sock")
    sockets = glob(pattern)

    if sockets:
        return sockets[0]

    return None


def sway_ipc(msg_type: int, payload: str = "") -> Optional[dict]:
    """Send a message to Sway and receive response.

    Args:
        msg_type: IPC message type (0=RUN_COMMAND, 4=GET_TREE, etc.)
        payload: Optional command payload

    Returns:
        Parsed JSON response or None on error
    """
    socket_path = get_sway_socket()
    if not socket_path:
        logger.debug("Sway socket not found")
        return None

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect(socket_path)

        # Build IPC message: magic + length + type + payload
        payload_bytes = payload.encode("utf-8")
        msg = b"i3-ipc" + len(payload_bytes).to_bytes(4, "little") + msg_type.to_bytes(4, "little") + payload_bytes
        sock.sendall(msg)

        # Read response header
        header = sock.recv(14)
        if len(header) < 14:
            return None

        # Parse header: magic (6) + length (4) + type (4)
        resp_len = int.from_bytes(header[6:10], "little")

        # Read response body
        body = b""
        while len(body) < resp_len:
            chunk = sock.recv(resp_len - len(body))
            if not chunk:
                break
            body += chunk

        sock.close()
        return json.loads(body.decode("utf-8"))
    except Exception as e:
        logger.debug(f"Sway IPC error: {e}")
        return None


def get_focused_window_id() -> Optional[int]:
    """Get the Sway container ID of the currently focused window.

    Returns:
        Window container ID (con_id) or None if not found
    """
    tree = sway_ipc(4)  # GET_TREE = 4
    if not tree:
        return None

    return _find_focused_window(tree)


def _find_focused_window(node: dict) -> Optional[int]:
    """Recursively find the focused window in the Sway tree.

    Args:
        node: Sway tree node

    Returns:
        Container ID of focused window or None
    """
    # Check if this node is a focused window (has pid means it's a window)
    if node.get("focused") and node.get("pid"):
        return node.get("id")

    # Recurse into child nodes
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        result = _find_focused_window(child)
        if result:
            return result

    return None


def get_focused_terminal_window_id() -> Optional[int]:
    """Get the container ID of the focused terminal window.

    Specifically looks for Ghostty or other terminal emulators.
    Falls back to any focused window if no terminal is focused.

    Returns:
        Window container ID or None
    """
    tree = sway_ipc(4)
    if not tree:
        return None

    focused = _find_focused_window_with_app(tree)
    if focused:
        return focused.get("id")

    return None


def get_focused_window_info() -> tuple[Optional[int], Optional[str]]:
    """Get focused window ID and project from marks.

    Returns:
        Tuple of (window_id, project) - project extracted from scoped marks
    """
    tree = sway_ipc(4)
    if not tree:
        return None, None

    window = _find_focused_window_with_app(tree)
    if not window:
        return None, None

    window_id = window.get("id")
    project = _extract_project_from_marks(window.get("marks", []))

    return window_id, project


def _extract_project_from_marks(marks: list) -> Optional[str]:
    """Extract project name from Sway window marks.

    Looks for scoped marks in format: scoped:app_type:owner/repo:branch:window_id
    Returns: owner/repo:branch

    Args:
        marks: List of window mark strings

    Returns:
        Project name or None
    """
    for mark in marks:
        if isinstance(mark, str) and mark.startswith("scoped:"):
            # Format: scoped:type:owner/repo:branch:id
            parts = mark.split(":")
            if len(parts) >= 4:
                # parts[2] = owner/repo, parts[3] = branch
                return f"{parts[2]}:{parts[3]}"
    return None


def _find_focused_window_with_app(node: dict) -> Optional[dict]:
    """Find focused window and return full node info.

    Args:
        node: Sway tree node

    Returns:
        Full window node dict or None
    """
    if node.get("focused") and node.get("pid"):
        return node

    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        result = _find_focused_window_with_app(child)
        if result:
            return result

    return None
