"""Historical event log display mode.

Static display of recent events from daemon's event buffer with filtering.
"""

from typing import Any, Dict, List, Optional

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from ..daemon_client import DaemonClient
from .base import BaseDisplay


class HistoryDisplay(BaseDisplay):
    """Historical event log display mode."""

    def __init__(
        self,
        client: DaemonClient,
        limit: int = 20,
        event_filter: Optional[str] = None,
        console: Optional[Console] = None,
    ):
        """Initialize history display.

        Args:
            client: DaemonClient instance for daemon communication
            limit: Maximum number of events to display (default 20, max 500)
            event_filter: Optional event type filter (e.g., "window", "workspace", "tick")
            console: Optional Rich Console instance
        """
        super().__init__(client, console)
        self.limit = min(limit, 500)  # Cap at 500
        self.event_filter = event_filter

    async def run(self) -> None:
        """Run history display.

        This queries the daemon for recent events and displays them as a static log.
        """
        # Fetch events from daemon
        try:
            events_data = await self.client.get_events(
                limit=self.limit,
                event_type=self.event_filter,
            )
        except ConnectionError as e:
            self.print_error(f"Failed to fetch events: {e}")
            return
        except Exception as e:
            self.print_error(f"Error fetching events: {e}")
            return

        # Extract events list
        events = events_data.get("events", [])

        # Display events
        self._display_events(events)

    def _display_events(self, events: List[Dict[str, Any]]) -> None:
        """Display events as a formatted log.

        Args:
            events: List of event dictionaries from daemon
        """
        if not events:
            self.print_warning("No events found")
            self._show_empty_state()
            return

        # Create table
        table = Table(
            show_header=True,
            header_style="bold cyan",
            border_style="blue",
            show_lines=False,
            expand=True,
        )

        table.add_column("TIME", justify="left", style="dim", width=19)
        table.add_column("TYPE", justify="left", style="yellow", width=25)
        table.add_column("WINDOW", justify="left", style="cyan", width=15)
        table.add_column("PROJECT", justify="left", style="magenta", width=12)
        table.add_column("DETAILS", justify="left", style="white", no_wrap=False)

        # Add events (already in reverse chronological order from daemon)
        for event in events:
            time_str = self.format_timestamp(event["timestamp"], include_date=True)
            event_type = event["event_type"]
            window_class = event.get("window_class") or "—"
            project = event.get("project_name") or "[dim](global)[/dim]"

            # Build details column
            details_parts = []
            if event.get("window_id"):
                details_parts.append(f"ID:{event['window_id']}")
            if event.get("workspace_name"):
                details_parts.append(f"WS:{event['workspace_name']}")
            if event.get("tick_payload"):
                details_parts.append(f"Payload:{event['tick_payload']}")
            if event.get("processing_duration_ms"):
                duration_str = self.format_duration_ms(event["processing_duration_ms"])
                details_parts.append(f"({duration_str})")
            if event.get("error"):
                details_parts.append(f"[red]ERROR: {event['error']}[/red]")

            details = " | ".join(details_parts) if details_parts else "—"

            # Colorize event type
            if event_type.startswith("window"):
                event_type_colored = f"[cyan]{event_type}[/cyan]"
            elif event_type.startswith("workspace"):
                event_type_colored = f"[yellow]{event_type}[/yellow]"
            elif event_type.startswith("tick"):
                event_type_colored = f"[magenta]{event_type}[/magenta]"
            else:
                event_type_colored = event_type

            table.add_row(time_str, event_type_colored, window_class, project, details)

        # Create panel with table
        filter_info = f" (filter: {self.event_filter})" if self.event_filter else ""
        panel = Panel(
            table,
            title=f"[bold green]Event History[/bold green]{filter_info}",
            border_style="green",
            padding=(0, 1),
        )

        # Display table
        self.console.print(panel)

        # Display footer
        self._display_footer(len(events))

    def _display_footer(self, event_count: int) -> None:
        """Display summary footer.

        Args:
            event_count: Number of events displayed
        """
        # Build summary text
        summary_parts = []

        if self.event_filter:
            summary_parts.append(f"Showing {event_count} events")
            summary_parts.append(f"filtered by type: [yellow]{self.event_filter}[/yellow]")
        else:
            summary_parts.append(f"Showing {event_count} events")

        if event_count == self.limit:
            summary_parts.append(f"(limited to {self.limit})")

        summary_text = Text.assemble(*[
            (part + " ", "white") for part in summary_parts
        ])

        # Display footer panel
        footer = Panel(
            summary_text,
            border_style="dim",
            padding=(0, 1),
        )

        self.console.print(footer)

    def _show_empty_state(self) -> None:
        """Display empty state when no events are found."""
        message = Text.assemble(
            ("[dim]No events found", "dim"),
        )

        if self.event_filter:
            message.append("\n\n")
            message.append("Try removing the filter or checking a different event type:", "yellow")
            message.append("\n  ")
            message.append(f"Current filter: {self.event_filter}", "cyan")

        panel = Panel(
            message,
            title="[bold yellow]Event History[/bold yellow]",
            border_style="yellow",
            padding=(1, 2),
        )

        self.console.print(panel)
