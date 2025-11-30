"""
Project filtering and loading service for Feature 078.

Feature 101: Refactored to use repos.json as single source of truth.
All projects are worktrees (including main branch checkouts).

Provides functions to load projects from repos.json, compute metadata,
and convert to ProjectListItem format for UI rendering.
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional, Tuple, Dict, Any

try:
    from .models.project_filter import (
        ProjectListItem,
        GitStatus,
        MatchPosition,
        ScoredMatch,
        FilterState,
    )
except ImportError:
    # Support direct import for tests
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


def load_repos_json() -> Dict[str, Any]:
    """Load repositories from repos.json.

    Feature 101: Single source of truth for all projects.

    Returns:
        Dict with "repositories" list and metadata, or empty dict if not found
    """
    repos_file = Path.home() / ".config" / "i3" / "repos.json"

    if not repos_file.exists():
        logger.debug("Feature 101: repos.json not found at %s", repos_file)
        return {"repositories": [], "last_discovery": None}

    try:
        with open(repos_file) as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        logger.warning(f"Feature 101: Failed to load repos.json: {e}")
        return {"repositories": [], "last_discovery": None}


def worktree_to_list_item(
    wt: Dict[str, Any],
    repo_qualified_name: str,
    repo_account: str,
    repo_name: str,
) -> ProjectListItem:
    """Convert a worktree from repos.json to ProjectListItem.

    Feature 101: All projects are worktrees in the new architecture.

    Args:
        wt: Worktree dict from repos.json
        repo_qualified_name: Parent repo qualified name (account/repo)
        repo_account: Repository account/owner
        repo_name: Repository name

    Returns:
        ProjectListItem with worktree metadata
    """
    # Build qualified name: account/repo:branch
    qualified_name = f"{repo_qualified_name}:{wt['branch']}"

    # Check if worktree directory exists
    wt_path = wt.get("path", "")
    directory_exists = Path(wt_path).exists() if wt_path else False

    # Extract git status
    git_status = GitStatus(
        is_clean=wt.get("is_clean", True),
        ahead_count=wt.get("ahead", 0),
        behind_count=wt.get("behind", 0),
    )

    # Calculate relative time from discovered_at or use current time
    # repos.json doesn't have per-worktree timestamps, use repo discovery time
    relative_time = "recent"

    # Feature 079: branch name for number extraction
    full_branch_name = wt.get("branch", "")

    # Generate display name from branch
    display_name = wt.get("branch", "unknown")

    return ProjectListItem(
        name=qualified_name,
        display_name=display_name,
        icon="🌿",  # All worktrees get worktree icon
        is_worktree=True,  # Feature 101: ALL projects are worktrees
        parent_project_name=repo_qualified_name,
        directory_exists=directory_exists,
        relative_time=relative_time,
        git_status=git_status,
        full_branch_name=full_branch_name,
        match_score=0,
        match_positions=[],
        selected=False,
    )


def load_all_projects(config_dir: Path) -> List[ProjectListItem]:
    """Load all projects from repos.json.

    Feature 101: Reads from repos.json as single source of truth.
    All projects are worktrees (including main branch checkouts).
    Groups worktrees by their parent repository.

    Args:
        config_dir: Path to i3 config directory (ignored - uses repos.json)

    Returns:
        List of ProjectListItem grouped by repository, sorted by discovery time
    """
    repos_data = load_repos_json()
    repositories = repos_data.get("repositories", [])

    if not repositories:
        logger.debug("Feature 101: No repositories found in repos.json")
        return []

    # Convert each repository's worktrees to ProjectListItems
    # Group by repository: repo header followed by its worktrees
    grouped_items: List[ProjectListItem] = []

    for repo in repositories:
        repo_account = repo.get("account", "unknown")
        repo_name = repo.get("name", "unknown")
        repo_qualified_name = f"{repo_account}/{repo_name}"

        worktrees = repo.get("worktrees", [])
        if not worktrees:
            continue

        # Sort worktrees: main/default branch first, then others alphabetically
        default_branch = repo.get("default_branch", "main")

        def worktree_sort_key(wt: Dict[str, Any]) -> tuple:
            branch = wt.get("branch", "")
            # Main/default branch comes first (0), others second (1)
            is_default = 0 if branch == default_branch else 1
            return (is_default, branch.lower())

        sorted_worktrees = sorted(worktrees, key=worktree_sort_key)

        # Convert each worktree to ProjectListItem
        for wt in sorted_worktrees:
            item = worktree_to_list_item(wt, repo_qualified_name, repo_account, repo_name)
            grouped_items.append(item)

    logger.debug(f"Feature 101: Loaded {len(grouped_items)} worktrees from repos.json")
    return grouped_items


def fuzzy_match_score(query: str, text: str) -> Tuple[int, List[MatchPosition]]:
    """Calculate fuzzy match score and positions.

    Scoring rules (per research.md):
    - Exact match: 1000
    - Prefix match: 500 + (len(query) / len(text)) * 100
    - Substring match: 100 - position_penalty
    - Word boundary match: 300 + 50 per consecutive word
    - No match: 0

    Feature 079: T071-T073 - Space-to-hyphen normalization
    Spaces in query are treated as equivalent to hyphens for fuzzy matching.
    This allows ":preview pane" to match "079-preview-pane-user-experience".

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

    # Feature 079: T073 - Normalize spaces to hyphens in query for matching
    # This enables "preview pane" to match "preview-pane" in branch names
    query_normalized = query_lower.replace(" ", "-")

    # Exact match (with normalization)
    if text_lower == query_lower or text_lower == query_normalized:
        return (1000, [MatchPosition(start=0, end=len(text))])

    # Prefix match (with normalization)
    if text_lower.startswith(query_lower) or text_lower.startswith(query_normalized):
        score = 500 + int((len(query) / len(text)) * 100)
        return (score, [MatchPosition(start=0, end=len(query))])

    # Substring match (anywhere in text) - try both original and normalized
    # Feature 079: T071/T072 - Space-to-word-boundary normalization
    pos = text_lower.find(query_lower)
    if pos == -1:
        # Try normalized query (spaces as hyphens)
        pos = text_lower.find(query_normalized)
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
