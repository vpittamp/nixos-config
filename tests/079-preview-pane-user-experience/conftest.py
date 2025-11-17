"""Pytest configuration for Feature 079: Preview Pane User Experience tests."""

import pytest
import sys
from pathlib import Path

# Add the daemon module to Python path
daemon_path = Path(__file__).parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_path))


@pytest.fixture
def sample_project_data():
    """Sample project data for testing."""
    return {
        "name": "nixos-079-preview-pane",
        "display_name": "Preview Pane UX",
        "path": "/home/vpittamp/nixos-079-preview-pane-user-experience",
        "icon": "",
        "worktree": {
            "is_worktree": True,
            "parent_repo": "nixos",
            "branch": "079-preview-pane-user-experience",
            "git_status": {
                "dirty": False,
                "ahead": 2,
                "behind": 0
            }
        }
    }


@pytest.fixture
def sample_projects_list():
    """List of sample projects for filtering tests."""
    return [
        {
            "name": "nixos-079-preview-pane",
            "display_name": "Preview Pane UX",
            "branch_number": "079",
            "branch_type": "feature",
            "full_branch_name": "079-preview-pane-user-experience",
            "icon": "",
            "is_worktree": True,
            "parent_project_name": "nixos",
            "match_score": 0,
            "match_positions": [],
            "relative_time": "2h ago",
            "path": "/home/vpittamp/nixos-079-preview-pane-user-experience"
        },
        {
            "name": "nixos-078-eww-preview",
            "display_name": "Eww Preview",
            "branch_number": "078",
            "branch_type": "feature",
            "full_branch_name": "078-eww-preview-improvement",
            "icon": "",
            "is_worktree": True,
            "parent_project_name": "nixos",
            "match_score": 0,
            "match_positions": [],
            "relative_time": "1d ago",
            "path": "/home/vpittamp/nixos-078-eww-preview-improvement"
        },
        {
            "name": "nixos",
            "display_name": "NixOS Config",
            "branch_number": None,
            "branch_type": "main",
            "full_branch_name": "main",
            "icon": "",
            "is_worktree": False,
            "parent_project_name": None,
            "match_score": 0,
            "match_positions": [],
            "relative_time": "3d ago",
            "path": "/home/vpittamp/nixos-config"
        }
    ]
