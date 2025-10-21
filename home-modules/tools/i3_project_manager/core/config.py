"""Configuration management for i3 project management system.

This module provides utilities for managing application classifications
and other global configuration settings.
"""

import json
from pathlib import Path
from typing import Dict, List, Optional, Set

from ..models.pattern import PatternRule


class AppClassConfig:
    """Manager for application classification configuration.

    Handles loading/saving application class classifications from/to
    ~/.config/i3/app-classes.json. Classifications determine whether
    windows are scoped to projects or global across all projects.
    """

    DEFAULT_SCOPED_CLASSES = ["Ghostty", "Code", "neovide", "Alacritty"]
    DEFAULT_GLOBAL_CLASSES = ["firefox", "Google-chrome", "mpv", "vlc"]

    def __init__(self, config_file: Optional[Path] = None):
        """Initialize app classification config.

        Args:
            config_file: Path to app-classes.json (default: ~/.config/i3/app-classes.json)
        """
        if config_file is None:
            config_file = Path.home() / ".config/i3/app-classes.json"
        self.config_file = config_file
        self.scoped_classes: Set[str] = set()
        self.global_classes: Set[str] = set()
        self.class_patterns: List[PatternRule] = []

    def load(self) -> None:
        """Load application classifications from disk.

        If file doesn't exist, creates it with default classifications.
        """
        if not self.config_file.exists():
            # Create default config
            self.scoped_classes = set(self.DEFAULT_SCOPED_CLASSES)
            self.global_classes = set(self.DEFAULT_GLOBAL_CLASSES)
            self.class_patterns = []
            self.save()
            return

        try:
            with self.config_file.open("r") as f:
                data = json.load(f)

            self.scoped_classes = set(data.get("scoped_classes", []))
            self.global_classes = set(data.get("global_classes", []))

            # Load patterns as list of PatternRule objects
            # Handle both old dict format and new array format for backward compatibility
            patterns_data = data.get("class_patterns", [])

            if isinstance(patterns_data, dict):
                # Old format: {"pattern": "scope"} -> convert to new format
                self.class_patterns = [
                    PatternRule(
                        pattern=pattern,
                        scope=scope,
                        priority=0,
                        description="",
                    )
                    for pattern, scope in patterns_data.items()
                ]
            elif isinstance(patterns_data, list):
                # New format: [{"pattern": "...", "scope": "...", ...}]
                self.class_patterns = [
                    PatternRule(
                        pattern=p["pattern"],
                        scope=p["scope"],
                        priority=p.get("priority", 0),
                        description=p.get("description", ""),
                    )
                    for p in patterns_data
                ]
            else:
                self.class_patterns = []

        except (json.JSONDecodeError, IOError) as e:
            raise ValueError(f"Failed to load app classifications: {e}")

    def save(self) -> None:
        """Save application classifications to disk.

        Creates parent directory if it doesn't exist.
        Performs atomic write using temp file + rename.
        Saves patterns in new PatternRule list format.
        """
        import tempfile
        import os

        # Ensure parent directory exists
        self.config_file.parent.mkdir(parents=True, exist_ok=True)

        # Prepare data - convert PatternRule objects to dicts
        data = {
            "scoped_classes": sorted(list(self.scoped_classes)),
            "global_classes": sorted(list(self.global_classes)),
            "class_patterns": [
                {
                    "pattern": p.pattern,
                    "scope": p.scope,
                    "priority": p.priority,
                    "description": p.description,
                }
                for p in self.class_patterns
            ],
        }

        # Atomic write using temp file + rename
        fd, temp_path = tempfile.mkstemp(
            dir=self.config_file.parent,
            prefix=".app-classes-",
            suffix=".json",
        )

        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
                f.write("\n")  # Add trailing newline
                f.flush()
                os.fsync(f.fileno())

            # Atomic rename
            os.rename(temp_path, self.config_file)

        except Exception:
            # Clean up temp file on error
            if Path(temp_path).exists():
                os.unlink(temp_path)
            raise

    def add_scoped_class(self, class_name: str) -> None:
        """Add a window class to the scoped list.

        Args:
            class_name: Window class name (e.g., "Code", "Ghostty")

        Raises:
            ValueError: If class is already in global list
        """
        if class_name in self.global_classes:
            raise ValueError(
                f"Class '{class_name}' is already in global list. "
                "Remove it from global first."
            )

        self.scoped_classes.add(class_name)

    def add_global_class(self, class_name: str) -> None:
        """Add a window class to the global list.

        Args:
            class_name: Window class name (e.g., "firefox", "chrome")

        Raises:
            ValueError: If class is already in scoped list
        """
        if class_name in self.scoped_classes:
            raise ValueError(
                f"Class '{class_name}' is already in scoped list. "
                "Remove it from scoped first."
            )

        self.global_classes.add(class_name)

    def remove_class(self, class_name: str) -> bool:
        """Remove a window class from both scoped and global lists.

        Args:
            class_name: Window class name to remove

        Returns:
            True if class was removed, False if not found
        """
        removed = False

        if class_name in self.scoped_classes:
            self.scoped_classes.remove(class_name)
            removed = True

        if class_name in self.global_classes:
            self.global_classes.remove(class_name)
            removed = True

        return removed

    def is_scoped(self, class_name: str, project: Optional[str] = None) -> bool:
        """Check if a window class is scoped (project-specific).

        Precedence: explicit scoped_classes > explicit global_classes > patterns > default

        Args:
            class_name: Window class name
            project: Optional project name (for project-specific overrides)

        Returns:
            True if class is scoped, False if global
        """
        # Direct match in scoped list (highest priority)
        if class_name in self.scoped_classes:
            return True

        # Direct match in global list
        if class_name in self.global_classes:
            return False

        # Pattern matching (sorted by priority, first match wins)
        sorted_patterns = sorted(self.class_patterns, key=lambda p: p.priority, reverse=True)
        for pattern in sorted_patterns:
            if pattern.matches(class_name):
                return pattern.scope == "scoped"

        # Default: treat unknown classes as scoped for safety
        # (prevents global windows from appearing in all projects)
        return True

    def is_global(self, class_name: str, project: Optional[str] = None) -> bool:
        """Check if a window class is global (visible in all projects).

        Args:
            class_name: Window class name
            project: Optional project name (for project-specific overrides)

        Returns:
            True if class is global, False if scoped
        """
        return not self.is_scoped(class_name, project)

    def get_all_scoped(self) -> List[str]:
        """Get all scoped window classes.

        Returns:
            Sorted list of scoped class names
        """
        return sorted(list(self.scoped_classes))

    def get_all_global(self) -> List[str]:
        """Get all global window classes.

        Returns:
            Sorted list of global class names
        """
        return sorted(list(self.global_classes))

    def get_classification(self, class_name: str) -> str:
        """Get classification for a window class.

        Args:
            class_name: Window class name

        Returns:
            "scoped", "global", or "unknown"
        """
        if class_name in self.scoped_classes:
            return "scoped"
        elif class_name in self.global_classes:
            return "global"
        else:
            # Check pattern matches
            sorted_patterns = sorted(
                self.class_patterns, key=lambda p: p.priority, reverse=True
            )
            for pattern in sorted_patterns:
                if pattern.matches(class_name):
                    return pattern.scope
            return "unknown"

    def add_pattern(self, pattern_rule: PatternRule) -> None:
        """Add a new pattern rule for classification.

        Args:
            pattern_rule: PatternRule object to add

        Raises:
            ValueError: If pattern syntax is invalid (caught in PatternRule.__post_init__)
        """
        # PatternRule validation happens in __post_init__
        self.class_patterns.append(pattern_rule)

    def remove_pattern(self, pattern_str: str) -> bool:
        """Remove a pattern rule by exact pattern string match.

        Args:
            pattern_str: Exact pattern string to remove (e.g., "glob:pwa-*")

        Returns:
            True if pattern was removed, False if not found
        """
        original_len = len(self.class_patterns)
        self.class_patterns = [p for p in self.class_patterns if p.pattern != pattern_str]
        return len(self.class_patterns) < original_len

    def list_patterns(self) -> List[PatternRule]:
        """Get all configured pattern rules, sorted by priority (descending).

        Returns:
            List of PatternRule objects sorted by priority
        """
        return sorted(self.class_patterns, key=lambda p: p.priority, reverse=True)
