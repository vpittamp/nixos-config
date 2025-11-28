"""
Git Utilities for Feature 097: Git-Centric Project and Worktree Management

This module provides core git discovery utilities that ALL user stories depend on:
- get_bare_repository_path(): Canonical identifier for worktrees
- determine_source_type(): Classify project as repository/worktree/standalone
- find_repository_for_bare_repo(): Find parent repository project
- detect_orphaned_worktrees(): Find worktrees with missing parents
- generate_unique_name(): Conflict resolution for project names
"""

import subprocess
from pathlib import Path
from typing import Optional, List, Set

from ..models.project_config import ProjectConfig, SourceType, ProjectStatus


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

        # Get status (clean/dirty)
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

        return {
            "current_branch": current_branch,
            "commit_hash": commit_hash,
            "is_clean": is_clean,
            "has_untracked": has_untracked,
            "ahead_count": ahead_count,
            "behind_count": behind_count,
            "remote_url": remote_url,
        }
    except (subprocess.TimeoutExpired, OSError):
        return None
