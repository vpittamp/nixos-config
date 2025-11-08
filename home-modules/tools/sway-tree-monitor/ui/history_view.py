"""Historical Event Query View

Displays historical tree change events with filtering and correlation details.

Features:
- Scrollable table of past events
- Time range filtering (--since, --last)
- Event type filtering (--filter)
- Correlation display with confidence levels
- Drill-down to detailed diff view
"""

import asyncio
from typing import Optional, List
from datetime import datetime

from textual.app import ComposeResult
from textual.containers import Container, Vertical, Horizontal
from textual.widgets import DataTable, Static, Input, Button
from textual import on

from ..rpc.client import RPCClient


class HistoryView(Container):
    """
    Historical event query view with filtering.

    Displays events from the circular buffer with:
    - Event ID, timestamp, type
    - Change summary and significance
    - User action correlation (if available)
    - Drill-down to detailed diff

    User can filter by:
    - Time range (since_ms, until_ms)
    - Event type (window::*, workspace::*)
    - Last N events
    """

    def __init__(
        self,
        rpc_client: RPCClient,
        since_ms: Optional[int] = None,
        until_ms: Optional[int] = None,
        last: Optional[int] = None,
        event_filter: Optional[str] = None
    ):
        """
        Initialize history view.

        Args:
            rpc_client: RPC client for daemon communication
            since_ms: Show events after this timestamp
            until_ms: Show events before this timestamp
            last: Show only last N events
            event_filter: Filter by event type pattern
        """
        super().__init__()
        self.rpc_client = rpc_client
        self.since_ms = since_ms
        self.until_ms = until_ms
        self.last = last
        self.event_filter = event_filter

    def compose(self) -> ComposeResult:
        """Compose the history view"""
        # Filter controls
        with Horizontal(id="filter-bar"):
            yield Static("Filter:", classes="label")
            yield Input(
                placeholder="Event type (e.g., window::new)",
                value=self.event_filter or "",
                id="filter-input"
            )
            yield Button("Apply", id="apply-filter")
            yield Button("Clear", id="clear-filter")
            yield Button("Refresh", id="refresh-button")

        # Status line
        yield Static("Loading...", id="status-line")

        # Event table
        table = DataTable(id="event-table")
        table.cursor_type = "row"
        table.zebra_stripes = True
        table.add_columns(
            "ID",
            "Timestamp",
            "Type",
            "Changes",
            "Triggered By",
            "Confidence"
        )
        yield table

        # Legend
        with Horizontal(id="legend"):
            yield Static("Confidence: 🟢 Very Likely | 🟡 Likely | 🟠 Possible | 🔴 Unlikely | ⚫ Very Unlikely", classes="legend-text")

    async def on_mount(self) -> None:
        """Load initial data when mounted"""
        await self._load_events()

    @on(Button.Pressed, "#apply-filter")
    async def handle_apply_filter(self, event: Button.Pressed) -> None:
        """Apply filter from input box"""
        filter_input = self.query_one("#filter-input", Input)
        self.event_filter = filter_input.value if filter_input.value else None
        await self._load_events()

    @on(Button.Pressed, "#clear-filter")
    async def handle_clear_filter(self, event: Button.Pressed) -> None:
        """Clear filter"""
        filter_input = self.query_one("#filter-input", Input)
        filter_input.value = ""
        self.event_filter = None
        await self._load_events()

    @on(Button.Pressed, "#refresh-button")
    async def handle_refresh(self, event: Button.Pressed) -> None:
        """Refresh event data"""
        await self._load_events()

    def action_drill_down(self) -> None:
        """Drill down into selected event - opens detailed diff view"""
        table = self.query_one("#event-table", DataTable)
        if table.cursor_row is not None:
            # Get event ID from first column
            row_data = table.get_row_at(table.cursor_row)
            event_id = int(row_data[0])  # First column is event ID

            # Push DiffView screen
            from .diff_view import DiffView
            self.app.push_screen(DiffView(self.rpc_client, event_id))

    async def _load_events(self) -> None:
        """Load events from daemon via RPC"""
        status = self.query_one("#status-line", Static)
        table = self.query_one("#event-table", DataTable)

        try:
            status.update("Loading events...")

            # Query events with filters
            params = {}
            if self.since_ms:
                params['since_ms'] = self.since_ms
            if self.until_ms:
                params['until_ms'] = self.until_ms
            if self.last:
                params['last'] = self.last
            if self.event_filter:
                params['event_type'] = self.event_filter

            response = self.rpc_client.query_events(**params)
            events = response.get('events', [])

            # Clear existing rows
            table.clear()

            if not events:
                status.update("No events found")
                return

            # Add rows
            for event in events:
                # Format timestamp
                timestamp_ms = event.get('timestamp_ms', 0)
                timestamp_str = datetime.fromtimestamp(timestamp_ms / 1000).strftime('%H:%M:%S.%f')[:-3]

                # Get event info
                event_id = event.get('event_id', 0)
                event_type = event.get('event_type', 'unknown')

                # Get diff info
                diff = event.get('diff', {})
                total_changes = diff.get('total_changes', 0)
                significance = diff.get('significance_level', 'low')

                # Format changes
                changes_str = f"{total_changes} changes ({significance})"

                # Get correlation info
                correlations = event.get('correlations', [])
                if correlations:
                    top_correlation = correlations[0]
                    action = top_correlation.get('action', {})
                    confidence = top_correlation.get('confidence', 0.0)
                    binding_command = action.get('binding_command', 'unknown')

                    # Format confidence with emoji
                    confidence_str, confidence_emoji = self._format_confidence(confidence)
                    triggered_by = f"{binding_command[:30]}"  # Truncate long commands
                else:
                    triggered_by = "(no correlation)"
                    confidence_str = "—"
                    confidence_emoji = ""

                # Add row
                table.add_row(
                    str(event_id),
                    timestamp_str,
                    event_type,
                    changes_str,
                    triggered_by,
                    f"{confidence_emoji} {confidence_str}"
                )

            # Update status
            status.update(f"Showing {len(events)} events")

        except Exception as e:
            status.update(f"Error: {e}")

    def _format_confidence(self, confidence: float) -> tuple[str, str]:
        """
        Format confidence score with label and emoji.

        Returns:
            Tuple of (label, emoji)
        """
        if confidence >= 0.9:
            return "very likely", "🟢"
        elif confidence >= 0.7:
            return "likely", "🟡"
        elif confidence >= 0.5:
            return "possible", "🟠"
        elif confidence >= 0.3:
            return "unlikely", "🔴"
        else:
            return "very unlikely", "⚫"
