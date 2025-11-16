"""
Project filtering and loading service for Feature 078.

Provides functions to load projects from JSON files, compute metadata,
and convert to ProjectListItem format for UI rendering.
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional, Tuple

from models import Project
from models.project_filter import (
    ProjectListItem,
    GitStatus,
    MatchPosition,
    ScoredMatch,
    FilterState,
)

logger = logging.getLogger(__name__)


def format_relative_time(dt: datetime) -> str:
    """Format a datetime as relative time string.

    Args:
        dt: Datetime to format

    Returns:
        Human-readable relative time (e.g., "2h ago", "3d ago", "1mo ago")
    """
    now = datetime.now(timezone.utc)

    # Ensure dt is timezone-aware
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)

    delta = now - dt
    total_seconds = delta.total_seconds()

    if total_seconds < 0:
        return "just now"

    # Calculate time units
    minutes = int(total_seconds / 60)
    hours = int(total_seconds / 3600)
    days = int(total_seconds / 86400)
    months = int(days / 30)

    if minutes < 1:
        return "just now"
    elif minutes < 60:
        return f"{minutes}m ago"
    elif hours < 24:
        return f"{hours}h ago"
    elif days < 30:
        return f"{days}d ago"
    else:
        return f"{months}mo ago"


def load_project_file(project_path: Path) -> Optional[dict]:
    """Load a single project JSON file.

    Args:
        project_path: Path to project JSON file

    Returns:
        Project data dict or None if loading fails
    """
    try:
        with open(project_path) as f:
            return json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load project {project_path}: {e}")
        return None


def resolve_parent_project_name(repository_path: str, all_projects: List[dict]) -> Optional[str]:
    """Resolve parent project name from repository path.

    Args:
        repository_path: Absolute path to parent repository (e.g., "/etc/nixos")
        all_projects: List of all project dicts

    Returns:
        Name of parent project or None if not found
    """
    for project in all_projects:
        if project.get("directory") == repository_path:
            return project.get("name")
    return None


def project_to_list_item(
    project_data: dict,
    all_projects: List[dict],
) -> ProjectListItem:
    """Convert raw project dict to ProjectListItem with computed fields.

    Args:
        project_data: Raw project JSON data
        all_projects: All loaded project dicts (for parent resolution)

    Returns:
        ProjectListItem with computed metadata
    """
    # Check if directory exists
    directory = project_data.get("directory", "")
    directory_exists = Path(directory).exists() if directory else False

    # Determine if worktree and extract git status
    worktree_data = project_data.get("worktree")
    is_worktree = worktree_data is not None
    git_status = None
    parent_project_name = None
    last_modified_str = None

    if is_worktree and worktree_data:
        # Extract git status
        git_status = GitStatus(
            is_clean=worktree_data.get("is_clean", True),
            ahead_count=worktree_data.get("ahead_count", 0),
            behind_count=worktree_data.get("behind_count", 0),
        )
        # Resolve parent project
        repository_path = worktree_data.get("repository_path", "")
        if repository_path:
            parent_project_name = resolve_parent_project_name(repository_path, all_projects)
        # Get last modified from worktree
        last_modified_str = worktree_data.get("last_modified")

    # Calculate relative time
    try:
        if last_modified_str:
            # Parse ISO8601 with timezone
            if "T" in last_modified_str:
                if "+" in last_modified_str or "-" in last_modified_str[10:]:
                    # Has timezone offset (e.g., "2025-11-16T11:45:03-05:00")
                    dt = datetime.fromisoformat(last_modified_str)
                else:
                    # UTC format (e.g., "2025-11-16T11:45:03Z")
                    dt = datetime.fromisoformat(last_modified_str.replace("Z", "+00:00"))
            else:
                dt = datetime.fromisoformat(last_modified_str)
        else:
            # Fall back to updated_at
            updated_at = project_data.get("updated_at", "")
            if updated_at:
                dt = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
            else:
                dt = datetime.now(timezone.utc)
        relative_time = format_relative_time(dt)
    except Exception as e:
        logger.warning(f"Failed to parse date for {project_data.get('name')}: {e}")
        relative_time = "unknown"

    return ProjectListItem(
        name=project_data.get("name", "unknown"),
        display_name=project_data.get("display_name", project_data.get("name", "Unknown")),
        icon=project_data.get("icon", "📁"),
        is_worktree=is_worktree,
        parent_project_name=parent_project_name,
        directory_exists=directory_exists,
        relative_time=relative_time,
        git_status=git_status,
        match_score=0,
        match_positions=[],
        selected=False,
    )


def load_all_projects(config_dir: Path) -> List[ProjectListItem]:
    """Load all projects from config directory.

    Args:
        config_dir: Path to i3 config directory (typically ~/.config/i3/)

    Returns:
        List of ProjectListItem sorted by last activity (most recent first)
    """
    projects_dir = config_dir / "projects"

    if not projects_dir.exists():
        logger.warning(f"Projects directory does not exist: {projects_dir}")
        return []

    # First pass: load all raw project data
    all_project_data = []
    for project_file in projects_dir.glob("*.json"):
        data = load_project_file(project_file)
        if data:
            all_project_data.append(data)

    # Second pass: convert to ProjectListItem with parent resolution
    project_items = []
    for data in all_project_data:
        item = project_to_list_item(data, all_project_data)
        project_items.append(item)

    # Sort by recency (most recent first)
    # Use updated_at or worktree.last_modified
    def get_sort_key(item: ProjectListItem) -> datetime:
        # Find original data
        for data in all_project_data:
            if data.get("name") == item.name:
                worktree = data.get("worktree")
                if worktree and "last_modified" in worktree:
                    try:
                        lm = worktree["last_modified"]
                        return datetime.fromisoformat(lm.replace("Z", "+00:00"))
                    except Exception:
                        pass
                try:
                    ua = data.get("updated_at", "1970-01-01T00:00:00Z")
                    return datetime.fromisoformat(ua.replace("Z", "+00:00"))
                except Exception:
                    pass
        return datetime.min.replace(tzinfo=timezone.utc)

    project_items.sort(key=get_sort_key, reverse=True)

    return project_items


def fuzzy_match_score(query: str, text: str) -> Tuple[int, List[MatchPosition]]:
    """Calculate fuzzy match score and positions.

    Scoring rules (per research.md):
    - Exact match: 1000
    - Prefix match: 500 + (len(query) / len(text)) * 100
    - Substring match: 100 - position_penalty
    - Word boundary match: 300 + 50 per consecutive word
    - No match: 0

    Args:
        query: Search query (lowercase)
        text: Text to match against

    Returns:
        Tuple of (score, match_positions)
    """
    if not query:
        return (0, [])

    text_lower = text.lower()
    query_lower = query.lower()

    # Exact match
    if text_lower == query_lower:
        return (1000, [MatchPosition(start=0, end=len(text))])

    # Prefix match
    if text_lower.startswith(query_lower):
        score = 500 + int((len(query) / len(text)) * 100)
        return (score, [MatchPosition(start=0, end=len(query))])

    # Substring match (anywhere in text)
    pos = text_lower.find(query_lower)
    if pos != -1:
        # Penalize based on position (further = lower score)
        position_penalty = min(pos * 10, 50)
        score = 100 - position_penalty
        return (score, [MatchPosition(start=pos, end=pos + len(query))])

    # Character-by-character fuzzy matching
    # Try to find all query characters in order
    positions = []
    text_idx = 0
    for char in query_lower:
        found = False
        while text_idx < len(text_lower):
            if text_lower[text_idx] == char:
                positions.append(MatchPosition(start=text_idx, end=text_idx + 1))
                text_idx += 1
                found = True
                break
            text_idx += 1
        if not found:
            # Character not found - no match
            return (0, [])

    # Score based on how spread out the matches are
    # Consecutive matches get bonus
    score = 50
    for i in range(1, len(positions)):
        if positions[i].start == positions[i - 1].end:
            score += 20  # Consecutive bonus
        else:
            score -= (positions[i].start - positions[i - 1].end)  # Gap penalty

    # Merge consecutive positions
    merged_positions = []
    if positions:
        current = positions[0]
        for pos in positions[1:]:
            if pos.start == current.end:
                current = MatchPosition(start=current.start, end=pos.end)
            else:
                merged_positions.append(current)
                current = pos
        merged_positions.append(current)

    return (max(score, 10), merged_positions)


def filter_projects(
    projects: List[ProjectListItem],
    query: str,
) -> List[ProjectListItem]:
    """Filter and score projects based on query.

    Args:
        projects: List of all projects
        query: Search query (can be empty)

    Returns:
        Filtered and sorted list of projects (best matches first)
    """
    if not query:
        # No query - return all projects in original order (by recency)
        return projects

    scored_matches = []
    for project in projects:
        # Match against name (primary) and display_name (secondary)
        name_score, name_positions = fuzzy_match_score(query, project.name)
        display_score, display_positions = fuzzy_match_score(query, project.display_name)

        # Use the better match
        if name_score >= display_score and name_score > 0:
            score = name_score
            positions = name_positions
        elif display_score > 0:
            score = display_score
            positions = display_positions
        else:
            # No match
            continue

        # Create scored copy
        scored_project = project.model_copy()
        scored_project.match_score = score
        scored_project.match_positions = positions
        scored_matches.append(scored_project)

    # Sort by score (highest first)
    scored_matches.sort(key=lambda p: p.match_score, reverse=True)

    return scored_matches
