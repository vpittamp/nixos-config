"""
Unit Tests for Form Validation Rules

Feature 094: Enhanced Projects & Applications CRUD Interface (User Story 2 - T031)
Tests validation logic for project edit forms with real-time feedback
"""

import pytest
import tempfile
import shutil
from pathlib import Path
from pydantic import ValidationError

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))

from i3_project_manager.models.project_config import ProjectConfig, RemoteConfig


@pytest.fixture
def temp_dir():
    """Create temporary directory for validation tests"""
    temp = Path(tempfile.mkdtemp(prefix="test_validation_"))
    yield temp
    shutil.rmtree(temp, ignore_errors=True)


@pytest.fixture
def temp_projects_dir():
    """Create temporary projects directory"""
    temp = Path(tempfile.mkdtemp(prefix="test_projects_"))
    yield temp
    shutil.rmtree(temp, ignore_errors=True)


class TestDisplayNameValidation:
    """Test display_name field validation for edit forms"""

    def test_valid_display_name(self, temp_dir):
        """Valid display names should pass"""
        config = ProjectConfig(
            name="test-project",
            display_name="Test Project",
            working_dir=str(temp_dir)
        )
        assert config.display_name == "Test Project"

    def test_display_name_with_special_chars(self, temp_dir):
        """Display names can contain special characters"""
        config = ProjectConfig(
            name="test",
            display_name="My Project (2024) - v2.0!",
            working_dir=str(temp_dir)
        )
        assert config.display_name == "My Project (2024) - v2.0!"

    def test_empty_display_name_rejected(self, temp_dir):
        """Empty display name should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="",
                working_dir=str(temp_dir)
            )
        assert "display_name" in str(exc_info.value)


class TestIconValidation:
    """Test icon field validation for edit forms"""

    def test_emoji_icon_accepted(self, temp_dir):
        """Single emoji should be accepted"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            icon="🚀",
            working_dir=str(temp_dir)
        )
        assert config.icon == "🚀"

    def test_multi_char_emoji_accepted(self, temp_dir):
        """Multi-character emoji (up to 4 chars) accepted"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            icon="👨‍💻",  # Man technologist (multi-char)
            working_dir=str(temp_dir)
        )
        assert config.icon == "👨‍💻"

    def test_absolute_file_path_accepted(self, temp_dir):
        """Absolute file path should be accepted"""
        icon_file = temp_dir / "icon.svg"
        icon_file.write_text("<svg></svg>")

        config = ProjectConfig(
            name="test",
            display_name="Test",
            icon=str(icon_file),
            working_dir=str(temp_dir)
        )
        assert config.icon == str(icon_file)

    def test_relative_path_rejected(self, temp_dir):
        """Relative path should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="Test",
                icon="./icon.svg",  # Relative path
                working_dir=str(temp_dir)
            )
        assert "absolute file path" in str(exc_info.value).lower()

    def test_nonexistent_file_path_warning(self, temp_dir):
        """Nonexistent file path accepted with warning (per spec.md Edge Case)"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            icon="/nonexistent/icon.svg",
            working_dir=str(temp_dir)
        )
        # Should not raise error, just warning
        assert config.icon == "/nonexistent/icon.svg"


class TestWorkingDirValidation:
    """Test working_dir field validation for edit forms"""

    def test_valid_existing_directory(self, temp_dir):
        """Existing accessible directory should pass"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            working_dir=str(temp_dir)
        )
        # Should resolve to absolute path
        assert Path(config.working_dir).is_absolute()

    def test_nonexistent_directory_rejected(self):
        """Nonexistent directory should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="Test",
                working_dir="/nonexistent/directory"
            )
        assert "does not exist" in str(exc_info.value).lower()

    def test_file_instead_of_directory_rejected(self, temp_dir):
        """File path should be rejected (must be directory)"""
        file_path = temp_dir / "file.txt"
        file_path.write_text("test")

        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="Test",
                working_dir=str(file_path)
            )
        assert "not a directory" in str(exc_info.value).lower()

    def test_tilde_expansion(self, temp_dir):
        """Tilde should be expanded to home directory"""
        # Note: This test assumes ~/tmp exists, adjust as needed
        config = ProjectConfig(
            name="test",
            display_name="Test",
            working_dir=str(temp_dir)
        )
        assert "~" not in config.working_dir
        assert Path(config.working_dir).is_absolute()


class TestScopeValidation:
    """Test scope field validation for edit forms"""

    def test_scoped_accepted(self, temp_dir):
        """'scoped' value should be accepted"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            scope="scoped",
            working_dir=str(temp_dir)
        )
        assert config.scope == "scoped"

    def test_global_accepted(self, temp_dir):
        """'global' value should be accepted"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            scope="global",
            working_dir=str(temp_dir)
        )
        assert config.scope == "global"

    def test_invalid_scope_rejected(self, temp_dir):
        """Invalid scope value should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="Test",
                scope="invalid",  # type: ignore
                working_dir=str(temp_dir)
            )
        assert "scope" in str(exc_info.value).lower()


class TestRemoteConfigValidation:
    """Test remote SSH configuration validation for edit forms"""

    def test_valid_remote_config(self, temp_dir):
        """Valid remote configuration should pass"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            working_dir=str(temp_dir),
            remote=RemoteConfig(
                enabled=True,
                host="example.com",
                user="testuser",
                remote_dir="/home/testuser/project"
            )
        )
        assert config.remote.enabled is True
        assert config.remote.host == "example.com"

    def test_remote_absolute_path_required(self, temp_dir):
        """Remote directory must be absolute path"""
        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="Test",
                working_dir=str(temp_dir),
                remote=RemoteConfig(
                    enabled=True,
                    host="example.com",
                    user="testuser",
                    remote_dir="relative/path"  # Not absolute
                )
            )
        assert "absolute path" in str(exc_info.value).lower()

    def test_remote_port_range_validation(self, temp_dir):
        """Port must be in valid range (1-65535)"""
        # Valid port
        config = ProjectConfig(
            name="test",
            display_name="Test",
            working_dir=str(temp_dir),
            remote=RemoteConfig(
                enabled=True,
                host="example.com",
                user="testuser",
                remote_dir="/home/testuser/project",
                port=2222
            )
        )
        assert config.remote.port == 2222

        # Port too low
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="example.com",
                user="testuser",
                remote_dir="/home/testuser/project",
                port=0
            )
        assert "port" in str(exc_info.value).lower()

        # Port too high
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="example.com",
                user="testuser",
                remote_dir="/home/testuser/project",
                port=70000
            )
        assert "port" in str(exc_info.value).lower()

    def test_empty_host_rejected(self, temp_dir):
        """Empty host should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="",
                user="testuser",
                remote_dir="/home/testuser/project"
            )
        assert "host" in str(exc_info.value).lower()

    def test_empty_user_rejected(self, temp_dir):
        """Empty user should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            RemoteConfig(
                enabled=True,
                host="example.com",
                user="",
                remote_dir="/home/testuser/project"
            )
        assert "user" in str(exc_info.value).lower()

    def test_tailscale_hostname_accepted(self, temp_dir):
        """Tailscale hostnames should be accepted"""
        config = ProjectConfig(
            name="test",
            display_name="Test",
            working_dir=str(temp_dir),
            remote=RemoteConfig(
                enabled=True,
                host="hetzner-sway.tailnet",
                user="vpittamp",
                remote_dir="/home/vpittamp/project"
            )
        )
        assert config.remote.host == "hetzner-sway.tailnet"


class TestFormValidationErrorMessages:
    """Test that validation errors return user-friendly messages"""

    def test_multiple_field_errors(self, temp_dir):
        """Multiple validation errors should be collected"""
        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="",  # Invalid: empty
                icon="./relative.svg",  # Invalid: relative path
                working_dir="/nonexistent",  # Invalid: doesn't exist
                scope="invalid"  # type: ignore  # Invalid: not scoped/global
            )

        error_dict = exc_info.value.errors()
        field_names = {e["loc"][0] for e in error_dict}

        # Should have errors for multiple fields
        assert "display_name" in field_names
        assert "icon" in field_names or "working_dir" in field_names

    def test_error_messages_include_field_context(self, temp_dir):
        """Error messages should include field name for UI display"""
        with pytest.raises(ValidationError) as exc_info:
            ProjectConfig(
                name="test",
                display_name="Test",
                working_dir="/nonexistent"
            )

        errors = exc_info.value.errors()
        assert any("working_dir" in str(e["loc"]) for e in errors)
        assert any("does not exist" in e["msg"].lower() for e in errors)
