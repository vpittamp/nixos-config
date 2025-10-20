"""Live state display mode.

Real-time monitoring of daemon status, active project, windows, and monitors.
"""

import asyncio
from typing import Any, Dict, Optional

from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from ..daemon_client import DaemonClient
from ..models import MonitorState, WindowEntry, MonitorEntry, OutputState, WorkspaceAssignment
from ..validators import validate_workspace_assignments, validate_output_configuration
from .base import BaseDisplay


class LiveDisplay(BaseDisplay):
    """Live real-time display of system state."""

    def __init__(self, client: DaemonClient, console: Optional[Console] = None):
        """Initialize live display.

        Args:
            client: DaemonClient instance for daemon communication
            console: Optional Rich Console instance
        """
        super().__init__(client, console)
        self.refresh_rate = 4  # Hz (250ms refresh)
        self.running = True

    async def run(self) -> None:
        """Run live display with auto-refresh.

        This is the main entry point for the live display mode.
        It continuously queries the daemon and updates the display.
        """
        # Check if daemon is running
        try:
            await self._test_connection()
        except ConnectionError as e:
            self._show_daemon_not_running_error(str(e))
            return

        # Run live display loop
        with Live(
            self._create_layout(),
            console=self.console,
            refresh_per_second=self.refresh_rate,
            screen=True,
        ) as live:
            try:
                while self.running:
                    # Fetch fresh data from daemon
                    layout = await self._fetch_and_render()
                    live.update(layout)

                    # Sleep until next refresh
                    await asyncio.sleep(1.0 / self.refresh_rate)

            except KeyboardInterrupt:
                self.console.print("\n[yellow]Live display stopped by user[/yellow]")
            except ConnectionError as e:
                self.console.print(f"\n[red]Lost connection to daemon: {e}[/red]")
            except Exception as e:
                self.console.print(f"\n[red]Error in live display: {e}[/red]")
                raise

    async def _test_connection(self) -> None:
        """Test daemon connection before starting live display.

        Raises:
            ConnectionError: If daemon is not reachable
        """
        try:
            await self.client.get_status()
        except Exception as e:
            raise ConnectionError(f"Cannot connect to daemon: {e}")

    def _show_daemon_not_running_error(self, error_msg: str) -> None:
        """Display daemon not running error state.

        Args:
            error_msg: Error message from connection attempt
        """
        self.console.print(Panel(
            Text.from_markup(
                f"[bold red]Daemon Not Running[/bold red]\n\n"
                f"Failed to connect to i3 project daemon.\n\n"
                f"[dim]Error: {error_msg}[/dim]\n\n"
                f"[yellow]Troubleshooting:[/yellow]\n"
                f"  1. Check daemon status:\n"
                f"     [cyan]systemctl --user status i3-project-event-listener[/cyan]\n\n"
                f"  2. Check daemon logs:\n"
                f"     [cyan]journalctl --user -u i3-project-event-listener -n 50[/cyan]\n\n"
                f"  3. Restart daemon:\n"
                f"     [cyan]systemctl --user restart i3-project-event-listener[/cyan]\n\n"
                f"  4. Check socket exists:\n"
                f"     [cyan]ls -la $XDG_RUNTIME_DIR/i3-project-daemon/[/cyan]"
            ),
            title="i3 Project Monitor - Error",
            border_style="red",
            padding=(1, 2),
        ))

    def _create_layout(self) -> Layout:
        """Create initial layout structure (Feature 018: T012).

        Returns:
            Rich Layout with 6 panels (added outputs and workspaces)
        """
        layout = Layout()
        layout.split_column(
            Layout(name="status", ratio=1),
            Layout(name="project", ratio=1),
            Layout(name="windows", ratio=3),
            Layout(name="outputs", ratio=2),  # NEW: i3 outputs panel
            Layout(name="workspaces", ratio=2),  # NEW: i3 workspaces panel
            Layout(name="monitors", ratio=1),  # Monitor tool clients (reduced ratio)
        )
        return layout

    async def _fetch_and_render(self) -> Layout:
        """Fetch data from daemon and i3, validate, and render complete layout (Feature 018: T013).

        Returns:
            Rendered Rich Layout
        """
        # Fetch daemon data sequentially (socket can only handle one request at a time)
        status_data = await self.client.get_status()
        windows_data = await self.client.get_windows()
        monitors_data = await self.client.list_monitors()

        # Fetch i3 IPC data directly (Feature 018: T013)
        try:
            outputs = await self.client.get_i3_outputs()
            workspaces = await self.client.get_i3_workspaces()

            # Validate outputs and workspaces (Feature 018: T013)
            output_validation = validate_output_configuration(outputs)
            workspace_validation = validate_workspace_assignments(workspaces, outputs)
        except Exception as e:
            # If i3 query fails, show error in panels
            outputs = []
            workspaces = []
            output_validation = None
            workspace_validation = None

        # Create layout
        layout = self._create_layout()

        # Render panels
        layout["status"].update(self._render_connection_status(status_data))
        layout["project"].update(self._render_active_project(status_data))
        layout["windows"].update(self._render_windows_table(windows_data))
        layout["outputs"].update(self._render_outputs_panel(outputs, output_validation))
        layout["workspaces"].update(self._render_workspaces_panel(workspaces, workspace_validation))
        layout["monitors"].update(self._render_monitors_table(monitors_data))

        return layout

    def _render_connection_status(self, status: Dict[str, Any]) -> Panel:
        """Render connection status panel.

        Args:
            status: Status data from daemon

        Returns:
            Rich Panel with connection info
        """
        uptime_seconds = status.get("uptime_seconds", 0.0)
        events_processed = status.get("event_count", 0)  # daemon returns "event_count"
        error_count = status.get("error_count", 0)
        is_connected = status.get("connected", False)  # daemon returns "connected", not "is_connected"

        # Format uptime
        uptime_str = self.format_uptime(uptime_seconds)

        # Build status text
        conn_status = self.colorize_status("Connected" if is_connected else "Disconnected")

        status_text = Text.assemble(
            ("Status: ", "bold white"),
            conn_status,
            ("\nUptime: ", "bold white"),
            (uptime_str, "cyan"),
            ("\nEvents Processed: ", "bold white"),
            (str(events_processed), "green"),
        )

        if error_count > 0:
            status_text.append("\nErrors: ", "bold white")
            status_text.append(str(error_count), "red")

        return Panel(
            status_text,
            title="[bold cyan]Daemon Status[/bold cyan]",
            border_style="cyan",
            padding=(0, 1),
        )

    def _render_active_project(self, status: Dict[str, Any]) -> Panel:
        """Render active project panel.

        Args:
            status: Status data from daemon

        Returns:
            Rich Panel with active project info
        """
        active_project = status.get("active_project")
        window_count = status.get("window_count", 0)  # daemon returns "window_count"
        workspace_count = status.get("workspace_count", 0)

        # Format project name
        if active_project:
            project_text = Text.assemble(
                ("Project: ", "bold white"),
                (active_project, "bold cyan"),
            )
            border_style = "cyan"
        else:
            project_text = Text.assemble(
                ("Mode: ", "bold white"),
                ("Global (no active project)", "dim"),
            )
            border_style = "dim"

        # Add window tracking stats
        project_text.append("\n")
        project_text.append("Tracked Windows: ", "bold white")
        project_text.append(f"{window_count}", "green")
        project_text.append("\n")
        project_text.append("Workspaces: ", "bold white")
        project_text.append(f"{workspace_count}", "cyan")

        return Panel(
            project_text,
            title="[bold magenta]Active Project[/bold magenta]",
            border_style=border_style,
            padding=(0, 1),
        )

    def _render_windows_table(self, windows_data: Dict[str, Any]) -> Panel:
        """Render windows table.

        Args:
            windows_data: Windows data from daemon

        Returns:
            Rich Panel with windows table
        """
        windows = windows_data.get("windows", [])

        # Create table
        table = Table(
            show_header=True,
            header_style="bold cyan",
            border_style="blue",
            show_lines=False,
        )

        table.add_column("ID", justify="right", style="dim", width=8)
        table.add_column("Class", justify="left", style="cyan", width=15)
        table.add_column("Title", justify="left", style="white", no_wrap=False)
        table.add_column("Project", justify="left", style="magenta", width=12)
        table.add_column("Workspace", justify="center", style="yellow", width=10)

        # Add rows
        if not windows:
            table.add_row("—", "—", "[dim]No windows tracked[/dim]", "—", "—")
        else:
            for window in windows:
                window_id = str(window.get("window_id", "?"))
                window_class = self.truncate_string(window.get("window_class", "?"), 15)
                window_title = self.truncate_string(window.get("window_title", "?"), 50)
                project = window.get("project") or "[dim](global)[/dim]"
                workspace = window.get("workspace", "?")
                focused = window.get("focused", False)

                # Highlight focused window
                if focused:
                    window_title = f"[bold]{window_title}[/bold]"

                table.add_row(window_id, window_class, window_title, project, workspace)

        return Panel(
            table,
            title=f"[bold green]Windows[/bold green] ({len(windows)} total)",
            border_style="green",
            padding=(0, 1),
        )

    def _render_monitors_table(self, monitors_data: Dict[str, Any]) -> Panel:
        """Render monitors table.

        Args:
            monitors_data: Monitors data from daemon

        Returns:
            Rich Panel with monitors table
        """
        monitors = monitors_data.get("monitors", [])

        # Create table
        table = Table(
            show_header=True,
            header_style="bold cyan",
            border_style="blue",
            show_lines=False,
        )

        table.add_column("Monitor", justify="left", style="cyan", width=12)
        table.add_column("Resolution", justify="left", style="white", width=12)
        table.add_column("Workspaces", justify="left", style="yellow", width=20)
        table.add_column("Primary", justify="center", style="green", width=8)
        table.add_column("Active", justify="center", style="magenta", width=8)

        # Add rows
        if not monitors:
            table.add_row("—", "—", "[dim]No monitors detected[/dim]", "—", "—")
        else:
            for monitor in monitors:
                name = monitor.get("name", "?")
                width = monitor.get("width", 0)
                height = monitor.get("height", 0)
                resolution = f"{width}×{height}"
                workspaces = ", ".join(str(ws) for ws in monitor.get("assigned_workspaces", []))
                primary = "✓" if monitor.get("primary", False) else "—"
                active_ws = str(monitor.get("active_workspace", "—"))

                table.add_row(name, resolution, workspaces, primary, active_ws)

        return Panel(
            table,
            title=f"[bold blue]Monitor Clients[/bold blue] ({len(monitors)} connected)",
            border_style="blue",
            padding=(0, 1),
        )

    def _render_outputs_panel(
        self,
        outputs: list[OutputState],
        validation: Optional[Any] = None
    ) -> Panel:
        """Render i3 outputs panel (Feature 018: T010).

        Args:
            outputs: List of OutputState objects from i3 GET_OUTPUTS
            validation: Output validation result

        Returns:
            Rich Panel with outputs table
        """
        # Create table
        table = Table(
            show_header=True,
            header_style="bold cyan",
            border_style="blue",
            show_lines=False,
        )

        table.add_column("Output", justify="left", style="cyan", width=12)
        table.add_column("Resolution", justify="left", style="white", width=14)
        table.add_column("Position", justify="left", style="dim", width=12)
        table.add_column("Primary", justify="center", style="green", width=8)
        table.add_column("Active", justify="center", style="magenta", width=8)

        # Add rows
        if not outputs:
            table.add_row("—", "—", "—", "—", "[red]No outputs[/red]")
        else:
            for output in outputs:
                name = output.name
                resolution = f"{output.width}×{output.height}"
                position = f"({output.x},{output.y})"
                primary = "✓" if output.primary else "—"
                active = "[green]✓[/green]" if output.active else "[dim]—[/dim]"

                # Highlight primary output
                if output.primary:
                    name = f"[bold]{name}[/bold]"

                table.add_row(name, resolution, position, primary, active)

        # Determine border style based on validation
        border_style = "green"
        title_suffix = ""
        if validation:
            if not validation.valid:
                border_style = "red"
                title_suffix = " [red]⚠[/red]"
            elif validation.warnings:
                border_style = "yellow"
                title_suffix = " [yellow]⚠[/yellow]"

        return Panel(
            table,
            title=f"[bold cyan]i3 Outputs[/bold cyan] ({len(outputs)} outputs){title_suffix}",
            border_style=border_style,
            padding=(0, 1),
        )

    def _render_workspaces_panel(
        self,
        workspaces: list[WorkspaceAssignment],
        validation: Optional[Any] = None
    ) -> Panel:
        """Render i3 workspaces panel (Feature 018: T011).

        Args:
            workspaces: List of WorkspaceAssignment objects from i3 GET_WORKSPACES
            validation: Workspace validation result

        Returns:
            Rich Panel with workspaces table
        """
        # Create table
        table = Table(
            show_header=True,
            header_style="bold cyan",
            border_style="blue",
            show_lines=False,
        )

        table.add_column("#", justify="right", style="yellow", width=4)
        table.add_column("Name", justify="left", style="white", width=20)
        table.add_column("Output", justify="left", style="cyan", width=12)
        table.add_column("Visible", justify="center", style="green", width=8)
        table.add_column("Focused", justify="center", style="magenta", width=8)

        # Add rows
        if not workspaces:
            table.add_row("—", "—", "—", "—", "[red]No workspaces[/red]")
        else:
            # Sort by workspace number
            sorted_workspaces = sorted(workspaces, key=lambda ws: ws.num)

            for ws in sorted_workspaces:
                num = str(ws.num)
                name = self.truncate_string(ws.name, 20)
                output = ws.output
                visible = "[green]✓[/green]" if ws.visible else "[dim]—[/dim]"
                focused = "[bold magenta]●[/bold magenta]" if ws.focused else "[dim]—[/dim]"

                # Highlight focused workspace
                if ws.focused:
                    name = f"[bold]{name}[/bold]"
                    num = f"[bold]{num}[/bold]"

                # Highlight urgent workspace
                if ws.urgent:
                    name = f"[red]{name}[/red]"
                    num = f"[red]{num}[/red]"

                table.add_row(num, name, output, visible, focused)

        # Determine border style based on validation
        border_style = "green"
        title_suffix = ""
        if validation:
            if not validation.valid:
                border_style = "red"
                error_count = len(validation.errors)
                title_suffix = f" [red]⚠ {error_count} errors[/red]"
            elif validation.warnings:
                border_style = "yellow"
                warning_count = len(validation.warnings)
                title_suffix = f" [yellow]⚠ {warning_count} warnings[/yellow]"

        return Panel(
            table,
            title=f"[bold yellow]i3 Workspaces[/bold yellow] ({len(workspaces)} workspaces){title_suffix}",
            border_style=border_style,
            padding=(0, 1),
        )
