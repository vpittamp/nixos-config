"""
Conflict Detection Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Detects file modification conflicts via timestamp comparison per spec.md Q2
"""

import difflib
from pathlib import Path
from typing import Optional, Dict, Any

import sys
sys.path.append(str(Path(__file__).parent.parent / "i3_project_manager"))

from models.validation_state import ConflictResolutionState


class ConflictDetector:
    """Service for detecting file modification conflicts during edit operations"""

    def check_project_conflict(
        self,
        project_name: str,
        ui_start_mtime: float
    ) -> ConflictResolutionState:
        """
        Check if project JSON file was modified externally during edit

        Args:
            project_name: Project name
            ui_start_mtime: Timestamp when UI started editing (seconds since epoch)

        Returns:
            ConflictResolutionState with conflict status and diff preview
        """
        projects_dir = Path.home() / ".config/i3/projects"
        project_file = projects_dir / f"{project_name}.json"

        if not project_file.exists():
            # File was deleted externally - treat as conflict
            return ConflictResolutionState(
                has_conflict=True,
                file_mtime=0.0,
                ui_mtime=ui_start_mtime,
                diff_preview="< file: DELETED\n> ui: Still has pending changes"
            )

        # Get current file modification time
        file_mtime = project_file.stat().st_mtime

        # Check if file was modified after UI started editing
        has_conflict = file_mtime > ui_start_mtime

        if not has_conflict:
            return ConflictResolutionState(
                has_conflict=False,
                file_mtime=file_mtime,
                ui_mtime=ui_start_mtime,
                diff_preview=""
            )

        # Conflict detected - generate diff preview
        diff_preview = self._generate_diff_preview(project_file)

        return ConflictResolutionState(
            has_conflict=True,
            file_mtime=file_mtime,
            ui_mtime=ui_start_mtime,
            diff_preview=diff_preview
        )

    def check_app_conflict(
        self,
        ui_start_mtime: float
    ) -> ConflictResolutionState:
        """
        Check if app-registry-data.nix was modified externally during edit

        Args:
            ui_start_mtime: Timestamp when UI started editing

        Returns:
            ConflictResolutionState with conflict status and diff preview
        """
        nix_file = Path("/etc/nixos/home-modules/desktop/app-registry-data.nix")

        if not nix_file.exists():
            return ConflictResolutionState(
                has_conflict=True,
                file_mtime=0.0,
                ui_mtime=ui_start_mtime,
                diff_preview="< file: app-registry-data.nix DELETED"
            )

        file_mtime = nix_file.stat().st_mtime
        has_conflict = file_mtime > ui_start_mtime

        if not has_conflict:
            return ConflictResolutionState(
                has_conflict=False,
                file_mtime=file_mtime,
                ui_mtime=ui_start_mtime,
                diff_preview=""
            )

        # Conflict detected - generate diff preview
        diff_preview = self._generate_diff_preview(nix_file)

        return ConflictResolutionState(
            has_conflict=True,
            file_mtime=file_mtime,
            ui_mtime=ui_start_mtime,
            diff_preview=diff_preview
        )

    def _generate_diff_preview(
        self,
        file_path: Path,
        max_lines: int = 20
    ) -> str:
        """
        Generate side-by-side diff preview for UI display

        Args:
            file_path: Path to file with conflicts
            max_lines: Maximum lines to show in preview

        Returns:
            Diff preview string
        """
        try:
            # Read current file content
            with open(file_path, 'r') as f:
                file_lines = f.readlines()

            # Read backup file if it exists
            backup_path = file_path.with_suffix(file_path.suffix + '.bak')
            if not backup_path.exists():
                return f"< file: Modified externally (no backup available)\n> ui: Cannot show diff without backup"

            with open(backup_path, 'r') as f:
                backup_lines = f.readlines()

            # Generate unified diff
            diff = difflib.unified_diff(
                backup_lines,
                file_lines,
                fromfile="ui (your changes)",
                tofile="file (external changes)",
                lineterm=""
            )

            # Format diff for display
            diff_lines = list(diff)

            if not diff_lines:
                return "No differences detected"

            # Skip unified diff header (first 2 lines)
            diff_lines = diff_lines[2:]

            # Limit to max_lines
            if len(diff_lines) > max_lines:
                diff_lines = diff_lines[:max_lines] + [f"... ({len(diff_lines) - max_lines} more lines)"]

            # Convert unified diff format to simple side-by-side
            preview_lines = []
            for line in diff_lines:
                line = line.rstrip('\n')
                if line.startswith('-'):
                    preview_lines.append(f"< ui: {line[1:]}")
                elif line.startswith('+'):
                    preview_lines.append(f"> file: {line[1:]}")
                elif line.startswith('@@'):
                    # Context line - show as separator
                    preview_lines.append(f"--- {line[2:]} ---")
                elif line.startswith(' '):
                    # Unchanged line - show both sides
                    preview_lines.append(f"  {line[1:]}")

            return "\n".join(preview_lines)

        except Exception as e:
            return f"Error generating diff: {str(e)}"

    def get_file_mtime(self, file_path: Path) -> float:
        """
        Get file modification timestamp

        Args:
            file_path: Path to file

        Returns:
            Modification timestamp (seconds since epoch)

        Raises:
            FileNotFoundError: If file doesn't exist
        """
        if not file_path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        return file_path.stat().st_mtime

    def create_backup(self, file_path: Path) -> Path:
        """
        Create backup file for conflict detection

        Args:
            file_path: Path to original file

        Returns:
            Path to backup file

        Raises:
            FileNotFoundError: If original file doesn't exist
        """
        if not file_path.exists():
            raise FileNotFoundError(f"Cannot backup non-existent file: {file_path}")

        backup_path = file_path.with_suffix(file_path.suffix + '.bak')

        import shutil
        shutil.copy2(file_path, backup_path)

        return backup_path

    def has_unsaved_changes(
        self,
        file_path: Path,
        ui_data: Dict[str, Any]
    ) -> bool:
        """
        Check if UI has unsaved changes compared to file

        Args:
            file_path: Path to file
            ui_data: Current UI data dict

        Returns:
            True if UI data differs from file content
        """
        if not file_path.exists():
            return True  # File deleted - UI has unsaved data

        try:
            import json

            with open(file_path, 'r') as f:
                file_data = json.load(f)

            # Compare dictionaries (ignoring timestamp fields)
            ignore_keys = {"_mtime", "_ui_start_time"}

            file_data_filtered = {k: v for k, v in file_data.items() if k not in ignore_keys}
            ui_data_filtered = {k: v for k, v in ui_data.items() if k not in ignore_keys}

            return file_data_filtered != ui_data_filtered

        except Exception:
            return True  # Assume changes if cannot compare
