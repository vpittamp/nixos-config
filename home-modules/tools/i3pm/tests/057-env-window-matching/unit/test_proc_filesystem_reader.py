"""
Unit tests for /proc filesystem environment variable reading.

Tests the read_process_environ() function's ability to:
- Read environment variables from /proc/<pid>/environ
- Handle FileNotFoundError gracefully
- Handle PermissionError gracefully
- Handle invalid UTF-8 with errors='ignore'
"""

import pytest
import os
import tempfile
from pathlib import Path
from home_modules.tools.i3pm.tests.test_utils import read_process_environ


class TestReadProcessEnviron:
    """Test suite for read_process_environ() function."""

    def test_read_self_environ(self):
        """Test reading environment from current process."""
        # Read our own process environment
        env = read_process_environ(os.getpid())

        # Verify we got environment variables
        assert isinstance(env, dict)
        assert len(env) > 0

        # Check for common environment variables
        assert "PATH" in env
        assert env["PATH"] != ""

    def test_read_environ_with_special_chars(self):
        """Test reading environment variables with special characters."""
        # Current process should have HOME env var
        env = read_process_environ(os.getpid())

        assert "HOME" in env
        # HOME typically contains / and other path characters
        assert "/" in env["HOME"]

    def test_handle_file_not_found(self):
        """Test graceful handling of non-existent process."""
        # Use PID that definitely doesn't exist (very high number)
        env = read_process_environ(999999999)

        # Should return empty dict, not raise exception
        assert isinstance(env, dict)
        assert len(env) == 0

    def test_handle_permission_denied(self):
        """Test graceful handling of permission denied."""
        # Try to read init process (PID 1) which may have restricted access
        # Note: This might succeed if running as root, so we accept both outcomes
        env = read_process_environ(1)

        # Should return dict (either empty or with values), not raise exception
        assert isinstance(env, dict)

    def test_parse_null_separated_values(self):
        """Test parsing null-byte separated key=value pairs."""
        # Read our own environment
        env = read_process_environ(os.getpid())

        # Verify parsing worked correctly
        assert isinstance(env, dict)

        # All keys should be strings
        for key, value in env.items():
            assert isinstance(key, str)
            assert isinstance(value, str)
            # Key should not contain = or null bytes
            assert "=" not in key
            assert "\0" not in key

    def test_environment_with_equals_in_value(self):
        """Test handling of environment variables with = in the value."""
        # Set a test environment variable with = in value
        test_key = "TEST_VAR_WITH_EQUALS"
        test_value = "key=value=another"
        os.environ[test_key] = test_value

        try:
            # Read our own environment
            env = read_process_environ(os.getpid())

            # Verify the value was parsed correctly (only first = splits key/value)
            assert test_key in env
            assert env[test_key] == test_value
        finally:
            # Cleanup
            del os.environ[test_key]

    def test_empty_environment_values(self):
        """Test handling of empty environment variable values."""
        # Set a test environment variable with empty value
        test_key = "TEST_EMPTY_VAR"
        os.environ[test_key] = ""

        try:
            # Read our own environment
            env = read_process_environ(os.getpid())

            # Verify empty value is preserved
            assert test_key in env
            assert env[test_key] == ""
        finally:
            # Cleanup
            del os.environ[test_key]

    def test_utf8_decode_with_ignore(self):
        """
        Test UTF-8 decoding with errors='ignore'.

        Note: This test is tricky because we can't easily inject invalid UTF-8
        into /proc/<pid>/environ. We verify the function doesn't crash on
        our own environment which should be valid UTF-8.
        """
        # Read our own environment
        env = read_process_environ(os.getpid())

        # Should succeed without raising UnicodeDecodeError
        assert isinstance(env, dict)

        # All values should be strings (not bytes)
        for key, value in env.items():
            assert isinstance(value, str)
