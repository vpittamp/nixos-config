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
