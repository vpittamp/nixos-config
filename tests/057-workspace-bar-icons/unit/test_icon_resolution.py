"""Unit tests for icon resolution cascade (T010-T011)."""
import json
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, mock_open
import sys

# Add workspace_panel module to path for import
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "sway-workspace-panel"))

from workspace_panel import DesktopIconIndex


class TestIconResolutionPriority:
    """Test icon resolution cascade priority (research.md lines 56-61)."""

    @pytest.fixture
    def mock_app_registry(self):
        """Mock application registry with firefox entry."""
        return {
            "version": "1.0",
            "applications": [{
                "name": "firefox",
                "display_name": "Firefox",
                "icon": "firefox-from-app-registry",
            }]
        }

    @pytest.fixture
    def mock_desktop_entry(self):
        """Mock .desktop file entry for firefox."""
        mock_entry = Mock()
        mock_entry.getIcon.return_value = "firefox-from-desktop-file"
        mock_entry.getName.return_value = "Firefox Desktop"
        mock_entry.getStartupWMClass.return_value = None
        return mock_entry

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True)
    def test_app_registry_takes_priority_over_desktop_files(self, mock_app_exists, mock_pwa_exists, mock_app_registry):
        """Test that app registry has higher priority than desktop files (research.md lines 56-61)."""
        # Setup: Mock both app registry AND desktop file
        with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_app_registry))):
            with patch.object(DesktopIconIndex, '_resolve_icon') as mock_resolve:
                # Return different paths for different icon names
                def resolve_side_effect(icon_name):
                    if icon_name == "firefox-from-app-registry":
                        return "/path/from/app/registry.svg"
                    elif icon_name == "firefox-from-desktop-file":
                        return "/path/from/desktop/file.svg"
                    return None

                mock_resolve.side_effect = resolve_side_effect
                index = DesktopIconIndex()

                # Manually inject desktop file entry (simulating _load_desktop_entries)
                index._by_desktop_id["firefox"] = {
                    "icon": "/path/from/desktop/file.svg",
                    "name": "Firefox Desktop"
                }

        # Test: Lookup should return app registry result (higher priority)
        result = index.lookup(app_id="firefox", window_class=None, window_instance=None)

        # Verify: App registry icon should be returned (not desktop file icon)
        assert result["icon"] == "/path/from/app/registry.svg", \
            "App registry icon should take priority over desktop file icon"
        assert result["name"] == "Firefox", \
            "App registry display name should take priority"

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=False)
    def test_desktop_file_used_when_app_registry_missing(self):
        """Test that desktop files are used when app registry has no match."""
        # Setup: No app registry, only desktop file
        index = DesktopIconIndex()

        # Manually inject desktop file entry
        index._by_desktop_id["firefox"] = {
            "icon": "/usr/share/icons/firefox.svg",
            "name": "Firefox Browser"
        }

        # Test: Lookup should return desktop file result
        result = index.lookup(app_id="firefox", window_class=None, window_instance=None)

        # Verify: Desktop file icon should be returned
        assert result["icon"] == "/usr/share/icons/firefox.svg", \
            "Desktop file icon should be used when app registry missing"
        assert result["name"] == "Firefox Browser"


class TestPWAIconResolution:
    """Test PWA registry icon resolution (T011 - research.md lines 63-67)."""

    @pytest.fixture
    def mock_pwa_registry(self):
        """Mock PWA registry with Claude entry."""
        return {
            "version": "1.0",
            "pwas": [{
                "name": "Claude",
                "url": "https://claude.ai",
                "ulid": "01JCYF8Z2VQRSTUVWXYZ123456",
                "icon": "/etc/nixos/assets/pwa-icons/claude.png",
                "preferred_workspace": 52,
            }]
        }

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=True)
    def test_pwa_registry_resolves_absolute_icon_paths(self, mock_pwa_exists, mock_app_exists, mock_pwa_registry):
        """Test that PWA registry resolves absolute icon paths (data-model.md lines 252-254)."""
        # Setup: Mock PWA registry
        with patch('workspace_panel.PWA_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_pwa_registry))):
            with patch.object(DesktopIconIndex, '_resolve_icon') as mock_resolve:
                # PWA icons are absolute paths, should pass through
                mock_resolve.return_value = "/etc/nixos/assets/pwa-icons/claude.png"
                index = DesktopIconIndex()

        # Test: Lookup by PWA app_id (ffpwa-{ulid} format)
        result = index.lookup(app_id="ffpwa-01jcyf8z2vqrstuvwxyz123456", window_class=None, window_instance=None)

        # Verify: Absolute PWA icon path should be returned
        assert result["icon"] == "/etc/nixos/assets/pwa-icons/claude.png", \
            "PWA registry should return absolute icon path"
        assert result["name"] == "Claude", \
            "PWA display name should be correct"

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=True)
    def test_pwa_app_id_format_case_insensitive(self, mock_pwa_exists, mock_app_exists, mock_pwa_registry):
        """Test that PWA app_id lookup is case-insensitive (data-model.md line 249)."""
        # Setup
        with patch('workspace_panel.PWA_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_pwa_registry))):
            with patch.object(DesktopIconIndex, '_resolve_icon') as mock_resolve:
                mock_resolve.return_value = "/etc/nixos/assets/pwa-icons/claude.png"
                index = DesktopIconIndex()

        # Test: Lookup with uppercase FFPWA (Sway may return this)
        result = index.lookup(app_id="FFPWA-01JCYF8Z2VQRSTUVWXYZ123456", window_class=None, window_instance=None)

        # Verify: Should match despite uppercase
        assert result["icon"] == "/etc/nixos/assets/pwa-icons/claude.png", \
            "PWA lookup should be case-insensitive"


class TestIconResolutionFallback:
    """Test fallback behavior when icons not found."""

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    def test_empty_dict_returned_when_no_match(self):
        """Test that empty dict is returned when no icon found (data-model.md line 154)."""
        # Setup: Empty index
        index = DesktopIconIndex()

        # Test: Lookup nonexistent app
        result = index.lookup(app_id="nonexistent-app", window_class=None, window_instance=None)

        # Verify: Should return empty dict (not None, not exception)
        assert result == {}, "Empty dict should be returned when no match found"
        assert isinstance(result, dict), "Result must be dict type"
