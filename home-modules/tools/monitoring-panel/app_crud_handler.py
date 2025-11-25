"""
Application CRUD Handler

Feature 094: Enhanced Projects & Applications CRUD Interface (User Story 7 - T047)
Handles application edit/create/delete requests from Eww monitoring panel
"""

import asyncio
import json
from pathlib import Path
from typing import Dict, Any, Optional, Callable, List
from dataclasses import dataclass, asdict

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from i3_project_manager.services.app_registry_editor import AppRegistryEditor, EditResult
from i3_project_manager.models.app_config import ApplicationConfig, PWAConfig, TerminalAppConfig


@dataclass
class CRUDResponse:
    """Response from CRUD operation"""
    success: bool
    validation_errors: List[str]
    error_message: str = ""
    backup_path: Optional[str] = None
    applications: Optional[List[Dict[str, Any]]] = None


class AppCRUDHandler:
    """Handler for application CRUD operations from monitoring panel"""

    def __init__(self, nix_file_path: Optional[str] = None):
        """
        Initialize CRUD handler

        Args:
            nix_file_path: Path to app-registry-data.nix (default: system location)
        """
        self.editor = AppRegistryEditor(nix_file_path=nix_file_path)
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

        if action == "edit_app":
            return await self._handle_edit(request, callback)
        elif action == "list_apps":
            return await self._handle_list(request)
        elif action == "create_app":
            return await self._handle_create(request, callback)
        elif action == "delete_app":
            return await self._handle_delete(request, callback)
        else:
            return {
                "success": False,
                "error_message": f"Unknown action: {action}",
                "validation_errors": []
            }

    async def _handle_edit(
        self, 
        request: Dict[str, Any], 
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """Handle application edit request"""
        try:
            app_name = request.get("app_name")
            updates = request.get("updates", {})
            stream_updates = request.get("stream_updates", False)

            if not app_name:
                return {
                    "success": False,
                    "error_message": "Missing required field: app_name",
                    "validation_errors": []
                }

            if not updates:
                return {
                    "success": False,
                    "error_message": "Missing required field: updates",
                    "validation_errors": []
                }

            # Acquire lock for file operations
            async with self._operation_lock:
                # Stream validation phase update
                if stream_updates and callback:
                    await callback({"phase": "validation", "progress": 0.2})

                # Validate updates before applying
                validation_errors = await self._validate_updates(app_name, updates)
                
                if validation_errors:
                    if stream_updates and callback:
                        await callback({
                            "phase": "validation_error",
                            "errors": validation_errors
                        })
                    return {
                        "success": False,
                        "error_message": "Validation failed",
                        "validation_errors": validation_errors
                    }

                # Stream editing phase update
                if stream_updates and callback:
                    await callback({"phase": "editing", "progress": 0.5})

                # Perform edit operation
                result = self.editor.edit_application(app_name, updates)

                if not result.success:
                    return {
                        "success": False,
                        "error_message": result.error_message,
                        "validation_errors": [],
                        "backup_path": result.backup_path
                    }

                # Stream complete phase update
                if stream_updates and callback:
                    await callback({"phase": "complete", "progress": 1.0})

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "backup_path": result.backup_path
                }

        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    async def _handle_list(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle application list request"""
        try:
            # Read current applications from Nix file
            content = self.editor.read_file()
            
            # Parse all mkApp blocks
            import re
            pattern = r'\(mkApp \{[^}]+\}[^)]*\)'
            matches = re.finditer(pattern, content, re.MULTILINE | re.DOTALL)

            applications = []
            for match in matches:
                block = match.group(0)
                fields = self.editor._parse_mkapp_fields(block)
                applications.append(fields)

            return {
                "success": True,
                "applications": applications,
                "error_message": "",
                "validation_errors": []
            }

        except Exception as e:
            return {
                "success": False,
                "error_message": f"Failed to list applications: {e}",
                "validation_errors": [],
                "applications": []
            }

    async def _handle_create(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """Handle application creation request"""
        try:
            config_data = request.get("config")
            if not config_data:
                return {
                    "success": False,
                    "error_message": "Missing required field: config",
                    "validation_errors": []
                }

            # Determine app type and create config
            if config_data.get("ulid"):
                config = PWAConfig(**config_data)
            elif config_data.get("terminal"):
                config = TerminalAppConfig(**config_data)
            else:
                config = ApplicationConfig(**config_data)

            # Add application
            async with self._operation_lock:
                result = self.editor.add_application(config)

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "ulid": result.get("ulid"),
                    "rebuild_required": True
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

    async def _handle_delete(
        self,
        request: Dict[str, Any],
        callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """Handle application deletion request"""
        try:
            app_name = request.get("app_name")
            if not app_name:
                return {
                    "success": False,
                    "error_message": "Missing required field: app_name",
                    "validation_errors": []
                }

            # Delete application
            async with self._operation_lock:
                result = self.editor.delete_application(app_name)

                return {
                    "success": True,
                    "error_message": "",
                    "validation_errors": [],
                    "pwa_warning": result.get("pwa_warning"),
                    "rebuild_required": True
                }

        except ValueError as e:
            return {
                "success": False,
                "error_message": str(e),
                "validation_errors": []
            }
        except Exception as e:
            return {
                "success": False,
                "error_message": f"Unexpected error: {e}",
                "validation_errors": []
            }

    async def _validate_updates(
        self, 
        app_name: str, 
        updates: Dict[str, Any]
    ) -> List[str]:
        """
        Validate update fields before applying

        Returns:
            List of validation error messages (empty if valid)
        """
        errors = []

        try:
            # Read current app config
            block = self.editor.find_app_block(app_name)
            if not block:
                errors.append(f"Application '{app_name}' not found")
                return errors

            # Parse current fields
            fields = self.editor._parse_mkapp_fields(block)
            
            # Apply updates to get complete field set
            fields.update(updates)

            # Validate using Pydantic models
            try:
                if fields.get("ulid"):
                    # PWA
                    PWAConfig(**fields)
                elif fields.get("terminal"):
                    # Terminal app
                    TerminalAppConfig(**fields)
                else:
                    # Regular app
                    ApplicationConfig(**fields)
            except Exception as e:
                # Extract validation errors from Pydantic exception
                if hasattr(e, 'errors'):
                    for err in e.errors():
                        field = ".".join(str(loc) for loc in err['loc'])
                        msg = err['msg']
                        errors.append(f"{field}: {msg}")
                else:
                    errors.append(str(e))

        except Exception as e:
            errors.append(f"Validation error: {e}")

        return errors
