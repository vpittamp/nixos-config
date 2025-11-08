"""Live streaming view for real-time event monitoring

Displays events as they occur with <100ms latency.

Features:
- Real-time event stream using DataTable
- Auto-scroll to latest event
- Keyboard navigation (q=quit, f=filter, d=drill down)
- Color-coded significance levels
"""

import asyncio
from datetime import datetime
from typing import Optional

from textual.app import ComposeResult
from textual.widgets import DataTable, Footer, Header
from textual.containers import Container
from textual import work
from textual.message import Message
from textual.reactive import reactive

from ..rpc.client import RPCClient, RPCError


class LiveEventView(Container):
    """Live event streaming view with real-time updates

    Polls daemon every 100ms for new events and updates table.
    """

    # Reactive attribute for update control
    auto_update = reactive(True)

    def __init__(self, rpc_client: RPCClient):
        super().__init__()
        self.rpc_client = rpc_client
        self.last_event_id = 0
        self.update_interval = 0.1  # 100ms polling

    def compose(self) -> ComposeResult:
        """Create child widgets"""
        yield DataTable(id="events_table")

    def on_mount(self) -> None:
        """Initialize table and start update worker"""
        table = self.query_one(DataTable)

        # Configure table
        table.cursor_type = "row"
        table.zebra_stripes = True

        # Add columns
        table.add_column("Event ID", key="id", width=10)
        table.add_column("Timestamp", key="timestamp", width=20)
        table.add_column("Type", key="type", width=20)
        table.add_column("Change", key="change", width=15)
        table.add_column("Summary", key="summary", width=60)
        table.add_column("Sig", key="significance", width=6)
        table.add_column("User Action", key="user_action", width=20)

        # Start update worker
        self.update_table_worker()

    @work(exclusive=True, group="update")
    async def update_table_worker(self) -> None:
        """Background worker to poll for new events

        Runs continuously, polling daemon every 100ms for new events.
        """
        while self.auto_update:
            try:
                # Query events newer than last seen
                response = self.rpc_client.query_events(last=50)  # Get recent 50 events
                events = response.get('events', [])

                # Filter to only new events
                new_events = [e for e in events if e['event_id'] > self.last_event_id]

                if new_events:
                    # Add new rows to table
                    table = self.query_one(DataTable)
                    for event in new_events:
                        self._add_event_row(table, event)
                        self.last_event_id = max(self.last_event_id, event['event_id'])

                    # Auto-scroll to bottom
                    if table.row_count > 0:
                        table.move_cursor(row=table.row_count - 1)

            except RPCError as e:
                # Daemon not responding - keep trying
                pass
            except ConnectionError:
                # Daemon disconnected - keep trying
                pass
            except Exception as e:
                self.log.error(f"Error in update worker: {e}")

            # Wait before next poll
            await asyncio.sleep(self.update_interval)

    def _add_event_row(self, table: DataTable, event: dict) -> None:
        """Add a single event row to the table"""
        # Format timestamp
        timestamp_ms = event.get('timestamp_ms', 0)
        dt = datetime.fromtimestamp(timestamp_ms / 1000)
        timestamp_str = dt.strftime("%H:%M:%S.%f")[:-3]  # HH:MM:SS.mmm

        # Extract fields
        event_id = str(event.get('event_id', ''))
        event_type = event.get('event_type', '')
        sway_change = event.get('sway_change', '')
        summary = event.get('summary', '')
        significance = event.get('significance_score', 0.0)

        # Format significance with color
        if significance >= 0.8:
            sig_str = "HIGH"
            sig_style = "bold red"
        elif significance >= 0.5:
            sig_str = "MED"
            sig_style = "bold yellow"
        else:
            sig_str = "LOW"
            sig_style = "dim"

        # User action correlation
        correlation = event.get('correlation', {})
        if correlation:
            action = correlation.get('action', '')
            confidence = correlation.get('confidence', 0.0)
            user_action_str = f"{action} ({confidence:.0%})"
        else:
            user_action_str = "-"

        # Add row
        table.add_row(
            event_id,
            timestamp_str,
            event_type,
            sway_change,
            summary,
            sig_str,
            user_action_str,
            key=event_id
        )

    def action_quit(self) -> None:
        """Quit the application"""
        self.app.exit()

    def action_filter(self) -> None:
        """Open filter dialog (TODO: Phase 5)"""
        self.app.notify("Filtering coming in Phase 5 (User Story 5)", severity="information")

    def action_drill_down(self) -> None:
        """Drill down into selected event - opens detailed diff view"""
        table = self.query_one(DataTable)
        if table.cursor_row is not None:
            # Get event ID from first column
            row_key = table.get_row_at(table.cursor_row)[0]  # Get event ID
            event_id = int(row_key)

            # Push DiffView screen
            from .diff_view import DiffView
            self.app.push_screen(DiffView(self.rpc_client, event_id))

    def on_unmount(self) -> None:
        """Cleanup when unmounting"""
        self.auto_update = False
