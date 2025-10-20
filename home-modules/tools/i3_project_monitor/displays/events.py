"""Event stream display mode.

Live monitoring of events as they occur in real-time with <100ms latency.
"""

import asyncio
from collections import deque
from datetime import datetime
from typing import Any, Dict, Optional, Deque

from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from ..daemon_client import DaemonClient
from ..models import EventEntry
from .base import BaseDisplay


class EventsDisplay(BaseDisplay):
    """Live event stream display mode."""

    def __init__(
        self,
        client: DaemonClient,
        event_filter: Optional[str] = None,
        console: Optional[Console] = None,
    ):
        """Initialize events display.

        Args:
            client: DaemonClient instance for daemon communication
            event_filter: Optional event type filter (e.g., "window", "workspace", "tick")
            console: Optional Rich Console instance
        """
        super().__init__(client, console)
        self.event_filter = event_filter
        self.event_buffer: Deque[Dict[str, Any]] = deque(maxlen=100)
        self.events_received = 0
        self.errors_count = 0
        self.start_time = datetime.now()
        self.running = True
        self.connection_lost = False

    async def run(self) -> None:
        """Run event stream display with live updates.

        This subscribes to daemon events and displays them in real-time.
        """
        # Subscribe to events
        try:
            await self._subscribe_to_events()
        except ConnectionError as e:
            self.print_error(f"Failed to subscribe to events: {e}")
            return

        # Start live display with event listener
        with Live(
            self._create_layout(),
            console=self.console,
            refresh_per_second=10,  # 100ms refresh for low latency
            screen=True,
        ) as live:
            try:
                # Run event listener in background
                listener_task = asyncio.create_task(self._event_listener())

                # Update display loop
                while self.running:
                    layout = self._render_display()
                    live.update(layout)
                    await asyncio.sleep(0.1)  # 100ms update interval

            except KeyboardInterrupt:
                self.console.print("\n[yellow]Event stream stopped by user[/yellow]")
                self.running = False
            except Exception as e:
                self.console.print(f"\n[red]Error in event stream: {e}[/red]")
                raise
            finally:
                # Cancel listener task
                if not listener_task.done():
                    listener_task.cancel()
                    try:
                        await listener_task
                    except asyncio.CancelledError:
                        pass

    async def _subscribe_to_events(self) -> None:
        """Subscribe to daemon event stream.

        Raises:
            ConnectionError: If subscription fails
        """
        # Build event_types filter if specified
        event_types = None
        if self.event_filter:
            event_types = [self.event_filter]

        try:
            await self.client.subscribe_events(event_types=event_types)
            self.print_info(f"Subscribed to events{f' (filter: {self.event_filter})' if self.event_filter else ''}")
        except Exception as e:
            raise ConnectionError(f"Failed to subscribe: {e}")

    async def _event_listener(self) -> None:
        """Background task that listens for events and adds them to buffer.

        This runs continuously and populates the event_buffer with incoming events.
        """
        try:
            async for event in self.client.stream_events():
                # Parse event data
                event_data = {
                    "timestamp": event.get("timestamp", datetime.now().isoformat()),
                    "event_type": event.get("event_type", "unknown"),
                    "event_id": event.get("event_id", self.events_received),
                    "window_id": event.get("window_id"),
                    "window_class": event.get("window_class"),
                    "workspace_name": event.get("workspace_name"),
                    "project_name": event.get("project_name"),
                    "tick_payload": event.get("tick_payload"),
                    "processing_duration_ms": event.get("processing_duration_ms", 0.0),
                    "error": event.get("error"),
                }

                # Apply filter if specified
                if self.event_filter:
                    if not event_data["event_type"].startswith(self.event_filter):
                        continue

                # Add to buffer
                self.event_buffer.append(event_data)
                self.events_received += 1

                # Track errors
                if event_data["error"]:
                    self.errors_count += 1

                # Reset connection lost flag
                self.connection_lost = False

        except ConnectionError as e:
            self.connection_lost = True
            self.print_warning(f"Connection lost: {e}")
            # Try to reconnect
            await self._handle_connection_loss()

    async def _handle_connection_loss(self) -> None:
        """Handle connection loss and attempt reconnection.

        Shows "Connection lost, retrying..." status during reconnection.
        """
        self.connection_lost = True
        retry_count = 0
        max_retries = 5

        while retry_count < max_retries and self.running:
            retry_count += 1
            delay = min(2 ** retry_count, 16)  # Exponential backoff

            self.print_warning(f"Attempting reconnect ({retry_count}/{max_retries}) in {delay}s...")
            await asyncio.sleep(delay)

            try:
                # Try to reconnect
                await self.client.connect()
                await self._subscribe_to_events()

                self.connection_lost = False
                self.print_info("Reconnected successfully")
                return

            except Exception as e:
                self.print_warning(f"Reconnect attempt {retry_count} failed: {e}")

        # All retries exhausted
        self.print_error("Failed to reconnect after all attempts")
        self.running = False

    def _create_layout(self) -> Layout:
        """Create initial layout structure.

        Returns:
            Rich Layout with events table and footer
        """
        layout = Layout()
        layout.split_column(
            Layout(name="events", ratio=10),
            Layout(name="footer", ratio=1),
        )
        return layout

    def _render_display(self) -> Layout:
        """Render complete display layout.

        Returns:
            Rendered Rich Layout
        """
        layout = self._create_layout()
        layout["events"].update(self._render_events_table())
        layout["footer"].update(self._render_footer())
        return layout

    def _render_events_table(self) -> Panel:
        """Render events stream table.

        Returns:
            Rich Panel with events table
        """
        # Create table
        table = Table(
            show_header=True,
            header_style="bold cyan",
            border_style="blue",
            show_lines=False,
        )

        table.add_column("TIME", justify="left", style="dim", width=12)
        table.add_column("TYPE", justify="left", style="yellow", width=20)
        table.add_column("WINDOW", justify="left", style="cyan", width=15)
        table.add_column("PROJECT", justify="left", style="magenta", width=12)
        table.add_column("DETAILS", justify="left", style="white", no_wrap=False)

        # Add events from buffer (most recent first)
        if not self.event_buffer:
            table.add_row("—", "—", "—", "—", "[dim]Waiting for events...[/dim]")
        else:
            # Show events in reverse chronological order (newest first)
            for event in reversed(list(self.event_buffer)):
                time_str = self.format_timestamp(event["timestamp"], include_date=False)
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
                    event_type = f"[cyan]{event_type}[/cyan]"
                elif event_type.startswith("workspace"):
                    event_type = f"[yellow]{event_type}[/yellow]"
                elif event_type.startswith("tick"):
                    event_type = f"[magenta]{event_type}[/magenta]"

                table.add_row(time_str, event_type, window_class, project, details)

        return Panel(
            table,
            title=f"[bold green]Event Stream[/bold green]{f' (filter: {self.event_filter})' if self.event_filter else ''}",
            border_style="green",
            padding=(0, 1),
        )

    def _render_footer(self) -> Panel:
        """Render statistics footer.

        Returns:
            Rich Panel with statistics
        """
        # Calculate uptime
        uptime = (datetime.now() - self.start_time).total_seconds()
        uptime_str = self.format_uptime(uptime)

        # Build status text
        status_text = Text.assemble(
            ("Events: ", "bold white"),
            (str(self.events_received), "green"),
            ("  |  ", "dim"),
            ("Errors: ", "bold white"),
            (str(self.errors_count), "red" if self.errors_count > 0 else "green"),
            ("  |  ", "dim"),
            ("Duration: ", "bold white"),
            (uptime_str, "cyan"),
        )

        # Add connection status
        if self.connection_lost:
            status_text.append("  |  ", "dim")
            status_text.append("[red bold]Connection lost, retrying...[/red bold]")

        return Panel(
            status_text,
            border_style="dim",
            padding=(0, 1),
        )
