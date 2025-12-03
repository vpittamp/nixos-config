"""
Git Utilities for Features 097/100: Git-Centric Project and Worktree Management

This module provides core git discovery utilities that ALL user stories depend on:
- get_bare_repository_path(): Canonical identifier for worktrees
- determine_source_type(): Classify project as repository/worktree/standalone
- find_repository_for_bare_repo(): Find parent repository project
- detect_orphaned_worktrees(): Find worktrees with missing parents
- generate_unique_name(): Conflict resolution for project names

Feature 100 additions:
- parse_github_url(): Extract account/repo from SSH or HTTPS URL
- get_default_branch(): Detect default branch (main/master)
- list_worktrees(): Enumerate worktrees using --porcelain output
"""

import subprocess
import re
import time
from pathlib import Path
from typing import Optional, List, Set, Tuple

from ..models.project_config import ProjectConfig, SourceType, ProjectStatus


# Feature 108: Staleness threshold for worktree detection
STALE_THRESHOLD_DAYS = 30
SECONDS_PER_DAY = 86400


# Feature 100: GitHub URL parsing patterns
SSH_PATTERN = re.compile(r'^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$')


def format_relative_time(timestamp: int) -> str:
    """
    Feature 108 T009: Format Unix timestamp as human-readable relative time.

    Returns strings like "2h ago", "3 days ago", "2 weeks ago", "1 month ago".

    Args:
        timestamp: Unix epoch timestamp

    Returns:
        Human-readable relative time string
    """
    now = int(time.time())
    diff_seconds = now - timestamp

    if diff_seconds < 0:
        return "in the future"

    minutes = diff_seconds // 60
    hours = diff_seconds // 3600
    days = diff_seconds // SECONDS_PER_DAY
    weeks = days // 7
    months = days // 30

    if minutes < 1:
        return "just now"
    elif minutes < 60:
        return f"{minutes}m ago"
    elif hours < 24:
        return f"{hours}h ago"
    elif days < 7:
        return f"{days} day{'s' if days != 1 else ''} ago"
    elif weeks < 4:
        return f"{weeks} week{'s' if weeks != 1 else ''} ago"
    else:
        return f"{months} month{'s' if months != 1 else ''} ago"


HTTPS_PATTERN = re.compile(r'^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$')


def parse_github_url(url: str) -> Tuple[str, str]:
    """
    Feature 100 T008: Extract (account, repo) from GitHub URL.

    Supports both SSH and HTTPS formats:
    - git@github.com:vpittamp/nixos.git
    - https://github.com/PittampalliOrg/api.git

    Args:
        url: GitHub repository URL

    Returns:
        Tuple of (account, repo_name)

    Raises:
        ValueError: If URL doesn't match expected patterns
    """
    for pattern in [SSH_PATTERN, HTTPS_PATTERN]:
        match = pattern.match(url)
        if match:
            return match.group(1), match.group(2)
    raise ValueError(f"Invalid GitHub URL: {url}")


def get_default_branch(bare_path: str) -> str:
    """
    Feature 100 T009: Get default branch name from bare repo.

    Queries refs/remotes/origin/HEAD to determine the default branch.
    Falls back to trying 'main', then 'master'.

    Args:
        bare_path: Path to .bare directory

    Returns:
        Branch name (e.g., "main" or "master")

    Raises:
        ValueError: If default branch cannot be determined
    """
    try:
        result = subprocess.run(
            ["git", "-C", bare_path, "symbolic-ref", "refs/remotes/origin/HEAD"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # "refs/remotes/origin/main" → "main"
            return result.stdout.strip().split('/')[-1]
    except (subprocess.TimeoutExpired, OSError):
        pass

    # Fallback: try main, then master
    for branch in ['main', 'master']:
        try:
            result = subprocess.run(
                ["git", "-C", bare_path, "rev-parse", f"refs/heads/{branch}"],
                capture_output=True,
                timeout=5
            )
            if result.returncode == 0:
                return branch
        except (subprocess.TimeoutExpired, OSError):
            pass

    raise ValueError("Could not determine default branch")


def list_worktrees(repo_path: str) -> List[dict]:
    """
    Feature 100 T037: List all worktrees for a repository.

    Uses `git worktree list --porcelain` for machine-readable output.
    Skips the bare repository entry.

    Args:
        repo_path: Path to repository (can be any worktree or repo directory)

    Returns:
        List of dicts with 'path', 'branch', 'commit' keys
    """
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10
        )
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, OSError):
        return []

    worktrees = []
    current: dict = {}

    for line in result.stdout.split('\n'):
        if line.startswith('worktree '):
            if current and not current.get('bare'):
                worktrees.append(current)
            current = {'path': line[9:]}
        elif line == 'bare':
            current['bare'] = True
        elif line.startswith('branch '):
            current['branch'] = line[7:].replace('refs/heads/', '')
        elif line.startswith('HEAD '):
            current['commit'] = line[5:][:7]  # Short hash

    # Don't forget the last entry
    if current and not current.get('bare'):
        worktrees.append(current)

    return worktrees


def prune_worktrees(repo_path: str) -> bool:
    """
    Feature 100 T043: Run git worktree prune to clean stale references.

    Args:
        repo_path: Path to repository

    Returns:
        True if successful, False otherwise
    """
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "worktree", "prune"],
            capture_output=True,
            timeout=10
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def get_bare_repository_path(directory: str) -> Optional[str]:
    """
    T006: Get the bare repository path (GIT_COMMON_DIR) for a directory.

    Git worktrees share a common directory (the bare repo or main repo's .git).
    This function returns the absolute path to that common directory, which is
    the canonical identifier for all worktrees belonging to the same repository.

    Args:
        directory: Path to check (any worktree or repo directory)

    Returns:
        Absolute path to the bare repository, or None if not a git repo
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            return None

        common_dir = result.stdout.strip()

        # The result might be relative, resolve to absolute
        if not common_dir.startswith("/"):
            # Get repo root to resolve relative path
            root_result = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=5
            )
            if root_result.returncode == 0:
                repo_root = root_result.stdout.strip()
                common_dir = str(Path(repo_root) / common_dir)

        # Normalize and resolve to absolute path
        common_dir = str(Path(common_dir).resolve())

        # For regular repos, --git-common-dir returns /path/to/repo/.git
        # We keep the .git suffix as the canonical identifier
        return common_dir
    except (subprocess.TimeoutExpired, OSError):
        return None


def determine_source_type(
    directory: str,
    existing_projects: List[ProjectConfig]
) -> SourceType:
    """
    T007: Determine project type based on git structure and existing projects.

    Decision tree:
    1. Not a git repo? → standalone
    2. Has a Repository Project with same bare_repo_path? → worktree
    3. First project for this bare_repo_path? → repository

    Args:
        directory: Path to the project directory
        existing_projects: List of currently registered projects

    Returns:
        SourceType enum value: repository, worktree, or standalone
    """
    bare_repo = get_bare_repository_path(directory)

    if bare_repo is None:
        return SourceType.STANDALONE

    # Check if any existing project with source_type=repository has the same bare_repo_path
    existing_repo = find_repository_for_bare_repo(bare_repo, existing_projects)

    if existing_repo is not None:
        return SourceType.WORKTREE
    else:
        return SourceType.REPOSITORY


def find_repository_for_bare_repo(
    bare_repo_path: str,
    projects: List[ProjectConfig]
) -> Optional[ProjectConfig]:
    """
    T008: Find the Repository Project for a given bare_repo_path.

    This is used to:
    1. Determine if a new project should be worktree vs repository
    2. Link worktrees to their parent repository project
    3. Detect orphaned worktrees

    Args:
        bare_repo_path: The canonical identifier (GIT_COMMON_DIR)
        projects: List of projects to search

    Returns:
        The Repository Project with matching bare_repo_path, or None
    """
    for project in projects:
        if (
            project.source_type == SourceType.REPOSITORY and
            project.bare_repo_path == bare_repo_path
        ):
            return project
    return None


def detect_orphaned_worktrees(projects: List[ProjectConfig]) -> List[ProjectConfig]:
    """
    T009: Find worktrees whose parent Repository Project is missing.

    A worktree is orphaned when:
    1. source_type == "worktree" AND
    2. No project with source_type == "repository" has matching bare_repo_path

    Args:
        projects: List of all registered projects

    Returns:
        List of orphaned worktree projects (mutated with status=orphaned)
    """
    # Collect all bare_repo_paths from repository projects
    repo_bare_paths: Set[str] = set()
    for project in projects:
        if project.source_type == SourceType.REPOSITORY and project.bare_repo_path:
            repo_bare_paths.add(project.bare_repo_path)

    # Find worktrees without a matching repository
    orphans: List[ProjectConfig] = []
    for project in projects:
        if project.source_type == SourceType.WORKTREE:
            if not project.bare_repo_path or project.bare_repo_path not in repo_bare_paths:
                project.status = ProjectStatus.ORPHANED
                orphans.append(project)

    return orphans


def generate_unique_name(base_name: str, existing_names: Set[str]) -> str:
    """
    T012: Generate a unique project name by appending numeric suffix if needed.

    Algorithm: my-app → my-app-2 → my-app-3 → ...

    Args:
        base_name: Desired project name
        existing_names: Set of already-used project names

    Returns:
        Unique name (either base_name or base_name-N)
    """
    if base_name not in existing_names:
        return base_name

    counter = 2
    while f"{base_name}-{counter}" in existing_names:
        counter += 1

    return f"{base_name}-{counter}"


def is_git_repository(directory: str) -> bool:
    """
    Check if a directory is a git repository (has .git file or directory).

    Uses file system check instead of git subprocess for speed.

    Args:
        directory: Path to check

    Returns:
        True if directory contains .git (file or directory)
    """
    git_path = Path(directory) / ".git"
    return git_path.exists()


def get_git_metadata(directory: str) -> Optional[dict]:
    """
    Extract git metadata for a repository/worktree.

    Feature 108: Enhanced to include merge status, staleness, detailed status counts,
    conflict detection, and last commit info.

    Args:
        directory: Path to the git repository

    Returns:
        Dictionary with git metadata, or None if not a git repo
    """
    if not is_git_repository(directory):
        return None

    try:
        # Get current branch
        branch_result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=5
        )
        current_branch = branch_result.stdout.strip() if branch_result.returncode == 0 else "HEAD"

        # Get commit hash (short)
        hash_result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=5
        )
        commit_hash = hash_result.stdout.strip()[:7] if hash_result.returncode == 0 else "0000000"

        # Get status (clean/dirty) with porcelain output
        status_result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=5
        )
        status_lines = status_result.stdout.strip().split("\n") if status_result.stdout.strip() else []
        is_clean = len(status_lines) == 0
        has_untracked = any(line.startswith("??") for line in status_lines)

        # Feature 108 T007: Parse detailed status counts from porcelain output
        staged_count = 0
        modified_count = 0
        untracked_count = 0
        has_conflicts = False

        for line in status_lines:
            if len(line) < 2:
                continue
            x_status = line[0]  # Staged status
            y_status = line[1]  # Working tree status

            # Feature 108 T008: Detect conflicts (UU, AA, DD codes)
            if x_status == 'U' or y_status == 'U' or (x_status == 'A' and y_status == 'A') or (x_status == 'D' and y_status == 'D'):
                has_conflicts = True

            # Count staged files (first column has change)
            if x_status in 'MADRC':
                staged_count += 1

            # Count modified (unstaged) files (second column has change)
            if y_status in 'MD':
                modified_count += 1

            # Count untracked files
            if line.startswith("??"):
                untracked_count += 1

        # Get ahead/behind counts (may fail if no upstream)
        ahead_count = 0
        behind_count = 0
        try:
            ab_result = subprocess.run(
                ["git", "rev-list", "--left-right", "--count", "@{u}...HEAD"],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=5
            )
            if ab_result.returncode == 0:
                parts = ab_result.stdout.strip().split()
                if len(parts) == 2:
                    behind_count = int(parts[0])
                    ahead_count = int(parts[1])
        except (ValueError, IndexError):
            pass

        # Get remote URL (optional)
        remote_result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=5
        )
        remote_url = remote_result.stdout.strip() if remote_result.returncode == 0 else None

        # Feature 108 T006: Get last commit timestamp and message
        last_commit_timestamp = 0
        last_commit_message = ""
        try:
            log_result = subprocess.run(
                ["git", "log", "-1", "--format=%ct|%s"],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=5
            )
            if log_result.returncode == 0:
                parts = log_result.stdout.strip().split("|", 1)
                if len(parts) >= 1 and parts[0]:
                    last_commit_timestamp = int(parts[0])
                if len(parts) >= 2:
                    last_commit_message = parts[1][:50]  # Truncate to 50 chars
        except (ValueError, subprocess.TimeoutExpired, OSError):
            pass

        # Feature 108 T005: Calculate staleness (30+ days since last commit)
        is_stale = False
        if last_commit_timestamp > 0:
            days_since_commit = (int(time.time()) - last_commit_timestamp) // SECONDS_PER_DAY
            is_stale = days_since_commit >= STALE_THRESHOLD_DAYS

        # Feature 108 T004: Check if branch is merged into main
        is_merged = False
        if current_branch not in ("main", "master", "HEAD"):
            try:
                # Check both main and master as potential default branches
                for default_branch in ["main", "master"]:
                    merged_result = subprocess.run(
                        ["git", "branch", "--merged", default_branch],
                        cwd=directory,
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if merged_result.returncode == 0:
                        merged_branches = [b.strip().lstrip("* ") for b in merged_result.stdout.strip().split("\n")]
                        if current_branch in merged_branches:
                            is_merged = True
                            break
            except (subprocess.TimeoutExpired, OSError):
                pass

        return {
            "current_branch": current_branch,
            "commit_hash": commit_hash,
            "is_clean": is_clean,
            "has_untracked": has_untracked,
            "ahead_count": ahead_count,
            "behind_count": behind_count,
            "remote_url": remote_url,
            # Feature 108 enhancements
            "is_merged": is_merged,
            "is_stale": is_stale,
            "last_commit_timestamp": last_commit_timestamp,
            "last_commit_message": last_commit_message,
            "staged_count": staged_count,
            "modified_count": modified_count,
            "untracked_count": untracked_count,
            "has_conflicts": has_conflicts,
        }
    except (subprocess.TimeoutExpired, OSError):
        return None


# =============================================================================
# Feature 111: Visual Worktree Relationship Map - Git Utilities
# =============================================================================


def get_merge_base(repo_path: str, branch_a: str, branch_b: str) -> Optional[str]:
    """
    Feature 111 T013: Get the merge-base commit between two branches.

    The merge-base is the most recent common ancestor of two branches.
    This is used to determine branch parent relationships and calculate
    how far branches have diverged.

    Args:
        repo_path: Path to the repository (any worktree directory works)
        branch_a: First branch name
        branch_b: Second branch name

    Returns:
        Short commit hash (7 chars) of merge-base, or None on error
    """
    try:
        result = subprocess.run(
            ["git", "merge-base", branch_a, branch_b],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()[:7]  # Short hash
    except (subprocess.TimeoutExpired, OSError):
        pass
    return None


def get_branch_relationship(
    repo_path: str,
    source_branch: str,
    target_branch: str
) -> Optional[dict]:
    """
    Feature 111 T014: Determine relationship between two branches.

    Uses `git rev-list --left-right --count` with three-dot syntax to
    get both ahead and behind counts in a single command.

    Args:
        repo_path: Path to the repository
        source_branch: Branch being analyzed
        target_branch: Branch to compare against (usually parent or main)

    Returns:
        Dictionary with keys:
        - ahead: Commits in source not in target
        - behind: Commits in target not in source
        - merge_base: Common ancestor commit hash
        - diverged: True if both ahead AND behind

        Returns None on error.
    """
    try:
        # Use three-dot syntax to get ahead/behind in both directions
        result = subprocess.run(
            ["git", "rev-list", "--left-right", "--count",
             f"{target_branch}...{source_branch}"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            return None

        parts = result.stdout.strip().split()
        if len(parts) != 2:
            return None

        behind_count = int(parts[0])
        ahead_count = int(parts[1])

        # Get merge-base
        merge_base = get_merge_base(repo_path, source_branch, target_branch)

        return {
            "ahead": ahead_count,
            "behind": behind_count,
            "merge_base": merge_base,
            "diverged": ahead_count > 0 and behind_count > 0
        }
    except (ValueError, subprocess.TimeoutExpired, OSError):
        return None


def find_likely_parent_branch(
    repo_path: str,
    target_branch: str,
    candidate_branches: List[str]
) -> Optional[str]:
    """
    Feature 111 T015: Determine which branch is the likely parent of target_branch.

    Uses merge-base distance heuristic: the branch with the smallest commit
    distance from target_branch to the merge-base is the likely parent.

    This handles cases where a feature branch was created from another
    feature branch rather than directly from main.

    Args:
        repo_path: Path to the repository
        target_branch: Branch to find parent for
        candidate_branches: List of potential parent branches

    Returns:
        Name of likely parent branch, or None if inconclusive
    """
    if not candidate_branches:
        return None

    min_distance = float('inf')
    best_candidate = None

    for candidate in candidate_branches:
        if candidate == target_branch:
            continue  # Skip self

        try:
            # Count commits from candidate to target
            # Smaller distance = closer parent
            result = subprocess.run(
                ["git", "rev-list", "--count",
                 f"{candidate}..{target_branch}"],
                cwd=repo_path,
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                distance = int(result.stdout.strip())
                if distance < min_distance:
                    min_distance = distance
                    best_candidate = candidate
        except (ValueError, subprocess.TimeoutExpired, OSError):
            continue

    return best_candidate


class WorktreeRelationshipCache:
    """
    Feature 111 T016: In-memory cache for branch relationships with TTL.

    Caching is essential for performance because computing branch
    relationships requires multiple git commands. With 10 worktrees,
    naive computation would require 45 git merge-base calls (~4-7 seconds).

    Cache invalidation triggers:
    - TTL expiration (default 5 minutes)
    - Manual invalidation via invalidate_repo()
    - Full clear via clear()

    Attributes:
        ttl_seconds: Time-to-live in seconds (default 300 = 5 minutes)
    """

    def __init__(self, ttl_seconds: int = 300):
        """Initialize cache with TTL.

        Args:
            ttl_seconds: Cache entry lifetime in seconds
        """
        from ..models.worktree_relationship import WorktreeRelationship
        self.ttl_seconds = ttl_seconds
        self._cache: dict[str, WorktreeRelationship] = {}

    def _make_key(self, repo_path: str, branch_a: str, branch_b: str) -> str:
        """Generate cache key from repo and branches.

        Args:
            repo_path: Path to repository
            branch_a: First branch name
            branch_b: Second branch name

        Returns:
            Cache key string
        """
        normalized_path = str(Path(repo_path).resolve())
        return f"{normalized_path}:{branch_a}~{branch_b}"

    def get(self, repo_path: str, branch_a: str, branch_b: str):
        """Get cached relationship if not stale.

        Args:
            repo_path: Path to repository
            branch_a: First branch name
            branch_b: Second branch name

        Returns:
            WorktreeRelationship if cached and not stale, None otherwise
        """
        key = self._make_key(repo_path, branch_a, branch_b)
        rel = self._cache.get(key)
        if rel and not rel.is_stale(self.ttl_seconds):
            return rel
        return None

    def set(self, repo_path: str, branch_a: str, branch_b: str, rel) -> None:
        """Cache a relationship.

        Args:
            repo_path: Path to repository
            branch_a: First branch name
            branch_b: Second branch name
            rel: WorktreeRelationship to cache
        """
        key = self._make_key(repo_path, branch_a, branch_b)
        rel.computed_at = int(time.time())
        self._cache[key] = rel

    def invalidate_repo(self, repo_path: str) -> None:
        """Clear all cached relationships for a repository.

        Use this when git operations (commit, push, pull) have occurred
        that may have changed branch relationships.

        Args:
            repo_path: Path to repository
        """
        normalized = str(Path(repo_path).resolve())
        keys_to_delete = [k for k in self._cache if k.startswith(normalized)]
        for k in keys_to_delete:
            del self._cache[k]

    def clear(self) -> None:
        """Clear entire cache."""
        self._cache.clear()


# =============================================================================
# Feature 111 US4: Merge Flow Visualization (T055-T058)
# =============================================================================


def detect_potential_conflicts(
    branch1_files: List[str],
    branch2_files: List[str],
) -> dict:
    """Detect potential merge conflicts between two branches.

    Feature 111 T055/T057: Compare changed files between branches to
    identify overlapping modifications that may cause merge conflicts.

    Args:
        branch1_files: List of files modified in first branch
        branch2_files: List of files modified in second branch

    Returns:
        Dict with:
        - has_conflict: True if any files overlap
        - conflicting_files: List of overlapping file paths
        - conflict_count: Number of conflicting files
    """
    # Find intersection of modified files
    set1 = set(branch1_files)
    set2 = set(branch2_files)
    overlapping = set1 & set2

    return {
        "has_conflict": len(overlapping) > 0,
        "conflicting_files": sorted(list(overlapping)),
        "conflict_count": len(overlapping),
    }


def get_merge_ready_status(
    is_clean: bool,
    ahead_of_main: int,
    behind_main: int,
) -> dict:
    """Determine if a branch is ready to merge to main.

    Feature 111 T056/T058: Check merge readiness based on:
    - Branch is clean (no uncommitted changes)
    - Branch is not behind main (requires rebase/merge first)
    - Branch has commits to merge

    Args:
        is_clean: True if no uncommitted changes
        ahead_of_main: Number of commits ahead of main
        behind_main: Number of commits behind main

    Returns:
        Dict with:
        - is_ready: True if branch can be merged
        - status: "ready", "dirty", "behind", or "no_changes"
        - reason: Human-readable explanation if not ready
        - commits_to_merge: Number of commits to merge (if ready)
    """
    # Check dirty status first (highest priority blocker)
    if not is_clean:
        return {
            "is_ready": False,
            "status": "dirty",
            "reason": "Has uncommitted changes",
            "commits_to_merge": 0,
        }

    # Check if behind main
    if behind_main > 0:
        return {
            "is_ready": False,
            "status": "behind",
            "reason": f"Behind main by {behind_main} commit{'s' if behind_main != 1 else ''}",
            "commits_to_merge": ahead_of_main,
        }

    # Check if there's anything to merge
    if ahead_of_main == 0:
        return {
            "is_ready": False,
            "status": "no_changes",
            "reason": "Nothing to merge - branch is in sync with main",
            "commits_to_merge": 0,
        }

    # Ready to merge
    return {
        "is_ready": True,
        "status": "ready",
        "reason": None,
        "commits_to_merge": ahead_of_main,
    }
