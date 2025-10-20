"""Base display class with Rich helpers.

Provides common functionality for all display modes using the Rich library.
"""

from abc import ABC, abstractmethod
from typing import Optional

from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from ..daemon_client import DaemonClient


class BaseDisplay(ABC):
    """Base class for all display modes."""

    def __init__(self, client: DaemonClient, console: Optional[Console] = None):
        """Initialize base display.

        Args:
            client: DaemonClient instance for daemon communication
            console: Optional Rich Console instance (created if not provided)
        """
        self.client = client
        self.console = console or Console()

    @abstractmethod
    async def run(self) -> None:
        """Run the display mode.

        This method should be implemented by each display mode.
        """
        pass

    def create_table(
        self,
        title: str,
        columns: list[tuple[str, str]],
        rows: list[list[str]],
        show_header: bool = True,
        show_lines: bool = False,
    ) -> Table:
        """Create a Rich table with consistent styling.

        Args:
            title: Table title
            columns: List of (name, justify) tuples for columns
            rows: List of row data (list of strings)
            show_header: Whether to show column headers
            show_lines: Whether to show lines between rows

        Returns:
            Configured Rich Table
        """
        table = Table(
            title=title,
            show_header=show_header,
            show_lines=show_lines,
            header_style="bold cyan",
            title_style="bold magenta",
        )

        # Add columns
        for name, justify in columns:
            table.add_column(name, justify=justify)

        # Add rows
        for row in rows:
            table.add_row(*row)

        return table

    def create_panel(
        self,
        content: str,
        title: str,
        border_style: str = "blue",
    ) -> Panel:
        """Create a Rich panel with consistent styling.

        Args:
            content: Panel content
            title: Panel title
            border_style: Border color style

        Returns:
            Configured Rich Panel
        """
        return Panel(
            content,
            title=title,
            border_style=border_style,
            padding=(1, 2),
        )

    def create_layout(self, *sections: tuple[str, int]) -> Layout:
        """Create a Rich layout with multiple sections.

        Args:
            sections: Tuples of (section_name, ratio) for layout sections

        Returns:
            Configured Rich Layout
        """
        layout = Layout()

        # Split layout into sections
        layout.split_column(
            *[Layout(name=name, ratio=ratio) for name, ratio in sections]
        )

        return layout

    def format_uptime(self, seconds: float) -> str:
        """Format uptime seconds into human-readable string.

        Args:
            seconds: Uptime in seconds

        Returns:
            Formatted string (e.g., "2h 34m 12s")
        """
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)

        if hours > 0:
            return f"{hours}h {minutes}m {secs}s"
        elif minutes > 0:
            return f"{minutes}m {secs}s"
        else:
            return f"{secs}s"

    def format_duration_ms(self, duration_ms: float) -> str:
        """Format duration in milliseconds.

        Args:
            duration_ms: Duration in milliseconds

        Returns:
            Formatted string with appropriate unit
        """
        if duration_ms < 1.0:
            return f"{duration_ms * 1000:.0f}µs"
        elif duration_ms < 1000:
            return f"{duration_ms:.1f}ms"
        else:
            return f"{duration_ms / 1000:.2f}s"

    def format_timestamp(self, timestamp: str, include_date: bool = False) -> str:
        """Format ISO timestamp for display.

        Args:
            timestamp: ISO format timestamp string
            include_date: Whether to include date in output

        Returns:
            Formatted timestamp string
        """
        from datetime import datetime

        dt = datetime.fromisoformat(timestamp)

        if include_date:
            return dt.strftime("%Y-%m-%d %H:%M:%S")
        else:
            return dt.strftime("%H:%M:%S")

    def colorize_status(self, status: str, is_error: bool = False) -> Text:
        """Colorize status text based on state.

        Args:
            status: Status text
            is_error: Whether this is an error status

        Returns:
            Colorized Rich Text object
        """
        if is_error:
            return Text(status, style="bold red")
        elif status.lower() in ["connected", "running", "active", "ok"]:
            return Text(status, style="bold green")
        elif status.lower() in ["connecting", "retrying", "pending"]:
            return Text(status, style="bold yellow")
        else:
            return Text(status, style="white")

    def colorize_project(self, project: Optional[str]) -> str:
        """Colorize project name for display.

        Args:
            project: Project name or None

        Returns:
            Formatted project string
        """
        if project is None:
            return "[dim](global)[/dim]"
        else:
            return f"[cyan]{project}[/cyan]"

    def truncate_string(self, text: str, max_length: int, suffix: str = "...") -> str:
        """Truncate string to maximum length.

        Args:
            text: String to truncate
            max_length: Maximum length
            suffix: Suffix to add if truncated

        Returns:
            Truncated string
        """
        if len(text) <= max_length:
            return text
        else:
            return text[: max_length - len(suffix)] + suffix

    def create_status_line(
        self,
        connected: bool,
        uptime_seconds: float,
        active_project: Optional[str],
        error_count: int,
    ) -> str:
        """Create a status line for display headers.

        Args:
            connected: Whether daemon is connected
            uptime_seconds: Daemon uptime in seconds
            active_project: Active project name
            error_count: Number of errors

        Returns:
            Formatted status line string
        """
        status = "Connected" if connected else "Disconnected"
        uptime = self.format_uptime(uptime_seconds)
        project = self.colorize_project(active_project)

        status_parts = [
            f"Status: {self.colorize_status(status).markup}",
            f"Uptime: {uptime}",
            f"Project: {project}",
        ]

        if error_count > 0:
            status_parts.append(f"[red]Errors: {error_count}[/red]")

        return " | ".join(status_parts)

    def print_error(self, message: str) -> None:
        """Print error message to console.

        Args:
            message: Error message to display
        """
        self.console.print(f"[bold red]Error:[/bold red] {message}")

    def print_info(self, message: str) -> None:
        """Print info message to console.

        Args:
            message: Info message to display
        """
        self.console.print(f"[cyan]ℹ[/cyan] {message}")

    def print_warning(self, message: str) -> None:
        """Print warning message to console.

        Args:
            message: Warning message to display
        """
        self.console.print(f"[yellow]⚠[/yellow] {message}")
