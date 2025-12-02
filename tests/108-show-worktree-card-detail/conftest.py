"""
Feature 108: Shared pytest fixtures for enhanced worktree card status display tests.

Provides:
- Mock git subprocess results
- Sample worktree state fixtures
- Helper functions for test setup
"""

import pytest
import sys
import time
from pathlib import Path
from unittest.mock import MagicMock, patch
from typing import Dict, Any

# Add fixtures directory to path for imports
_fixtures_dir = Path(__file__).parent / "fixtures"
if str(_fixtures_dir) not in sys.path:
    sys.path.insert(0, str(_fixtures_dir))

from sample_worktree_states import (
    CLEAN_WORKTREE,
    DIRTY_WORKTREE_MODIFIED,
    DIRTY_WORKTREE_UNTRACKED,
    DIRTY_WORKTREE_MIXED,
    MERGED_WORKTREE,
    STALE_WORKTREE,
    STALE_AND_MERGED_WORKTREE,
    CONFLICT_WORKTREE,
    MAIN_BRANCH_WORKTREE,
    DETACHED_HEAD_WORKTREE,
    NO_REMOTE_WORKTREE,
    GIT_STATUS_PORCELAIN_CLEAN,
    GIT_STATUS_PORCELAIN_DIRTY,
    GIT_STATUS_PORCELAIN_CONFLICTS,
    GIT_STATUS_PORCELAIN_STAGED_ONLY,
    GIT_STATUS_PORCELAIN_MODIFIED_ONLY,
    GIT_STATUS_PORCELAIN_UNTRACKED_ONLY,
    create_worktree_data,
)


# --- Worktree data fixtures ---

@pytest.fixture
def clean_worktree() -> Dict[str, Any]:
    """Clean worktree with no uncommitted changes."""
    return CLEAN_WORKTREE.copy()


@pytest.fixture
def dirty_worktree_modified() -> Dict[str, Any]:
    """Dirty worktree with modified files."""
    return DIRTY_WORKTREE_MODIFIED.copy()


@pytest.fixture
def dirty_worktree_untracked() -> Dict[str, Any]:
    """Dirty worktree with untracked files."""
    return DIRTY_WORKTREE_UNTRACKED.copy()


@pytest.fixture
def dirty_worktree_mixed() -> Dict[str, Any]:
    """Dirty worktree with staged, modified, and untracked files."""
    return DIRTY_WORKTREE_MIXED.copy()


@pytest.fixture
def merged_worktree() -> Dict[str, Any]:
    """Worktree with branch merged into main."""
    return MERGED_WORKTREE.copy()


@pytest.fixture
def stale_worktree() -> Dict[str, Any]:
    """Worktree with no commits in 30+ days."""
    return STALE_WORKTREE.copy()


@pytest.fixture
def conflict_worktree() -> Dict[str, Any]:
    """Worktree with unresolved merge conflicts."""
    return CONFLICT_WORKTREE.copy()


@pytest.fixture
def main_branch_worktree() -> Dict[str, Any]:
    """Main branch worktree (should not show 'merged into main')."""
    return MAIN_BRANCH_WORKTREE.copy()


@pytest.fixture
def detached_head_worktree() -> Dict[str, Any]:
    """Worktree in detached HEAD state."""
    return DETACHED_HEAD_WORKTREE.copy()


@pytest.fixture
def no_remote_worktree() -> Dict[str, Any]:
    """Worktree with no remote configured."""
    return NO_REMOTE_WORKTREE.copy()


# --- Git porcelain output fixtures ---

@pytest.fixture
def git_status_clean() -> str:
    """Empty git status output (clean)."""
    return GIT_STATUS_PORCELAIN_CLEAN


@pytest.fixture
def git_status_dirty() -> str:
    """Git status with mixed changes."""
    return GIT_STATUS_PORCELAIN_DIRTY


@pytest.fixture
def git_status_conflicts() -> str:
    """Git status with merge conflicts."""
    return GIT_STATUS_PORCELAIN_CONFLICTS


@pytest.fixture
def git_status_staged_only() -> str:
    """Git status with only staged changes."""
    return GIT_STATUS_PORCELAIN_STAGED_ONLY


@pytest.fixture
def git_status_modified_only() -> str:
    """Git status with only modified (unstaged) changes."""
    return GIT_STATUS_PORCELAIN_MODIFIED_ONLY


@pytest.fixture
def git_status_untracked_only() -> str:
    """Git status with only untracked files."""
    return GIT_STATUS_PORCELAIN_UNTRACKED_ONLY


# --- Helper fixtures ---

@pytest.fixture
def worktree_factory():
    """Factory fixture for creating worktrees with specific states."""
    return create_worktree_data


@pytest.fixture
def mock_subprocess_result():
    """Factory for creating mock subprocess.CompletedProcess results."""
    def _make_result(stdout: str = "", returncode: int = 0) -> MagicMock:
        result = MagicMock()
        result.stdout = stdout
        result.returncode = returncode
        return result
    return _make_result


@pytest.fixture
def mock_time_now():
    """Mock time.time() for consistent timestamp testing."""
    with patch('time.time') as mock_time:
        # Fix time at a known point: 2025-12-01 00:00:00 UTC
        mock_time.return_value = 1733011200
        yield mock_time


# --- Constants for tests ---

STALE_THRESHOLD_DAYS = 30
SECONDS_PER_DAY = 86400
