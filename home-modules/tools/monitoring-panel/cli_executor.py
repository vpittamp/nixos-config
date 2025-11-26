"""
CLI Execution Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Executes i3pm/Git commands and parses stderr/exit codes per spec.md Q3
"""

import asyncio
import re
from typing import Optional, Literal
from pathlib import Path

import sys
# Add tools directory to path for i3_project_manager imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from i3_project_manager.models.validation_state import CLIExecutionResult


class CLIExecutor:
    """Service for executing CLI commands with error categorization"""

    def __init__(self, timeout: int = 30):
        """
        Initialize CLI executor

        Args:
            timeout: Command timeout in seconds (default: 30)
        """
        self.timeout = timeout

    async def execute_i3pm_command(
        self,
        command: str,
        args: list[str],
        cwd: Optional[Path] = None
    ) -> CLIExecutionResult:
        """
        Execute i3pm CLI command

        Args:
            command: i3pm subcommand (e.g., "project", "worktree")
            args: Command arguments
            cwd: Working directory for command execution

        Returns:
            CLIExecutionResult with execution status and error categorization
        """
        full_command = ["i3pm", command] + args
        return await self._execute_command(full_command, cwd)

    async def execute_git_command(
        self,
        args: list[str],
        cwd: Optional[Path] = None
    ) -> CLIExecutionResult:
        """
        Execute Git command

        Args:
            args: Git command arguments
            cwd: Working directory (usually Git repository root)

        Returns:
            CLIExecutionResult with execution status and error categorization
        """
        full_command = ["git"] + args
        return await self._execute_command(full_command, cwd)

    async def execute_nixos_rebuild(
        self,
        action: Literal["switch", "test", "build"],
        target: Optional[str] = None,
        extra_args: Optional[list[str]] = None
    ) -> CLIExecutionResult:
        """
        Execute nixos-rebuild command

        Args:
            action: Rebuild action (switch, test, build)
            target: Optional system target (e.g., "hetzner-sway", "m1")
            extra_args: Additional arguments

        Returns:
            CLIExecutionResult with execution status
        """
        command = ["sudo", "nixos-rebuild", action]

        if target:
            command.extend(["--flake", f".#{target}"])

        if extra_args:
            command.extend(extra_args)

        return await self._execute_command(command, cwd=Path("/etc/nixos"))

    async def _execute_command(
        self,
        command: list[str],
        cwd: Optional[Path] = None
    ) -> CLIExecutionResult:
        """
        Execute arbitrary command with error handling

        Args:
            command: Command and arguments as list
            cwd: Working directory

        Returns:
            CLIExecutionResult with categorized errors
        """
        command_str = " ".join(command)

        try:
            # Execute command
            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=str(cwd) if cwd else None
            )

            # Wait for completion with timeout
            try:
                stdout_bytes, stderr_bytes = await asyncio.wait_for(
                    process.communicate(),
                    timeout=self.timeout
                )
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                return CLIExecutionResult(
                    success=False,
                    exit_code=-1,
                    stdout="",
                    stderr=f"Command timed out after {self.timeout} seconds",
                    error_category="timeout",
                    user_message=f"Command timed out after {self.timeout} seconds. Try increasing timeout or check for hanging processes.",
                    command=command_str
                )

            # Decode output
            stdout = stdout_bytes.decode('utf-8', errors='replace')
            stderr = stderr_bytes.decode('utf-8', errors='replace')
            exit_code = process.returncode

            # Success case
            if exit_code == 0:
                return CLIExecutionResult(
                    success=True,
                    exit_code=0,
                    stdout=stdout,
                    stderr=stderr,
                    error_category=None,
                    user_message="",
                    command=command_str
                )

            # Error case - categorize and provide user-friendly message
            error_category = self._categorize_error(stderr, exit_code, command)
            user_message = self._generate_user_message(stderr, error_category, command)

            return CLIExecutionResult(
                success=False,
                exit_code=exit_code,
                stdout=stdout,
                stderr=stderr,
                error_category=error_category,
                user_message=user_message,
                command=command_str
            )

        except FileNotFoundError:
            return CLIExecutionResult(
                success=False,
                exit_code=-1,
                stdout="",
                stderr=f"Command not found: {command[0]}",
                error_category="validation",
                user_message=f"Command '{command[0]}' not found. Ensure it is installed and in PATH.",
                command=command_str
            )
        except Exception as e:
            return CLIExecutionResult(
                success=False,
                exit_code=-1,
                stdout="",
                stderr=str(e),
                error_category="unknown",
                user_message=f"Unexpected error executing command: {str(e)}",
                command=command_str
            )

    def _categorize_error(
        self,
        stderr: str,
        exit_code: int,
        command: list[str]
    ) -> Literal["validation", "permission", "git", "timeout", "unknown"]:
        """
        Categorize error based on stderr content and exit code

        Args:
            stderr: Standard error output
            exit_code: Process exit code
            command: Executed command

        Returns:
            Error category
        """
        stderr_lower = stderr.lower()

        # Validation errors
        validation_patterns = [
            r"invalid",
            r"already exists",
            r"not found",
            r"does not exist",
            r"cannot create",
            r"name.*required",
            r"invalid.*format"
        ]
        for pattern in validation_patterns:
            if re.search(pattern, stderr_lower):
                return "validation"

        # Permission errors
        permission_patterns = [
            r"permission denied",
            r"access denied",
            r"insufficient permissions",
            r"operation not permitted",
            r"sudo",
            r"must be root"
        ]
        for pattern in permission_patterns:
            if re.search(pattern, stderr_lower):
                return "permission"

        # Git-specific errors
        git_patterns = [
            r"fatal:",
            r"not a git repository",
            r"branch.*not found",
            r"cannot.*branch",
            r"worktree.*already exists",
            r"no such ref",
            r"ambiguous argument"
        ]
        if any("git" in cmd for cmd in command):
            for pattern in git_patterns:
                if re.search(pattern, stderr_lower):
                    return "git"

        # Unknown error
        return "unknown"

    def _generate_user_message(
        self,
        stderr: str,
        category: Literal["validation", "permission", "git", "timeout", "unknown"],
        command: list[str]
    ) -> str:
        """
        Generate user-friendly error message with recovery steps

        Args:
            stderr: Standard error output
            category: Error category
            command: Executed command

        Returns:
            User-friendly error message
        """
        if category == "validation":
            return self._handle_validation_error(stderr, command)
        elif category == "permission":
            return self._handle_permission_error(stderr, command)
        elif category == "git":
            return self._handle_git_error(stderr, command)
        elif category == "timeout":
            return f"Command timed out. Try again or check for hanging processes."
        else:
            return f"Command failed with unexpected error. Check logs for details:\n{stderr[:200]}"

    def _handle_validation_error(self, stderr: str, command: list[str]) -> str:
        """Generate message for validation errors"""
        stderr_lower = stderr.lower()

        if "already exists" in stderr_lower:
            if "project" in " ".join(command).lower():
                return "A project with this name already exists. Choose a different name."
            elif "worktree" in " ".join(command).lower():
                return "A worktree at this path already exists. Choose a different path or delete the existing worktree."
            else:
                return "Resource already exists. Choose a different name or path."

        if "not found" in stderr_lower or "does not exist" in stderr_lower:
            if "branch" in stderr_lower:
                return "Branch not found in repository. Create the branch first or choose an existing branch."
            elif "project" in stderr_lower:
                return "Project not found. Verify the project name is correct."
            elif "directory" in stderr_lower or "path" in stderr_lower:
                return "Directory not found. Ensure the path exists and is accessible."
            else:
                return "Resource not found. Verify the name or path is correct."

        if "invalid" in stderr_lower:
            if "name" in stderr_lower:
                return "Invalid name format. Use lowercase letters, numbers, hyphens, and dots only."
            elif "path" in stderr_lower:
                return "Invalid path format. Use absolute paths starting with /."
            elif "branch" in stderr_lower:
                return "Invalid branch name. Branch names cannot contain spaces or special characters."
            else:
                return "Invalid input format. Check the field requirements and try again."

        # Generic validation error
        return f"Validation error: {stderr[:150]}"

    def _handle_permission_error(self, stderr: str, command: list[str]) -> str:
        """Generate message for permission errors"""
        if "sudo" in stderr.lower() or "must be root" in stderr.lower():
            return "This operation requires root privileges. Try running with sudo or ensure you have permission."

        if "write" in stderr.lower() or "create" in stderr.lower():
            return "Cannot write to this location. Check file/directory permissions or choose a different path."

        return f"Permission denied. Ensure you have access to the required files and directories:\n{stderr[:150]}"

    def _handle_git_error(self, stderr: str, command: list[str]) -> str:
        """Generate message for Git errors"""
        stderr_lower = stderr.lower()

        if "branch" in stderr_lower and "not found" in stderr_lower:
            # Extract branch name from stderr if possible
            match = re.search(r"'([^']+)'", stderr)
            branch_name = match.group(1) if match else "specified branch"

            return (
                f"Branch '{branch_name}' not found in repository.\n\n"
                f"Recovery steps:\n"
                f"1. List available branches: git branch -a\n"
                f"2. Create the branch: git branch {branch_name}\n"
                f"3. Or choose an existing branch"
            )

        if "worktree" in stderr_lower and "already exists" in stderr_lower:
            return (
                "Worktree path already exists or is in use.\n\n"
                "Recovery steps:\n"
                "1. Remove existing worktree: git worktree remove <path>\n"
                "2. Or choose a different path"
            )

        if "not a git repository" in stderr_lower:
            return (
                "Not a Git repository.\n\n"
                "Recovery steps:\n"
                "1. Initialize repository: git init\n"
                "2. Or verify you're in the correct directory"
            )

        # Generic Git error
        return f"Git command failed:\n{stderr[:200]}"
