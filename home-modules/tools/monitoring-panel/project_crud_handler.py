"""
Project CRUD Handler

Feature 094: Enhanced Projects & Applications CRUD Interface (User Story 5 - T056)
Handles project and worktree edit/create/delete requests from Eww monitoring panel
"""

import asyncio
import json
from pathlib import Path
from typing import Dict, Any, Optional, Callable, List
from dataclasses import dataclass

import sys
# Add parent directory for i3_project_manager imports
sys.path.insert(0, str(Path(__file__).parent.parent))
# Add current directory for cli_executor import
sys.path.insert(0, str(Path(__file__).parent))

from i3_project_manager.services.project_editor import ProjectEditor
from i3_project_manager.models.project_config import ProjectConfig, WorktreeConfig
from cli_executor import CLIExecutor


def check_project_name_exists(name: str, projects_dir: Path = None) -> bool:
    """
    Check if a project with the given name already exists

    Args:
        name: Project name to check
        projects_dir: Path to projects directory (default: ~/.config/i3/projects/)

    Returns:
        True if project exists, False otherwise
    """
    if projects_dir is None:
        projects_dir = Path.home() / ".config" / "i3" / "projects"

    project_file = projects_dir / f"{name}.json"
    return project_file.exists()


@dataclass
class CRUDResponse:
    """Response from CRUD operation"""
    success: bool
    validation_errors: List[str]
    error_message: str = ""
    backup_path: Optional[str] = None


class ProjectCRUDHandler:
    """Handler for project and worktree CRUD operations from monitoring panel"""

    def __init__(self, projects_dir: Optional[str] = None):
        """
        Initialize CRUD handler

        Args:
            projects_dir: Path to projects directory (default: ~/.config/i3/projects/)
        """
        self.editor = ProjectEditor(
            projects_dir=Path(projects_dir) if projects_dir else None
        )
        self.cli_executor = CLIExecutor(timeout=60)
        self._operation_lock = asyncio.Lock()

    async def handle_request(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """
        Handle CRUD request from monitoring panel

        Args:
            request: Request dict with action and parameters
            callback: Optional callback for streaming updates

        Returns:
            Response dict with results
        """
        action = request.get("action")

        if action == "edit_project":
            return await self._handle_edit_project(request, callback)
        elif action == "list_projects":
            return await self._handle_list_projects(request)
        elif action == "create_project":
            return await self._handle_create_project(request, callback)
        elif action == "delete_project":
            return await self._handle_delete_project(request, callback)
        # Worktree operations
        elif action == "create_worktree":
            return await self._handle_create_worktree(request, callback)
        elif action == "edit_worktree":
            return await self._handle_edit_worktree(request, callback)
        elif action == "delete_worktree":
            return await self._handle_delete_worktree(request, callback)
        else:
            return {
                "success": False,
                "error_message": f"Unknown action: {action}",
                "validation_errors": []
            }

    async def _handle_edit_project(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """Handle project edit request"""
        try:
            project_name = request.get("project_name")
            updates = request.get("updates", {})
            stream_updates = request.get("stream_updates", False)

            if not project_name:
                return {
                    "success": False,
                    "error_message": "Missing required field: project_name",
                    "validation_errors": []
                }

            if not updates:
                return {
                    "success": False,
                    "error_message": "Missing required field: updates",
                    "validation_errors": []
                }

            async with self._operation_lock:
                if stream_updates and callback:
                    await callback({"phase": "validation", "progress": 0.2})

                # Perform edit operation
                result = self.editor.edit_project(project_name, updates)

                if stream_updates and callback:
                    await callback({"phase": "complete", "progress": 1.0})

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "conflict": result.get("conflict", False)
                }

        except FileNotFoundError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": []
            }
        except ValueError as e:
            return {
                "success": False,
                "error_message": "Validation failed",
                "validation_errors": [str(e)]
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    async def _handle_list_projects(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle project list request"""
        try:
            result = self.editor.list_projects()
            return {
                "success": True,
                "main_projects": result["main_projects"],
                "worktrees": result["worktrees"],
                "error_message": "",
                "validation_errors": []
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Failed to list projects: {e}",
                "validation_errors": [],
                "main_projects": [],
                "worktrees": []
            }

    async def _handle_create_project(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """Handle project creation request"""
        try:
            config_data = request.get("config")
            if not config_data:
                return {
                    "success": False,
                    "error_message": "Missing required field: config",
                    "validation_errors": []
                }

            config = ProjectConfig(**config_data)

            async with self._operation_lock:
                result = self.editor.create_project(config)

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "path": result.get("path")
                }

        except ValueError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": [str(e)]
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    async def _handle_delete_project(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """Handle project deletion request"""
        try:
            project_name = request.get("project_name")
            force = request.get("force", False)

            if not project_name:
                return {
                    "success": False,
                    "error_message": "Missing required field: project_name",
                    "validation_errors": []
                }

            async with self._operation_lock:
                result = self.editor.delete_project(project_name, force=force)

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "backup": result.get("backup")
                }

        except FileNotFoundError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": []
            }
        except ValueError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": [str(e)]
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    # -------------------------------------------------------------------------
    # Worktree Operations (T056 - User Story 5)
    # -------------------------------------------------------------------------

    async def _handle_create_worktree(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """
        Handle worktree creation request

        Creates both:
        1. Git worktree via `git worktree add`
        2. i3pm project JSON configuration

        Args:
            request: {
                "parent_project": str,  # Name of parent project
                "branch_name": str,     # Git branch name
                "worktree_path": str,   # Absolute path for worktree
                "display_name": str,    # Display name for project
                "icon": str             # Emoji icon
            }
            callback: Optional progress callback

        Returns:
            Response dict with success status and errors
        """
        try:
            parent_name = request.get("parent_project")
            branch_name = request.get("branch_name")
            worktree_path = request.get("worktree_path")
            display_name = request.get("display_name")
            icon = request.get("icon", "🌿")

            # Validate required fields
            errors = []
            if not parent_name:
                errors.append("Missing required field: parent_project")
            if not branch_name:
                errors.append("Missing required field: branch_name")
            if not worktree_path:
                errors.append("Missing required field: worktree_path")
            if not display_name:
                errors.append("Missing required field: display_name")

            if errors:
                return {
                    "success": False,
                    "error_message": "Validation failed",
                    "validation_errors": errors
                }

            async with self._operation_lock:
                # Phase 1: Validate parent project exists
                if callback:
                    await callback({"phase": "validation", "progress": 0.1})

                try:
                    parent_data = self.editor.read_project(parent_name)
                except FileNotFoundError:
                    return {
                        "success": False,
                        "error_message": f"Parent project '{parent_name}' not found",
                        "validation_errors": [f"Parent project '{parent_name}' does not exist"]
                    }

                parent_dir = parent_data.get("directory") or parent_data.get("working_dir")
                if not parent_dir:
                    return {
                        "success": False,
                        "error_message": "Parent project has no working directory",
                        "validation_errors": []
                    }

                # Phase 2: Create Git worktree
                if callback:
                    await callback({"phase": "git_worktree", "progress": 0.3})

                git_result = await self.cli_executor.execute_git_command(
                    ["worktree", "add", worktree_path, branch_name],
                    cwd=Path(parent_dir)
                )

                if not git_result.success:
                    return {
                        "success": False,
                        "error_message": git_result.user_message or "Git worktree creation failed",
                        "validation_errors": [],
                        "git_error": git_result.stderr,
                        "error_category": git_result.error_category
                    }

                # Phase 3: Create i3pm project configuration
                if callback:
                    await callback({"phase": "project_config", "progress": 0.7})

                # Generate worktree project name from branch
                worktree_name = self._generate_worktree_name(parent_name, branch_name)

                config = WorktreeConfig(
                    name=worktree_name,
                    display_name=display_name,
                    icon=icon,
                    working_dir=worktree_path,
                    scope="scoped",
                    worktree_path=worktree_path,
                    branch_name=branch_name,
                    parent_project=parent_name
                )

                result = self.editor.create_project(config)

                if callback:
                    await callback({"phase": "complete", "progress": 1.0})

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "worktree_name": worktree_name,
                    "path": result.get("path")
                }

        except ValueError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": [str(e)]
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    async def _handle_edit_worktree(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """
        Handle worktree edit request

        Per spec.md US5 scenario 6: branch_name and worktree_path are read-only
        Only display_name and icon can be edited

        Args:
            request: {
                "worktree_name": str,   # Name of worktree project
                "updates": {
                    "display_name": str,
                    "icon": str
                }
            }
            callback: Optional progress callback

        Returns:
            Response dict with success status
        """
        try:
            worktree_name = request.get("worktree_name")
            updates = request.get("updates", {})

            if not worktree_name:
                return {
                    "success": False,
                    "error_message": "Missing required field: worktree_name",
                    "validation_errors": []
                }

            # Filter to only allow editable fields
            allowed_fields = {"display_name", "icon", "scope"}
            filtered_updates = {
                k: v for k, v in updates.items() if k in allowed_fields
            }

            if not filtered_updates:
                return {
                    "success": False,
                    "error_message": "No valid updates provided (only display_name, icon, scope allowed)",
                    "validation_errors": []
                }

            async with self._operation_lock:
                if callback:
                    await callback({"phase": "editing", "progress": 0.5})

                result = self.editor.edit_project(worktree_name, filtered_updates)

                if callback:
                    await callback({"phase": "complete", "progress": 1.0})

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "conflict": result.get("conflict", False)
                }

        except FileNotFoundError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": []
            }
        except ValueError as e:
            return {
                "success": False,
                "error_message": "Validation failed",
                "validation_errors": [str(e)]
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    async def _handle_delete_worktree(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """
        Handle worktree deletion request

        Performs:
        1. Git worktree removal via `git worktree remove`
        2. i3pm project JSON deletion

        Args:
            request: {
                "worktree_name": str,   # Name of worktree project
                "force": bool           # Force delete even with uncommitted changes
            }
            callback: Optional progress callback

        Returns:
            Response dict with success status and warnings
        """
        try:
            worktree_name = request.get("worktree_name")
            force = request.get("force", False)

            if not worktree_name:
                return {
                    "success": False,
                    "error_message": "Missing required field: worktree_name",
                    "validation_errors": []
                }

            async with self._operation_lock:
                # Phase 1: Read worktree config
                if callback:
                    await callback({"phase": "validation", "progress": 0.1})

                try:
                    worktree_data = self.editor.read_project(worktree_name)
                except FileNotFoundError:
                    return {
                        "success": False,
                        "error_message": f"Worktree '{worktree_name}' not found",
                        "validation_errors": []
                    }

                # Verify it's actually a worktree
                if "parent_project" not in worktree_data:
                    return {
                        "success": False,
                        "error_message": f"'{worktree_name}' is not a worktree (use delete_project instead)",
                        "validation_errors": []
                    }

                worktree_path = worktree_data.get("worktree_path")
                parent_name = worktree_data.get("parent_project")

                # Phase 2: Remove Git worktree
                if callback:
                    await callback({"phase": "git_cleanup", "progress": 0.4})

                # Get parent working directory
                try:
                    parent_data = self.editor.read_project(parent_name)
                    parent_dir = parent_data.get("directory") or parent_data.get("working_dir")
                except FileNotFoundError:
                    parent_dir = None

                git_warning = None
                if parent_dir and worktree_path:
                    git_args = ["worktree", "remove"]
                    if force:
                        git_args.append("--force")
                    git_args.append(worktree_path)

                    git_result = await self.cli_executor.execute_git_command(
                        git_args,
                        cwd=Path(parent_dir)
                    )

                    if not git_result.success:
                        # Git removal failed - warn but continue with project deletion
                        git_warning = f"Git worktree removal failed: {git_result.user_message}. Project config will be deleted but Git worktree may still exist."

                # Phase 3: Delete project config
                if callback:
                    await callback({"phase": "config_cleanup", "progress": 0.7})

                result = self.editor.delete_project(worktree_name, force=True)

                if callback:
                    await callback({"phase": "complete", "progress": 1.0})

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "git_warning": git_warning,
                    "backup": result.get("backup")
                }

        except FileNotFoundError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": []
            }
        except ValueError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": [str(e)]
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    def _generate_worktree_name(self, parent_name: str, branch_name: str) -> str:
        """
        Generate worktree project name from parent and branch

        Args:
            parent_name: Parent project name
            branch_name: Git branch name

        Returns:
            Generated worktree name (e.g., "nixos-feature-123")
        """
        # Clean branch name for use in project name
        clean_branch = branch_name.replace("/", "-").replace("_", "-").lower()
        # Remove common prefixes
        for prefix in ["feature-", "feat-", "bugfix-", "fix-", "release-"]:
            if clean_branch.startswith(prefix):
                clean_branch = clean_branch[len(prefix):]
                break

        return f"{parent_name}-{clean_branch}"


# CLI interface for shell script usage
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Project CRUD Handler CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Edit command
    edit_parser = subparsers.add_parser("edit", help="Edit a project")
    edit_parser.add_argument("project_name", help="Project name")
    edit_parser.add_argument("--updates", required=True, help="JSON object of updates")

    # List command
    list_parser = subparsers.add_parser("list", help="List all projects")

    # Delete command
    delete_parser = subparsers.add_parser("delete", help="Delete a project")
    delete_parser.add_argument("project_name", help="Project name")
    delete_parser.add_argument("--force", action="store_true", help="Force delete")

    # Worktree create command
    wt_create_parser = subparsers.add_parser("create-worktree", help="Create a worktree")
    wt_create_parser.add_argument("--parent", required=True, help="Parent project name")
    wt_create_parser.add_argument("--branch", required=True, help="Git branch name")
    wt_create_parser.add_argument("--path", required=True, help="Worktree path")
    wt_create_parser.add_argument("--display-name", required=True, help="Display name")
    wt_create_parser.add_argument("--icon", default="🌿", help="Icon emoji")

    # Worktree edit command
    wt_edit_parser = subparsers.add_parser("edit-worktree", help="Edit a worktree")
    wt_edit_parser.add_argument("worktree_name", help="Worktree name")
    wt_edit_parser.add_argument("--updates", required=True, help="JSON object of updates")

    # Worktree delete command
    wt_delete_parser = subparsers.add_parser("delete-worktree", help="Delete a worktree")
    wt_delete_parser.add_argument("worktree_name", help="Worktree name")
    wt_delete_parser.add_argument("--force", action="store_true", help="Force delete")

    args = parser.parse_args()

    handler = ProjectCRUDHandler()

    if args.command == "edit":
        try:
            updates = json.loads(args.updates)
            request = {
                "action": "edit_project",
                "project_name": args.project_name,
                "updates": updates
            }
            result = asyncio.run(handler.handle_request(request))

            if result.get("success"):
                print(json.dumps({"status": "success"}))
            else:
                print(json.dumps({
                    "status": "error",
                    "error": result.get("error_message", "Unknown error"),
                    "validation_errors": result.get("validation_errors", [])
                }))
                sys.exit(1)

        except json.JSONDecodeError as e:
            print(json.dumps({"status": "error", "error": f"Invalid JSON: {e}"}))
            sys.exit(1)

    elif args.command == "list":
        request = {"action": "list_projects"}
        result = asyncio.run(handler.handle_request(request))
        print(json.dumps(result))

    elif args.command == "delete":
        request = {
            "action": "delete_project",
            "project_name": args.project_name,
            "force": args.force
        }
        result = asyncio.run(handler.handle_request(request))

        if result.get("success"):
            print(json.dumps({"status": "success", "backup": result.get("backup")}))
        else:
            print(json.dumps({
                "status": "error",
                "error": result.get("error_message", "Unknown error")
            }))
            sys.exit(1)

    elif args.command == "create-worktree":
        request = {
            "action": "create_worktree",
            "parent_project": args.parent,
            "branch_name": args.branch,
            "worktree_path": args.path,
            "display_name": args.display_name,
            "icon": args.icon
        }
        result = asyncio.run(handler.handle_request(request))

        if result.get("success"):
            print(json.dumps({
                "status": "success",
                "worktree_name": result.get("worktree_name"),
                "path": result.get("path")
            }))
        else:
            print(json.dumps({
                "status": "error",
                "error": result.get("error_message", "Unknown error"),
                "validation_errors": result.get("validation_errors", []),
                "error_category": result.get("error_category")
            }))
            sys.exit(1)

    elif args.command == "edit-worktree":
        try:
            updates = json.loads(args.updates)
            request = {
                "action": "edit_worktree",
                "worktree_name": args.worktree_name,
                "updates": updates
            }
            result = asyncio.run(handler.handle_request(request))

            if result.get("success"):
                print(json.dumps({"status": "success"}))
            else:
                print(json.dumps({
                    "status": "error",
                    "error": result.get("error_message", "Unknown error"),
                    "validation_errors": result.get("validation_errors", [])
                }))
                sys.exit(1)

        except json.JSONDecodeError as e:
            print(json.dumps({"status": "error", "error": f"Invalid JSON: {e}"}))
            sys.exit(1)

    elif args.command == "delete-worktree":
        request = {
            "action": "delete_worktree",
            "worktree_name": args.worktree_name,
            "force": args.force
        }
        result = asyncio.run(handler.handle_request(request))

        if result.get("success"):
            print(json.dumps({
                "status": "success",
                "git_warning": result.get("git_warning"),
                "backup": result.get("backup")
            }))
        else:
            print(json.dumps({
                "status": "error",
                "error": result.get("error_message", "Unknown error")
            }))
            sys.exit(1)
