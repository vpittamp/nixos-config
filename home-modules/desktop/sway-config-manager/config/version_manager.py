"""
Configuration version tracking manager.

Maintains persistent state of the active configuration version.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from ..models import ConfigurationVersion

logger = logging.getLogger(__name__)


class VersionManager:
    """Manages configuration version tracking and persistence."""

    def __init__(self, config_dir: Path):
        """
        Initialize version manager.

        Args:
            config_dir: Path to Sway configuration directory
        """
        self.config_dir = config_dir
        self.version_file = config_dir / ".config-version"

    def save_active_version(self, version: ConfigurationVersion) -> None:
        """
        Save the active configuration version to persistent storage.

        Args:
            version: ConfigurationVersion to save
        """
        try:
            version_data = {
                "commit_hash": version.commit_hash,
                "timestamp": version.timestamp.isoformat(),
                "message": version.message,
                "author": version.author,
                "is_active": True,
                "files_changed": version.files_changed
            }

            with open(self.version_file, "w") as f:
                json.dump(version_data, f, indent=2)

            logger.info(f"Saved active version: {version.commit_hash[:8]}")

        except Exception as e:
            logger.error(f"Failed to save active version: {e}")

    def load_active_version(self) -> Optional[ConfigurationVersion]:
        """
        Load the active configuration version from persistent storage.

        Returns:
            ConfigurationVersion if available, None otherwise
        """
        try:
            if not self.version_file.exists():
                logger.debug("No version file found")
                return None

            with open(self.version_file, "r") as f:
                data = json.load(f)

            version = ConfigurationVersion(
                commit_hash=data["commit_hash"],
                timestamp=datetime.fromisoformat(data["timestamp"]),
                message=data["message"],
                author=data.get("author", "unknown"),
                is_active=True,
                files_changed=data.get("files_changed", [])
            )

            logger.debug(f"Loaded active version: {version.commit_hash[:8]}")
            return version

        except Exception as e:
            logger.error(f"Failed to load active version: {e}")
            return None

    def update_active_version(
        self,
        commit_hash: str,
        message: Optional[str] = None,
        author: Optional[str] = None
    ) -> ConfigurationVersion:
        """
        Update the active configuration version.

        Args:
            commit_hash: Git commit SHA
            message: Commit message (defaults to "Configuration update")
            author: Commit author (defaults to "system")

        Returns:
            Updated ConfigurationVersion
        """
        version = ConfigurationVersion(
            commit_hash=commit_hash,
            timestamp=datetime.now(),
            message=message or "Configuration update",
            author=author or "system",
            is_active=True,
            files_changed=[]
        )

        self.save_active_version(version)
        return version

    def clear_active_version(self) -> None:
        """Clear the active configuration version (delete version file)."""
        try:
            if self.version_file.exists():
                self.version_file.unlink()
                logger.info("Cleared active version")
        except Exception as e:
            logger.error(f"Failed to clear active version: {e}")

    def get_version_info(self) -> dict:
        """
        Get version information as a dictionary.

        Returns:
            Dictionary with version details or empty dict if no version
        """
        version = self.load_active_version()

        if not version:
            return {
                "status": "no_version",
                "message": "No configuration version tracked"
            }

        return {
            "status": "active",
            "commit_hash": version.commit_hash,
            "commit_hash_short": version.commit_hash[:8],
            "timestamp": version.timestamp.isoformat(),
            "message": version.message,
            "author": version.author,
            "files_changed": version.files_changed
        }
