"""CLI commands for workspace mode navigation.

Feature 042: Event-Driven Workspace Mode Navigation
Provides user-facing commands: digit, execute, cancel, state, history
"""

import asyncio
import json
import sys
from pathlib import Path
from typing import Optional
from rich.console import Console
from rich.table import Table
from datetime import datetime

# Daemon socket path
DAEMON_SOCKET = Path.home() / ".local" / "state" / "i3-project-daemon.sock"

console = Console()


async def send_ipc_request(method: str, params: Optional[dict] = None) -> dict:
    """Send JSON-RPC request to daemon.

    Args:
        method: RPC method name (e.g., "workspace_mode.digit")
        params: Method parameters (default: empty dict)

    Returns:
        Response result dict

    Raises:
        ConnectionError: If daemon socket not available
        RuntimeError: If RPC method returns error
    """
    if params is None:
        params = {}

    if not DAEMON_SOCKET.exists():
        raise ConnectionError(
            f"Daemon socket not found: {DAEMON_SOCKET}\n"
            "Ensure daemon is running: systemctl --user status i3-project-event-listener"
        )

    try:
        reader, writer = await asyncio.open_unix_connection(str(DAEMON_SOCKET))
    except Exception as e:
        raise ConnectionError(f"Failed to connect to daemon: {e}")

    # Send request
    request = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1
    }

    writer.write(json.dumps(request).encode() + b"\n")
    await writer.drain()

    # Read response
    response_line = await reader.readline()
    writer.close()
    await writer.wait_closed()

    if not response_line:
        raise RuntimeError("No response from daemon")

    response = json.loads(response_line.decode())

    # Check for RPC error
    if "error" in response:
        error = response["error"]
        raise RuntimeError(f"RPC error: {error.get('message', 'Unknown error')} (code: {error.get('code')})")

    return response.get("result", {})


def cmd_digit(digit: str) -> None:
    """Add digit to accumulated state (called from Sway bindings).

    Args:
        digit: Single digit 0-9

    Example:
        i3pm workspace-mode digit 2
    """
    if not digit or digit not in "0123456789":
        console.print(f"[red]Error:[/red] Invalid digit '{digit}'. Must be 0-9.", file=sys.stderr)
        sys.exit(1)

    try:
        result = asyncio.run(send_ipc_request("workspace_mode.digit", {"digit": digit}))
        # Silent success (no output needed, status bar shows feedback)
    except Exception as e:
        console.print(f"[red]Error:[/red] {e}", file=sys.stderr)
        sys.exit(1)


def cmd_execute() -> None:
    """Execute workspace switch with accumulated digits.

    Example:
        i3pm workspace-mode execute
    """
    try:
        result = asyncio.run(send_ipc_request("workspace_mode.execute", {}))
        # Silent success (workspace switch happens via i3 IPC)
    except Exception as e:
        console.print(f"[red]Error:[/red] {e}", file=sys.stderr)
        sys.exit(1)


def cmd_cancel() -> None:
    """Cancel workspace mode without action.

    Example:
        i3pm workspace-mode cancel
    """
    try:
        result = asyncio.run(send_ipc_request("workspace_mode.cancel", {}))
        # Silent success
    except Exception as e:
        console.print(f"[red]Error:[/red] {e}", file=sys.stderr)
        sys.exit(1)


def cmd_state(json_output: bool = False) -> None:
    """Query current workspace mode state.

    Args:
        json_output: If True, output raw JSON

    Example:
        i3pm workspace-mode state
        i3pm workspace-mode state --json
    """
    try:
        result = asyncio.run(send_ipc_request("workspace_mode.state", {}))

        if json_output:
            print(json.dumps(result, indent=2))
        else:
            # Human-readable output
            active = result.get("active", False)

            if active:
                mode_type = result.get("mode_type", "unknown")
                digits = result.get("accumulated_digits", "")
                entered_at = result.get("entered_at")

                console.print(f"[green]Active:[/green] {active}")
                console.print(f"[blue]Mode:[/blue] {mode_type}")
                console.print(f"[yellow]Digits:[/yellow] {digits or '(none)'}")

                if entered_at:
                    dt = datetime.fromtimestamp(entered_at)
                    console.print(f"[cyan]Entered:[/cyan] {dt.strftime('%Y-%m-%d %H:%M:%S')}")
            else:
                console.print("[dim]Active: false[/dim]")

    except Exception as e:
        console.print(f"[red]Error:[/red] {e}", file=sys.stderr)
        sys.exit(1)


def cmd_history(limit: Optional[int] = None, json_output: bool = False) -> None:
    """Query workspace navigation history.

    Args:
        limit: Maximum number of entries to return (default: all)
        json_output: If True, output raw JSON

    Example:
        i3pm workspace-mode history
        i3pm workspace-mode history --limit 10
        i3pm workspace-mode history --json
    """
    try:
        params = {}
        if limit is not None:
            params["limit"] = limit

        result = asyncio.run(send_ipc_request("workspace_mode.history", params))

        if json_output:
            print(json.dumps(result, indent=2))
        else:
            # Human-readable table
            history = result.get("history", [])
            total = result.get("total", 0)

            if not history:
                console.print("[dim]No workspace switches recorded yet.[/dim]")
                return

            table = Table(title=f"Workspace Navigation History (showing {len(history)} of {total})")
            table.add_column("WS", justify="right", style="cyan")
            table.add_column("Output", style="magenta")
            table.add_column("Time", style="green")
            table.add_column("Mode", style="yellow")

            for switch in history:
                workspace = str(switch["workspace"])
                output = switch["output"]
                timestamp = switch["timestamp"]
                mode_type = switch["mode_type"]

                # Format timestamp
                dt = datetime.fromtimestamp(timestamp)
                time_str = dt.strftime("%Y-%m-%d %H:%M:%S")

                table.add_row(workspace, output, time_str, mode_type)

            console.print(table)

    except Exception as e:
        console.print(f"[red]Error:[/red] {e}", file=sys.stderr)
        sys.exit(1)


def main():
    """Main CLI entry point (argument parsing handled by caller)."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Workspace mode navigation commands",
        prog="i3pm workspace-mode"
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # digit command
    digit_parser = subparsers.add_parser("digit", help="Add digit to accumulated state")
    digit_parser.add_argument("digit", help="Single digit 0-9")

    # execute command
    subparsers.add_parser("execute", help="Execute workspace switch")

    # cancel command
    subparsers.add_parser("cancel", help="Cancel workspace mode")

    # state command
    state_parser = subparsers.add_parser("state", help="Query current mode state")
    state_parser.add_argument("--json", action="store_true", help="Output JSON")

    # history command
    history_parser = subparsers.add_parser("history", help="Query navigation history")
    history_parser.add_argument("--limit", type=int, help="Maximum entries to show")
    history_parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    # Dispatch to command handlers
    if args.command == "digit":
        cmd_digit(args.digit)
    elif args.command == "execute":
        cmd_execute()
    elif args.command == "cancel":
        cmd_cancel()
    elif args.command == "state":
        cmd_state(json_output=args.json)
    elif args.command == "history":
        cmd_history(limit=args.limit, json_output=args.json)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
