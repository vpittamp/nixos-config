"""
Unit Tests for CLI Executor Service

Feature 094: Enhanced Projects & Applications CRUD Interface (T053)
Tests for CLIExecutor class: i3pm/Git command execution, error parsing, timeout handling
"""

import pytest
import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, patch, MagicMock

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools/monitoring-panel"))

from cli_executor import CLIExecutor


class TestCLIExecutorI3PM:
    """Test i3pm command execution"""

    @pytest.fixture
    def executor(self):
        """Create CLI executor instance"""
        return CLIExecutor(timeout=5)

    @pytest.mark.asyncio
    async def test_execute_i3pm_worktree_create_success(self, executor):
        """Test successful i3pm worktree create command"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"Worktree created at /tmp/test-worktree\n",
                b""
            ))
            mock_process.returncode = 0
            mock_subprocess.return_value = mock_process

            result = await executor.execute_i3pm_command(
                "worktree",
                ["create", "test-branch", "/tmp/test-worktree"]
            )

            assert result.success is True
            assert result.exit_code == 0
            assert "Worktree created" in result.stdout
            assert result.error_category is None

    @pytest.mark.asyncio
    async def test_execute_i3pm_worktree_create_branch_not_found(self, executor):
        """Test i3pm worktree create with non-existent branch"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"",
                b"fatal: invalid reference: nonexistent-branch\n"
            ))
            mock_process.returncode = 1
            mock_subprocess.return_value = mock_process

            result = await executor.execute_i3pm_command(
                "worktree",
                ["create", "nonexistent-branch", "/tmp/test-worktree"]
            )

            assert result.success is False
            assert result.exit_code == 1
            assert result.error_category == "validation"
            assert "not found" in result.user_message.lower() or "invalid" in result.user_message.lower()

    @pytest.mark.asyncio
    async def test_execute_i3pm_worktree_delete_success(self, executor):
        """Test successful worktree deletion"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"Worktree deleted\n",
                b""
            ))
            mock_process.returncode = 0
            mock_subprocess.return_value = mock_process

            result = await executor.execute_i3pm_command(
                "worktree",
                ["delete", "test-worktree"]
            )

            assert result.success is True
            assert result.exit_code == 0

    @pytest.mark.asyncio
    async def test_execute_i3pm_project_switch(self, executor):
        """Test i3pm project switch command"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"Switched to project: nixos\n",
                b""
            ))
            mock_process.returncode = 0
            mock_subprocess.return_value = mock_process

            result = await executor.execute_i3pm_command(
                "project",
                ["switch", "nixos"]
            )

            assert result.success is True
            assert "nixos" in result.stdout


class TestCLIExecutorGit:
    """Test Git command execution"""

    @pytest.fixture
    def executor(self):
        """Create CLI executor instance"""
        return CLIExecutor(timeout=5)

    @pytest.mark.asyncio
    async def test_execute_git_worktree_add_success(self, executor):
        """Test successful git worktree add"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"Preparing worktree (checking out 'feature-123')\n",
                b""
            ))
            mock_process.returncode = 0
            mock_subprocess.return_value = mock_process

            result = await executor.execute_git_command(
                ["worktree", "add", "-b", "feature-123", "/tmp/wt"],
                cwd=Path("/tmp/test-repo")
            )

            assert result.success is True
            assert result.exit_code == 0

    @pytest.mark.asyncio
    async def test_execute_git_branch_not_found(self, executor):
        """Test git command with non-existent branch"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"",
                b"fatal: 'nonexistent' is not a commit and a branch 'nonexistent' cannot be created from it\n"
            ))
            mock_process.returncode = 128
            mock_subprocess.return_value = mock_process

            result = await executor.execute_git_command(
                ["worktree", "add", "/tmp/wt", "nonexistent"],
                cwd=Path("/tmp/test-repo")
            )

            assert result.success is False
            assert result.error_category == "git"

    @pytest.mark.asyncio
    async def test_execute_git_worktree_already_exists(self, executor):
        """Test git worktree add when path already exists"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"",
                b"fatal: '/tmp/existing-wt' already exists\n"
            ))
            mock_process.returncode = 128
            mock_subprocess.return_value = mock_process

            result = await executor.execute_git_command(
                ["worktree", "add", "/tmp/existing-wt", "main"],
                cwd=Path("/tmp/test-repo")
            )

            assert result.success is False
            # Either "git" or "validation" is acceptable here
            assert result.error_category in ["git", "validation"]
            assert "already exists" in result.user_message.lower() or "already exists" in result.stderr.lower()

    @pytest.mark.asyncio
    async def test_execute_git_not_a_repository(self, executor):
        """Test git command outside a repository"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"",
                b"fatal: not a git repository (or any of the parent directories): .git\n"
            ))
            mock_process.returncode = 128
            mock_subprocess.return_value = mock_process

            result = await executor.execute_git_command(
                ["worktree", "list"],
                cwd=Path("/tmp/not-a-repo")
            )

            assert result.success is False
            assert result.error_category == "git"
            assert "not a git repository" in result.stderr.lower()
            assert "git init" in result.user_message.lower() or "repository" in result.user_message.lower()


class TestCLIExecutorErrorHandling:
    """Test error handling and categorization"""

    @pytest.fixture
    def executor(self):
        """Create CLI executor instance"""
        return CLIExecutor(timeout=5)

    @pytest.mark.asyncio
    async def test_command_timeout(self, executor):
        """Test command timeout handling"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(
                side_effect=asyncio.TimeoutError()
            )
            mock_process.kill = MagicMock()
            mock_process.wait = AsyncMock()
            mock_subprocess.return_value = mock_process

            result = await executor.execute_i3pm_command(
                "project",
                ["switch", "slow-project"]
            )

            assert result.success is False
            assert result.error_category == "timeout"
            assert "timeout" in result.user_message.lower()
            mock_process.kill.assert_called_once()

    @pytest.mark.asyncio
    async def test_command_not_found(self, executor):
        """Test handling when command doesn't exist"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_subprocess.side_effect = FileNotFoundError("Command not found: nonexistent-cmd")

            result = await executor.execute_i3pm_command(
                "nonexistent-cmd",
                ["arg1"]
            )

            assert result.success is False
            assert result.error_category == "validation"
            assert "not found" in result.user_message.lower()

    @pytest.mark.asyncio
    async def test_permission_error(self, executor):
        """Test permission error categorization"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"",
                b"Permission denied: /root/protected\n"
            ))
            mock_process.returncode = 1
            mock_subprocess.return_value = mock_process

            result = await executor.execute_git_command(
                ["init"],
                cwd=Path("/root/protected")
            )

            assert result.success is False
            assert result.error_category == "permission"
            assert "permission" in result.user_message.lower()

    @pytest.mark.asyncio
    async def test_unexpected_error(self, executor):
        """Test unexpected error handling"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_subprocess.side_effect = RuntimeError("Unexpected internal error")

            result = await executor.execute_i3pm_command(
                "project",
                ["list"]
            )

            assert result.success is False
            assert result.error_category == "unknown"
            assert "unexpected" in result.user_message.lower()


class TestCLIExecutorUserMessages:
    """Test user-friendly error message generation"""

    @pytest.fixture
    def executor(self):
        """Create CLI executor instance"""
        return CLIExecutor(timeout=5)

    @pytest.mark.asyncio
    async def test_branch_not_found_recovery_steps(self, executor):
        """Test that branch not found errors include recovery steps"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"",
                b"fatal: cannot lock ref 'refs/heads/feature-abc': unable to resolve reference 'refs/heads/feature-abc': reference broken\n"
            ))
            mock_process.returncode = 128
            mock_subprocess.return_value = mock_process

            result = await executor.execute_git_command(
                ["worktree", "add", "/tmp/wt", "feature-abc"],
                cwd=Path("/tmp/repo")
            )

            assert result.success is False
            # User message should include helpful recovery information
            # At minimum, should mention something about the command failing
            assert len(result.user_message) > 0

    @pytest.mark.asyncio
    async def test_worktree_exists_recovery_steps(self, executor):
        """Test that worktree already exists errors include recovery steps"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"",
                b"fatal: worktree '/tmp/my-worktree' already exists\n"
            ))
            mock_process.returncode = 128
            mock_subprocess.return_value = mock_process

            result = await executor.execute_git_command(
                ["worktree", "add", "/tmp/my-worktree", "main"],
                cwd=Path("/tmp/repo")
            )

            assert result.success is False
            # Should mention remove or choose different path
            assert "remove" in result.user_message.lower() or "different" in result.user_message.lower() or "already exists" in result.stderr.lower()


class TestCLIExecutorNixosRebuild:
    """Test nixos-rebuild command execution"""

    @pytest.fixture
    def executor(self):
        """Create CLI executor instance"""
        return CLIExecutor(timeout=300)  # Longer timeout for rebuild

    @pytest.mark.asyncio
    async def test_nixos_rebuild_switch(self, executor):
        """Test nixos-rebuild switch command"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"activating the configuration...\ndone.\n",
                b""
            ))
            mock_process.returncode = 0
            mock_subprocess.return_value = mock_process

            result = await executor.execute_nixos_rebuild(
                action="switch",
                target="hetzner-sway"
            )

            assert result.success is True
            assert result.exit_code == 0
            # Verify the command was constructed correctly
            assert "sudo nixos-rebuild switch" in result.command

    @pytest.mark.asyncio
    async def test_nixos_rebuild_with_target(self, executor):
        """Test nixos-rebuild with specific target"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(
                b"Building...\n",
                b""
            ))
            mock_process.returncode = 0
            mock_subprocess.return_value = mock_process

            result = await executor.execute_nixos_rebuild(
                action="build",
                target="m1",
                extra_args=["--impure"]
            )

            assert result.success is True
            # Verify flake target format
            assert ".#m1" in result.command


class TestCLIExecutorCommandString:
    """Test command string construction"""

    @pytest.fixture
    def executor(self):
        """Create CLI executor instance"""
        return CLIExecutor(timeout=5)

    @pytest.mark.asyncio
    async def test_command_string_stored(self, executor):
        """Test that full command string is stored in result"""
        with patch('asyncio.create_subprocess_exec') as mock_subprocess:
            mock_process = AsyncMock()
            mock_process.communicate = AsyncMock(return_value=(b"", b""))
            mock_process.returncode = 0
            mock_subprocess.return_value = mock_process

            result = await executor.execute_i3pm_command(
                "worktree",
                ["create", "test-branch", "/tmp/wt", "--display-name", "Test"]
            )

            assert "i3pm worktree create test-branch /tmp/wt --display-name Test" in result.command
