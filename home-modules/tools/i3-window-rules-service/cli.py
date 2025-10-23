#!/usr/bin/env python3
"""
Standalone CLI for window rules discovery.

This script can be called directly from Deno CLI or used standalone.
"""

import asyncio
import sys
import json
import argparse
from pathlib import Path
from typing import Optional

# Import our modules - handle both relative and absolute imports
try:
    from .models import ApplicationDefinition, PatternType, Scope
    from .discovery import discover_application, discover_from_registry, discover_from_open_windows
    from .config_manager import ConfigManager
    from .comparison import compare_with_existing_rules, format_comparison_report
except ImportError:
    from models import ApplicationDefinition, PatternType, Scope
    from discovery import discover_application, discover_from_registry, discover_from_open_windows
    from config_manager import ConfigManager
    from comparison import compare_with_existing_rules, format_comparison_report


async def discover_single(
    app_name: str,
    workspace: Optional[int] = None,
    scope: Optional[str] = None,
    launch_method: str = "direct",
    timeout: float = 10.0,
    keep_window: bool = False,
    output_json: bool = False,
) -> int:
    """Discover pattern for a single application."""
    # Load application registry
    config_mgr = ConfigManager()
    registry_apps = config_mgr.read_application_registry()

    # Find application in registry
    app_def = None
    for app in registry_apps:
        if app.name.lower() == app_name.lower():
            app_def = app
            break

    if not app_def:
        # Create minimal application definition
        app_def = ApplicationDefinition(
            name=app_name,
            display_name=app_name.title(),
            command=app_name,
            expected_pattern_type=PatternType.CLASS,
            scope=Scope(scope) if scope else Scope.GLOBAL,
            preferred_workspace=workspace,
        )

    # Discover pattern
    result = await discover_application(
        app_def,
        launch_method=launch_method,
        timeout=timeout,
        keep_window=keep_window,
    )

    # Output result
    if output_json:
        # JSON output for programmatic use
        output = {
            "application_name": result.application_name,
            "success": result.success,
            "pattern": {
                "type": result.generated_pattern.type.value,
                "value": result.generated_pattern.value,
                "confidence": result.confidence,
            } if result.generated_pattern else None,
            "window": {
                "class": result.window.window_class,
                "instance": result.window.window_instance,
                "title": result.window.title,
                "workspace": result.window.workspace_num,
            } if result.window else None,
            "errors": result.errors,
            "warnings": result.warnings,
            "wait_duration": result.wait_duration,
        }
        print(json.dumps(output, indent=2))
    else:
        # Human-readable output
        print(f"\nDiscovering pattern for: {result.application_name}")
        print("─" * 60)

        if result.success:
            print(f"✓ Window captured in {result.wait_duration:.1f}s\n")
            print("Discovered Pattern:")
            print(f"  Type:       {result.generated_pattern.type.value}")
            print(f"  Value:      {result.generated_pattern.value}")
            print(f"  Confidence: {result.confidence:.2f}")

            if result.window:
                print(f"\nWindow Properties:")
                print(f"  Class:      {result.window.window_class}")
                print(f"  Instance:   {result.window.window_instance}")
                print(f"  Title:      {result.window.title}")
                print(f"  Workspace:  {result.window.workspace_num}")

            if result.warnings:
                print(f"\nWarnings:")
                for warning in result.warnings:
                    print(f"  ⚠ {warning}")

            print("─" * 60)
        else:
            print(f"✗ Discovery failed\n")
            for error in result.errors:
                print(f"  ✗ {error}")
            if result.warnings:
                print(f"\nWarnings:")
                for warning in result.warnings:
                    print(f"  ⚠ {warning}")
            print("─" * 60)
            return 1

    return 0


async def scan_open_windows(output_json: bool = False, compare: bool = False, verbose: bool = False) -> int:
    """Scan currently open windows and generate patterns instantly."""
    if compare:
        # Compare with existing rules
        comparison_data = await compare_with_existing_rules()

        if output_json:
            # JSON output with full comparison data
            output = {
                "success": comparison_data["success"],
                "statistics": comparison_data["statistics"],
                "issues": []
            }

            for result in comparison_data.get("results", []):
                if result.status.value != "correct":
                    output["issues"].append({
                        "window_class": result.window.window_class,
                        "title": result.window.title,
                        "workspace": result.window.workspace_num,
                        "status": result.status.value,
                        "discovered_pattern": {
                            "type": result.discovered_pattern.type.value,
                            "value": result.discovered_pattern.value,
                        },
                        "matched_rule": result.matched_rule.rule_id if result.matched_rule else None,
                        "issues": result.issues,
                        "suggestions": result.suggestions,
                    })

            print(json.dumps(output, indent=2))
        else:
            # Human-readable comparison report
            report = format_comparison_report(comparison_data, verbose=verbose)
            print(report)

        return 0 if comparison_data.get("success") and comparison_data["statistics"]["total_issues"] == 0 else 1

    # Regular scan without comparison
    if not output_json:
        print("\nScanning open windows...")
        print("─" * 60)

    results = await discover_from_open_windows()

    if not results:
        print("No windows found")
        return 1

    if output_json:
        # Output all results as JSON
        output = []
        for result in results:
            output.append({
                "application_name": result.application_name,
                "pattern": {
                    "type": result.generated_pattern.type.value,
                    "value": result.generated_pattern.value,
                    "confidence": result.confidence,
                } if result.generated_pattern else None,
                "window": {
                    "class": result.window.window_class,
                    "instance": result.window.window_instance,
                    "title": result.window.title,
                    "workspace": result.window.workspace_num,
                } if result.window else None,
            })
        print(json.dumps(output, indent=2))
    else:
        # Human-readable table output
        print("\nDiscovered Patterns:")
        print(f"{'Application':<20} {'Type':<10} {'Value':<30} {'Confidence':<10}")
        print("─" * 80)
        for result in results:
            if result.generated_pattern:
                app_name = result.application_name[:20]
                pattern_type = result.generated_pattern.type.value
                pattern_value = result.generated_pattern.value[:30]
                confidence = f"{result.confidence:.2f}"
                print(f"{app_name:<20} {pattern_type:<10} {pattern_value:<30} {confidence:<10}")
        print("─" * 80)

    return 0


async def discover_bulk(
    registry_path: Optional[Path] = None,
    timeout: float = 10.0,
    delay: float = 1.0,
    output_json: bool = False,
) -> int:
    """Discover patterns for all applications in registry."""
    config_mgr = ConfigManager()

    if registry_path:
        # Load from specified path
        config_mgr.app_registry_path = registry_path

    registry_apps = config_mgr.read_application_registry()

    if not registry_apps:
        print("Error: No applications found in registry")
        return 1

    print(f"\nDiscovering patterns for {len(registry_apps)} applications...")
    print("─" * 60)

    results = await discover_from_registry(registry_apps, timeout=timeout, delay=delay)

    # Summary
    success_count = sum(1 for r in results if r.success)
    fail_count = len(results) - success_count

    print("─" * 60)
    print(f"\nComplete: {success_count}/{len(results)} succeeded, {fail_count} failed")

    if output_json:
        # Output all results as JSON
        output = []
        for result in results:
            output.append({
                "application_name": result.application_name,
                "success": result.success,
                "pattern": {
                    "type": result.generated_pattern.type.value,
                    "value": result.generated_pattern.value,
                    "confidence": result.confidence,
                } if result.generated_pattern else None,
                "errors": result.errors,
                "warnings": result.warnings,
            })
        print("\n" + json.dumps(output, indent=2))

    return 0 if success_count == len(results) else 1


def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Window rules discovery tool"
    )
    parser.add_argument("--version", action="version", version="1.0.0")

    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # Discover command
    discover_parser = subparsers.add_parser("discover", help="Discover window pattern")
    discover_parser.add_argument("--app", required=True, help="Application name")
    discover_parser.add_argument("--workspace", type=int, help="Workspace number (1-9)")
    discover_parser.add_argument("--scope", choices=["scoped", "global"], help="Application scope")
    discover_parser.add_argument("--method", choices=["direct", "rofi"], default="direct", help="Launch method")
    discover_parser.add_argument("--timeout", type=float, default=10.0, help="Wait timeout in seconds")
    discover_parser.add_argument("--keep-window", action="store_true", help="Don't close window after discovery")
    discover_parser.add_argument("--json", action="store_true", help="Output JSON")

    # Scan command - NEW: Instant discovery from open windows
    scan_parser = subparsers.add_parser("scan", help="Scan currently open windows (instant)")
    scan_parser.add_argument("--json", action="store_true", help="Output JSON")
    scan_parser.add_argument("--compare", action="store_true", help="Compare with existing rules")
    scan_parser.add_argument("--verbose", action="store_true", help="Show detailed output")

    # Bulk discover command
    bulk_parser = subparsers.add_parser("bulk", help="Discover patterns from registry")
    bulk_parser.add_argument("--registry", type=Path, help="Path to application-registry.json")
    bulk_parser.add_argument("--timeout", type=float, default=10.0, help="Wait timeout per app")
    bulk_parser.add_argument("--delay", type=float, default=1.0, help="Delay between apps")
    bulk_parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    if args.command == "discover":
        exit_code = asyncio.run(discover_single(
            app_name=args.app,
            workspace=args.workspace,
            scope=args.scope,
            launch_method=args.method,
            timeout=args.timeout,
            keep_window=args.keep_window,
            output_json=args.json,
        ))
        sys.exit(exit_code)

    elif args.command == "scan":
        exit_code = asyncio.run(scan_open_windows(
            output_json=args.json,
            compare=args.compare,
            verbose=args.verbose,
        ))
        sys.exit(exit_code)

    elif args.command == "bulk":
        exit_code = asyncio.run(discover_bulk(
            registry_path=args.registry,
            timeout=args.timeout,
            delay=args.delay,
            output_json=args.json,
        ))
        sys.exit(exit_code)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
