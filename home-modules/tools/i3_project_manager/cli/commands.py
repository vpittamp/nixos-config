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
