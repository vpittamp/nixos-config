"""
Configuration Source Attribution Tracker

Tracks which settings came from Nix, runtime files, or project overrides.
Enables users to understand configuration precedence and troubleshoot conflicts.
"""

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional


class SourceSystem(str, Enum):
    """Configuration source system."""
    NIX = "nix"
    RUNTIME = "runtime"
    PROJECT = "project"


class PrecedenceLevel(int, Enum):
    """Configuration precedence level (higher wins)."""
    NIX_BASE = 1
    RUNTIME = 2
    PROJECT = 3


@dataclass
class ConfigurationSource:
    """
    Attribution information for a configuration setting.

    Tracks where a setting came from and when it was last modified.
    """
    setting_path: str  # e.g., "keybindings.Mod+Return"
    source_system: SourceSystem
    precedence_level: PrecedenceLevel
    file_path: Path
    last_modified: datetime
    value: Any
    overridden_by: Optional['ConfigurationSource'] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "setting_path": self.setting_path,
            "source_system": self.source_system.value,
            "precedence_level": self.precedence_level.value,
            "file_path": str(self.file_path),
            "last_modified": self.last_modified.isoformat(),
            "value": str(self.value),
            "overridden_by": self.overridden_by.setting_path if self.overridden_by else None
        }


class SourceTracker:
    """
    Tracks configuration sources and precedence.

    Maintains a registry of where each setting came from and
    which settings override others based on precedence.
    """

    def __init__(self):
        """Initialize source tracker."""
        self.sources: Dict[str, List[ConfigurationSource]] = {}
        self.active_sources: Dict[str, ConfigurationSource] = {}

    def register_source(
        self,
        setting_path: str,
        source_system: SourceSystem,
        file_path: Path,
        value: Any
    ) -> ConfigurationSource:
        """
        Register a configuration source.

        Args:
            setting_path: Path to setting (e.g., "keybindings.Mod+Return")
            source_system: Source system (nix, runtime, project)
            file_path: Path to configuration file
            value: Setting value

        Returns:
            ConfigurationSource instance
        """
        # Determine precedence level from source system
        precedence_map = {
            SourceSystem.NIX: PrecedenceLevel.NIX_BASE,
            SourceSystem.RUNTIME: PrecedenceLevel.RUNTIME,
            SourceSystem.PROJECT: PrecedenceLevel.PROJECT
        }

        precedence = precedence_map[source_system]

        # Get last modified time from file
        last_modified = datetime.fromtimestamp(file_path.stat().st_mtime)

        source = ConfigurationSource(
            setting_path=setting_path,
            source_system=source_system,
            precedence_level=precedence,
            file_path=file_path,
            last_modified=last_modified,
            value=value
        )

        # Add to sources registry
        if setting_path not in self.sources:
            self.sources[setting_path] = []

        self.sources[setting_path].append(source)

        # Update active source based on precedence
        self._update_active_source(setting_path)

        return source

    def _update_active_source(self, setting_path: str):
        """
        Update active source for a setting based on precedence.

        Args:
            setting_path: Path to setting
        """
        sources = self.sources.get(setting_path, [])
        if not sources:
            return

        # Sort by precedence (highest first)
        sorted_sources = sorted(
            sources,
            key=lambda s: s.precedence_level.value,
            reverse=True
        )

        # Active source is highest precedence
        active = sorted_sources[0]
        self.active_sources[setting_path] = active

        # Mark lower precedence sources as overridden
        for source in sorted_sources[1:]:
            source.overridden_by = active

    def get_active_source(self, setting_path: str) -> Optional[ConfigurationSource]:
        """
        Get active source for a setting.

        Args:
            setting_path: Path to setting

        Returns:
            Active ConfigurationSource or None
        """
        return self.active_sources.get(setting_path)

    def get_all_sources(self, setting_path: str) -> List[ConfigurationSource]:
        """
        Get all sources for a setting (including overridden).

        Args:
            setting_path: Path to setting

        Returns:
            List of ConfigurationSource instances
        """
        return self.sources.get(setting_path, [])

    def get_overridden_settings(self) -> List[ConfigurationSource]:
        """
        Get all settings that are overridden by higher precedence sources.

        Returns:
            List of overridden ConfigurationSource instances
        """
        overridden = []

        for setting_path, sources in self.sources.items():
            for source in sources:
                if source.overridden_by:
                    overridden.append(source)

        return overridden

    def get_sources_by_system(self, source_system: SourceSystem) -> Dict[str, ConfigurationSource]:
        """
        Get all sources from a specific system.

        Args:
            source_system: Source system to filter by

        Returns:
            Dictionary mapping setting_path to ConfigurationSource
        """
        result = {}

        for setting_path, sources in self.sources.items():
            for source in sources:
                if source.source_system == source_system:
                    result[setting_path] = source

        return result

    def get_active_sources_by_file(self, file_path: Path) -> List[ConfigurationSource]:
        """
        Get all active sources from a specific file.

        Args:
            file_path: Configuration file path

        Returns:
            List of active ConfigurationSource instances from file
        """
        result = []

        for setting_path, source in self.active_sources.items():
            if source.file_path == file_path:
                result.append(source)

        return result

    def clear(self):
        """Clear all tracked sources."""
        self.sources.clear()
        self.active_sources.clear()

    def to_dict(self) -> Dict[str, Any]:
        """
        Convert tracker state to dictionary.

        Returns:
            Dictionary representation of tracker state
        """
        return {
            "total_settings": len(self.sources),
            "active_settings": len(self.active_sources),
            "overridden_settings": len(self.get_overridden_settings()),
            "sources_by_system": {
                "nix": len(self.get_sources_by_system(SourceSystem.NIX)),
                "runtime": len(self.get_sources_by_system(SourceSystem.RUNTIME)),
                "project": len(self.get_sources_by_system(SourceSystem.PROJECT))
            },
            "active_sources": {
                setting_path: source.to_dict()
                for setting_path, source in self.active_sources.items()
            }
        }

    def get_setting_history(self, setting_path: str) -> List[Dict[str, Any]]:
        """
        Get history of all sources for a setting with precedence info.

        Args:
            setting_path: Path to setting

        Returns:
            List of source dictionaries sorted by precedence (highest first)
        """
        sources = self.get_all_sources(setting_path)

        # Sort by precedence (highest first)
        sorted_sources = sorted(
            sources,
            key=lambda s: s.precedence_level.value,
            reverse=True
        )

        return [
            {
                **source.to_dict(),
                "is_active": source == self.get_active_source(setting_path),
                "is_overridden": source.overridden_by is not None
            }
            for source in sorted_sources
        ]
