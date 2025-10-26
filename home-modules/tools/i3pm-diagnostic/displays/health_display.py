"""
Health Check Display Module

Rich-formatted display for daemon health status.

Feature 039 - Task T097
"""

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.text import Text
from typing import Dict, Any
from datetime import timedelta


def format_uptime(seconds: float) -> str:
    """Format uptime in human-readable format."""
    td = timedelta(seconds=int(seconds))
    parts = []

    if td.days > 0:
        parts.append(f"{td.days}d")

    hours = td.seconds // 3600
    if hours > 0:
        parts.append(f"{hours}h")

    minutes = (td.seconds % 3600) // 60
    if minutes > 0:
        parts.append(f"{minutes}m")

    secs = td.seconds % 60
    if secs > 0 or not parts:
        parts.append(f"{secs}s")

    return " ".join(parts)


def display_health(health_data: Dict[str, Any], console: Console = None) -> None:
    """
    Display daemon health check in formatted table.

    Args:
        health_data: Health check result from daemon
        console: Rich console (optional, creates new if not provided)
    """
    if console is None:
        console = Console()

    # Create main status table
    status_table = Table(title="Daemon Health Check", show_header=True, header_style="bold cyan")
    status_table.add_column("Check", style="dim")
    status_table.add_column("Status")

    # Add daemon info
    status_table.add_row("Daemon Version", health_data.get("daemon_version", "unknown"))
    status_table.add_row("Uptime", format_uptime(health_data.get("uptime_seconds", 0)))

    # Add connection status
    i3_connected = health_data.get("i3_ipc_connected", False)
    i3_status = Text("✓ Connected", style="green") if i3_connected else Text("✗ Disconnected", style="red")
    status_table.add_row("IPC Connection", i3_status)

    rpc_running = health_data.get("json_rpc_server_running", False)
    rpc_status = Text("✓ Running", style="green") if rpc_running else Text("✗ Stopped", style="red")
    status_table.add_row("JSON-RPC Server", rpc_status)

    console.print(status_table)
    console.print()

    # Create event subscriptions table
    subscriptions = health_data.get("event_subscriptions", [])
    if subscriptions:
        sub_table = Table(title="Event Subscriptions", show_header=True, header_style="bold cyan")
        sub_table.add_column("Type")
        sub_table.add_column("Active", justify="center")
        sub_table.add_column("Count", justify="right")
        sub_table.add_column("Last Event")

        for sub in subscriptions:
            sub_type = sub.get("subscription_type", "unknown")
            is_active = sub.get("is_active", False)
            event_count = sub.get("event_count", 0)
            last_event_time = sub.get("last_event_time", "never")
            last_event_change = sub.get("last_event_change", "")

            active_status = Text("✓", style="green") if is_active else Text("✗", style="red")
            last_event_str = f"{last_event_time}"
            if last_event_change:
                last_event_str += f" ({last_event_change})"

            sub_table.add_row(
                sub_type,
                active_status,
                f"{event_count:,}",
                last_event_str
            )

        console.print(sub_table)
        console.print()

    # Create window tracking table
    tracking_table = Table(show_header=False)
    tracking_table.add_column("Metric", style="dim")
    tracking_table.add_column("Value", justify="right")

    tracking_table.add_row("Total Windows", str(health_data.get("total_windows", 0)))
    tracking_table.add_row("Total Events Processed", f"{health_data.get('total_events_processed', 0):,}")

    console.print(Panel(tracking_table, title="Window Tracking"))
    console.print()

    # Overall status
    overall_status = health_data.get("overall_status", "unknown")
    health_issues = health_data.get("health_issues", [])

    if overall_status == "healthy":
        status_text = Text("✓ HEALTHY", style="bold green")
    elif overall_status == "warning":
        status_text = Text("⚠ WARNING", style="bold yellow")
    else:
        status_text = Text("✗ CRITICAL", style="bold red")

    console.print(Panel(status_text, title="Overall Status"))

    # Display health issues if any
    if health_issues:
        console.print()
        console.print("[bold red]Health Issues:[/bold red]")
        for issue in health_issues:
            console.print(f"  • {issue}", style="red")


def format_health_json(health_data: Dict[str, Any]) -> str:
    """
    Format health data as JSON string.

    Args:
        health_data: Health check result from daemon

    Returns:
        JSON string
    """
    import json
    return json.dumps(health_data, indent=2)
