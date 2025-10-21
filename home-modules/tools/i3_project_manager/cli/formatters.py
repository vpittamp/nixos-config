"""Rich formatters for i3pm CLI output.

Provides formatted, colored output for CLI commands using the Rich library.
Includes fallback to plain text for terminals without color support.
"""

import json
from typing import Any, Dict, List, Optional
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.text import Text

from i3_project_manager.core.models import Project


# Global console instance
console = Console()


def format_project_list(projects: List[Project], sort_by: str = "modified", reverse: bool = False) -> Table:
    """Format a list of projects as a Rich table.

    Args:
        projects: List of projects to display
        sort_by: Field to sort by (name, modified, directory)
        reverse: Reverse sort order

    Returns:
        Rich Table object ready for display
    """
    table = Table(title="Projects", show_header=True, header_style="bold cyan")

    table.add_column("Icon", style="white", width=4)
    table.add_column("Name", style="bold green")
    table.add_column("Directory", style="blue")
    table.add_column("Apps", justify="right", style="yellow")
    table.add_column("Layouts", justify="right", style="magenta")
    table.add_column("Modified", style="dim")

    # Sort projects
    if sort_by == "name":
        key = lambda p: p.name
    elif sort_by == "directory":
        key = lambda p: str(p.directory)
    else:  # modified
        key = lambda p: p.modified_at

    sorted_projects = sorted(projects, key=key, reverse=reverse)

    for project in sorted_projects:
        # Calculate relative time
        from datetime import datetime
        time_diff = datetime.now() - project.modified_at
        if time_diff.days > 0:
            modified_str = f"{time_diff.days}d ago"
        elif time_diff.seconds // 3600 > 0:
            modified_str = f"{time_diff.seconds // 3600}h ago"
        else:
            modified_str = f"{time_diff.seconds // 60}m ago"

        table.add_row(
            project.icon or " ",
            project.display_name or project.name,
            str(project.directory),
            str(len(project.scoped_classes)),
            str(len(project.saved_layouts)),
            modified_str,
        )

    return table


def format_project_details(project: Project, daemon_status: Optional[Dict[str, Any]] = None) -> Panel:
    """Format detailed project information as a Rich panel.

    Args:
        project: The project to display
        daemon_status: Optional daemon status for active window count

    Returns:
        Rich Panel object ready for display
    """
    lines = []

    # Basic info
    lines.append(f"[bold cyan]Name:[/bold cyan] {project.name}")
    if project.display_name:
        lines.append(f"[bold cyan]Display Name:[/bold cyan] {project.display_name}")
    if project.icon:
        lines.append(f"[bold cyan]Icon:[/bold cyan] {project.icon}")
    lines.append(f"[bold cyan]Directory:[/bold cyan] {project.directory}")

    # Scoped classes
    lines.append("")
    lines.append(f"[bold cyan]Scoped Applications ({len(project.scoped_classes)}):[/bold cyan]")
    for cls in project.scoped_classes:
        lines.append(f"  • {cls}")

    # Workspace preferences
    if project.workspace_preferences:
        lines.append("")
        lines.append("[bold cyan]Workspace Preferences:[/bold cyan]")
        for ws, output in project.workspace_preferences.items():
            lines.append(f"  WS {ws} → {output}")

    # Auto-launch apps
    if project.auto_launch:
        lines.append("")
        lines.append(f"[bold cyan]Auto-Launch ({len(project.auto_launch)}):[/bold cyan]")
        for app in project.auto_launch:
            lines.append(f"  • {app.command}")

    # Saved layouts
    if project.saved_layouts:
        lines.append("")
        lines.append(f"[bold cyan]Saved Layouts ({len(project.saved_layouts)}):[/bold cyan]")
        for layout in project.saved_layouts:
            lines.append(f"  • {layout}")

    # Daemon info
    if daemon_status:
        lines.append("")
        if daemon_status.get("active_project") == project.name:
            lines.append("[bold green]Status:[/bold green] Active")
            if "tracked_windows" in daemon_status:
                lines.append(f"[bold green]Windows:[/bold green] {daemon_status['tracked_windows']}")

    # Metadata
    lines.append("")
    lines.append(f"[dim]Created: {project.created_at.strftime('%Y-%m-%d %H:%M:%S')}[/dim]")
    lines.append(f"[dim]Modified: {project.modified_at.strftime('%Y-%m-%d %H:%M:%S')}[/dim]")

    content = "\n".join(lines)
    return Panel(content, title=f"Project: {project.name}", border_style="cyan")


def format_status(status: Dict[str, Any]) -> Panel:
    """Format daemon status as a Rich panel.

    Args:
        status: Daemon status dictionary

    Returns:
        Rich Panel object ready for display
    """
    lines = []

    daemon_connected = status.get("daemon_connected", False)
    if daemon_connected:
        lines.append("[bold green]Daemon Status:[/bold green] Connected ✓")
    else:
        lines.append("[bold red]Daemon Status:[/bold red] Disconnected ✗")

    if status.get("uptime_seconds"):
        uptime = status["uptime_seconds"]
        if uptime > 3600:
            uptime_str = f"{uptime / 3600:.1f}h"
        elif uptime > 60:
            uptime_str = f"{uptime / 60:.0f}m"
        else:
            uptime_str = f"{uptime:.0f}s"
        lines.append(f"[bold cyan]Uptime:[/bold cyan] {uptime_str}")

    active_project = status.get("active_project")
    if active_project:
        lines.append(f"[bold cyan]Active Project:[/bold cyan] [green]{active_project}[/green]")
    else:
        lines.append("[bold cyan]Active Project:[/bold cyan] [dim]None[/dim]")

    if status.get("tracked_windows") is not None:
        lines.append(f"[bold cyan]Tracked Windows:[/bold cyan] {status['tracked_windows']}")

    if status.get("events_processed") is not None:
        lines.append(f"[bold cyan]Events Processed:[/bold cyan] {status['events_processed']}")

    content = "\n".join(lines)
    return Panel(content, title="i3pm Status", border_style="cyan")


def format_success(message: str) -> Text:
    """Format a success message with green checkmark.

    Args:
        message: The success message

    Returns:
        Rich Text object ready for display
    """
    return Text.from_markup(f"[bold green]✓[/bold green] {message}")


def format_error(message: str) -> Text:
    """Format an error message with red X.

    Args:
        message: The error message

    Returns:
        Rich Text object ready for display
    """
    return Text.from_markup(f"[bold red]✗[/bold red] {message}")


def format_warning(message: str) -> Text:
    """Format a warning message with yellow warning symbol.

    Args:
        message: The warning message

    Returns:
        Rich Text object ready for display
    """
    return Text.from_markup(f"[bold yellow]⚠[/bold yellow]  {message}")


def format_json(data: Any, pretty: bool = True) -> str:
    """Format data as JSON string.

    Args:
        data: The data to format as JSON
        pretty: Whether to pretty-print with indentation

    Returns:
        JSON string
    """
    if pretty:
        return json.dumps(data, indent=2, default=str)
    return json.dumps(data, default=str)


def print_success(message: str) -> None:
    """Print a success message to console.

    Args:
        message: The success message
    """
    console.print(format_success(message))


def print_error(message: str) -> None:
    """Print an error message to console.

    Args:
        message: The error message
    """
    console.print(format_error(message))


def print_warning(message: str) -> None:
    """Print a warning message to console.

    Args:
        message: The warning message
    """
    console.print(format_warning(message))
