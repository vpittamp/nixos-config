"""
Integration Tests for Project Create Workflow

Feature 094: Enhanced Projects & Applications CRUD Interface
- User Story 3 (T063): Tests the full project creation workflow

Tests cover:
- Creating project via CRUD handler
- JSON file creation
- Project list refresh
- Error handling for duplicates
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

from project_crud_handler import ProjectCRUDHandler, check_project_name_exists
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


class TestProjectCreateWorkflow:
    """Test the full project creation workflow"""

    @pytest.mark.asyncio
    async def test_create_project_success(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Creating a new project should succeed and create JSON file"""
        request = {
            "action": "create_project",
            "config": {
                "name": "test-project",
                "display_name": "Test Project",
                "icon": "🚀",
                "working_dir": str(temp_working_dir),
                "scope": "scoped"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        assert result["error_message"] == ""
        assert len(result["validation_errors"]) == 0

        # Verify JSON file was created
        project_file = temp_projects_dir / "test-project.json"
        assert project_file.exists()

        # Verify JSON content
        with open(project_file) as f:
            data = json.load(f)
        assert data["name"] == "test-project"
        assert data["display_name"] == "Test Project"
        assert data["icon"] == "🚀"

    @pytest.mark.asyncio
    async def test_create_project_with_remote(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Creating a remote project should include remote config"""
        request = {
            "action": "create_project",
            "config": {
                "name": "remote-project",
                "display_name": "Remote Project",
                "icon": "🌐",
                "working_dir": str(temp_working_dir),
                "scope": "scoped",
                "remote": {
                    "enabled": True,
                    "host": "hetzner-sway.tailnet",
                    "user": "vpittamp",
                    "remote_dir": "/home/vpittamp/dev/project"
                }
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True

        # Verify remote config in JSON
        project_file = temp_projects_dir / "remote-project.json"
        with open(project_file) as f:
            data = json.load(f)
        assert data["remote"]["enabled"] is True
        assert data["remote"]["host"] == "hetzner-sway.tailnet"

    @pytest.mark.asyncio
    async def test_create_duplicate_project_rejected(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Creating project with existing name should fail"""
        # Create first project
        request = {
            "action": "create_project",
            "config": {
                "name": "duplicate-test",
                "display_name": "First Project",
                "working_dir": str(temp_working_dir)
            }
        }
        result = await crud_handler.handle_request(request)
        assert result["success"] is True

        # Try to create second project with same name
        request["config"]["display_name"] = "Second Project"
        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "exists" in result["error_message"].lower() or len(result["validation_errors"]) > 0

    @pytest.mark.asyncio
    async def test_create_project_invalid_name_rejected(self, crud_handler, temp_working_dir):
        """Creating project with invalid name should fail validation"""
        request = {
            "action": "create_project",
            "config": {
                "name": "Invalid Name",  # Has uppercase and space
                "display_name": "Invalid Project",
                "working_dir": str(temp_working_dir)
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert len(result["validation_errors"]) > 0 or "name" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_create_project_invalid_directory_rejected(self, crud_handler):
        """Creating project with nonexistent directory should fail"""
        request = {
            "action": "create_project",
            "config": {
                "name": "no-dir-project",
                "display_name": "No Directory",
                "working_dir": "/nonexistent/path/to/project"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "directory" in result["error_message"].lower() or len(result["validation_errors"]) > 0

    @pytest.mark.asyncio
    async def test_create_project_missing_config_rejected(self, crud_handler):
        """Creating project without config should fail"""
        request = {
            "action": "create_project"
            # Missing config field
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "config" in result["error_message"].lower()


class TestProjectListAfterCreate:
    """Test project list updates after creation"""

    @pytest.mark.asyncio
    async def test_new_project_appears_in_list(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Newly created project should appear in list"""
        # Create project
        create_request = {
            "action": "create_project",
            "config": {
                "name": "list-test",
                "display_name": "List Test",
                "working_dir": str(temp_working_dir)
            }
        }
        result = await crud_handler.handle_request(create_request)
        assert result["success"] is True

        # List projects
        list_request = {"action": "list_projects"}
        list_result = await crud_handler.handle_request(list_request)

        assert list_result["success"] is True
        project_names = [p["name"] for p in list_result["main_projects"]]
        assert "list-test" in project_names

    @pytest.mark.asyncio
    async def test_multiple_projects_in_list(self, crud_handler, temp_projects_dir, temp_working_dir):
        """Multiple created projects should all appear in list"""
        # Create multiple projects
        for i in range(3):
            # Create separate working directories
            working_dir = temp_working_dir / f"project-{i}"
            working_dir.mkdir(exist_ok=True)

            request = {
                "action": "create_project",
                "config": {
                    "name": f"project-{i}",
                    "display_name": f"Project {i}",
                    "working_dir": str(working_dir)
                }
            }
            result = await crud_handler.handle_request(request)
            assert result["success"] is True

        # List projects
        list_request = {"action": "list_projects"}
        list_result = await crud_handler.handle_request(list_request)

        assert list_result["success"] is True
        project_names = [p["name"] for p in list_result["main_projects"]]
        assert len(project_names) >= 3
        for i in range(3):
            assert f"project-{i}" in project_names


class TestCheckProjectNameExists:
    """Test the project name existence helper function"""

    def test_existing_project_detected(self, temp_projects_dir):
        """Should return True for existing project"""
        project_file = temp_projects_dir / "existing.json"
        project_file.write_text('{"name": "existing"}')

        assert check_project_name_exists("existing", temp_projects_dir) is True

    def test_nonexistent_project_not_detected(self, temp_projects_dir):
        """Should return False for nonexistent project"""
        assert check_project_name_exists("nonexistent", temp_projects_dir) is False

    def test_empty_directory(self, temp_projects_dir):
        """Should return False for empty directory"""
        assert check_project_name_exists("any-name", temp_projects_dir) is False
