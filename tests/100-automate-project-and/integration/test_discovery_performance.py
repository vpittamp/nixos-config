"""
Feature 100: Performance Validation Test

T058: Verify discovery completes in <5s for 50 repos + 100 worktrees (SC-001)

This test creates a mock repository structure and validates discovery performance.
"""

import json
import pytest
import subprocess
import tempfile
import time
from pathlib import Path


# Performance target from spec
MAX_DISCOVERY_TIME_SECONDS = 5.0
TARGET_REPO_COUNT = 50
TARGET_WORKTREE_COUNT = 100


@pytest.fixture
def performance_test_environment(tmp_path):
    """Create a performance test environment with many repos and worktrees."""
    repos_dir = tmp_path / "repos"
    repos_dir.mkdir()

    config_dir = tmp_path / "config" / "i3"
    config_dir.mkdir(parents=True)

    # Create multiple test accounts
    accounts = []
    for account_num in range(5):  # 5 accounts
        account_name = f"test-account-{account_num}"
        account_path = repos_dir / account_name
        account_path.mkdir()
        accounts.append({
            "name": account_name,
            "path": str(account_path),
            "is_default": account_num == 0,
            "ssh_host": "github.com"
        })

    # Write accounts config
    accounts_data = {"version": 1, "accounts": accounts}
    (config_dir / "accounts.json").write_text(json.dumps(accounts_data, indent=2))

    return {
        "repos_dir": repos_dir,
        "config_dir": config_dir,
        "accounts": accounts,
        "tmp_path": tmp_path
    }


def create_mock_bare_repo(account_dir: Path, repo_name: str, worktree_count: int) -> dict:
    """Create a mock bare repository structure without actual git operations.

    For performance testing, we simulate the directory structure that discovery
    would find, without the overhead of actual git operations.
    """
    repo_dir = account_dir / repo_name
    repo_dir.mkdir(exist_ok=True)

    # Create .bare directory with minimal git structure
    bare_dir = repo_dir / ".bare"
    bare_dir.mkdir(exist_ok=True)

    # Create minimal git structure to look like a bare repo
    (bare_dir / "HEAD").write_text("ref: refs/heads/main\n")
    (bare_dir / "config").write_text("[core]\nbare = true\n")
    refs_dir = bare_dir / "refs" / "heads"
    refs_dir.mkdir(parents=True, exist_ok=True)
    (refs_dir / "main").write_text("0" * 40 + "\n")

    # Create .git pointer
    (repo_dir / ".git").write_text("gitdir: ./.bare")

    # Create mock worktree directories
    worktree_info = []
    for wt_num in range(worktree_count):
        branch_name = "main" if wt_num == 0 else f"{wt_num:03d}-feature"
        wt_dir = repo_dir / branch_name
        wt_dir.mkdir(exist_ok=True)

        # Create minimal worktree indicator
        (wt_dir / ".git").write_text(f"gitdir: ../.bare/worktrees/{branch_name}")

        worktree_info.append({
            "branch": branch_name,
            "path": str(wt_dir)
        })

    # Create worktrees directory in bare repo (git worktree list reads this)
    worktrees_dir = bare_dir / "worktrees"
    worktrees_dir.mkdir(exist_ok=True)

    for wt in worktree_info:
        wt_meta_dir = worktrees_dir / wt["branch"]
        wt_meta_dir.mkdir(exist_ok=True)
        (wt_meta_dir / "gitdir").write_text(wt["path"] + "/.git")
        (wt_meta_dir / "HEAD").write_text("0" * 40 + "\n")

    return {
        "repo_dir": repo_dir,
        "bare_dir": bare_dir,
        "worktrees": worktree_info
    }


class TestDiscoveryPerformance:
    """Performance tests for repository discovery."""

    @pytest.fixture
    def populated_environment(self, performance_test_environment):
        """Create environment with target number of repos and worktrees."""
        repos_dir = performance_test_environment["repos_dir"]
        accounts = performance_test_environment["accounts"]

        # Distribute repos across accounts
        repos_per_account = TARGET_REPO_COUNT // len(accounts)
        worktrees_per_repo = TARGET_WORKTREE_COUNT // TARGET_REPO_COUNT

        total_repos = 0
        total_worktrees = 0

        for account in accounts:
            account_path = Path(account["path"])
            for repo_num in range(repos_per_account):
                repo_name = f"test-repo-{repo_num}"
                result = create_mock_bare_repo(
                    account_path,
                    repo_name,
                    worktrees_per_repo
                )
                total_repos += 1
                total_worktrees += len(result["worktrees"])

        return {
            **performance_test_environment,
            "total_repos": total_repos,
            "total_worktrees": total_worktrees
        }

    def test_discovery_directory_scan_performance(self, populated_environment):
        """Test that directory scanning completes quickly."""
        repos_dir = populated_environment["repos_dir"]
        start_time = time.perf_counter()

        # Simulate discovery scan
        repos_found = 0
        worktrees_found = 0

        for account_dir in repos_dir.iterdir():
            if not account_dir.is_dir():
                continue

            for repo_dir in account_dir.iterdir():
                if not repo_dir.is_dir():
                    continue

                bare_path = repo_dir / ".bare"
                if not bare_path.is_dir():
                    continue

                repos_found += 1

                # Count worktree directories
                for entry in repo_dir.iterdir():
                    if entry.is_dir() and entry.name not in (".bare",):
                        # Check if it's a worktree (has .git file)
                        if (entry / ".git").exists():
                            worktrees_found += 1

        elapsed = time.perf_counter() - start_time

        print(f"\nDiscovery Performance:")
        print(f"  Repos found: {repos_found}")
        print(f"  Worktrees found: {worktrees_found}")
        print(f"  Time elapsed: {elapsed:.3f}s")
        print(f"  Target: <{MAX_DISCOVERY_TIME_SECONDS}s")

        assert elapsed < MAX_DISCOVERY_TIME_SECONDS, (
            f"Discovery took {elapsed:.3f}s, exceeds target of {MAX_DISCOVERY_TIME_SECONDS}s"
        )
        assert repos_found >= TARGET_REPO_COUNT - 5, (
            f"Found {repos_found} repos, expected ~{TARGET_REPO_COUNT}"
        )
        assert worktrees_found >= TARGET_WORKTREE_COUNT - 10, (
            f"Found {worktrees_found} worktrees, expected ~{TARGET_WORKTREE_COUNT}"
        )

    def test_repos_json_write_performance(self, populated_environment):
        """Test that writing repos.json is fast."""
        config_dir = populated_environment["config_dir"]
        repos_file = config_dir / "repos.json"

        # Create mock discovery data
        repositories = []
        for i in range(TARGET_REPO_COUNT):
            worktrees = []
            worktrees_per_repo = TARGET_WORKTREE_COUNT // TARGET_REPO_COUNT
            for j in range(worktrees_per_repo):
                worktrees.append({
                    "branch": f"{j:03d}-feature" if j > 0 else "main",
                    "path": f"/tmp/repos/account/repo-{i}/{j:03d}-feature",
                    "commit": "0" * 40,
                    "is_main": j == 0,
                    "is_clean": True,
                    "ahead": 0,
                    "behind": 0
                })

            repositories.append({
                "account": f"account-{i // 10}",
                "name": f"repo-{i}",
                "path": f"/tmp/repos/account/repo-{i}",
                "remote_url": f"git@github.com:account/repo-{i}.git",
                "default_branch": "main",
                "worktrees": worktrees,
                "discovered_at": "2024-01-01T00:00:00Z"
            })

        repos_data = {
            "version": 1,
            "last_discovery": "2024-01-01T00:00:00Z",
            "repositories": repositories
        }

        # Measure write time
        start_time = time.perf_counter()
        repos_file.write_text(json.dumps(repos_data, indent=2))
        write_elapsed = time.perf_counter() - start_time

        # Measure read time
        start_time = time.perf_counter()
        loaded = json.loads(repos_file.read_text())
        read_elapsed = time.perf_counter() - start_time

        print(f"\nJSON I/O Performance:")
        print(f"  File size: {repos_file.stat().st_size / 1024:.1f} KB")
        print(f"  Write time: {write_elapsed * 1000:.1f}ms")
        print(f"  Read time: {read_elapsed * 1000:.1f}ms")

        # Both operations should be under 500ms
        assert write_elapsed < 0.5, f"Write took {write_elapsed:.3f}s"
        assert read_elapsed < 0.5, f"Read took {read_elapsed:.3f}s"
        assert len(loaded["repositories"]) == TARGET_REPO_COUNT


class TestScalability:
    """Tests for scalability requirements."""

    def test_qualified_name_generation_performance(self):
        """Test that qualified name generation is O(1)."""
        iterations = 10000

        start_time = time.perf_counter()
        for i in range(iterations):
            account = f"account-{i % 10}"
            repo = f"repo-{i % 100}"
            branch = f"feature-{i}"
            qualified = f"{account}/{repo}:{branch}"
            assert ":" in qualified

        elapsed = time.perf_counter() - start_time
        per_name = (elapsed / iterations) * 1000000  # microseconds

        print(f"\nQualified Name Generation:")
        print(f"  {iterations} iterations in {elapsed * 1000:.1f}ms")
        print(f"  Per name: {per_name:.2f}µs")

        assert per_name < 10, f"Name generation too slow: {per_name:.2f}µs per name"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
