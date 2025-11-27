"""
Unit tests for local/remote repository correlation.

Feature 097: Git-Based Project Discovery and Management
Task T038: Test local/remote repo correlation

Tests the correlation of locally discovered repositories with GitHub
repositories to identify which are cloned and which are remote-only.
"""

import pytest
from pathlib import Path


class TestRepoCorrelation:
    """Test cases for correlating local and remote repositories."""

    def test_correlate_by_remote_url(self):
        """Should correlate local repo with GitHub by remote URL."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            correlate_local_remote
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            DiscoveredRepository, GitHubRepo, GitMetadata
        )

        local_repos = [
            DiscoveredRepository(
                name="my-project",
                path="/home/user/projects/my-project",
                is_worktree=False,
                inferred_icon="🐍",
                git_metadata=GitMetadata(
                    current_branch="main",
                    commit_hash="abc1234",
                    is_clean=True,
                    has_untracked=False,
                    ahead_count=0,
                    behind_count=0,
                    remote_url="https://github.com/user/my-project.git"
                )
            )
        ]

        github_repos = [
            GitHubRepo(
                name="my-project",
                full_name="user/my-project",
                clone_url="https://github.com/user/my-project",
                ssh_url="git@github.com:user/my-project.git"
            )
        ]

        result = correlate_local_remote(local_repos, github_repos)

        # GitHub repo should be marked as having local clone
        assert len(result.cloned) == 1
        assert result.cloned[0].name == "my-project"
        assert result.cloned[0].has_local_clone is True
        assert result.cloned[0].local_project_name == "my-project"

    def test_identify_remote_only_repos(self):
        """Should identify GitHub repos without local clones."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            correlate_local_remote
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            DiscoveredRepository, GitHubRepo, GitMetadata
        )

        local_repos = [
            DiscoveredRepository(
                name="local-only",
                path="/home/user/projects/local-only",
                is_worktree=False,
                inferred_icon="📁",
                git_metadata=GitMetadata(
                    current_branch="main",
                    commit_hash="abc1234",
                    is_clean=True,
                    has_untracked=False,
                    remote_url="https://github.com/user/local-only.git"
                )
            )
        ]

        github_repos = [
            GitHubRepo(
                name="local-only",
                full_name="user/local-only",
                clone_url="https://github.com/user/local-only",
                ssh_url="git@github.com:user/local-only.git"
            ),
            GitHubRepo(
                name="remote-only",
                full_name="user/remote-only",
                clone_url="https://github.com/user/remote-only",
                ssh_url="git@github.com:user/remote-only.git"
            )
        ]

        result = correlate_local_remote(local_repos, github_repos)

        # Should have one cloned and one remote-only
        assert len(result.cloned) == 1
        assert len(result.remote_only) == 1
        assert result.remote_only[0].name == "remote-only"
        assert result.remote_only[0].has_local_clone is False

    def test_correlate_by_ssh_url(self):
        """Should correlate when local repo uses SSH URL."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            correlate_local_remote
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            DiscoveredRepository, GitHubRepo, GitMetadata
        )

        local_repos = [
            DiscoveredRepository(
                name="ssh-clone",
                path="/home/user/projects/ssh-clone",
                is_worktree=False,
                inferred_icon="📁",
                git_metadata=GitMetadata(
                    current_branch="main",
                    commit_hash="abc1234",
                    is_clean=True,
                    has_untracked=False,
                    # Local uses SSH URL
                    remote_url="git@github.com:user/ssh-clone.git"
                )
            )
        ]

        github_repos = [
            GitHubRepo(
                name="ssh-clone",
                full_name="user/ssh-clone",
                clone_url="https://github.com/user/ssh-clone",
                ssh_url="git@github.com:user/ssh-clone.git"
            )
        ]

        result = correlate_local_remote(local_repos, github_repos)

        assert len(result.cloned) == 1
        assert result.cloned[0].name == "ssh-clone"
        assert result.cloned[0].has_local_clone is True

    def test_correlate_by_repo_name_fallback(self):
        """Should correlate by repo name if no remote URL match."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            correlate_local_remote
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            DiscoveredRepository, GitHubRepo, GitMetadata
        )

        local_repos = [
            DiscoveredRepository(
                name="my-repo",
                path="/home/user/projects/my-repo",
                is_worktree=False,
                inferred_icon="📁",
                git_metadata=GitMetadata(
                    current_branch="main",
                    commit_hash="abc1234",
                    is_clean=True,
                    has_untracked=False,
                    # No remote URL
                    remote_url=None
                )
            )
        ]

        github_repos = [
            GitHubRepo(
                name="my-repo",
                full_name="user/my-repo",
                clone_url="https://github.com/user/my-repo",
                ssh_url="git@github.com:user/my-repo.git"
            )
        ]

        result = correlate_local_remote(local_repos, github_repos)

        # Should still correlate by name
        assert len(result.cloned) == 1
        assert result.cloned[0].name == "my-repo"

    def test_no_correlation_for_local_only_repos(self):
        """Local repos not on GitHub should not appear in correlation results."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            correlate_local_remote
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            DiscoveredRepository, GitHubRepo, GitMetadata
        )

        local_repos = [
            DiscoveredRepository(
                name="private-local",
                path="/home/user/projects/private-local",
                is_worktree=False,
                inferred_icon="📁",
                git_metadata=GitMetadata(
                    current_branch="main",
                    commit_hash="abc1234",
                    is_clean=True,
                    has_untracked=False,
                    remote_url="https://gitlab.com/user/private-local.git"
                )
            )
        ]

        github_repos = [
            GitHubRepo(
                name="different-repo",
                full_name="user/different-repo",
                clone_url="https://github.com/user/different-repo",
                ssh_url="git@github.com:user/different-repo.git"
            )
        ]

        result = correlate_local_remote(local_repos, github_repos)

        # Should have no clones and one remote-only
        assert len(result.cloned) == 0
        assert len(result.remote_only) == 1
        assert result.remote_only[0].name == "different-repo"

    def test_empty_inputs(self):
        """Should handle empty input lists."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            correlate_local_remote
        )

        result = correlate_local_remote([], [])

        assert len(result.cloned) == 0
        assert len(result.remote_only) == 0

    def test_normalize_url_variations(self):
        """Should normalize URL variations (with/without .git suffix)."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            correlate_local_remote
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            DiscoveredRepository, GitHubRepo, GitMetadata
        )

        local_repos = [
            DiscoveredRepository(
                name="url-variation",
                path="/home/user/projects/url-variation",
                is_worktree=False,
                inferred_icon="📁",
                git_metadata=GitMetadata(
                    current_branch="main",
                    commit_hash="abc1234",
                    is_clean=True,
                    has_untracked=False,
                    # URL without .git suffix
                    remote_url="https://github.com/user/url-variation"
                )
            )
        ]

        github_repos = [
            GitHubRepo(
                name="url-variation",
                full_name="user/url-variation",
                # URL without .git suffix (GitHub API format)
                clone_url="https://github.com/user/url-variation",
                ssh_url="git@github.com:user/url-variation.git"
            )
        ]

        result = correlate_local_remote(local_repos, github_repos)

        assert len(result.cloned) == 1
