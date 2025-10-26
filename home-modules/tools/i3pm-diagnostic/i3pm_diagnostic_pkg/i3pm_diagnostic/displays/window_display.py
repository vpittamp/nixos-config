"""
Window Identity Display Module

Rich-formatted display for window properties and diagnostic information.

Feature 039 - Task T098
"""

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.text import Text
from rich.syntax import Syntax
from typing import Dict, Any, Optional


def display_window_identity(window_data: Dict[str, Any], console: Console = None) -> None:
    """
    Display comprehensive window identity in formatted tables.

    Args:
        window_data: Window identity result from daemon
        console: Rich console (optional, creates new if not provided)
    """
    if console is None:
        console = Console()

    window_id = window_data.get("window_id")
    console.print(f"\n[bold cyan]Window Identity: {window_id}[/bold cyan]\n")

    # Basic Properties Table
    basic_table = Table(title="Basic Properties", show_header=False)
    basic_table.add_column("Property", style="dim")
    basic_table.add_column("Value")

    basic_table.add_row("Window ID", str(window_id))
    basic_table.add_row("Class", window_data.get("window_class", "unknown"))
    basic_table.add_row("Class (normalized)", window_data.get("window_class_normalized", "unknown"))
    basic_table.add_row("Instance", window_data.get("window_instance", ""))
    basic_table.add_row("Title", window_data.get("window_title", "(no title)"))
    basic_table.add_row("PID", str(window_data.get("window_pid", "N/A")))

    console.print(basic_table)
    console.print()

    # Location Table
    location_table = Table(title="Location", show_header=False)
    location_table.add_column("Property", style="dim")
    location_table.add_column("Value")

    workspace_num = window_data.get("workspace_number")
    workspace_name = window_data.get("workspace_name", "")
    location_table.add_row("Workspace", f"{workspace_num}" + (f" ({workspace_name})" if workspace_name else ""))
    location_table.add_row("Output", window_data.get("output_name", "N/A"))

    is_floating = window_data.get("is_floating", False)
    floating_text = "[yellow]Yes[/yellow]" if is_floating else "[green]No[/green]"
    location_table.add_row("Floating", floating_text)

    is_focused = window_data.get("is_focused", False)
    focused_text = "[green]Yes[/green]" if is_focused else "[dim]No[/dim]"
    location_table.add_row("Focused", focused_text)

    is_hidden = window_data.get("is_hidden", False)
    hidden_text = "[red]Yes (in scratchpad)[/red]" if is_hidden else "[green]No[/green]"
    location_table.add_row("Hidden", hidden_text)

    console.print(location_table)
    console.print()

    # I3PM Environment Table
    i3pm_env = window_data.get("i3pm_env")
    if i3pm_env:
        env_table = Table(title="I3PM Environment", show_header=False)
        env_table.add_column("Variable", style="dim")
        env_table.add_column("Value")

        env_table.add_row("App ID", i3pm_env.get("app_id", "N/A"))
        env_table.add_row("App Name", i3pm_env.get("app_name", "N/A"))

        project_name = i3pm_env.get("project_name")
        if project_name:
            env_table.add_row("Project Name", f"[bold cyan]{project_name}[/bold cyan]")
        else:
            env_table.add_row("Project Name", "[dim](none - global)[/dim]")

        scope = i3pm_env.get("scope", "unknown")
        scope_style = "green" if scope == "scoped" else "yellow"
        env_table.add_row("Scope", f"[{scope_style}]{scope}[/{scope_style}]")

        console.print(env_table)
        console.print()
    else:
        console.print(Panel(
            "[yellow]No I3PM environment found[/yellow]\n"
            "This window may have existed before the daemon started, "
            "or was not launched via the app launcher.",
            title="I3PM Environment"
        ))
        console.print()

    # I3 Marks
    i3pm_marks = window_data.get("i3pm_marks", [])
    if i3pm_marks:
        marks_text = ", ".join([f"[cyan]{mark}[/cyan]" for mark in i3pm_marks])
        console.print(Panel(marks_text, title="I3PM Marks"))
        console.print()

    # Registry Matching
    matched_app = window_data.get("matched_app")
    match_type = window_data.get("match_type", "none")

    match_table = Table(title="Registry Matching", show_header=False)
    match_table.add_column("Property", style="dim")
    match_table.add_column("Value")

    if matched_app:
        match_table.add_row("Matched App", f"[green]{matched_app}[/green]")

        match_type_style = "green" if match_type in ["exact", "instance"] else "yellow"
        match_table.add_row("Match Type", f"[{match_type_style}]{match_type}[/{match_type_style}]")
    else:
        match_table.add_row("Matched App", "[red](no match)[/red]")
        match_table.add_row("Match Type", "[red]none[/red]")

    console.print(match_table)


def display_window_mismatch(window_data: Dict[str, Any], expected_class: str, console: Console = None) -> None:
    """
    Display window class mismatch diagnostic.

    Highlights the difference between expected and actual window class.

    Args:
        window_data: Window identity result
        expected_class: Expected window class from configuration
        console: Rich console
    """
    if console is None:
        console = Console()

    actual_class = window_data.get("window_class", "unknown")
    normalized_class = window_data.get("window_class_normalized", "unknown")

    mismatch_table = Table(title="⚠ Class Mismatch Detected", show_header=False)
    mismatch_table.add_column("", style="dim")
    mismatch_table.add_column("")

    mismatch_table.add_row("Expected", Text(expected_class, style="yellow"))
    mismatch_table.add_row("Actual", Text(actual_class, style="red"))
    mismatch_table.add_row("Normalized", Text(normalized_class, style="cyan"))

    console.print(mismatch_table)
    console.print()

    # Suggestions
    console.print("[bold]Suggestions:[/bold]")
    if normalized_class.lower() == expected_class.lower():
        console.print("  ✓ Normalized classes match! The matching should work correctly.")
    elif normalized_class in actual_class.lower():
        console.print(f"  • Try using normalized class: '{normalized_class}'")
    else:
        console.print(f"  • Update your configuration to use: '{actual_class}'")
        console.print(f"  • Or use normalized form: '{normalized_class}'")
        console.print(f"  • Or add alias: '{expected_class}' to the app registry")


def format_window_json(window_data: Dict[str, Any]) -> str:
    """
    Format window identity as JSON string.

    Args:
        window_data: Window identity result from daemon

    Returns:
        JSON string
    """
    import json
    return json.dumps(window_data, indent=2)
