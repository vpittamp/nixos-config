"""
Unit tests for git metadata extraction.

Feature 097: Git-Based Project Discovery and Management
Task T015: Test git metadata extraction logic

Tests the `extract_git_metadata()` function that extracts git information
from repositories using git commands.
"""

import pytest
from pathlib import Path
from datetime import datetime
from unittest.mock import AsyncMock, patch, MagicMock
import asyncio


class TestGitMetadataExtraction:
    """Test cases for extracting git metadata from repositories."""

    @pytest.fixture
    def mock_subprocess(self):
        """Mock asyncio.create_subprocess_exec for git commands."""
        with patch("asyncio.create_subprocess_exec") as mock:
            yield mock

    @pytest.mark.asyncio
    async def test_extract_metadata_from_clean_repo(self, mock_subprocess):
        """Should extract correct metadata from a clean repository."""
        # Mock git command responses
        responses = {
            "rev-parse --abbrev-ref HEAD": "main",
            "rev-parse --short HEAD": "a1b2c3d",
            "status --porcelain": "",  # Empty = clean
            "remote get-url origin": "https://github.com/user/repo.git",
            "rev-list --left-right --count @{u}...HEAD": "0\t0",
            "log -1 --format=%cI": "2025-11-26T10:30:00+00:00",
        }

        async def mock_exec(*args, **kwargs):
            cmd_args = " ".join(args[1:])  # Skip 'git'
            proc = MagicMock()
            output = ""
            for pattern, response in responses.items():
                if pattern in cmd_args:
                    output = response
                    break
            proc.communicate = AsyncMock(return_value=(output.encode(), b""))
            proc.returncode = 0
            return proc

        mock_subprocess.side_effect = mock_exec

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            extract_git_metadata
        )

        metadata = await extract_git_metadata(Path("/fake/repo"))

        assert metadata.current_branch == "main"
        assert metadata.commit_hash == "a1b2c3d"
        assert metadata.is_clean is True
        assert metadata.has_untracked is False
        assert metadata.ahead_count == 0
        assert metadata.behind_count == 0
        assert metadata.remote_url == "https://github.com/user/repo.git"

    @pytest.mark.asyncio
    async def test_extract_metadata_from_dirty_repo(self, mock_subprocess):
        """Should detect dirty status from modified files."""
        responses = {
            "rev-parse --abbrev-ref HEAD": "feature-x",
            "rev-parse --short HEAD": "b2c3d4e",
            "status --porcelain": " M src/main.py\n?? new-file.txt",  # Modified + untracked
            "remote get-url origin": "git@github.com:user/repo.git",
            "rev-list --left-right --count @{u}...HEAD": "2\t1",
            "log -1 --format=%cI": "2025-11-25T15:00:00+00:00",
        }

        async def mock_exec(*args, **kwargs):
            cmd_args = " ".join(args[1:])
            proc = MagicMock()
            output = ""
            for pattern, response in responses.items():
                if pattern in cmd_args:
                    output = response
                    break
            proc.communicate = AsyncMock(return_value=(output.encode(), b""))
            proc.returncode = 0
            return proc

        mock_subprocess.side_effect = mock_exec

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            extract_git_metadata
        )

        metadata = await extract_git_metadata(Path("/fake/repo"))

        assert metadata.current_branch == "feature-x"
        assert metadata.is_clean is False
        assert metadata.has_untracked is True
        assert metadata.ahead_count == 1  # HEAD is ahead
        assert metadata.behind_count == 2  # upstream is ahead

    @pytest.mark.asyncio
    async def test_extract_metadata_with_detached_head(self, mock_subprocess):
        """Should handle detached HEAD state."""
        responses = {
            "rev-parse --abbrev-ref HEAD": "HEAD",  # Detached
            "rev-parse --short HEAD": "c3d4e5f",
            "status --porcelain": "",
            "remote get-url origin": "https://github.com/user/repo.git",
        }

        async def mock_exec(*args, **kwargs):
            cmd_args = " ".join(args[1:])
            proc = MagicMock()
            output = ""
            for pattern, response in responses.items():
                if pattern in cmd_args:
                    output = response
                    break
            proc.communicate = AsyncMock(return_value=(output.encode(), b""))
            proc.returncode = 0
            return proc

        mock_subprocess.side_effect = mock_exec

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            extract_git_metadata
        )

        metadata = await extract_git_metadata(Path("/fake/repo"))

        assert metadata.current_branch == "HEAD"

    @pytest.mark.asyncio
    async def test_extract_metadata_without_remote(self, mock_subprocess):
        """Should handle repos without remote."""
        async def mock_exec(*args, **kwargs):
            cmd_args = " ".join(args[1:])
            proc = MagicMock()

            if "remote get-url" in cmd_args:
                proc.returncode = 1  # No remote
                proc.communicate = AsyncMock(return_value=(b"", b"fatal: No such remote"))
            else:
                proc.returncode = 0
                output = {
                    "rev-parse --abbrev-ref HEAD": "main",
                    "rev-parse --short HEAD": "d4e5f6g",
                    "status --porcelain": "",
                }.get(cmd_args.split()[0] + " " + " ".join(cmd_args.split()[1:3]), "")
                proc.communicate = AsyncMock(return_value=(output.encode(), b""))

            return proc

        mock_subprocess.side_effect = mock_exec

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            extract_git_metadata
        )

        metadata = await extract_git_metadata(Path("/fake/repo"))

        assert metadata.remote_url is None

    @pytest.mark.asyncio
    async def test_extract_metadata_without_upstream(self, mock_subprocess):
        """Should handle repos without upstream tracking branch."""
        async def mock_exec(*args, **kwargs):
            cmd_args = " ".join(args[1:])
            proc = MagicMock()

            if "rev-list --left-right" in cmd_args:
                proc.returncode = 128  # No upstream
                proc.communicate = AsyncMock(return_value=(b"", b"fatal: no upstream"))
            else:
                proc.returncode = 0
                responses = {
                    "rev-parse --abbrev-ref HEAD": "main",
                    "rev-parse --short HEAD": "e5f6g7h",
                    "status --porcelain": "",
                    "remote get-url origin": "https://github.com/user/repo.git",
                }
                output = ""
                for pattern, response in responses.items():
                    if pattern in cmd_args:
                        output = response
                        break
                proc.communicate = AsyncMock(return_value=(output.encode(), b""))

            return proc

        mock_subprocess.side_effect = mock_exec

        from home_modules.desktop.i3_project_event_daemon.services.discovery_service import (
            extract_git_metadata
        )

        metadata = await extract_git_metadata(Path("/fake/repo"))

        assert metadata.ahead_count == 0
        assert metadata.behind_count == 0
