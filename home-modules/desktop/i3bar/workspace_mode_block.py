#!/usr/bin/env python3
"""i3bar status block for workspace mode navigation.

Feature 042: Event-Driven Workspace Mode Navigation
Subscribes to daemon workspace_mode events and outputs i3bar protocol JSON.

Output Format:
- Mode inactive: Empty block (no output)
- Mode active: "WS: 23" (accumulated digits) or "WS: _" (no digits yet)
"""

import asyncio
import json
import sys
from pathlib import Path

# Daemon socket path (system service socket)
DAEMON_SOCKET = Path("/run/i3-project-daemon/ipc.sock")

# Catppuccin Mocha colors
COLOR_GREEN = "#a6e3a1"  # Active mode
COLOR_DIM = "#6c7086"    # Inactive mode


async def main():
    """Subscribe to daemon events and output workspace mode state."""

    if not DAEMON_SOCKET.exists():
        # Daemon not running - output empty block and exit
        print(json.dumps({"full_text": "", "short_text": ""}))
        sys.stdout.flush()
        return

    try:
        reader, writer = await asyncio.open_unix_connection(str(DAEMON_SOCKET))
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
                    # Event payload structure: {type, event_type, state: {active, mode_type, accumulated_digits}, timestamp}
                    state = params.get("state", {})

                    mode_active = state.get("active", False)
                    mode_type = state.get("mode_type")
                    accumulated_digits = state.get("accumulated_digits", "")

                    if mode_active:
                        # Show accumulated digits or placeholder
                        display_digits = accumulated_digits if accumulated_digits else "_"

                        # Mode indicator symbol
                        if mode_type == "goto":
                            mode_symbol = "→"  # Navigate to workspace
                        elif mode_type == "move":
                            mode_symbol = "⇒"  # Move window to workspace
                        else:
                            mode_symbol = "•"  # Unknown mode

                        full_text = f"{mode_symbol} WS: {display_digits}"

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
