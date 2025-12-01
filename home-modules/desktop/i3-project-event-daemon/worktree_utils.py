"""Worktree utilities for parsing qualified names and marks.

Feature 101: Centralized utilities for worktree/project name handling.
This eliminates duplicate parsing logic scattered throughout the codebase.
"""

import json
import logging
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple

from .constants import ConfigPaths

logger = logging.getLogger(__name__)


@dataclass
class ParsedQualifiedName:
    """Parsed components of a qualified worktree name.

    A qualified name has format: account/repo:branch
    Example: vpittamp/nixos-config:main
    """

    account: str
    repo: str
    branch: str

    @property
    def repo_qualified_name(self) -> str:
        """Get account/repo without branch."""
        return f"{self.account}/{self.repo}"

    @property
    def full_qualified_name(self) -> str:
        """Get full account/repo:branch name."""
        return f"{self.account}/{self.repo}:{self.branch}"


@dataclass
class ParsedMark:
    """Parsed components of a unified Sway window mark.

    Feature 103: Unified mark format
    Format: SCOPE:APP_NAME:PROJECT:WINDOW_ID

    Example marks:
    - scoped:terminal:vpittamp/nixos-config:main:12345
    - scoped:scratchpad-terminal:myproject:67890
    - global:firefox:nixos:99999
    - scoped:code:102-unified-event-tracing:54321
    """

    scope: str  # "scoped" or "global"
    app_name: str  # Application name from app-registry (e.g., "terminal", "code", "scratchpad-terminal")
    project_name: str  # Simple name or qualified name (may contain colons)
    window_id: str  # Window ID (required in unified format)


def parse_qualified_name(qualified_name: str) -> ParsedQualifiedName:
    """Parse a qualified worktree name into components.

    Args:
        qualified_name: String in format "account/repo:branch"

    Returns:
        ParsedQualifiedName with account, repo, and branch components

    Raises:
        ValueError: If format is invalid

    Example:
        >>> parsed = parse_qualified_name("vpittamp/nixos-config:main")
        >>> parsed.account
        'vpittamp'
        >>> parsed.repo
        'nixos-config'
        >>> parsed.branch
        'main'
    """
    if ":" not in qualified_name:
        raise ValueError(
            f"Invalid qualified name '{qualified_name}'. "
            f"Expected format: account/repo:branch (missing ':')"
        )

    # Split on last colon to get repo_name and branch
    repo_part, branch = qualified_name.rsplit(":", 1)

    if not branch:
        raise ValueError(
            f"Invalid qualified name '{qualified_name}'. "
            f"Branch cannot be empty."
        )

    if "/" not in repo_part:
        raise ValueError(
            f"Invalid qualified name '{qualified_name}'. "
            f"Expected format: account/repo:branch (missing '/')"
        )

    # Split on first slash to get account and repo
    account, repo = repo_part.split("/", 1)

    if not account or not repo:
        raise ValueError(
            f"Invalid qualified name '{qualified_name}'. "
            f"Account and repository cannot be empty."
        )

    return ParsedQualifiedName(account=account, repo=repo, branch=branch)


def is_qualified_name(name: str) -> bool:
    """Check if a name is a qualified worktree name.

    Args:
        name: Name to check

    Returns:
        True if name matches account/repo:branch format

    Example:
        >>> is_qualified_name("vpittamp/nixos-config:main")
        True
        >>> is_qualified_name("my-project")
        False
    """
    return "/" in name and ":" in name


def parse_mark(mark: str, window_id_hint: Optional[int] = None) -> Optional[ParsedMark]:
    """Parse a unified Sway window mark into components.

    Feature 103: Only handles unified format SCOPE:APP:PROJECT:WINDOW_ID
    Legacy 3-part marks are ignored (return None).

    Args:
        mark: Sway mark string
        window_id_hint: Optional window ID for debug logging

    Returns:
        ParsedMark with scope, app_name, project_name, and window_id, or None if invalid

    Example:
        >>> parse_mark("scoped:terminal:vpittamp/nixos-config:main:12345")
        ParsedMark(scope='scoped', app_name='terminal', project_name='vpittamp/nixos-config:main', window_id='12345')

        >>> parse_mark("scoped:code:myproject:67890")
        ParsedMark(scope='scoped', app_name='code', project_name='myproject', window_id='67890')

        >>> parse_mark("scoped:myproject:12345")  # Legacy format
        None  # Not supported
    """
    # Must start with valid scope
    if not mark.startswith("scoped:") and not mark.startswith("global:"):
        return None

    parts = mark.split(":")

    # Feature 103: Unified format requires at least 4 parts: SCOPE:APP:PROJECT:WINDOW_ID
    # Project names may contain colons (e.g., vpittamp/nixos-config:main)
    if len(parts) < 4:
        logger.debug(
            f"[Feature 103] Ignoring non-unified mark (window {window_id_hint}): "
            f"'{mark}' has {len(parts)} parts (need 4+)"
        )
        return None

    scope = parts[0]
    app_name = parts[1]
    window_id = parts[-1]
    # Project is everything between app_name and window_id
    project_name = ":".join(parts[2:-1])

    # Validate window_id is numeric
    if not window_id.isdigit():
        logger.warning(
            f"[Feature 103] Invalid window_id in mark (window {window_id_hint}): "
            f"'{mark}' - window_id '{window_id}' is not numeric"
        )
        return None

    logger.debug(
        f"[Feature 103] Parsed unified mark (window {window_id_hint}): "
        f"scope={scope}, app={app_name}, project={project_name}, window_id={window_id}"
    )

    return ParsedMark(scope=scope, app_name=app_name, project_name=project_name, window_id=window_id)


def extract_project_from_mark(mark: str, window_id_hint: Optional[int] = None) -> Optional[str]:
    """Extract project name from a Sway mark.

    Convenience function that returns just the project name.

    Args:
        mark: Sway mark string
        window_id_hint: Optional window ID for debug logging

    Returns:
        Project name (simple or qualified), or None if invalid mark
    """
    parsed = parse_mark(mark, window_id_hint)
    return parsed.project_name if parsed else None


def build_mark(scope: str, app_name: str, project_name: str, window_id: int) -> str:
    """Build a unified Sway mark string from components.

    Feature 103: Unified mark format SCOPE:APP:PROJECT:WINDOW_ID

    Args:
        scope: "scoped" or "global"
        app_name: Application name from app-registry (e.g., "terminal", "code")
        project_name: Project name (simple or qualified)
        window_id: Window ID

    Returns:
        Mark string in unified format SCOPE:APP:PROJECT:WINDOW_ID

    Example:
        >>> build_mark("scoped", "terminal", "vpittamp/nixos-config:main", 12345)
        'scoped:terminal:vpittamp/nixos-config:main:12345'

        >>> build_mark("global", "firefox", "nixos", 99999)
        'global:firefox:nixos:99999'
    """
    return f"{scope}:{app_name}:{project_name}:{window_id}"


def validate_worktree_path(path: Optional[str]) -> Tuple[bool, str]:
    """Validate a worktree directory path.

    Args:
        path: Path to validate (can be None or empty)

    Returns:
        Tuple of (is_valid, status) where status is one of:
        - "active": Path exists and is a directory
        - "missing": Path does not exist
        - "invalid": Path is None, empty, or not a directory
    """
    if not path:
        return False, "invalid"

    try:
        p = Path(path)
        if p.exists():
            if p.is_dir():
                return True, "active"
            else:
                return False, "invalid"  # Exists but not a directory
        else:
            return False, "missing"
    except (ValueError, OSError) as e:
        logger.warning(f"[Feature 101] Path validation error for '{path}': {e}")
        return False, "invalid"


def get_active_worktree() -> Optional[dict]:
    """Read the active worktree from active-worktree.json.

    Returns:
        Dict with worktree data, or None if no active worktree

    Example:
        >>> wt = get_active_worktree()
        >>> wt["qualified_name"]
        'vpittamp/nixos-config:main'
    """
    if not ConfigPaths.ACTIVE_WORKTREE_FILE.exists():
        return None

    try:
        with open(ConfigPaths.ACTIVE_WORKTREE_FILE) as f:
            data = json.load(f)

        if not data or "qualified_name" not in data:
            return None

        return data

    except (json.JSONDecodeError, IOError) as e:
        logger.warning(f"[Feature 101] Failed to read active-worktree.json: {e}")
        return None


def get_active_qualified_name() -> Optional[str]:
    """Get the qualified name of the active worktree.

    Returns:
        Qualified name string (account/repo:branch), or None if no active worktree
    """
    wt = get_active_worktree()
    return wt.get("qualified_name") if wt else None


def get_active_directory() -> Optional[Path]:
    """Get the directory of the active worktree.

    Returns:
        Path to worktree directory, or None if no active worktree
    """
    wt = get_active_worktree()
    if wt and wt.get("directory"):
        return Path(wt["directory"])
    return None
