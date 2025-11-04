"""
Diagnostic commands for i3pm environment variable-based window matching.

Provides commands for:
- Coverage validation across all windows
- Window-specific environment inspection
- Environment variable troubleshooting
"""

import asyncio
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

import click
from rich.console import Console
from rich.table import Table
from i3ipc.aio import Connection

# Add daemon module to path for imports
daemon_path = Path(__file__).parent.parent / "daemon"
if str(daemon_path) not in sys.path:
    sys.path.insert(0, str(daemon_path))

from window_environment import (
    validate_environment_coverage,
    get_window_environment,
    read_process_environ,
)

console = Console()


@click.group()
def diagnose():
    """Diagnostic commands for environment variable validation."""
    pass


@diagnose.command()
@click.option(
    "--json",
    "output_json",
    is_flag=True,
    help="Output results as JSON instead of table",
)
async def coverage(output_json: bool):
    """
    Validate environment variable coverage across all windows.

    Checks that all launched applications have I3PM_* environment variables
    injected. Reports coverage percentage and lists windows without variables.

    Examples:
        i3pm diagnose coverage
        i3pm diagnose coverage --json
    """
    try:
        # Connect to Sway IPC
        async with Connection() as i3:
            # Validate coverage
            report = await validate_environment_coverage(i3)

            if output_json:
                # JSON output for scripting
                output = {
                    "total_windows": report.total_windows,
                    "windows_with_env": report.windows_with_env,
                    "windows_without_env": report.windows_without_env,
                    "coverage_percentage": report.coverage_percentage,
                    "status": report.status,
                    "timestamp": report.timestamp.isoformat(),
                    "missing_windows": [
                        {
                            "window_id": w.window_id,
                            "window_class": w.window_class,
                            "window_title": w.window_title,
                            "pid": w.pid,
                            "reason": w.reason,
                        }
                        for w in report.missing_windows
                    ],
                }
                click.echo(json.dumps(output, indent=2))
            else:
                # Human-readable table output
                _display_coverage_report(report)

            # Exit with status code based on coverage
            sys.exit(0 if report.status == "PASS" else 1)

    except Exception as e:
        console.print(f"[red]Error validating coverage: {e}[/red]")
        sys.exit(2)


@diagnose.command()
@click.argument("window_id", type=int)
@click.option(
    "--json",
    "output_json",
    is_flag=True,
    help="Output results as JSON instead of table",
)
async def window(window_id: int, output_json: bool):
    """
    Inspect environment variables for a specific window.

    Shows I3PM_* environment variables from /proc/<pid>/environ for the
    specified window ID. Displays traversal depth if parent process was used.

    Examples:
        i3pm diagnose window 94532735639728
        i3pm diagnose window 94532735639728 --json

    Get window ID:
        swaymsg -t get_tree | jq '.. | select(.focused?) | .id'
    """
    try:
        # Connect to Sway IPC
        async with Connection() as i3:
            # Find window in tree
            tree = await i3.get_tree()
            target_window = None

            for win in tree.leaves():
                if win.id == window_id:
                    target_window = win
                    break

            if not target_window:
                console.print(f"[red]Window {window_id} not found[/red]")
                sys.exit(1)

            # Check if window has PID
            if not target_window.pid:
                console.print(f"[yellow]Window {window_id} has no PID[/yellow]")
                if output_json:
                    click.echo(json.dumps({"error": "no_pid", "window_id": window_id}))
                sys.exit(1)

            # Query environment
            result = await get_window_environment(
                window_id=target_window.id,
                pid=target_window.pid,
            )

            if output_json:
                # JSON output
                output = {
                    "window_id": result.window_id,
                    "requested_pid": result.requested_pid,
                    "actual_pid": result.actual_pid,
                    "traversal_depth": result.traversal_depth,
                    "query_time_ms": result.query_time_ms,
                    "error": result.error,
                }

                if result.environment:
                    output["environment"] = {
                        "app_id": result.environment.app_id,
                        "app_name": result.environment.app_name,
                        "scope": result.environment.scope,
                        "project_name": result.environment.project_name,
                        "project_dir": result.environment.project_dir,
                        "target_workspace": result.environment.target_workspace,
                        "expected_class": result.environment.expected_class,
                    }

                click.echo(json.dumps(output, indent=2))
            else:
                # Human-readable output
                _display_window_environment(target_window, result)

            sys.exit(0 if result.environment else 1)

    except Exception as e:
        console.print(f"[red]Error inspecting window: {e}[/red]")
        sys.exit(2)


def _display_coverage_report(report):
    """Display coverage report as formatted table."""
    # Summary section
    console.print("\n[bold]Environment Variable Coverage Report[/bold]")
    console.print(f"Timestamp: {report.timestamp.strftime('%Y-%m-%d %H:%M:%S')}\n")

    # Statistics table
    stats_table = Table(show_header=True, header_style="bold cyan")
    stats_table.add_column("Metric", style="cyan")
    stats_table.add_column("Value", justify="right")

    stats_table.add_row("Total Windows", str(report.total_windows))
    stats_table.add_row("With I3PM_* Variables", str(report.windows_with_env))
    stats_table.add_row("Without Variables", str(report.windows_without_env))
    stats_table.add_row(
        "Coverage",
        f"{report.coverage_percentage:.1f}%",
    )

    # Status with color
    status_color = "green" if report.status == "PASS" else "red"
    stats_table.add_row("Status", f"[{status_color}]{report.status}[/{status_color}]")

    console.print(stats_table)

    # Missing windows table (if any)
    if report.missing_windows:
        console.print(f"\n[bold yellow]Missing Windows ({len(report.missing_windows)})[/bold yellow]\n")

        missing_table = Table(show_header=True, header_style="bold yellow")
        missing_table.add_column("Window ID", style="yellow")
        missing_table.add_column("Class")
        missing_table.add_column("Title", max_width=40)
        missing_table.add_column("PID", justify="right")
        missing_table.add_column("Reason")

        for missing in report.missing_windows[:20]:  # Show first 20
            missing_table.add_row(
                str(missing.window_id),
                missing.window_class,
                missing.window_title[:40] if missing.window_title else "(no title)",
                str(missing.pid) if missing.pid else "N/A",
                missing.reason,
            )

        console.print(missing_table)

        if len(report.missing_windows) > 20:
            console.print(f"\n[dim]... and {len(report.missing_windows) - 20} more[/dim]")


def _display_window_environment(window, result):
    """Display window environment as formatted output."""
    console.print(f"\n[bold]Window Environment: {window.id}[/bold]\n")

    # Window info
    info_table = Table(show_header=False, box=None)
    info_table.add_column("Property", style="cyan")
    info_table.add_column("Value")

    info_table.add_row("Window ID", str(window.id))
    info_table.add_row("Window Class", getattr(window, "app_id", None) or getattr(window, "window_class", "(unknown)"))
    info_table.add_row("Window Title", window.name or "(no title)")
    info_table.add_row("PID", str(window.pid))
    info_table.add_row("Workspace", str(window.workspace().num if window.workspace() else "N/A"))

    console.print(info_table)

    # Query info
    console.print(f"\n[bold]Environment Query[/bold]\n")
    query_table = Table(show_header=False, box=None)
    query_table.add_column("Property", style="cyan")
    query_table.add_column("Value")

    query_table.add_row("Requested PID", str(result.requested_pid))
    query_table.add_row("Actual PID", str(result.actual_pid) if result.actual_pid else "N/A")
    query_table.add_row("Traversal Depth", str(result.traversal_depth))
    query_table.add_row("Query Time", f"{result.query_time_ms:.2f}ms")

    if result.error:
        query_table.add_row("Error", f"[red]{result.error}[/red]")

    console.print(query_table)

    # Environment variables
    if result.environment:
        console.print(f"\n[bold green]I3PM_* Environment Variables[/bold green]\n")
        env_table = Table(show_header=False, box=None)
        env_table.add_column("Variable", style="green")
        env_table.add_column("Value")

        env = result.environment
        env_table.add_row("I3PM_APP_ID", env.app_id[:50] + "..." if len(env.app_id) > 50 else env.app_id)
        env_table.add_row("I3PM_APP_NAME", env.app_name)
        env_table.add_row("I3PM_SCOPE", env.scope)
        env_table.add_row("I3PM_PROJECT_NAME", env.project_name or "(none)")
        env_table.add_row("I3PM_PROJECT_DIR", env.project_dir or "(none)")
        if env.target_workspace:
            env_table.add_row("I3PM_TARGET_WORKSPACE", str(env.target_workspace))
        if env.expected_class:
            env_table.add_row("I3PM_EXPECTED_CLASS", env.expected_class)

        console.print(env_table)

        # Validation
        if result.environment:
            from window_environment import validate_window_environment
            env_dict = read_process_environ(result.actual_pid)
            errors = validate_window_environment(env_dict)

            if errors:
                console.print(f"\n[bold red]Validation Errors[/bold red]\n")
                for error in errors:
                    console.print(f"  [red]✗[/red] {error}")
            else:
                console.print(f"\n[bold green]✓ All environment variables valid[/bold green]")
    else:
        console.print(f"\n[bold yellow]No I3PM_* environment variables found[/bold yellow]")
        if result.traversal_depth > 0:
            console.print(f"[dim]Checked {result.traversal_depth + 1} process levels[/dim]")


# Make commands async-compatible
def _run_async(coro):
    """Helper to run async commands."""
    return asyncio.run(coro)


# Wrap commands to run async
_coverage_original = coverage
_window_original = window


@diagnose.command(name="coverage")
@click.option("--json", "output_json", is_flag=True, help="Output as JSON")
def coverage_sync(output_json):
    """Validate environment variable coverage."""
    _run_async(_coverage_original.callback(output_json))


@diagnose.command(name="window")
@click.argument("window_id", type=int)
@click.option("--json", "output_json", is_flag=True, help="Output as JSON")
def window_sync(window_id, output_json):
    """Inspect window environment variables."""
    _run_async(_window_original.callback(window_id, output_json))


if __name__ == "__main__":
    diagnose()
