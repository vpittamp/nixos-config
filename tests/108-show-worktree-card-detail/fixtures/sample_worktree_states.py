"""
Feature 108: Sample worktree states for testing enhanced git status indicators.

This module provides mock git metadata in various states for testing:
- Dirty/clean states with staged/modified/untracked breakdowns
- Ahead/behind sync states
- Merged/unmerged branches
- Stale/active worktrees
- Conflict states
"""

import time
from typing import Dict, Any

# Constants
STALE_THRESHOLD_DAYS = 30
SECONDS_PER_DAY = 86400


def _timestamp_days_ago(days: int) -> int:
    """Generate Unix timestamp N days ago."""
    return int(time.time() - (days * SECONDS_PER_DAY))


# --- Clean worktree states ---

CLEAN_WORKTREE: Dict[str, Any] = {
    "current_branch": "099-feature",
    "commit_hash": "abc1234",
    "is_clean": True,
    "has_untracked": False,
    "ahead_count": 0,
    "behind_count": 0,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(1),  # 1 day ago
    "last_commit_message": "Clean worktree with recent commit",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": False,
}


# --- Dirty worktree states ---

DIRTY_WORKTREE_MODIFIED: Dict[str, Any] = {
    "current_branch": "100-wip-feature",
    "commit_hash": "def5678",
    "is_clean": False,
    "has_untracked": False,
    "ahead_count": 2,
    "behind_count": 0,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(0),  # Today
    "last_commit_message": "Work in progress",
    "staged_count": 1,
    "modified_count": 3,
    "untracked_count": 0,
    "has_conflicts": False,
}

DIRTY_WORKTREE_UNTRACKED: Dict[str, Any] = {
    "current_branch": "101-new-files",
    "commit_hash": "111aaaa",
    "is_clean": False,
    "has_untracked": True,
    "ahead_count": 0,
    "behind_count": 1,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(2),
    "last_commit_message": "Add new feature",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 5,
    "has_conflicts": False,
}

DIRTY_WORKTREE_MIXED: Dict[str, Any] = {
    "current_branch": "102-mixed-changes",
    "commit_hash": "222bbbb",
    "is_clean": False,
    "has_untracked": True,
    "ahead_count": 5,
    "behind_count": 2,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(0),
    "last_commit_message": "Fix authentication bug with multiple changes",
    "staged_count": 2,
    "modified_count": 3,
    "untracked_count": 1,
    "has_conflicts": False,
}


# --- Merged worktree states ---

MERGED_WORKTREE: Dict[str, Any] = {
    "current_branch": "097-completed-feature",
    "commit_hash": "333cccc",
    "is_clean": True,
    "has_untracked": False,
    "ahead_count": 0,
    "behind_count": 0,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": True,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(7),
    "last_commit_message": "Merge PR #97: Completed feature",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": False,
}


# --- Stale worktree states ---

STALE_WORKTREE: Dict[str, Any] = {
    "current_branch": "050-old-experiment",
    "commit_hash": "444dddd",
    "is_clean": True,
    "has_untracked": False,
    "ahead_count": 10,
    "behind_count": 50,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": True,
    "last_commit_timestamp": _timestamp_days_ago(45),  # 45 days ago
    "last_commit_message": "Last commit before abandonment",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": False,
}

STALE_AND_MERGED_WORKTREE: Dict[str, Any] = {
    "current_branch": "030-ancient-feature",
    "commit_hash": "555eeee",
    "is_clean": True,
    "has_untracked": False,
    "ahead_count": 0,
    "behind_count": 0,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": True,
    "is_stale": True,
    "last_commit_timestamp": _timestamp_days_ago(90),  # 90 days ago
    "last_commit_message": "Ancient feature merged long ago",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": False,
}


# --- Conflict worktree states ---

CONFLICT_WORKTREE: Dict[str, Any] = {
    "current_branch": "103-merge-conflict",
    "commit_hash": "666ffff",
    "is_clean": False,
    "has_untracked": False,
    "ahead_count": 3,
    "behind_count": 5,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(0),
    "last_commit_message": "Merge conflict in progress",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": True,
}


# --- Edge case worktree states ---

MAIN_BRANCH_WORKTREE: Dict[str, Any] = {
    "current_branch": "main",
    "commit_hash": "777gggg",
    "is_clean": True,
    "has_untracked": False,
    "ahead_count": 0,
    "behind_count": 0,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,  # Main should not show "merged into main"
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(0),
    "last_commit_message": "Latest on main",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": False,
}

DETACHED_HEAD_WORKTREE: Dict[str, Any] = {
    "current_branch": "HEAD",  # Detached state
    "commit_hash": "888hhhh",
    "is_clean": True,
    "has_untracked": False,
    "ahead_count": 0,
    "behind_count": 0,
    "remote_url": "git@github.com:vpittamp/nixos-config.git",
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(1),
    "last_commit_message": "Detached at specific commit",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": False,
}

NO_REMOTE_WORKTREE: Dict[str, Any] = {
    "current_branch": "local-only",
    "commit_hash": "999iiii",
    "is_clean": True,
    "has_untracked": False,
    "ahead_count": 0,  # No remote to compare
    "behind_count": 0,
    "remote_url": None,  # No remote configured
    # Feature 108 enhancements
    "is_merged": False,
    "is_stale": False,
    "last_commit_timestamp": _timestamp_days_ago(5),
    "last_commit_message": "Local development only",
    "staged_count": 0,
    "modified_count": 0,
    "untracked_count": 0,
    "has_conflicts": False,
}


# --- Git status porcelain output samples ---

GIT_STATUS_PORCELAIN_CLEAN = ""

GIT_STATUS_PORCELAIN_DIRTY = """M  home-modules/desktop/eww-monitoring-panel.nix
 M home-modules/tools/i3_project_manager/services/git_utils.py
?? tests/108-show-worktree-card-detail/
A  specs/108-show-worktree-card-detail/spec.md"""

GIT_STATUS_PORCELAIN_CONFLICTS = """UU home-modules/desktop/eww-monitoring-panel.nix
AA specs/108-show-worktree-card-detail/data-model.md
DD removed-file.py"""

GIT_STATUS_PORCELAIN_STAGED_ONLY = """M  file1.py
A  file2.py
D  file3.py"""

GIT_STATUS_PORCELAIN_MODIFIED_ONLY = """ M file1.py
 M file2.py
 D file3.py"""

GIT_STATUS_PORCELAIN_UNTRACKED_ONLY = """?? new-file1.py
?? new-file2.py
?? new-directory/"""


# --- Helper function for creating worktree data in different states ---

def create_worktree_data(
    branch: str,
    is_dirty: bool = False,
    is_merged: bool = False,
    is_stale: bool = False,
    has_conflicts: bool = False,
    ahead: int = 0,
    behind: int = 0,
    staged: int = 0,
    modified: int = 0,
    untracked: int = 0,
    days_since_commit: int = 0,
) -> Dict[str, Any]:
    """
    Factory function to create worktree data with specific states.

    Args:
        branch: Branch name
        is_dirty: Whether worktree has uncommitted changes
        is_merged: Whether branch is merged into main
        is_stale: Whether branch has no commits in 30+ days
        has_conflicts: Whether worktree has merge conflicts
        ahead: Commits ahead of upstream
        behind: Commits behind upstream
        staged: Count of staged files
        modified: Count of modified files
        untracked: Count of untracked files
        days_since_commit: Days since last commit

    Returns:
        Dictionary with all worktree metadata fields
    """
    return {
        "current_branch": branch,
        "commit_hash": f"{branch[:7]}123",
        "is_clean": not is_dirty,
        "has_untracked": untracked > 0,
        "ahead_count": ahead,
        "behind_count": behind,
        "remote_url": "git@github.com:vpittamp/nixos-config.git",
        "is_merged": is_merged,
        "is_stale": is_stale or days_since_commit >= STALE_THRESHOLD_DAYS,
        "last_commit_timestamp": _timestamp_days_ago(days_since_commit),
        "last_commit_message": f"Test commit for {branch}",
        "staged_count": staged,
        "modified_count": modified,
        "untracked_count": untracked,
        "has_conflicts": has_conflicts,
    }
