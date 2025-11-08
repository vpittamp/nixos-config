"""Statistical Summary View

Displays performance statistics and daemon health metrics.

Features:
- Buffer statistics (size, overflow events)
- Performance metrics (diff computation times, CPU, memory)
- Event type distribution
- Correlation statistics
- Real-time updates
"""

from typing import Optional

from textual.app import ComposeResult
from textual.containers import Container, Vertical, Horizontal
from textual.widgets import Static, Button
from textual import on
from rich.table import Table
from rich.panel import Panel
from rich.progress import Progress, BarColumn, TextColumn
from rich.text import Text

from ..rpc.client import RPCClient


class StatsView(Container):
    """
    Statistical summary view with performance metrics.

    Displays:
    - Daemon status (uptime, version, running state)
    - Performance metrics (CPU%, memory MB, diff times)
    - Buffer statistics (size, capacity, overflow)
    - Event type distribution
    - Correlation statistics
    """

    def __init__(
        self,
        rpc_client: RPCClient,
        since_ms: Optional[int] = None
    ):
        """
        Initialize stats view.

        Args:
            rpc_client: RPC client for daemon communication
            since_ms: Analyze events since this timestamp
        """
        super().__init__()
        self.rpc_client = rpc_client
        self.since_ms = since_ms

    def compose(self) -> ComposeResult:
        """Compose the stats view"""
        # Header with controls
        with Horizontal(id="stats-header"):
            yield Static("Performance Statistics", id="stats-title")
            yield Button("Refresh", id="refresh-button")
            yield Button("Clear Stats", id="clear-stats-button")

        # Status line
        yield Static("Loading...", id="stats-status")

        # Stats panels
        with Vertical(id="stats-panels"):
            yield Static("", id="daemon-status-panel")
            yield Static("", id="performance-panel")
            yield Static("", id="buffer-panel")
            yield Static("", id="events-panel")
            yield Static("", id="correlation-panel")

    async def on_mount(self) -> None:
        """Load statistics when mounted"""
        await self._load_stats()

    @on(Button.Pressed, "#refresh-button")
    async def handle_refresh(self, event: Button.Pressed) -> None:
        """Refresh statistics"""
        await self._load_stats()

    @on(Button.Pressed, "#clear-stats-button")
    async def handle_clear_stats(self, event: Button.Pressed) -> None:
        """Clear statistics (reset since timestamp)"""
        self.since_ms = None
        await self._load_stats()

    async def _load_stats(self) -> None:
        """Load statistics from daemon via RPC"""
        status_widget = self.query_one("#stats-status", Static)

        try:
            status_widget.update("Loading statistics...")

            # Get daemon status and statistics
            daemon_status = self.rpc_client.get_daemon_status()
            stats = self.rpc_client.get_statistics(since_ms=self.since_ms)

            # Update panels
            self._update_daemon_status(daemon_status)
            self._update_performance(daemon_status, stats)
            self._update_buffer(daemon_status)
            self._update_events(stats)
            self._update_correlation(stats)

            status_widget.update("✓ Statistics loaded")

        except Exception as e:
            status_widget.update(f"Error: {e}")

    def _update_daemon_status(self, status: dict) -> None:
        """Update daemon status panel"""
        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Field", style="cyan")
        table.add_column("Value")

        table.add_row("Status", "🟢 Running" if status.get('running') else "🔴 Stopped")
        table.add_row("Version", status.get('version', 'unknown'))

        # Format uptime
        uptime_seconds = status.get('uptime_seconds', 0)
        hours = uptime_seconds // 3600
        minutes = (uptime_seconds % 3600) // 60
        seconds = uptime_seconds % 60
        table.add_row("Uptime", f"{hours}h {minutes}m {seconds}s")

        # Render as panel
        panel = Panel(table, title="[bold]Daemon Status[/bold]", border_style="green")
        self.query_one("#daemon-status-panel", Static).update(panel)

    def _update_performance(self, status: dict, stats: dict) -> None:
        """Update performance metrics panel"""
        perf = status.get('performance', {})
        stats_perf = stats.get('performance', {})

        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Metric", style="cyan")
        table.add_column("Value")
        table.add_column("Status")

        # Memory usage
        memory_mb = perf.get('memory_mb', 0)
        memory_status = "✓" if memory_mb < 25 else "⚠"
        memory_color = "green" if memory_mb < 25 else "yellow"
        table.add_row(
            "Memory Usage",
            f"{memory_mb:.1f} MB",
            f"[{memory_color}]{memory_status} Target: <25MB[/{memory_color}]"
        )

        # CPU usage
        cpu_percent = perf.get('cpu_percent', 0)
        cpu_status = "✓" if cpu_percent < 2.0 else "⚠"
        cpu_color = "green" if cpu_percent < 2.0 else "yellow"
        table.add_row(
            "CPU Usage (avg)",
            f"{cpu_percent:.2f}%",
            f"[{cpu_color}]{cpu_status} Target: <2%[/{cpu_color}]"
        )

        # Diff computation times
        if stats_perf:
            avg_diff = stats_perf.get('avg_diff_computation_ms', 0)
            p95_diff = stats_perf.get('p95_diff_computation_ms', 0)
            p99_diff = stats_perf.get('p99_diff_computation_ms', 0)

            diff_status = "✓" if p95_diff < 10 else "⚠"
            diff_color = "green" if p95_diff < 10 else "yellow"

            table.add_row(
                "Diff Time (avg)",
                f"{avg_diff:.2f} ms",
                ""
            )
            table.add_row(
                "Diff Time (p95)",
                f"{p95_diff:.2f} ms",
                f"[{diff_color}]{diff_status} Target: <10ms[/{diff_color}]"
            )
            table.add_row(
                "Diff Time (p99)",
                f"{p99_diff:.2f} ms",
                ""
            )

        # Render as panel
        panel = Panel(table, title="[bold]Performance Metrics[/bold]", border_style="blue")
        self.query_one("#performance-panel", Static).update(panel)

    def _update_buffer(self, status: dict) -> None:
        """Update buffer statistics panel"""
        buffer = status.get('buffer', {})

        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Field", style="cyan")
        table.add_column("Value")

        # Buffer size
        size = buffer.get('size', 0)
        max_size = buffer.get('max_size', 500)
        is_full = buffer.get('is_full', False)

        usage_percent = (size / max_size * 100) if max_size > 0 else 0

        table.add_row("Event Count", f"{size} / {max_size}")
        table.add_row("Usage", f"{usage_percent:.1f}%")
        table.add_row("Status", "🟡 Full" if is_full else "🟢 Space Available")

        # Overflow events
        if 'overflow_count' in buffer:
            table.add_row("Overflow Events", str(buffer['overflow_count']))

        # Render as panel
        panel = Panel(table, title="[bold]Circular Buffer[/bold]", border_style="magenta")
        self.query_one("#buffer-panel", Static).update(panel)

    def _update_events(self, stats: dict) -> None:
        """Update event type distribution panel"""
        event_dist = stats.get('event_type_distribution', {})

        if not event_dist:
            panel = Panel("No events recorded", title="[bold]Event Distribution[/bold]", border_style="yellow")
            self.query_one("#events-panel", Static).update(panel)
            return

        # Sort by count descending
        sorted_events = sorted(event_dist.items(), key=lambda x: x[1], reverse=True)

        table = Table(box=None, padding=(0, 1))
        table.add_column("Event Type", style="cyan")
        table.add_column("Count", justify="right")
        table.add_column("Percentage", justify="right")

        total = sum(event_dist.values())

        for event_type, count in sorted_events[:10]:  # Top 10
            percentage = (count / total * 100) if total > 0 else 0
            table.add_row(event_type, str(count), f"{percentage:.1f}%")

        if len(sorted_events) > 10:
            remaining = sum(count for _, count in sorted_events[10:])
            percentage = (remaining / total * 100) if total > 0 else 0
            table.add_row("[dim]Other[/dim]", f"[dim]{remaining}[/dim]", f"[dim]{percentage:.1f}%[/dim]")

        # Render as panel
        panel = Panel(table, title="[bold]Event Distribution[/bold]", border_style="yellow")
        self.query_one("#events-panel", Static).update(panel)

    def _update_correlation(self, stats: dict) -> None:
        """Update correlation statistics panel"""
        corr = stats.get('correlation', {})

        table = Table(show_header=False, box=None, padding=(0, 1))
        table.add_column("Metric", style="cyan")
        table.add_column("Value")

        user_initiated = corr.get('user_initiated_count', 0)
        high_confidence = corr.get('high_confidence_count', 0)
        no_correlation = corr.get('no_correlation_count', 0)

        total = user_initiated + no_correlation

        table.add_row("User-Initiated", str(user_initiated))
        table.add_row("High Confidence (≥90%)", str(high_confidence))
        table.add_row("No Correlation", str(no_correlation))

        if total > 0:
            user_percent = (user_initiated / total * 100)
            table.add_row("Correlation Rate", f"{user_percent:.1f}%")

        # Render as panel
        panel = Panel(table, title="[bold]User Action Correlation[/bold]", border_style="green")
        self.query_one("#correlation-panel", Static).update(panel)
