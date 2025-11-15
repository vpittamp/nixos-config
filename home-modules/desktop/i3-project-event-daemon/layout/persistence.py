"""
Layout Persistence Module

Feature 030: Production Readiness
Task T034: Persist layout to ~/.local/share/i3pm/layouts/
Task T035: Load layout from disk by name

Handles saving and loading layout snapshots to/from disk.
"""

import logging
import json
from pathlib import Path
from typing import List, Optional
from datetime import datetime

try:
    from .models import LayoutSnapshot
except ImportError:
    from models import LayoutSnapshot

logger = logging.getLogger(__name__)


class LayoutPersistence:
    """
    Manages layout snapshot persistence

    Layouts are stored in: ~/.local/share/i3pm/layouts/<project>/<name>.json
    """

    def __init__(self, layouts_dir: Optional[Path] = None):
        """
        Initialize layout persistence

        Args:
            layouts_dir: Directory for layout storage (default: ~/.local/share/i3pm/layouts/)
        """
        self.layouts_dir = layouts_dir or Path.home() / ".local/share/i3pm/layouts"

    def save_layout(self, snapshot: LayoutSnapshot) -> Path:
        """
        Save layout snapshot to disk

        Args:
            snapshot: LayoutSnapshot to save

        Returns:
            Path to saved file
        """
        # Create project directory
        project_dir = self.layouts_dir / snapshot.project
        project_dir.mkdir(parents=True, exist_ok=True)

        # Generate filename
        filename = f"{snapshot.name}.json"
        filepath = project_dir / filename

        # Convert to dict (Pydantic v2 uses model_dump)
        snapshot_dict = snapshot.model_dump(mode='python')

        # Ensure datetime objects are ISO strings
        snapshot_dict = self._serialize_datetimes(snapshot_dict)

        # Write to file
        with open(filepath, 'w') as f:
            json.dump(snapshot_dict, f, indent=2, default=str)

        # Feature 076 T020: Log mark metadata statistics
        windows_with_marks = 0
        total_windows = 0
        for workspace_data in snapshot.workspace_layouts:
            for window in workspace_data.windows:
                total_windows += 1
                if hasattr(window, 'marks_metadata') and window.marks_metadata:
                    windows_with_marks += 1

        if windows_with_marks > 0:
            logger.info(
                f"Saved layout snapshot: {filepath} "
                f"({windows_with_marks}/{total_windows} windows with mark metadata)"
            )
        else:
            logger.info(f"Saved layout snapshot: {filepath}")

        return filepath

    def load_layout(self, name: str, project: str = "global") -> Optional[LayoutSnapshot]:
        """
        Load layout snapshot from disk

        Args:
            name: Layout snapshot name
            project: Project name (default: "global")

        Returns:
            LayoutSnapshot or None if not found
        """
        # Build filepath
        filepath = self.layouts_dir / project / f"{name}.json"

        if not filepath.exists():
            logger.warning(f"Layout not found: {filepath}")
            return None

        try:
            # Load JSON
            with open(filepath, 'r') as f:
                data = json.load(f)

            # Feature 074: Strict validation - enforce required fields (no backward compatibility)
            # Check for required top-level fields
            required_top_level = ['focused_workspace']
            missing_top = [f for f in required_top_level if f not in data]
            if missing_top:
                error_msg = (
                    f"Layout '{name}' is incompatible (missing required fields: {', '.join(missing_top)}).\n"
                    f"This layout was created before Feature 074 (Session Management).\n"
                    f"Migration required: Re-save your layouts with: i3pm layout save {name}"
                )
                logger.error(error_msg)
                raise ValueError(error_msg)

            # Check for required window fields
            for ws in data.get('workspace_layouts', []):
                for window in ws.get('windows', []):
                    required_window_fields = ['cwd', 'focused', 'app_registry_name', 'restoration_mark']
                    missing_window = [f for f in required_window_fields if f not in window]
                    if missing_window:
                        error_msg = (
                            f"Layout '{name}' has incompatible windows (missing fields: {', '.join(missing_window)}).\n"
                            f"This layout was created before Feature 074 (Session Management).\n"
                            f"Migration required: Re-save this layout with: i3pm layout save {name}"
                        )
                        logger.error(error_msg)
                        raise ValueError(error_msg)

            # Reconstruct LayoutSnapshot (Pydantic will enforce types)
            snapshot = LayoutSnapshot(**data)

            logger.info(f"Loaded layout snapshot: {filepath}")

            return snapshot

        except ValueError as e:
            # Re-raise validation errors with original message
            logger.error(f"Layout validation failed: {e}")
            raise
        except Exception as e:
            logger.error(f"Failed to load layout {filepath}: {e}")
            return None

    def list_layouts(self, project: Optional[str] = None) -> List[dict]:
        """
        List available layout snapshots

        Args:
            project: Filter by project name (optional)

        Returns:
            List of layout metadata dictionaries
        """
        layouts = []

        if project:
            # List layouts for specific project
            project_dir = self.layouts_dir / project
            if project_dir.exists():
                layouts.extend(self._list_layouts_in_dir(project_dir, project))
        else:
            # List layouts for all projects
            if self.layouts_dir.exists():
                for project_dir in self.layouts_dir.iterdir():
                    if project_dir.is_dir():
                        layouts.extend(
                            self._list_layouts_in_dir(project_dir, project_dir.name)
                        )

        return layouts

    def _list_layouts_in_dir(self, project_dir: Path, project: str) -> List[dict]:
        """
        List layouts in a project directory

        Args:
            project_dir: Path to project directory
            project: Project name

        Returns:
            List of layout metadata
        """
        layouts = []

        for layout_file in project_dir.glob("*.json"):
            try:
                # Load metadata only
                with open(layout_file, 'r') as f:
                    data = json.load(f)

                layout_info = {
                    "name": data.get("name", layout_file.stem),
                    "project": project,
                    "created_at": data.get("created_at"),
                    "total_windows": data.get("metadata", {}).get("total_windows", 0),
                    "total_workspaces": data.get("metadata", {}).get("total_workspaces", 0),
                    "total_monitors": data.get("metadata", {}).get("total_monitors", 0),
                    "file_path": str(layout_file),
                }

                layouts.append(layout_info)

            except Exception as e:
                logger.warning(f"Failed to read layout metadata from {layout_file}: {e}")
                continue

        return layouts

    def delete_layout(self, name: str, project: str = "global") -> bool:
        """
        Delete layout snapshot from disk

        Args:
            name: Layout snapshot name
            project: Project name

        Returns:
            True if deleted, False if not found
        """
        filepath = self.layouts_dir / project / f"{name}.json"

        if not filepath.exists():
            logger.warning(f"Layout not found: {filepath}")
            return False

        try:
            filepath.unlink()
            logger.info(f"Deleted layout snapshot: {filepath}")
            return True

        except Exception as e:
            logger.error(f"Failed to delete layout {filepath}: {e}")
            return False

    def _serialize_datetimes(self, obj):
        """
        Recursively convert datetime objects to ISO strings

        Args:
            obj: Object to serialize

        Returns:
            Serialized object
        """
        if isinstance(obj, datetime):
            return obj.isoformat()
        elif isinstance(obj, dict):
            return {k: self._serialize_datetimes(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [self._serialize_datetimes(item) for item in obj]
        else:
            return obj


# Global instance
_persistence_instance: Optional[LayoutPersistence] = None


def get_layout_persistence() -> LayoutPersistence:
    """
    Get global layout persistence instance

    Returns:
        LayoutPersistence singleton
    """
    global _persistence_instance
    if _persistence_instance is None:
        _persistence_instance = LayoutPersistence()
    return _persistence_instance


def save_layout(snapshot: LayoutSnapshot) -> Path:
    """
    Convenience function to save layout

    Args:
        snapshot: LayoutSnapshot to save

    Returns:
        Path to saved file
    """
    persistence = get_layout_persistence()
    return persistence.save_layout(snapshot)


def load_layout(name: str, project: str = "global") -> Optional[LayoutSnapshot]:
    """
    Convenience function to load layout

    Args:
        name: Layout snapshot name
        project: Project name

    Returns:
        LayoutSnapshot or None
    """
    persistence = get_layout_persistence()
    return persistence.load_layout(name, project)


def list_layouts(project: Optional[str] = None) -> List[dict]:
    """
    Convenience function to list layouts

    Args:
        project: Filter by project name (optional)

    Returns:
        List of layout metadata
    """
    persistence = get_layout_persistence()
    return persistence.list_layouts(project)


def delete_layout(name: str, project: str = "global") -> bool:
    """
    Convenience function to delete layout

    Args:
        name: Layout snapshot name
        project: Project name

    Returns:
        True if deleted, False if not found
    """
    persistence = get_layout_persistence()
    return persistence.delete_layout(name, project)
