#!/usr/bin/env python3
"""
Feature 110: Notification Monitor - Streaming backend for Eww notification badge

Subscribes to SwayNC events via `swaync-client --subscribe` and streams
enriched JSON to stdout for Eww's deflisten mechanism.

Output schema (per contracts/eww-deflisten.md):
{
    "count": int,           # Number of notifications (0-N)
    "dnd": bool,            # Do Not Disturb enabled
    "visible": bool,        # Control center panel open
    "inhibited": bool,      # Notifications inhibited by app
    "has_unread": bool,     # Computed: count > 0
    "display_count": str    # Badge text: "0"-"9" or "9+"
}
"""

import json
import subprocess
import sys
import time
from typing import Optional

# Reconnection settings (exponential backoff)
INITIAL_RETRY_DELAY = 1.0  # seconds
MAX_RETRY_DELAY = 30.0  # seconds
BACKOFF_MULTIPLIER = 2.0


def get_initial_state() -> dict:
    """Return default state when SwayNC is unavailable."""
    return {
        "count": 0,
        "dnd": False,
        "visible": False,
        "inhibited": False,
        "has_unread": False,
        "display_count": "0",
        "error": False
    }


def get_error_state() -> dict:
    """Return error state when SwayNC daemon is unavailable."""
    state = get_initial_state()
    state["error"] = True
    return state


def transform_event(raw_event: dict) -> dict:
    """
    Transform SwayNC event to Eww-compatible format.

    Input (from swaync-client --subscribe):
        {"count": 2, "dnd": false, "visible": false, "inhibited": false}

    Output (for Eww deflisten):
        {"count": 2, "dnd": false, "visible": false, "inhibited": false,
         "has_unread": true, "display_count": "2", "error": false}
    """
    count = raw_event.get("count", 0)

    return {
        "count": count,
        "dnd": raw_event.get("dnd", False),
        "visible": raw_event.get("visible", False),
        "inhibited": raw_event.get("inhibited", False),
        "has_unread": count > 0,
        "display_count": "9+" if count > 9 else str(count),
        "error": False
    }


def emit(data: dict) -> None:
    """Emit JSON to stdout with immediate flush for Eww deflisten."""
    print(json.dumps(data), flush=True)


def subscribe_loop() -> None:
    """
    Main subscription loop with automatic reconnection.

    Spawns `swaync-client --subscribe` and processes its JSON output.
    On daemon failure, waits with exponential backoff before retrying.
    """
    retry_delay = INITIAL_RETRY_DELAY

    while True:
        try:
            # Spawn SwayNC subscribe process
            proc = subprocess.Popen(
                ["swaync-client", "--subscribe"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1  # Line-buffered
            )

            # Reset retry delay on successful connection
            retry_delay = INITIAL_RETRY_DELAY

            # Process events from SwayNC
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue

                try:
                    raw_event = json.loads(line)
                    transformed = transform_event(raw_event)
                    emit(transformed)
                except json.JSONDecodeError as e:
                    # Log malformed JSON to stderr, skip line
                    print(f"[notification-monitor] Malformed JSON: {e}", file=sys.stderr)
                    continue

            # Process ended (daemon stopped/crashed)
            proc.wait()

        except FileNotFoundError:
            # swaync-client not found
            print("[notification-monitor] swaync-client not found, retrying...", file=sys.stderr)
            emit(get_error_state())

        except Exception as e:
            print(f"[notification-monitor] Error: {e}", file=sys.stderr)
            emit(get_error_state())

        # Wait before reconnecting (exponential backoff)
        print(f"[notification-monitor] Reconnecting in {retry_delay}s...", file=sys.stderr)
        time.sleep(retry_delay)
        retry_delay = min(retry_delay * BACKOFF_MULTIPLIER, MAX_RETRY_DELAY)


def main() -> None:
    """Entry point: emit initial state then start subscription loop."""
    # Emit initial state immediately so Eww has valid data
    emit(get_initial_state())

    # Start the main subscription loop
    subscribe_loop()


if __name__ == "__main__":
    main()
