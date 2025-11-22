"""
Feature 087: Remote Project Environment Support
Integration tests for remote project creation via CLI

Tests cover:
- Successful project creation via create-remote command
- Validation of missing required fields
- Rejection of relative paths for remote working directory
- Verification of JSON file creation with correct structure
"""

import pytest
import subprocess
import json
from pathlib import Path
import tempfile
import shutil


class TestRemoteProjectCreation:
    """Integration tests for create-remote CLI command."""

    @pytest.fixture
    def temp_dir(self):
        """Create temporary directory for test projects."""
        tmpdir = tempfile.mkdtemp()
        yield tmpdir
        shutil.rmtree(tmpdir, ignore_errors=True)

    @pytest.fixture
    def config_dir(self):
        """Create temporary config directory."""
        tmpdir = tempfile.mkdtemp()
        yield Path(tmpdir)
        shutil.rmtree(tmpdir, ignore_errors=True)

    @pytest.fixture
    def cli_path(self):
        """Get path to CLI main.ts."""
        return Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "i3pm-cli" / "main.ts"

    def run_cli(self, cli_path: Path, args: list, env: dict = None) -> subprocess.CompletedProcess:
        """Run CLI command and return result."""
        # Use full deno path from NixOS
        deno_path = "/run/current-system/sw/bin/deno"
        cmd = [deno_path, "run", "--allow-read", "--allow-write", "--allow-env", str(cli_path)] + args
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env
        )

    def test_successful_project_creation(self, cli_path, temp_dir, config_dir):
        """Test successful creation of remote project."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "test-project",
                "--local-dir", temp_dir,
                "--remote-host", "hetzner-sway.tailnet",
                "--remote-user", "vpittamp",
                "--remote-dir", "/home/vpittamp/dev/app"
            ],
            env=env
        )

        assert result.returncode == 0, f"Failed with: {result.stderr}"
        assert "Created remote project 'test-project'" in result.stdout

        # Verify JSON file created
        project_file = config_dir / ".config" / "i3" / "projects" / "test-project.json"
        assert project_file.exists()

        # Verify JSON structure
        with open(project_file) as f:
            project_data = json.load(f)

        assert project_data["name"] == "test-project"
        assert project_data["directory"] == temp_dir
        assert project_data["remote"]["enabled"] is True
        assert project_data["remote"]["host"] == "hetzner-sway.tailnet"
        assert project_data["remote"]["user"] == "vpittamp"
        assert project_data["remote"]["working_dir"] == "/home/vpittamp/dev/app"
        assert project_data["remote"]["port"] == 22

    def test_custom_port(self, cli_path, temp_dir, config_dir):
        """Test project creation with custom SSH port."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "test-custom-port",
                "--local-dir", temp_dir,
                "--remote-host", "192.168.1.100",
                "--remote-user", "deploy",
                "--remote-dir", "/opt/app",
                "--port", "2222"
            ],
            env=env
        )

        assert result.returncode == 0

        # Verify custom port in JSON
        project_file = config_dir / ".config" / "i3" / "projects" / "test-custom-port.json"
        with open(project_file) as f:
            project_data = json.load(f)

        assert project_data["remote"]["port"] == 2222

    def test_missing_required_field_host(self, cli_path, temp_dir, config_dir):
        """Test validation fails when host is missing."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "test-missing-host",
                "--local-dir", temp_dir,
                "--remote-user", "user",
                "--remote-dir", "/home/user"
            ],
            env=env
        )

        assert result.returncode == 1
        assert "Missing required flags" in result.stderr
        assert "remote-host" in result.stderr

    def test_missing_required_field_user(self, cli_path, temp_dir, config_dir):
        """Test validation fails when user is missing."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "test-missing-user",
                "--local-dir", temp_dir,
                "--remote-host", "host.example.com",
                "--remote-dir", "/home/user"
            ],
            env=env
        )

        assert result.returncode == 1
        assert "Missing required flags" in result.stderr
        assert "remote-user" in result.stderr

    def test_missing_required_field_working_dir(self, cli_path, temp_dir, config_dir):
        """Test validation fails when working_dir is missing."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "test-missing-dir",
                "--local-dir", temp_dir,
                "--remote-host", "host.example.com",
                "--remote-user", "user"
            ],
            env=env
        )

        assert result.returncode == 1
        assert "Missing required flags" in result.stderr
        assert "remote-dir" in result.stderr

    def test_relative_path_rejected(self, cli_path, temp_dir, config_dir):
        """Test validation fails when remote working_dir is relative path."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "test-relative",
                "--local-dir", temp_dir,
                "--remote-host", "host.example.com",
                "--remote-user", "user",
                "--remote-dir", "relative/path"
            ],
            env=env
        )

        assert result.returncode == 1
        assert "absolute path" in result.stderr.lower()

    def test_local_dir_not_exists(self, cli_path, config_dir):
        """Test validation fails when local directory doesn't exist."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "test-no-local",
                "--local-dir", "/nonexistent/path",
                "--remote-host", "host.example.com",
                "--remote-user", "user",
                "--remote-dir", "/home/user"
            ],
            env=env
        )

        assert result.returncode == 1
        assert "does not exist" in result.stderr

    def test_duplicate_project_rejected(self, cli_path, temp_dir, config_dir):
        """Test cannot create project with duplicate name."""
        env = {"HOME": str(config_dir)}

        # Create first project
        result1 = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "duplicate-test",
                "--local-dir", temp_dir,
                "--remote-host", "host.example.com",
                "--remote-user", "user",
                "--remote-dir", "/home/user"
            ],
            env=env
        )
        assert result1.returncode == 0

        # Try to create duplicate
        result2 = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "duplicate-test",
                "--local-dir", temp_dir,
                "--remote-host", "host.example.com",
                "--remote-user", "user",
                "--remote-dir", "/home/user"
            ],
            env=env
        )
        assert result2.returncode == 1
        assert "already exists" in result2.stderr

    def test_display_name_and_icon(self, cli_path, temp_dir, config_dir):
        """Test custom display name and icon."""
        env = {"HOME": str(config_dir)}

        result = self.run_cli(
            cli_path,
            [
                "project", "create-remote", "custom-display",
                "--local-dir", temp_dir,
                "--remote-host", "host.example.com",
                "--remote-user", "user",
                "--remote-dir", "/home/user",
                "--display-name", "My Custom Project",
                "--icon", "🚀"
            ],
            env=env
        )

        assert result.returncode == 0

        # Verify custom values in JSON
        project_file = config_dir / ".config" / "i3" / "projects" / "custom-display.json"
        with open(project_file) as f:
            project_data = json.load(f)

        assert project_data["display_name"] == "My Custom Project"
        assert project_data["icon"] == "🚀"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
