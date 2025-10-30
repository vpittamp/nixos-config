"""
Git-based rollback manager for Sway configuration.

Provides version control and rollback capabilities for configuration files.
"""

import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from ..models import ConfigurationVersion


class RollbackManager:
    """Manages git-based version control and rollback for configuration."""

    def __init__(self, config_dir: Path):
        """
        Initialize rollback manager.

        Args:
            config_dir: Path to Sway configuration directory
        """
        self.config_dir = config_dir
        self._ensure_git_repo()

    def _ensure_git_repo(self):
        """Ensure configuration directory is a git repository."""
        git_dir = self.config_dir / ".git"
        if not git_dir.exists():
            subprocess.run(
                ["git", "init"],
                cwd=self.config_dir,
                check=True,
                capture_output=True
            )

    def list_versions(self, limit: int = 10) -> List[ConfigurationVersion]:
        """
        List recent configuration versions from git history.

        Args:
            limit: Maximum number of versions to return

        Returns:
            List of ConfigurationVersion objects sorted by timestamp (newest first)
        """
        result = subprocess.run(
            [
                "git", "log",
                f"-{limit}",
                "--pretty=format:%H|%at|%s|%an",
                "--name-only"
            ],
            cwd=self.config_dir,
            capture_output=True,
            text=True,
            check=True
        )

        versions = []
        current_commit = None
        current_files = []

        for line in result.stdout.strip().split("\n"):
            if not line:
                if current_commit:
                    versions.append(current_commit)
                    current_commit = None
                    current_files = []
                continue

            if "|" in line:
                # Commit info line
                parts = line.split("|")
                commit_hash, timestamp_str, message, author = parts
                current_commit = ConfigurationVersion(
                    commit_hash=commit_hash,
                    timestamp=datetime.fromtimestamp(int(timestamp_str)),
                    message=message,
                    files_changed=[],
                    author=author,
                    is_active=False
                )
            else:
                # File name line
                if current_commit:
                    current_files.append(line)
                    current_commit.files_changed = current_files

        # Add the last commit if exists
        if current_commit:
            versions.append(current_commit)

        # Mark the first version as active (HEAD)
        if versions:
            versions[0].is_active = True

        return versions

    def rollback_to_commit(self, commit_hash: str) -> bool:
        """
        Rollback configuration to a specific commit.

        Args:
            commit_hash: Git commit SHA to rollback to

        Returns:
            True if rollback successful, False otherwise
        """
        try:
            subprocess.run(
                ["git", "checkout", commit_hash, "."],
                cwd=self.config_dir,
                check=True,
                capture_output=True
            )
            return True
        except subprocess.CalledProcessError:
            return False

    def commit_config_changes(self, message: Optional[str] = None, files: Optional[List[str]] = None) -> str:
        """
        Commit configuration changes to git.

        Args:
            message: Commit message (auto-generated if None)
            files: List of files to commit (all changed files if None)

        Returns:
            Commit hash of the new commit
        """
        if files:
            for file in files:
                subprocess.run(
                    ["git", "add", file],
                    cwd=self.config_dir,
                    check=True,
                    capture_output=True
                )
        else:
            subprocess.run(
                ["git", "add", "-A"],
                cwd=self.config_dir,
                check=True,
                capture_output=True
            )

        # Bail out gracefully if there is nothing to commit (avoid git error code 1)
        diff_check = subprocess.run(
            ["git", "diff", "--cached", "--quiet"],
            cwd=self.config_dir
        )
        if diff_check.returncode == 0:
            # No staged changes, return current HEAD if it exists
            existing_head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=self.config_dir,
                capture_output=True,
                text=True
            )
            if existing_head.returncode == 0:
                return existing_head.stdout.strip()
            # Repository has no commits yet; nothing staged means no changes to persist
            raise RuntimeError("No configuration changes to commit")

        if message is None:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            message = f"Configuration update: {timestamp}"

        subprocess.run(
            ["git", "commit", "-m", message],
            cwd=self.config_dir,
            check=True,
            capture_output=True
        )

        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=self.config_dir,
            capture_output=True,
            text=True,
            check=True
        )

        return result.stdout.strip()

    def get_active_version(self) -> Optional[ConfigurationVersion]:
        """
        Get the currently active configuration version.

        Returns:
            ConfigurationVersion for HEAD or None if no commits
        """
        versions = self.list_versions(limit=1)
        return versions[0] if versions else None

    def create_backup(self, backup_name: Optional[str] = None) -> Path:
        """
        Create timestamped backup of configuration files.

        Feature 047 Phase 8: T058 - Create backup before reload

        Args:
            backup_name: Optional backup name (auto-generated if None)

        Returns:
            Path to the backup directory

        Raises:
            RuntimeError: If backup creation fails
        """
        import shutil

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        if backup_name:
            backup_dir_name = f"backup_{backup_name}_{timestamp}"
        else:
            backup_dir_name = f"backup_{timestamp}"

        # Create backups directory if it doesn't exist
        backups_parent = self.config_dir / ".backups"
        backups_parent.mkdir(exist_ok=True)

        backup_dir = backups_parent / backup_dir_name

        # Files to backup
        backup_files = [
            "keybindings.toml",
            "window-rules.json",
            "workspace-assignments.json",
            "projects/*.json",  # All project files
            ".config-version"   # Version tracking file
        ]

        # Create backup directory
        backup_dir.mkdir(parents=True, exist_ok=True)

        # Copy files
        for pattern in backup_files:
            if "*" in pattern:
                # Handle glob patterns
                parts = pattern.split("/")
                if len(parts) == 2:
                    subdir, file_pattern = parts
                    source_dir = self.config_dir / subdir
                    if source_dir.exists():
                        dest_dir = backup_dir / subdir
                        dest_dir.mkdir(parents=True, exist_ok=True)
                        for file_path in source_dir.glob(file_pattern):
                            if file_path.is_file():
                                shutil.copy2(file_path, dest_dir / file_path.name)
            else:
                # Handle single files
                source_path = self.config_dir / pattern
                if source_path.exists():
                    dest_path = backup_dir / pattern
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source_path, dest_path)

        # Create backup metadata file
        metadata = {
            "timestamp": timestamp,
            "backup_name": backup_name or "auto",
            "files_backed_up": len(list(backup_dir.rglob("*"))),
            "created_at": datetime.now().isoformat()
        }

        import json
        with open(backup_dir / ".backup-metadata.json", "w") as f:
            json.dump(metadata, f, indent=2)

        return backup_dir

    def list_backups(self, limit: Optional[int] = None) -> List[Path]:
        """
        List available configuration backups.

        Feature 047 Phase 8: T058 - List backups

        Args:
            limit: Maximum number of backups to return (None for all)

        Returns:
            List of backup directory paths sorted by creation time (newest first)
        """
        backups_dir = self.config_dir / ".backups"
        if not backups_dir.exists():
            return []

        backups = sorted(
            [d for d in backups_dir.iterdir() if d.is_dir()],
            key=lambda p: p.stat().st_mtime,
            reverse=True
        )

        if limit:
            backups = backups[:limit]

        return backups

    def restore_backup(self, backup_path: Path) -> bool:
        """
        Restore configuration from a backup.

        Feature 047 Phase 8: T058 - Restore from backup

        Args:
            backup_path: Path to backup directory

        Returns:
            True if restore successful, False otherwise
        """
        import shutil

        if not backup_path.exists() or not backup_path.is_dir():
            return False

        try:
            # Restore files from backup
            for item in backup_path.rglob("*"):
                if item.is_file() and item.name != ".backup-metadata.json":
                    # Calculate relative path
                    rel_path = item.relative_to(backup_path)
                    dest_path = self.config_dir / rel_path

                    # Create parent directory if needed
                    dest_path.parent.mkdir(parents=True, exist_ok=True)

                    # Copy file
                    shutil.copy2(item, dest_path)

            return True
        except Exception:
            return False
