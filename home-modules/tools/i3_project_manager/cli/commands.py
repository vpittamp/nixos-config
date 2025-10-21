"""CLI command handlers for i3pm.

Implements all CLI commands for i3 project management.
"""

import argparse
import asyncio
import sys
from pathlib import Path
from typing import Optional

try:
    import argcomplete
    ARGCOMPLETE_AVAILABLE = True
except ImportError:
    ARGCOMPLETE_AVAILABLE = False

from ..core.project import ProjectManager
from ..core.daemon_client import DaemonClient, DaemonError
from ..core.i3_client import I3Client, I3Error
from .logging_config import init_logging, get_global_logger


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


def print_error_with_remediation(error: str, remediation: str) -> None:
    """Print error with remediation steps.

    T090: Consistent error format following SC-036
    Format: "Error: <issue>. Remediation: <steps>"

    Args:
        error: Description of the error
        remediation: Steps to remediate the issue

    Examples:
        >>> print_error_with_remediation(
        ...     "Window not found: 12345",
        ...     "Use --click mode to select a visible window"
        ... )
    """
    print(f"{Colors.RED}✗ Error:{Colors.RESET} {error}", file=sys.stderr)
    print(f"{Colors.BLUE}  Remediation:{Colors.RESET} {remediation}", file=sys.stderr)


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
    from .output import OutputFormatter, format_switch_result_json

    project_name = args.project
    no_launch = args.no_launch if hasattr(args, 'no_launch') else False
    json_mode = getattr(args, 'json', False)

    fmt = OutputFormatter(json_mode=json_mode)

    try:
        manager = ProjectManager()

        # Verify project exists
        try:
            project = await manager.get_project(project_name)
        except FileNotFoundError:
            fmt.print_error(
                f"Project '{project_name}' not found",
                "Use 'i3pm list' to see available projects"
            )
            fmt.output()
            return 1

        # Switch to project
        fmt.print_info(f"Switching to project: {project.display_name or project.name}")
        success, elapsed_ms, error_msg = await manager.switch_to_project(
            project_name, no_launch=no_launch
        )

        if success:
            fmt.print_success(f"Switched to '{project.display_name or project.name}' ({elapsed_ms:.0f}ms)")
            if no_launch:
                fmt.print_info("Auto-launch disabled")

            fmt.output(format_switch_result_json(
                project_name=project.display_name or project.name,
                success=True,
                elapsed_ms=elapsed_ms,
                no_launch=no_launch
            ))
            return 0
        else:
            fmt.print_error(f"Failed to switch: {error_msg}")
            fmt.output(format_switch_result_json(
                project_name=project_name,
                success=False,
                elapsed_ms=elapsed_ms,
                error_msg=error_msg
            ))
            return 1

    except Exception as e:
        fmt.print_error(f"Unexpected error: {e}")
        fmt.output()
        return 1


async def cmd_current(args: argparse.Namespace) -> int:
    """Show current active project.

    Args:
        args: Parsed arguments

    Returns:
        0 on success, 1 on error
    """
    from .output import OutputFormatter, format_project_json

    json_mode = getattr(args, 'json', False)
    fmt = OutputFormatter(json_mode=json_mode)

    try:
        manager = ProjectManager()

        # Get current project
        current = await manager.get_current_project()

        if current:
            # Get project details
            try:
                project = await manager.get_project(current)
                window_count = await manager.get_project_window_count(current)

                if json_mode:
                    fmt.output(format_project_json(project, is_active=True, window_count=window_count))
                else:
                    print(f"{Colors.BOLD}{project.display_name or project.name}{Colors.RESET}")
                    print(f"  Name: {project.name}")
                    print(f"  Directory: {project.directory}")
                    if project.icon:
                        print(f"  Icon: {project.icon}")
                    print(f"  Windows: {window_count}")
                    print(f"  Scoped classes: {', '.join(project.scoped_classes)}")

            except FileNotFoundError:
                # Project exists in daemon but not in config
                if json_mode:
                    fmt.output({"name": current, "error": "config_not_found"})
                else:
                    print(f"{Colors.BOLD}{current}{Colors.RESET}")
                    print_warning(f"Project config not found for '{current}'")

            return 0
        else:
            if json_mode:
                fmt.output({"active_project": None, "mode": "global"})
            else:
                print_info("No active project (global mode)")
            return 0

    except DaemonError as e:
        fmt.print_error(f"Daemon error: {e}", "Is the i3-project-event-listener daemon running?")
        fmt.output()
        return 1
    except Exception as e:
        fmt.print_error(f"Unexpected error: {e}")
        fmt.output()
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
    from .output import OutputFormatter, format_project_list_json

    json_mode = getattr(args, 'json', False)
    fmt = OutputFormatter(json_mode=json_mode)

    try:
        manager = ProjectManager()

        # Get all projects
        projects = await manager.list_projects(sort_by=args.sort if hasattr(args, 'sort') else "modified")

        if not projects:
            if json_mode:
                fmt.output({"total": 0, "projects": []})
            else:
                print_info("No projects found")
                print_info(f"Create one with: i3pm create <name> <directory>")
            return 0

        # Get current project for highlighting
        try:
            current = await manager.get_current_project()
        except:
            current = None

        if json_mode:
            fmt.output(format_project_list_json(projects, current))
        else:
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
        fmt.print_error(f"Error listing projects: {e}")
        fmt.output()
        return 1


async def cmd_create(args: argparse.Namespace) -> int:
    """Create a new project.

    Args:
        args: Parsed arguments with name, directory, and optional fields

    Returns:
        0 on success, 1 on error
    """
    from .output import OutputFormatter
    from .dryrun import dry_run_create_project

    # Validate required arguments
    if not args.name:
        print_error("Project name is required")
        print_info("Usage: i3pm create <name> <directory> [options]")
        return 1

    if not args.directory:
        print_error("Project directory is required")
        print_info("Usage: i3pm create <name> <directory> [options]")
        return 1

    json_mode = getattr(args, 'json', False)
    dry_run = getattr(args, 'dry_run', False)
    fmt = OutputFormatter(json_mode=json_mode)

    try:
        manager = ProjectManager()

        # Validate directory exists
        directory = Path(args.directory).resolve()
        if not directory.exists():
            fmt.print_error(f"Directory does not exist: {directory}", f"Create it first with: mkdir -p {directory}")
            fmt.output()
            return 1

        if not directory.is_dir():
            fmt.print_error(f"Path is not a directory: {directory}")
            fmt.output()
            return 1

        # Prepare values
        display_name = args.display_name if hasattr(args, 'display_name') and args.display_name else args.name
        icon = args.icon if hasattr(args, 'icon') and args.icon else "📁"
        scoped_classes = args.scoped_classes.split(',') if hasattr(args, 'scoped_classes') and args.scoped_classes else ["Ghostty", "Code"]

        # Dry-run mode
        if dry_run:
            result = dry_run_create_project(args.name, directory, display_name, icon, scoped_classes)
            if json_mode:
                fmt.output(result.to_dict())
            else:
                print(result)
            return 0 if result.success else 1

        # Create project
        fmt.print_info(f"Creating project: {args.name}")

        project = await manager.create_project(
            name=args.name,
            directory=directory,
            display_name=display_name,
            icon=icon,
            scoped_classes=scoped_classes,
        )

        fmt.print_success(f"Created project '{project.display_name or project.name}'")
        fmt.print_info(f"  Name: {project.name}")
        fmt.print_info(f"  Directory: {project.directory}")
        fmt.print_info(f"  Icon: {project.icon}")
        fmt.print_info(f"  Scoped classes: {', '.join(project.scoped_classes)}")
        fmt.print_info(f"Switch to it with: i3pm switch {project.name}")

        if json_mode:
            from .output import format_project_json
            fmt.output(format_project_json(project, is_active=False, window_count=0))

        return 0

    except ValueError as e:
        fmt.print_error(f"Validation error: {e}")
        fmt.output()
        return 1
    except Exception as e:
        fmt.print_error(f"Failed to create project: {e}")
        fmt.output()
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
    from ..core.app_discovery import AppDiscovery
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
                    print(f"  {Colors.GRAY}(none){Colors.RESET}")

                print()

                # Global classes
                print(f"{Colors.GREEN}{Colors.BOLD}Global Classes:{Colors.RESET} (visible in all projects)")
                if config.global_classes:
                    for cls in config.get_all_global():
                        print(f"  {Colors.GREEN}●{Colors.RESET} {cls}")
                else:
                    print(f"  {Colors.GRAY}(none){Colors.RESET}")

                print()

                # Patterns
                if config.class_patterns:
                    print(f"{Colors.YELLOW}{Colors.BOLD}Patterns:{Colors.RESET}")
                    for pattern_rule in sorted(config.class_patterns, key=lambda p: p.priority, reverse=True):
                        color = Colors.BLUE if pattern_rule.scope == "scoped" else Colors.GREEN
                        priority_str = f"[priority {pattern_rule.priority}]" if pattern_rule.priority != 0 else ""
                        desc_str = f" - {pattern_rule.description}" if pattern_rule.description else ""
                        print(f"  {color}●{Colors.RESET} {pattern_rule.pattern} → {pattern_rule.scope} {priority_str}{desc_str}")
                    print()

            return 0

        elif subcommand == 'add-scoped':
            # Add scoped class
            from .output import OutputFormatter
            from .dryrun import dry_run_add_class

            class_name = args.class_name
            json_mode = getattr(args, 'json', False)
            dry_run = getattr(args, 'dry_run', False)
            fmt = OutputFormatter(json_mode=json_mode)

            try:
                # Check current classification
                current_scope = config.get_classification(class_name)
                already_classified = current_scope in ["scoped", "global"]

                # Dry-run mode
                if dry_run:
                    result = dry_run_add_class(class_name, "scoped", already_classified, current_scope)
                    if json_mode:
                        fmt.output(result.to_dict())
                    else:
                        print(result)
                    return 0 if result.success else 1

                # Execute
                config.add_scoped_class(class_name)
                config.save()

                fmt.print_success(f"Added '{class_name}' to scoped classes")
                fmt.print_info("Windows of this class will now be project-specific")

                if json_mode:
                    fmt.output({"status": "success", "class": class_name, "scope": "scoped"})

                return 0
            except ValueError as e:
                fmt.print_error(str(e))
                fmt.output()
                return 1

        elif subcommand == 'add-global':
            # Add global class
            from .output import OutputFormatter
            from .dryrun import dry_run_add_class

            class_name = args.class_name
            json_mode = getattr(args, 'json', False)
            dry_run = getattr(args, 'dry_run', False)
            fmt = OutputFormatter(json_mode=json_mode)

            try:
                # Check current classification
                current_scope = config.get_classification(class_name)
                already_classified = current_scope in ["scoped", "global"]

                # Dry-run mode
                if dry_run:
                    result = dry_run_add_class(class_name, "global", already_classified, current_scope)
                    if json_mode:
                        fmt.output(result.to_dict())
                    else:
                        print(result)
                    return 0 if result.success else 1

                # Execute
                config.add_global_class(class_name)
                config.save()

                fmt.print_success(f"Added '{class_name}' to global classes")
                fmt.print_info("Windows of this class will now be visible in all projects")

                if json_mode:
                    fmt.output({"status": "success", "class": class_name, "scope": "global"})

                return 0
            except ValueError as e:
                fmt.print_error(str(e))
                fmt.output()
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

        elif subcommand == 'discover':
            # Discover all apps on system
            discovery = AppDiscovery()
            print_info("Scanning system for installed applications...")
            apps = discovery.discover_all()

            if hasattr(args, 'json') and args.json:
                result = {
                    "total": len(apps),
                    "apps": [
                        {
                            "name": app.name,
                            "wm_class": app.wm_class,
                            "guessed_class": discovery.guess_wm_class(app),
                            "exec": app.exec_command,
                            "suggested": discovery.suggest_classification(app),
                            "categories": app.categories,
                        }
                        for app in apps
                    ],
                }
                print(json.dumps(result, indent=2))
            else:
                # Rich formatted output
                print(f"\n{Colors.BOLD}Discovered Applications:{Colors.RESET} {len(apps)} apps\n")

                # Group by whether they have WM class
                apps_with_class = [a for a in apps if a.wm_class]
                apps_without = [a for a in apps if not a.wm_class]

                print(f"{Colors.GREEN}✓{Colors.RESET} {len(apps_with_class)} apps with WM class defined")
                print(f"{Colors.YELLOW}?{Colors.RESET} {len(apps_without)} apps without WM class (can be detected)")
                print()

                # Show apps with classification suggestions
                if hasattr(args, 'show_all') and args.show_all:
                    print(f"{Colors.BOLD}Applications with WM Class:{Colors.RESET}\n")
                    for app in sorted(apps_with_class, key=lambda a: a.name.lower())[:20]:
                        suggestion = discovery.suggest_classification(app)
                        color = Colors.BLUE if suggestion == "scoped" else Colors.GREEN
                        print(f"  {color}●{Colors.RESET} {app.name:30} {app.wm_class:20} ({suggestion})")

                    if len(apps_with_class) > 20:
                        print(f"\n  ... and {len(apps_with_class) - 20} more")

                print(f"\n{Colors.GRAY}Use 'i3pm app-classes discover --show-all' to see full list{Colors.RESET}")
                print(f"{Colors.GRAY}Use 'i3pm app-classes suggest' for auto-classification{Colors.RESET}")

            return 0

        elif subcommand == 'detect':
            # Detect window classes using Xvfb (T042, FR-083, FR-090, FR-093)
            from ..core.app_discovery import (
                check_xvfb_available,
                detect_window_class_xvfb,
                get_cached_result,
                update_cache_with_result,
            )
            from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn

            # Check dependencies first (FR-083)
            if not check_xvfb_available():
                print_error("Required tools not found: Xvfb, xdotool, or xprop")
                print_info("Please install: sudo apt install xvfb xdotool x11-utils  (Debian/Ubuntu)")
                print_info("              or: sudo pacman -S xorg-server-xvfb xdotool xorg-xprop  (Arch)")
                return 1

            # Parse options
            all_missing = getattr(args, 'all_missing', False)
            isolated_only = getattr(args, 'isolated', False)
            timeout = getattr(args, 'timeout', 10)
            use_cache = getattr(args, 'cache', True)
            verbose = getattr(args, 'verbose', False)
            desktop_file = getattr(args, 'desktop_file', None)

            # Get list of apps to detect
            discovery = AppDiscovery()

            if desktop_file:
                # Single app detection
                apps_to_detect = [desktop_file]
            elif all_missing:
                # All apps without WM_CLASS
                print_info("Scanning for applications without WM_CLASS...")
                all_apps = discovery.discover_all()
                apps_to_detect = [str(app.desktop_file) for app in all_apps if not app.wm_class]

                if not apps_to_detect:
                    print_success("All discovered apps already have WM_CLASS defined!")
                    return 0

                print_info(f"Found {len(apps_to_detect)} apps without WM_CLASS")
            else:
                print_error("Please specify either a desktop file or use --all-missing")
                print_info("Usage: i3pm app-classes detect /path/to/app.desktop")
                print_info("       i3pm app-classes detect --all-missing")
                return 1

            # Detect window classes with progress indication (FR-090)
            results = []
            cache_hits = 0

            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(),
                TaskProgressColumn(),
                console=None if verbose else ...
            ) as progress:
                task = progress.add_task(
                    f"[cyan]Detecting window classes...",
                    total=len(apps_to_detect)
                )

                for desktop_path in apps_to_detect:
                    # Check cache first (FR-091)
                    if use_cache:
                        cached = get_cached_result(desktop_path)
                        if cached:
                            cache_hits += 1
                            results.append(cached)
                            progress.update(task, advance=1, description=f"[cyan]Using cached result for {Path(desktop_path).stem}")
                            continue

                    # Perform detection (FR-086: with timeout)
                    if verbose:
                        print_info(f"Detecting {Path(desktop_path).stem}...")

                    progress.update(task, description=f"[cyan]Detecting {Path(desktop_path).stem}...")
                    result = detect_window_class_xvfb(desktop_path, timeout=timeout)
                    results.append(result)

                    # Update cache on success (FR-091)
                    if result.detection_method == "xvfb" and use_cache:
                        update_cache_with_result(result)

                    progress.update(task, advance=1)

            # Display results (FR-093)
            successful = [r for r in results if r.detection_method == "xvfb"]
            failed = [r for r in results if r.detection_method == "failed"]

            print()
            print_success(f"Detected {len(successful)}/{len(results)} window classes")

            if cache_hits > 0:
                print_info(f"Used {cache_hits} cached results")

            if successful:
                print(f"\n{Colors.GREEN}{Colors.BOLD}Successful Detections:{Colors.RESET}")
                for result in successful:
                    app_name = result.app_name
                    wm_class = result.detected_class
                    print(f"  {Colors.GREEN}✓{Colors.RESET} {app_name:30} → {wm_class}")

            if failed:
                print(f"\n{Colors.RED}{Colors.BOLD}Failed Detections:{Colors.RESET}")
                for result in failed:
                    app_name = result.app_name
                    error = result.error_message
                    print(f"  {Colors.RED}✗{Colors.RESET} {app_name:30} ({error})")

            if successful and not isolated_only:
                print(f"\n{Colors.GRAY}Next steps:{Colors.RESET}")
                print(f"{Colors.GRAY}- Review detected classes above{Colors.RESET}")
                print(f"{Colors.GRAY}- Use 'i3pm app-classes add-scoped <class>' to classify{Colors.RESET}")
                print(f"{Colors.GRAY}- Or use 'i3pm app-classes suggest' for automatic suggestions{Colors.RESET}")

            return 0 if len(failed) == 0 else 1

        elif subcommand == 'wizard':
            # Launch interactive classification wizard (T065)
            print_info("Launching classification wizard...")
            print_info("Use arrow keys to navigate, s/g/u to classify, Enter to save")

            # Import here to avoid loading Textual when not needed
            from ..tui.wizard import WizardApp

            try:
                # Create wizard app
                app = WizardApp(
                    filter_status=args.filter,
                    sort_by=args.sort,
                    auto_accept=args.auto_accept,
                )

                # Run asynchronously since we're already in an async function
                await app.run_async()
                return 0
            except KeyboardInterrupt:
                print_info("\nWizard cancelled")
                return 0
            except Exception as e:
                print_error(f"Wizard failed: {e}")
                import traceback
                traceback.print_exc()
                return 1

        elif subcommand == 'inspect':
            # Launch window inspector TUI (T086)
            from ..tui.inspector import (
                InspectorApp,
                inspect_window_click,
                inspect_window_focused,
                inspect_window_by_id,
            )

            try:
                # Determine inspection mode
                window_props = None

                if args.window_id:
                    # By-ID mode
                    print_info(f"Inspecting window ID: {args.window_id}")
                    window_props = await inspect_window_by_id(args.window_id)

                elif args.focused:
                    # Focused mode
                    print_info("Inspecting focused window...")
                    window_props = await inspect_window_focused()

                else:
                    # Click mode (default)
                    print_info("Click any window to inspect...")
                    print_info("(Press Escape to cancel)")

                    window_id = inspect_window_click()
                    if window_id is None:
                        print_info("Cancelled")
                        return 0

                    window_props = await inspect_window_by_id(window_id)

                # Launch inspector app
                app = InspectorApp(window_props=window_props)

                # Enable live mode if requested
                if args.live:
                    app.live_mode = True

                await app.run_async()
                return 0

            except KeyboardInterrupt:
                print_info("\nInspector cancelled")
                return 0
            except ValueError as e:
                # T090: Consistent error format with remediation
                error_msg = str(e)
                if "Window not found" in error_msg:
                    print_error_with_remediation(
                        error_msg,
                        "Use --click mode to select a visible window, or --focused to inspect the focused window"
                    )
                else:
                    print_error_with_remediation(error_msg, "Check window ID and try again")
                return 1
            except Exception as e:
                print_error_with_remediation(
                    f"Inspector failed: {e}",
                    "Check that i3 is running and i3ipc is installed. Use --verbose for details."
                )
                if hasattr(args, 'verbose') and args.verbose:
                    import traceback
                    traceback.print_exc()
                return 1

        elif subcommand == 'suggest':
            # Auto-classify discovered apps
            discovery = AppDiscovery()
            print_info("Scanning applications and generating suggestions...")
            apps = discovery.discover_all()

            # Filter to apps with WM class
            apps_with_class = [a for a in apps if a.wm_class]

            # Generate suggestions
            scoped_suggestions = []
            global_suggestions = []

            for app in apps_with_class:
                suggestion = discovery.suggest_classification(app)
                wm_class = app.wm_class

                # Skip if already classified
                if config.get_classification(wm_class) in ["scoped", "global"]:
                    continue

                if suggestion == "scoped":
                    scoped_suggestions.append((app.name, wm_class))
                elif suggestion == "global":
                    global_suggestions.append((app.name, wm_class))

            if hasattr(args, 'json') and args.json:
                result = {
                    "scoped": [{"name": n, "class": c} for n, c in scoped_suggestions],
                    "global": [{"name": n, "class": c} for n, c in global_suggestions],
                }
                print(json.dumps(result, indent=2))
            else:
                print(f"\n{Colors.BOLD}Classification Suggestions:{Colors.RESET}\n")

                if scoped_suggestions:
                    print(f"{Colors.BLUE}{Colors.BOLD}Suggested Scoped:{Colors.RESET} (project-specific)")
                    for name, wm_class in scoped_suggestions[:10]:
                        print(f"  {Colors.BLUE}●{Colors.RESET} {name:30} ({wm_class})")
                    if len(scoped_suggestions) > 10:
                        print(f"  ... and {len(scoped_suggestions) - 10} more")
                    print()

                if global_suggestions:
                    print(f"{Colors.GREEN}{Colors.BOLD}Suggested Global:{Colors.RESET} (visible everywhere)")
                    for name, wm_class in global_suggestions[:10]:
                        print(f"  {Colors.GREEN}●{Colors.RESET} {name:30} ({wm_class})")
                    if len(global_suggestions) > 10:
                        print(f"  ... and {len(global_suggestions) - 10} more")
                    print()

                if scoped_suggestions or global_suggestions:
                    print(f"{Colors.GRAY}Use 'i3pm app-classes auto-classify' to apply these suggestions{Colors.RESET}")
                else:
                    print_success("All discovered apps are already classified!")

            return 0

        elif subcommand == 'auto-classify':
            # Auto-classify based on suggestions
            discovery = AppDiscovery()
            print_info("Scanning and auto-classifying applications...")
            apps = discovery.discover_all()

            apps_with_class = [a for a in apps if a.wm_class]

            added_scoped = []
            added_global = []

            for app in apps_with_class:
                suggestion = discovery.suggest_classification(app)
                wm_class = app.wm_class

                # Skip if already classified
                if config.get_classification(wm_class) in ["scoped", "global"]:
                    continue

                # Skip if no clear suggestion
                if suggestion == "unknown":
                    continue

                try:
                    if suggestion == "scoped":
                        config.add_scoped_class(wm_class)
                        added_scoped.append((app.name, wm_class))
                    elif suggestion == "global":
                        config.add_global_class(wm_class)
                        added_global.append((app.name, wm_class))
                except ValueError:
                    # Already exists, skip
                    pass

            # Save changes
            if added_scoped or added_global:
                config.save()

                print_success(f"Auto-classified {len(added_scoped) + len(added_global)} applications")

                if added_scoped:
                    print(f"\n{Colors.BLUE}Added to scoped:{Colors.RESET}")
                    for name, wm_class in added_scoped[:5]:
                        print(f"  {Colors.BLUE}●{Colors.RESET} {name} ({wm_class})")
                    if len(added_scoped) > 5:
                        print(f"  ... and {len(added_scoped) - 5} more")

                if added_global:
                    print(f"\n{Colors.GREEN}Added to global:{Colors.RESET}")
                    for name, wm_class in added_global[:5]:
                        print(f"  {Colors.GREEN}●{Colors.RESET} {name} ({wm_class})")
                    if len(added_global) > 5:
                        print(f"  ... and {len(added_global) - 5} more")
            else:
                print_info("No new applications to classify (all already handled)")

            return 0

        elif subcommand == 'report':
            # Generate classification report
            discovery = AppDiscovery()
            print_info("Generating classification report...")
            apps = discovery.discover_all()

            report = discovery.generate_classification_report()

            if hasattr(args, 'output') and args.output:
                # Write to file
                output_path = Path(args.output)
                output_path.write_text(report)
                print_success(f"Report saved to: {output_path}")
            else:
                # Print to stdout
                print(report)

            return 0

        elif subcommand == 'add-pattern':
            # Add pattern rule (T025)
            from ..models.pattern import PatternRule
            from .output import OutputFormatter
            from .dryrun import dry_run_add_pattern

            pattern = args.pattern
            scope = args.scope
            priority = getattr(args, 'priority', 0)
            description = getattr(args, 'description', '')
            json_mode = getattr(args, 'json', False)
            dry_run = getattr(args, 'dry_run', False)
            fmt = OutputFormatter(json_mode=json_mode)

            try:
                # Check if pattern exists
                pattern_exists = any(p.pattern == pattern for p in config.class_patterns)

                # Dry-run mode
                if dry_run:
                    result = dry_run_add_pattern(pattern, scope, priority, description, pattern_exists)
                    if json_mode:
                        fmt.output(result.to_dict())
                    else:
                        print(result)
                    return 0 if result.success else 1

                # Create and add pattern rule
                pattern_rule = PatternRule(
                    pattern=pattern,
                    scope=scope,
                    priority=priority,
                    description=description
                )
                config.add_pattern(pattern_rule)
                config.save()

                fmt.print_success(f"Added pattern: {pattern} → {scope}")
                if priority != 0:
                    fmt.print_info(f"Priority: {priority}")
                if description:
                    fmt.print_info(f"Description: {description}")

                # Suggest daemon reload
                fmt.print_info("Run 'i3pm app-classes reload' to apply changes to daemon")

                if json_mode:
                    fmt.output({
                        "status": "success",
                        "pattern": pattern,
                        "scope": scope,
                        "priority": priority,
                        "description": description
                    })

                return 0

            except ValueError as e:
                fmt.print_error(f"Invalid pattern: {e}")
                fmt.output()
                return 1

        elif subcommand == 'list-patterns':
            # List pattern rules (T026)
            if not config.class_patterns:
                print_info("No pattern rules configured")
                return 0

            if hasattr(args, 'json') and args.json:
                # JSON output
                import json
                patterns_data = [
                    {
                        "pattern": p.pattern,
                        "scope": p.scope,
                        "priority": p.priority,
                        "description": p.description
                    }
                    for p in config.list_patterns()
                ]
                print(json.dumps(patterns_data, indent=2))
            else:
                # Table output using rich
                from rich.console import Console
                from rich.table import Table

                console = Console()
                table = Table(title="Pattern Rules", show_header=True, header_style="bold")
                table.add_column("Pattern", style="cyan")
                table.add_column("Scope", style="green")
                table.add_column("Priority", justify="right")
                table.add_column("Description", style="dim")

                for pattern in config.list_patterns():
                    scope_color = "blue" if pattern.scope == "scoped" else "green"
                    table.add_row(
                        pattern.pattern,
                        f"[{scope_color}]{pattern.scope}[/{scope_color}]",
                        str(pattern.priority),
                        pattern.description or ""
                    )

                console.print(table)

            return 0

        elif subcommand == 'remove-pattern':
            # Remove pattern rule (T027)
            from .output import OutputFormatter
            from .dryrun import dry_run_remove_pattern

            pattern = args.pattern
            json_mode = getattr(args, 'json', False)
            dry_run = getattr(args, 'dry_run', False)
            fmt = OutputFormatter(json_mode=json_mode)

            # Check if pattern exists
            pattern_exists = any(p.pattern == pattern for p in config.class_patterns)

            # Dry-run mode
            if dry_run:
                result = dry_run_remove_pattern(pattern, pattern_exists)
                if json_mode:
                    fmt.output(result.to_dict())
                else:
                    print(result)
                return 0 if result.success else 1

            # Confirm removal unless --yes flag or JSON mode
            if not getattr(args, 'yes', False) and not json_mode:
                import sys
                if sys.stdin.isatty():
                    response = input(f"Remove pattern '{pattern}'? [y/N]: ")
                    if response.lower() not in ['y', 'yes']:
                        fmt.print_info("Cancelled")
                        return 0
                else:
                    fmt.print_error("Cannot confirm in non-interactive mode", "Use --yes to skip confirmation")
                    fmt.output()
                    return 1

            if config.remove_pattern(pattern):
                config.save()
                fmt.print_success(f"Removed pattern: {pattern}")
                fmt.print_info("Run 'i3pm app-classes reload' to apply changes to daemon")

                if json_mode:
                    fmt.output({"status": "success", "pattern": pattern, "action": "removed"})

                return 0
            else:
                fmt.print_error(f"Pattern not found: {pattern}")
                fmt.output()
                return 1

        elif subcommand == 'test-pattern':
            # Test pattern matching (T028)
            pattern = args.pattern
            window_class = args.window_class if hasattr(args, 'window_class') else None

            from ..models.pattern import PatternRule

            try:
                # Create pattern rule for testing
                test_pattern = PatternRule(pattern=pattern, scope="scoped", priority=0)

                if window_class:
                    # Test single window class
                    matches = test_pattern.matches(window_class)

                    if hasattr(args, 'json') and args.json:
                        import json
                        result = {
                            "pattern": pattern,
                            "window_class": window_class,
                            "matches": matches
                        }
                        print(json.dumps(result, indent=2))
                    else:
                        if matches:
                            print_success(f"Pattern '{pattern}' MATCHES '{window_class}'")
                        else:
                            print_info(f"Pattern '{pattern}' does NOT match '{window_class}'")

                    return 0

                elif hasattr(args, 'all_classes') and args.all_classes:
                    # Test against all known window classes
                    all_classes = set()
                    all_classes.update(config.scoped_classes)
                    all_classes.update(config.global_classes)

                    matches = [cls for cls in sorted(all_classes) if test_pattern.matches(cls)]

                    if hasattr(args, 'json') and args.json:
                        import json
                        result = {
                            "pattern": pattern,
                            "matches": matches,
                            "total_tested": len(all_classes)
                        }
                        print(json.dumps(result, indent=2))
                    else:
                        if matches:
                            print_success(f"Pattern '{pattern}' matches {len(matches)} classes:")
                            for cls in matches:
                                print(f"  {Colors.GREEN}✓{Colors.RESET} {cls}")
                        else:
                            print_info(f"Pattern '{pattern}' matches no known classes")
                        print_info(f"Tested against {len(all_classes)} known classes")

                    return 0

                else:
                    # Just show pattern info
                    print_info(f"Pattern: {pattern}")
                    print_info("Use --window-class or --all-classes to test matching")
                    return 0

            except ValueError as e:
                print_error(f"Invalid pattern: {e}")
                return 1

        elif subcommand == 'reload':
            # Reload daemon configuration (T029 part 1 - CLI function)
            print_info("Reloading daemon configuration...")

            try:
                # Send i3 tick event to daemon
                async with I3Client() as i3:
                    await i3.command('nop "i3pm:reload-config"')

                print_success("Reload signal sent to daemon")
                print_info("Daemon will reload configuration on next event")
                return 0

            except I3Error as e:
                print_error(f"Failed to send reload signal: {e}")
                return 1

        else:
            print_error(f"Unknown subcommand: {subcommand}")
            return 1

    except Exception as e:
        print_error(f"Failed to manage app classifications: {e}")
        import traceback
        traceback.print_exc()
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
                    events_response = await daemon.get_events(limit=100, event_type=event_type, since_id=last_event_id)

                    # Extract events array from response
                    if isinstance(events_response, dict) and "events" in events_response:
                        events = events_response["events"]
                    elif isinstance(events_response, list):
                        events = events_response
                    else:
                        events = []

                    for event in events:
                        if json_output:
                            import json
                            print(json.dumps(event))
                        else:
                            # Format event
                            timestamp = event.get("timestamp", "")
                            evt_type = event.get("event_type", "unknown")

                            # Build details string
                            details_parts = []
                            if event.get("window_class"):
                                details_parts.append(f"class={event['window_class']}")
                            if event.get("workspace_name"):
                                details_parts.append(f"ws={event['workspace_name']}")
                            if event.get("project_name"):
                                details_parts.append(f"project={event['project_name']}")
                            if event.get("tick_payload"):
                                details_parts.append(f"payload={event['tick_payload']}")
                            details = " ".join(details_parts) if details_parts else ""

                            # Color code by type
                            evt_prefix = evt_type.split("::")[0] if "::" in evt_type else evt_type
                            type_color = {
                                "window": Colors.BLUE,
                                "workspace": Colors.GREEN,
                                "output": Colors.YELLOW,
                                "tick": Colors.GRAY,
                                "error": Colors.RED,
                            }.get(evt_prefix, Colors.RESET)

                            print(f"{Colors.GRAY}{timestamp}{Colors.RESET} {type_color}{evt_type:20}{Colors.RESET} {details}")

                        last_event_id = max(last_event_id, event.get("event_id", 0))

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
    """Main CLI entry point.

    T094: Shell completion enabled via argcomplete
    """
    # T094: Import completers if argcomplete is available
    if ARGCOMPLETE_AVAILABLE:
        from .completers import (
            complete_project_names,
            complete_window_classes,
            complete_pattern_prefix,
            complete_scope_values,
            complete_desktop_files,
            complete_filter_status,
            complete_sort_fields,
            complete_event_types,
        )

    parser = argparse.ArgumentParser(
        prog="i3pm",
        description="i3 Project Manager - Unified CLI/TUI for i3 window manager projects",
        epilog="For more information, see: /etc/nixos/specs/019-re-explore-and/"
    )

    parser.add_argument(
        "--version",
        action="version",
        version="i3pm 0.3.0 (Phase 7: Polish & Documentation)"
    )

    # T093: Global logging flags
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging (INFO level)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging (DEBUG level, includes verbose)"
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
    switch_project_arg = parser_switch.add_argument(
        "project",
        help="Project name to switch to"
    )
    # T094: Add completion for project names
    if ARGCOMPLETE_AVAILABLE:
        switch_project_arg.completer = complete_project_names
    parser_switch.add_argument(
        "--no-launch",
        action="store_true",
        help="Don't auto-launch applications"
    )
    parser_switch.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # i3pm current
    parser_current = subparsers.add_parser(
        "current",
        help="Show current active project",
        description="Display information about the currently active project"
    )
    parser_current.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # i3pm clear
    parser_clear = subparsers.add_parser(
        "clear",
        help="Clear active project (global mode)",
        description="Return to global mode (no active project)"
    )
    parser_clear.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
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
    parser_list.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
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
    parser_create.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )
    parser_create.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without creating"
    )

    # i3pm show
    parser_show = subparsers.add_parser(
        "show",
        help="Show project details",
        description="Display detailed information about a project"
    )
    parser_show.add_argument("project", help="Project name")
    parser_show.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

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
    parser_app_classes_add_scoped.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be added without adding"
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
    parser_app_classes_add_global.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be added without adding"
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

    # app-classes discover
    parser_app_classes_discover = app_classes_subparsers.add_parser(
        "discover",
        help="Discover all installed applications"
    )
    parser_app_classes_discover.add_argument(
        "--show-all",
        action="store_true",
        help="Show all discovered apps (not just summary)"
    )
    parser_app_classes_discover.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # app-classes detect (T042)
    parser_app_classes_detect = app_classes_subparsers.add_parser(
        "detect",
        help="Detect window classes using isolated Xvfb",
        description="Launch applications in isolated Xvfb to detect their window classes"
    )
    parser_app_classes_detect.add_argument(
        "desktop_file",
        nargs="?",
        help="Path to .desktop file to detect (optional)"
    )
    parser_app_classes_detect.add_argument(
        "--all-missing",
        action="store_true",
        help="Detect all apps without WM_CLASS defined"
    )
    parser_app_classes_detect.add_argument(
        "--isolated",
        action="store_true",
        help="Skip final suggestions, only detect"
    )
    parser_app_classes_detect.add_argument(
        "--timeout",
        type=int,
        default=10,
        help="Timeout in seconds per app (default: 10)"
    )
    parser_app_classes_detect.add_argument(
        "--no-cache",
        dest="cache",
        action="store_false",
        default=True,
        help="Skip cache and force fresh detection"
    )
    parser_app_classes_detect.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show verbose output during detection"
    )

    # app-classes wizard (T065)
    parser_app_classes_wizard = app_classes_subparsers.add_parser(
        "wizard",
        help="Interactive TUI for bulk application classification",
        description="Launch interactive wizard for classifying multiple applications with keyboard shortcuts"
    )
    parser_app_classes_wizard.add_argument(
        "--filter",
        choices=["all", "unclassified", "scoped", "global"],
        default="all",
        help="Initial filter (default: all)"
    )
    parser_app_classes_wizard.add_argument(
        "--sort",
        choices=["name", "class", "status", "confidence"],
        default="name",
        help="Initial sort field (default: name)"
    )
    parser_app_classes_wizard.add_argument(
        "--auto-accept",
        action="store_true",
        help="Automatically accept high-confidence suggestions on launch"
    )

    # app-classes inspect (T086)
    parser_app_classes_inspect = app_classes_subparsers.add_parser(
        "inspect",
        help="Inspect window properties and classification (TUI)",
        description="Launch interactive window inspector with real-time property display and classification actions"
    )
    inspect_mode_group = parser_app_classes_inspect.add_mutually_exclusive_group()
    inspect_mode_group.add_argument(
        "--click",
        action="store_true",
        help="Click mode - select window by clicking (default)"
    )
    inspect_mode_group.add_argument(
        "--focused",
        action="store_true",
        help="Focused mode - inspect currently focused window"
    )
    inspect_mode_group.add_argument(
        "window_id",
        nargs="?",
        type=int,
        help="Inspect specific window by i3 container ID"
    )
    parser_app_classes_inspect.add_argument(
        "--live",
        action="store_true",
        help="Enable live mode by default (auto-update on i3 events)"
    )

    # app-classes suggest
    parser_app_classes_suggest = app_classes_subparsers.add_parser(
        "suggest",
        help="Suggest classifications for discovered apps"
    )
    parser_app_classes_suggest.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # app-classes auto-classify
    parser_app_classes_auto = app_classes_subparsers.add_parser(
        "auto-classify",
        help="Automatically classify apps based on suggestions"
    )

    # app-classes report
    parser_app_classes_report = app_classes_subparsers.add_parser(
        "report",
        help="Generate classification report"
    )
    parser_app_classes_report.add_argument(
        "--output",
        "-o",
        help="Output file (default: stdout)"
    )

    # app-classes add-pattern (T025)
    parser_app_classes_add_pattern = app_classes_subparsers.add_parser(
        "add-pattern",
        help="Add a pattern rule for window class matching"
    )
    pattern_arg = parser_app_classes_add_pattern.add_argument(
        "pattern",
        help="Pattern string (e.g., 'glob:pwa-*', 'regex:^vim$', or literal 'Code')"
    )
    # T094: Add completion for pattern prefixes
    if ARGCOMPLETE_AVAILABLE:
        pattern_arg.completer = complete_pattern_prefix

    scope_arg = parser_app_classes_add_pattern.add_argument(
        "scope",
        choices=["scoped", "global"],
        help="Classification scope"
    )
    # T094: Add completion for scope values
    if ARGCOMPLETE_AVAILABLE:
        scope_arg.completer = complete_scope_values
    parser_app_classes_add_pattern.add_argument(
        "--priority",
        type=int,
        default=0,
        help="Pattern priority (higher = evaluated first, default: 0)"
    )
    parser_app_classes_add_pattern.add_argument(
        "--description",
        help="Optional description for the pattern"
    )
    parser_app_classes_add_pattern.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be added without adding"
    )

    # app-classes list-patterns (T026)
    parser_app_classes_list_patterns = app_classes_subparsers.add_parser(
        "list-patterns",
        help="List all pattern rules"
    )
    parser_app_classes_list_patterns.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # app-classes remove-pattern (T027)
    parser_app_classes_remove_pattern = app_classes_subparsers.add_parser(
        "remove-pattern",
        help="Remove a pattern rule"
    )
    parser_app_classes_remove_pattern.add_argument(
        "pattern",
        help="Exact pattern string to remove"
    )
    parser_app_classes_remove_pattern.add_argument(
        "--yes", "-y",
        action="store_true",
        help="Skip confirmation prompt"
    )
    parser_app_classes_remove_pattern.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be removed without removing"
    )

    # app-classes test-pattern (T028)
    parser_app_classes_test_pattern = app_classes_subparsers.add_parser(
        "test-pattern",
        help="Test pattern matching against window classes"
    )
    parser_app_classes_test_pattern.add_argument(
        "pattern",
        help="Pattern to test (e.g., 'glob:pwa-*')"
    )
    parser_app_classes_test_pattern.add_argument(
        "--window-class",
        help="Test against specific window class"
    )
    parser_app_classes_test_pattern.add_argument(
        "--all-classes",
        action="store_true",
        help="Test against all known window classes"
    )
    parser_app_classes_test_pattern.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )

    # app-classes reload (T029)
    parser_app_classes_reload = app_classes_subparsers.add_parser(
        "reload",
        help="Reload daemon configuration"
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

    # T094: Enable shell completion if argcomplete is available
    if ARGCOMPLETE_AVAILABLE:
        argcomplete.autocomplete(parser)

    # Parse arguments
    args = parser.parse_args()

    # T093: Initialize logging based on flags
    verbose = getattr(args, 'verbose', False)
    debug = getattr(args, 'debug', False)
    init_logging(verbose=verbose, debug=debug)

    logger = get_global_logger()
    if debug:
        logger.debug("Debug logging enabled")
    elif verbose:
        logger.info("Verbose logging enabled")

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
