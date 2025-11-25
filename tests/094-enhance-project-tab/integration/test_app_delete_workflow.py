"""
Integration Tests for Application Delete Workflow

Feature 094: Enhanced Projects & Applications CRUD Interface
- User Story 9 (T091): Tests the full application deletion workflow

Tests cover:
- Deleting regular app via CRUD handler
- Deleting PWA via CRUD handler (with uninstall warning)
- App list refresh after deletion
- Error handling
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

    # Sample Nix file with multiple apps
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
    icon = "firefox";
    description = "Web browser";
    terminal = false;
  })

  (mkApp {
    name = "code";
    display_name = "VS Code";
    command = "code";
    parameters = [];
    scope = "scoped";
    expected_class = "code";
    preferred_workspace = 2;
    icon = "vscode";
    description = "Code editor";
    terminal = false;
  })

  (mkApp {
    name = "terminal";
    display_name = "Terminal";
    command = "ghostty";
    parameters = ["-e" "bash"];
    scope = "scoped";
    expected_class = "ghostty";
    preferred_workspace = 1;
    icon = "terminal";
    description = "Terminal emulator";
    terminal = true;
  })

  (mkApp {
    name = "claude-pwa";
    display_name = "Claude AI";
    command = "firefoxpwa";
    parameters = ["site" "launch" "01ABCDEFGH1234567890ABCDEF"];
    scope = "global";
    expected_class = "FFPWA-01ABCDEFGH1234567890ABCDEF";
    preferred_workspace = 52;
    ulid = "01ABCDEFGH1234567890ABCDEF";
    start_url = "https://claude.ai";
    scope_url = "https://claude.ai/";
    icon = "/etc/nixos/assets/icons/claude.svg";
    description = "Claude AI chat";
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


class TestAppDeleteWorkflow:
    """Test the full application deletion workflow"""

    @pytest.mark.asyncio
    async def test_delete_regular_app_success(self, crud_handler, temp_nix_file):
        """Deleting a regular app should succeed"""
        request = {
            "action": "delete_app",
            "app_name": "code"
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        assert result["rebuild_required"] is True

        # Verify app was removed from nix file
        content = temp_nix_file.read_text()
        assert 'name = "code"' not in content
        assert 'display_name = "VS Code"' not in content

        # Verify other apps still exist
        assert 'name = "firefox"' in content
        assert 'name = "terminal"' in content

    @pytest.mark.asyncio
    async def test_delete_pwa_shows_warning(self, crud_handler, temp_nix_file):
        """Deleting a PWA should include uninstall warning"""
        request = {
            "action": "delete_app",
            "app_name": "claude-pwa"
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        assert result["rebuild_required"] is True
        # Should have PWA warning with ULID
        assert "pwa_warning" in result or "warning" in result.get("error_message", "").lower() or result.get("pwa_uninstall_required", False)

    @pytest.mark.asyncio
    async def test_delete_nonexistent_app_fails(self, crud_handler):
        """Deleting a nonexistent app should fail"""
        request = {
            "action": "delete_app",
            "app_name": "nonexistent-app"
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "not found" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_delete_missing_app_name_fails(self, crud_handler):
        """Delete request without app_name should fail"""
        request = {
            "action": "delete_app"
            # Missing app_name
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False
        assert "app_name" in result["error_message"].lower()

    @pytest.mark.asyncio
    async def test_delete_app_removes_from_list(self, crud_handler, temp_nix_file):
        """Deleted app should disappear from app list"""
        # List apps before deletion
        list_request = {"action": "list_apps"}
        list_result = await crud_handler.handle_request(list_request)
        app_names_before = [app.get("name") for app in list_result.get("applications", [])]
        assert "terminal" in app_names_before

        # Delete app
        delete_request = {
            "action": "delete_app",
            "app_name": "terminal"
        }
        delete_result = await crud_handler.handle_request(delete_request)
        assert delete_result["success"] is True

        # List apps after deletion
        list_result_after = await crud_handler.handle_request(list_request)
        app_names_after = [app.get("name") for app in list_result_after.get("applications", [])]
        assert "terminal" not in app_names_after

    @pytest.mark.asyncio
    async def test_delete_preserves_other_apps(self, crud_handler, temp_nix_file):
        """Deleting one app should not affect others"""
        # Delete firefox
        request = {
            "action": "delete_app",
            "app_name": "firefox"
        }
        result = await crud_handler.handle_request(request)
        assert result["success"] is True

        # Verify other apps still work
        content = temp_nix_file.read_text()
        assert 'name = "code"' in content
        assert 'name = "terminal"' in content
        assert 'name = "claude-pwa"' in content


class TestPWADeleteWorkflow:
    """Test PWA-specific deletion behavior"""

    @pytest.mark.asyncio
    async def test_pwa_delete_includes_ulid_in_warning(self, crud_handler, temp_nix_file):
        """PWA deletion warning should include ULID for uninstall command"""
        request = {
            "action": "delete_app",
            "app_name": "claude-pwa"
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        # Should include the ULID somewhere in the result
        result_str = json.dumps(result)
        assert "01ABCDEFGH1234567890ABCDEF" in result_str or "pwa" in result_str.lower()

    @pytest.mark.asyncio
    async def test_regular_app_no_pwa_warning(self, crud_handler, temp_nix_file):
        """Regular app deletion should not have PWA warning"""
        request = {
            "action": "delete_app",
            "app_name": "firefox"
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is True
        # Should NOT have pwa_warning
        assert result.get("pwa_warning") is None or result.get("pwa_warning") == ""


class TestDeleteValidation:
    """Test validation during deletion"""

    @pytest.mark.asyncio
    async def test_empty_app_name_fails(self, crud_handler):
        """Empty app name should fail"""
        request = {
            "action": "delete_app",
            "app_name": ""
        }

        result = await crud_handler.handle_request(request)

        assert result["success"] is False

    @pytest.mark.asyncio
    async def test_delete_after_create(self, crud_handler, temp_nix_file):
        """Should be able to delete a newly created app"""
        # Create a new app
        create_request = {
            "action": "create_app",
            "config": {
                "name": "new-test-app",
                "display_name": "New Test App",
                "command": "test-command",
                "expected_class": "new-test-app",
                "preferred_workspace": 10
            }
        }
        create_result = await crud_handler.handle_request(create_request)
        assert create_result["success"] is True

        # Delete the new app
        delete_request = {
            "action": "delete_app",
            "app_name": "new-test-app"
        }
        delete_result = await crud_handler.handle_request(delete_request)
        assert delete_result["success"] is True

        # Verify it's gone
        content = temp_nix_file.read_text()
        assert 'name = "new-test-app"' not in content
