"""
Integration test for Projects tab data loading (Feature 094 - T018)

Tests verify:
1. query_projects_data() returns correct structure
2. Main projects and worktrees are correctly identified
3. Remote project flags are set correctly
4. Active project is identified
5. Error handling works correctly
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch, MagicMock
import json
from pathlib import Path


@pytest.mark.asyncio
class TestProjectViewDataLoading:
    """Integration tests for Projects tab data loading."""

    async def test_query_projects_data_structure(self):
        """Test that query_projects_data returns correct structure."""
        # Mock i3pm project list response
        mock_projects = [
            {
                "name": "nixos",
                "display_name": "NixOS Config",
                "directory": "/home/user/nixos",
                "icon": "󱄅",
                "remote": None,
            },
            {
                "name": "094-enhance",
                "display_name": "094 - Enhance Project Tab",
                "directory": "/home/user/nixos/.git/worktrees/094-enhance",
                "icon": "󰙨",
                "remote": None,
            },
        ]

        # Mock daemon client response for active project
        mock_daemon_response = {"current_project": "nixos"}

        with patch("subprocess.run") as mock_run:
            # Setup mock responses
            def run_side_effect(*args, **kwargs):
                cmd = args[0] if args else kwargs.get("args", [])
                if "i3pm" in cmd and "project" in cmd and "list" in cmd:
                    # i3pm project list --json
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_projects)
                    return result
                elif "i3pm" in cmd and "daemon" in cmd and "status" in cmd:
                    # i3pm daemon status --json
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_daemon_response)
                    return result
                else:
                    result = Mock()
                    result.returncode = 1
                    result.stderr = "Unknown command"
                    return result

            mock_run.side_effect = run_side_effect

            # Import after patching
            from i3_project_manager.cli.monitoring_data import (
                query_projects_data,
            )

            # Execute
            result = await query_projects_data()

            # Verify structure
            assert "status" in result
            assert result["status"] == "success"
            assert "main_projects" in result
            assert "worktrees" in result
            assert isinstance(result["main_projects"], list)
            assert isinstance(result["worktrees"], list)

    async def test_main_projects_identified_correctly(self):
        """Test that main projects are separated from worktrees."""
        mock_projects = [
            {
                "name": "nixos",
                "display_name": "NixOS Config",
                "directory": "/home/user/nixos",
                "icon": "󱄅",
                "remote": None,
            },
            {
                "name": "094-enhance",
                "display_name": "094 - Enhance Project Tab",
                "directory": "/home/user/nixos/.git/worktrees/094-enhance",
                "icon": "󰙨",
                "remote": None,
            },
        ]

        mock_daemon_response = {"current_project": None}

        with patch("subprocess.run") as mock_run:

            def run_side_effect(*args, **kwargs):
                cmd = args[0] if args else kwargs.get("args", [])
                if "i3pm" in cmd and "project" in cmd and "list" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_projects)
                    return result
                elif "i3pm" in cmd and "daemon" in cmd and "status" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_daemon_response)
                    return result
                else:
                    result = Mock()
                    result.returncode = 1
                    return result

            mock_run.side_effect = run_side_effect

            from i3_project_manager.cli.monitoring_data import (
                query_projects_data,
            )

            result = await query_projects_data()

            # Verify main project
            assert len(result["main_projects"]) == 1
            assert result["main_projects"][0]["name"] == "nixos"
            assert result["main_projects"][0]["directory"] == "/home/user/nixos"

            # Verify worktree
            assert len(result["worktrees"]) == 1
            assert result["worktrees"][0]["name"] == "094-enhance"
            assert ".git/worktrees" in result["worktrees"][0]["directory"]
            assert result["worktrees"][0]["parent_project"] == "nixos"

    async def test_remote_project_flag_set_correctly(self):
        """Test that is_remote flag is set for projects with remote config."""
        mock_projects = [
            {
                "name": "local-project",
                "display_name": "Local Project",
                "directory": "/home/user/local",
                "icon": "󱄅",
                "remote": None,
            },
            {
                "name": "remote-project",
                "display_name": "Remote Project",
                "directory": "/home/user/remote",
                "icon": "󰒍",
                "remote": {
                    "enabled": True,
                    "host": "hetzner-sway.tailnet",
                    "user": "vpittamp",
                    "working_dir": "/home/vpittamp/dev/remote",
                },
            },
        ]

        mock_daemon_response = {"current_project": None}

        with patch("subprocess.run") as mock_run:

            def run_side_effect(*args, **kwargs):
                cmd = args[0] if args else kwargs.get("args", [])
                if "i3pm" in cmd and "project" in cmd and "list" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_projects)
                    return result
                elif "i3pm" in cmd and "daemon" in cmd and "status" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_daemon_response)
                    return result
                else:
                    result = Mock()
                    result.returncode = 1
                    return result

            mock_run.side_effect = run_side_effect

            from i3_project_manager.cli.monitoring_data import (
                query_projects_data,
            )

            result = await query_projects_data()

            # Verify local project
            local_proj = next(p for p in result["main_projects"] if p["name"] == "local-project")
            assert local_proj["is_remote"] is False

            # Verify remote project
            remote_proj = next(p for p in result["main_projects"] if p["name"] == "remote-project")
            assert remote_proj["is_remote"] is True

    async def test_active_project_identified(self):
        """Test that the active project is flagged correctly."""
        mock_projects = [
            {
                "name": "project-a",
                "display_name": "Project A",
                "directory": "/home/user/project-a",
                "icon": "󱄅",
                "remote": None,
            },
            {
                "name": "project-b",
                "display_name": "Project B",
                "directory": "/home/user/project-b",
                "icon": "󱄅",
                "remote": None,
            },
        ]

        mock_daemon_response = {"current_project": "project-b"}

        with patch("subprocess.run") as mock_run:

            def run_side_effect(*args, **kwargs):
                cmd = args[0] if args else kwargs.get("args", [])
                if "i3pm" in cmd and "project" in cmd and "list" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_projects)
                    return result
                elif "i3pm" in cmd and "daemon" in cmd and "status" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_daemon_response)
                    return result
                else:
                    result = Mock()
                    result.returncode = 1
                    return result

            mock_run.side_effect = run_side_effect

            from i3_project_manager.cli.monitoring_data import (
                query_projects_data,
            )

            result = await query_projects_data()

            # Verify project-a is not active
            proj_a = next(p for p in result["main_projects"] if p["name"] == "project-a")
            assert proj_a["is_active"] is False

            # Verify project-b is active
            proj_b = next(p for p in result["main_projects"] if p["name"] == "project-b")
            assert proj_b["is_active"] is True

    async def test_error_handling_invalid_json(self):
        """Test that invalid JSON from i3pm is handled gracefully."""
        with patch("subprocess.run") as mock_run:

            def run_side_effect(*args, **kwargs):
                result = Mock()
                result.returncode = 0
                result.stdout = "INVALID JSON {"
                return result

            mock_run.side_effect = run_side_effect

            from i3_project_manager.cli.monitoring_data import (
                query_projects_data,
            )

            result = await query_projects_data()

            # Verify error status
            assert result["status"] == "error"
            assert "error" in result
            assert "JSON" in result["error"] or "parse" in result["error"].lower()

    async def test_error_handling_command_failure(self):
        """Test that i3pm command failures are handled gracefully."""
        with patch("subprocess.run") as mock_run:

            def run_side_effect(*args, **kwargs):
                result = Mock()
                result.returncode = 1
                result.stderr = "i3pm: command not found"
                return result

            mock_run.side_effect = run_side_effect

            from i3_project_manager.cli.monitoring_data import (
                query_projects_data,
            )

            result = await query_projects_data()

            # Verify error status
            assert result["status"] == "error"
            assert "error" in result
            # Should contain stderr message
            assert "command not found" in result["error"].lower() or "failed" in result["error"].lower()

    async def test_json_repr_field_included(self):
        """Test that json_repr field is included for hover details."""
        mock_projects = [
            {
                "name": "nixos",
                "display_name": "NixOS Config",
                "directory": "/home/user/nixos",
                "icon": "󱄅",
                "remote": None,
            },
        ]

        mock_daemon_response = {"current_project": None}

        with patch("subprocess.run") as mock_run:

            def run_side_effect(*args, **kwargs):
                cmd = args[0] if args else kwargs.get("args", [])
                if "i3pm" in cmd and "project" in cmd and "list" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_projects)
                    return result
                elif "i3pm" in cmd and "daemon" in cmd and "status" in cmd:
                    result = Mock()
                    result.returncode = 0
                    result.stdout = json.dumps(mock_daemon_response)
                    return result
                else:
                    result = Mock()
                    result.returncode = 1
                    return result

            mock_run.side_effect = run_side_effect

            from i3_project_manager.cli.monitoring_data import (
                query_projects_data,
            )

            result = await query_projects_data()

            # Verify json_repr field exists
            assert len(result["main_projects"]) > 0
            project = result["main_projects"][0]
            assert "json_repr" in project
            assert isinstance(project["json_repr"], str)
            # Should contain project data
            assert "nixos" in project["json_repr"]
