"""
Feature 087: Remote Project Environment Support
Unit tests for RemoteConfig validation

Tests cover:
- Absolute path validation for working_dir
- Port range validation (1-65535)
- Missing required fields (host, user, working_dir)
- Backward compatibility (loading old JSON without remote field)
"""

import pytest
from pydantic import ValidationError
from pathlib import Path
import json
import sys

# Add parent directory to path to import models
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"))

from models import RemoteConfig, Project


class TestRemoteConfigValidation:
    """Test RemoteConfig Pydantic model validation."""

    def test_valid_minimal_config(self):
        """Test minimal valid remote configuration."""
        config = RemoteConfig(
            enabled=True,
            host="hetzner-sway.tailnet",
            user="vpittamp",
            working_dir="/home/vpittamp/dev/app"
        )
        assert config.enabled is True
        assert config.host == "hetzner-sway.tailnet"
        assert config.user == "vpittamp"
        assert config.working_dir == "/home/vpittamp/dev/app"
        assert config.port == 22  # Default port

    def test_valid_custom_port(self):
        """Test remote config with custom SSH port."""
        config = RemoteConfig(
            enabled=True,
            host="192.168.1.100",
            user="deploy",
            working_dir="/opt/app",
            port=2222
        )
        assert config.port == 2222

    def test_disabled_remote_config(self):
        """Test remote config with enabled=False."""
        config = RemoteConfig(
            enabled=False,
            host="example.com",
            user="user",
            working_dir="/home/user"
        )
        assert config.enabled is False

    def test_absolute_path_validation_pass(self):
        """Test working_dir must be absolute path (pass)."""
        config = RemoteConfig(
            enabled=True,
            host="host",
            user="user",
            working_dir="/absolute/path"
        )
        assert config.working_dir == "/absolute/path"

    def test_absolute_path_validation_fail(self):
        """Test working_dir must be absolute path (fail on relative)."""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="host",
                user="user",
                working_dir="relative/path"
            )
        error = exc_info.value.errors()[0]
        assert "absolute path" in error["msg"].lower()

    def test_missing_host(self):
        """Test validation fails when host is missing."""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                user="user",
                working_dir="/home/user"
            )
        errors = exc_info.value.errors()
        assert any(err["loc"] == ("host",) for err in errors)

    def test_missing_user(self):
        """Test validation fails when user is missing."""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="host",
                working_dir="/home/user"
            )
        errors = exc_info.value.errors()
        assert any(err["loc"] == ("user",) for err in errors)

    def test_missing_working_dir(self):
        """Test validation fails when working_dir is missing."""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="host",
                user="user"
            )
        errors = exc_info.value.errors()
        assert any(err["loc"] == ("working_dir",) for err in errors)

    def test_port_range_validation_min(self):
        """Test port must be >= 1."""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="host",
                user="user",
                working_dir="/path",
                port=0
            )
        error = exc_info.value.errors()[0]
        assert error["loc"] == ("port",)

    def test_port_range_validation_max(self):
        """Test port must be <= 65535."""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="host",
                user="user",
                working_dir="/path",
                port=100000
            )
        error = exc_info.value.errors()[0]
        assert error["loc"] == ("port",)

    def test_to_ssh_host_default_port(self):
        """Test to_ssh_host() method with default port 22."""
        config = RemoteConfig(
            enabled=True,
            host="hetzner-sway.tailnet",
            user="vpittamp",
            working_dir="/home/vpittamp/dev"
        )
        assert config.to_ssh_host() == "vpittamp@hetzner-sway.tailnet"

    def test_to_ssh_host_custom_port(self):
        """Test to_ssh_host() method with custom port."""
        config = RemoteConfig(
            enabled=True,
            host="192.168.1.100",
            user="deploy",
            working_dir="/opt/app",
            port=2222
        )
        assert config.to_ssh_host() == "deploy@192.168.1.100:2222"


class TestProjectRemoteField:
    """Test Project model with optional remote field."""

    def test_project_without_remote(self, tmp_path):
        """Test project creation without remote field (backward compatibility)."""
        project = Project(
            name="local-project",
            directory=str(tmp_path),
            display_name="Local Project"
        )
        assert project.remote is None
        assert project.is_remote() is False
        assert project.get_effective_directory() == str(tmp_path)

    def test_project_with_remote_enabled(self, tmp_path):
        """Test project with remote configuration enabled."""
        project = Project(
            name="remote-project",
            directory=str(tmp_path),
            display_name="Remote Project",
            remote=RemoteConfig(
                enabled=True,
                host="hetzner-sway.tailnet",
                user="vpittamp",
                working_dir="/home/vpittamp/dev/app"
            )
        )
        assert project.is_remote() is True
        assert project.get_effective_directory() == "/home/vpittamp/dev/app"

    def test_project_with_remote_disabled(self, tmp_path):
        """Test project with remote config but enabled=False."""
        project = Project(
            name="mixed-project",
            directory=str(tmp_path),
            display_name="Mixed Project",
            remote=RemoteConfig(
                enabled=False,
                host="host",
                user="user",
                working_dir="/remote/path"
            )
        )
        assert project.is_remote() is False
        assert project.get_effective_directory() == str(tmp_path)

    def test_backward_compatibility_json_loading(self, tmp_path):
        """Test loading old project JSON without remote field."""
        # Create old-style project JSON
        project_data = {
            "name": "old-project",
            "directory": str(tmp_path),
            "display_name": "Old Project",
            "icon": "📁",
            "created_at": "2025-11-22T10:00:00.000Z",
            "updated_at": "2025-11-22T10:00:00.000Z",
            "scoped_classes": []
        }

        # Save to file
        config_dir = tmp_path / ".config" / "i3"
        config_dir.mkdir(parents=True)
        projects_dir = config_dir / "projects"
        projects_dir.mkdir()

        project_file = projects_dir / "old-project.json"
        with open(project_file, 'w') as f:
            json.dump(project_data, f)

        # Load project
        project = Project.load_from_file(config_dir, "old-project")

        # Verify no remote field
        assert project.remote is None
        assert project.is_remote() is False

    def test_remote_project_json_roundtrip(self, tmp_path):
        """Test saving and loading remote project preserves configuration."""
        # Create remote project
        project = Project(
            name="remote-test",
            directory=str(tmp_path),
            display_name="Remote Test",
            remote=RemoteConfig(
                enabled=True,
                host="hetzner-sway.tailnet",
                user="vpittamp",
                working_dir="/home/vpittamp/dev/test",
                port=2222
            )
        )

        # Save to file
        config_dir = tmp_path / ".config" / "i3"
        config_dir.mkdir(parents=True)
        project.save_to_file(config_dir)

        # Load from file
        loaded_project = Project.load_from_file(config_dir, "remote-test")

        # Verify all fields preserved
        assert loaded_project.is_remote() is True
        assert loaded_project.remote.host == "hetzner-sway.tailnet"
        assert loaded_project.remote.user == "vpittamp"
        assert loaded_project.remote.working_dir == "/home/vpittamp/dev/test"
        assert loaded_project.remote.port == 2222
        assert loaded_project.get_effective_directory() == "/home/vpittamp/dev/test"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
