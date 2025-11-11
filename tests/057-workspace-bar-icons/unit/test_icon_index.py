"""Unit tests for DesktopIconIndex app registry loading (T009)."""
import json
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, mock_open
import sys

# Add workspace_panel module to path for import
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "sway-workspace-panel"))

from workspace_panel import DesktopIconIndex


class TestDesktopIconIndexAppRegistry:
    """Test app registry loading and indexing."""

    @pytest.fixture
    def mock_app_registry(self):
        """Mock application-registry.json data."""
        return {
            "version": "1.0",
            "applications": [
                {
                    "name": "firefox",
                    "display_name": "Firefox",
                    "command": "firefox",
                    "expected_class": "firefox",
                    "expected_instance": None,
                    "icon": "firefox",
                    "scope": "global",
                    "preferred_workspace": 3,
                    "preferred_monitor_role": "secondary"
                },
                {
                    "name": "code",
                    "display_name": "VS Code",
                    "command": "code",
                    "expected_class": "Code",
                    "expected_instance": None,
                    "icon": "code",
                    "scope": "scoped",
                    "preferred_workspace": 2,
                    "preferred_monitor_role": "primary"
                },
            ]
        }

    @pytest.fixture
    def mock_pwa_registry(self):
        """Mock pwa-registry.json data."""
        return {
            "version": "1.0",
            "pwas": [
                {
                    "name": "Claude",
                    "url": "https://claude.ai",
                    "ulid": "01JCYF8Z2VQRSTUVWXYZ123456",
                    "icon": "/etc/nixos/assets/pwa-icons/claude.png",
                    "preferred_workspace": 52,
                    "preferred_monitor_role": "tertiary"
                }
            ]
        }

    @patch('workspace_panel.Path.exists')
    @patch('builtins.open', new_callable=mock_open)
    def test_load_app_registry_normalizes_keys_to_lowercase(self, mock_file, mock_exists, mock_app_registry):
        """Test that app registry keys are normalized to lowercase (data-model.md line 42)."""
        # Setup
        mock_exists.return_value = True
        mock_file.return_value.read.return_value = json.dumps(mock_app_registry)

        with patch('workspace_panel.PWA_REGISTRY_PATH', Path("/nonexistent")):
            with patch('workspace_panel.DESKTOP_DIRS', []):
                # Create index with mocked registries
                with patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True):
                    with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_app_registry))):
                        index = DesktopIconIndex()

        # Verify: Keys should be lowercase
        assert "firefox" in index._by_app_id, "App name 'firefox' should be indexed (lowercase)"
        assert "code" in index._by_app_id, "App name 'code' should be indexed (lowercase)"
        assert "FIREFOX" not in index._by_app_id, "Uppercase keys should not exist"

    @patch('workspace_panel.Path.exists')
    @patch('builtins.open', new_callable=mock_open)
    def test_load_app_registry_stores_icon_and_display_name(self, mock_file, mock_exists, mock_app_registry):
        """Test that app registry stores icon path and display name."""
        # Setup
        mock_exists.return_value = True
        mock_file.return_value.read.return_value = json.dumps(mock_app_registry)

        with patch('workspace_panel.PWA_REGISTRY_PATH', Path("/nonexistent")):
            with patch('workspace_panel.DESKTOP_DIRS', []):
                with patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True):
                    with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_app_registry))):
                        with patch.object(DesktopIconIndex, '_resolve_icon', return_value="/path/to/firefox.svg"):
                            index = DesktopIconIndex()

        # Verify: Firefox entry has icon and name
        firefox_payload = index._by_app_id.get("firefox")
        assert firefox_payload is not None, "Firefox should be indexed"
        assert firefox_payload["icon"] == "/path/to/firefox.svg", "Icon path should be resolved"
        assert firefox_payload["name"] == "Firefox", "Display name should be stored"

    @patch('workspace_panel.Path.exists')
    def test_load_app_registry_handles_missing_file_gracefully(self, mock_exists):
        """Test that missing app registry file doesn't crash."""
        # Setup: Registry file doesn't exist
        mock_exists.return_value = False

        with patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False):
            with patch('workspace_panel.DESKTOP_DIRS', []):
                # Should not raise exception
                index = DesktopIconIndex()

        # Verify: Index should be empty but functional
        assert len(index._by_app_id) == 0, "Empty app registry should result in empty index"


class TestDesktopIconIndexIconPayload:
    """Test IconPayload structure (data-model.md lines 25-30)."""

    @patch('workspace_panel.Path.exists')
    @patch('builtins.open', new_callable=mock_open)
    def test_icon_payload_structure(self, mock_file, mock_exists):
        """Test that IconPayload has required 'icon' and 'name' fields."""
        mock_app_registry = {
            "version": "1.0",
            "applications": [{
                "name": "test",
                "display_name": "Test App",
                "icon": "test-icon",
            }]
        }

        mock_exists.return_value = True

        with patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False):
            with patch('workspace_panel.DESKTOP_DIRS', []):
                with patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True):
                    with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_app_registry))):
                        with patch.object(DesktopIconIndex, '_resolve_icon', return_value="/path/icon.svg"):
                            index = DesktopIconIndex()

        payload = index._by_app_id.get("test")
        assert payload is not None, "Payload should exist"
        assert "icon" in payload, "Payload must have 'icon' field"
        assert "name" in payload, "Payload must have 'name' field"
        assert isinstance(payload["icon"], str), "Icon must be string (absolute path or empty)"
        assert isinstance(payload["name"], str), "Name must be string"
