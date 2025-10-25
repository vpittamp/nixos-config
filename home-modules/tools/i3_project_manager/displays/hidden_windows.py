"""Display module for hidden windows visualization.

This module provides Rich-based formatted displays for hidden windows
in Feature 037 (Unified Project-Scoped Window Management).

Supported formats:
- table: Rich table with project grouping
- tree: Hierarchical project → windows structure
- json: Machine-readable JSON output
"""

from typing import Dict, List, Optional
from rich.console import Console
from rich.table import Table
from rich.tree import Tree
from rich.text import Text
import json

from ..core.models import ProjectWindows, WindowState


def display_table(
    projects_windows: List[ProjectWindows],
    console: Optional[Console] = None,
    show_empty: bool = False,
) -> None:
    """Display hidden windows in table format with project grouping.

    Args:
        projects_windows: List of ProjectWindows with hidden windows
        console: Rich console (creates new if None)
        show_empty: Show projects with no hidden windows
    """
    if console is None:
        console = Console()

    if not projects_windows and not show_empty:
        console.print("[yellow]No hidden windows found[/yellow]")
        return

    # Create main table
    table = Table(title="Hidden Windows by Project", show_header=True, header_style="bold magenta")
    table.add_column("Project", style="cyan", no_wrap=True)
    table.add_column("App", style="green")
    table.add_column("Window", style="white")
    table.add_column("Workspace", style="yellow", justify="right")
    table.add_column("Last Seen", style="dim")

    # Add rows grouped by project
    total_hidden = 0
    for proj_windows in projects_windows:
        if not proj_windows.hidden and not show_empty:
            continue

        # Add project header row (span all columns)
        if proj_windows.hidden:
            table.add_row(
                f"[bold]{proj_windows.project_name}[/bold] ({len(proj_windows.hidden)} windows)",
                "",
                "",
                "",
                "",
                style="cyan",
            )

            # Add window rows
            for window in proj_windows.hidden:
                # Format last seen time
                import time
                time_diff = time.time() - window.last_seen
                if time_diff < 60:
                    last_seen_str = f"{int(time_diff)}s ago"
                elif time_diff < 3600:
                    last_seen_str = f"{int(time_diff / 60)}m ago"
                elif time_diff < 86400:
                    last_seen_str = f"{int(time_diff / 3600)}h ago"
                else:
                    last_seen_str = f"{int(time_diff / 86400)}d ago"

                table.add_row(
                    "",  # Indent under project
                    f"  {window.app_name}",
                    f"  {window.window_class}",
                    f"WS {window.workspace_number}",
                    last_seen_str,
                )

            total_hidden += len(proj_windows.hidden)
        elif show_empty:
            table.add_row(
                f"[dim]{proj_windows.project_name}[/dim] (0 windows)",
                "",
                "",
                "",
                "",
                style="dim",
            )

    console.print(table)

    # Summary
    if total_hidden > 0:
        console.print(f"\n[bold]Total hidden windows:[/bold] {total_hidden}")


def display_tree(
    projects_windows: List[ProjectWindows],
    console: Optional[Console] = None,
    show_empty: bool = False,
) -> None:
    """Display hidden windows in tree format with hierarchical structure.

    Args:
        projects_windows: List of ProjectWindows with hidden windows
        console: Rich console (creates new if None)
        show_empty: Show projects with no hidden windows
    """
    if console is None:
        console = Console()

    if not projects_windows and not show_empty:
        console.print("[yellow]No hidden windows found[/yellow]")
        return

    # Create root tree
    tree = Tree("🔒 [bold]Hidden Windows[/bold]")

    total_hidden = 0
    for proj_windows in projects_windows:
        if not proj_windows.hidden and not show_empty:
            continue

        # Add project branch
        project_label = f"[cyan]{proj_windows.project_name}[/cyan] ({len(proj_windows.hidden)} windows)"
        if not proj_windows.hidden:
            project_label = f"[dim]{proj_windows.project_name}[/dim] (0 windows)"

        project_branch = tree.add(project_label)

        # Add window leaves
        for window in proj_windows.hidden:
            window_label = (
                f"[green]{window.app_name}[/green] - "
                f"[white]{window.window_class}[/white] "
                f"[yellow]→ WS {window.workspace_number}[/yellow]"
            )
            if window.floating:
                window_label += " [magenta](floating)[/magenta]"

            project_branch.add(window_label)

        total_hidden += len(proj_windows.hidden)

    console.print(tree)

    # Summary
    if total_hidden > 0:
        console.print(f"\n[bold]Total hidden windows:[/bold] {total_hidden}")


def display_json(
    projects_windows: List[ProjectWindows],
    console: Optional[Console] = None,
    pretty: bool = True,
) -> None:
    """Display hidden windows in JSON format.

    Args:
        projects_windows: List of ProjectWindows with hidden windows
        console: Rich console (creates new if None)
        pretty: Pretty-print JSON with indentation
    """
    if console is None:
        console = Console()

    # Build JSON structure
    output = {
        "projects": [
            {
                "project_name": proj.project_name,
                "hidden_count": len(proj.hidden),
                "windows": [
                    {
                        "window_id": w.window_id,
                        "app_name": w.app_name,
                        "window_class": w.window_class,
                        "workspace_number": w.workspace_number,
                        "floating": w.floating,
                        "last_seen": w.last_seen,
                    }
                    for w in proj.hidden
                ],
            }
            for proj in projects_windows
        ],
        "total_hidden": sum(len(proj.hidden) for proj in projects_windows),
    }

    # Print JSON
    if pretty:
        console.print_json(data=output)
    else:
        console.print(json.dumps(output))


def display_hidden_windows(
    projects_windows: List[ProjectWindows],
    format: str = "table",
    console: Optional[Console] = None,
    show_empty: bool = False,
) -> None:
    """Display hidden windows using specified format.

    Args:
        projects_windows: List of ProjectWindows with hidden windows
        format: Display format ("table", "tree", or "json")
        console: Rich console (creates new if None)
        show_empty: Show projects with no hidden windows

    Raises:
        ValueError: If format is not supported
    """
    if format == "table":
        display_table(projects_windows, console, show_empty)
    elif format == "tree":
        display_tree(projects_windows, console, show_empty)
    elif format == "json":
        display_json(projects_windows, console)
    else:
        raise ValueError(f"Unsupported format: {format}. Must be 'table', 'tree', or 'json'")


def filter_projects(
    projects_windows: List[ProjectWindows],
    project_name: Optional[str] = None,
    workspace: Optional[int] = None,
    app_name: Optional[str] = None,
) -> List[ProjectWindows]:
    """Filter projects_windows by various criteria.

    Args:
        projects_windows: List of ProjectWindows to filter
        project_name: Filter by project name (exact match)
        workspace: Filter by workspace number
        app_name: Filter by application name (exact match)

    Returns:
        Filtered list of ProjectWindows
    """
    filtered = []

    for proj_windows in projects_windows:
        # Filter by project name
        if project_name and proj_windows.project_name != project_name:
            continue

        # Filter windows by workspace and app_name
        filtered_hidden = proj_windows.hidden

        if workspace:
            filtered_hidden = [w for w in filtered_hidden if w.workspace_number == workspace]

        if app_name:
            filtered_hidden = [w for w in filtered_hidden if w.app_name == app_name]

        # Create filtered ProjectWindows
        if filtered_hidden or not (workspace or app_name):
            filtered.append(
                ProjectWindows(
                    project_name=proj_windows.project_name,
                    visible=proj_windows.visible,
                    hidden=filtered_hidden,
                )
            )

    return filtered
