"""
Pytest fixtures for Feature 096 - Project & Worktree CRUD Testing

Provides common fixtures for:
- ProjectEditor service instantiation
- Temporary project directory setup/teardown
- Mock project configurations
- Test data generators
"""

import json
import pytest
import tempfile
import shutil
from pathlib import Path
from datetime import datetime
from typing import Generator, Dict, Any


@pytest.fixture
def temp_projects_dir() -> Generator[Path, None, None]:
    """Create a temporary projects directory for isolated testing"""
    temp_dir = tempfile.mkdtemp(prefix="i3pm_test_projects_")
    temp_path = Path(temp_dir)
    yield temp_path
    # Cleanup after test
    shutil.rmtree(temp_dir, ignore_errors=True)


@pytest.fixture
def sample_project_config(temp_projects_dir: Path) -> Dict[str, Any]:
    """Return a sample project configuration for testing"""
    # Create a real directory for the project (validation requires it)
    project_dir = temp_projects_dir / "test-project-dir"
    project_dir.mkdir(parents=True, exist_ok=True)
    return {
        "name": "test-project",
        "display_name": "Test Project",
        "icon": "\U0001F4C1",  # Folder emoji (valid icon format)
        "directory": str(project_dir),
        "scope": "scoped",
        "created_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat()
    }


@pytest.fixture
def sample_worktree_config(sample_project_config: Dict[str, Any]) -> Dict[str, Any]:
    """Return a sample worktree configuration for testing"""
    return {
        **sample_project_config,
        "name": "test-project-feature-123",
        "display_name": "Feature 123",
        "parent_project": "test-project",
        "branch_name": "feature-123",
        "worktree_path": "/tmp/test-project-feature-123"
    }


@pytest.fixture
def project_json_file(temp_projects_dir: Path, sample_project_config: Dict[str, Any]) -> Path:
    """Create a project JSON file in the temp directory and return its path"""
    project_file = temp_projects_dir / f"{sample_project_config['name']}.json"
    with open(project_file, 'w') as f:
        json.dump(sample_project_config, f, indent=2)
    return project_file


@pytest.fixture
def project_editor(temp_projects_dir: Path):
    """Create a ProjectEditor instance with a temporary projects directory"""
    # Import here to allow tests to run without full i3pm installation
    from i3_project_manager.services.project_editor import ProjectEditor
    return ProjectEditor(projects_dir=temp_projects_dir)


@pytest.fixture
def populated_projects_dir(temp_projects_dir: Path) -> Path:
    """Create a temp directory with multiple project files for list testing"""
    projects = [
        {"name": "project-a", "display_name": "Project A", "directory": "/home/user/project-a", "icon": "a"},
        {"name": "project-b", "display_name": "Project B", "directory": "/home/user/project-b", "icon": "b"},
        {"name": "project-c-worktree", "display_name": "Feature Branch", "directory": "/home/user/project-c",
         "parent_project": "project-a", "branch_name": "feature-x", "worktree_path": "/home/user/wt-x"},
    ]
    for proj in projects:
        proj_file = temp_projects_dir / f"{proj['name']}.json"
        with open(proj_file, 'w') as f:
            json.dump(proj, f, indent=2)
    return temp_projects_dir


# Eww state dump fixture for debugging failed UI tests
@pytest.fixture
def eww_state_dump():
    """Capture eww state for debugging test failures"""
    import subprocess
    try:
        result = subprocess.run(
            ["eww", "--config", f"{Path.home()}/.config/eww-monitoring-panel", "state"],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return "eww state capture failed"


# Test markers for categorization
def pytest_configure(config):
    """Register custom markers"""
    config.addinivalue_line("markers", "unit: Unit tests (fast, isolated)")
    config.addinivalue_line("markers", "integration: Integration tests (may require eww daemon)")
    config.addinivalue_line("markers", "sway: Sway UI tests (require running Sway session)")
    config.addinivalue_line("markers", "screenshot: Screenshot comparison tests")
