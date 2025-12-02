"""
Discovery service for Feature 097: Git-Based Project Discovery and Management.

Provides functions for:
- Detecting git repositories and worktrees
- Extracting git metadata
- Scanning directories for repositories
- Resolving name conflicts
- Inferring project icons from language

Per Constitution Principle X: Python 3.11+, async/await, Pydantic.
"""

import asyncio
import logging
import os
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Set, Tuple

from ..models.discovery import (
    CorrelationResult,
    DiscoveredRepository,
    DiscoveredWorktree,
    DiscoveryError,
    DiscoveryResult,
    GitHubRepo,
    GitMetadata,
    ScanConfiguration,
    SkippedPath,
    SourceType,
)

logger = logging.getLogger(__name__)


# =============================================================================
# Git Detection Functions
# =============================================================================

def is_git_repository(path: Path) -> bool:
    """Check if a directory is a git repository.

    A directory is a git repository if it contains either:
    - .git/ directory (standard repository)
    - .git file (worktree or submodule)

    Args:
        path: Directory path to check

    Returns:
        True if path is a git repository, False otherwise

    Per research.md: Uses filesystem checks, no subprocess overhead.
    """
    if not path.exists() or not path.is_dir():
        return False

    git_path = path / ".git"
    return git_path.exists()


def is_worktree(path: Path) -> bool:
    """Check if a directory is a git worktree (not a regular repository).

    Worktrees have a .git FILE (not directory) containing:
    `gitdir: /path/to/repo/.git/worktrees/<name>`

    Args:
        path: Directory path to check

    Returns:
        True if path is a worktree, False otherwise
    """
    git_path = path / ".git"

    if not git_path.exists():
        return False

    return git_path.is_file()


def get_worktree_parent(worktree_path: Path) -> Optional[str]:
    """Get the parent repository path for a worktree.

    Parses the .git file to find the gitdir, then resolves the parent
    repository from the commondir file or path structure.

    Args:
        worktree_path: Path to the worktree

    Returns:
        Absolute path to parent repository, or None if not resolvable

    Per research.md: Uses .git file + commondir resolution pattern.
    """
    git_file = worktree_path / ".git"

    if not git_file.is_file():
        return None

    try:
        content = git_file.read_text().strip()
        # Content: "gitdir: /path/to/repo/.git/worktrees/<name>"
        if not content.startswith("gitdir:"):
            return None

        gitdir = Path(content.replace("gitdir:", "").strip())

        # Try commondir file first (more reliable)
        commondir_file = gitdir / "commondir"
        if commondir_file.exists():
            commondir = commondir_file.read_text().strip()
            # commondir is relative to gitdir
            parent_git = (gitdir / commondir).resolve()
            return str(parent_git.parent)

        # Fallback: derive from path structure
        # /repo/.git/worktrees/<name> → /repo
        if "worktrees" in gitdir.parts:
            worktrees_idx = gitdir.parts.index("worktrees")
            parent_git = Path(*gitdir.parts[:worktrees_idx])
            return str(parent_git.parent)

        return None

    except Exception as e:
        logger.warning(f"Failed to resolve worktree parent for {worktree_path}: {e}")
        return None


# =============================================================================
# Git Metadata Extraction
# =============================================================================

async def _run_git_command(repo_path: Path, *args: str) -> Tuple[int, str, str]:
    """Run a git command and return (returncode, stdout, stderr).

    Args:
        repo_path: Repository path to run command in
        *args: Git command arguments (without 'git')

    Returns:
        Tuple of (return_code, stdout_text, stderr_text)
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            "git", *args,
            cwd=repo_path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        return (
            proc.returncode,
            stdout.decode("utf-8", errors="replace").strip(),
            stderr.decode("utf-8", errors="replace").strip(),
        )
    except Exception as e:
        logger.warning(f"Git command failed in {repo_path}: {e}")
        return (-1, "", str(e))


async def extract_git_metadata(repo_path: Path) -> GitMetadata:
    """Extract git metadata from a repository using git commands.

    Uses async subprocess calls for parallel execution of git commands.

    Args:
        repo_path: Path to git repository

    Returns:
        GitMetadata object with extracted information

    Per research.md: Uses git plumbing commands for reliable parsing.
    Feature 108: Enhanced with merge/stale/conflict detection.
    """
    # Run all git commands in parallel
    branch_task = _run_git_command(repo_path, "rev-parse", "--abbrev-ref", "HEAD")
    commit_task = _run_git_command(repo_path, "rev-parse", "--short", "HEAD")
    status_task = _run_git_command(repo_path, "status", "--porcelain")
    remote_task = _run_git_command(repo_path, "remote", "get-url", "origin")
    ahead_behind_task = _run_git_command(
        repo_path, "rev-list", "--left-right", "--count", "@{u}...HEAD"
    )
    # Feature 108: Get commit timestamp and message
    last_commit_task = _run_git_command(repo_path, "log", "-1", "--format=%ct|%s")

    results = await asyncio.gather(
        branch_task,
        commit_task,
        status_task,
        remote_task,
        ahead_behind_task,
        last_commit_task,
        return_exceptions=True,
    )

    # Parse results
    branch_result = results[0] if not isinstance(results[0], Exception) else (-1, "", "")
    commit_result = results[1] if not isinstance(results[1], Exception) else (-1, "", "")
    status_result = results[2] if not isinstance(results[2], Exception) else (-1, "", "")
    remote_result = results[3] if not isinstance(results[3], Exception) else (-1, "", "")
    ahead_behind_result = results[4] if not isinstance(results[4], Exception) else (-1, "", "")
    last_commit_result = results[5] if not isinstance(results[5], Exception) else (-1, "", "")

    # Extract values
    current_branch = branch_result[1] if branch_result[0] == 0 else "HEAD"
    commit_hash = commit_result[1][:7] if commit_result[0] == 0 and commit_result[1] else "0000000"

    # Parse status - Feature 108: Enhanced with counts and conflict detection
    status_lines = [line for line in (status_result[1].split("\n") if status_result[1] else []) if line.strip()]
    is_clean = len(status_lines) == 0
    has_untracked = any(line.startswith("??") for line in status_lines)

    # Feature 108: Parse detailed status counts
    staged_count = 0
    modified_count = 0
    untracked_count = 0
    has_conflicts = False

    for line in status_lines:
        if len(line) >= 2:
            x, y = line[0], line[1]
            # Conflict detection: UU (both modified), AA (both added), DD (both deleted)
            if x == 'U' or y == 'U' or (x == 'A' and y == 'A') or (x == 'D' and y == 'D'):
                has_conflicts = True
            # Staged changes (first column not space/?)
            if x not in (' ', '?'):
                staged_count += 1
            # Unstaged modifications (second column M)
            if y == 'M':
                modified_count += 1
            # Untracked files
            if x == '?' and y == '?':
                untracked_count += 1

    # Remote URL
    remote_url = remote_result[1] if remote_result[0] == 0 else None

    # Ahead/behind
    ahead_count = 0
    behind_count = 0
    if ahead_behind_result[0] == 0 and ahead_behind_result[1]:
        try:
            parts = ahead_behind_result[1].split()
            if len(parts) >= 2:
                behind_count = int(parts[0])  # Left side = upstream ahead (we're behind)
                ahead_count = int(parts[1])   # Right side = we're ahead
        except (ValueError, IndexError):
            pass

    # Feature 108: Last commit timestamp and message
    last_commit_date = None
    last_commit_timestamp = 0
    last_commit_message = ""
    if last_commit_result[0] == 0 and last_commit_result[1]:
        try:
            parts = last_commit_result[1].split("|", 1)
            if parts:
                last_commit_timestamp = int(parts[0])
                last_commit_date = datetime.fromtimestamp(last_commit_timestamp)
                if len(parts) > 1:
                    last_commit_message = parts[1][:50]  # Truncate to 50 chars
        except (ValueError, IndexError):
            pass

    # Feature 108: Stale detection (30+ days since last commit)
    is_stale = False
    if last_commit_timestamp > 0:
        import time
        days_since = (int(time.time()) - last_commit_timestamp) // 86400
        is_stale = days_since >= 30

    # Feature 108: Merge detection (check if branch merged into main)
    # Skip for main/master branches themselves
    is_merged = False
    if current_branch not in ("main", "master", "HEAD"):
        for default_branch in ["main", "master"]:
            merged_result = await _run_git_command(
                repo_path, "branch", "--merged", default_branch
            )
            if merged_result[0] == 0:
                merged_branches = [b.strip().lstrip("* ") for b in merged_result[1].split("\n")]
                if current_branch in merged_branches:
                    is_merged = True
                    break

    return GitMetadata(
        current_branch=current_branch,
        commit_hash=commit_hash,
        is_clean=is_clean,
        has_untracked=has_untracked,
        ahead_count=ahead_count,
        behind_count=behind_count,
        remote_url=remote_url,
        primary_language=None,  # Inferred separately
        last_commit_date=last_commit_date,
        # Feature 108: Enhanced fields
        is_merged=is_merged,
        is_stale=is_stale,
        has_conflicts=has_conflicts,
        staged_count=staged_count,
        modified_count=modified_count,
        untracked_count=untracked_count,
        last_commit_timestamp=last_commit_timestamp,
        last_commit_message=last_commit_message,
    )


# =============================================================================
# Name Resolution
# =============================================================================

def derive_project_name(path: Path) -> str:
    """Derive a project name from a directory path.

    Args:
        path: Directory path

    Returns:
        Project name (last component of path)
    """
    return path.name


def generate_unique_name(base_name: str, existing_names: Set[str]) -> str:
    """Generate a unique project name by appending numeric suffix if needed.

    Algorithm:
    - If base_name is unique, return it
    - Otherwise, try base_name-2, base_name-3, etc.

    Args:
        base_name: Desired project name
        existing_names: Set of names that already exist

    Returns:
        Unique project name

    Per research.md: Simple numeric suffix approach.
    """
    if base_name not in existing_names:
        return base_name

    counter = 2
    while f"{base_name}-{counter}" in existing_names:
        counter += 1

    return f"{base_name}-{counter}"


# =============================================================================
# Language Detection and Icon Inference
# =============================================================================

# Language to emoji icon mapping
LANGUAGE_ICONS = {
    "Python": "🐍",
    "TypeScript": "📘",
    "JavaScript": "📒",
    "Rust": "🦀",
    "Go": "🐹",
    "Nix": "❄️",
    "Shell": "🐚",
    "Bash": "🐚",
    "Java": "☕",
    "C": "⚙️",
    "C++": "⚙️",
    "Ruby": "💎",
    "PHP": "🐘",
    "Kotlin": "🎯",
    "Swift": "🕊️",
    "Haskell": "λ",
    "Elixir": "💧",
    "Lua": "🌙",
    "Vim script": "📝",
    "HTML": "🌐",
    "CSS": "🎨",
}

# File extension to language mapping for detection
EXTENSION_LANGUAGE = {
    ".py": "Python",
    ".ts": "TypeScript",
    ".tsx": "TypeScript",
    ".js": "JavaScript",
    ".jsx": "JavaScript",
    ".rs": "Rust",
    ".go": "Go",
    ".nix": "Nix",
    ".sh": "Shell",
    ".bash": "Bash",
    ".java": "Java",
    ".c": "C",
    ".h": "C",
    ".cpp": "C++",
    ".hpp": "C++",
    ".rb": "Ruby",
    ".php": "PHP",
    ".kt": "Kotlin",
    ".swift": "Swift",
    ".hs": "Haskell",
    ".ex": "Elixir",
    ".exs": "Elixir",
    ".lua": "Lua",
    ".vim": "Vim script",
}


def infer_language_from_repo(repo_path: Path) -> Optional[str]:
    """Infer the primary programming language from repository files.

    Simple heuristic: count files by extension, pick most common.

    Args:
        repo_path: Path to repository

    Returns:
        Language name or None if not detectable
    """
    try:
        extension_counts: dict[str, int] = {}

        # Walk directory (limited depth for performance)
        for root, dirs, files in os.walk(repo_path):
            # Skip hidden directories and common non-source dirs
            dirs[:] = [
                d for d in dirs
                if not d.startswith(".")
                and d not in {"node_modules", "vendor", "target", "build", "dist", "__pycache__"}
            ]

            # Limit depth
            depth = len(Path(root).relative_to(repo_path).parts)
            if depth > 3:
                continue

            for file in files:
                ext = Path(file).suffix.lower()
                if ext in EXTENSION_LANGUAGE:
                    extension_counts[ext] = extension_counts.get(ext, 0) + 1

        if not extension_counts:
            return None

        # Find most common extension
        most_common = max(extension_counts.items(), key=lambda x: x[1])
        return EXTENSION_LANGUAGE.get(most_common[0])

    except Exception as e:
        logger.warning(f"Failed to infer language for {repo_path}: {e}")
        return None


def infer_icon_from_language(language: Optional[str], is_worktree: bool = False) -> str:
    """Get an emoji icon based on programming language.

    Args:
        language: Programming language name
        is_worktree: If True, return worktree-specific icon

    Returns:
        Emoji icon string
    """
    if is_worktree:
        return "🌿"

    if language and language in LANGUAGE_ICONS:
        return LANGUAGE_ICONS[language]

    return "📁"  # Default folder icon


# =============================================================================
# GitHub Correlation
# =============================================================================

def _normalize_git_url(url: Optional[str]) -> Optional[str]:
    """Normalize a git URL for comparison.

    Removes .git suffix and normalizes to https format.

    Args:
        url: Git URL (https or ssh format)

    Returns:
        Normalized URL or None
    """
    if not url:
        return None

    # Remove trailing .git
    if url.endswith(".git"):
        url = url[:-4]

    # Convert SSH to HTTPS format for comparison
    if url.startswith("git@github.com:"):
        # git@github.com:user/repo -> https://github.com/user/repo
        path = url.replace("git@github.com:", "")
        url = f"https://github.com/{path}"

    return url.lower()


def correlate_local_remote(
    local_repos: List[DiscoveredRepository],
    github_repos: List[GitHubRepo],
) -> CorrelationResult:
    """Correlate local repositories with GitHub repositories.

    Feature 097: Identifies which GitHub repos have local clones.

    Matching strategy (in order of priority):
    1. Remote URL match (most reliable)
    2. Repository name match (fallback)

    Args:
        local_repos: List of locally discovered repositories
        github_repos: List of GitHub repositories from gh CLI

    Returns:
        CorrelationResult with cloned and remote_only lists
    """
    # Build index of local repos by normalized remote URL
    local_by_url: dict[str, DiscoveredRepository] = {}
    local_by_name: dict[str, DiscoveredRepository] = {}

    for repo in local_repos:
        if repo.git_metadata and repo.git_metadata.remote_url:
            normalized = _normalize_git_url(repo.git_metadata.remote_url)
            if normalized:
                local_by_url[normalized] = repo
        local_by_name[repo.name.lower()] = repo

    cloned: List[GitHubRepo] = []
    remote_only: List[GitHubRepo] = []

    for gh_repo in github_repos:
        # Try URL match first
        normalized_clone = _normalize_git_url(gh_repo.clone_url)
        normalized_ssh = _normalize_git_url(gh_repo.ssh_url)

        matched_local: Optional[DiscoveredRepository] = None

        # Check clone URL
        if normalized_clone and normalized_clone in local_by_url:
            matched_local = local_by_url[normalized_clone]
        # Check SSH URL
        elif normalized_ssh and normalized_ssh in local_by_url:
            matched_local = local_by_url[normalized_ssh]
        # Fallback to name match
        elif gh_repo.name.lower() in local_by_name:
            matched_local = local_by_name[gh_repo.name.lower()]

        if matched_local:
            # Mark as cloned
            gh_repo_copy = gh_repo.model_copy()
            gh_repo_copy.has_local_clone = True
            gh_repo_copy.local_project_name = matched_local.name
            cloned.append(gh_repo_copy)
        else:
            # Mark as remote-only
            gh_repo_copy = gh_repo.model_copy()
            gh_repo_copy.has_local_clone = False
            remote_only.append(gh_repo_copy)

    return CorrelationResult(
        cloned=cloned,
        remote_only=remote_only
    )


# =============================================================================
# Directory Scanning
# =============================================================================

async def scan_directory(
    scan_path: Path,
    config: ScanConfiguration,
    existing_names: Optional[Set[str]] = None,
) -> Tuple[List[DiscoveredRepository], List[DiscoveredWorktree], List[SkippedPath]]:
    """Scan a directory for git repositories.

    Recursively walks the directory tree up to max_depth, finding git
    repositories and worktrees while respecting exclude patterns.

    Args:
        scan_path: Root directory to scan
        config: Scan configuration with exclude patterns and max_depth
        existing_names: Set of existing project names for conflict resolution

    Returns:
        Tuple of (discovered_repos, discovered_worktrees, skipped_paths)
    """
    if existing_names is None:
        existing_names = set()

    repos: List[DiscoveredRepository] = []
    worktrees: List[DiscoveredWorktree] = []
    skipped: List[SkippedPath] = []
    used_names = existing_names.copy()

    async def _scan_recursive(path: Path, depth: int) -> None:
        """Recursively scan directory for git repos."""
        nonlocal repos, worktrees, skipped, used_names

        if depth > config.max_depth:
            return

        if not path.exists() or not path.is_dir():
            return

        # Check if current directory is a git repository
        if is_git_repository(path):
            try:
                # Extract metadata
                metadata = await extract_git_metadata(path)

                # Infer language and icon
                language = infer_language_from_repo(path)
                if language:
                    metadata = GitMetadata(
                        **{**metadata.model_dump(), "primary_language": language}
                    )

                # Generate unique name
                base_name = derive_project_name(path)
                unique_name = generate_unique_name(base_name, used_names)
                used_names.add(unique_name)

                if is_worktree(path):
                    parent_path = get_worktree_parent(path)
                    if parent_path:
                        worktrees.append(DiscoveredWorktree(
                            path=str(path),
                            name=unique_name,
                            is_worktree=True,
                            git_metadata=metadata,
                            parent_repo_path=parent_path,
                            inferred_icon=infer_icon_from_language(language, is_worktree=True),
                        ))
                    else:
                        # Can't resolve parent, treat as regular repo
                        repos.append(DiscoveredRepository(
                            path=str(path),
                            name=unique_name,
                            is_worktree=False,
                            git_metadata=metadata,
                            inferred_icon=infer_icon_from_language(language),
                        ))
                else:
                    repos.append(DiscoveredRepository(
                        path=str(path),
                        name=unique_name,
                        is_worktree=False,
                        git_metadata=metadata,
                        inferred_icon=infer_icon_from_language(language),
                    ))

            except Exception as e:
                logger.warning(f"Failed to process repository {path}: {e}")
                skipped.append(SkippedPath(
                    path=str(path),
                    reason=f"git_metadata_extraction_failed: {str(e)}"
                ))

            # Don't recurse into git repos (they handle their own .git)
            return

        # Check if directory matches exclude patterns
        dir_name = path.name
        if dir_name in config.exclude_patterns:
            return  # Skip without logging as skipped (these are expected)

        # Not a git repo, check subdirectories
        try:
            subdirs = []
            for entry in path.iterdir():
                if entry.is_dir() and not entry.name.startswith("."):
                    subdirs.append(entry)

            # Process subdirectories
            for subdir in subdirs:
                await _scan_recursive(subdir, depth + 1)

        except PermissionError:
            skipped.append(SkippedPath(
                path=str(path),
                reason="permission_denied"
            ))
        except Exception as e:
            skipped.append(SkippedPath(
                path=str(path),
                reason=f"scan_error: {str(e)}"
            ))

    # If scan_path itself doesn't contain git repos at top level,
    # record it as skipped for non-git directories
    if scan_path.exists() and scan_path.is_dir():
        if not is_git_repository(scan_path):
            # Scan subdirectories
            try:
                for entry in scan_path.iterdir():
                    if entry.is_dir() and not entry.name.startswith("."):
                        if entry.name not in config.exclude_patterns:
                            if not is_git_repository(entry):
                                # Record non-git directory as skipped
                                skipped.append(SkippedPath(
                                    path=str(entry),
                                    reason="no_git_directory"
                                ))
            except PermissionError:
                pass

    await _scan_recursive(scan_path, 0)

    return repos, worktrees, skipped


async def discover_projects(
    config: ScanConfiguration,
    existing_names: Optional[Set[str]] = None,
    dry_run: bool = False,
) -> DiscoveryResult:
    """Run discovery on all configured scan paths.

    Args:
        config: Scan configuration with paths and settings
        existing_names: Existing project names for conflict avoidance
        dry_run: If True, don't create projects (just report what would be found)

    Returns:
        DiscoveryResult with discovered repos, worktrees, and stats
    """
    import time
    start_time = time.perf_counter()

    if existing_names is None:
        existing_names = set()

    all_repos: List[DiscoveredRepository] = []
    all_worktrees: List[DiscoveredWorktree] = []
    all_skipped: List[SkippedPath] = []
    all_errors: List[DiscoveryError] = []

    used_names = existing_names.copy()

    for scan_path_str in config.scan_paths:
        scan_path = Path(scan_path_str).expanduser().resolve()

        if not scan_path.exists():
            all_errors.append(DiscoveryError(
                path=scan_path_str,
                error="path_not_found",
                message=f"Scan path does not exist: {scan_path_str}"
            ))
            continue

        if not scan_path.is_dir():
            all_errors.append(DiscoveryError(
                path=scan_path_str,
                error="not_a_directory",
                message=f"Scan path is not a directory: {scan_path_str}"
            ))
            continue

        try:
            repos, worktrees, skipped = await scan_directory(
                scan_path, config, used_names
            )
            all_repos.extend(repos)
            all_worktrees.extend(worktrees)
            all_skipped.extend(skipped)

            # Track used names across scan paths
            for r in repos:
                used_names.add(r.name)
            for w in worktrees:
                used_names.add(w.name)

        except Exception as e:
            all_errors.append(DiscoveryError(
                path=scan_path_str,
                error="scan_failed",
                message=str(e)
            ))

    duration_ms = int((time.perf_counter() - start_time) * 1000)

    logger.info(
        f"[Feature 097] Discovery complete: "
        f"{len(all_repos)} repos, {len(all_worktrees)} worktrees, "
        f"{len(all_skipped)} skipped, {len(all_errors)} errors "
        f"in {duration_ms}ms"
    )

    return DiscoveryResult(
        success=len(all_errors) == 0 or len(all_repos) + len(all_worktrees) > 0,
        discovered_repos=all_repos,
        discovered_worktrees=all_worktrees,
        skipped_paths=all_skipped,
        projects_created=0 if dry_run else len(all_repos) + len(all_worktrees),
        projects_updated=0,
        projects_marked_missing=0,
        duration_ms=duration_ms,
        errors=all_errors,
    )
