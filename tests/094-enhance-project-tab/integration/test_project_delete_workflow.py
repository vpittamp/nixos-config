"""
Integration Tests for Project Delete Workflow

Feature 094: Enhanced Projects & Applications CRUD Interface
- User Story 4 (T084): Tests the full project deletion workflow

Tests cover:
- Deleting project via CRUD handler
- JSON file removal verification
- Project list refresh after deletion
- Worktree blocking behavior
- Error handling
"""

import pytest
import asyncio
import json
import tempfile
import shutil
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools/monitoring-panel"))

from project_crud_handler import ProjectCRUDHandler
from i3_project_manager.models.project_config import ProjectConfig


@pytest.fixture
def temp_projects_dir():
    """Create temporary projects directory"""
    temp = Path(tempfile.mkdtemp(prefix="test_projects_"))
    yield temp
    shutil.rmtree(temp, ignore_errors=True)


@pytest.fixture
def temp_working_dir():
    """Create temporary working directory for project"""
    temp = Path(tempfile.mkdtemp(prefix="test_working_"))
    yield temp
    shutil.rmtree(temp, ignore_errors=True)


@pytest.fixture
def crud_handler(temp_projects_dir):
    """Create CRUD handler with temporary projects directory"""
    return ProjectCRUDHandler(projects_dir=str(temp_projects_dir))


@pytest.fixture
async def created_project(crud_handler, temp_projects_dir, temp_working_dir):
    """Create a project fixture for deletion tests"""
    request = {
        "action": "create_project",
        "config": {
            "name": "delete-test-project",
            "display_name": "Delete Test Project",
            "icon": "🗑️",
            "working_dir": str(temp_working_dir),
            "scope": "scoped"
        }
    }
    result = await crud_handler.handle_request(request)
    assert result["success"] is True
    return "delete-test-project"


class TestProjectDeleteWorkflow:
    """Test the full project deletion workflow"""

    @pytest.mark.asyncio
    async def test_delete_project_success(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Deleting a project should remove the JSON file"""
        # Create project first
        create_request = {
            "action": "create_project",
            "config": {
                "name": "to-delete",
                "display_name": "To Delete",
                "icon": "🗑️",
                "working_dir": str(temp_working_dir),
                "scope": "scoped"
            }
        }
        create_result = await crud_handler.handle_request(create_request)
        assert create_result["success"] is True

        # Verify file exists
        project_file = temp_projects_dir / "to-delete.json"
        assert project_file.exists()

        # Delete project
        delete_request = {
            "action": "delete_project",
            "project_name": "to-delete"
        }
        result = await crud_handler.handle_request(delete_request)

        assert result["success"] is True
        assert result["error_message"] == ""

        # Verify JSON file is removed
        assert not project_file.exists()

        # Verify backup file exists (.deleted extension)
        backup_file = temp_projects_dir / "to-delete.json.deleted"
        assert backup_file.exists()

    @pytest.mark.asyncio
    async def test_delete_nonexistent_project_fails(self, crud_handler):
        """Deleting a nonexistent project should fail"""
        request = {
            "action": "delete_project",
            "project_name": "nonexistent-project"
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "not found" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_delete_project_removes_from_list(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Deleted project should disappear from project list"""
        # Create two projects
        for name in ["project-a", "project-b"]:
            working = temp_working_dir / name
            working.mkdir(exist_ok=True)
            request = {
                "action": "create_project",
                "config": {
                    "name": name,
                    "display_name": f"Project {name.upper()}",
                    "working_dir": str(working)
                }
            }
            result = await crud_handler.handle_request(request)
            assert result["success"] is True

        # Verify both in list
        list_result = await crud_handler.handle_request({"action": "list_projects"})
        project_names = [p["name"] for p in list_result["main_projects"]]
        assert "project-a" in project_names
        assert "project-b" in project_names

        # Delete project-a
        delete_request = {
            "action": "delete_project",
            "project_name": "project-a"
        }
        await crud_handler.handle_request(delete_request)

        # Verify only project-b remains
        list_result = await crud_handler.handle_request({"action": "list_projects"})
        project_names = [p["name"] for p in list_result["main_projects"]]
        assert "project-a" not in project_names
        assert "project-b" in project_names


class TestDeleteWithWorktrees:
    """Test deletion behavior with worktrees"""

    @pytest.mark.asyncio
    async def test_delete_project_with_worktrees_blocked(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Deleting a project with active worktrees should be blocked"""
        # Create main project
        main_working = temp_working_dir / "main"
        main_working.mkdir(exist_ok=True)
        create_request = {
            "action": "create_project",
            "config": {
                "name": "main-project",
                "display_name": "Main Project",
                "working_dir": str(main_working)
            }
        }
        result = await crud_handler.handle_request(create_request)
        assert result["success"] is True

        # Manually create a worktree JSON file
        worktree_working = temp_working_dir / "worktree"
        worktree_working.mkdir(exist_ok=True)
        worktree_data = {
            "name": "worktree-1",
            "display_name": "Worktree 1",
            "icon": "🌳",
            "working_dir": str(worktree_working),
            "scope": "scoped",
            "parent_project": "main-project",
            "worktree_path": str(worktree_working),
            "branch_name": "feature-branch"
        }
        worktree_file = temp_projects_dir / "worktree-1.json"
        worktree_file.write_text(json.dumps(worktree_data))

        # Try to delete main project - should fail
        delete_request = {
            "action": "delete_project",
            "project_name": "main-project"
        }
        result = await crud_handler.handle_request(delete_request)

        assert result["success"] is False
        assert "worktree" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_delete_project_with_worktrees_force(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Force deleting a project with worktrees should succeed"""
        # Create main project
        main_working = temp_working_dir / "main"
        main_working.mkdir(exist_ok=True)
        create_request = {
            "action": "create_project",
            "config": {
                "name": "force-delete-main",
                "display_name": "Force Delete Main",
                "working_dir": str(main_working)
            }
        }
        result = await crud_handler.handle_request(create_request)
        assert result["success"] is True

        # Create worktree
        worktree_working = temp_working_dir / "worktree"
        worktree_working.mkdir(exist_ok=True)
        worktree_data = {
            "name": "force-worktree",
            "display_name": "Force Worktree",
            "working_dir": str(worktree_working),
            "scope": "scoped",
            "parent_project": "force-delete-main",
            "worktree_path": str(worktree_working),
            "branch_name": "feature"
        }
        worktree_file = temp_projects_dir / "force-worktree.json"
        worktree_file.write_text(json.dumps(worktree_data))

        # Force delete should succeed
        delete_request = {
            "action": "delete_project",
            "project_name": "force-delete-main",
            "force": True
        }
        result = await crud_handler.handle_request(delete_request)

        assert result["success"] is True

        # Main project should be gone
        main_file = temp_projects_dir / "force-delete-main.json"
        assert not main_file.exists()

        # Worktree should still exist (orphaned)
        assert worktree_file.exists()


class TestDeleteValidation:
    """Test validation during deletion"""

    @pytest.mark.asyncio
    async def test_delete_missing_project_name(self, crud_handler):
        """Delete request without project_name should fail"""
        request = {
            "action": "delete_project"
            # Missing project_name
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "project_name" in result["error_message"].lower()


class TestDeleteWorkflow:
    """Test the complete delete workflow end-to-end"""

    @pytest.mark.asyncio
    async def test_create_delete_create_same_name(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Should be able to create project with same name after deletion"""
        # Create project
        create_request = {
            "action": "create_project",
            "config": {
                "name": "recycle-name",
                "display_name": "First Instance",
                "working_dir": str(temp_working_dir)
            }
        }
        result = await crud_handler.handle_request(create_request)
        assert result["success"] is True

        # Delete project
        delete_request = {
            "action": "delete_project",
            "project_name": "recycle-name"
        }
        result = await crud_handler.handle_request(delete_request)
        assert result["success"] is True

        # Create again with same name
        create_request["config"]["display_name"] = "Second Instance"
        result = await crud_handler.handle_request(create_request)
        assert result["success"] is True

        # Verify it's the new instance
        project_data = json.loads((temp_projects_dir / "recycle-name.json").read_text())
        assert project_data["display_name"] == "Second Instance"

    @pytest.mark.asyncio
    async def test_delete_preserves_other_projects(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Deleting one project should not affect others"""
        # Create multiple projects
        projects = ["alpha", "beta", "gamma"]
        for name in projects:
            working = temp_working_dir / name
            working.mkdir(exist_ok=True)
            request = {
                "action": "create_project",
                "config": {
                    "name": name,
                    "display_name": name.title(),
                    "working_dir": str(working)
                }
            }
            result = await crud_handler.handle_request(request)
            assert result["success"] is True

        # Delete beta
        delete_request = {
            "action": "delete_project",
            "project_name": "beta"
        }
        result = await crud_handler.handle_request(delete_request)
        assert result["success"] is True

        # Verify alpha and gamma still exist and have correct content
        alpha_data = json.loads((temp_projects_dir / "alpha.json").read_text())
        assert alpha_data["name"] == "alpha"
        assert alpha_data["display_name"] == "Alpha"

        gamma_data = json.loads((temp_projects_dir / "gamma.json").read_text())
        assert gamma_data["name"] == "gamma"
        assert gamma_data["display_name"] == "Gamma"

        # Beta should be gone
        assert not (temp_projects_dir / "beta.json").exists()
