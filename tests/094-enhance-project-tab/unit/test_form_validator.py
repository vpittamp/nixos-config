"""
Unit Tests for Form Validation Rules

Feature 094: Enhanced Projects & Applications CRUD Interface
- User Story 2 (T031): Tests validation logic for project edit forms
- User Story 7 (T042): Tests validation logic for application edit forms

Tests include workspace ranges, ULID format, URL validation, and command validation
"""

import pytest
import tempfile
import shutil
from pathlib import Path
from pydantic import ValidationError

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))

from i3_project_manager.models.project_config import ProjectConfig, RemoteConfig
from i3_project_manager.models.app_config import ApplicationConfig, TerminalAppConfig, PWAConfig


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


# =============================================================================
# User Story 7 (T042): Application Validation Tests
# =============================================================================


class TestApplicationWorkspaceValidation:
    """Test workspace range validation for regular apps (1-50)"""

    def test_valid_workspace_range(self):
        """Regular apps should accept workspaces 1-50"""
        for ws in [1, 25, 50]:
            config = ApplicationConfig(
                name="test-app",
                display_name="Test App",
                command="testcmd",
                expected_class="TestApp",
                preferred_workspace=ws
            )
            assert config.preferred_workspace == ws

    def test_workspace_below_range_rejected(self):
        """Workspace 0 should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="test-app",
                display_name="Test App",
                command="testcmd",
                expected_class="TestApp",
                preferred_workspace=0
            )
        assert "preferred_workspace" in str(exc_info.value).lower()

    def test_workspace_above_regular_range_rejected(self):
        """Regular apps cannot use workspace 51+ (reserved for PWAs)"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="test-app",
                display_name="Test App",
                command="testcmd",
                expected_class="TestApp",
                preferred_workspace=51
            )
        assert "1-50" in str(exc_info.value)


class TestPWAWorkspaceValidation:
    """Test workspace range validation for PWAs (50+)"""

    def test_pwa_workspace_50_or_higher(self):
        """PWAs should accept workspaces 50+"""
        for ws in [50, 55, 70]:
            config = PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=ws,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="https://example.com",
                scope_url="https://example.com/"
            )
            assert config.preferred_workspace == ws

    def test_pwa_workspace_below_50_rejected(self):
        """PWAs cannot use workspaces 1-49 (reserved for regular apps)"""
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=49,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="https://example.com",
                scope_url="https://example.com/"
            )
        assert "50 or higher" in str(exc_info.value)


class TestULIDFormatValidation:
    """Test ULID format validation (26 chars, Crockford Base32)"""

    def test_valid_ulid_format(self):
        """Valid ULID should be accepted"""
        valid_ulids = [
            "01JCYF8Z2M0N3P4Q5R6S7T8V9W",  # Standard ULID
            "01ARZ3NDEKTSV4RRFFQ69G5FAV",  # Example from spec
            "01HQWX9Y7Z0123456789ABCDEF",  # Another valid ULID
        ]
        for ulid in valid_ulids:
            config = PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", ulid],
                expected_class=f"FFPWA-{ulid}",
                preferred_workspace=50,
                ulid=ulid,
                start_url="https://example.com",
                scope_url="https://example.com/"
            )
            assert config.ulid == ulid

    def test_ulid_wrong_length_rejected(self):
        """ULID must be exactly 26 characters"""
        # Too short
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", "SHORT"],
                expected_class="FFPWA-SHORT",
                preferred_workspace=50,
                ulid="SHORT",  # Only 5 characters
                start_url="https://example.com",
                scope_url="https://example.com/"
            )
        assert "26" in str(exc_info.value)

        # Too long
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9WEXTRA"],
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9WEXTRA",
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9WEXTRA",  # 31 characters
                start_url="https://example.com",
                scope_url="https://example.com/"
            )
        assert "26" in str(exc_info.value)

    def test_ulid_invalid_characters_rejected(self):
        """ULID must use Crockford Base32 alphabet (excludes I, L, O, U)"""
        invalid_ulids = [
            "01JCYF8Z2M0N3P4Q5R6S7T8VIL",  # Contains I and L
            "01JCYF8Z2M0N3P4Q5R6S7T8VOU",  # Contains O and U
            "01JCYF8Z2M0N3P4Q5R6S7T8V9!",  # Contains special char
            "01jcyf8z2m0n3p4q5r6s7t8v9w",  # Lowercase (invalid)
        ]
        for invalid_ulid in invalid_ulids:
            with pytest.raises(ValidationError):
                PWAConfig(
                    name="test-pwa",
                    display_name="Test PWA",
                    command="firefoxpwa",
                    parameters=["site", "launch", invalid_ulid],
                    expected_class=f"FFPWA-{invalid_ulid}",
                    preferred_workspace=50,
                    ulid=invalid_ulid,
                    start_url="https://example.com",
                    scope_url="https://example.com/"
                )

    def test_ulid_first_char_timestamp_validation(self):
        """ULID first character must be 0-7 (timestamp constraint)"""
        # Valid: First char 0-7
        for first_char in "01234567":
            ulid = f"{first_char}1JCYF8Z2M0N3P4Q5R6S7T8V9W"
            config = PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", ulid],
                expected_class=f"FFPWA-{ulid}",
                preferred_workspace=50,
                ulid=ulid,
                start_url="https://example.com",
                scope_url="https://example.com/"
            )
            assert config.ulid[0] == first_char

        # Invalid: First char 8-9 or A-Z
        for first_char in "89ABCDEFGHJKMNPQRSTVWXYZ":
            ulid = f"{first_char}1JCYF8Z2M0N3P4Q5R6S7T8V9W"
            with pytest.raises(ValidationError) as exc_info:
                PWAConfig(
                    name="test-pwa",
                    display_name="Test PWA",
                    command="firefoxpwa",
                    parameters=["site", "launch", ulid],
                    expected_class=f"FFPWA-{ulid}",
                    preferred_workspace=50,
                    ulid=ulid,
                    start_url="https://example.com",
                    scope_url="https://example.com/"
                )
            assert "first char 0-7" in str(exc_info.value)


class TestURLValidation:
    """Test URL format validation for PWAs"""

    def test_valid_http_url(self):
        """HTTP URLs should be accepted"""
        config = PWAConfig(
            name="test-pwa",
            display_name="Test PWA",
            command="firefoxpwa",
            parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
            expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            preferred_workspace=50,
            ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            start_url="http://example.com",
            scope_url="http://example.com/"
        )
        assert config.start_url == "http://example.com"

    def test_valid_https_url(self):
        """HTTPS URLs should be accepted"""
        config = PWAConfig(
            name="test-pwa",
            display_name="Test PWA",
            command="firefoxpwa",
            parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
            expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            preferred_workspace=50,
            ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            start_url="https://example.com/app",
            scope_url="https://example.com/"
        )
        assert config.start_url == "https://example.com/app"

    def test_url_with_port_accepted(self):
        """URLs with port numbers should be accepted"""
        config = PWAConfig(
            name="test-pwa",
            display_name="Test PWA",
            command="firefoxpwa",
            parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
            expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            preferred_workspace=50,
            ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            start_url="https://localhost:3000",
            scope_url="https://localhost:3000/"
        )
        assert config.start_url == "https://localhost:3000"

    def test_url_without_scheme_rejected(self):
        """URLs without http:// or https:// should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="example.com",  # Missing scheme
                scope_url="https://example.com/"
            )
        assert "http://" in str(exc_info.value).lower() or "https://" in str(exc_info.value).lower()

    def test_invalid_scheme_rejected(self):
        """URLs with non-HTTP schemes should be rejected"""
        with pytest.raises(ValidationError):
            PWAConfig(
                name="test-pwa",
                display_name="Test PWA",
                command="firefoxpwa",
                parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="ftp://example.com",  # FTP not allowed
                scope_url="https://example.com/"
            )


class TestApplicationNameValidation:
    """Test application name format validation"""

    def test_valid_lowercase_name(self):
        """Lowercase alphanumeric names should be accepted"""
        config = ApplicationConfig(
            name="firefox",
            display_name="Firefox",
            command="firefox",
            expected_class="firefox",
            preferred_workspace=3
        )
        assert config.name == "firefox"

    def test_name_with_hyphens_accepted(self):
        """Names with hyphens should be accepted"""
        config = ApplicationConfig(
            name="google-chrome",
            display_name="Google Chrome",
            command="google-chrome",
            expected_class="Google-chrome",
            preferred_workspace=3
        )
        assert config.name == "google-chrome"

    def test_name_with_dots_accepted(self):
        """Names with dots should be accepted (e.g., org.example.app)"""
        config = ApplicationConfig(
            name="org.mozilla.firefox",
            display_name="Firefox",
            command="firefox",
            expected_class="firefox",
            preferred_workspace=3
        )
        assert config.name == "org.mozilla.firefox"

    def test_uppercase_name_rejected(self):
        """Uppercase characters should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="Firefox",  # Uppercase not allowed
                display_name="Firefox",
                command="firefox",
                expected_class="firefox",
                preferred_workspace=3
            )
        assert "lowercase" in str(exc_info.value).lower()

    def test_name_with_spaces_rejected(self):
        """Spaces in name should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="my app",  # Spaces not allowed
                display_name="My App",
                command="myapp",
                expected_class="MyApp",
                preferred_workspace=3
            )
        assert "name" in str(exc_info.value).lower()

    def test_pwa_name_suffix_required(self):
        """PWA names must end with '-pwa'"""
        # Valid PWA name
        config = PWAConfig(
            name="youtube-pwa",
            display_name="YouTube",
            command="firefoxpwa",
            parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
            expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            preferred_workspace=50,
            ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            start_url="https://youtube.com",
            scope_url="https://youtube.com/"
        )
        assert config.name.endswith("-pwa")

        # Invalid: Missing -pwa suffix
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="youtube",  # Missing -pwa suffix
                display_name="YouTube",
                command="firefoxpwa",
                parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="https://youtube.com",
                scope_url="https://youtube.com/"
            )
        assert "-pwa" in str(exc_info.value)


class TestCommandValidation:
    """Test command field validation (no shell metacharacters)"""

    def test_simple_command_accepted(self):
        """Simple command without arguments should be accepted"""
        config = ApplicationConfig(
            name="firefox",
            display_name="Firefox",
            command="firefox",
            expected_class="firefox",
            preferred_workspace=3
        )
        assert config.command == "firefox"

    def test_command_with_path_accepted(self):
        """Command with path should be accepted"""
        config = ApplicationConfig(
            name="custom-app",
            display_name="Custom App",
            command="/usr/local/bin/myapp",
            expected_class="MyApp",
            preferred_workspace=3
        )
        assert config.command == "/usr/local/bin/myapp"

    def test_command_with_semicolon_rejected(self):
        """Command with semicolon should be rejected (shell injection risk)"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="bad-app",
                display_name="Bad App",
                command="firefox; rm -rf /",  # Command injection attempt
                expected_class="firefox",
                preferred_workspace=3
            )
        assert "metacharacter" in str(exc_info.value).lower()

    def test_command_with_pipe_rejected(self):
        """Command with pipe should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="bad-app",
                display_name="Bad App",
                command="cat /etc/passwd | grep root",  # Piping not allowed
                expected_class="cat",
                preferred_workspace=3
            )
        assert "metacharacter" in str(exc_info.value).lower()

    def test_command_with_ampersand_rejected(self):
        """Command with ampersand should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="bad-app",
                display_name="Bad App",
                command="firefox && malware",  # Command chaining not allowed
                expected_class="firefox",
                preferred_workspace=3
            )
        assert "metacharacter" in str(exc_info.value).lower()

    def test_command_with_backtick_rejected(self):
        """Command with backtick should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="bad-app",
                display_name="Bad App",
                command="echo `whoami`",  # Command substitution not allowed
                expected_class="echo",
                preferred_workspace=3
            )
        assert "metacharacter" in str(exc_info.value).lower()

    def test_command_with_dollar_rejected(self):
        """Command with dollar sign should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="bad-app",
                display_name="Bad App",
                command="echo $(whoami)",  # Command substitution not allowed
                expected_class="echo",
                preferred_workspace=3
            )
        assert "metacharacter" in str(exc_info.value).lower()


class TestTerminalAppValidation:
    """Test terminal app specific validation"""

    def test_valid_terminal_app(self):
        """Valid terminal app configuration should be accepted"""
        config = TerminalAppConfig(
            name="terminal",
            display_name="Terminal",
            command="ghostty",
            parameters=["-e", "bash"],
            expected_class="ghostty",
            preferred_workspace=1,
            scope="scoped"
        )
        assert config.terminal is True
        assert config.command == "ghostty"

    def test_terminal_app_valid_commands(self):
        """Terminal apps should only accept specific terminal emulators"""
        valid_terminals = ["ghostty", "alacritty", "kitty", "wezterm"]
        for term in valid_terminals:
            config = TerminalAppConfig(
                name="terminal",
                display_name="Terminal",
                command=term,
                expected_class=term,
                preferred_workspace=1
            )
            assert config.command == term

    def test_terminal_app_invalid_command_rejected(self):
        """Terminal apps with invalid command should be rejected"""
        with pytest.raises(ValidationError) as exc_info:
            TerminalAppConfig(
                name="terminal",
                display_name="Terminal",
                command="firefox",  # Not a terminal emulator
                expected_class="firefox",
                preferred_workspace=1
            )
        assert "command" in str(exc_info.value).lower()
