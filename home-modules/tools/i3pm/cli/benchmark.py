"""
Performance benchmark commands for environment variable queries.

Provides commands for measuring and validating /proc filesystem read performance.
"""

import asyncio
import json
import sys
from pathlib import Path

import click
from rich.console import Console
from rich.table import Table

# Add daemon module to path for imports
daemon_path = Path(__file__).parent.parent / "daemon"
if str(daemon_path) not in sys.path:
    sys.path.insert(0, str(daemon_path))

from window_environment import benchmark_environment_queries

console = Console()


@click.group()
def benchmark():
    """Performance benchmark commands."""
    pass


@benchmark.command()
@click.option(
    "--samples",
    type=int,
    default=1000,
    help="Number of samples to measure (default: 1000)",
)
@click.option(
    "--json",
    "output_json",
    is_flag=True,
    help="Output results as JSON instead of table",
)
async def environ(samples: int, output_json: bool):
    """
    Benchmark environment variable query performance.

    Measures /proc/<pid>/environ read latency to validate performance meets
    <10ms p95 target. Creates test processes and measures read_process_environ()
    latency for statistical analysis.

    Examples:
        i3pm benchmark environ
        i3pm benchmark environ --samples 2000
        i3pm benchmark environ --samples 1000 --json
    """
    if samples < 10:
        console.print("[red]Error: samples must be at least 10[/red]")
        sys.exit(1)

    if samples > 10000:
        console.print("[yellow]Warning: large sample size may take a while...[/yellow]")

    try:
        # Run benchmark
        console.print(f"\nRunning environment query benchmark with {samples} samples...")
        console.print("[dim]Creating test processes and measuring latency...[/dim]\n")

        result = await benchmark_environment_queries(sample_size=samples)

        if output_json:
            # JSON output for scripting
            output = {
                "operation": result.operation,
                "sample_size": result.sample_size,
                "average_ms": result.average_ms,
                "p50_ms": result.p50_ms,
                "p95_ms": result.p95_ms,
                "p99_ms": result.p99_ms,
                "max_ms": result.max_ms,
                "min_ms": result.min_ms,
                "status": result.status,
            }
            click.echo(json.dumps(output, indent=2))
        else:
            # Human-readable table output
            _display_benchmark_results(result)

        # Exit with status code based on benchmark result
        sys.exit(0 if result.status == "PASS" else 1)

    except KeyboardInterrupt:
        console.print("\n[yellow]Benchmark interrupted by user[/yellow]")
        sys.exit(130)
    except Exception as e:
        console.print(f"[red]Error running benchmark: {e}[/red]")
        sys.exit(2)


def _display_benchmark_results(result):
    """Display benchmark results as formatted table."""
    console.print(f"\n[bold]Environment Query Performance Benchmark[/bold]\n")

    # Statistics table
    stats_table = Table(show_header=True, header_style="bold cyan")
    stats_table.add_column("Metric", style="cyan")
    stats_table.add_column("Value", justify="right")

    stats_table.add_row("Operation", result.operation)
    stats_table.add_row("Sample Size", f"{result.sample_size:,}")
    stats_table.add_row("", "")  # Separator

    # Latency metrics with color coding
    avg_color = "green" if result.average_ms < 1.0 else "yellow"
    stats_table.add_row("Average", f"[{avg_color}]{result.average_ms:.3f}ms[/{avg_color}]")

    p50_color = "green" if result.p50_ms < 1.0 else "yellow"
    stats_table.add_row("p50 (median)", f"[{p50_color}]{result.p50_ms:.3f}ms[/{p50_color}]")

    p95_color = "green" if result.p95_ms < 10.0 else "red"
    stats_table.add_row("p95", f"[{p95_color}]{result.p95_ms:.3f}ms[/{p95_color}]")

    p99_color = "green" if result.p99_ms < 10.0 else "yellow"
    stats_table.add_row("p99", f"[{p99_color}]{result.p99_ms:.3f}ms[/{p99_color}]")

    stats_table.add_row("Min", f"{result.min_ms:.3f}ms")
    stats_table.add_row("Max", f"{result.max_ms:.3f}ms")
    stats_table.add_row("", "")  # Separator

    # Status with color
    status_color = "green" if result.status == "PASS" else "red"
    stats_table.add_row("Status", f"[bold {status_color}]{result.status}[/bold {status_color}]")

    console.print(stats_table)

    # Performance targets
    console.print(f"\n[bold]Performance Targets:[/bold]")
    console.print(f"  Average:  < 1.0ms   [{_check_mark(result.average_ms < 1.0)}]")
    console.print(f"  p95:      < 10.0ms  [{_check_mark(result.p95_ms < 10.0)}]")

    if result.status == "PASS":
        console.print(f"\n[bold green]✓ Benchmark PASSED - Performance meets targets[/bold green]")
    else:
        console.print(f"\n[bold red]✗ Benchmark FAILED - Performance below targets[/bold red]")

    console.print()


def _check_mark(passed: bool) -> str:
    """Return colored check or cross mark."""
    return "[green]✓[/green]" if passed else "[red]✗[/red]"


# Make command async-compatible
def _run_async(coro):
    """Helper to run async commands."""
    return asyncio.run(coro)


# Wrap command to run async
_environ_original = environ


@benchmark.command(name="environ")
@click.option("--samples", type=int, default=1000, help="Number of samples")
@click.option("--json", "output_json", is_flag=True, help="Output as JSON")
def environ_sync(samples, output_json):
    """Benchmark environment variable query performance."""
    _run_async(_environ_original.callback(samples, output_json))


if __name__ == "__main__":
    benchmark()
