#!/usr/bin/env python3
"""i3bar status block for workspace mode navigation and project switching.

Feature 042: Event-Driven Workspace Mode Navigation + Unified Project Switching
Subscribes to daemon workspace_mode events and outputs i3bar protocol JSON.

Output Format:
- Mode inactive: Empty block (no output)
- Workspace mode: "→ WS: 23" (accumulated digits) or "→ WS: _" (no digits yet)
- Project mode: "→ PR: nix" (accumulated chars) or "→ PR: _" (no chars yet)
"""

import asyncio
import json
import sys
from pathlib import Path

# Feature 117: Daemon socket path - user service at XDG_RUNTIME_DIR
import os
_runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
DAEMON_SOCKET = Path(f"{_runtime_dir}/i3-project-daemon/ipc.sock")

# Catppuccin Mocha colors
COLOR_GREEN = "#a6e3a1"  # Active mode
COLOR_DIM = "#6c7086"    # Inactive mode


async def main():
    """Subscribe to daemon events and output workspace mode state."""

    # Feature 117: User socket only (daemon runs as user service)
    socket_path = DAEMON_SOCKET
    if not socket_path.exists():
        # Daemon not running - output empty block and exit
        print(json.dumps({"full_text": "", "short_text": ""}))
        sys.stdout.flush()
        return

    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path))
    except Exception:
        # Connection failed - output empty block and exit
        print(json.dumps({"full_text": "", "short_text": ""}))
        sys.stdout.flush()
        return

    # Subscribe to events
    request = {
        "jsonrpc": "2.0",
        "method": "subscribe",
        "params": {},
        "id": 1
    }

    try:
        writer.write(json.dumps(request).encode() + b"\n")
        await writer.drain()
    except Exception:
        print(json.dumps({"full_text": "", "short_text": ""}))
        sys.stdout.flush()
        return

    # Output initial state (empty)
    print(json.dumps({"full_text": "", "short_text": ""}))
    sys.stdout.flush()

    # Process events
    try:
        while True:
            line = await reader.readline()
            if not line:
                break

            try:
                event = json.loads(line.decode())
            except json.JSONDecodeError:
                continue

            # Filter for workspace_mode events
            if event.get("method") == "event":
                params = event.get("params", {})
                if params.get("type") == "workspace_mode":
                    # Event payload structure: {type, event_type, state: {active, mode_type, accumulated_digits, accumulated_chars, input_type}, timestamp}
                    state = params.get("state", {})

                    mode_active = state.get("active", False)
                    mode_type = state.get("mode_type")
                    accumulated_digits = state.get("accumulated_digits", "")
                    accumulated_chars = state.get("accumulated_chars", "")
                    input_type = state.get("input_type")

                    if mode_active:
                        # Determine display based on input type
                        if input_type == "project":
                            # Project switching mode
                            display_text = accumulated_chars if accumulated_chars else "_"
                            label = "PR"
                        else:
                            # Workspace navigation mode (default)
                            display_text = accumulated_digits if accumulated_digits else "_"
                            label = "WS"

                        # Mode indicator symbol
                        if mode_type == "goto":
                            mode_symbol = "→"  # Navigate to workspace/project
                        elif mode_type == "move":
                            mode_symbol = "⇒"  # Move window to workspace
                        else:
                            mode_symbol = "•"  # Unknown mode

                        full_text = f"{mode_symbol} {label}: {display_text}"

                        output = {
                            "full_text": full_text,
                            "short_text": full_text,
                            "color": COLOR_GREEN,
                            "urgent": False
                        }
                    else:
                        # Mode inactive - show nothing
                        output = {
                            "full_text": "",
                            "short_text": ""
                        }

                    print(json.dumps(output))
                    sys.stdout.flush()

    except Exception:
        # Connection lost or error - output empty and exit
        print(json.dumps({"full_text": "", "short_text": ""}))
        sys.stdout.flush()
    finally:
        writer.close()
        await writer.wait_closed()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
