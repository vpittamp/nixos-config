"""
Event Trace Display Module

Rich-formatted display for event log with live update support.

Feature 039 - Task T099
"""

from rich.console import Console
from rich.table import Table
from rich.live import Live
from rich.text import Text
from typing import Dict, Any, List
from datetime import datetime


def format_timestamp(timestamp_str: str) -> str:
    """Format timestamp for display."""
    try:
        dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        return dt.strftime("%H:%M:%S.%f")[:-3]  # HH:MM:SS.mmm
    except:
        return timestamp_str


def format_duration(duration_ms: float) -> Text:
    """Format duration with color coding."""
    if duration_ms is None:
        return Text("N/A", style="dim")

    if duration_ms < 50:
        return Text(f"{duration_ms:.1f}ms", style="green")
    elif duration_ms < 100:
        return Text(f"{duration_ms:.1f}ms", style="yellow")
    else:
        return Text(f"{duration_ms:.1f}ms", style="red")


def create_event_table(events: List[Dict[str, Any]], title: str = "Recent Events") -> Table:
    """
    Create Rich table for event display.

    Args:
        events: List of event dictionaries
        title: Table title

    Returns:
        Rich Table object
    """
    table = Table(title=title, show_header=True, header_style="bold cyan")

    table.add_column("Time", style="dim")
    table.add_column("Type")
    table.add_column("Change")
    table.add_column("Window", overflow="fold")
    table.add_column("WS", justify="right")
    table.add_column("Duration", justify="right")
    table.add_column("Status")

    for event in events:
        timestamp = format_timestamp(event.get("timestamp", ""))
        event_type = event.get("event_type", "unknown")
        event_change = event.get("event_change", "")

        # Window info
        window_id = event.get("window_id")
        window_class = event.get("window_class", "")
        window_title = event.get("window_title", "")

        window_str = ""
        if window_class:
            window_str = window_class
        if window_title and len(window_title) < 40:
            window_str += f" - {window_title[:37]}..."

        # Workspace
        workspace = event.get("workspace_assigned")
        ws_str = str(workspace) if workspace else "-"

        # Duration
        duration_ms = event.get("handler_duration_ms")
        duration_text = format_duration(duration_ms)

        # Status
        error = event.get("error")
        if error:
            status = Text("✗ Error", style="red")
        elif event.get("marks_applied"):
            status = Text("✓ OK", style="green")
        else:
            status = Text("-", style="dim")

        table.add_row(
            timestamp,
            event_type,
            event_change,
            window_str,
            ws_str,
            duration_text,
            status
        )

    return table


def display_events(events: List[Dict[str, Any]], console: Console = None) -> None:
    """
    Display events in formatted table.

    Args:
        events: List of event dictionaries
        console: Rich console (optional, creates new if not provided)
    """
    if console is None:
        console = Console()

    if not events:
        console.print("[yellow]No events found[/yellow]")
        return

    table = create_event_table(events)
    console.print(table)

    # Summary
    console.print()
    console.print(f"[dim]Total events: {len(events)}[/dim]")


def display_events_live(events_getter: callable, console: Console = None) -> None:
    """
    Display events with live updates.

    Args:
        events_getter: Callable that returns current event list
        console: Rich console (optional, creates new if not provided)
    """
    if console is None:
        console = Console()

    with Live(create_event_table([]), refresh_per_second=2, console=console) as live:
        while True:
            try:
                events = events_getter()
                table = create_event_table(events, title="Recent Events (Live)")
                live.update(table)
            except KeyboardInterrupt:
                break
            except Exception as e:
                console.print(f"[red]Error: {e}[/red]")
                break


def display_event_details(event: Dict[str, Any], console: Console = None) -> None:
    """
    Display detailed information for a single event.

    Args:
        event: Event dictionary
        console: Rich console (optional, creates new if not provided)
    """
    if console is None:
        console = Console()

    console.print(f"\n[bold cyan]Event Details[/bold cyan]\n")

    # Basic info
    basic_table = Table(show_header=False)
    basic_table.add_column("Property", style="dim")
    basic_table.add_column("Value")

    basic_table.add_row("Timestamp", event.get("timestamp", "unknown"))
    basic_table.add_row("Event Type", event.get("event_type", "unknown"))
    basic_table.add_row("Change", event.get("event_change", ""))

    console.print(basic_table)
    console.print()

    # Window info
    window_id = event.get("window_id")
    if window_id:
        window_table = Table(title="Window", show_header=False)
        window_table.add_column("Property", style="dim")
        window_table.add_column("Value")

        window_table.add_row("ID", str(window_id))
        window_table.add_row("Class", event.get("window_class", "unknown"))
        window_table.add_row("Title", event.get("window_title", ""))

        console.print(window_table)
        console.print()

    # Processing info
    processing_table = Table(title="Processing", show_header=False)
    processing_table.add_column("Property", style="dim")
    processing_table.add_column("Value")

    duration_ms = event.get("handler_duration_ms")
    if duration_ms:
        processing_table.add_row("Handler Duration", format_duration(duration_ms))

    workspace_assigned = event.get("workspace_assigned")
    if workspace_assigned:
        processing_table.add_row("Workspace Assigned", str(workspace_assigned))

    marks_applied = event.get("marks_applied", [])
    if marks_applied:
        processing_table.add_row("Marks Applied", ", ".join(marks_applied))

    error = event.get("error")
    if error:
        processing_table.add_row("Error", Text(error, style="red"))

    console.print(processing_table)


def format_events_json(events: List[Dict[str, Any]]) -> str:
    """
    Format events as JSON string.

    Args:
        events: List of event dictionaries

    Returns:
        JSON string
    """
    import json
    return json.dumps(events, indent=2)
