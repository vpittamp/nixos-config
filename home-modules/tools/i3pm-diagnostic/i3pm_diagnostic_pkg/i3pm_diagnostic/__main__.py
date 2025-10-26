"""
I3PM Diagnostic CLI Tool

Main entry point for diagnostic commands.

Feature 039 - Tasks T093-T096, T100-T104

Usage:
    i3pm diagnose health [--json]
    i3pm diagnose window <window_id> [--json]
    i3pm diagnose events [--limit N] [--type TYPE] [--follow] [--json]
    i3pm diagnose validate [--json]
"""

import click
import json
import socket
import sys
from pathlib import Path
from rich.console import Console
from typing import Dict, Any, Optional

# Import display modules
from .displays import health_display, window_display, event_display


class DaemonClient:
    """JSON-RPC client for daemon communication."""

    def __init__(self, socket_path: Optional[Path] = None):
        """
        Initialize daemon client.

        Args:
            socket_path: Path to daemon socket (default: /run/i3-project-daemon/ipc.sock for system service)
        """
        if socket_path is None:
            socket_path = Path("/run/i3-project-daemon/ipc.sock")
        self.socket_path = socket_path
        self.request_id = 0

    def call(self, method: str, params: Optional[Dict[str, Any]] = None) -> Any:
        """
        Call JSON-RPC method on daemon.

        Args:
            method: Method name
            params: Method parameters (optional)

        Returns:
            Method result

        Raises:
            RuntimeError: If daemon is not running or returns error
        """
        self.request_id += 1

        request = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self.request_id
        }

        try:
            # Connect to daemon socket
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5.0)  # 5 second timeout
            sock.connect(str(self.socket_path))

            # Send request
            sock.sendall(json.dumps(request).encode() + b'\n')

            # Receive response
            response_data = b''
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response_data += chunk
                if b'\n' in chunk:  # Response complete
                    break

            sock.close()

            # Parse response
            response = json.loads(response_data.decode())

            if "error" in response:
                error = response["error"]
                raise RuntimeError(f"Daemon error: {error.get('message', 'Unknown error')}")

            return response.get("result")

        except socket.timeout:
            raise RuntimeError(
                "Timeout connecting to daemon (5s). Check daemon status:\n"
                "  systemctl --user status i3-project-event-listener"
            )
        except FileNotFoundError:
            raise RuntimeError(
                f"Daemon socket not found: {self.socket_path}\n"
                "Start daemon with: systemctl --user start i3-project-event-listener"
            )
        except ConnectionRefusedError:
            raise RuntimeError(
                "Daemon not running. Start with:\n"
                "  systemctl --user start i3-project-event-listener"
            )


@click.group()
def cli():
    """I3PM diagnostic commands for troubleshooting window management issues."""
    pass


@cli.command()
@click.option('--json', 'output_json', is_flag=True, help='Output JSON instead of formatted tables')
def health(output_json: bool):
    """
    Check daemon health and event subscriptions.

    Feature 039 - T093

    Displays:
    - Daemon version and uptime
    - i3 IPC connection status
    - JSON-RPC server status
    - Event subscription details
    - Window tracking stats
    - Overall health assessment

    Exit codes:
      0 - Healthy
      1 - Warning (state drift, subscription issues)
      2 - Critical (daemon not running, i3 IPC disconnected)
    """
    console = Console()

    try:
        client = DaemonClient()
        health_data = client.call("health_check")

        if output_json:
            console.print(health_display.format_health_json(health_data))
        else:
            health_display.display_health(health_data, console)

        # Set exit code based on status
        status = health_data.get("overall_status", "unknown")
        if status == "healthy":
            sys.exit(0)
        elif status == "warning":
            sys.exit(1)
        else:
            sys.exit(2)

    except RuntimeError as e:
        console.print(f"[red]Error: {e}[/red]")
        sys.exit(2)
    except Exception as e:
        console.print(f"[red]Unexpected error: {e}[/red]")
        sys.exit(2)


@cli.command()
@click.argument('window_id', type=int)
@click.option('--json', 'output_json', is_flag=True, help='Output JSON instead of formatted tables')
def window(window_id: int, output_json: bool):
    """
    Inspect window properties and matching information.

    Feature 039 - T094

    Shows comprehensive window identity including:
    - Window class and instance
    - Workspace and output location
    - I3PM environment variables
    - Registry matching details
    - Project association

    WINDOW_ID: i3 window container ID (get from `i3-msg -t get_tree`)
    """
    console = Console()

    try:
        client = DaemonClient()
        window_data = client.call("get_window_identity", {"window_id": window_id})

        if output_json:
            console.print(window_display.format_window_json(window_data))
        else:
            window_display.display_window_identity(window_data, console)

        sys.exit(0)

    except RuntimeError as e:
        error_msg = str(e)
        if "Window not found" in error_msg:
            console.print(f"[red]Error: Window {window_id} not found[/red]")
            console.print("[dim]Tip: Get window ID with: i3-msg -t get_tree | jq '.nodes[].nodes[].nodes[].id'[/dim]")
        else:
            console.print(f"[red]Error: {e}[/red]")
        sys.exit(1)
    except Exception as e:
        console.print(f"[red]Unexpected error: {e}[/red]")
        sys.exit(1)


@cli.command()
@click.option('--limit', type=int, default=50, help='Maximum number of events to show (1-500)')
@click.option('--type', 'event_type', type=str, help='Filter by event type (window, workspace, output, tick)')
@click.option('--follow', is_flag=True, help='Follow event stream in real-time')
@click.option('--json', 'output_json', is_flag=True, help='Output JSON instead of formatted tables')
def events(limit: int, event_type: Optional[str], follow: bool, output_json: bool):
    """
    View recent events from daemon event buffer.

    Feature 039 - T095

    Shows event trace with:
    - Event timestamps
    - Event types and changes
    - Window information
    - Processing duration
    - Errors if any

    Use --follow for live event monitoring (Ctrl+C to stop).
    """
    console = Console()

    if limit < 1 or limit > 500:
        console.print("[red]Error: Limit must be between 1 and 500[/red]")
        sys.exit(1)

    try:
        client = DaemonClient()

        if follow:
            # Live event stream
            if output_json:
                console.print("[yellow]Warning: --follow mode does not support --json output[/yellow]")

            console.print("[cyan]Following event stream (Ctrl+C to stop)...[/cyan]\n")

            def get_events():
                return client.call("get_recent_events", {"limit": limit, "event_type": event_type})

            try:
                event_display.display_events_live(get_events, console)
            except KeyboardInterrupt:
                console.print("\n[dim]Stopped event stream[/dim]")

        else:
            # One-time event display
            events_data = client.call("get_recent_events", {"limit": limit, "event_type": event_type})

            if output_json:
                console.print(event_display.format_events_json(events_data))
            else:
                event_display.display_events(events_data, console)

        sys.exit(0)

    except RuntimeError as e:
        console.print(f"[red]Error: {e}[/red]")
        sys.exit(1)
    except Exception as e:
        console.print(f"[red]Unexpected error: {e}[/red]")
        sys.exit(1)


@cli.command()
@click.option('--json', 'output_json', is_flag=True, help='Output JSON instead of formatted tables')
def validate(output_json: bool):
    """
    Validate daemon state consistency against i3 IPC.

    Feature 039 - T096

    Compares daemon tracked state with actual i3 window tree to detect:
    - Workspace mismatches
    - Mark inconsistencies
    - State drift

    Exit codes:
      0 - State is consistent
      1 - State inconsistencies detected
    """
    console = Console()

    try:
        client = DaemonClient()
        validation_data = client.call("validate_state")

        if output_json:
            console.print(json.dumps(validation_data, indent=2))
        else:
            # Display validation results
            console.print(f"\n[bold cyan]State Validation[/bold cyan]\n")

            from rich.table import Table

            summary_table = Table(show_header=False)
            summary_table.add_column("Metric", style="dim")
            summary_table.add_column("Value", justify="right")

            summary_table.add_row("Total Windows Checked", str(validation_data.get("total_windows_checked", 0)))
            summary_table.add_row("Consistent", str(validation_data.get("windows_consistent", 0)))
            summary_table.add_row("Inconsistent", str(validation_data.get("windows_inconsistent", 0)))
            summary_table.add_row("Consistency", f"{validation_data.get('consistency_percentage', 0)}%")

            console.print(summary_table)
            console.print()

            # Display mismatches if any
            mismatches = validation_data.get("mismatches", [])
            if mismatches:
                console.print("[bold red]Mismatches Found:[/bold red]\n")

                mismatch_table = Table()
                mismatch_table.add_column("Window ID")
                mismatch_table.add_column("Property")
                mismatch_table.add_column("Daemon Value")
                mismatch_table.add_column("i3 Value")
                mismatch_table.add_column("Severity")

                for mismatch in mismatches:
                    severity_style = "red" if mismatch.get("severity") == "error" else "yellow"
                    mismatch_table.add_row(
                        str(mismatch.get("window_id")),
                        mismatch.get("property_name"),
                        str(mismatch.get("daemon_value")),
                        str(mismatch.get("i3_value")),
                        f"[{severity_style}]{mismatch.get('severity')}[/{severity_style}]"
                    )

                console.print(mismatch_table)
                console.print()

            # Overall status
            is_consistent = validation_data.get("is_consistent", False)
            if is_consistent:
                from rich.text import Text
                console.print(Text(" State is consistent", style="bold green"))
            else:
                from rich.text import Text
                console.print(Text(" State inconsistencies detected", style="bold red"))

        # Set exit code
        is_consistent = validation_data.get("is_consistent", False)
        sys.exit(0 if is_consistent else 1)

    except RuntimeError as e:
        console.print(f"[red]Error: {e}[/red]")
        sys.exit(1)
    except Exception as e:
        console.print(f"[red]Unexpected error: {e}[/red]")
        sys.exit(1)


if __name__ == '__main__':
    cli()
