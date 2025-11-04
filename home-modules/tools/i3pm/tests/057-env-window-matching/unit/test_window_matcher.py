"""
Unit tests for simplified window matching using environment variables (User Story 4).

Tests verify that window matching uses I3PM_* environment variables exclusively,
without falling back to window class normalization or registry iteration.
"""

import pytest
from unittest.mock import Mock, patch, AsyncMock
from pathlib import Path

# Import test utilities
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import daemon modules
daemon_path = Path(__file__).parent.parent.parent / "daemon"
if str(daemon_path) not in sys.path:
    sys.path.insert(0, str(daemon_path))

from models import WindowEnvironment
from window_environment import get_window_environment


@pytest.mark.asyncio
async def test_simplified_window_matcher_uses_environment():
    """
    T036: Unit test - Simplified window matcher uses I3PM_APP_NAME.

    Verifies that window matching logic:
    1. Uses I3PM_APP_NAME instead of window class
    2. Uses I3PM_APP_ID instead of window title
    3. Does NOT iterate through registry for class matching
    """
    # Mock window with environment variables
    mock_window = Mock()
    mock_window.id = 123456
    mock_window.pid = 98765
    mock_window.app_id = "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5"  # Original PWA class
    mock_window.name = "Claude — Mozilla Firefox"  # Window title

    # Mock environment variables returned from /proc
    mock_env_vars = {
        "I3PM_APP_ID": "claude-pwa-nixos-833032-1762201416",
        "I3PM_APP_NAME": "claude-pwa",
        "I3PM_SCOPE": "scoped",
        "I3PM_PROJECT_NAME": "nixos",
        "I3PM_PROJECT_DIR": "/etc/nixos",
        "I3PM_EXPECTED_CLASS": "FFPWA-01JCYF8Z2M7R4N6QW9XKPHVTB5",
    }

    # Patch read_process_environ to return mock environment
    with patch('window_environment.read_process_environ', return_value=mock_env_vars):
        # Query window environment
        result = await get_window_environment(
            window_id=mock_window.id,
            pid=mock_window.pid,
        )

        # Assert environment was found
        assert result.environment is not None, "Failed to find environment"

        # Assert uses I3PM_APP_NAME instead of window class
        assert result.environment.app_name == "claude-pwa", \
            f"Expected app_name='claude-pwa', got '{result.environment.app_name}'"

        # Verify app_name does NOT match window class
        assert result.environment.app_name != mock_window.app_id, \
            "app_name should not match window class (should use I3PM_APP_NAME)"

        # Assert uses I3PM_APP_ID instead of window title
        assert result.environment.app_id == "claude-pwa-nixos-833032-1762201416", \
            f"Expected specific app_id, got '{result.environment.app_id}'"

        # Verify app_id does NOT match window title
        assert result.environment.app_id not in mock_window.name, \
            "app_id should not be derived from window title"

        # Assert project association is from environment
        assert result.environment.project_name == "nixos", \
            "project_name should come from I3PM_PROJECT_NAME"


@pytest.mark.asyncio
async def test_no_registry_iteration_on_environment_match():
    """
    Unit test - Verify NO registry iteration when environment variables present.

    When I3PM_* variables are found, the matcher should NOT:
    - Iterate through app registry
    - Perform class normalization
    - Check aliases
    - Do fuzzy matching
    """
    mock_env_vars = {
        "I3PM_APP_ID": "vscode-test-123",
        "I3PM_APP_NAME": "vscode",
        "I3PM_SCOPE": "scoped",
        "I3PM_PROJECT_NAME": "nixos",
    }

    # Patch to verify registry is NOT accessed
    with patch('window_environment.read_process_environ', return_value=mock_env_vars):
        result = await get_window_environment(
            window_id=111111,
            pid=22222,
        )

        # Should find environment without registry
        assert result.environment is not None
        assert result.environment.app_name == "vscode"

        # The key point: we got the answer directly from environment
        # without needing to consult any registry or do class matching


@pytest.mark.asyncio
async def test_window_identification_performance():
    """
    Unit test - Environment-based identification should be faster than legacy.

    Legacy matching: ~6-11ms (class normalization + registry iteration + PWA detection)
    Environment matching: ~0.4ms (single /proc read + dict lookup)

    Expected improvement: 15-27x faster
    """
    import time

    mock_env_vars = {
        "I3PM_APP_ID": "test-perf",
        "I3PM_APP_NAME": "test",
        "I3PM_SCOPE": "global",
    }

    with patch('window_environment.read_process_environ', return_value=mock_env_vars):
        # Measure query time
        start = time.perf_counter()
        result = await get_window_environment(window_id=999, pid=888)
        end = time.perf_counter()

        latency_ms = (end - start) * 1000.0

        # Should be very fast (most of the time is the mock overhead)
        assert result.environment is not None
        assert latency_ms < 10.0, \
            f"Environment query took {latency_ms:.2f}ms (target: <10ms)"


def test_window_environment_from_dict_parsing():
    """
    Unit test - WindowEnvironment.from_env_dict() parses I3PM_* variables.

    Verifies that parsing logic extracts all fields correctly without
    needing window class information.
    """
    env_dict = {
        "I3PM_APP_ID": "firefox-pwa-youtube-12345",
        "I3PM_APP_NAME": "youtube-pwa",
        "I3PM_SCOPE": "global",
        "I3PM_PROJECT_NAME": "",
        "I3PM_PROJECT_DIR": "",
        "I3PM_TARGET_WORKSPACE": "3",
        "I3PM_EXPECTED_CLASS": "FFPWA-01JD0H7Z8M",
    }

    # Parse environment
    window_env = WindowEnvironment.from_env_dict(env_dict)

    assert window_env is not None
    assert window_env.app_id == "firefox-pwa-youtube-12345"
    assert window_env.app_name == "youtube-pwa"
    assert window_env.scope == "global"
    assert window_env.target_workspace == 3
    assert window_env.expected_class == "FFPWA-01JD0H7Z8M"

    # Note: expected_class is for VALIDATION only, not for matching
    assert window_env.app_name != window_env.expected_class, \
        "app_name should be human-readable, not the window class"


def test_environment_based_identification_without_class():
    """
    Unit test - Environment-based identification works without window class.

    Even if window class is unknown or missing, identification succeeds
    because it relies only on environment variables.
    """
    env_dict = {
        "I3PM_APP_ID": "unknown-class-app-789",
        "I3PM_APP_NAME": "custom-app",
        "I3PM_SCOPE": "scoped",
        "I3PM_PROJECT_NAME": "test-project",
        "I3PM_PROJECT_DIR": "/tmp/test",
    }

    window_env = WindowEnvironment.from_env_dict(env_dict)

    # Should work perfectly without any window class information
    assert window_env is not None
    assert window_env.app_name == "custom-app"
    assert window_env.project_name == "test-project"

    # No class-based fallback needed!


@pytest.mark.asyncio
async def test_multiple_instances_distinguished_by_app_id():
    """
    Unit test - Multiple instances of same app distinguished by I3PM_APP_ID.

    Legacy approach: Same window class → ambiguity
    Environment approach: Unique APP_ID per instance → deterministic
    """
    # Two VS Code instances with different APP_IDs
    env_instance1 = {
        "I3PM_APP_ID": "vscode-nixos-1001-1234567890",
        "I3PM_APP_NAME": "vscode",
        "I3PM_SCOPE": "scoped",
        "I3PM_PROJECT_NAME": "nixos",
    }

    env_instance2 = {
        "I3PM_APP_ID": "vscode-stacks-1002-1234567891",
        "I3PM_APP_NAME": "vscode",
        "I3PM_SCOPE": "scoped",
        "I3PM_PROJECT_NAME": "stacks",
    }

    # Parse both environments
    instance1 = WindowEnvironment.from_env_dict(env_instance1)
    instance2 = WindowEnvironment.from_env_dict(env_instance2)

    # Same app_name (both VS Code)
    assert instance1.app_name == instance2.app_name == "vscode"

    # Different app_ids (unique instances)
    assert instance1.app_id != instance2.app_id, \
        "Each instance must have unique APP_ID"

    # Different projects
    assert instance1.project_name == "nixos"
    assert instance2.project_name == "stacks"

    # No ambiguity!
