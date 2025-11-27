"""
Integration tests for worktree discovery workflow.

Feature 097: Git-Based Project Discovery and Management
Task T030: Integration test for worktree discovery workflow

Tests the complete discovery workflow for git worktrees: finding worktrees,
extracting metadata, linking to parent repository, and creating projects.
"""

import pytest
from pathlib import Path
import tempfile
import shutil
import subprocess


class TestWorktreeDiscoveryWorkflow:
    """Integration tests for the complete worktree discovery workflow."""

    @pytest.fixture
    def temp_workspace(self) -> Path:
        """Create a temporary workspace with a main repo and worktrees."""
        workspace = Path(tempfile.mkdtemp())

        # Create main repository
        main_repo = workspace / "main-project"
        main_repo.mkdir()
        subprocess.run(["git", "init"], cwd=main_repo, capture_output=True)
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"],
            cwd=main_repo,
            capture_output=True
        )
        subprocess.run(
            ["git", "config", "user.name", "Test User"],
            cwd=main_repo,
            capture_output=True
        )
        # Create initial commit
        (main_repo / "README.md").write_text("# Main Project\n")
        subprocess.run(["git", "add", "."], cwd=main_repo, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "Initial commit"],
            cwd=main_repo,
            capture_output=True
        )

        # Create worktree
        worktree_path = workspace / "feature-branch"
        subprocess.run(
            ["git", "worktree", "add", str(worktree_path), "-b", "feature-branch"],
            cwd=main_repo,
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
    async def test_discover_finds_worktree(self, temp_workspace: Path):
        """Discovery should find and identify worktrees separately from repos."""
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

        # Should find 1 main repo and 1 worktree
        assert len(repos) == 1
        assert len(worktrees) == 1

        # Verify main repo
        assert repos[0].name == "main-project"
        assert repos[0].is_worktree is False

        # Verify worktree
        assert worktrees[0].name == "feature-branch"
        assert worktrees[0].is_worktree is True
        assert worktrees[0].parent_repo_path == str(temp_workspace / "main-project")

    @pytest.mark.asyncio
    async def test_worktree_has_correct_branch(self, temp_workspace: Path):
        """Discovered worktree should have correct branch in metadata."""
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

        assert len(worktrees) == 1
        worktree = worktrees[0]

        # Branch should be "feature-branch" (what we created)
        assert worktree.git_metadata is not None
        assert worktree.git_metadata.current_branch == "feature-branch"

    @pytest.mark.asyncio
    async def test_worktree_has_worktree_icon(self, temp_workspace: Path):
        """Discovered worktree should have the worktree-specific icon."""
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

        assert len(worktrees) == 1
        # Worktrees should have 🌿 icon
        assert worktrees[0].inferred_icon == "🌿"

    @pytest.mark.asyncio
    async def test_create_project_from_worktree(
        self, temp_workspace: Path, temp_config_dir: Path
    ):
        """Should create project with source_type=worktree from discovered worktree."""
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

        repos, worktrees, skipped = await scan_directory(temp_workspace, config)
        assert len(worktrees) == 1

        project_service = ProjectService(temp_config_dir)
        discovered_wt = worktrees[0]

        # Create project from worktree discovery
        project = await project_service.create_or_update_from_discovery(discovered_wt)

        assert project.name == "feature-branch"
        assert project.source_type == SourceType.WORKTREE
        assert project.git_metadata is not None
        assert project.icon == "🌿"

    @pytest.mark.asyncio
    async def test_multiple_worktrees_discovered(self, temp_workspace: Path):
        """Discovery should find multiple worktrees from same parent."""
        # Create second worktree
        main_repo = temp_workspace / "main-project"
        worktree2_path = temp_workspace / "hotfix-branch"
        subprocess.run(
            ["git", "worktree", "add", str(worktree2_path), "-b", "hotfix-branch"],
            cwd=main_repo,
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
            exclude_patterns=[],
            max_depth=2
        )

        repos, worktrees, skipped = await scan_directory(temp_workspace, config)

        # Should find 1 main repo and 2 worktrees
        assert len(repos) == 1
        assert len(worktrees) == 2

        worktree_names = {wt.name for wt in worktrees}
        assert worktree_names == {"feature-branch", "hotfix-branch"}

        # All worktrees should point to same parent
        parent_paths = {wt.parent_repo_path for wt in worktrees}
        assert len(parent_paths) == 1
        assert str(main_repo) in parent_paths


class TestNestedWorktreeDiscovery:
    """Test discovery of worktrees in nested directory structures."""

    @pytest.fixture
    def nested_workspace(self) -> Path:
        """Create workspace with nested worktrees."""
        workspace = Path(tempfile.mkdtemp())

        # Create projects/main-repo
        projects_dir = workspace / "projects"
        projects_dir.mkdir()

        main_repo = projects_dir / "main-repo"
        main_repo.mkdir()
        subprocess.run(["git", "init"], cwd=main_repo, capture_output=True)
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"],
            cwd=main_repo,
            capture_output=True
        )
        subprocess.run(
            ["git", "config", "user.name", "Test User"],
            cwd=main_repo,
            capture_output=True
        )
        (main_repo / "README.md").write_text("# Main\n")
        subprocess.run(["git", "add", "."], cwd=main_repo, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "init"],
            cwd=main_repo,
            capture_output=True
        )

        # Create worktrees/feature in same level
        worktrees_dir = projects_dir / "worktrees"
        worktrees_dir.mkdir()

        worktree_path = worktrees_dir / "feature"
        subprocess.run(
            ["git", "worktree", "add", str(worktree_path), "-b", "feature"],
            cwd=main_repo,
            capture_output=True
        )

        yield workspace
        shutil.rmtree(workspace, ignore_errors=True)

    @pytest.mark.asyncio
    async def test_discover_nested_worktree(self, nested_workspace: Path):
        """Should find worktrees in nested directory structures."""
        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            scan_directory
        )
        from home_modules.desktop.i3_project_event_daemon.models.discovery import (
            ScanConfiguration
        )

        config = ScanConfiguration(
            scan_paths=[str(nested_workspace)],
            exclude_patterns=[],
            max_depth=4
        )

        repos, worktrees, skipped = await scan_directory(nested_workspace, config)

        # Should find main repo and worktree despite nesting
        assert len(repos) == 1
        assert len(worktrees) == 1

        assert repos[0].name == "main-repo"
        assert worktrees[0].name == "feature"
