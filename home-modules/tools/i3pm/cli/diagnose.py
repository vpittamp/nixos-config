"""
Diagnostic commands for i3pm environment variable-based window matching.

Provides commands for:
- Coverage validation across all windows
- Window-specific environment inspection
- Environment variable troubleshooting
"""

import asyncio
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

import click
from rich.console import Console
from rich.table import Table

tools_root = Path(__file__).resolve().parents[2]
if str(tools_root) not in sys.path:
    sys.path.insert(0, str(tools_root))

from i3_project_manager.core.daemon_client import DaemonClient, DaemonError

console = Console()


@click.group()
def diagnose():
    """Diagnostic commands for environment variable validation."""
    pass


@diagnose.command()
@click.option(
    "--json",
    "output_json",
    is_flag=True,
    help="Output results as JSON instead of table",
)
async def coverage(output_json: bool):
    """
    Validate environment variable coverage across all windows.

    Checks that all launched applications have I3PM_* environment variables
    injected. Reports coverage percentage and lists windows without variables.

    Examples:
        i3pm diagnose coverage
        i3pm diagnose coverage --json
    """
    try:
        report = await _build_coverage_report()

        if output_json:
            click.echo(json.dumps(report, indent=2))
        else:
            _display_coverage_report(report)

        sys.exit(0 if report["status"] == "PASS" else 1)

    except Exception as e:
        console.print(f"[red]Error validating coverage: {e}[/red]")
        sys.exit(2)


@diagnose.command()
@click.argument("window_id", type=int)
@click.option(
    "--json",
    "output_json",
    is_flag=True,
    help="Output results as JSON instead of table",
)
async def window(window_id: int, output_json: bool):
    """
    Inspect environment variables for a specific window.

    Shows daemon-reported I3PM_* environment variables for the specified window.

    Examples:
        i3pm diagnose window 94532735639728
        i3pm diagnose window 94532735639728 --json

    Get window ID:
        i3pm windows list --json | jq '.windows[] | .window_id'
    """
    try:
        payload = await _get_window_payload(window_id)

        if output_json:
            click.echo(json.dumps(payload, indent=2))
        else:
            _display_window_environment(payload)

        sys.exit(0 if payload.get("environment") else 1)

    except Exception as e:
        console.print(f"[red]Error inspecting window: {e}[/red]")
        sys.exit(2)


async def _build_coverage_report() -> Dict[str, Any]:
    async with DaemonClient() as daemon:
        windows_response = await daemon.get_windows()
        windows = windows_response.get("windows", [])

        missing_windows = []
        windows_with_env = 0

        for window in windows:
            state = await daemon.get_window_state(window["window_id"])
            env = state.get("i3pm_env") or {}
            if env:
                windows_with_env += 1
                continue

            missing_windows.append(
                {
                    "window_id": window["window_id"],
                    "window_class": state.get("window_class") or window.get("class") or "",
                    "window_title": state.get("window_title") or window.get("title") or "",
                    "pid": state.get("pid"),
                    "reason": "no_pid" if not state.get("pid") else "missing_i3pm_env",
                }
            )

    total_windows = len(windows)
    windows_without_env = len(missing_windows)
    coverage_percentage = (windows_with_env / total_windows * 100.0) if total_windows else 100.0

    return {
        "total_windows": total_windows,
        "windows_with_env": windows_with_env,
        "windows_without_env": windows_without_env,
        "coverage_percentage": coverage_percentage,
        "status": "PASS" if windows_without_env == 0 else "FAIL",
        "timestamp": datetime.now().isoformat(),
        "missing_windows": missing_windows,
    }


async def _get_window_payload(window_id: int) -> Dict[str, Any]:
    async with DaemonClient() as daemon:
        windows_response = await daemon.get_windows()
        windows = {window["window_id"]: window for window in windows_response.get("windows", [])}
        if window_id not in windows:
            raise DaemonError(f"Window {window_id} not found")

        state = await daemon.get_window_state(window_id)
        env = state.get("i3pm_env") or {}

    return {
        "window_id": window_id,
        "window_class": state.get("window_class") or windows[window_id].get("class") or "(unknown)",
        "window_title": state.get("window_title") or windows[window_id].get("title") or "(no title)",
        "pid": state.get("pid"),
        "workspace": state.get("i3_state", {}).get("workspace"),
        "query_time_ms": state.get("duration_ms", 0.0),
        "error": None if env else "missing_i3pm_env",
        "environment": env or None,
    }


def _display_coverage_report(report: Dict[str, Any]):
    """Display coverage report as formatted table."""
    # Summary section
    console.print("\n[bold]Environment Variable Coverage Report[/bold]")
    console.print(f"Timestamp: {report['timestamp']}\n")

    # Statistics table
    stats_table = Table(show_header=True, header_style="bold cyan")
    stats_table.add_column("Metric", style="cyan")
    stats_table.add_column("Value", justify="right")

    stats_table.add_row("Total Windows", str(report["total_windows"]))
    stats_table.add_row("With I3PM_* Variables", str(report["windows_with_env"]))
    stats_table.add_row("Without Variables", str(report["windows_without_env"]))
    stats_table.add_row(
        "Coverage",
        f"{report['coverage_percentage']:.1f}%",
    )

    # Status with color
    status_color = "green" if report["status"] == "PASS" else "red"
    stats_table.add_row("Status", f"[{status_color}]{report['status']}[/{status_color}]")

    console.print(stats_table)

    # Missing windows table (if any)
    if report["missing_windows"]:
        console.print(f"\n[bold yellow]Missing Windows ({len(report['missing_windows'])})[/bold yellow]\n")

        missing_table = Table(show_header=True, header_style="bold yellow")
        missing_table.add_column("Window ID", style="yellow")
        missing_table.add_column("Class")
        missing_table.add_column("Title", max_width=40)
        missing_table.add_column("PID", justify="right")
        missing_table.add_column("Reason")

        for missing in report["missing_windows"][:20]:
            missing_table.add_row(
                str(missing["window_id"]),
                missing["window_class"],
                missing["window_title"][:40] if missing["window_title"] else "(no title)",
                str(missing["pid"]) if missing["pid"] else "N/A",
                missing["reason"],
            )

        console.print(missing_table)

        if len(report["missing_windows"]) > 20:
            console.print(f"\n[dim]... and {len(report['missing_windows']) - 20} more[/dim]")


def _display_window_environment(payload: Dict[str, Any]):
    """Display window environment as formatted output."""
    console.print(f"\n[bold]Window Environment: {payload['window_id']}[/bold]\n")

    # Window info
    info_table = Table(show_header=False, box=None)
    info_table.add_column("Property", style="cyan")
    info_table.add_column("Value")

    info_table.add_row("Window ID", str(payload["window_id"]))
    info_table.add_row("Window Class", payload["window_class"])
    info_table.add_row("Window Title", payload["window_title"] or "(no title)")
    info_table.add_row("PID", str(payload["pid"]) if payload.get("pid") else "N/A")
    info_table.add_row("Workspace", str(payload["workspace"]) if payload.get("workspace") is not None else "N/A")

    console.print(info_table)

    # Query info
    console.print(f"\n[bold]Environment Query[/bold]\n")
    query_table = Table(show_header=False, box=None)
    query_table.add_column("Property", style="cyan")
    query_table.add_column("Value")

    query_table.add_row("Requested PID", str(payload["pid"]) if payload.get("pid") else "N/A")
    query_table.add_row("Actual PID", str(payload["pid"]) if payload.get("pid") else "N/A")
    query_table.add_row("Traversal Depth", "daemon-managed")
    query_table.add_row("Query Time", f"{payload['query_time_ms']:.2f}ms")

    if payload.get("error"):
        query_table.add_row("Error", f"[red]{payload['error']}[/red]")

    console.print(query_table)

    # Environment variables
    if payload.get("environment"):
        console.print(f"\n[bold green]I3PM_* Environment Variables[/bold green]\n")
        env_table = Table(show_header=False, box=None)
        env_table.add_column("Variable", style="green")
        env_table.add_column("Value")

        env = payload["environment"]
        app_id = env.get("I3PM_APP_ID") or "(none)"
        env_table.add_row("I3PM_APP_ID", app_id[:50] + "..." if len(app_id) > 50 else app_id)
        env_table.add_row("I3PM_APP_NAME", env.get("I3PM_APP_NAME", "(none)"))
        env_table.add_row("I3PM_SCOPE", env.get("I3PM_SCOPE", "(none)"))
        env_table.add_row("I3PM_PROJECT_NAME", env.get("I3PM_PROJECT_NAME") or "(none)")
        env_table.add_row("I3PM_PROJECT_DIR", env.get("I3PM_PROJECT_DIR") or "(none)")
        if env.get("I3PM_TARGET_WORKSPACE") is not None:
            env_table.add_row("I3PM_TARGET_WORKSPACE", str(env["I3PM_TARGET_WORKSPACE"]))
        if env.get("I3PM_EXPECTED_CLASS"):
            env_table.add_row("I3PM_EXPECTED_CLASS", env["I3PM_EXPECTED_CLASS"])

        console.print(env_table)
        console.print("\n[bold green]✓ Environment is present on the tracked window process[/bold green]")
    else:
        console.print(f"\n[bold yellow]No I3PM_* environment variables found[/bold yellow]")
        console.print("[dim]The daemon did not report managed environment for this window[/dim]")


# Make commands async-compatible
def _run_async(coro):
    """Helper to run async commands."""
    return asyncio.run(coro)


# Wrap commands to run async
_coverage_original = coverage
_window_original = window


@diagnose.command(name="coverage")
@click.option("--json", "output_json", is_flag=True, help="Output as JSON")
def coverage_sync(output_json):
    """Validate environment variable coverage."""
    _run_async(_coverage_original.callback(output_json))


@diagnose.command(name="window")
@click.argument("window_id", type=int)
@click.option("--json", "output_json", is_flag=True, help="Output as JSON")
def window_sync(window_id, output_json):
    """Inspect window environment variables."""
    _run_async(_window_original.callback(window_id, output_json))


@diagnose.command(name="socket-health")
@click.option("--json", "output_json", is_flag=True, help="Output as JSON")
def socket_health(output_json):
    """
    Query daemon for Sway IPC socket health status.

    Feature 121: Shows socket connectivity and health status.

    Returns JSON with:
    - status: "healthy", "stale", or "disconnected"
    - socket_path: Current socket path
    - last_validated: Timestamp of last successful validation
    - latency_ms: Round-trip time for health check
    - reconnection_count: Number of reconnections since daemon start
    - uptime_seconds: Time since last successful connection

    Examples:
        i3pm diagnose socket-health
        i3pm diagnose socket-health --json
    """
    import socket as sock
    from pathlib import Path

    # Find daemon IPC socket
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    daemon_socket = Path(runtime_dir) / "i3-project-daemon" / "ipc.sock"

    if not daemon_socket.exists():
        console.print(f"[red]Daemon socket not found: {daemon_socket}[/red]")
        console.print("[yellow]Is i3-project-daemon running?[/yellow]")
        sys.exit(1)

    try:
        # Send JSON-RPC request to daemon
        request = json.dumps({
            "jsonrpc": "2.0",
            "method": "get_socket_health",
            "params": {},
            "id": 1,
        })

        # Connect to daemon socket
        client = sock.socket(sock.AF_UNIX, sock.SOCK_STREAM)
        client.settimeout(5.0)
        client.connect(str(daemon_socket))
        client.sendall((request + "\n").encode())

        # Read response
        response_data = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            response_data += chunk
            if b"\n" in chunk:
                break

        client.close()

        # Parse response
        response = json.loads(response_data.decode().strip())

        if "error" in response:
            console.print(f"[red]Daemon error: {response['error']['message']}[/red]")
            sys.exit(1)

        result = response.get("result", {})

        if output_json:
            click.echo(json.dumps(result, indent=2))
        else:
            _display_socket_health(result)

        # Exit with status based on health
        if result.get("status") == "healthy":
            sys.exit(0)
        elif result.get("status") == "stale":
            sys.exit(1)
        else:
            sys.exit(2)

    except sock.timeout:
        console.print("[red]Daemon connection timed out[/red]")
        sys.exit(2)
    except ConnectionRefusedError:
        console.print("[red]Daemon not accepting connections[/red]")
        sys.exit(2)
    except Exception as e:
        console.print(f"[red]Error querying daemon: {e}[/red]")
        sys.exit(2)


def _display_socket_health(result):
    """Display socket health status as formatted output."""
    status = result.get("status", "unknown")
    socket_path = result.get("socket_path", "(none)")
    last_validated = result.get("last_validated", "(never)")
    latency_ms = result.get("latency_ms")
    reconnection_count = result.get("reconnection_count", 0)
    uptime_seconds = result.get("uptime_seconds", 0)
    error = result.get("error")

    console.print("\n[bold]Sway IPC Socket Health[/bold]\n")

    # Status with color
    status_color = {
        "healthy": "green",
        "stale": "yellow",
        "disconnected": "red",
    }.get(status, "white")

    health_table = Table(show_header=False, box=None)
    health_table.add_column("Property", style="cyan")
    health_table.add_column("Value")

    health_table.add_row("Status", f"[{status_color}]{status.upper()}[/{status_color}]")
    health_table.add_row("Socket Path", socket_path or "(none)")
    health_table.add_row("Last Validated", last_validated or "(never)")
    health_table.add_row("Latency", f"{latency_ms:.2f}ms" if latency_ms is not None else "N/A")
    health_table.add_row("Reconnection Count", str(reconnection_count))
    health_table.add_row("Uptime", f"{uptime_seconds:.1f}s")

    if error:
        health_table.add_row("Error", f"[red]{error}[/red]")

    console.print(health_table)


if __name__ == "__main__":
    diagnose()
