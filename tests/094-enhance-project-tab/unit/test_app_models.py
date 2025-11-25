"""
Unit tests for ApplicationConfig models (Feature 094 - T025)

Tests verify:
1. Regular ApplicationConfig validation
2. TerminalAppConfig validation
3. PWAConfig validation (ULID format, workspace 50+, URL validation)
"""

import pytest
from pydantic import ValidationError

from i3_project_manager.models.app_config import (
    ApplicationConfig,
    TerminalAppConfig,
    PWAConfig,
)


class TestApplicationConfig:
    """Unit tests for base ApplicationConfig model."""

    def test_valid_regular_app_config(self):
        """Test that valid regular application config passes validation."""
        config = ApplicationConfig(
            name="firefox",
            display_name="Firefox",
            command="firefox",
            parameters=[],
            scope="global",
            expected_class="firefox",
            preferred_workspace=3,
            icon="firefox",
            nix_package="pkgs.firefox",
            terminal=False,
        )

        assert config.name == "firefox"
        assert config.display_name == "Firefox"
        assert config.command == "firefox"
        assert config.preferred_workspace == 3
        assert config.scope == "global"
        assert config.terminal is False

    def test_name_validation_lowercase_only(self):
        """Test that application name must be lowercase."""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="FireFox",  # Uppercase not allowed
                display_name="Firefox",
                command="firefox",
                expected_class="firefox",
                preferred_workspace=3,
            )

        assert "lowercase alphanumeric" in str(exc_info.value)

    def test_name_validation_no_spaces(self):
        """Test that application name cannot contain spaces."""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="my app",  # Spaces not allowed
                display_name="My App",
                command="myapp",
                expected_class="myapp",
                preferred_workspace=3,
            )

        assert "lowercase alphanumeric" in str(exc_info.value)

    def test_command_validation_no_shell_metacharacters(self):
        """Test that command cannot contain shell metacharacters (FR-A-009)."""
        dangerous_chars = [';', '|', '&', '`', '$']

        for char in dangerous_chars:
            with pytest.raises(ValidationError) as exc_info:
                ApplicationConfig(
                    name="test-app",
                    display_name="Test App",
                    command=f"command{char}injection",
                    expected_class="test",
                    preferred_workspace=3,
                )

            assert "dangerous metacharacter" in str(exc_info.value)

    def test_workspace_range_validation_regular_apps(self):
        """Test that regular apps must use workspaces 1-50 (FR-A-007)."""
        # Test lower bound
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="test-app",
                display_name="Test",
                command="test",
                expected_class="test",
                preferred_workspace=0,  # Too low
            )

        assert "greater than or equal to 1" in str(exc_info.value) or "1-50" in str(exc_info.value)

        # Test upper bound
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="test-app",
                display_name="Test",
                command="test",
                expected_class="test",
                preferred_workspace=51,  # Too high for regular apps
            )

        assert "1-50" in str(exc_info.value) or "less than or equal to 50" in str(exc_info.value)

    def test_floating_size_requires_floating_enabled(self):
        """Test that floating_size can only be set when floating=True (Edge Case)."""
        with pytest.raises(ValidationError) as exc_info:
            ApplicationConfig(
                name="test-app",
                display_name="Test",
                command="test",
                expected_class="test",
                preferred_workspace=3,
                floating=False,
                floating_size="medium",  # Invalid without floating=True
            )

        assert "floating_size can only be set when floating=True" in str(exc_info.value)

    def test_valid_floating_window_config(self):
        """Test that floating window with size is valid."""
        config = ApplicationConfig(
            name="test-app",
            display_name="Test",
            command="test",
            expected_class="test",
            preferred_workspace=3,
            floating=True,
            floating_size="medium",
        )

        assert config.floating is True
        assert config.floating_size == "medium"

    def test_monitor_role_validation(self):
        """Test that preferred_monitor_role accepts valid roles."""
        for role in ["primary", "secondary", "tertiary"]:
            config = ApplicationConfig(
                name="test-app",
                display_name="Test",
                command="test",
                expected_class="test",
                preferred_workspace=3,
                preferred_monitor_role=role,
            )

            assert config.preferred_monitor_role == role


class TestTerminalAppConfig:
    """Unit tests for TerminalAppConfig model."""

    def test_valid_terminal_app_config(self):
        """Test that valid terminal app config passes validation."""
        config = TerminalAppConfig(
            name="terminal",
            display_name="Terminal",
            command="ghostty",
            parameters=["-e", "sesh", "connect", "$PROJECT_DIR"],
            scope="scoped",
            expected_class="com.mitchellh.ghostty",
            preferred_workspace=1,
            icon="🖥️",
            nix_package="pkgs.ghostty",
            multi_instance=True,
            terminal=True,
        )

        assert config.name == "terminal"
        assert config.terminal is True
        assert config.command == "ghostty"
        assert config.scope == "scoped"

    def test_terminal_flag_defaults_to_true(self):
        """Test that terminal flag defaults to True for TerminalAppConfig."""
        config = TerminalAppConfig(
            name="terminal",
            display_name="Terminal",
            command="ghostty",
            expected_class="ghostty",
            preferred_workspace=1,
        )

        assert config.terminal is True

    def test_terminal_command_validation(self):
        """Test that command must be a valid terminal emulator."""
        valid_terminals = ["ghostty", "alacritty", "kitty", "wezterm"]

        for terminal in valid_terminals:
            config = TerminalAppConfig(
                name="test-terminal",
                display_name="Test Terminal",
                command=terminal,
                expected_class=terminal,
                preferred_workspace=1,
            )

            assert config.command == terminal

    def test_invalid_terminal_command_rejected(self):
        """Test that non-terminal commands are rejected."""
        with pytest.raises(ValidationError) as exc_info:
            TerminalAppConfig(
                name="fake-terminal",
                display_name="Fake",
                command="firefox",  # Not a terminal emulator
                expected_class="firefox",
                preferred_workspace=1,
            )

        # Should fail because firefox is not in the allowed terminal emulator list
        assert "Input should be 'ghostty'" in str(exc_info.value) or "Input should be" in str(exc_info.value)


class TestPWAConfig:
    """Unit tests for PWAConfig model."""

    def test_valid_pwa_config(self):
        """Test that valid PWA config passes validation."""
        config = PWAConfig(
            name="youtube-pwa",
            display_name="YouTube",
            command="firefoxpwa",
            parameters=["site", "launch", "01JCYF8Z2M0N3P4Q5R6S7T8V9W"],
            scope="global",
            expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            preferred_workspace=50,
            icon="youtube",
            ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            start_url="https://www.youtube.com",
            scope_url="https://www.youtube.com/",
            app_scope="scoped",
            categories="Network;AudioVideo;",
            keywords="youtube;video;",
        )

        assert config.name == "youtube-pwa"
        assert config.ulid == "01JCYF8Z2M0N3P4Q5R6S7T8V9W"
        assert config.start_url == "https://www.youtube.com"
        assert config.preferred_workspace == 50

    def test_pwa_name_must_end_with_pwa(self):
        """Test that PWA name must end with '-pwa'."""
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="youtube",  # Missing '-pwa' suffix
                display_name="YouTube",
                command="firefoxpwa",
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="https://www.youtube.com",
                scope_url="https://www.youtube.com/",
            )

        assert "'-pwa'" in str(exc_info.value) or "pattern" in str(exc_info.value)

    def test_ulid_format_validation(self):
        """Test that ULID must be 26 characters in Crockford Base32 (FR-A-008, FR-A-030)."""
        # Test invalid length
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test",
                command="firefoxpwa",
                expected_class="FFPWA-ABC",
                preferred_workspace=50,
                ulid="ABC",  # Too short
                start_url="https://example.com",
                scope_url="https://example.com/",
            )

        assert "26 characters" in str(exc_info.value) or "String should have at least" in str(exc_info.value)

        # Test invalid characters (excluded: I, L, O, U per Crockford Base32)
        invalid_ulids = [
            "01JCYF8Z2M0N3P4Q5R6S7T8VI9",  # Contains 'I'
            "01JCYF8Z2M0N3P4Q5R6S7T8VL9",  # Contains 'L'
            "01JCYF8Z2M0N3P4Q5R6S7T8VO9",  # Contains 'O'
            "01JCYF8Z2M0N3P4Q5R6S7T8VU9",  # Contains 'U'
        ]

        for ulid in invalid_ulids:
            with pytest.raises(ValidationError) as exc_info:
                PWAConfig(
                    name="test-pwa",
                    display_name="Test",
                    command="firefoxpwa",
                    expected_class=f"FFPWA-{ulid}",
                    preferred_workspace=50,
                    ulid=ulid,
                    start_url="https://example.com",
                    scope_url="https://example.com/",
                )

            assert "Invalid ULID format" in str(exc_info.value)

    def test_pwa_workspace_must_be_50_plus(self):
        """Test that PWAs must use workspace 50 or higher (FR-A-007)."""
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test",
                command="firefoxpwa",
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=49,  # Too low
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="https://example.com",
                scope_url="https://example.com/",
            )

        assert "50 or higher" in str(exc_info.value)

    def test_url_validation_requires_http_https(self):
        """Test that start_url and scope_url must be valid HTTP/HTTPS URLs (FR-A-015)."""
        # Test start_url without protocol
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test",
                command="firefoxpwa",
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="www.example.com",  # Missing http://
                scope_url="https://example.com/",
            )

        assert "http://" in str(exc_info.value) or "https://" in str(exc_info.value)

        # Test scope_url without protocol
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test",
                command="firefoxpwa",
                expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="https://example.com",
                scope_url="example.com/",  # Missing http://
            )

        assert "http://" in str(exc_info.value) or "https://" in str(exc_info.value)

    def test_expected_class_format_validation(self):
        """Test that expected_class must match FFPWA-<ULID> format."""
        with pytest.raises(ValidationError) as exc_info:
            PWAConfig(
                name="test-pwa",
                display_name="Test",
                command="firefoxpwa",
                expected_class="InvalidFormat",  # Wrong format
                preferred_workspace=50,
                ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
                start_url="https://example.com",
                scope_url="https://example.com/",
            )

        assert "FFPWA-" in str(exc_info.value) or "pattern" in str(exc_info.value)

    def test_valid_pwa_with_http_url(self):
        """Test that HTTP (not just HTTPS) URLs are accepted."""
        config = PWAConfig(
            name="test-pwa",
            display_name="Test",
            command="firefoxpwa",
            expected_class="FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            preferred_workspace=50,
            ulid="01JCYF8Z2M0N3P4Q5R6S7T8V9W",
            start_url="http://example.com",  # HTTP is OK
            scope_url="http://example.com/",
        )

        assert config.start_url == "http://example.com"
        assert config.scope_url == "http://example.com/"
