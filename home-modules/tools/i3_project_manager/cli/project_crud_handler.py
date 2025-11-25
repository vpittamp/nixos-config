"""
Project CRUD Handler for Eww Integration

Feature 094: Enhanced Projects & Applications CRUD Interface (T037)
Provides command-line interface for project CRUD operations with Eww-compatible JSON output.

Usage:
    python3 -m i3_project_manager.cli.project_crud_handler read <name>
    python3 -m i3_project_manager.cli.project_crud_handler edit <name> --updates '{"display_name":"New Name"}'
    python3 -m i3_project_manager.cli.project_crud_handler create --config '{"name":"test","display_name":"Test","working_dir":"/tmp"}'
    python3 -m i3_project_manager.cli.project_crud_handler delete <name> [--force]
    python3 -m i3_project_manager.cli.project_crud_handler list
    python3 -m i3_project_manager.cli.project_crud_handler get-mtime <name>

Output: Single-line JSON to stdout
Error Handling: Catches all exceptions and returns {"status": "error", "error": "message"}
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, Any, Optional

from pydantic import ValidationError

from ..services.project_editor import ProjectEditor
from ..models.project_config import ProjectConfig, WorktreeConfig


def create_response(status: str, **kwargs) -> Dict[str, Any]:
    """
    Create standardized response dict for Eww consumption

    Args:
        status: "success" or "error"
        **kwargs: Additional fields to include in response

    Returns:
        Response dict with status field
    """
    return {"status": status, **kwargs}


def handle_read(editor: ProjectEditor, name: str) -> Dict[str, Any]:
    """
    Read project configuration

    Args:
        editor: ProjectEditor instance
        name: Project name

    Returns:
        {"status": "success", "project": {...}} or {"status": "error", "error": "..."}
    """
    try:
        project_data = editor.read_project(name)
        return create_response("success", project=project_data)
    except FileNotFoundError as e:
        return create_response("error", error=str(e))
    except Exception as e:
        return create_response("error", error=f"Unexpected error: {str(e)}")


def handle_edit(editor: ProjectEditor, name: str, updates: Dict[str, Any]) -> Dict[str, Any]:
    """
    Edit project configuration

    Args:
        editor: ProjectEditor instance
        name: Project name
        updates: Dict of fields to update

    Returns:
        {"status": "success", "conflict": bool, "path": "..."} or {"status": "error", "error": "...", "validation_errors": [...]}
    """
    try:
        result = editor.edit_project(name, updates)
        # result already contains {"status": "success", ...}, so just return it
        return result
    except FileNotFoundError as e:
        return create_response("error", error=str(e))
    except ValidationError as e:
        # Extract validation errors for UI display
        errors = []
        for error in e.errors():
            field = ".".join(str(loc) for loc in error["loc"])
            errors.append({
                "field": field,
                "message": error["msg"],
                "type": error["type"]
            })
        return create_response("error",
                             error=f"Validation failed: {len(errors)} error(s)",
                             validation_errors=errors)
    except ValueError as e:
        return create_response("error", error=str(e))
    except Exception as e:
        return create_response("error", error=f"Unexpected error: {str(e)}")


def handle_create(editor: ProjectEditor, config_dict: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create new project

    Args:
        editor: ProjectEditor instance
        config_dict: Project configuration dict

    Returns:
        {"status": "success", "path": "...", "project_name": "..."} or {"status": "error", "error": "...", "validation_errors": [...]}
    """
    try:
        # Determine if worktree or regular project
        if "parent_project" in config_dict:
            config = WorktreeConfig(**config_dict)
        else:
            config = ProjectConfig(**config_dict)

        result = editor.create_project(config)
        # result already contains {"status": "success", ...}, so just return it
        return result
    except ValidationError as e:
        # Extract validation errors for UI display
        errors = []
        for error in e.errors():
            field = ".".join(str(loc) for loc in error["loc"])
            errors.append({
                "field": field,
                "message": error["msg"],
                "type": error["type"]
            })
        return create_response("error",
                             error=f"Validation failed: {len(errors)} error(s)",
                             validation_errors=errors)
    except ValueError as e:
        return create_response("error", error=str(e))
    except Exception as e:
        return create_response("error", error=f"Unexpected error: {str(e)}")


def handle_delete(editor: ProjectEditor, name: str, force: bool = False) -> Dict[str, Any]:
    """
    Delete project

    Args:
        editor: ProjectEditor instance
        name: Project name
        force: If True, skip worktree check

    Returns:
        {"status": "success", "path": "...", "backup": "..."} or {"status": "error", "error": "..."}
    """
    try:
        result = editor.delete_project(name, force=force)
        # result already contains {"status": "success", ...}, so just return it
        return result
    except FileNotFoundError as e:
        return create_response("error", error=str(e))
    except ValueError as e:
        return create_response("error", error=str(e))
    except Exception as e:
        return create_response("error", error=f"Unexpected error: {str(e)}")


def handle_list(editor: ProjectEditor) -> Dict[str, Any]:
    """
    List all projects and worktrees

    Args:
        editor: ProjectEditor instance

    Returns:
        {"status": "success", "main_projects": [...], "worktrees": [...]} or {"status": "error", "error": "..."}
    """
    try:
        result = editor.list_projects()
        return create_response("success", **result)
    except Exception as e:
        return create_response("error", error=f"Unexpected error: {str(e)}")


def handle_get_mtime(editor: ProjectEditor, name: str) -> Dict[str, Any]:
    """
    Get file modification timestamp for conflict detection

    Args:
        editor: ProjectEditor instance
        name: Project name

    Returns:
        {"status": "success", "mtime": <timestamp>} or {"status": "error", "error": "..."}
    """
    try:
        mtime = editor.get_file_mtime(name)
        return create_response("success", mtime=mtime, project_name=name)
    except FileNotFoundError as e:
        return create_response("error", error=str(e))
    except Exception as e:
        return create_response("error", error=f"Unexpected error: {str(e)}")


def main():
    """Main entry point for CLI"""
    parser = argparse.ArgumentParser(
        description="Project CRUD handler for Eww integration (Feature 094)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Read project
  %(prog)s read nixos-094

  # Edit project display name
  %(prog)s edit nixos-094 --updates '{"display_name":"New Name"}'

  # Create new project
  %(prog)s create --config '{"name":"test","display_name":"Test","working_dir":"/tmp"}'

  # Delete project
  %(prog)s delete old-project

  # List all projects
  %(prog)s list

  # Get file modification time
  %(prog)s get-mtime nixos-094
"""
    )

    parser.add_argument(
        "--projects-dir",
        type=Path,
        default=None,
        help="Projects directory (default: ~/.config/i3/projects/)"
    )

    subparsers = parser.add_subparsers(dest="command", required=True, help="CRUD operation")

    # Read command
    read_parser = subparsers.add_parser("read", help="Read project configuration")
    read_parser.add_argument("name", help="Project name")

    # Edit command
    edit_parser = subparsers.add_parser("edit", help="Edit project configuration")
    edit_parser.add_argument("name", help="Project name")
    edit_parser.add_argument("--updates", required=True, help="JSON dict of fields to update")

    # Create command
    create_parser = subparsers.add_parser("create", help="Create new project")
    create_parser.add_argument("--config", required=True, help="JSON project configuration")

    # Delete command
    delete_parser = subparsers.add_parser("delete", help="Delete project")
    delete_parser.add_argument("name", help="Project name")
    delete_parser.add_argument("--force", action="store_true", help="Force delete (skip worktree check)")

    # List command
    list_parser = subparsers.add_parser("list", help="List all projects and worktrees")

    # Get mtime command
    mtime_parser = subparsers.add_parser("get-mtime", help="Get file modification time")
    mtime_parser.add_argument("name", help="Project name")

    args = parser.parse_args()

    # Initialize ProjectEditor
    editor = ProjectEditor(projects_dir=args.projects_dir)

    # Execute command
    result = None

    if args.command == "read":
        result = handle_read(editor, args.name)
    elif args.command == "edit":
        try:
            updates = json.loads(args.updates)
            result = handle_edit(editor, args.name, updates)
        except json.JSONDecodeError as e:
            result = create_response("error", error=f"Invalid JSON in --updates: {str(e)}")
    elif args.command == "create":
        try:
            config = json.loads(args.config)
            result = handle_create(editor, config)
        except json.JSONDecodeError as e:
            result = create_response("error", error=f"Invalid JSON in --config: {str(e)}")
    elif args.command == "delete":
        result = handle_delete(editor, args.name, force=args.force)
    elif args.command == "list":
        result = handle_list(editor)
    elif args.command == "get-mtime":
        result = handle_get_mtime(editor, args.name)
    else:
        result = create_response("error", error=f"Unknown command: {args.command}")

    # Output JSON (single line for Eww compatibility)
    print(json.dumps(result))

    # Exit with non-zero if error
    if result.get("status") == "error":
        sys.exit(1)


if __name__ == "__main__":
    main()
