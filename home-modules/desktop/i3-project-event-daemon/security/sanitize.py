"""
Sensitive Data Sanitization Module

Feature 030: Production Readiness
Task T010: Regex-based pattern matching for credential removal

This module sanitizes window titles, command lines, and other text
to prevent credential leakage in logs and diagnostic exports.

Reference: research.md Decision 7 (lines 376-450)
"""

import re
import json
import logging
from pathlib import Path
from typing import List, Tuple

logger = logging.getLogger(__name__)


# ============================================================================
# Sanitization Patterns
# ============================================================================

# Default patterns for common credential formats
# Each pattern is (regex, replacement_text)
DEFAULT_SANITIZE_PATTERNS: List[Tuple[str, str]] = [
    # GitHub tokens (ghp_, gho_, ghs_, github_pat_) - MUST come before generic token patterns
    (r'gh[pso]_[A-Za-z0-9_]{30,}', 'GITHUB_TOKEN_REDACTED'),
    (r'github_pat_[A-Za-z0-9_]{20,}', 'GITHUB_PAT_REDACTED'),

    # API keys and tokens (generic)
    (r'(api[_-]?key|token|secret)[=:\s]+[A-Za-z0-9_-]{20,}', 'API_KEY_REDACTED'),
    (r'Bearer\s+[A-Za-z0-9_-]{10,}', 'BEARER_TOKEN_REDACTED'),

    # Passwords - order matters for --password vs password= patterns
    (r'--password[=\s]+\S+', '--PASSWORD_REDACTED'),
    (r'(password|passwd|pwd)[=:\s]+\S+', 'PASSWORD_REDACTED'),
    (r'-p\s+\S+', '-p PASSWORD_REDACTED'),  # Common -p flag

    # AWS credentials
    (r'AWS_SECRET_ACCESS_KEY[=:\s]+\S+', 'AWS_SECRET_REDACTED'),
    (r'AKIA[0-9A-Z]{16}', 'AWS_ACCESS_KEY_REDACTED'),
    (r'aws_secret_access_key\s*=\s*\S+', 'aws_secret_access_key=REDACTED'),

    # GitLab tokens
    (r'glpat-[A-Za-z0-9_-]{20,}', 'GITLAB_TOKEN_REDACTED'),

    # SSH private key indicators
    (r'-----BEGIN.*PRIVATE KEY-----', 'PRIVATE_KEY_REDACTED'),

    # Database connection strings
    (r'(mysql|postgresql|postgres|mongodb|redis)://[^:]+:[^@]+@', r'\1://USER:PASSWORD_REDACTED@'),
    (r'(mysql|postgresql|postgres|mongodb|redis)://[^/\s]+', 'DB_CONNECTION_REDACTED'),

    # JWT tokens (eyJ header indicates JWT)
    (r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', 'JWT_TOKEN_REDACTED'),

    # Generic long alphanumeric strings that might be tokens
    # (Conservative pattern: only match if preceded by key/token/auth)
    (r'(key|token|auth|credential)[=:\s]+[A-Za-z0-9_-]{32,}', r'\1=CREDENTIAL_REDACTED'),

    # OAuth tokens
    (r'oauth_token[=:\s]+[A-Za-z0-9_-]+', 'oauth_token=REDACTED'),
    (r'access_token[=:\s]+[A-Za-z0-9_-]+', 'access_token=REDACTED'),

    # NPM tokens
    (r'//registry\.npmjs\.org/:_authToken=[^\s]+', '//registry.npmjs.org/:_authToken=REDACTED'),

    # Stripe keys
    (r'sk_live_[A-Za-z0-9]{24,}', 'STRIPE_SECRET_REDACTED'),
    (r'pk_live_[A-Za-z0-9]{24,}', 'STRIPE_PUBLIC_REDACTED'),

    # Slack tokens
    (r'xox[baprs]-[A-Za-z0-9-]+', 'SLACK_TOKEN_REDACTED'),

    # Google Cloud credentials
    (r'AIza[A-Za-z0-9_-]{35}', 'GOOGLE_API_KEY_REDACTED'),

    # Docker Hub tokens
    (r'dckr_pat_[A-Za-z0-9_-]{20,}', 'DOCKER_TOKEN_REDACTED'),
]


# Custom user-defined patterns (loaded from config)
_custom_patterns: List[Tuple[str, str]] = []


# ============================================================================
# Configuration Loading
# ============================================================================

def load_custom_patterns(config_path: Path) -> List[Tuple[str, str]]:
    """
    Load user-defined sanitization patterns from config file

    Config format (JSON):
    {
      "custom_patterns": [
        {
          "pattern": "MYORG_SECRET_[A-Z0-9]+",
          "replacement": "MYORG_SECRET_REDACTED"
        }
      ]
    }

    Args:
        config_path: Path to sanitize-patterns.json

    Returns:
        List of (pattern, replacement) tuples
    """
    patterns = []

    if not config_path.exists():
        logger.debug(f"No custom sanitization patterns found at {config_path}")
        return patterns

    try:
        with open(config_path) as f:
            config = json.load(f)

        for entry in config.get("custom_patterns", []):
            pattern = entry.get("pattern")
            replacement = entry.get("replacement", "CUSTOM_REDACTED")

            # Validate regex
            try:
                re.compile(pattern)
                patterns.append((pattern, replacement))
                logger.debug(f"Loaded custom sanitization pattern: {pattern}")
            except re.error as e:
                logger.warning(f"Invalid custom pattern '{pattern}': {e}")

    except Exception as e:
        logger.error(f"Failed to load custom patterns from {config_path}: {e}")

    return patterns


def initialize_custom_patterns(config_dir: Path) -> None:
    """
    Initialize custom patterns from config directory

    Args:
        config_dir: Directory containing sanitize-patterns.json
    """
    global _custom_patterns
    config_path = config_dir / "sanitize-patterns.json"
    _custom_patterns = load_custom_patterns(config_path)
    logger.info(f"Loaded {len(_custom_patterns)} custom sanitization patterns")


# ============================================================================
# Sanitization Functions
# ============================================================================

def sanitize_text(
    text: str,
    use_default_patterns: bool = True,
    use_custom_patterns: bool = True
) -> str:
    """
    Sanitize text by replacing credential patterns with redacted placeholders

    This is the primary sanitization function used throughout the daemon
    to prevent credential leakage in logs and diagnostics.

    Args:
        text: Text to sanitize
        use_default_patterns: Apply default built-in patterns
        use_custom_patterns: Apply user-defined custom patterns

    Returns:
        Sanitized text with credentials replaced

    Example:
        >>> sanitize_text("--password=secret123 --api-key=abc_xyz_123")
        '--password=PASSWORD_REDACTED --api-key=API_KEY_REDACTED'
    """
    if not text:
        return text

    result = text

    # Apply default patterns
    if use_default_patterns:
        for pattern, replacement in DEFAULT_SANITIZE_PATTERNS:
            try:
                result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
            except re.error as e:
                logger.error(f"Regex error in default pattern '{pattern}': {e}")

    # Apply custom patterns
    if use_custom_patterns and _custom_patterns:
        for pattern, replacement in _custom_patterns:
            try:
                result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
            except re.error as e:
                logger.error(f"Regex error in custom pattern '{pattern}': {e}")

    return result


def sanitize_window_title(title: str) -> str:
    """
    Sanitize window title before logging or exporting

    Window titles often contain sensitive information like:
    - Database connection strings (SQL client)
    - API endpoints with tokens
    - File paths with secrets
    - Terminal commands with passwords

    Args:
        title: Window title from WM_NAME or _NET_WM_NAME

    Returns:
        Sanitized window title

    Example:
        >>> sanitize_window_title("mysql -p secret123 | Terminal")
        'mysql -p PASSWORD_REDACTED | Terminal'
    """
    return sanitize_text(title)


def sanitize_command_line(cmdline: str) -> str:
    """
    Sanitize process command line before logging or exporting

    Command lines frequently contain credentials as arguments:
    - Database passwords: mysql -p password
    - API keys: curl -H "Authorization: Bearer token"
    - SSH keys: ssh -i /path/to/private_key

    Args:
        cmdline: Process command line from /proc/pid/cmdline

    Returns:
        Sanitized command line

    Example:
        >>> sanitize_command_line("docker login --password=secret123 docker.io")
        'docker login --password=PASSWORD_REDACTED docker.io'
    """
    return sanitize_text(cmdline)


def sanitize_dict(data: dict, keys_to_sanitize: List[str] = None) -> dict:
    """
    Recursively sanitize dictionary values

    Used for sanitizing diagnostic exports and event data structures.

    Args:
        data: Dictionary to sanitize
        keys_to_sanitize: List of key names to sanitize (default: common keys)

    Returns:
        New dictionary with sanitized values

    Example:
        >>> sanitize_dict({"title": "mysql -p secret", "id": 123})
        {'title': 'mysql -p PASSWORD_REDACTED', 'id': 123}
    """
    if keys_to_sanitize is None:
        keys_to_sanitize = [
            "title",
            "command",
            "cmdline",
            "command_line",
            "window_title",
            "launch_command",
            "env",
            "environment",
        ]

    result = {}

    for key, value in data.items():
        if isinstance(value, str) and key.lower() in [k.lower() for k in keys_to_sanitize]:
            # Sanitize string values for sensitive keys
            result[key] = sanitize_text(value)
        elif isinstance(value, dict):
            # Recursively sanitize nested dictionaries
            result[key] = sanitize_dict(value, keys_to_sanitize)
        elif isinstance(value, list):
            # Sanitize list elements (if they're strings or dicts)
            result[key] = [
                sanitize_text(item) if isinstance(item, str) else
                sanitize_dict(item, keys_to_sanitize) if isinstance(item, dict) else
                item
                for item in value
            ]
        else:
            # Keep non-string values as-is
            result[key] = value

    return result


def is_sensitive(text: str, threshold: float = 0.7) -> bool:
    """
    Heuristic check if text likely contains sensitive information

    This can be used as a warning before logging unsanitized text.

    Args:
        text: Text to check
        threshold: Confidence threshold (0.0-1.0)

    Returns:
        True if text likely contains sensitive data

    Example:
        >>> is_sensitive("mysql -p secret123")
        True
        >>> is_sensitive("firefox https://example.com")
        False
    """
    if not text:
        return False

    text_lower = text.lower()

    # High confidence indicators
    high_confidence_keywords = [
        "password", "passwd", "pwd", "secret", "token", "api_key",
        "apikey", "bearer", "credential", "private_key", "ssh_key"
    ]

    for keyword in high_confidence_keywords:
        if keyword in text_lower:
            return True

    # Medium confidence indicators
    # Check for patterns that look like credentials
    medium_confidence_patterns = [
        r'[A-Za-z0-9]{32,}',  # Long alphanumeric strings
        r'ey[A-Za-z0-9_-]+\.',  # JWT-like
        r'[A-Z0-9]{16,}',  # Uppercase token-like
    ]

    confidence = 0.0
    for pattern in medium_confidence_patterns:
        if re.search(pattern, text):
            confidence += 0.3

    return confidence >= threshold


# ============================================================================
# Testing & Validation
# ============================================================================

def test_sanitization_patterns():
    """
    Self-test for sanitization patterns

    Returns a list of (input, output, passed) tuples for debugging.
    """
    test_cases = [
        # (input, expected_substring) - check if expected is in output
        ("--password=secret123", "--PASSWORD_REDACTED"),  # --password pattern wins
        ("Bearer abc123xyz456", "BEARER_TOKEN_REDACTED"),
        ("AKIA1234567890123456", "AWS_ACCESS_KEY_REDACTED"),
        ("ghp_1234567890abcdefABCDEF1234567890", "GITHUB_TOKEN_REDACTED"),
        ("mysql://user:pass@localhost", "DB_CONNECTION_REDACTED"),  # More general DB pattern matches first
        ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.doe", "JWT_TOKEN_REDACTED"),
    ]

    results = []
    for input_text, expected_substring in test_cases:
        actual_output = sanitize_text(input_text)
        passed = expected_substring in actual_output
        results.append((input_text, actual_output, passed))

        if not passed:
            logger.warning(
                f"Sanitization test failed:\n"
                f"  Input: {input_text}\n"
                f"  Expected substring: {expected_substring}\n"
                f"  Actual: {actual_output}"
            )

    return results
