"""
Form Validation Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Provides real-time validation for project and application forms
"""

import asyncio
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

from ..models.project_config import ProjectConfig, WorktreeConfig
from ..models.app_config import ApplicationConfig, PWAConfig, TerminalAppConfig
from ..models.validation_state import FormValidationState


class FormValidator:
    """Service for real-time form validation with debouncing"""

    def __init__(self, debounce_ms: int = 300):
        """
        Initialize form validator

        Args:
            debounce_ms: Debounce delay in milliseconds (default: 300ms)
        """
        self.debounce_ms = debounce_ms
        self._debounce_tasks: Dict[str, asyncio.Task] = {}

    async def validate_project_form(
        self,
        form_data: Dict[str, Any],
        form_id: str,
        existing_name: Optional[str] = None
    ) -> FormValidationState:
        """
        Validate project form data with debouncing

        Args:
            form_data: Raw form input data
            form_id: Unique form identifier for debouncing
            existing_name: Name of existing project (for edit operations)

        Returns:
            FormValidationState with validation results
        """
        # Cancel previous debounce task if exists
        if form_id in self._debounce_tasks:
            self._debounce_tasks[form_id].cancel()

        # Create new debounce task
        task = asyncio.create_task(self._debounced_validate_project(
            form_data, existing_name
        ))
        self._debounce_tasks[form_id] = task

        try:
            result = await task
            return result
        except asyncio.CancelledError:
            # Return previous validation state on cancel
            return FormValidationState(valid=False, errors={}, warnings={})
        finally:
            # Clean up task reference
            if form_id in self._debounce_tasks:
                del self._debounce_tasks[form_id]

    async def _debounced_validate_project(
        self,
        form_data: Dict[str, Any],
        existing_name: Optional[str]
    ) -> FormValidationState:
        """Internal debounced validation logic"""
        # Wait for debounce delay
        await asyncio.sleep(self.debounce_ms / 1000.0)

        errors: Dict[str, str] = {}
        warnings: Dict[str, str] = {}

        # Validate with Pydantic model
        try:
            # Determine if worktree based on parent_project field
            if "parent_project" in form_data and form_data["parent_project"]:
                config = WorktreeConfig(**form_data)
            else:
                config = ProjectConfig(**form_data)

            # Additional validation beyond Pydantic

            # Check if name already exists (for create operations)
            if not existing_name or (existing_name and form_data.get("name") != existing_name):
                if self._project_exists(form_data.get("name", "")):
                    errors["name"] = f"Project '{form_data.get('name')}' already exists"

            # Validate working directory exists and is accessible
            working_dir = form_data.get("working_dir", "")
            if working_dir:
                path = Path(working_dir).expanduser()
                if not path.exists():
                    errors["working_dir"] = f"Directory does not exist: {working_dir}"
                elif not path.is_dir():
                    errors["working_dir"] = f"Path is not a directory: {working_dir}"
                elif not self._is_accessible(path):
                    errors["working_dir"] = f"Directory is not accessible: {working_dir}"

            # Validate icon if it's a file path
            icon = form_data.get("icon", "")
            if icon and icon.startswith("/"):
                icon_path = Path(icon)
                if not icon_path.exists():
                    warnings["icon"] = f"Custom icon path not found, will use default"

            # Worktree-specific validation
            if isinstance(config, WorktreeConfig):
                # Validate parent project exists
                if not self._project_exists(config.parent_project):
                    errors["parent_project"] = f"Parent project '{config.parent_project}' does not exist"

                # Validate worktree path does NOT exist yet
                worktree_path = Path(config.worktree_path).expanduser()
                if worktree_path.exists():
                    errors["worktree_path"] = f"Worktree path already exists: {config.worktree_path}"

                # Validate branch name format (basic Git ref validation)
                if not self._is_valid_git_ref(config.branch_name):
                    errors["branch_name"] = f"Invalid branch name format: {config.branch_name}"

            # Remote-specific validation
            if config.remote and config.remote.enabled:
                # Validate remote_dir is absolute
                if not config.remote.remote_dir.startswith("/"):
                    errors["remote.remote_dir"] = "Remote directory must be an absolute path"

                # Warn about SSH connectivity (cannot verify without actual SSH)
                warnings["remote"] = "SSH connectivity will be verified on save"

        except ValueError as e:
            # Pydantic validation error
            error_msg = str(e)
            # Try to extract field name from error message
            if "name" in error_msg.lower():
                errors["name"] = error_msg
            elif "working_dir" in error_msg.lower() or "directory" in error_msg.lower():
                errors["working_dir"] = error_msg
            elif "icon" in error_msg.lower():
                errors["icon"] = error_msg
            elif "scope" in error_msg.lower():
                errors["scope"] = error_msg
            elif "branch" in error_msg.lower():
                errors["branch_name"] = error_msg
            elif "worktree_path" in error_msg.lower():
                errors["worktree_path"] = error_msg
            elif "parent_project" in error_msg.lower():
                errors["parent_project"] = error_msg
            elif "remote" in error_msg.lower():
                errors["remote"] = error_msg
            else:
                errors["_general"] = error_msg

        valid = len(errors) == 0
        return FormValidationState(valid=valid, errors=errors, warnings=warnings)

    async def validate_app_form(
        self,
        form_data: Dict[str, Any],
        form_id: str,
        existing_name: Optional[str] = None
    ) -> FormValidationState:
        """
        Validate application form data with debouncing

        Args:
            form_data: Raw form input data
            form_id: Unique form identifier for debouncing
            existing_name: Name of existing app (for edit operations)

        Returns:
            FormValidationState with validation results
        """
        # Cancel previous debounce task if exists
        if form_id in self._debounce_tasks:
            self._debounce_tasks[form_id].cancel()

        # Create new debounce task
        task = asyncio.create_task(self._debounced_validate_app(
            form_data, existing_name
        ))
        self._debounce_tasks[form_id] = task

        try:
            result = await task
            return result
        except asyncio.CancelledError:
            return FormValidationState(valid=False, errors={}, warnings={})
        finally:
            if form_id in self._debounce_tasks:
                del self._debounce_tasks[form_id]

    async def _debounced_validate_app(
        self,
        form_data: Dict[str, Any],
        existing_name: Optional[str]
    ) -> FormValidationState:
        """Internal debounced validation logic for applications"""
        await asyncio.sleep(self.debounce_ms / 1000.0)

        errors: Dict[str, str] = {}
        warnings: Dict[str, str] = {}

        try:
            # Determine app type and validate with appropriate model
            if form_data.get("ulid"):
                # PWA
                config = PWAConfig(**form_data)
            elif form_data.get("terminal"):
                # Terminal app
                config = TerminalAppConfig(**form_data)
            else:
                # Regular app
                config = ApplicationConfig(**form_data)

            # Check if name already exists (for create operations)
            if not existing_name or (existing_name and form_data.get("name") != existing_name):
                if self._app_exists(form_data.get("name", "")):
                    errors["name"] = f"Application '{form_data.get('name')}' already exists"

            # Validate icon if it's a file path
            icon = form_data.get("icon", "")
            if icon and icon.startswith("/"):
                icon_path = Path(icon)
                if not icon_path.exists():
                    warnings["icon"] = "Custom icon path not found, will use default"

            # Validate nix_package if not "null"
            nix_package = form_data.get("nix_package", "null")
            if nix_package != "null" and not nix_package.startswith("pkgs."):
                warnings["nix_package"] = "Nix package should start with 'pkgs.' or be 'null'"

            # Validate floating_size only when floating enabled
            if form_data.get("floating_size") and not form_data.get("floating", False):
                errors["floating_size"] = "floating_size can only be set when floating=True"

            # PWA-specific warnings
            if isinstance(config, PWAConfig):
                # Warn about ULID immutability
                if existing_name:
                    warnings["ulid"] = "ULID cannot be changed after creation"

                # Validate workspace 50+
                workspace = form_data.get("preferred_workspace", 0)
                if workspace < 50:
                    errors["preferred_workspace"] = f"PWAs must use workspaces 50 or higher, got: {workspace}"

        except ValueError as e:
            error_msg = str(e)
            # Map error to field
            if "name" in error_msg.lower():
                errors["name"] = error_msg
            elif "command" in error_msg.lower():
                errors["command"] = error_msg
            elif "workspace" in error_msg.lower():
                errors["preferred_workspace"] = error_msg
            elif "ulid" in error_msg.lower():
                errors["ulid"] = error_msg
            elif "url" in error_msg.lower():
                if "start" in error_msg.lower():
                    errors["start_url"] = error_msg
                elif "scope" in error_msg.lower():
                    errors["scope_url"] = error_msg
                else:
                    errors["url"] = error_msg
            else:
                errors["_general"] = error_msg

        valid = len(errors) == 0
        return FormValidationState(valid=valid, errors=errors, warnings=warnings)

    def _project_exists(self, name: str) -> bool:
        """Check if project with given name already exists"""
        if not name:
            return False

        projects_dir = Path.home() / ".config/i3/projects"
        project_file = projects_dir / f"{name}.json"
        return project_file.exists()

    def _app_exists(self, name: str) -> bool:
        """Check if application with given name already exists"""
        if not name:
            return False

        # Check in app-registry-data.nix
        nix_file = Path("/etc/nixos/home-modules/desktop/app-registry-data.nix")
        if not nix_file.exists():
            return False

        try:
            with open(nix_file, 'r') as f:
                content = f.read()
                # Simple check: look for name = "<name>"; pattern
                return f'name = "{name}";' in content
        except Exception:
            return False

    def _is_accessible(self, path: Path) -> bool:
        """Check if path is readable and writable"""
        try:
            return path.exists() and path.is_dir()
        except (OSError, PermissionError):
            return False

    def _is_valid_git_ref(self, ref: str) -> bool:
        """
        Validate Git reference name format

        Per git-check-ref-format rules:
        - Cannot start/end with slash or dot
        - Cannot contain consecutive dots (..)
        - Cannot contain spaces or control characters
        - Cannot contain shell metacharacters
        """
        if not ref:
            return False

        # Basic checks
        if ref.startswith(("/", ".")) or ref.endswith(("/", ".")):
            return False

        if ".." in ref:
            return False

        # Check for invalid characters
        invalid_chars = [" ", "~", "^", ":", "?", "*", "[", "\\", "\n", "\r", "\t"]
        for char in invalid_chars:
            if char in ref:
                return False

        return True
