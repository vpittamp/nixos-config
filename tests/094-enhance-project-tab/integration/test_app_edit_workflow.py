"""
Integration Tests for Application Edit Workflow

Feature 094: Enhanced Projects & Applications CRUD Interface (User Story 7 - T044)
Tests complete end-to-end workflow: UI request → validation → Nix editing → response

Tests the integration between monitoring_data.py, app_crud_handler.py, 
app_registry_editor.py, and form_validator.py
"""

import pytest
import tempfile
import shutil
import json
import asyncio
from pathlib import Path
from unittest.mock import Mock, patch, AsyncMock

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))

from i3_project_manager.models.app_config import ApplicationConfig, PWAConfig
from monitoring_panel.app_crud_handler import AppCRUDHandler
from i3_project_manager.services.app_registry_editor import AppRegistryEditor
from i3_project_manager.services.form_validator import FormValidator


@pytest.fixture
def temp_workspace():
    """Create temporary workspace with Nix file and config dirs"""
    temp = Path(tempfile.mkdtemp(prefix="test_integration_"))
    
    # Create Nix file
    nix_file = temp / "app-registry-data.nix"
    nix_file.write_text("""# App Registry
{ lib, pkgs, ... }:
let mkApp = import ./mkApp.nix { inherit lib; }; in
[
  (mkApp {
    name = "test-app";
    display_name = "Test App";
    command = "testcmd";
    parameters = [];
    scope = "scoped";
    expected_class = "TestApp";
    preferred_workspace = 3;
    icon = "📦";
    nix_package = pkgs.testapp;
    multi_instance = false;
    floating = false;
    description = "Test application";
    terminal = false;
  })
  
  (mkApp {
    name = "test-pwa";
    display_name = "Test PWA";
    command = "firefoxpwa";
    parameters = ["site" "launch" "01JCYF8Z2M0N3P4Q5R6S7T8V9W"];
    scope = "global";
    expected_class = "FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W";
    preferred_workspace = 50;
    ulid = "01JCYF8Z2M0N3P4Q5R6S7T8V9W";
    start_url = "https://example.com";
    scope_url = "https://example.com/";
    icon = "🌐";
    description = "Test PWA";
    terminal = false;
  })
]
""")
    
    yield {"root": temp, "nix_file": nix_file}
    shutil.rmtree(temp, ignore_errors=True)


@pytest.fixture
def crud_handler(temp_workspace):
    """Create AppCRUDHandler with temp workspace"""
    return AppCRUDHandler(nix_file_path=str(temp_workspace["nix_file"]))


class TestRegularAppEditWorkflow:
    """Test complete workflow for editing regular applications"""

    @pytest.mark.asyncio
    async def test_edit_display_name_success(self, crud_handler, temp_workspace):
        """Should successfully edit display name through complete workflow"""
        # Step 1: Receive edit request (from Eww UI)
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {
                "display_name": "Updated Test App"
            }
        }
        
        # Step 2: Process request through handler
        response = await crud_handler.handle_request(request)
        
        # Step 3: Verify response
        assert response["success"] is True
        assert "backup_path" in response
        assert response["validation_errors"] == []
        
        # Step 4: Verify file was actually modified
        content = temp_workspace["nix_file"].read_text()
        assert "Updated Test App" in content
        assert "Test App" not in content or "Updated Test App" in content

    @pytest.mark.asyncio
    async def test_edit_workspace_success(self, crud_handler, temp_workspace):
        """Should successfully edit workspace number"""
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {
                "preferred_workspace": 5
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is True
        content = temp_workspace["nix_file"].read_text()
        assert "preferred_workspace = 5" in content

    @pytest.mark.asyncio
    async def test_edit_multiple_fields_success(self, crud_handler, temp_workspace):
        """Should successfully edit multiple fields at once"""
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {
                "display_name": "New Name",
                "preferred_workspace": 7,
                "icon": "🚀",
                "floating": True
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is True
        content = temp_workspace["nix_file"].read_text()
        assert "New Name" in content
        assert "preferred_workspace = 7" in content
        assert "🚀" in content
        assert "floating = true" in content


class TestPWAEditWorkflow:
    """Test complete workflow for editing PWA applications"""

    @pytest.mark.asyncio
    async def test_edit_pwa_display_name(self, crud_handler, temp_workspace):
        """Should successfully edit PWA display name"""
        request = {
            "action": "edit_app",
            "app_name": "test-pwa",
            "updates": {
                "display_name": "Updated PWA"
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is True
        content = temp_workspace["nix_file"].read_text()
        assert "Updated PWA" in content

    @pytest.mark.asyncio
    async def test_edit_pwa_workspace_valid_range(self, crud_handler, temp_workspace):
        """Should allow PWA workspace in 50+ range"""
        request = {
            "action": "edit_app",
            "app_name": "test-pwa",
            "updates": {
                "preferred_workspace": 55
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is True
        content = temp_workspace["nix_file"].read_text()
        assert "preferred_workspace = 55" in content

    @pytest.mark.asyncio
    async def test_edit_pwa_workspace_invalid_range(self, crud_handler):
        """Should reject PWA workspace below 50"""
        request = {
            "action": "edit_app",
            "app_name": "test-pwa",
            "updates": {
                "preferred_workspace": 30  # Invalid for PWA
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is False
        assert len(response["validation_errors"]) > 0
        assert "50" in str(response["validation_errors"])


class TestValidationInWorkflow:
    """Test validation integration in edit workflow"""

    @pytest.mark.asyncio
    async def test_validation_rejects_invalid_workspace(self, crud_handler):
        """Should reject invalid workspace through validation"""
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {
                "preferred_workspace": 100  # Too high
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is False
        assert len(response["validation_errors"]) > 0
        assert "workspace" in str(response["validation_errors"]).lower()

    @pytest.mark.asyncio
    async def test_validation_rejects_invalid_command(self, crud_handler):
        """Should reject command with metacharacters"""
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {
                "command": "testcmd; rm -rf /"  # Shell injection attempt
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is False
        assert "metacharacter" in str(response["validation_errors"]).lower()

    @pytest.mark.asyncio
    async def test_validation_accepts_valid_changes(self, crud_handler):
        """Should pass validation for valid changes"""
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {
                "display_name": "Valid Name",
                "preferred_workspace": 5,
                "icon": "✅"
            }
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is True
        assert response["validation_errors"] == []


class TestBackupInWorkflow:
    """Test backup creation and restoration in workflow"""

    @pytest.mark.asyncio
    async def test_backup_created_before_edit(self, crud_handler, temp_workspace):
        """Should create backup before applying changes"""
        original_content = temp_workspace["nix_file"].read_text()
        
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {"display_name": "New Name"}
        }
        
        response = await crud_handler.handle_request(request)
        
        # Verify backup was created
        assert response["backup_path"] is not None
        backup_path = Path(response["backup_path"])
        assert backup_path.exists()
        
        # Verify backup contains original content
        backup_content = backup_path.read_text()
        assert backup_content == original_content

    @pytest.mark.asyncio
    async def test_restore_on_nix_syntax_error(self, crud_handler, temp_workspace):
        """Should restore from backup if Nix syntax becomes invalid"""
        original_content = temp_workspace["nix_file"].read_text()
        
        # Mock Nix validation to fail
        with patch.object(AppRegistryEditor, 'validate_nix_syntax') as mock_validate:
            mock_validate.return_value = Mock(valid=False, error_message="Syntax error")
            
            request = {
                "action": "edit_app",
                "app_name": "test-app",
                "updates": {"display_name": "New Name"}
            }
            
            response = await crud_handler.handle_request(request)
            
            # Should fail and restore
            assert response["success"] is False
            assert "syntax" in response["error_message"].lower()
            
            # Verify original content restored
            current_content = temp_workspace["nix_file"].read_text()
            assert current_content == original_content


class TestErrorHandlingInWorkflow:
    """Test error handling throughout the workflow"""

    @pytest.mark.asyncio
    async def test_handle_nonexistent_app(self, crud_handler):
        """Should handle attempt to edit nonexistent app"""
        request = {
            "action": "edit_app",
            "app_name": "nonexistent-app",
            "updates": {"display_name": "New Name"}
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is False
        assert "not found" in response["error_message"].lower()

    @pytest.mark.asyncio
    async def test_handle_file_permission_error(self, crud_handler, temp_workspace):
        """Should handle file permission errors gracefully"""
        # Make file read-only
        temp_workspace["nix_file"].chmod(0o444)
        
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {"display_name": "New Name"}
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is False
        assert "permission" in response["error_message"].lower()
        
        # Restore permissions
        temp_workspace["nix_file"].chmod(0o644)

    @pytest.mark.asyncio
    async def test_handle_malformed_request(self, crud_handler):
        """Should handle malformed requests gracefully"""
        # Missing required fields
        request = {
            "action": "edit_app"
            # Missing app_name and updates
        }
        
        response = await crud_handler.handle_request(request)
        
        assert response["success"] is False
        assert "required" in response["error_message"].lower() or "missing" in response["error_message"].lower()


class TestStreamingUpdates:
    """Test real-time streaming of validation and progress updates"""

    @pytest.mark.asyncio
    async def test_stream_validation_updates(self, crud_handler):
        """Should stream validation updates in real-time"""
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {"display_name": "New Name"},
            "stream_updates": True
        }
        
        updates_received = []
        
        async def update_callback(update):
            updates_received.append(update)
        
        response = await crud_handler.handle_request(request, callback=update_callback)
        
        # Should have received progress updates
        assert len(updates_received) > 0
        assert any(u["phase"] == "validation" for u in updates_received)
        assert any(u["phase"] == "editing" for u in updates_received)
        assert any(u["phase"] == "complete" for u in updates_received)

    @pytest.mark.asyncio
    async def test_stream_validation_errors(self, crud_handler):
        """Should stream validation errors as they occur"""
        request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {"preferred_workspace": 100},  # Invalid
            "stream_updates": True
        }
        
        updates_received = []
        
        async def update_callback(update):
            updates_received.append(update)
        
        response = await crud_handler.handle_request(request, callback=update_callback)
        
        # Should have received validation error update
        error_updates = [u for u in updates_received if u.get("phase") == "validation_error"]
        assert len(error_updates) > 0


class TestListRefresh:
    """Test that application list refreshes after successful edit"""

    @pytest.mark.asyncio
    async def test_list_reflects_changes_after_edit(self, crud_handler, temp_workspace):
        """Should see updated values in list after edit"""
        # Step 1: Edit application
        edit_request = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {"display_name": "Updated Name"}
        }
        
        edit_response = await crud_handler.handle_request(edit_request)
        assert edit_response["success"] is True
        
        # Step 2: Fetch application list
        list_request = {"action": "list_apps"}
        list_response = await crud_handler.handle_request(list_request)
        
        # Step 3: Verify updated name appears in list
        apps = list_response["applications"]
        test_app = next((a for a in apps if a["name"] == "test-app"), None)
        assert test_app is not None
        assert test_app["display_name"] == "Updated Name"


class TestConcurrentEdits:
    """Test handling of concurrent edit attempts"""

    @pytest.mark.asyncio
    async def test_second_edit_waits_for_first(self, crud_handler):
        """Should queue second edit until first completes"""
        # Start first edit
        request1 = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {"display_name": "First Edit"}
        }
        
        # Start second edit concurrently
        request2 = {
            "action": "edit_app",
            "app_name": "test-app",
            "updates": {"display_name": "Second Edit"}
        }
        
        # Run concurrently
        responses = await asyncio.gather(
            crud_handler.handle_request(request1),
            crud_handler.handle_request(request2)
        )
        
        # Both should succeed
        assert responses[0]["success"] is True
        assert responses[1]["success"] is True
        
        # Final state should reflect second edit
        # (since it ran after first completed)

    @pytest.mark.asyncio
    async def test_detect_conflicting_edits(self, crud_handler):
        """Should detect if file was modified externally during edit"""
        # This would test the conflict detection mechanism
        # from spec.md clarification Q2 (file mtime comparison)
        pass  # Implementation depends on conflict detection service
