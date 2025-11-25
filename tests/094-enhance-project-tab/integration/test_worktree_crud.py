"""
Integration Test for Worktree CRUD Workflow

Feature 094: Enhanced Projects & Applications CRUD Interface (User Story 5 - T054)
Tests the complete worktree CRUD workflow: create → edit → delete with Git integration
"""

import pytest
import json
import tempfile
import shutil
import subprocess
from pathlib import Path
from unittest.mock import patch, AsyncMock

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools/monitoring-panel"))

from i3_project_manager.services.project_editor import ProjectEditor
from i3_project_manager.models.project_config import ProjectConfig, WorktreeConfig
from cli_executor import CLIExecutor


@pytest.fixture
def temp_dir():
    """Create temporary directory"""
    temp = Path(tempfile.mkdtemp(prefix="test_worktree_crud_"))
    yield temp
    shutil.rmtree(temp, ignore_errors=True)


@pytest.fixture
def git_repo(temp_dir):
    """Create a temporary Git repository for testing"""
    repo_dir = temp_dir / "repo"
    repo_dir.mkdir()

    # Environment for git commands (disable GPG signing, set identity)
    git_env = {
        **subprocess.os.environ,
        "GIT_AUTHOR_NAME": "Test User",
        "GIT_AUTHOR_EMAIL": "test@test.com",
        "GIT_COMMITTER_NAME": "Test User",
        "GIT_COMMITTER_EMAIL": "test@test.com",
        "GIT_CONFIG_NOSYSTEM": "1",
        "HOME": str(temp_dir),  # Avoid reading user's .gitconfig
    }

    # Initialize git repo
    subprocess.run(["git", "init"], cwd=repo_dir, check=True, capture_output=True, env=git_env)
    subprocess.run(
        ["git", "config", "user.email", "test@test.com"],
        cwd=repo_dir, check=True, capture_output=True, env=git_env
    )
    subprocess.run(
        ["git", "config", "user.name", "Test User"],
        cwd=repo_dir, check=True, capture_output=True, env=git_env
    )
    subprocess.run(
        ["git", "config", "commit.gpgsign", "false"],
        cwd=repo_dir, check=True, capture_output=True, env=git_env
    )

    # Create initial commit
    (repo_dir / "README.md").write_text("# Test Repo")
    subprocess.run(["git", "add", "."], cwd=repo_dir, check=True, capture_output=True, env=git_env)
    subprocess.run(
        ["git", "commit", "-m", "Initial commit"],
        cwd=repo_dir, check=True, capture_output=True, env=git_env
    )

    # Create a feature branch
    subprocess.run(
        ["git", "branch", "feature-123"],
        cwd=repo_dir, check=True, capture_output=True, env=git_env
    )

    return repo_dir


@pytest.fixture
def projects_dir(temp_dir):
    """Create projects directory for testing"""
    projects = temp_dir / "projects"
    projects.mkdir()
    return projects


@pytest.fixture
def editor(projects_dir):
    """Create ProjectEditor with temporary directory"""
    return ProjectEditor(projects_dir=projects_dir)


@pytest.fixture
def parent_project(editor, git_repo, projects_dir):
    """Create a parent project for worktree tests"""
    # Patch Path.home() to use temp projects_dir
    original_home = Path.home
    Path.home = lambda: projects_dir.parent

    # Create parent config directory
    (projects_dir.parent / ".config" / "i3" / "projects").mkdir(parents=True, exist_ok=True)

    config = ProjectConfig(
        name="parent-project",
        display_name="Parent Project",
        icon="📦",
        working_dir=str(git_repo),
        scope="scoped"
    )
    result = editor.create_project(config)

    # Also create in the expected location for validation
    parent_json = projects_dir.parent / ".config" / "i3" / "projects" / "parent-project.json"
    parent_json.write_text(json.dumps({
        "name": "parent-project",
        "display_name": "Parent Project",
        "icon": "📦",
        "directory": str(git_repo),
        "scope": "scoped"
    }))

    yield {
        "editor": editor,
        "project": config,
        "repo": git_repo,
        "path": result["path"]
    }

    # Restore
    Path.home = original_home


class TestWorktreeCreateWorkflow:
    """Test worktree creation workflow"""

    def test_create_worktree_config_file(self, parent_project, temp_dir, projects_dir):
        """Test creating worktree configuration JSON file"""
        editor = parent_project["editor"]
        repo = parent_project["repo"]

        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            worktree_path = temp_dir / "worktree-path"

            config = WorktreeConfig(
                name="feature-worktree",
                display_name="Feature Worktree",
                icon="🌿",
                working_dir=str(repo),  # Use repo as working dir (it exists)
                scope="scoped",
                worktree_path=str(worktree_path),
                branch_name="feature-123",
                parent_project="parent-project"
            )

            result = editor.create_project(config)

            assert result["status"] == "success"

            # Verify file contents
            project_file = Path(result["path"])
            with open(project_file, 'r') as f:
                data = json.load(f)

            assert data["name"] == "feature-worktree"
            assert data["parent_project"] == "parent-project"
            assert data["branch_name"] == "feature-123"
            assert "worktree_path" in data
        finally:
            Path.home = original_home

    def test_create_worktree_validates_parent_exists(self, temp_dir, editor, projects_dir):
        """Test that worktree creation validates parent project exists"""
        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            with pytest.raises(ValueError) as exc_info:
                WorktreeConfig(
                    name="orphan-worktree",
                    display_name="Orphan Worktree",
                    icon="🌿",
                    working_dir=str(temp_dir),
                    scope="scoped",
                    worktree_path=str(temp_dir / "wt"),
                    branch_name="main",
                    parent_project="nonexistent-parent"
                )

            assert "does not exist" in str(exc_info.value)
        finally:
            Path.home = original_home

    def test_create_worktree_validates_path_not_exists(self, parent_project, temp_dir, projects_dir):
        """Test that worktree path must not already exist"""
        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            # Create directory that conflicts
            existing_path = temp_dir / "existing-wt"
            existing_path.mkdir()

            with pytest.raises(ValueError) as exc_info:
                WorktreeConfig(
                    name="conflict-worktree",
                    display_name="Conflict Worktree",
                    icon="🌿",
                    working_dir=str(parent_project["repo"]),
                    scope="scoped",
                    worktree_path=str(existing_path),
                    branch_name="feature-123",
                    parent_project="parent-project"
                )

            assert "already exists" in str(exc_info.value)
        finally:
            Path.home = original_home


class TestWorktreeEditWorkflow:
    """Test worktree edit workflow"""

    def test_edit_worktree_display_name(self, parent_project, temp_dir, projects_dir):
        """Test editing worktree display name"""
        editor = parent_project["editor"]
        repo = parent_project["repo"]

        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            # First create the worktree
            worktree_path = temp_dir / "editable-wt"

            config = WorktreeConfig(
                name="editable-worktree",
                display_name="Editable Worktree",
                icon="🌿",
                working_dir=str(repo),
                scope="scoped",
                worktree_path=str(worktree_path),
                branch_name="feature-123",
                parent_project="parent-project"
            )
            editor.create_project(config)

            # Now edit the display name
            updates = {"display_name": "Updated Worktree Name"}
            result = editor.edit_project("editable-worktree", updates)

            assert result["status"] == "success"

            # Verify the change
            project_data = editor.read_project("editable-worktree")
            assert project_data["display_name"] == "Updated Worktree Name"
            assert project_data["branch_name"] == "feature-123"  # Unchanged
            assert project_data["parent_project"] == "parent-project"  # Unchanged
        finally:
            Path.home = original_home

    def test_edit_worktree_icon(self, parent_project, temp_dir, projects_dir):
        """Test editing worktree icon"""
        editor = parent_project["editor"]
        repo = parent_project["repo"]

        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            worktree_path = temp_dir / "icon-wt"

            config = WorktreeConfig(
                name="icon-worktree",
                display_name="Icon Worktree",
                icon="🌿",
                working_dir=str(repo),
                scope="scoped",
                worktree_path=str(worktree_path),
                branch_name="feature-123",
                parent_project="parent-project"
            )
            editor.create_project(config)

            # Edit icon
            updates = {"icon": "🔧"}
            result = editor.edit_project("icon-worktree", updates)

            assert result["status"] == "success"

            project_data = editor.read_project("icon-worktree")
            assert project_data["icon"] == "🔧"
        finally:
            Path.home = original_home


class TestWorktreeDeleteWorkflow:
    """Test worktree deletion workflow"""

    def test_delete_worktree_config(self, parent_project, temp_dir, projects_dir):
        """Test deleting worktree configuration file"""
        editor = parent_project["editor"]
        repo = parent_project["repo"]

        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            worktree_path = temp_dir / "deletable-wt"

            config = WorktreeConfig(
                name="deletable-worktree",
                display_name="Deletable Worktree",
                icon="🌿",
                working_dir=str(repo),
                scope="scoped",
                worktree_path=str(worktree_path),
                branch_name="feature-123",
                parent_project="parent-project"
            )
            editor.create_project(config)

            # Verify exists
            assert editor.read_project("deletable-worktree") is not None

            # Delete
            result = editor.delete_project("deletable-worktree")

            assert result["status"] == "success"

            # Verify deleted
            with pytest.raises(FileNotFoundError):
                editor.read_project("deletable-worktree")
        finally:
            Path.home = original_home


class TestWorktreeListWorkflow:
    """Test worktree listing and hierarchy"""

    def test_list_projects_separates_worktrees(self, parent_project, temp_dir, projects_dir):
        """Test that list_projects correctly separates main projects and worktrees"""
        editor = parent_project["editor"]
        repo = parent_project["repo"]

        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            # Create a worktree
            worktree_path = temp_dir / "list-wt"

            config = WorktreeConfig(
                name="list-worktree",
                display_name="List Worktree",
                icon="🌿",
                working_dir=str(repo),
                scope="scoped",
                worktree_path=str(worktree_path),
                branch_name="feature-123",
                parent_project="parent-project"
            )
            editor.create_project(config)

            # List all projects
            result = editor.list_projects()

            # Should have main projects and worktrees separated
            assert "main_projects" in result
            assert "worktrees" in result

            # Parent project should be in main_projects
            main_names = [p["name"] for p in result["main_projects"]]
            assert "parent-project" in main_names

            # Worktree should be in worktrees
            wt_names = [w["name"] for w in result["worktrees"]]
            assert "list-worktree" in wt_names
        finally:
            Path.home = original_home

    def test_worktrees_grouped_by_parent(self, parent_project, temp_dir, projects_dir):
        """Test that worktrees are associated with correct parent"""
        editor = parent_project["editor"]
        repo = parent_project["repo"]

        # Patch Path.home for validation
        original_home = Path.home
        Path.home = lambda: projects_dir.parent

        try:
            # Create multiple worktrees
            for i in range(3):
                worktree_path = temp_dir / f"grouped-wt-{i}"

                config = WorktreeConfig(
                    name=f"grouped-worktree-{i}",
                    display_name=f"Grouped Worktree {i}",
                    icon="🌿",
                    working_dir=str(repo),
                    scope="scoped",
                    worktree_path=str(worktree_path),
                    branch_name="feature-123",
                    parent_project="parent-project"
                )
                editor.create_project(config)

            result = editor.list_projects()

            # All worktrees should have parent-project as parent
            for wt in result["worktrees"]:
                if wt["name"].startswith("grouped-worktree"):
                    assert wt["parent_project"] == "parent-project"
        finally:
            Path.home = original_home


class TestCLIExecutorWorktreeIntegration:
    """Test CLI executor integration for worktree Git operations"""

    @pytest.fixture
    def executor(self):
        """Create CLI executor instance"""
        return CLIExecutor(timeout=30)

    @pytest.mark.asyncio
    async def test_git_worktree_list(self, executor, git_repo):
        """Test git worktree list command execution"""
        result = await executor.execute_git_command(
            ["worktree", "list"],
            cwd=git_repo
        )

        # Should succeed (even if no worktrees yet)
        assert result.success is True
        assert str(git_repo) in result.stdout

    @pytest.mark.asyncio
    async def test_git_worktree_add(self, executor, git_repo, temp_dir):
        """Test git worktree add command execution"""
        worktree_path = temp_dir / "git-wt-test"

        result = await executor.execute_git_command(
            ["worktree", "add", str(worktree_path), "feature-123"],
            cwd=git_repo
        )

        assert result.success is True
        assert worktree_path.exists()

    @pytest.mark.asyncio
    async def test_git_worktree_remove(self, executor, git_repo, temp_dir):
        """Test git worktree remove command execution"""
        worktree_path = temp_dir / "git-wt-remove"

        # First add worktree
        await executor.execute_git_command(
            ["worktree", "add", str(worktree_path), "feature-123"],
            cwd=git_repo
        )

        assert worktree_path.exists()

        # Now remove it
        result = await executor.execute_git_command(
            ["worktree", "remove", str(worktree_path)],
            cwd=git_repo
        )

        assert result.success is True
        # Note: Directory may still exist but worktree is removed from Git

    @pytest.mark.asyncio
    async def test_git_worktree_add_nonexistent_branch(self, executor, git_repo, temp_dir):
        """Test git worktree add with non-existent branch"""
        worktree_path = temp_dir / "git-wt-noref"

        result = await executor.execute_git_command(
            ["worktree", "add", str(worktree_path), "nonexistent-branch-xyz"],
            cwd=git_repo
        )

        assert result.success is False
        # Error category can be "git" or "validation" depending on error message parsing
        assert result.error_category in ["git", "validation"]
        # The stderr should contain indication of the branch issue
        assert "nonexistent" in result.stderr.lower() or "invalid" in result.stderr.lower() or "not" in result.stderr.lower()
