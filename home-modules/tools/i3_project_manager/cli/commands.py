"""CLI command handlers for i3pm.

Implements all CLI commands for i3 project management.
"""

import argparse
import asyncio
import sys
from pathlib import Path
from typing import Optional

from ..core.project import ProjectManager
from ..core.daemon_client import DaemonClient, DaemonError
from ..core.i3_client import I3Client, I3Error


# ANSI color codes for output
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    BLUE = "\033[34m"
    GRAY = "\033[90m"


def print_success(message: str) -> None:
    """Print success message in green."""
    print(f"{Colors.GREEN}✓{Colors.RESET} {message}")


def print_error(message: str) -> None:
    """Print error message in red."""
    print(f"{Colors.RED}✗{Colors.RESET} {message}", file=sys.stderr)


def print_info(message: str) -> None:
    """Print info message in blue."""
    print(f"{Colors.BLUE}ℹ{Colors.RESET} {message}")


def print_warning(message: str) -> None:
    """Print warning message in yellow."""
    print(f"{Colors.YELLOW}⚠{Colors.RESET} {message}")


# ============================================================================
# Phase 3: Switch Commands (T012-T016)
# ============================================================================


async def cmd_switch(args: argparse.Namespace) -> int:
    """Switch to a project.

    Args:
        args: Parsed arguments with 'project' field

    Returns:
        0 on success, 1 on error
    """
    project_name = args.project
    no_launch = args.no_launch if hasattr(args, 'no_launch') else False

    try:
        manager = ProjectManager()

        # Verify project exists
        try:
            project = await manager.get_project(project_name)
        except FileNotFoundError:
            print_error(f"Project '{project_name}' not found")
            print_info(f"Use 'i3pm list' to see available projects")
            return 1

        # Switch to project
        print_info(f"Switching to project: {project.display_name or project.name}")
        success, elapsed_ms, error_msg = await manager.switch_to_project(
            project_name, no_launch=no_launch
        )

        if success:
            print_success(f"Switched to '{project.display_name or project.name}' ({elapsed_ms:.0f}ms)")
            if no_launch:
                print_info("Auto-launch disabled")
            return 0
        else:
            print_error(f"Failed to switch: {error_msg}")
            return 1

    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return 1


async def cmd_current(args: argparse.Namespace) -> int:
    """Show current active project.

    Args:
        args: Parsed arguments

    Returns:
        0 on success, 1 on error
    """
    try:
        manager = ProjectManager()

        # Get current project
        current = await manager.get_current_project()

        if current:
            # Get project details
            try:
                project = await manager.get_project(current)
                window_count = await manager.get_project_window_count(current)

                print(f"{Colors.BOLD}{project.display_name or project.name}{Colors.RESET}")
                print(f"  Name: {project.name}")
                print(f"  Directory: {project.directory}")
                if project.icon:
                    print(f"  Icon: {project.icon}")
                print(f"  Windows: {window_count}")
                print(f"  Scoped classes: {', '.join(project.scoped_classes)}")

            except FileNotFoundError:
                # Project exists in daemon but not in config
                print(f"{Colors.BOLD}{current}{Colors.RESET}")
                print_warning(f"Project config not found for '{current}'")

            return 0
        else:
            print_info("No active project (global mode)")
            return 0

    except DaemonError as e:
        print_error(f"Daemon error: {e}")
        print_info("Is the i3-project-event-listener daemon running?")
        return 1
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return 1


async def cmd_clear(args: argparse.Namespace) -> int:
    """Clear active project (return to global mode).

    Args:
        args: Parsed arguments

    Returns:
        0 on success, 1 on error
    """
    try:
        manager = ProjectManager()

        # Check if there's an active project
        current = await manager.get_current_project()

        if not current:
            print_info("Already in global mode")
            return 0

        # Clear project
        print_info(f"Clearing active project: {current}")
        success, elapsed_ms, error_msg = await manager.clear_project()

        if success:
            print_success(f"Returned to global mode ({elapsed_ms:.0f}ms)")
            return 0
        else:
            print_error(f"Failed to clear project: {error_msg}")
            return 1

    except DaemonError as e:
        print_error(f"Daemon error: {e}")
        print_info("Is the i3-project-event-listener daemon running?")
        return 1
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return 1


# ============================================================================
# Phase 4-5: CRUD Commands (T021-T029) - To Be Implemented
# ============================================================================


async def cmd_list(args: argparse.Namespace) -> int:
    """List all projects.

    Args:
        args: Parsed arguments

    Returns:
        0 on success, 1 on error
    """
    try:
        manager = ProjectManager()

        # Get all projects
        projects = await manager.list_projects(sort_by=args.sort if hasattr(args, 'sort') else "modified")

        if not projects:
            print_info("No projects found")
            print_info(f"Create one with: i3pm create <name> <directory>")
            return 0

        # Get current project for highlighting
        try:
            current = await manager.get_current_project()
        except:
            current = None

        # Print projects
        print(f"{Colors.BOLD}Projects:{Colors.RESET}")
        for project in projects:
            is_current = project.name == current
            marker = f"{Colors.GREEN}●{Colors.RESET}" if is_current else f"{Colors.GRAY}○{Colors.RESET}"
            icon = f"{project.icon} " if project.icon else ""
            name = f"{Colors.BOLD}{project.display_name or project.name}{Colors.RESET}" if is_current else (project.display_name or project.name)

            print(f"  {marker} {icon}{name}")
            print(f"     {Colors.GRAY}{project.directory}{Colors.RESET}")

        return 0

    except Exception as e:
        print_error(f"Error listing projects: {e}")
        return 1


async def cmd_create(args: argparse.Namespace) -> int:
    """Create a new project.

    Args:
        args: Parsed arguments with name, directory, and optional fields

    Returns:
        0 on success, 1 on error
    """
    # Validate required arguments
    if not args.name:
        print_error("Project name is required")
        print_info("Usage: i3pm create <name> <directory> [options]")
        return 1

    if not args.directory:
        print_error("Project directory is required")
        print_info("Usage: i3pm create <name> <directory> [options]")
        return 1

    try:
        manager = ProjectManager()

        # Validate directory exists
        directory = Path(args.directory).resolve()
        if not directory.exists():
            print_error(f"Directory does not exist: {directory}")
            print_info(f"Create it first with: mkdir -p {directory}")
            return 1

        if not directory.is_dir():
            print_error(f"Path is not a directory: {directory}")
            return 1

        # Create project
        print_info(f"Creating project: {args.name}")

        project = await manager.create_project(
            name=args.name,
            directory=directory,
            display_name=args.display_name if hasattr(args, 'display_name') and args.display_name else args.name,
            icon=args.icon if hasattr(args, 'icon') and args.icon else "📁",
            scoped_classes=args.scoped_classes.split(',') if hasattr(args, 'scoped_classes') and args.scoped_classes else ["Ghostty", "Code"],
        )

        print_success(f"Created project '{project.display_name or project.name}'")
        print_info(f"  Name: {project.name}")
        print_info(f"  Directory: {project.directory}")
        print_info(f"  Icon: {project.icon}")
        print_info(f"  Scoped classes: {', '.join(project.scoped_classes)}")
        print_info(f"Switch to it with: i3pm switch {project.name}")

        return 0

    except ValueError as e:
        print_error(f"Validation error: {e}")
        return 1
    except Exception as e:
        print_error(f"Failed to create project: {e}")
        return 1


async def cmd_show(args: argparse.Namespace) -> int:
    """Show detailed project information.

    Args:
        args: Parsed arguments with project name

    Returns:
        0 on success, 1 on error
    """
    if not args.project:
        print_error("Project name is required")
        print_info("Usage: i3pm show <project>")
        return 1

    try:
        manager = ProjectManager()

        # Load project
        try:
            project = await manager.get_project(args.project)
        except FileNotFoundError:
            print_error(f"Project '{args.project}' not found")
            print_info("Use 'i3pm list' to see available projects")
            return 1

        # Get additional info
        try:
            current = await manager.get_current_project()
            is_active = current == project.name
        except:
            is_active = False

        try:
            window_count = await manager.get_project_window_count(project.name)
        except:
            window_count = 0

        # Display project details
        status = f"{Colors.GREEN}ACTIVE{Colors.RESET}" if is_active else f"{Colors.GRAY}INACTIVE{Colors.RESET}"
        print(f"\n{Colors.BOLD}{project.icon} {project.display_name or project.name}{Colors.RESET} [{status}]")
        print(f"{Colors.GRAY}{'─' * 60}{Colors.RESET}")

        print(f"\n{Colors.BOLD}Basic Information:{Colors.RESET}")
        print(f"  Name: {project.name}")
        print(f"  Display Name: {project.display_name or project.name}")
        print(f"  Icon: {project.icon}")
        print(f"  Directory: {project.directory}")

        print(f"\n{Colors.BOLD}Runtime Information:{Colors.RESET}")
        print(f"  Status: {status}")
        print(f"  Open Windows: {window_count}")

        print(f"\n{Colors.BOLD}Configuration:{Colors.RESET}")
        print(f"  Scoped Classes: {', '.join(project.scoped_classes)}")

        if project.workspace_preferences:
            print(f"\n{Colors.BOLD}Workspace Preferences:{Colors.RESET}")
            for ws_num, output_role in sorted(project.workspace_preferences.items()):
                print(f"  Workspace {ws_num}: {output_role}")

        if project.auto_launch:
            print(f"\n{Colors.BOLD}Auto-Launch Applications:{Colors.RESET}")
            for app in project.auto_launch:
                ws_info = f" (workspace {app.workspace})" if app.workspace else ""
                print(f"  • {app.command}{ws_info}")

        if project.saved_layouts:
            print(f"\n{Colors.BOLD}Saved Layouts:{Colors.RESET}")
            for layout in project.saved_layouts:
                print(f"  • {layout}")

        print(f"\n{Colors.BOLD}Timestamps:{Colors.RESET}")
        print(f"  Created: {project.created_at.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"  Modified: {project.modified_at.strftime('%Y-%m-%d %H:%M:%S')}")

        print(f"\n{Colors.BOLD}File Location:{Colors.RESET}")
        config_file = Path.home() / ".config/i3/projects" / f"{project.name}.json"
        print(f"  {config_file}")

        print()  # Empty line at end

        return 0

    except Exception as e:
        print_error(f"Error showing project: {e}")
        return 1


async def cmd_edit(args: argparse.Namespace) -> int:
    """Edit project configuration.

    Args:
        args: Parsed arguments with project name and optional update fields

    Returns:
        0 on success, 1 on error
    """
    if not args.project:
        print_error("Project name is required")
        print_info("Usage: i3pm edit <project> [--display-name NAME] [--icon ICON] [--scoped-classes CLASS1,CLASS2]")
        return 1

    try:
        manager = ProjectManager()

        # Verify project exists
        try:
            project = await manager.get_project(args.project)
        except FileNotFoundError:
            print_error(f"Project '{args.project}' not found")
            print_info("Use 'i3pm list' to see available projects")
            return 1

        # Collect updates
        updates = {}

        if hasattr(args, 'display_name') and args.display_name:
            updates['display_name'] = args.display_name

        if hasattr(args, 'icon') and args.icon:
            updates['icon'] = args.icon

        if hasattr(args, 'scoped_classes') and args.scoped_classes:
            updates['scoped_classes'] = args.scoped_classes.split(',')

        if hasattr(args, 'directory') and args.directory:
            directory = Path(args.directory).resolve()
            if not directory.exists() or not directory.is_dir():
                print_error(f"Invalid directory: {directory}")
                return 1
            updates['directory'] = directory

        # Check if any updates provided
        if not updates:
            print_error("No updates specified")
            print_info("Usage: i3pm edit <project> [--display-name NAME] [--icon ICON] [--scoped-classes CLASS1,CLASS2]")
            print_info("Example: i3pm edit nixos --display-name 'NixOS Config' --icon '❄️'")
            return 1

        # Apply updates
        print_info(f"Updating project: {args.project}")
        updated_project = await manager.update_project(args.project, **updates)

        print_success(f"Updated project '{updated_project.display_name or updated_project.name}'")

        # Show what was updated
        for key, value in updates.items():
            if key == 'scoped_classes':
                value_str = ', '.join(value)
            else:
                value_str = str(value)
            print_info(f"  {key}: {value_str}")

        return 0

    except ValueError as e:
        print_error(f"Validation error: {e}")
        return 1
    except Exception as e:
        print_error(f"Failed to update project: {e}")
        return 1


async def cmd_delete(args: argparse.Namespace) -> int:
    """Delete a project.

    Args:
        args: Parsed arguments with project name and optional flags

    Returns:
        0 on success, 1 on error
    """
    if not args.project:
        print_error("Project name is required")
        print_info("Usage: i3pm delete <project> [--force] [--keep-layouts]")
        return 1

    try:
        manager = ProjectManager()

        # Verify project exists
        try:
            project = await manager.get_project(args.project)
        except FileNotFoundError:
            print_error(f"Project '{args.project}' not found")
            print_info("Use 'i3pm list' to see available projects")
            return 1

        # Check if project is currently active
        try:
            current = await manager.get_current_project()
            if current == args.project:
                print_warning(f"Project '{args.project}' is currently active")
                print_info("Consider switching to another project first: i3pm switch <project>")
                print_info("Or clear the active project: i3pm clear")

                if not (hasattr(args, 'force') and args.force):
                    print_error("Use --force to delete active project")
                    return 1
        except:
            pass  # Daemon not available, continue

        # Confirm deletion (unless --force)
        if not (hasattr(args, 'force') and args.force):
            print_warning(f"About to delete project: {project.display_name or project.name}")
            print_info(f"  Name: {project.name}")
            print_info(f"  Directory: {project.directory}")

            if project.saved_layouts:
                if hasattr(args, 'keep_layouts') and args.keep_layouts:
                    print_info(f"  Saved layouts: {len(project.saved_layouts)} (will be kept)")
                else:
                    print_info(f"  Saved layouts: {len(project.saved_layouts)} (will be deleted)")

            # Simple confirmation
            import sys
            if sys.stdin.isatty():
                response = input(f"\n{Colors.YELLOW}Delete this project? [y/N]:{Colors.RESET} ")
                if response.lower() not in ['y', 'yes']:
                    print_info("Deletion cancelled")
                    return 0
            else:
                # Non-interactive mode, require --force
                print_error("Cannot confirm deletion in non-interactive mode")
                print_info("Use --force to delete without confirmation")
                return 1

        # Delete project
        print_info(f"Deleting project: {args.project}")

        delete_layouts = not (hasattr(args, 'keep_layouts') and args.keep_layouts)
        await manager.delete_project(args.project, force=True, delete_layouts=delete_layouts)

        print_success(f"Deleted project '{project.display_name or project.name}'")

        if delete_layouts and project.saved_layouts:
            print_info(f"  Deleted {len(project.saved_layouts)} saved layout(s)")

        return 0

    except Exception as e:
        print_error(f"Failed to delete project: {e}")
        return 1


async def cmd_validate(args: argparse.Namespace) -> int:
    """Validate project configuration(s).

    Args:
        args: Parsed arguments with optional project name and flags

    Returns:
        0 if validation passes, 1 if validation fails
    """
    from ..validators.project_validator import ProjectValidator
    import json

    try:
        validator = ProjectValidator()
        manager = ProjectManager()

        # Determine which projects to validate
        if hasattr(args, 'project') and args.project:
            # Validate single project
            projects_to_validate = [args.project]
        else:
            # Validate all projects
            all_projects = await manager.list_projects()
            projects_to_validate = [p.name for p in all_projects]

        # Validate each project
        all_errors = []
        all_warnings = []
        validated_count = 0

        for project_name in projects_to_validate:
            try:
                # Load project config file
                config_file = manager.config_dir / f"{project_name}.json"

                if not config_file.exists():
                    print_error(f"Project config not found: {config_file}")
                    all_errors.append({
                        "project": project_name,
                        "path": str(config_file),
                        "message": "Configuration file not found"
                    })
                    continue

                # Validate file
                is_valid, errors = validator.validate_file(config_file)

                # Collect errors (warnings not yet implemented in validator)
                for error in errors:
                    all_errors.append({
                        "project": project_name,
                        "path": error.path,
                        "message": error.message
                    })

                validated_count += 1

            except Exception as e:
                print_error(f"Failed to validate project '{project_name}': {e}")
                all_errors.append({
                    "project": project_name,
                    "path": "unknown",
                    "message": str(e)
                })

        # Output results
        if hasattr(args, 'json') and args.json:
            # JSON output
            result = {
                "validated": validated_count,
                "errors": all_errors,
                "warnings": all_warnings,
                "passed": len(all_errors) == 0
            }
            print(json.dumps(result, indent=2))
        else:
            # Rich formatted output
            if len(all_errors) == 0 and len(all_warnings) == 0:
                print_success(f"Validated {validated_count} project(s) - All checks passed ✓")
                return 0

            # Print validation summary
            print(f"\n{Colors.BOLD}Validation Results:{Colors.RESET}")
            print(f"  Projects validated: {validated_count}")
            print(f"  Errors: {len(all_errors)}")
            print(f"  Warnings: {len(all_warnings)}\n")

            # Print errors
            if all_errors:
                print(f"{Colors.RED}{Colors.BOLD}Errors:{Colors.RESET}")
                for error in all_errors:
                    print(f"  {Colors.RED}✗{Colors.RESET} {error['project']}: {error['path']}")
                    print(f"    {error['message']}")
                print()

            # Print warnings
            if all_warnings:
                print(f"{Colors.YELLOW}{Colors.BOLD}Warnings:{Colors.RESET}")
                for warning in all_warnings:
                    print(f"  {Colors.YELLOW}⚠{Colors.RESET} {warning['project']}: {warning['path']}")
                    print(f"    {warning['message']}")
                print()

        # Return exit code based on errors
        if all_errors:
            print_error(f"Validation failed with {len(all_errors)} error(s)")
            return 1
        elif all_warnings:
            print_warning(f"Validation passed with {len(all_warnings)} warning(s)")
            return 0
        else:
            return 0

    except Exception as e:
        print_error(f"Validation failed: {e}")
        return 1


# ============================================================================
# Phase 4: Application Classification Commands (T019)
# ============================================================================


async def cmd_app_classes(args: argparse.Namespace) -> int:
    """Manage application classifications (scoped vs global).

    Args:
        args: Parsed arguments with subcommand and options

    Returns:
        0 on success, 1 on error
    """
    from ..core.config import AppClassConfig
    import json

    try:
        config = AppClassConfig()
        config.load()

        # Handle subcommands
        subcommand = getattr(args, 'app_classes_command', None)

        if subcommand == 'list' or subcommand is None:
            # List all classifications
            if hasattr(args, 'json') and args.json:
                result = {
                    "scoped": config.get_all_scoped(),
                    "global": config.get_all_global(),
                    "patterns": config.class_patterns
                }
                print(json.dumps(result, indent=2))
            else:
                # Rich formatted output
                print(f"\n{Colors.BOLD}Application Classifications:{Colors.RESET}\n")

                # Scoped classes
                print(f"{Colors.BLUE}{Colors.BOLD}Scoped Classes:{Colors.RESET} (project-specific windows)")
                if config.scoped_classes:
                    for cls in config.get_all_scoped():
                        print(f"  {Colors.BLUE}●{Colors.RESET} {cls}")
                else:
                    print(f"  {Colors.DIM}(none){Colors.RESET}")

                print()

                # Global classes
                print(f"{Colors.GREEN}{Colors.BOLD}Global Classes:{Colors.RESET} (visible in all projects)")
                if config.global_classes:
                    for cls in config.get_all_global():
                        print(f"  {Colors.GREEN}●{Colors.RESET} {cls}")
                else:
                    print(f"  {Colors.DIM}(none){Colors.RESET}")

                print()

                # Patterns
                if config.class_patterns:
                    print(f"{Colors.YELLOW}{Colors.BOLD}Patterns:{Colors.RESET}")
                    for pattern, classification in config.class_patterns.items():
                        color = Colors.BLUE if classification == "scoped" else Colors.GREEN
                        print(f"  {color}●{Colors.RESET} {pattern}* → {classification}")
                    print()

            return 0

        elif subcommand == 'add-scoped':
            # Add scoped class
            class_name = args.class_name
            try:
                config.add_scoped_class(class_name)
                config.save()
                print_success(f"Added '{class_name}' to scoped classes")
                print_info("Windows of this class will now be project-specific")
                return 0
            except ValueError as e:
                print_error(str(e))
                return 1

        elif subcommand == 'add-global':
            # Add global class
            class_name = args.class_name
            try:
                config.add_global_class(class_name)
                config.save()
                print_success(f"Added '{class_name}' to global classes")
                print_info("Windows of this class will now be visible in all projects")
                return 0
            except ValueError as e:
                print_error(str(e))
                return 1

        elif subcommand == 'remove':
            # Remove class
            class_name = args.class_name
            if config.remove_class(class_name):
                config.save()
                print_success(f"Removed '{class_name}' from classifications")
                return 0
            else:
                print_error(f"Class '{class_name}' not found in any classification")
                return 1

        elif subcommand == 'check':
            # Check classification
            class_name = args.class_name
            classification = config.get_classification(class_name)

            if hasattr(args, 'json') and args.json:
                result = {
                    "class": class_name,
                    "classification": classification,
                    "is_scoped": classification == "scoped",
                    "is_global": classification == "global"
                }
                print(json.dumps(result, indent=2))
            else:
                if classification == "scoped":
                    print(f"{Colors.BLUE}●{Colors.RESET} {class_name}: {Colors.BOLD}SCOPED{Colors.RESET}")
                    print_info("Windows will be project-specific")
                elif classification == "global":
                    print(f"{Colors.GREEN}●{Colors.RESET} {class_name}: {Colors.BOLD}GLOBAL{Colors.RESET}")
                    print_info("Windows will be visible in all projects")
                else:
                    print(f"{Colors.YELLOW}●{Colors.RESET} {class_name}: {Colors.BOLD}UNKNOWN{Colors.RESET}")
                    print_info("No explicit classification (defaults to scoped)")

            return 0

        else:
            print_error(f"Unknown subcommand: {subcommand}")
            return 1

    except Exception as e:
        print_error(f"Failed to manage app classifications: {e}")
        return 1


# ============================================================================
# Phase 7: Monitoring Commands (T041-T044)
# ============================================================================


async def cmd_status(args: argparse.Namespace) -> int:
    """Show daemon status and diagnostics.

    Args:
        args: Parsed arguments with optional --json flag

    Returns:
        0 on success, 1 on error
    """
    try:
        # Connect to daemon
        daemon = DaemonClient()
        await daemon.connect()

        # Get status
        status = await daemon.get_status()

        # Display status
        if hasattr(args, 'json') and args.json:
            import json
            print(json.dumps(status, indent=2))
            return 0

        # Rich formatted output
        print(f"\n{Colors.BOLD}i3 Project Daemon Status{Colors.RESET}")
        print(f"{Colors.GRAY}{'─' * 60}{Colors.RESET}")

        # Connection status
        daemon_status = f"{Colors.GREEN}RUNNING{Colors.RESET}"
        print(f"\n{Colors.BOLD}Connection:{Colors.RESET}")
        print(f"  Status: {daemon_status}")
        print(f"  Socket: ~/.cache/i3-project/daemon.sock")

        # Active project
        active_project = status.get("active_project")
        if active_project:
            project_display = f"{Colors.GREEN}{active_project}{Colors.RESET}"
        else:
            project_display = f"{Colors.GRAY}None (global mode){Colors.RESET}"

        print(f"\n{Colors.BOLD}Active Project:{Colors.RESET}")
        print(f"  {project_display}")

        # Window counts
        tracked_windows = status.get("tracked_windows", 0)
        total_windows = status.get("total_windows", 0)

        print(f"\n{Colors.BOLD}Windows:{Colors.RESET}")
        print(f"  Tracked: {tracked_windows}")
        print(f"  Total: {total_windows}")

        # Event statistics
        event_count = status.get("event_count", 0)
        event_rate = status.get("event_rate", 0.0)

        print(f"\n{Colors.BOLD}Events:{Colors.RESET}")
        print(f"  Total: {event_count}")
        print(f"  Rate: {event_rate:.1f} events/sec")

        # Uptime
        uptime_seconds = status.get("uptime_seconds", 0)
        uptime_str = f"{uptime_seconds // 3600}h {(uptime_seconds % 3600) // 60}m {uptime_seconds % 60}s"

        print(f"\n{Colors.BOLD}Runtime:{Colors.RESET}")
        print(f"  Uptime: {uptime_str}")

        # Errors
        error_count = status.get("error_count", 0)
        if error_count > 0:
            print(f"\n{Colors.BOLD}Errors:{Colors.RESET}")
            print(f"  {Colors.RED}Count: {error_count}{Colors.RESET}")
            print_info("Run 'i3pm events --type=error' to see error details")

        print()  # Empty line at end

        await daemon.close()
        return 0

    except DaemonError as e:
        print_error(f"Daemon is not running")
        print_info(f"Error: {e}")
        print_info("Start the daemon with: systemctl --user start i3-project-event-listener")
        print_info("Check daemon logs with: journalctl --user -u i3-project-event-listener -f")
        return 1
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return 1


async def cmd_events(args: argparse.Namespace) -> int:
    """Show daemon events.

    Args:
        args: Parsed arguments with limit, type, follow, json flags

    Returns:
        0 on success, 1 on error
    """
    try:
        # Connect to daemon
        daemon = DaemonClient()
        await daemon.connect()

        # Get limit and type filters
        limit = args.limit if hasattr(args, 'limit') and args.limit else 20
        event_type = args.type if hasattr(args, 'type') and args.type else None
        follow = args.follow if hasattr(args, 'follow') and args.follow else False
        json_output = args.json if hasattr(args, 'json') and args.json else False

        if follow:
            # Stream events continuously
            print_info(f"Streaming events... (Ctrl+C to stop)")
            if event_type:
                print_info(f"Filter: {event_type}")
            print()

            last_event_id = 0

            try:
                while True:
                    # Poll for new events
                    events = await daemon.get_events(limit=100, event_type=event_type, since_id=last_event_id)

                    for event in events:
                        if json_output:
                            import json
                            print(json.dumps(event))
                        else:
                            # Format event
                            timestamp = event.get("timestamp", "")
                            evt_type = event.get("type", "unknown")
                            details = event.get("details", {})

                            # Color code by type
                            type_color = {
                                "window": Colors.BLUE,
                                "workspace": Colors.GREEN,
                                "output": Colors.YELLOW,
                                "tick": Colors.GRAY,
                                "error": Colors.RED,
                            }.get(evt_type, Colors.RESET)

                            print(f"{Colors.GRAY}{timestamp}{Colors.RESET} {type_color}{evt_type:10}{Colors.RESET} {details}")

                        last_event_id = max(last_event_id, event.get("id", 0))

                    # Sleep briefly before next poll
                    await asyncio.sleep(0.1)

            except KeyboardInterrupt:
                print()
                print_info("Stopped event stream")
                await daemon.close()
                return 0

        else:
            # Get historical events
            events_response = await daemon.get_events(limit=limit, event_type=event_type)

            # Extract events array from response
            if isinstance(events_response, dict) and "events" in events_response:
                events = events_response["events"]
            elif isinstance(events_response, list):
                events = events_response
            else:
                events = []

            if json_output:
                import json
                print(json.dumps(events_response, indent=2))
                await daemon.close()
                return 0

            # Display events
            if not events:
                print_info("No events found")
                if event_type:
                    print_info(f"Filter: {event_type}")
                await daemon.close()
                return 0

            print(f"\n{Colors.BOLD}Recent Events{Colors.RESET}")
            if event_type:
                print(f"{Colors.GRAY}Filter: {event_type}{Colors.RESET}")
            print(f"{Colors.GRAY}{'─' * 80}{Colors.RESET}\n")

            # Print header
            print(f"{Colors.BOLD}{'TIME':<12} {'TYPE':<20} {'DETAILS'}{Colors.RESET}")
            print(f"{Colors.GRAY}{'─' * 90}{Colors.RESET}")

            # Print events
            for event in events:
                timestamp = event.get("timestamp", "")[:12]  # Truncate timestamp
                evt_type = event.get("event_type", "unknown")

                # Format details based on event type
                if evt_type.startswith("window::"):
                    action = evt_type.split("::")[-1]
                    win_class = event.get("window_class", "unknown")
                    detail_str = f"{action} - {win_class}"
                    base_type = "window"
                elif evt_type.startswith("workspace::"):
                    action = evt_type.split("::")[-1]
                    ws_name = event.get("workspace_name", "?")
                    detail_str = f"{action} - {ws_name}"
                    base_type = "workspace"
                elif evt_type == "tick":
                    payload = event.get("tick_payload", "")
                    project = event.get("project_name", "")
                    detail_str = f"{payload} (project: {project})" if project else payload
                    base_type = "tick"
                elif evt_type.startswith("output::"):
                    action = evt_type.split("::")[-1]
                    detail_str = action
                    base_type = "output"
                else:
                    detail_str = evt_type
                    base_type = evt_type

                # Color code by type
                type_color = {
                    "window": Colors.BLUE,
                    "workspace": Colors.GREEN,
                    "output": Colors.YELLOW,
                    "tick": Colors.GRAY,
                    "error": Colors.RED,
                }.get(base_type, Colors.RESET)

                print(f"{Colors.GRAY}{timestamp:<12}{Colors.RESET} {type_color}{evt_type:<20}{Colors.RESET} {detail_str}")

            print(f"\n{Colors.GRAY}Showing {len(events)} event(s){Colors.RESET}")
            print_info(f"Use --limit=N to show more events")
            print_info(f"Use --follow to stream events in real-time")
            print()

        await daemon.close()
        return 0

    except DaemonError as e:
        print_error(f"Daemon is not running")
        print_info(f"Error: {e}")
        print_info("Start the daemon with: systemctl --user start i3-project-event-listener")
        return 1
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return 1


async def cmd_windows(args: argparse.Namespace) -> int:
    """Show tracked windows.

    Args:
        args: Parsed arguments with project, all, json flags

    Returns:
        0 on success, 1 on error
    """
    try:
        # Determine if we need i3 client or daemon client
        show_all = args.all if hasattr(args, 'all') and args.all else False
        project_filter = args.project if hasattr(args, 'project') and args.project else None
        json_output = args.json if hasattr(args, 'json') and args.json else False

        if show_all:
            # Use i3 client to get all windows
            i3 = I3Client()
            await i3.connect()

            tree = await i3.get_tree()
            windows = await i3.get_all_windows(tree)

            await i3.close()
        else:
            # Use daemon client to get tracked windows
            daemon = DaemonClient()
            await daemon.connect()

            windows_response = await daemon.get_windows(project=project_filter)

            await daemon.close()

            # Extract windows array from response
            if isinstance(windows_response, dict) and "windows" in windows_response:
                windows = windows_response["windows"]
            elif isinstance(windows_response, list):
                windows = windows_response
            else:
                windows = []

        if json_output:
            import json
            print(json.dumps([{
                "id": w.get("id") or w.get("window_id"),
                "class": w.get("class") or w.get("window_class"),
                "title": w.get("title") or w.get("window_title"),
                "workspace": w.get("workspace") or w.get("workspace_name"),
                "marks": w.get("marks", []),
            } for w in windows], indent=2))
            return 0

        # Display windows
        if not windows:
            if project_filter:
                print_info(f"No windows found for project: {project_filter}")
            else:
                print_info("No tracked windows found")
            return 0

        print(f"\n{Colors.BOLD}Windows{Colors.RESET}")
        if project_filter:
            print(f"{Colors.GRAY}Project: {project_filter}{Colors.RESET}")
        if show_all:
            print(f"{Colors.GRAY}Showing all windows{Colors.RESET}")
        else:
            print(f"{Colors.GRAY}Showing tracked windows only{Colors.RESET}")
        print(f"{Colors.GRAY}{'─' * 100}{Colors.RESET}\n")

        # Print header
        print(f"{Colors.BOLD}{'ID':<10} {'CLASS':<15} {'WORKSPACE':<10} {'MARKS':<20} {'TITLE'}{Colors.RESET}")
        print(f"{Colors.GRAY}{'─' * 100}{Colors.RESET}")

        # Print windows
        for window in windows:
            # Handle both daemon format (window_id, window_class) and i3 format (id, class)
            win_id = str(window.get("window_id") or window.get("id", ""))[:8]
            win_class = (window.get("window_class") or window.get("class", "unknown"))[:14]
            workspace_name = window.get("workspace_name") or window.get("workspace", "?")
            workspace = f"WS{workspace_name}" if not workspace_name.startswith("WS") else workspace_name
            marks = window.get("marks", [])
            marks_str = ", ".join(marks)[:18] if marks else ""
            title = (window.get("window_title") or window.get("title", ""))[:40]

            # Highlight project-marked windows
            if any(m.startswith("project:") for m in marks):
                win_class = f"{Colors.GREEN}{win_class}{Colors.RESET}"

            print(f"{win_id:<10} {win_class:<15} {workspace:<10} {marks_str:<20} {title}")

        print(f"\n{Colors.GRAY}Showing {len(windows)} window(s){Colors.RESET}")
        print_info(f"Use --all to show all windows (not just tracked)")
        print_info(f"Use --project=NAME to filter by project")
        print()

        return 0

    except (DaemonError, I3Error) as e:
        print_error(f"Error querying windows: {e}")
        if isinstance(e, DaemonError):
            print_info("Is the daemon running? Check with: systemctl --user status i3-project-event-listener")
        return 1
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return 1


async def cmd_monitor(args: argparse.Namespace) -> int:
    """Launch TUI monitor dashboard.

    Args:
        args: Parsed arguments with optional mode

    Returns:
        0 on success, 1 on error
    """
    try:
        # Import TUI app
        from ..tui.app import I3PMApp
        from ..tui.screens.monitor import MonitorScreen

        # Create app
        app = I3PMApp()

        # If mode specified, navigate to that tab
        mode = args.mode if hasattr(args, 'mode') and args.mode else None

        # Push monitor screen directly
        async def on_mount():
            screen = MonitorScreen()
            await app.push_screen(screen)

            # Navigate to specific tab if requested
            if mode:
                tab_map = {
                    "live": 0,
                    "events": 1,
                    "history": 2,
                    "tree": 3,
                }
                tab_index = tab_map.get(mode)
                if tab_index is not None:
                    # TODO: Switch to tab (implement in MonitorScreen)
                    pass

        # Override on_mount to push monitor screen
        app.on_mount = on_mount

        # Run TUI
        await app.run_async()

        return 0

    except ImportError as e:
        print_error(f"TUI not available: {e}")
        print_info("The monitor dashboard requires Textual TUI framework")
        return 1
    except Exception as e:
        print_error(f"Failed to launch monitor: {e}")
        return 1


# ============================================================================
# CLI Entry Point
# ============================================================================


def cli_main() -> int:
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        prog="i3pm",
        description="i3 Project Manager - Unified CLI/TUI for i3 window manager projects",
        epilog="For more information, see: /etc/nixos/specs/019-re-explore-and/"
    )

    parser.add_argument(
        "--version",
        action="version",
        version="i3pm 0.1.0 (Phase 3)"
    )

    # Subcommands
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # ========================================================================
    # Phase 3: Switch Commands
    # ========================================================================

    # i3pm switch <project>
    parser_switch = subparsers.add_parser(
        "switch",
        help="Switch to a project",
        description="Switch to a project (shows project windows, hides others)"
    )
    parser_switch.add_argument(
        "project",
        help="Project name to switch to"
    )
    parser_switch.add_argument(
        "--no-launch",
        action="store_true",
        help="Don't auto-launch applications"
    )

    # i3pm current
    parser_current = subparsers.add_parser(
        "current",
        help="Show current active project",
        description="Display information about the currently active project"
    )

    # i3pm clear
    parser_clear = subparsers.add_parser(
        "clear",
        help="Clear active project (global mode)",
        description="Return to global mode (no active project)"
    )

    # ========================================================================
    # Phase 4-5: CRUD Commands
    # ========================================================================

    # i3pm list
    parser_list = subparsers.add_parser(
        "list",
        help="List all projects",
        description="List all available projects"
    )
    parser_list.add_argument(
        "--sort",
        choices=["name", "modified", "directory"],
        default="modified",
        help="Sort order (default: modified)"
    )

    # i3pm create
    parser_create = subparsers.add_parser(
        "create",
        help="Create a new project",
        description="Create a new project with specified configuration"
    )
    parser_create.add_argument("name", help="Project name (alphanumeric, dashes, underscores)")
    parser_create.add_argument("directory", help="Project directory path")
    parser_create.add_argument(
        "--display-name",
        help="Display name (defaults to capitalized name)"
    )
    parser_create.add_argument(
        "--icon",
        default="📁",
        help="Project icon/emoji (default: 📁)"
    )
    parser_create.add_argument(
        "--scoped-classes",
        help="Comma-separated list of window classes (e.g., 'Ghostty,Code')"
    )

    # i3pm show
    parser_show = subparsers.add_parser(
        "show",
        help="Show project details",
        description="Display detailed information about a project"
    )
    parser_show.add_argument("project", help="Project name")

    # i3pm edit
    parser_edit = subparsers.add_parser(
        "edit",
        help="Edit project configuration",
        description="Update project configuration fields"
    )
    parser_edit.add_argument("project", help="Project name")
    parser_edit.add_argument(
        "--display-name",
        help="Update display name"
    )
    parser_edit.add_argument(
        "--icon",
        help="Update project icon/emoji"
    )
    parser_edit.add_argument(
        "--scoped-classes",
        help="Update scoped window classes (comma-separated)"
    )
    parser_edit.add_argument(
        "--directory",
        help="Update project directory path"
    )

    # i3pm delete
    parser_delete = subparsers.add_parser(
        "delete",
        help="Delete a project",
        description="Delete a project configuration file"
    )
    parser_delete.add_argument("project", help="Project name")
    parser_delete.add_argument(
        "--force",
        action="store_true",
        help="Skip confirmation prompt"
    )
    parser_delete.add_argument(
        "--keep-layouts",
        action="store_true",
        help="Keep saved layout files"
    )

    # i3pm validate
    parser_validate = subparsers.add_parser(
        "validate",
        help="Validate project configuration(s)",
        description="Validate project configurations against schema and filesystem requirements"
    )
    parser_validate.add_argument(
        "project",
        nargs="?",
        help="Project name to validate (validates all if omitted)"
    )
    parser_validate.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # ========================================================================
    # Phase 4: Application Classification Commands
    # ========================================================================

    # i3pm app-classes
    parser_app_classes = subparsers.add_parser(
        "app-classes",
        help="Manage application classifications",
        description="Manage which window classes are scoped (project-specific) or global (visible in all projects)"
    )

    # Create subparsers for app-classes subcommands
    app_classes_subparsers = parser_app_classes.add_subparsers(
        dest="app_classes_command",
        help="Subcommand"
    )

    # app-classes list
    parser_app_classes_list = app_classes_subparsers.add_parser(
        "list",
        help="List all application classifications"
    )
    parser_app_classes_list.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # app-classes add-scoped
    parser_app_classes_add_scoped = app_classes_subparsers.add_parser(
        "add-scoped",
        help="Add a window class to scoped list"
    )
    parser_app_classes_add_scoped.add_argument(
        "class_name",
        help="Window class name (e.g., Code, Ghostty)"
    )

    # app-classes add-global
    parser_app_classes_add_global = app_classes_subparsers.add_parser(
        "add-global",
        help="Add a window class to global list"
    )
    parser_app_classes_add_global.add_argument(
        "class_name",
        help="Window class name (e.g., firefox, chrome)"
    )

    # app-classes remove
    parser_app_classes_remove = app_classes_subparsers.add_parser(
        "remove",
        help="Remove a window class from all lists"
    )
    parser_app_classes_remove.add_argument(
        "class_name",
        help="Window class name to remove"
    )

    # app-classes check
    parser_app_classes_check = app_classes_subparsers.add_parser(
        "check",
        help="Check classification of a window class"
    )
    parser_app_classes_check.add_argument(
        "class_name",
        help="Window class name to check"
    )
    parser_app_classes_check.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # ========================================================================
    # Phase 7: Monitoring Commands
    # ========================================================================

    # i3pm status
    parser_status = subparsers.add_parser(
        "status",
        help="Show daemon status and diagnostics",
        description="Display daemon health, active project, and event statistics"
    )
    parser_status.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # i3pm events
    parser_events = subparsers.add_parser(
        "events",
        help="Show daemon events",
        description="Display recent daemon events or stream them in real-time"
    )
    parser_events.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Number of events to show (default: 20)"
    )
    parser_events.add_argument(
        "--type",
        choices=["window", "workspace", "output", "tick", "error"],
        help="Filter by event type"
    )
    parser_events.add_argument(
        "--follow", "-f",
        action="store_true",
        help="Stream events continuously (like tail -f)"
    )
    parser_events.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # i3pm windows
    parser_windows = subparsers.add_parser(
        "windows",
        help="Show tracked windows",
        description="List windows tracked by the project management system"
    )
    parser_windows.add_argument(
        "--project",
        help="Filter windows by project name"
    )
    parser_windows.add_argument(
        "--all",
        action="store_true",
        help="Show all windows, not just tracked ones"
    )
    parser_windows.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # i3pm monitor
    parser_monitor = subparsers.add_parser(
        "monitor",
        help="Launch TUI monitor dashboard",
        description="Open the interactive monitoring dashboard"
    )
    parser_monitor.add_argument(
        "mode",
        nargs="?",
        choices=["live", "events", "history", "tree"],
        help="Start in specific monitor mode"
    )

    # Parse arguments
    args = parser.parse_args()

    # No command = show help
    if not args.command:
        parser.print_help()
        return 0

    # Command routing
    command_handlers = {
        # Phase 3: Switch commands
        "switch": cmd_switch,
        "current": cmd_current,
        "clear": cmd_clear,
        "list": cmd_list,
        # Phase 5: CRUD commands
        "create": cmd_create,
        "show": cmd_show,
        "edit": cmd_edit,
        "delete": cmd_delete,
        "validate": cmd_validate,
        # Phase 4: App classification commands
        "app-classes": cmd_app_classes,
        # Phase 7: Monitoring commands
        "status": cmd_status,
        "events": cmd_events,
        "windows": cmd_windows,
        "monitor": cmd_monitor,
    }

    handler = command_handlers.get(args.command)
    if handler:
        # Run async handler
        return asyncio.run(handler(args))
    else:
        print_error(f"Unknown command: {args.command}")
        parser.print_help()
        return 1


if __name__ == "__main__":
    sys.exit(cli_main())
