"""Shell completion helpers for i3pm CLI.

T094: Bash completion using argcomplete.

Provides custom completers for:
- Project names
- Window class names
- Pattern types (glob:, regex:, literal)
- Scope values (scoped, global)
"""

import asyncio
from pathlib import Path
from typing import List, Optional


def complete_project_names(prefix: str, **kwargs) -> List[str]:
    """Complete project names from ~/.config/i3/projects/

    Args:
        prefix: Current prefix being typed

    Returns:
        List of matching project names

    T094: Project name completion
    """
    try:
        projects_dir = Path.home() / ".config/i3/projects"

        if not projects_dir.exists():
            return []

        # Get all .json files in projects directory
        project_files = projects_dir.glob("*.json")
        project_names = [f.stem for f in project_files]

        # Filter by prefix
        if prefix:
            return [name for name in project_names if name.startswith(prefix)]

        return sorted(project_names)

    except Exception:
        return []


def complete_window_classes(prefix: str, **kwargs) -> List[str]:
    """Complete window class names from app-classes.json

    Args:
        prefix: Current prefix being typed

    Returns:
        List of matching window class names

    T094: Window class completion
    """
    try:
        from ..core.config import AppClassConfig

        # Load configuration
        config = AppClassConfig()
        config.load()

        # Get all known window classes
        all_classes = set()
        all_classes.update(config.scoped_classes)
        all_classes.update(config.global_classes)

        # Filter by prefix
        if prefix:
            return [cls for cls in sorted(all_classes) if cls.startswith(prefix)]

        return sorted(all_classes)

    except Exception:
        return []


def complete_pattern_prefix(prefix: str, **kwargs) -> List[str]:
    """Complete pattern prefixes (glob:, regex:)

    Args:
        prefix: Current prefix being typed

    Returns:
        List of pattern type suggestions

    T094: Pattern prefix completion
    """
    prefixes = ["glob:", "regex:", "literal:"]

    if prefix:
        # If prefix contains ':', complete the part after it
        if ':' in prefix:
            return []  # Don't complete after colon

        # Complete prefix types
        return [p for p in prefixes if p.startswith(prefix)]

    return prefixes


def complete_scope_values(prefix: str, **kwargs) -> List[str]:
    """Complete scope values (scoped, global)

    Args:
        prefix: Current prefix being typed

    Returns:
        List of scope values

    T094: Scope value completion
    """
    scopes = ["scoped", "global"]

    if prefix:
        return [s for s in scopes if s.startswith(prefix)]

    return scopes


def complete_desktop_files(prefix: str, **kwargs) -> List[str]:
    """Complete .desktop file paths

    Args:
        prefix: Current prefix being typed

    Returns:
        List of .desktop file paths

    T094: Desktop file completion
    """
    try:
        # Common desktop file locations
        desktop_dirs = [
            Path("/usr/share/applications"),
            Path("/usr/local/share/applications"),
            Path.home() / ".local/share/applications",
        ]

        desktop_files = []
        for d in desktop_dirs:
            if d.exists():
                desktop_files.extend(str(f) for f in d.glob("*.desktop"))

        # Filter by prefix
        if prefix:
            return [f for f in desktop_files if f.startswith(prefix)]

        return sorted(desktop_files)

    except Exception:
        return []


def complete_filter_status(prefix: str, **kwargs) -> List[str]:
    """Complete filter status values for wizard

    Args:
        prefix: Current prefix being typed

    Returns:
        List of filter status values

    T094: Filter status completion
    """
    statuses = ["all", "unclassified", "scoped", "global"]

    if prefix:
        return [s for s in statuses if s.startswith(prefix)]

    return statuses


def complete_sort_fields(prefix: str, **kwargs) -> List[str]:
    """Complete sort field values

    Args:
        prefix: Current prefix being typed

    Returns:
        List of sort field values

    T094: Sort field completion
    """
    fields = ["name", "modified", "directory", "class", "status", "confidence"]

    if prefix:
        return [f for f in fields if f.startswith(prefix)]

    return fields


def complete_event_types(prefix: str, **kwargs) -> List[str]:
    """Complete event type filters

    Args:
        prefix: Current prefix being typed

    Returns:
        List of event types

    T094: Event type completion
    """
    types = ["window", "workspace", "output", "tick", "error"]

    if prefix:
        return [t for t in types if t.startswith(prefix)]

    return types


# Export all completers for easy import
__all__ = [
    'complete_project_names',
    'complete_window_classes',
    'complete_pattern_prefix',
    'complete_scope_values',
    'complete_desktop_files',
    'complete_filter_status',
    'complete_sort_fields',
    'complete_event_types',
]
