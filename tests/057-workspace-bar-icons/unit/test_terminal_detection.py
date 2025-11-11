"""Unit tests for terminal application icon detection (T022-T024)."""
import json
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, mock_open
import sys

# Add workspace_panel module to path for import
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules" / "tools" / "sway-workspace-panel"))

from workspace_panel import DesktopIconIndex


class TestTerminalAppDetection:
    """Test window_instance matching for terminal apps (research.md lines 69-74)."""

    @pytest.fixture
    def mock_app_registry_with_terminal_apps(self):
        """Mock application registry with terminal app entries."""
        return {
            "version": "1.0",
            "applications": [
                {
                    "name": "lazygit",
                    "display_name": "lazygit",
                    "command": "ghostty -e lazygit",
                    "expected_class": "ghostty",
                    "expected_instance": "lazygit",
                    "icon": "lazygit",
                    "scope": "scoped",
                    "preferred_workspace": 7,
                },
                {
                    "name": "yazi",
                    "display_name": "Yazi",
                    "command": "ghostty -e yazi",
                    "expected_class": "ghostty",
                    "expected_instance": "yazi",
                    "icon": "yazi",
                    "scope": "scoped",
                    "preferred_workspace": 8,
                },
                {
                    "name": "btop",
                    "display_name": "btop",
                    "command": "ghostty -e btop",
                    "expected_class": "ghostty",
                    "expected_instance": "btop",
                    "icon": "btop",
                    "scope": "global",
                    "preferred_workspace": 7,
                }
            ]
        }

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True)
    def test_terminal_app_lazygit_resolves_via_window_instance(self, mock_app_exists, mock_pwa_exists, mock_app_registry_with_terminal_apps):
        """Test that lazygit terminal app resolves to lazygit icon (not ghostty icon) via window_instance."""
        # Setup: Mock app registry with terminal apps
        with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_app_registry_with_terminal_apps))):
            with patch.object(DesktopIconIndex, '_resolve_icon') as mock_resolve:
                # Simulate icon resolution
                def resolve_side_effect(icon_name):
                    return f"/usr/share/icons/{icon_name}.svg" if icon_name else None

                mock_resolve.side_effect = resolve_side_effect
                index = DesktopIconIndex()

        # Test: Lookup with ghostty class but lazygit instance
        # This simulates: window.app_id="ghostty", window.window_class="ghostty", window.window_instance="lazygit"
        result = index.lookup(
            app_id="ghostty",
            window_class="ghostty",
            window_instance="lazygit"
        )

        # Verify: Should return lazygit icon (NOT ghostty icon)
        assert result.get("icon") == "/usr/share/icons/lazygit.svg", \
            "Terminal app lazygit should resolve to lazygit icon via window_instance"
        assert result.get("name") == "lazygit", \
            "Display name should be lazygit (not Ghostty)"

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True)
    def test_terminal_app_yazi_resolves_via_window_instance(self, mock_app_exists, mock_pwa_exists, mock_app_registry_with_terminal_apps):
        """Test that yazi terminal app resolves to yazi icon via window_instance (T023)."""
        # Setup
        with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_app_registry_with_terminal_apps))):
            with patch.object(DesktopIconIndex, '_resolve_icon') as mock_resolve:
                def resolve_side_effect(icon_name):
                    return f"/usr/share/icons/{icon_name}.svg" if icon_name else None
                mock_resolve.side_effect = resolve_side_effect
                index = DesktopIconIndex()

        # Test: Lookup yazi via window_instance
        result = index.lookup(
            app_id="ghostty",
            window_class="ghostty",
            window_instance="yazi"
        )

        # Verify
        assert result.get("icon") == "/usr/share/icons/yazi.svg", \
            "Yazi should resolve to yazi icon"
        assert result.get("name") == "Yazi"

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True)
    def test_terminal_app_btop_resolves_via_window_instance(self, mock_app_exists, mock_pwa_exists, mock_app_registry_with_terminal_apps):
        """Test that btop terminal app resolves to btop icon via window_instance (T024)."""
        # Setup
        with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mock_app_registry_with_terminal_apps))):
            with patch.object(DesktopIconIndex, '_resolve_icon') as mock_resolve:
                def resolve_side_effect(icon_name):
                    return f"/usr/share/icons/{icon_name}.svg" if icon_name else None
                mock_resolve.side_effect = resolve_side_effect
                index = DesktopIconIndex()

        # Test: Lookup btop via window_instance
        result = index.lookup(
            app_id="ghostty",
            window_class="ghostty",
            window_instance="btop"
        )

        # Verify
        assert result.get("icon") == "/usr/share/icons/btop.svg", \
            "btop should resolve to btop icon"
        assert result.get("name") == "btop"


class TestTerminalAppFallback:
    """Test fallback behavior for terminal apps without registry entry."""

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=False)
    def test_terminal_app_without_registry_falls_back_to_ghostty(self):
        """Test that terminal app without registry entry falls back to ghostty icon."""
        # Setup: Empty registry
        index = DesktopIconIndex()

        # Manually add ghostty desktop entry (simulating desktop file fallback)
        index._by_desktop_id["ghostty"] = {
            "icon": "/usr/share/icons/ghostty.svg",
            "name": "Ghostty Terminal"
        }

        # Test: Lookup terminal app not in registry
        result = index.lookup(
            app_id="ghostty",
            window_class="ghostty",
            window_instance="unknown-terminal-app"
        )

        # Verify: Should fall back to ghostty icon (generic terminal)
        assert result.get("icon") == "/usr/share/icons/ghostty.svg", \
            "Unknown terminal app should fall back to Ghostty icon"


class TestTerminalAppRegistryExtended:
    """Test that terminal apps extend the existing application registry pattern."""

    @patch('workspace_panel.DESKTOP_DIRS', [])
    @patch('workspace_panel.PWA_REGISTRY_PATH.exists', return_value=False)
    @patch('workspace_panel.APP_REGISTRY_PATH.exists', return_value=True)
    def test_terminal_apps_coexist_with_regular_apps_in_registry(self, mock_app_exists, mock_pwa_exists):
        """Test that terminal apps and regular apps coexist in same registry."""
        mixed_registry = {
            "version": "1.0",
            "applications": [
                {
                    "name": "firefox",
                    "display_name": "Firefox",
                    "icon": "firefox",
                },
                {
                    "name": "lazygit",
                    "display_name": "lazygit",
                    "command": "ghostty -e lazygit",
                    "expected_class": "ghostty",
                    "expected_instance": "lazygit",
                    "icon": "lazygit",
                }
            ]
        }

        # Setup
        with patch('workspace_panel.APP_REGISTRY_PATH.open', mock_open(read_data=json.dumps(mixed_registry))):
            with patch.object(DesktopIconIndex, '_resolve_icon') as mock_resolve:
                def resolve_side_effect(icon_name):
                    return f"/icons/{icon_name}.svg" if icon_name else None
                mock_resolve.side_effect = resolve_side_effect
                index = DesktopIconIndex()

        # Test: Both apps should be indexed
        firefox_result = index.lookup(app_id="firefox", window_class=None, window_instance=None)
        lazygit_result = index.lookup(app_id="ghostty", window_class="ghostty", window_instance="lazygit")

        # Verify: Both should resolve correctly
        assert firefox_result.get("icon") == "/icons/firefox.svg"
        assert lazygit_result.get("icon") == "/icons/lazygit.svg"
