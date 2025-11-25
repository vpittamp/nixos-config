"""
Unit Tests for Project Configuration Models

Feature 094: Enhanced Projects & Applications CRUD Interface
Tests for ProjectConfig, WorktreeConfig, and RemoteConfig Pydantic models
"""

import pytest
from pathlib import Path
from pydantic import ValidationError

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))

from i3_project_manager.models.project_config import (
    ProjectConfig,
    WorktreeConfig,
    RemoteConfig
)


class TestProjectConfig:
    """Test ProjectConfig model validation"""

    def test_valid_minimal_project(self):
        """Test minimal valid project configuration"""
        config = ProjectConfig(
            name="test-project",
            display_name="Test Project",
            icon="🚀",
            working_dir="/tmp/test",
            scope="scoped"
        )
        assert config.name == "test-project"
        assert config.display_name == "Test Project"
        assert config.scope == "scoped"

    def test_project_name_format_validation(self):
        """Test project name must be lowercase with hyphens/dots only"""
        # Valid names
        valid_names = ["test", "test-project", "my.project", "test-123"]
        for name in valid_names:
            config = ProjectConfig(
                name=name,
                display_name="Test",
                icon="🚀",
                working_dir="/tmp",
                scope="scoped"
            )
            assert config.name == name

        # Invalid names
        invalid_names = [
            "Test-Project",  # uppercase
            "test project",  # space
            "test_project",  # underscore
            "test/project",  # slash
        ]
        for name in invalid_names:
            with pytest.raises(ValidationError) as exc_info:
                ProjectConfig(
                    name=name,
                    display_name="Test",
                    icon="🚀",
                    working_dir="/tmp",
                    scope="scoped"
                )
            assert "lowercase" in str(exc_info.value).lower()

    def test_working_dir_validation(self):
        """Test working directory must exist"""
        # Valid: /tmp should exist on all systems
        config = ProjectConfig(
            name="test",
            display_name="Test",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        assert config.working_dir == "/tmp"

        # Note: Pydantic model doesn't check existence - that's FormValidator's job
        # Model only validates the field is a string

    def test_scope_validation(self):
        """Test scope must be 'scoped' or 'global'"""
        # Valid scopes
        for scope in ["scoped", "global"]:
            config = ProjectConfig(
                name="test",
                display_name="Test",
                icon="🚀",
                working_dir="/tmp",
                scope=scope
            )
            assert config.scope == scope

        # Invalid scope
        with pytest.raises(ValidationError):
            ProjectConfig(
                name="test",
                display_name="Test",
                icon="🚀",
                working_dir="/tmp",
                scope="invalid"
            )

    def test_optional_remote_config(self):
        """Test remote configuration is optional"""
        # Without remote
        config = ProjectConfig(
            name="test",
            display_name="Test",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        assert config.remote is None

        # With remote
        config_with_remote = ProjectConfig(
            name="test",
            display_name="Test",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped",
            remote=RemoteConfig(
                enabled=True,
                host="example.com",
                user="user",
                remote_dir="/home/user/project"
            )
        )
        assert config_with_remote.remote is not None
        assert config_with_remote.remote.enabled is True


class TestRemoteConfig:
    """Test RemoteConfig model validation"""

    def test_valid_remote_config(self):
        """Test valid remote configuration"""
        config = RemoteConfig(
            enabled=True,
            host="example.com",
            user="user",
            remote_dir="/home/user/project"
        )
        assert config.enabled is True
        assert config.host == "example.com"
        assert config.user == "user"
        assert config.remote_dir == "/home/user/project"
        assert config.port == 22  # default

    def test_custom_port(self):
        """Test custom SSH port"""
        config = RemoteConfig(
            enabled=True,
            host="example.com",
            user="user",
            remote_dir="/home/user/project",
            port=2222
        )
        assert config.port == 2222

    def test_port_range_validation(self):
        """Test port must be in valid range (1-65535)"""
        # Valid ports
        for port in [1, 22, 2222, 65535]:
            config = RemoteConfig(
                enabled=True,
                host="example.com",
                user="user",
                remote_dir="/home/user/project",
                port=port
            )
            assert config.port == port

        # Invalid ports
        for port in [0, -1, 65536, 100000]:
            with pytest.raises(ValidationError):
                RemoteConfig(
                    enabled=True,
                    host="example.com",
                    user="user",
                    remote_dir="/home/user/project",
                    port=port
                )

    def test_remote_dir_must_be_absolute(self):
        """Test remote directory must be absolute path"""
        # Valid absolute path
        config = RemoteConfig(
            enabled=True,
            host="example.com",
            user="user",
            remote_dir="/home/user/project"
        )
        assert config.remote_dir == "/home/user/project"

        # Invalid relative path
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="example.com",
                user="user",
                remote_dir="relative/path"
            )
        assert "absolute" in str(exc_info.value).lower()


class TestWorktreeConfig:
    """Test WorktreeConfig model validation"""

    @pytest.fixture
    def parent_project_fixture(self, tmp_path):
        """Create parent project directory and JSON file for worktree tests"""
        # Create projects config directory
        projects_dir = tmp_path / ".config" / "i3" / "projects"
        projects_dir.mkdir(parents=True, exist_ok=True)

        # Create parent project JSON file
        parent_file = projects_dir / "parent-project.json"
        parent_file.write_text('{"name": "parent-project", "display_name": "Parent Project", "icon": "📦", "directory": "/tmp", "scope": "scoped"}')

        # Create working directory
        working_dir = tmp_path / "test-working-dir"
        working_dir.mkdir(parents=True, exist_ok=True)

        # Monkey-patch Path.home() to return tmp_path for testing
        original_home = Path.home
        Path.home = lambda: tmp_path

        yield {
            "projects_dir": projects_dir,
            "parent_file": parent_file,
            "working_dir": working_dir,
            "tmp_path": tmp_path
        }

        # Restore original
        Path.home = original_home

    def test_valid_worktree_config(self, parent_project_fixture):
        """Test valid worktree configuration"""
        wt = parent_project_fixture
        worktree_path = wt["tmp_path"] / "test-worktree"  # Non-existent path (required)

        config = WorktreeConfig(
            name="test-worktree",
            display_name="Test Worktree",
            icon="🌳",
            working_dir=str(wt["working_dir"]),
            scope="scoped",
            worktree_path=str(worktree_path),
            branch_name="feature-123",
            parent_project="parent-project"
        )
        assert config.name == "test-worktree"
        assert config.worktree_path == str(worktree_path)
        assert config.branch_name == "feature-123"
        assert config.parent_project == "parent-project"

    def test_branch_name_validation(self, parent_project_fixture):
        """Test branch name validation"""
        wt = parent_project_fixture

        # Valid branch names
        valid_branches = [
            "main",
            "feature-123",
            "feat/new-feature",
            "bugfix/issue-456",
            "release/v1.0.0"
        ]
        for i, branch in enumerate(valid_branches):
            # Use unique worktree paths for each test
            worktree_path = wt["tmp_path"] / f"wt-{i}"

            config = WorktreeConfig(
                name="test",
                display_name="Test",
                icon="🌳",
                working_dir=str(wt["working_dir"]),
                scope="scoped",
                worktree_path=str(worktree_path),
                branch_name=branch,
                parent_project="parent-project"
            )
            assert config.branch_name == branch

        # Invalid branch names (containing invalid Git ref characters)
        # Note: Full validation happens in FormValidator, model does basic checks
        invalid_branches = [
            "",  # empty
        ]
        for branch in invalid_branches:
            with pytest.raises(ValidationError):
                WorktreeConfig(
                    name="test",
                    display_name="Test",
                    icon="🌳",
                    working_dir=str(wt["working_dir"]),
                    scope="scoped",
                    worktree_path=str(wt["tmp_path"] / "wt-invalid"),
                    branch_name=branch,
                    parent_project="parent-project"
                )

    def test_parent_project_required(self, parent_project_fixture):
        """Test parent_project field is required for worktrees"""
        wt = parent_project_fixture

        with pytest.raises(ValidationError):
            WorktreeConfig(
                name="test",
                display_name="Test",
                icon="🌳",
                working_dir=str(wt["working_dir"]),
                scope="scoped",
                worktree_path=str(wt["tmp_path"] / "wt-missing-parent"),
                branch_name="feature"
                # parent_project missing
            )

    def test_parent_project_must_exist(self, parent_project_fixture):
        """Test parent_project must reference an existing project"""
        wt = parent_project_fixture

        with pytest.raises(ValidationError) as exc_info:
            WorktreeConfig(
                name="test",
                display_name="Test",
                icon="🌳",
                working_dir=str(wt["working_dir"]),
                scope="scoped",
                worktree_path=str(wt["tmp_path"] / "wt-nonexistent-parent"),
                branch_name="feature",
                parent_project="nonexistent-parent"
            )
        assert "does not exist" in str(exc_info.value)

    def test_worktree_path_must_not_exist(self, parent_project_fixture):
        """Test worktree_path must not already exist"""
        wt = parent_project_fixture

        # Create a directory at the worktree path
        existing_path = wt["tmp_path"] / "existing-wt"
        existing_path.mkdir()

        with pytest.raises(ValidationError) as exc_info:
            WorktreeConfig(
                name="test",
                display_name="Test",
                icon="🌳",
                working_dir=str(wt["working_dir"]),
                scope="scoped",
                worktree_path=str(existing_path),
                branch_name="feature",
                parent_project="parent-project"
            )
        assert "already exists" in str(exc_info.value)

    def test_worktree_inherits_project_config(self, parent_project_fixture):
        """Test WorktreeConfig inherits all ProjectConfig fields"""
        wt = parent_project_fixture

        config = WorktreeConfig(
            name="test-wt",
            display_name="Test Worktree",
            icon="🌳",
            working_dir=str(wt["working_dir"]),
            scope="scoped",
            worktree_path=str(wt["tmp_path"] / "wt-inherit"),
            branch_name="feature",
            parent_project="parent-project"
        )
        # Should have both ProjectConfig and WorktreeConfig fields
        assert hasattr(config, "name")
        assert hasattr(config, "display_name")
        assert hasattr(config, "working_dir")
        assert hasattr(config, "worktree_path")
        assert hasattr(config, "branch_name")
        assert hasattr(config, "parent_project")


class TestModelSerialization:
    """Test model serialization to/from JSON"""

    def test_project_to_dict(self):
        """Test ProjectConfig serialization to dict"""
        config = ProjectConfig(
            name="test",
            display_name="Test Project",
            icon="🚀",
            working_dir="/tmp/test",
            scope="scoped"
        )
        data = config.model_dump()
        assert data["name"] == "test"
        assert data["display_name"] == "Test Project"
        assert data["icon"] == "🚀"
        assert data["working_dir"] == "/tmp/test"
        assert data["scope"] == "scoped"

    def test_project_from_dict(self):
        """Test ProjectConfig deserialization from dict"""
        data = {
            "name": "test",
            "display_name": "Test Project",
            "icon": "🚀",
            "working_dir": "/tmp/test",
            "scope": "scoped"
        }
        config = ProjectConfig(**data)
        assert config.name == "test"
        assert config.display_name == "Test Project"

    def test_worktree_to_dict(self):
        """Test WorktreeConfig serialization includes all fields"""
        config = WorktreeConfig(
            name="test-wt",
            display_name="Test Worktree",
            icon="🌳",
            working_dir="/tmp/test",
            scope="scoped",
            worktree_path="/tmp/wt",
            branch_name="feature",
            parent_project="parent"
        )
        data = config.model_dump()
        assert data["name"] == "test-wt"
        assert data["worktree_path"] == "/tmp/wt"
        assert data["branch_name"] == "feature"
        assert data["parent_project"] == "parent"

    def test_remote_config_to_dict(self):
        """Test RemoteConfig serialization"""
        config = RemoteConfig(
            enabled=True,
            host="example.com",
            user="user",
            remote_dir="/home/user/project",
            port=2222
        )
        data = config.model_dump()
        assert data["enabled"] is True
        assert data["host"] == "example.com"
        assert data["port"] == 2222
