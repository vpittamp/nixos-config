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
            if "window_count" in daemon_status:
                lines.append(f"[bold green]Windows:[/bold green] {daemon_status['window_count']}")

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

    daemon_connected = status.get("connected", False)
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

    if status.get("window_count") is not None:
        lines.append(f"[bold cyan]Tracked Windows:[/bold cyan] {status['window_count']}")

    if status.get("event_count") is not None:
        lines.append(f"[bold cyan]Events Processed:[/bold cyan] {status['event_count']}")

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


# ============================================================================
# Feature 025: Window State Visualization Formatters (T034-T035)
# ============================================================================


def format_window_tree(tree_data: Dict[str, Any]) -> None:
    """Format window tree as ASCII tree using Rich Tree (T034).

    Args:
        tree_data: Window tree data from daemon (outputs → workspaces → windows)
    """
    from rich.tree import Tree

    # Create root tree
    root = Tree(f"🪟 Window State ({tree_data['total_windows']} windows)", guide_style="dim")

    for output in tree_data.get("outputs", []):
        # Output node
        output_label = f"📺 {output['name']} ({output['rect']['width']}x{output['rect']['height']})"
        output_node = root.add(output_label, style="bold cyan")

        for workspace in output.get("workspaces", []):
            # Workspace node
            focused = "●" if workspace.get("focused") else "○"
            visible = "👁" if workspace.get("visible") else ""
            ws_label = f"{focused} WS{workspace['number']}: {workspace['name']} - {len(workspace.get('windows', []))} windows {visible}"
            ws_node = output_node.add(ws_label, style="bold yellow" if workspace.get("focused") else "yellow")

            for window in workspace.get("windows", []):
                # Window node
                window_label = _format_window_tree_node(window)
                window_style = "green" if window.get("focused") else "white"
                ws_node.add(window_label, style=window_style)

    console.print(root)


def _format_window_tree_node(window: Dict) -> str:
    """Format individual window node label for tree view.

    Args:
        window: Window data dict

    Returns:
        Formatted label string
    """
    window_class = window.get("window_class", "?")
    title = window.get("title", "")
    project = window.get("project")
    hidden = window.get("hidden", False)
    classification = window.get("classification", "global")
    floating = window.get("floating", False)

    # Truncate title
    if len(title) > 40:
        title = title[:37] + "..."

    # Build label
    parts = []

    # Status indicators
    if hidden:
        parts.append("🔒")
    elif classification == "scoped":
        parts.append("🔸")

    if floating:
        parts.append("⬜")

    # Class and title
    parts.append(f"{window_class}: {title}")

    # Project tag
    if project:
        parts.append(f"[{project}]")

    return " ".join(parts)


def format_window_table(tree_data: Dict[str, Any]) -> None:
    """Format window state as table using Rich Table (T035).

    Args:
        tree_data: Window tree data from daemon
    """
    table = Table(title="Window State", show_header=True, header_style="bold cyan")

    # Add columns
    table.add_column("ID", justify="right", style="dim", width=8)
    table.add_column("Class", style="green", width=20)
    table.add_column("Title", style="white", width=35)
    table.add_column("WS", justify="center", width=5)
    table.add_column("Output", style="cyan", width=12)
    table.add_column("Project", style="yellow", width=12)
    table.add_column("Status", style="magenta", width=15)

    # Extract all windows from tree
    for output in tree_data.get("outputs", []):
        for workspace in output.get("workspaces", []):
            for window in workspace.get("windows", []):
                # Format row
                window_id = str(window.get("id", ""))
                window_class = window.get("window_class", "")
                title = window.get("title", "")
                ws_num = str(window.get("workspace", "?"))
                output_name = window.get("output", "")
                project = window.get("project", "-") or "-"
                status = _format_window_status(window)

                # Truncate title
                if len(title) > 35:
                    title = title[:32] + "..."

                table.add_row(
                    window_id,
                    window_class,
                    title,
                    ws_num,
                    output_name,
                    project,
                    status,
                )

    console.print(table)


def _format_window_status(window: Dict) -> str:
    """Format window status string for table view.

    Args:
        window: Window data dict

    Returns:
        Status string with indicators
    """
    parts = []

    if window.get("focused", False):
        parts.append("●Focus")

    if window.get("hidden", False):
        parts.append("🔒Hidden")
    elif window.get("classification") == "scoped":
        parts.append("🔸Scoped")
    else:
        parts.append("Global")

    if window.get("floating", False):
        parts.append("Float")

    return " ".join(parts)


def format_window_json(tree_data: Dict[str, Any]) -> None:
    """Format window state as JSON (T035).

    Args:
        tree_data: Window tree data from daemon
    """
    # Pretty-print JSON
    console.print_json(json.dumps(tree_data, indent=2))
