"""
Unit Tests for Project Editor Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Tests for ProjectEditor CRUD operations on ~/.config/i3/projects/*.json
"""

import pytest
import json
import tempfile
import shutil
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))

from i3_project_manager.services.project_editor import ProjectEditor
from i3_project_manager.models.project_config import ProjectConfig, WorktreeConfig


@pytest.fixture
def temp_projects_dir():
    """Create temporary projects directory for testing"""
    temp_dir = Path(tempfile.mkdtemp(prefix="test_projects_"))
    yield temp_dir
    # Cleanup
    shutil.rmtree(temp_dir, ignore_errors=True)


@pytest.fixture
def editor(temp_projects_dir):
    """Create ProjectEditor instance with temporary directory"""
    return ProjectEditor(projects_dir=temp_projects_dir)


class TestProjectCreation:
    """Test create_project() method"""

    def test_create_minimal_project(self, editor, temp_projects_dir):
        """Test creating a minimal project"""
        config = ProjectConfig(
            name="test-project",
            display_name="Test Project",
            icon="🚀",
            working_dir="/tmp/test",
            scope="scoped"
        )
        result = editor.create_project(config)

        # Check result
        assert result["status"] == "success"
        assert result["project_name"] == "test-project"
        assert "path" in result

        # Check file was created
        project_file = temp_projects_dir / "test-project.json"
        assert project_file.exists()

        # Check file contents
        with open(project_file, 'r') as f:
            data = json.load(f)
        assert data["name"] == "test-project"
        assert data["display_name"] == "Test Project"
        assert data["icon"] == "🚀"

    def test_create_project_with_remote_config(self, editor, temp_projects_dir):
        """Test creating a project with remote SSH configuration"""
        config = ProjectConfig(
            name="remote-project",
            display_name="Remote Project",
            icon="🌐",
            working_dir="/tmp/test",
            scope="scoped",
            remote={
                "enabled": True,
                "host": "example.com",
                "user": "user",
                "remote_dir": "/home/user/project",
                "port": 2222
            }
        )
        result = editor.create_project(config)

        assert result["status"] == "success"

        # Check remote config was saved
        project_file = temp_projects_dir / "remote-project.json"
        with open(project_file, 'r') as f:
            data = json.load(f)
        assert "remote" in data
        assert data["remote"]["enabled"] is True
        assert data["remote"]["host"] == "example.com"
        assert data["remote"]["port"] == 2222

    def test_create_project_already_exists(self, editor, temp_projects_dir):
        """Test creating a project that already exists raises error"""
        config = ProjectConfig(
            name="duplicate",
            display_name="Duplicate",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )

        # Create first time - should succeed
        result1 = editor.create_project(config)
        assert result1["status"] == "success"

        # Create second time - should fail
        with pytest.raises(ValueError) as exc_info:
            editor.create_project(config)
        assert "already exists" in str(exc_info.value)


class TestProjectReading:
    """Test read_project() and list_projects() methods"""

    def test_read_existing_project(self, editor, temp_projects_dir):
        """Test reading an existing project"""
        # Create a project first
        config = ProjectConfig(
            name="read-test",
            display_name="Read Test",
            icon="📖",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(config)

        # Read it back
        data = editor.read_project("read-test")
        assert data["name"] == "read-test"
        assert data["display_name"] == "Read Test"
        assert data["icon"] == "📖"

    def test_read_nonexistent_project(self, editor):
        """Test reading a project that doesn't exist raises error"""
        with pytest.raises(FileNotFoundError) as exc_info:
            editor.read_project("nonexistent")
        assert "not found" in str(exc_info.value)

    def test_list_empty_projects(self, editor):
        """Test listing projects when directory is empty"""
        result = editor.list_projects()
        assert result["main_projects"] == []
        assert result["worktrees"] == []

    def test_list_main_projects(self, editor):
        """Test listing main projects"""
        # Create some projects
        for i in range(3):
            config = ProjectConfig(
                name=f"project-{i}",
                display_name=f"Project {i}",
                icon="🚀",
                working_dir="/tmp",
                scope="scoped"
            )
            editor.create_project(config)

        # List them
        result = editor.list_projects()
        assert len(result["main_projects"]) == 3
        assert len(result["worktrees"]) == 0

        # Check sorting by name
        names = [p["name"] for p in result["main_projects"]]
        assert names == sorted(names)

    def test_list_separates_worktrees(self, editor, temp_projects_dir):
        """Test list_projects() separates main projects from worktrees"""
        # Create main project
        main_config = ProjectConfig(
            name="main",
            display_name="Main",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(main_config)

        # Create worktree (manually write JSON with parent_project field)
        worktree_data = {
            "name": "worktree",
            "display_name": "Worktree",
            "icon": "🌳",
            "working_dir": "/tmp/wt",
            "scope": "scoped",
            "parent_project": "main",
            "worktree_path": "/tmp/wt",
            "branch_name": "feature"
        }
        worktree_file = temp_projects_dir / "worktree.json"
        with open(worktree_file, 'w') as f:
            json.dump(worktree_data, f)

        # List projects
        result = editor.list_projects()
        assert len(result["main_projects"]) == 1
        assert len(result["worktrees"]) == 1
        assert result["main_projects"][0]["name"] == "main"
        assert result["worktrees"][0]["name"] == "worktree"


class TestProjectEditing:
    """Test edit_project() method"""

    def test_edit_project_display_name(self, editor, temp_projects_dir):
        """Test editing project display name"""
        # Create project
        config = ProjectConfig(
            name="edit-test",
            display_name="Original Name",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(config)

        # Edit display name
        result = editor.edit_project("edit-test", {"display_name": "New Name"})
        assert result["status"] == "success"

        # Verify change
        data = editor.read_project("edit-test")
        assert data["display_name"] == "New Name"
        assert data["name"] == "edit-test"  # name unchanged

    def test_edit_project_icon(self, editor):
        """Test editing project icon"""
        config = ProjectConfig(
            name="icon-test",
            display_name="Icon Test",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(config)

        # Edit icon
        editor.edit_project("icon-test", {"icon": "🎯"})

        # Verify
        data = editor.read_project("icon-test")
        assert data["icon"] == "🎯"

    def test_edit_project_multiple_fields(self, editor):
        """Test editing multiple fields at once"""
        config = ProjectConfig(
            name="multi-edit",
            display_name="Original",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(config)

        # Edit multiple fields
        updates = {
            "display_name": "Updated Name",
            "icon": "🎯",
            "scope": "global"
        }
        editor.edit_project("multi-edit", updates)

        # Verify all changes
        data = editor.read_project("multi-edit")
        assert data["display_name"] == "Updated Name"
        assert data["icon"] == "🎯"
        assert data["scope"] == "global"

    def test_edit_nonexistent_project(self, editor):
        """Test editing a project that doesn't exist raises error"""
        with pytest.raises(FileNotFoundError):
            editor.edit_project("nonexistent", {"display_name": "New"})

    def test_edit_creates_backup(self, editor, temp_projects_dir):
        """Test edit operation creates backup file"""
        config = ProjectConfig(
            name="backup-test",
            display_name="Original",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(config)

        # Edit project
        editor.edit_project("backup-test", {"display_name": "Updated"})

        # Check backup file exists
        backup_file = temp_projects_dir / "backup-test.json.bak"
        assert backup_file.exists()

        # Backup should have original content
        with open(backup_file, 'r') as f:
            backup_data = json.load(f)
        assert backup_data["display_name"] == "Original"


class TestProjectDeletion:
    """Test delete_project() method"""

    def test_delete_project(self, editor, temp_projects_dir):
        """Test deleting a project"""
        config = ProjectConfig(
            name="delete-test",
            display_name="Delete Test",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(config)

        # Delete it
        result = editor.delete_project("delete-test")
        assert result["status"] == "success"

        # Verify file is gone
        project_file = temp_projects_dir / "delete-test.json"
        assert not project_file.exists()

        # Verify backup was created
        backup_file = temp_projects_dir / "delete-test.json.deleted"
        assert backup_file.exists()

    def test_delete_nonexistent_project(self, editor):
        """Test deleting a project that doesn't exist raises error"""
        with pytest.raises(FileNotFoundError):
            editor.delete_project("nonexistent")

    def test_delete_project_with_worktrees_blocked(self, editor, temp_projects_dir):
        """Test deleting a project with active worktrees is blocked"""
        # Create main project
        main_config = ProjectConfig(
            name="main-with-wt",
            display_name="Main",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(main_config)

        # Create worktree
        worktree_data = {
            "name": "child-wt",
            "display_name": "Child Worktree",
            "icon": "🌳",
            "working_dir": "/tmp/wt",
            "scope": "scoped",
            "parent_project": "main-with-wt",
            "worktree_path": "/tmp/wt",
            "branch_name": "feature"
        }
        worktree_file = temp_projects_dir / "child-wt.json"
        with open(worktree_file, 'w') as f:
            json.dump(worktree_data, f)

        # Try to delete main project - should fail
        with pytest.raises(ValueError) as exc_info:
            editor.delete_project("main-with-wt")
        assert "active worktrees" in str(exc_info.value)
        assert "child-wt" in str(exc_info.value)

    def test_delete_project_with_worktrees_force(self, editor, temp_projects_dir):
        """Test force deleting a project with worktrees"""
        # Create main project and worktree
        main_config = ProjectConfig(
            name="main-force",
            display_name="Main",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(main_config)

        worktree_data = {
            "name": "child",
            "parent_project": "main-force",
            "display_name": "Child",
            "icon": "🌳",
            "working_dir": "/tmp/wt",
            "scope": "scoped",
            "worktree_path": "/tmp/wt",
            "branch_name": "feature"
        }
        worktree_file = temp_projects_dir / "child.json"
        with open(worktree_file, 'w') as f:
            json.dump(worktree_data, f)

        # Force delete should succeed
        result = editor.delete_project("main-force", force=True)
        assert result["status"] == "success"

        # Verify main project is deleted
        assert not (temp_projects_dir / "main-force.json").exists()
        # Worktree still exists (orphaned)
        assert (temp_projects_dir / "child.json").exists()


class TestConflictDetection:
    """Test conflict detection via file mtime comparison"""

    def test_get_file_mtime(self, editor, temp_projects_dir):
        """Test getting file modification timestamp"""
        config = ProjectConfig(
            name="mtime-test",
            display_name="Mtime Test",
            icon="🚀",
            working_dir="/tmp",
            scope="scoped"
        )
        editor.create_project(config)

        # Get mtime
        mtime = editor.get_file_mtime("mtime-test")
        assert isinstance(mtime, float)
        assert mtime > 0

    def test_get_mtime_nonexistent_file(self, editor):
        """Test getting mtime of nonexistent file raises error"""
        with pytest.raises(FileNotFoundError):
            editor.get_file_mtime("nonexistent")
