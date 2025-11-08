"""Detailed Diff View

Displays detailed tree diff with syntax-highlighted JSON and enriched context.

Features:
- Full field-level diff display with tree paths
- Enriched context (I3PM_* variables, project marks)
- Syntax highlighting with Rich
- Drilldown from live/history views

Updated: Fixed include_enrichment parameter error
"""

import json
from typing import Optional

from textual.app import ComposeResult
from textual.screen import Screen
from textual.containers import Container, Vertical, Horizontal, ScrollableContainer
from textual.widgets import Static, Button
from textual import on
from rich.syntax import Syntax
from rich.table import Table
from rich.panel import Panel
from rich.text import Text

from ..rpc.client import RPCClient


class DiffView(Screen):
    """
    Detailed diff inspection view.

    Displays:
    - Event metadata (ID, timestamp, type)
    - User action correlation
    - Detailed field-level changes with tree paths
    - Enriched context (I3PM_* env vars, project marks)
    - Syntax-highlighted JSON diff
    """

    def __init__(
        self,
        rpc_client: RPCClient,
        event_id: int
    ):
        """
        Initialize diff view.

        Args:
            rpc_client: RPC client for daemon communication
            event_id: Event ID to display
        """
        super().__init__()
        self.rpc_client = rpc_client
        self.event_id = event_id
        self.event_data = None

    def compose(self) -> ComposeResult:
        """Compose the diff view"""
        # Header with navigation
        with Horizontal(id="diff-header"):
            yield Static(f"Event #{self.event_id}", id="diff-title")
            yield Button("← Back", id="back-button")

        # Status line
        yield Static("Loading...", id="diff-status")

        # Scrollable content area
        with ScrollableContainer(id="diff-content"):
            yield Static("", id="event-metadata")
            yield Static("", id="correlation-info")
            yield Static("", id="diff-details")
            yield Static("", id="enrichment-data")

    async def on_mount(self) -> None:
        """Load event data when mounted"""
        await self._load_event()

    @on(Button.Pressed, "#back-button")
    async def handle_back(self, event: Button.Pressed) -> None:
        """Go back to previous view"""
        self.app.pop_screen()

    async def _load_event(self) -> None:
        """Load event from daemon via RPC"""
        status = self.query_one("#diff-status", Static)

        try:
            status.update("Loading event details...")

            # Get event with detailed diff (enrichment is included by default)
            response = self.rpc_client.get_event(
                event_id=self.event_id,
                include_diff=True
            )
            self.event_data = response

            # Update UI sections
            self._update_metadata()
            self._update_correlation()
            self._update_diff_details()
            self._update_enrichment()

            status.update("✓ Event loaded")

        except Exception as e:
            status.update(f"Error: {e}")

    def _update_metadata(self) -> None:
        """Update event metadata section"""
        if not self.event_data:
            return

        event = self.event_data

        # Create metadata table
        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Field", style="cyan")
        table.add_column("Value")

        table.add_row("Event ID", str(event['event_id']))

        # Format timestamp
        from datetime import datetime
        timestamp_ms = event['timestamp_ms']
        timestamp_str = datetime.fromtimestamp(timestamp_ms / 1000).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        table.add_row("Timestamp", timestamp_str)

        table.add_row("Event Type", event['event_type'])
        table.add_row("Sway Change", event.get('sway_change', 'unknown'))

        if 'container_id' in event and event['container_id']:
            table.add_row("Container ID", str(event['container_id']))

        # Diff summary
        if 'diff' in event:
            diff = event['diff']
            table.add_row("Changes", f"{diff['total_changes']} fields")
            table.add_row("Significance", f"{diff['significance_score']:.2f} ({diff['significance_level']})")
            table.add_row("Computation Time", f"{diff['computation_time_ms']:.2f}ms")

        # Render as panel
        panel = Panel(table, title="[bold]Event Metadata[/bold]", border_style="blue")

        metadata_widget = self.query_one("#event-metadata", Static)
        metadata_widget.update(panel)

    def _update_correlation(self) -> None:
        """Update correlation info section"""
        if not self.event_data or not self.event_data.get('correlations'):
            correlation_widget = self.query_one("#correlation-info", Static)
            correlation_widget.update(Panel(
                "No user action correlation",
                title="[bold]User Action Correlation[/bold]",
                border_style="yellow"
            ))
            return

        correlations = self.event_data['correlations']
        top_correlation = correlations[0]  # Highest confidence

        # Create correlation table
        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Field", style="cyan")
        table.add_column("Value")

        action = top_correlation['action']
        table.add_row("Action Type", action['action_type'])
        table.add_row("Command", action.get('binding_command', 'N/A'))
        table.add_row("Time Delta", f"{top_correlation['time_delta_ms']}ms")

        confidence = top_correlation['confidence']
        confidence_level = top_correlation.get('confidence_level', 'unknown')
        confidence_emoji = self._get_confidence_emoji(confidence)
        table.add_row("Confidence", f"{confidence_emoji} {confidence:.2%} ({confidence_level})")

        table.add_row("Reasoning", top_correlation.get('reasoning', 'N/A'))

        # Show additional correlations if present
        if len(correlations) > 1:
            table.add_row("", "")
            table.add_row("[dim]Other Correlations[/dim]", f"{len(correlations) - 1} lower confidence")

        # Render as panel
        panel = Panel(table, title="[bold]User Action Correlation[/bold]", border_style="green")

        correlation_widget = self.query_one("#correlation-info", Static)
        correlation_widget.update(panel)

    def _update_diff_details(self) -> None:
        """Update diff details section with field-level changes"""
        if not self.event_data or 'diff' not in self.event_data:
            diff_widget = self.query_one("#diff-details", Static)
            diff_widget.update("No diff data available")
            return

        diff = self.event_data['diff']
        node_changes = diff.get('node_changes', [])

        if not node_changes:
            diff_widget = self.query_one("#diff-details", Static)
            diff_widget.update("No changes detected")
            return

        # Build detailed diff display
        content = Text()
        content.append("Field-Level Changes\n", style="bold underline")
        content.append("\n")

        for node_change in node_changes:
            # Node header
            node_path = node_change['node_path']
            node_type = node_change['node_type']
            change_type = node_change['change_type']

            content.append(f"▶ {node_path}\n", style="bold cyan")
            content.append(f"  Type: {node_type} | Change: {change_type}\n", style="dim")

            # Field changes
            for field_change in node_change['field_changes']:
                field_path = field_change['field_path']
                old_value = field_change.get('old_value')
                new_value = field_change.get('new_value')
                fc_type = field_change['change_type']
                significance = field_change['significance_score']

                content.append(f"  • {field_path}\n", style="yellow")

                if fc_type == 'MODIFIED':
                    content.append(f"    Old: {old_value}\n", style="red")
                    content.append(f"    New: {new_value}\n", style="green")
                elif fc_type == 'ADDED':
                    content.append(f"    Added: {new_value}\n", style="green")
                elif fc_type == 'REMOVED':
                    content.append(f"    Removed: {old_value}\n", style="red")

                content.append(f"    Significance: {significance:.2f}\n", style="dim")

            content.append("\n")

        # Render as panel
        panel = Panel(content, title="[bold]Detailed Diff[/bold]", border_style="magenta")

        diff_widget = self.query_one("#diff-details", Static)
        diff_widget.update(panel)

    def _update_enrichment(self) -> None:
        """Update enrichment data section (I3PM_* variables, marks)"""
        if not self.event_data or 'enrichment' not in self.event_data:
            enrichment_widget = self.query_one("#enrichment-data", Static)
            enrichment_widget.update("")
            return

        enrichment = self.event_data['enrichment']

        if not enrichment:
            enrichment_widget = self.query_one("#enrichment-data", Static)
            enrichment_widget.update(Panel(
                "No enriched context available",
                title="[bold]Enriched Context[/bold]",
                border_style="blue"
            ))
            return

        # Build enrichment display
        content = Text()

        for window_id, context in enrichment.items():
            content.append(f"Window {window_id}\n", style="bold cyan")

            # Process info
            if context.get('pid'):
                content.append(f"  PID: {context['pid']}\n", style="dim")

            # I3PM variables
            i3pm_vars = []
            if context.get('i3pm_app_id'):
                i3pm_vars.append(f"APP_ID={context['i3pm_app_id']}")
            if context.get('i3pm_app_name'):
                i3pm_vars.append(f"APP_NAME={context['i3pm_app_name']}")
            if context.get('i3pm_project_name'):
                i3pm_vars.append(f"PROJECT={context['i3pm_project_name']}")
            if context.get('i3pm_scope'):
                i3pm_vars.append(f"SCOPE={context['i3pm_scope']}")

            if i3pm_vars:
                content.append("  I3PM Variables:\n", style="yellow")
                for var in i3pm_vars:
                    content.append(f"    • {var}\n", style="green")

            # Marks
            project_marks = context.get('project_marks', [])
            app_marks = context.get('app_marks', [])

            if project_marks:
                content.append("  Project Marks:\n", style="yellow")
                for mark in project_marks:
                    content.append(f"    • {mark}\n", style="blue")

            if app_marks:
                content.append("  App Marks:\n", style="yellow")
                for mark in app_marks:
                    content.append(f"    • {mark}\n", style="blue")

            # Launch context
            if context.get('launch_timestamp_ms'):
                from datetime import datetime
                launch_time = datetime.fromtimestamp(context['launch_timestamp_ms'] / 1000).strftime('%H:%M:%S')
                content.append(f"  Launched: {launch_time}\n", style="dim")

            if context.get('launch_action'):
                content.append(f"  Launch Action: {context['launch_action']}\n", style="dim")

            content.append("\n")

        # Render as panel
        panel = Panel(content, title="[bold]Enriched Context (I3PM)[/bold]", border_style="blue")

        enrichment_widget = self.query_one("#enrichment-data", Static)
        enrichment_widget.update(panel)

    def _get_confidence_emoji(self, confidence: float) -> str:
        """Get emoji for confidence level"""
        if confidence >= 0.9:
            return "🟢"
        elif confidence >= 0.7:
            return "🟡"
        elif confidence >= 0.5:
            return "🟠"
        elif confidence >= 0.3:
            return "🔴"
        else:
            return "⚫"
