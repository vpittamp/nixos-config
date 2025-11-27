"""
Integration tests for local git repository discovery.

Feature 097: Git-Based Project Discovery and Management
Task T017: Integration test for local discovery workflow

Tests the complete discovery workflow: scanning directories, detecting
git repos, extracting metadata, and creating projects.
"""

import pytest
from pathlib import Path
import tempfile
import shutil
import subprocess


class TestLocalDiscoveryWorkflow:
    """Integration tests for the complete local discovery workflow."""

    @pytest.fixture
    def temp_workspace(self) -> Path:
        """Create a temporary workspace with multiple git repos."""
        workspace = Path(tempfile.mkdtemp())

        # Create a few git repositories
        repos = ["project-alpha", "project-beta", "project-gamma"]
        for repo_name in repos:
            repo_path = workspace / repo_name
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
            # Create initial commit
            (repo_path / "README.md").write_text(f"# {repo_name}\n")
            subprocess.run(["git", "add", "."], cwd=repo_path, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", "Initial commit"],
                cwd=repo_path,
                capture_output=True
            )

        # Create a non-git directory (should be skipped)
        (workspace / "not-a-repo").mkdir()
        (workspace / "not-a-repo" / "file.txt").write_text("content")

        yield workspace
        shutil.rmtree(workspace, ignore_errors=True)

    @pytest.fixture
    def temp_config_dir(self) -> Path:
        """Create a temporary config directory for test projects."""
        config_dir = Path(tempfile.mkdtemp())
        (config_dir / "projects").mkdir()
        yield config_dir
        shutil.rmtree(config_dir, ignore_errors=True)

    @pytest.mark.asyncio
    async def test_discover_finds_all_git_repos(self, temp_workspace: Path):
        """Discovery should find all git repositories in directory."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration
        )

        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=2
        )

        repos, worktrees, skipped = await scan_directory(temp_workspace, config)

        # Should find 3 repos, no worktrees
        assert len(repos) == 3
        assert len(worktrees) == 0

        repo_names = {r.name for r in repos}
        assert repo_names == {"project-alpha", "project-beta", "project-gamma"}

    @pytest.mark.asyncio
    async def test_discover_skips_non_git_directories(self, temp_workspace: Path):
        """Discovery should skip directories without .git."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration
        )

        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=2
        )

        repos, worktrees, skipped = await scan_directory(temp_workspace, config)

        # "not-a-repo" should be in skipped
        skipped_paths = {s.path for s in skipped}
        assert str(temp_workspace / "not-a-repo") in skipped_paths

    @pytest.mark.asyncio
    async def test_discover_respects_exclude_patterns(self, temp_workspace: Path):
        """Discovery should skip directories matching exclude patterns."""
        # Create a node_modules directory (should be excluded)
        nm_path = temp_workspace / "node_project"
        nm_path.mkdir()
        subprocess.run(["git", "init"], cwd=nm_path, capture_output=True)
        (nm_path / "node_modules").mkdir()
        (nm_path / "node_modules" / "dep").mkdir()
        subprocess.run(
            ["git", "init"],
            cwd=nm_path / "node_modules" / "dep",
            capture_output=True
        )

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration
        )

        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=["node_modules"],
            max_depth=3
        )

        repos, worktrees, skipped = await scan_directory(temp_workspace, config)

        # node_project should be found, but not node_modules/dep
        repo_paths = {r.path for r in repos}
        assert str(nm_path) in repo_paths
        assert str(nm_path / "node_modules" / "dep") not in repo_paths

    @pytest.mark.asyncio
    async def test_discover_respects_max_depth(self, temp_workspace: Path):
        """Discovery should respect max_depth configuration."""
        # Create nested directory structure
        deep_path = temp_workspace / "level1" / "level2" / "level3" / "deep-repo"
        deep_path.mkdir(parents=True)
        subprocess.run(["git", "init"], cwd=deep_path, capture_output=True)

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration
        )

        # max_depth=2 should not find deep-repo at level 4
        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=2
        )

        repos, worktrees, skipped = await scan_directory(temp_workspace, config)

        repo_names = {r.name for r in repos}
        assert "deep-repo" not in repo_names

        # max_depth=5 should find deep-repo
        config_deep = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=5
        )

        repos_deep, _, _ = await scan_directory(temp_workspace, config_deep)
        repo_names_deep = {r.name for r in repos_deep}
        assert "deep-repo" in repo_names_deep

    @pytest.mark.asyncio
    async def test_discover_extracts_git_metadata(self, temp_workspace: Path):
        """Discovered repos should have correct git metadata."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration
        )

        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=2
        )

        repos, _, _ = await scan_directory(temp_workspace, config)

        for repo in repos:
            assert repo.git_metadata is not None
            assert repo.git_metadata.current_branch in ["main", "master"]
            assert len(repo.git_metadata.commit_hash) == 7
            assert repo.git_metadata.is_clean is True  # We only created clean repos


class TestProjectCreationFromDiscovery:
    """Integration tests for creating projects from discovered repos."""

    @pytest.fixture
    def temp_workspace(self) -> Path:
        """Create a temporary workspace with a git repo."""
        workspace = Path(tempfile.mkdtemp())
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
        """Create a temporary config directory for test projects."""
        config_dir = Path(tempfile.mkdtemp())
        (config_dir / "projects").mkdir()
        yield config_dir
        shutil.rmtree(config_dir, ignore_errors=True)

    @pytest.mark.asyncio
    async def test_create_project_from_discovered_repo(
        self, temp_workspace: Path, temp_config_dir: Path
    ):
        """Should create i3pm project from discovered repository."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.services.project_service import (
            ProjectService
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration, SourceType
        )

        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=2
        )

        repos, _, _ = await scan_directory(temp_workspace, config)
        assert len(repos) == 1

        discovered = repos[0]
        project_service = ProjectService(temp_config_dir)

        # Create project from discovery
        project = await project_service.create_or_update_from_discovery(discovered)

        assert project.name == "my-project"
        assert project.directory == str(temp_workspace / "my-project")
        assert project.source_type == SourceType.LOCAL
        assert project.git_metadata is not None
        assert project.discovered_at is not None

    @pytest.mark.asyncio
    async def test_update_existing_project_on_rediscovery(
        self, temp_workspace: Path, temp_config_dir: Path
    ):
        """Rediscovering should update existing project, not create duplicate."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.services.project_service import (
            ProjectService
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration
        )

        config = ScanConfiguration(
            scan_paths=[str(temp_workspace)],
            exclude_patterns=[],
            max_depth=2
        )

        project_service = ProjectService(temp_config_dir)

        # First discovery
        repos1, _, _ = await scan_directory(temp_workspace, config)
        project1 = await project_service.create_or_update_from_discovery(repos1[0])
        original_created_at = project1.created_at

        # Make a change in the repo
        repo_path = temp_workspace / "my-project"
        (repo_path / "new-file.txt").write_text("new content")
        subprocess.run(["git", "add", "."], cwd=repo_path, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "Add new file"],
            cwd=repo_path,
            capture_output=True
        )

        # Second discovery
        repos2, _, _ = await scan_directory(temp_workspace, config)
        project2 = await project_service.create_or_update_from_discovery(repos2[0])

        # Should be same project (same created_at), but updated metadata
        assert project2.created_at == original_created_at
        assert project2.git_metadata.commit_hash != project1.git_metadata.commit_hash

        # Should only have one project file
        projects = project_service.list()
        assert len(projects) == 1
