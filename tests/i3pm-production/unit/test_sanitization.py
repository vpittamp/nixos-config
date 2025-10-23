"""
Unit tests for sensitive data sanitization

Feature 030: Production Readiness
Task T012: Sanitization tests

Tests regex-based credential redaction.
"""

import pytest
import tempfile
import json
from pathlib import Path

from security.sanitize import (
    sanitize_text,
    sanitize_window_title,
    sanitize_command_line,
    sanitize_dict,
    is_sensitive,
    load_custom_patterns,
    initialize_custom_patterns,
    test_sanitization_patterns,
    DEFAULT_SANITIZE_PATTERNS,
)


# ============================================================================
# Basic Sanitization Tests
# ============================================================================

def test_sanitize_text_empty():
    """Test sanitization handles empty string"""
    assert sanitize_text("") == ""
    assert sanitize_text(None) is None


def test_sanitize_text_no_sensitive_data():
    """Test sanitization preserves non-sensitive text"""
    clean_text = "firefox https://example.com"
    assert sanitize_text(clean_text) == clean_text


def test_sanitize_text_password_flag():
    """Test sanitization redacts password arguments"""
    inputs_and_outputs = [
        ("--password=secret123", "PASSWORD_REDACTED"),
        ("--password secret123", "PASSWORD_REDACTED"),
        ("-p secret123", "-p PASSWORD_REDACTED"),
        ("pwd=mypassword", "PASSWORD_REDACTED"),
    ]

    for input_text, expected_substring in inputs_and_outputs:
        result = sanitize_text(input_text)
        assert expected_substring in result
        assert "secret123" not in result
        assert "mypassword" not in result


def test_sanitize_text_api_keys():
    """Test sanitization redacts API keys"""
    inputs = [
        "api_key=abc123xyz456789012345",
        "apikey: abc123xyz456789012345",
        "token abc123xyz456789012345",
    ]

    for input_text in inputs:
        result = sanitize_text(input_text)
        assert "abc123xyz456789012345" not in result
        assert "REDACTED" in result


def test_sanitize_text_bearer_token():
    """Test sanitization redacts Bearer tokens"""
    input_text = "Authorization: Bearer abc123xyz456789012345"
    result = sanitize_text(input_text)

    assert "abc123xyz456789012345" not in result
    assert "BEARER_TOKEN_REDACTED" in result


def test_sanitize_text_aws_credentials():
    """Test sanitization redacts AWS credentials"""
    # AWS access key
    input_text = "AKIA1234567890123456"
    result = sanitize_text(input_text)
    assert "AKIA1234567890123456" not in result
    assert "AWS" in result

    # AWS secret key
    input_text = "AWS_SECRET_ACCESS_KEY=abcdefghijklmnopqrstuvwxyz"
    result = sanitize_text(input_text)
    assert "abcdefghijklmnopqrstuvwxyz" not in result
    assert "AWS_SECRET_REDACTED" in result


def test_sanitize_text_github_tokens():
    """Test sanitization redacts GitHub tokens"""
    tokens = [
        "ghp_1234567890abcdefABCDEF1234567890",  # Personal access token
        "gho_1234567890abcdefABCDEF1234567890",  # OAuth token
        "ghs_1234567890abcdefABCDEF1234567890",  # Server token
        "github_pat_11AAAAAA0ABCDEFGHIJKLMNOPQRS",  # New PAT format
    ]

    for token in tokens:
        result = sanitize_text(token)
        assert token not in result
        assert "GITHUB" in result or "REDACTED" in result


def test_sanitize_text_database_connection():
    """Test sanitization redacts database connection strings"""
    inputs = [
        "mysql://user:password@localhost/db",
        "postgresql://admin:secret@db.example.com:5432/mydb",
        "mongodb://user:pass@mongo:27017",
    ]

    for input_text in inputs:
        result = sanitize_text(input_text)
        # Password should be redacted
        assert "password" not in result or "PASSWORD_REDACTED" in result
        assert "secret" not in result
        assert "pass@" not in result


def test_sanitize_text_jwt_token():
    """Test sanitization redacts JWT tokens"""
    jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    result = sanitize_text(jwt)

    assert jwt not in result
    assert "JWT_TOKEN_REDACTED" in result


def test_sanitize_text_private_key():
    """Test sanitization redacts SSH private keys"""
    input_text = "-----BEGIN RSA PRIVATE KEY-----"
    result = sanitize_text(input_text)

    assert "RSA PRIVATE KEY" not in result
    assert "PRIVATE_KEY_REDACTED" in result


def test_sanitize_text_multiple_secrets():
    """Test sanitization handles multiple secrets in same string"""
    # Use longer token to meet 10+ character requirement
    input_text = "curl -H 'Authorization: Bearer token123abc' --password=secret https://api.example.com"
    result = sanitize_text(input_text)

    assert "token123abc" not in result
    assert "secret" not in result
    assert "BEARER_TOKEN_REDACTED" in result
    assert "PASSWORD_REDACTED" in result
    assert "https://api.example.com" in result  # Preserve non-sensitive parts


# ============================================================================
# Specific Function Tests
# ============================================================================

def test_sanitize_window_title():
    """Test window title sanitization"""
    title = "mysql -p secret123 | Terminal"
    result = sanitize_window_title(title)

    assert "secret123" not in result
    assert "Terminal" in result


def test_sanitize_command_line():
    """Test command line sanitization"""
    cmdline = "docker login --password=secret123 docker.io"
    result = sanitize_command_line(cmdline)

    assert "secret123" not in result
    assert "docker login" in result
    assert "docker.io" in result


def test_sanitize_dict_basic():
    """Test dictionary sanitization"""
    data = {
        "id": 12345,
        "title": "mysql -p secret",
        "workspace": "1",
    }

    result = sanitize_dict(data)

    assert result["id"] == 12345
    assert "secret" not in result["title"]
    assert result["workspace"] == "1"


def test_sanitize_dict_nested():
    """Test nested dictionary sanitization"""
    data = {
        "window": {
            "id": 1,
            "title": "password=secret123",
        },
        "events": [
            {"type": "window", "command": "api_key=abc123xyz456789012345"}
        ],
    }

    result = sanitize_dict(data)

    assert "secret123" not in str(result)
    assert "abc123xyz456789012345" not in str(result)
    assert result["window"]["id"] == 1


def test_sanitize_dict_custom_keys():
    """Test sanitization with custom key list"""
    data = {
        "custom_field": "password=secret",
        "normal_field": "password=secret",  # Won't be sanitized
    }

    result = sanitize_dict(data, keys_to_sanitize=["custom_field"])

    assert "secret" not in result["custom_field"]
    assert "secret" in result["normal_field"]  # Not in sanitize list


# ============================================================================
# Sensitivity Detection Tests
# ============================================================================

def test_is_sensitive_positive():
    """Test sensitivity detection identifies sensitive text"""
    sensitive_strings = [
        "password=secret",
        "api_key: abc123",
        "Bearer token123",
        "ssh_key: /path/to/key",
    ]

    for text in sensitive_strings:
        assert is_sensitive(text) is True


def test_is_sensitive_negative():
    """Test sensitivity detection doesn't flag clean text"""
    clean_strings = [
        "firefox https://example.com",
        "Visual Studio Code",
        "git status",
    ]

    for text in clean_strings:
        assert is_sensitive(text) is False


def test_is_sensitive_threshold():
    """Test sensitivity detection respects confidence threshold"""
    # Text with medium confidence indicators
    text = "some_random_long_string_ABCDEF1234567890"

    # Should not be sensitive with high threshold
    assert is_sensitive(text, threshold=0.9) is False

    # Might be sensitive with low threshold
    # (depends on pattern matches)


# ============================================================================
# Custom Patterns Tests
# ============================================================================

def test_load_custom_patterns_valid():
    """Test loading custom patterns from config file"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        config = {
            "custom_patterns": [
                {
                    "pattern": "MYORG_SECRET_[A-Z0-9]+",
                    "replacement": "MYORG_SECRET_REDACTED"
                }
            ]
        }
        json.dump(config, f)
        config_path = Path(f.name)

    try:
        patterns = load_custom_patterns(config_path)
        assert len(patterns) == 1
        assert patterns[0][0] == "MYORG_SECRET_[A-Z0-9]+"
        assert patterns[0][1] == "MYORG_SECRET_REDACTED"
    finally:
        config_path.unlink()


def test_load_custom_patterns_invalid_regex():
    """Test loading skips invalid regex patterns"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        config = {
            "custom_patterns": [
                {
                    "pattern": "[invalid(regex",  # Unclosed bracket
                    "replacement": "INVALID"
                },
                {
                    "pattern": "valid_pattern",
                    "replacement": "VALID"
                }
            ]
        }
        json.dump(config, f)
        config_path = Path(f.name)

    try:
        patterns = load_custom_patterns(config_path)
        # Should skip invalid pattern, load valid one
        assert len(patterns) == 1
        assert patterns[0][0] == "valid_pattern"
    finally:
        config_path.unlink()


def test_load_custom_patterns_nonexistent():
    """Test loading from nonexistent file returns empty list"""
    patterns = load_custom_patterns(Path("/nonexistent/file.json"))
    assert patterns == []


def test_sanitize_with_custom_patterns():
    """Test sanitization uses custom patterns"""
    # Initialize with custom pattern
    with tempfile.TemporaryDirectory() as tmpdir:
        config_path = Path(tmpdir) / "sanitize-patterns.json"
        with open(config_path, 'w') as f:
            json.dump({
                "custom_patterns": [
                    {
                        "pattern": "CUSTOM_TOKEN_[0-9]+",
                        "replacement": "CUSTOM_REDACTED"
                    }
                ]
            }, f)

        initialize_custom_patterns(Path(tmpdir))

        # Test sanitization
        result = sanitize_text("CUSTOM_TOKEN_12345")
        assert "CUSTOM_TOKEN_12345" not in result
        assert "CUSTOM_REDACTED" in result


# ============================================================================
# Self-Test Validation
# ============================================================================

def test_sanitization_patterns_self_test():
    """Test the built-in pattern validation"""
    results = test_sanitization_patterns()

    # All test cases should pass
    assert all(passed for _, _, passed in results), \
        f"Some sanitization patterns failed: {results}"


# ============================================================================
# Edge Cases
# ============================================================================

def test_sanitize_text_case_insensitive():
    """Test sanitization is case-insensitive"""
    inputs = [
        "PASSWORD=secret",
        "password=secret",
        "PaSsWoRd=secret",
    ]

    for input_text in inputs:
        result = sanitize_text(input_text)
        assert "secret" not in result


def test_sanitize_text_preserves_structure():
    """Test sanitization preserves overall text structure"""
    input_text = "app --user=admin --password=secret --host=db.example.com"
    result = sanitize_text(input_text)

    # Should preserve command structure
    assert "app" in result
    assert "--user=admin" in result
    assert "--host=db.example.com" in result
    # But redact password
    assert "secret" not in result


def test_sanitize_text_unicode():
    """Test sanitization handles unicode characters"""
    input_text = "password=пароль123"  # Cyrillic password
    result = sanitize_text(input_text)

    # Should still redact (pattern matches 'password=' prefix)
    assert "пароль123" not in result


def test_sanitize_dict_empty():
    """Test sanitizing empty dictionary"""
    result = sanitize_dict({})
    assert result == {}


def test_sanitize_dict_preserves_types():
    """Test sanitization preserves non-string types"""
    data = {
        "int": 123,
        "float": 45.67,
        "bool": True,
        "none": None,
        "list": [1, 2, 3],
    }

    result = sanitize_dict(data)

    assert result == data
