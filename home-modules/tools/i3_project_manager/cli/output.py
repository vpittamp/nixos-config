"""Output formatting utilities for CLI commands.

T091: JSON output format support for all CLI commands.
Provides both rich formatted output and machine-readable JSON output.
"""

import json
import sys
from typing import Any, Dict, List, Optional, Union
from datetime import datetime
from pathlib import Path


class OutputFormatter:
    """Format output as either rich text or JSON.

    T091: Centralized output formatting with --json flag support
    SC-036: Consistent formatting across all commands

    Examples:
        >>> fmt = OutputFormatter(json_mode=False)
        >>> fmt.print_success("Operation completed")
        ✓ Operation completed

        >>> fmt = OutputFormatter(json_mode=True)
        >>> fmt.print_success("Operation completed")
        {"status": "success", "message": "Operation completed"}
    """

    def __init__(self, json_mode: bool = False):
        """Initialize output formatter.

        Args:
            json_mode: If True, output JSON instead of rich text
        """
        self.json_mode = json_mode
        self._json_result: Dict[str, Any] = {}

    def set_result(self, **kwargs: Any) -> None:
        """Set JSON result fields.

        Args:
            **kwargs: Key-value pairs to include in JSON output
        """
        self._json_result.update(kwargs)

    def print_success(self, message: str) -> None:
        """Print success message.

        Args:
            message: Success message
        """
        if self.json_mode:
            self.set_result(status="success", message=message)
        else:
            from .commands import print_success
            print_success(message)

    def print_error(self, message: str, remediation: Optional[str] = None) -> None:
        """Print error message.

        Args:
            message: Error message
            remediation: Optional remediation steps
        """
        if self.json_mode:
            result = {"status": "error", "message": message}
            if remediation:
                result["remediation"] = remediation
            self.set_result(**result)
        else:
            if remediation:
                from .commands import print_error_with_remediation
                print_error_with_remediation(message, remediation)
            else:
                from .commands import print_error
                print_error(message)

    def print_info(self, message: str) -> None:
        """Print info message.

        Args:
            message: Info message
        """
        if self.json_mode:
            # Don't include info messages in JSON output
            pass
        else:
            from .commands import print_info
            print_info(message)

    def print_warning(self, message: str) -> None:
        """Print warning message.

        Args:
            message: Warning message
        """
        if self.json_mode:
            self.set_result(status="warning", message=message)
        else:
            from .commands import print_warning
            print_warning(message)

    def output(self, data: Optional[Dict[str, Any]] = None, file=None) -> None:
        """Output final result.

        In JSON mode, outputs accumulated JSON result.
        In rich mode, does nothing (output already printed).

        Args:
            data: Optional data to merge into JSON result
            file: Output file (default: stdout)
        """
        if self.json_mode:
            if file is None:
                file = sys.stdout
            if data:
                self._json_result.update(data)
            print(json.dumps(self._json_result, indent=2, cls=ProjectJSONEncoder), file=file)


class ProjectJSONEncoder(json.JSONEncoder):
    """Custom JSON encoder for project objects.

    Handles datetime, Path, and custom project objects.
    """

    def default(self, obj: Any) -> Any:
        """Encode custom objects.

        Args:
            obj: Object to encode

        Returns:
            JSON-serializable representation
        """
        if isinstance(obj, datetime):
            return obj.isoformat()
        elif isinstance(obj, Path):
            return str(obj)
        elif hasattr(obj, "to_dict"):
            return obj.to_dict()
        elif hasattr(obj, "__dict__"):
            # Fallback: serialize object attributes
            return {
                k: v for k, v in obj.__dict__.items()
                if not k.startswith("_")
            }
        return super().default(obj)


def format_project_list_json(projects: List[Any], current: Optional[str] = None) -> Dict[str, Any]:
    """Format project list as JSON.

    Args:
        projects: List of Project objects
        current: Currently active project name

    Returns:
        JSON-serializable dictionary
    """
    return {
        "total": len(projects),
        "current": current,
        "projects": [
            {
                "name": p.name,
                "display_name": p.display_name or p.name,
                "directory": str(p.directory),
                "icon": p.icon,
                "scoped_classes": p.scoped_classes,
                "is_current": p.name == current,
                "created_at": p.created_at.isoformat() if hasattr(p, "created_at") else None,
                "modified_at": p.modified_at.isoformat() if hasattr(p, "modified_at") else None,
            }
            for p in projects
        ]
    }


def format_project_json(project: Any, is_active: bool = False, window_count: int = 0) -> Dict[str, Any]:
    """Format single project as JSON.

    Args:
        project: Project object
        is_active: Whether project is currently active
        window_count: Number of open windows

    Returns:
        JSON-serializable dictionary
    """
    return {
        "name": project.name,
        "display_name": project.display_name or project.name,
        "directory": str(project.directory),
        "icon": project.icon,
        "scoped_classes": project.scoped_classes,
        "is_active": is_active,
        "window_count": window_count,
        "workspace_preferences": project.workspace_preferences if hasattr(project, "workspace_preferences") else {},
        "auto_launch": [
            {
                "command": app.command,
                "workspace": app.workspace if hasattr(app, "workspace") else None
            }
            for app in (project.auto_launch if hasattr(project, "auto_launch") else [])
        ],
        "saved_layouts": project.saved_layouts if hasattr(project, "saved_layouts") else [],
        "created_at": project.created_at.isoformat() if hasattr(project, "created_at") else None,
        "modified_at": project.modified_at.isoformat() if hasattr(project, "modified_at") else None,
    }


def format_switch_result_json(
    project_name: str,
    success: bool,
    elapsed_ms: float,
    error_msg: Optional[str] = None,
    no_launch: bool = False,
) -> Dict[str, Any]:
    """Format switch result as JSON.

    Args:
        project_name: Name of project switched to
        success: Whether switch succeeded
        elapsed_ms: Time elapsed in milliseconds
        error_msg: Optional error message
        no_launch: Whether auto-launch was disabled

    Returns:
        JSON-serializable dictionary
    """
    result = {
        "status": "success" if success else "error",
        "project": project_name,
        "elapsed_ms": round(elapsed_ms, 2),
    }

    if not success and error_msg:
        result["error"] = error_msg

    if no_launch:
        result["auto_launch"] = False

    return result


def format_daemon_status_json(status: Dict[str, Any]) -> Dict[str, Any]:
    """Format daemon status as JSON.

    Args:
        status: Raw daemon status dictionary

    Returns:
        JSON-serializable dictionary with formatted fields
    """
    return {
        "status": "running",
        "active_project": status.get("active_project"),
        "tracked_windows": status.get("tracked_windows", 0),
        "total_windows": status.get("total_windows", 0),
        "event_count": status.get("event_count", 0),
        "event_rate": round(status.get("event_rate", 0.0), 2),
        "uptime_seconds": status.get("uptime_seconds", 0),
        "error_count": status.get("error_count", 0),
    }
