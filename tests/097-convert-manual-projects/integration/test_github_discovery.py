"""
Integration tests for GitHub discovery workflow.

Feature 097: Git-Based Project Discovery and Management
Task T039: Integration test for GitHub discovery workflow

Tests the complete GitHub discovery workflow: listing repos via gh CLI,
correlating with local repos, and creating remote-only projects.

Note: These tests mock gh CLI output since we can't rely on actual
GitHub authentication in CI environments.
"""

import pytest
from pathlib import Path
import tempfile
import shutil
import subprocess
from unittest.mock import AsyncMock, patch


class TestGitHubDiscoveryWorkflow:
    """Integration tests for GitHub discovery with mocked gh CLI."""

    @pytest.fixture
    def temp_workspace(self) -> Path:
        """Create a workspace with a local git repo."""
        workspace = Path(tempfile.mkdtemp())

        # Create a local repo that matches a GitHub repo
        repo_path = workspace / "my-project"
        repo_path.mkdir()
        subprocess.run(["git", "init"], cwd=repo_path, capture_output=True)
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"],
            cwd=repo_path,
            capture_output=True
        )
        subprocess.run(
            ["git", "config", "user.name", "Test User"],
            cwd=repo_path,
            capture_output=True
        )
        subprocess.run(
            ["git", "remote", "add", "origin", "https://github.com/user/my-project.git"],
            cwd=repo_path,
            capture_output=True
        )
        (repo_path / "README.md").write_text("# My Project\n")
        subprocess.run(["git", "add", "."], cwd=repo_path, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "Initial commit"],
            cwd=repo_path,
            capture_output=True
        )

        yield workspace
        shutil.rmtree(workspace, ignore_errors=True)

    @pytest.fixture
    def temp_config_dir(self) -> Path:
        """Create a temporary config directory."""
        config_dir = Path(tempfile.mkdtemp())
        (config_dir / "projects").mkdir()
        yield config_dir
        shutil.rmtree(config_dir, ignore_errors=True)

    @pytest.mark.asyncio
    async def test_discover_with_github_correlation(self, temp_workspace: Path):
        """Should correlate local repos with GitHub repos."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory, correlate_local_remote
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration, GitHubRepo
        )

        # Discover local repos
        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=2
        )
        repos, worktrees, skipped = await scan_directory(temp_workspace, config)

        # Simulate GitHub repos (would come from gh CLI)
        github_repos = [
            GitHubRepo(
                name="my-project",
                full_name="user/my-project",
                clone_url="https://github.com/user/my-project",
                ssh_url="git@github.com:user/my-project.git"
            ),
            GitHubRepo(
                name="uncloned-repo",
                full_name="user/uncloned-repo",
                clone_url="https://github.com/user/uncloned-repo",
                ssh_url="git@github.com:user/uncloned-repo.git"
            )
        ]

        # Correlate
        result = correlate_local_remote(repos, github_repos)

        # my-project should be cloned, uncloned-repo should be remote-only
        assert len(result.cloned) == 1
        assert len(result.remote_only) == 1
        assert result.cloned[0].name == "my-project"
        assert result.cloned[0].has_local_clone is True
        assert result.remote_only[0].name == "uncloned-repo"
        assert result.remote_only[0].has_local_clone is False


class TestGitHubServiceMocked:
    """Tests for github_service.py with mocked subprocess calls."""

    @pytest.fixture
    def mock_gh_output(self):
        """Mock gh CLI JSON output."""
        return [
            {
                "name": "repo-a",
                "nameWithOwner": "user/repo-a",
                "url": "https://github.com/user/repo-a",
                "sshUrl": "git@github.com:user/repo-a.git",
                "isPrivate": False,
                "isFork": False,
                "isArchived": False,
                "primaryLanguage": {"name": "Python"},
                "pushedAt": "2024-01-20T12:00:00Z"
            },
            {
                "name": "repo-b",
                "nameWithOwner": "user/repo-b",
                "url": "https://github.com/user/repo-b",
                "sshUrl": "git@github.com:user/repo-b.git",
                "isPrivate": True,
                "isFork": False,
                "isArchived": False,
                "primaryLanguage": {"name": "TypeScript"},
                "pushedAt": "2024-01-18T09:00:00Z"
            }
        ]

    @pytest.mark.asyncio
    async def test_list_repos_parses_gh_output(self, mock_gh_output):
        """Should parse gh CLI output into GitHubRepo objects."""
        import json
        from home_modules.desktop.i3_project_event_daemon.services.github_service import (
            list_repos
        )

        with patch("asyncio.create_subprocess_exec") as mock_exec:
            # Mock successful gh output
            mock_process = AsyncMock()
            mock_process.returncode = 0
            mock_process.communicate = AsyncMock(
                return_value=(json.dumps(mock_gh_output).encode(), b"")
            )
            mock_exec.return_value = mock_process

            result = await list_repos()

            assert result.success is True
            assert len(result.repos) == 2
            assert result.repos[0].name == "repo-a"
            assert result.repos[0].primary_language == "Python"
            assert result.repos[1].name == "repo-b"
            assert result.repos[1].is_private is True

    @pytest.mark.asyncio
    async def test_list_repos_handles_auth_failure(self):
        """Should handle gh auth failure gracefully."""
        from home_modules.desktop.i3_project_event_daemon.services.github_service import (
            list_repos
        )

        with patch("asyncio.create_subprocess_exec") as mock_exec:
            # Mock auth failure
            mock_process = AsyncMock()
            mock_process.returncode = 1
            mock_process.communicate = AsyncMock(
                return_value=(b"", b"gh: not logged in to any GitHub hosts")
            )
            mock_exec.return_value = mock_process

            result = await list_repos()

            assert result.success is False
            assert len(result.repos) == 0
            assert len(result.errors) > 0

    @pytest.mark.asyncio
    async def test_check_auth_status(self):
        """Should check gh CLI authentication status."""
        from home_modules.desktop.i3_project_event_daemon.services.github_service import (
            check_auth
        )

        with patch("asyncio.create_subprocess_exec") as mock_exec:
            # Mock authenticated
            mock_process = AsyncMock()
            mock_process.returncode = 0
            mock_process.communicate = AsyncMock(
                return_value=(b"Logged in to github.com as user", b"")
            )
            mock_exec.return_value = mock_process

            is_authenticated = await check_auth()

            assert is_authenticated is True

    @pytest.mark.asyncio
    async def test_check_auth_not_authenticated(self):
        """Should detect when not authenticated."""
        from home_modules.desktop.i3_project_event_daemon.services.github_service import (
            check_auth
        )

        with patch("asyncio.create_subprocess_exec") as mock_exec:
            # Mock not authenticated
            mock_process = AsyncMock()
            mock_process.returncode = 1
            mock_process.communicate = AsyncMock(
                return_value=(b"", b"not logged in")
            )
            mock_exec.return_value = mock_process

            is_authenticated = await check_auth()

            assert is_authenticated is False


class TestRemoteOnlyProjectCreation:
    """Tests for creating remote-only projects from GitHub repos."""

    @pytest.fixture
    def temp_config_dir(self) -> Path:
        """Create a temporary config directory."""
        config_dir = Path(tempfile.mkdtemp())
        (config_dir / "projects").mkdir()
        yield config_dir
        shutil.rmtree(config_dir, ignore_errors=True)

    @pytest.mark.asyncio
    async def test_create_remote_only_project(self, temp_config_dir: Path):
        """Should create project with source_type=remote for uncloned repos."""
        from home_modules.desktop.i3_project_event_daemon.services.project_service import (
            ProjectService
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo, SourceType
        )

        project_service = ProjectService(temp_config_dir)

        # Create remote-only GitHub repo
        gh_repo = GitHubRepo(
            name="remote-only",
            full_name="user/remote-only",
            clone_url="https://github.com/user/remote-only",
            ssh_url="git@github.com:user/remote-only.git",
            has_local_clone=False
        )

        # Create project from remote-only repo
        project = await project_service.create_from_github_repo(gh_repo)

        assert project.name == "remote-only"
        assert project.source_type == SourceType.REMOTE
        assert "github.com" in project.directory  # URL as "directory"

    @pytest.mark.asyncio
    async def test_remote_project_preserves_metadata(self, temp_config_dir: Path):
        """Should preserve GitHub metadata in remote-only project."""
        from home_modules.desktop.i3_project_event_daemon.services.project_service import (
            ProjectService
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            GitHubRepo
        )
        from datetime import datetime, timezone

        project_service = ProjectService(temp_config_dir)

        gh_repo = GitHubRepo(
            name="metadata-test",
            full_name="user/metadata-test",
            description="Test repository",
            primary_language="Python",
            clone_url="https://github.com/user/metadata-test",
            ssh_url="git@github.com:user/metadata-test.git",
            pushed_at=datetime(2024, 1, 15, 10, 30, tzinfo=timezone.utc),
            is_private=False,
            is_fork=False,
            has_local_clone=False
        )

        project = await project_service.create_from_github_repo(gh_repo)

        assert project.git_metadata is not None
        assert project.git_metadata.remote_url == "https://github.com/user/metadata-test"
        assert project.git_metadata.primary_language == "Python"
