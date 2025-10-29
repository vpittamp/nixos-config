"""
Pytest configuration and fixtures for Sway Configuration Manager tests.

Feature 047 US5 T055: Test infrastructure
"""

import asyncio
import json
import tempfile
from pathlib import Path
from typing import Generator

import pytest


@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def temp_config_dir() -> Generator[Path, None, None]:
    """Create temporary configuration directory for tests."""
    with tempfile.TemporaryDirectory() as tmpdir:
        config_dir = Path(tmpdir)

        # Create subdirectories
        (config_dir / "projects").mkdir()
        (config_dir / "schemas").mkdir()

        yield config_dir


@pytest.fixture
def valid_keybindings():
    """Valid keybindings configuration data."""
    return [
        {
            "key_combo": "Mod+Return",
            "action": "exec ghostty",
            "description": "Launch terminal"
        },
        {
            "key_combo": "Mod+Shift+Q",
            "action": "kill",
            "description": "Close window"
        },
        {
            "key_combo": "Mod+D",
            "action": "exec walker",
            "description": "Launch application launcher"
        }
    ]


@pytest.fixture
def valid_window_rules():
    """Valid window rules configuration data."""
    return [
        {
            "rule_id": "float_calculator",
            "criteria": {
                "app_id": "gnome-calculator"
            },
            "actions": {
                "floating": True,
                "resize": {"width": 400, "height": 600}
            },
            "priority": 100
        },
        {
            "rule_id": "vscode_workspace2",
            "criteria": {
                "window_class": "Code"
            },
            "actions": {
                "workspace": 2
            },
            "priority": 90
        }
    ]


@pytest.fixture
def valid_workspace_assignments():
    """Valid workspace assignments configuration data."""
    return [
        {
            "workspace_number": 1,
            "primary_output": "DP-1",
            "fallback_output": "HDMI-A-1"
        },
        {
            "workspace_number": 2,
            "primary_output": "DP-1"
        },
        {
            "workspace_number": 3,
            "primary_output": "HDMI-A-1"
        }
    ]


@pytest.fixture
def invalid_keybindings_syntax():
    """Keybindings with syntax errors."""
    return [
        {
            "key_combo": "Mod++Return",  # Double plus - invalid
            "action": "exec terminal",
            "description": "Invalid key combo"
        },
        {
            "key_combo": "Mod+",  # Trailing plus - invalid
            "action": "exec something",
            "description": "Incomplete key combo"
        },
        {
            "key_combo": "",  # Empty key combo
            "action": "exec test",
            "description": "Empty key combo"
        }
    ]


@pytest.fixture
def invalid_window_rules_regex():
    """Window rules with invalid regex patterns."""
    return [
        {
            "rule_id": "bad_regex_1",
            "criteria": {
                "app_id": "[invalid(regex"  # Unclosed bracket
            },
            "actions": {
                "floating": True
            },
            "priority": 100
        },
        {
            "rule_id": "bad_regex_2",
            "criteria": {
                "title": "(?P<invalid>"  # Incomplete named group
            },
            "actions": {
                "workspace": 2
            },
            "priority": 90
        },
        {
            "rule_id": "bad_regex_3",
            "criteria": {
                "window_class": "***"  # Invalid quantifier
            },
            "actions": {
                "floating": True
            },
            "priority": 80
        }
    ]


@pytest.fixture
def invalid_workspace_assignments():
    """Workspace assignments with validation errors."""
    return [
        {
            "workspace_number": 0,  # Too low
            "primary_output": "DP-1"
        },
        {
            "workspace_number": 71,  # Too high (max is 70)
            "primary_output": "DP-1"
        },
        {
            "workspace_number": -5,  # Negative
            "primary_output": "DP-1"
        }
    ]


@pytest.fixture
def malformed_json():
    """Malformed JSON configuration."""
    return '{"rule_id": "test", "criteria": {invalid json}'


@pytest.fixture
def schema_violation_data():
    """Data that violates JSON schema (missing required fields)."""
    return [
        {
            # Missing required "key_combo" field
            "action": "exec something",
            "description": "Missing key combo"
        },
        {
            "key_combo": "Mod+X",
            # Missing required "action" field
            "description": "Missing action"
        }
    ]


@pytest.fixture
def conflicting_rules():
    """Window rules with conflicts."""
    return [
        {
            "rule_id": "rule_1",
            "criteria": {
                "app_id": "calculator"
            },
            "actions": {
                "workspace": 2
            },
            "priority": 100
        },
        {
            "rule_id": "rule_2",
            "criteria": {
                "app_id": "calculator"  # Same criteria, different action - conflict
            },
            "actions": {
                "workspace": 3
            },
            "priority": 100  # Same priority makes conflict ambiguous
        }
    ]


@pytest.fixture
def project_override_errors():
    """Project window rule overrides with errors."""
    return {
        "name": "test-project",
        "directory": "/tmp/test",
        "window_rule_overrides": [
            {
                "base_rule_id": "nonexistent_rule",  # References non-existent rule
                "override_properties": {
                    "workspace": 5
                },
                "enabled": True
            },
            {
                "base_rule_id": "some_rule",
                "override_properties": {
                    "invalid_field": "value"  # Invalid property name
                },
                "enabled": True
            }
        ]
    }
