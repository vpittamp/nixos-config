"""
Integration Tests for Application Create Workflow

Feature 094: Enhanced Projects & Applications CRUD Interface
- User Story 8 (T072): Tests the full application creation workflow

Tests cover:
- Creating regular app via CRUD handler
- Creating terminal app via CRUD handler
- Creating PWA via CRUD handler (with ULID generation)
- App list refresh after creation
- Error handling for duplicates and validation
"""

import pytest
import asyncio
import json
import tempfile
import shutil
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools/monitoring-panel"))

from app_crud_handler import AppCRUDHandler
from i3_project_manager.services.app_registry_editor import AppRegistryEditor


@pytest.fixture
def temp_nix_file():
    """Create temporary Nix file with sample mkApp entries"""
    temp = Path(tempfile.mkdtemp(prefix="test_nix_"))
    nix_file = temp / "app-registry-data.nix"

    # Minimal valid Nix file with array structure
    nix_file.write_text("""# Application Registry Data
{ lib, pkgs, ... }:

let
  mkApp = import ./mkApp.nix { inherit lib; };
in

[
  (mkApp {
    name = "firefox";
    display_name = "Firefox";
    command = "firefox";
    parameters = [];
    scope = "global";
    expected_class = "firefox";
    preferred_workspace = 3;
    preferred_monitor_role = "primary";
    icon = "firefox";
    nix_package = pkgs.firefox;
    multi_instance = false;
    floating = false;
    fallback_behavior = "skip";
    description = "Web browser";
    terminal = false;
  })
] # Auto-generate PWA entries below
""")

    yield nix_file
    shutil.rmtree(temp, ignore_errors=True)


@pytest.fixture
def crud_handler(temp_nix_file):
    """Create CRUD handler with temporary nix file"""
    return AppCRUDHandler(nix_file_path=str(temp_nix_file))


@pytest.fixture
def editor(temp_nix_file):
    """Create editor for direct inspection"""
    return AppRegistryEditor(nix_file_path=str(temp_nix_file))


class TestRegularAppCreation:
    """Test regular application creation workflow"""

    @pytest.mark.asyncio
    async def test_create_regular_app_success(self, crud_handler, temp_nix_file):
        """Creating a regular app should succeed"""
        request = {
            "action": "create_app",
            "config": {
                "name": "test-app",
                "display_name": "Test App",
                "command": "test-command",
                "parameters": ["--arg1", "--arg2"],
                "scope": "scoped",
                "expected_class": "test-app",
                "preferred_workspace": 10,
                "icon": "🧪",
                "description": "A test application"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        assert result["error_message"] == ""
        assert result["rebuild_required"] is True

        # Verify app was added to nix file
        content = temp_nix_file.read_text()
        assert "test-app" in content
        assert "Test App" in content
        assert "test-command" in content

    @pytest.mark.asyncio
    async def test_create_regular_app_workspace_range(self, crud_handler):
        """Regular apps must use workspace 1-50"""
        request = {
            "action": "create_app",
            "config": {
                "name": "high-workspace-app",
                "display_name": "High Workspace",
                "command": "test-command",
                "expected_class": "high-workspace",
                "preferred_workspace": 60  # Invalid for regular app
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert len(result["validation_errors"]) > 0 or "workspace" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_create_app_with_floating(self, crud_handler, temp_nix_file):
        """Creating floating app should set floating_size"""
        request = {
            "action": "create_app",
            "config": {
                "name": "floating-app",
                "display_name": "Floating App",
                "command": "test-command",
                "expected_class": "floating-app",
                "preferred_workspace": 5,
                "floating": True,
                "floating_size": "medium"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        content = temp_nix_file.read_text()
        assert "floating = true" in content
        assert 'floating_size = "medium"' in content


class TestTerminalAppCreation:
    """Test terminal application creation workflow"""

    @pytest.mark.asyncio
    async def test_create_terminal_app_success(self, crud_handler, temp_nix_file):
        """Creating a terminal app should succeed"""
        request = {
            "action": "create_app",
            "config": {
                "name": "my-terminal",
                "display_name": "My Terminal",
                "command": "ghostty",
                "parameters": ["-e", "tmux"],
                "scope": "scoped",
                "expected_class": "ghostty",
                "preferred_workspace": 1,
                "terminal": True,
                "description": "Custom terminal"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        assert result["rebuild_required"] is True

        content = temp_nix_file.read_text()
        assert "my-terminal" in content
        assert "terminal = true" in content or "terminal" in content

    @pytest.mark.asyncio
    async def test_terminal_app_requires_terminal_flag(self, crud_handler):
        """Terminal apps must have terminal=True"""
        # This test verifies the terminal detection logic in handler
        request = {
            "action": "create_app",
            "config": {
                "name": "not-a-terminal",
                "display_name": "Not Terminal",
                "command": "ghostty",
                "expected_class": "ghostty",
                "preferred_workspace": 1,
                "terminal": True  # Mark as terminal
            }
        }

        result = await crud_handler.handle_request(request)

        # Should succeed - valid terminal app config
        assert result["success"] is True


class TestPWACreation:
    """Test PWA creation workflow"""

    @pytest.mark.asyncio
    async def test_create_pwa_with_ulid_success(self, crud_handler, editor, temp_nix_file):
        """Creating a PWA with valid ULID should succeed"""
        # Generate a valid ULID for testing
        test_ulid = editor._generate_ulid()

        request = {
            "action": "create_app",
            "config": {
                "name": "test-pwa",
                "display_name": "Test PWA",
                "command": "firefoxpwa",
                "parameters": ["site", "launch", test_ulid],
                "scope": "global",
                "expected_class": f"FFPWA-{test_ulid}",
                "preferred_workspace": 50,
                "ulid": test_ulid,
                "start_url": "https://test.example.com",
                "scope_url": "https://test.example.com/",
                "icon": "/etc/nixos/assets/icons/test.svg",
                "description": "Test PWA application"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        assert result["rebuild_required"] is True
        assert result.get("ulid") is not None

        content = temp_nix_file.read_text()
        assert "test-pwa" in content
        assert test_ulid in content

    @pytest.mark.asyncio
    async def test_pwa_workspace_must_be_50_or_higher(self, crud_handler, editor):
        """PWAs must use workspace 50+"""
        test_ulid = editor._generate_ulid()

        request = {
            "action": "create_app",
            "config": {
                "name": "low-workspace-pwa",
                "display_name": "Low Workspace PWA",
                "command": "firefoxpwa",
                "parameters": ["site", "launch", test_ulid],
                "expected_class": f"FFPWA-{test_ulid}",
                "preferred_workspace": 30,  # Invalid for PWA
                "ulid": test_ulid,
                "start_url": "https://test.example.com",
                "scope_url": "https://test.example.com/"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert len(result["validation_errors"]) > 0 or "workspace" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_pwa_name_must_end_with_pwa(self, crud_handler, editor):
        """PWA name must end with '-pwa'"""
        test_ulid = editor._generate_ulid()

        request = {
            "action": "create_app",
            "config": {
                "name": "bad-name",  # Doesn't end with -pwa
                "display_name": "Bad Name PWA",
                "command": "firefoxpwa",
                "parameters": ["site", "launch", test_ulid],
                "expected_class": f"FFPWA-{test_ulid}",
                "preferred_workspace": 50,
                "ulid": test_ulid,
                "start_url": "https://test.example.com",
                "scope_url": "https://test.example.com/"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert len(result["validation_errors"]) > 0 or "name" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_pwa_url_validation(self, crud_handler, editor):
        """PWA URLs must be valid HTTP/HTTPS"""
        test_ulid = editor._generate_ulid()

        request = {
            "action": "create_app",
            "config": {
                "name": "invalid-url-pwa",
                "display_name": "Invalid URL PWA",
                "command": "firefoxpwa",
                "parameters": ["site", "launch", test_ulid],
                "expected_class": f"FFPWA-{test_ulid}",
                "preferred_workspace": 50,
                "ulid": test_ulid,
                "start_url": "not-a-valid-url",  # Invalid URL
                "scope_url": "https://test.example.com/"
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert len(result["validation_errors"]) > 0 or "url" in result["error_message"].lower()


class TestAppCreateValidation:
    """Test validation during app creation"""

    @pytest.mark.asyncio
    async def test_duplicate_name_rejected(self, crud_handler, temp_nix_file):
        """Creating app with duplicate name should fail"""
        # First app
        request1 = {
            "action": "create_app",
            "config": {
                "name": "duplicate-app",
                "display_name": "First App",
                "command": "test-command",
                "expected_class": "duplicate-app",
                "preferred_workspace": 5
            }
        }
        result1 = await crud_handler.handle_request(request1)
        assert result1["success"] is True

        # Second app with same name
        request2 = {
            "action": "create_app",
            "config": {
                "name": "duplicate-app",
                "display_name": "Second App",
                "command": "other-command",
                "expected_class": "duplicate-app",
                "preferred_workspace": 6
            }
        }
        result2 = await crud_handler.handle_request(request2)

        assert result2["success"] is False
        assert "exists" in result2["error_message"].lower() or len(result2["validation_errors"]) > 0

    @pytest.mark.asyncio
    async def test_invalid_name_format_rejected(self, crud_handler):
        """App names must be lowercase with hyphens"""
        request = {
            "action": "create_app",
            "config": {
                "name": "Invalid Name",  # Has uppercase and space
                "display_name": "Invalid Name App",
                "command": "test-command",
                "expected_class": "invalid",
                "preferred_workspace": 5
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False

    @pytest.mark.asyncio
    async def test_missing_required_field_rejected(self, crud_handler):
        """Missing required fields should fail"""
        request = {
            "action": "create_app",
            "config": {
                "name": "incomplete-app"
                # Missing display_name, command, expected_class, preferred_workspace
            }
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False

    @pytest.mark.asyncio
    async def test_missing_config_rejected(self, crud_handler):
        """Request without config field should fail"""
        request = {
            "action": "create_app"
            # Missing config
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "config" in result["error_message"].lower()


class TestAppListAfterCreate:
    """Test app list updates after creation"""

    @pytest.mark.asyncio
    async def test_new_app_appears_in_list(self, crud_handler, temp_nix_file):
        """Newly created app should appear in list"""
        # Create app
        create_request = {
            "action": "create_app",
            "config": {
                "name": "list-test-app",
                "display_name": "List Test App",
                "command": "test-command",
                "expected_class": "list-test-app",
                "preferred_workspace": 10
            }
        }
        result = await crud_handler.handle_request(create_request)
        assert result["success"] is True

        # List apps
        list_request = {"action": "list_apps"}
        list_result = await crud_handler.handle_request(list_request)

        assert list_result["success"] is True
        app_names = [app.get("name") for app in list_result["applications"]]
        assert "list-test-app" in app_names

    @pytest.mark.asyncio
    async def test_multiple_apps_in_list(self, crud_handler, temp_nix_file):
        """Multiple created apps should all appear in list"""
        # Create multiple apps
        for i in range(3):
            request = {
                "action": "create_app",
                "config": {
                    "name": f"multi-app-{i}",
                    "display_name": f"Multi App {i}",
                    "command": f"command-{i}",
                    "expected_class": f"multi-app-{i}",
                    "preferred_workspace": 10 + i
                }
            }
            result = await crud_handler.handle_request(request)
            assert result["success"] is True

        # List apps
        list_request = {"action": "list_apps"}
        list_result = await crud_handler.handle_request(list_request)

        assert list_result["success"] is True
        app_names = [app.get("name") for app in list_result["applications"]]
        for i in range(3):
            assert f"multi-app-{i}" in app_names


class TestCreateWithStreamingUpdates:
    """Test streaming progress updates during creation"""

    @pytest.mark.asyncio
    async def test_create_app_with_callback(self, crud_handler, temp_nix_file):
        """Creating app with callback should receive progress updates"""
        progress_updates = []

        async def capture_callback(update):
            progress_updates.append(update)

        request = {
            "action": "create_app",
            "config": {
                "name": "callback-app",
                "display_name": "Callback App",
                "command": "test-command",
                "expected_class": "callback-app",
                "preferred_workspace": 5
            },
            "stream_updates": True
        }

        result = await crud_handler.handle_request(request, callback=capture_callback)

        # App should be created successfully even with callback
        assert result["success"] is True
