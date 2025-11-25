"""
Unit Tests for Nix File Editing Service

Feature 094: Enhanced Projects & Applications CRUD Interface (User Story 7 - T043)
Tests app_registry_editor.py service for editing app-registry-data.nix

Tests text-based Nix expression manipulation for CRUD operations on mkApp blocks
"""

import pytest
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, patch

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))

from i3_project_manager.services.app_registry_editor import AppRegistryEditor
from i3_project_manager.models.app_config import ApplicationConfig, PWAConfig


@pytest.fixture
def temp_nix_file():
    """Create temporary Nix file with sample mkApp entries"""
    temp = Path(tempfile.mkdtemp(prefix="test_nix_"))
    nix_file = temp / "app-registry-data.nix"
    
    # Sample Nix file content with mkApp entries
    nix_file.write_text("""# Application Registry Data
# This file defines all applications for i3pm

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

  (mkApp {
    name = "terminal";
    display_name = "Terminal";
    command = "ghostty";
    parameters = ["-e" "bash"];
    scope = "scoped";
    expected_class = "ghostty";
    preferred_workspace = 1;
    icon = "🖥️";
    nix_package = pkgs.ghostty;
    multi_instance = true;
    floating = false;
    description = "Terminal emulator";
    terminal = true;
  })

  (mkApp {
    name = "youtube-pwa";
    display_name = "YouTube";
    command = "firefoxpwa";
    parameters = ["site" "launch" "01JCYF8Z2M0N3P4Q5R6S7T8V9W"];
    scope = "global";
    expected_class = "FFPWA-01JCYF8Z2M0N3P4Q5R6S7T8V9W";
    preferred_workspace = 50;
    icon = "/etc/nixos/assets/icons/youtube.svg";
    ulid = "01JCYF8Z2M0N3P4Q5R6S7T8V9W";
    start_url = "https://www.youtube.com";
    scope_url = "https://www.youtube.com/";
    app_scope = "scoped";
    categories = "Network;AudioVideo;";
    keywords = "youtube;video;";
    description = "YouTube video platform";
    terminal = false;
  })
]
""")
    
    yield nix_file
    shutil.rmtree(temp, ignore_errors=True)


@pytest.fixture
def editor(temp_nix_file):
    """Create AppRegistryEditor instance with temp file"""
    return AppRegistryEditor(nix_file_path=str(temp_nix_file))


class TestNixFileReading:
    """Test reading and parsing Nix file"""

    def test_read_nix_file_success(self, editor):
        """Should successfully read Nix file"""
        content = editor.read_file()
        assert "mkApp" in content
        assert "firefox" in content
        assert "terminal" in content

    def test_find_app_block(self, editor):
        """Should find mkApp block by name"""
        block = editor.find_app_block("firefox")
        assert block is not None
        assert "firefox" in block
        assert "display_name = \"Firefox\"" in block

    def test_find_nonexistent_app_block(self, editor):
        """Should return None for nonexistent app"""
        block = editor.find_app_block("nonexistent-app")
        assert block is None

    def test_find_pwa_block(self, editor):
        """Should find PWA mkApp block"""
        block = editor.find_app_block("youtube-pwa")
        assert block is not None
        assert "ulid" in block
        assert "start_url" in block
        assert "01JCYF8Z2M0N3P4Q5R6S7T8V9W" in block


class TestFieldParsing:
    """Test parsing individual fields from mkApp blocks"""

    def test_parse_string_field(self, editor):
        """Should parse string field correctly"""
        block = editor.find_app_block("firefox")
        value = editor.parse_field(block, "display_name")
        assert value == "Firefox"

    def test_parse_integer_field(self, editor):
        """Should parse integer field correctly"""
        block = editor.find_app_block("firefox")
        value = editor.parse_field(block, "preferred_workspace")
        assert value == 3

    def test_parse_boolean_field(self, editor):
        """Should parse boolean field correctly"""
        block = editor.find_app_block("firefox")
        value = editor.parse_field(block, "terminal")
        assert value is False
        
        block = editor.find_app_block("terminal")
        value = editor.parse_field(block, "terminal")
        assert value is True

    def test_parse_list_field(self, editor):
        """Should parse list field correctly"""
        block = editor.find_app_block("terminal")
        value = editor.parse_field(block, "parameters")
        assert value == ["-e", "bash"]

    def test_parse_empty_list_field(self, editor):
        """Should parse empty list correctly"""
        block = editor.find_app_block("firefox")
        value = editor.parse_field(block, "parameters")
        assert value == []

    def test_parse_enum_field(self, editor):
        """Should parse enum field correctly"""
        block = editor.find_app_block("firefox")
        value = editor.parse_field(block, "scope")
        assert value == "global"

    def test_parse_optional_field_present(self, editor):
        """Should parse optional field when present"""
        block = editor.find_app_block("firefox")
        value = editor.parse_field(block, "preferred_monitor_role")
        assert value == "primary"

    def test_parse_optional_field_absent(self, editor):
        """Should return None for absent optional field"""
        block = editor.find_app_block("terminal")
        value = editor.parse_field(block, "preferred_monitor_role")
        assert value is None


class TestFieldEditing:
    """Test editing individual fields in mkApp blocks"""

    def test_edit_string_field(self, editor):
        """Should update string field correctly"""
        block = editor.find_app_block("firefox")
        new_block = editor.update_field(block, "display_name", "Firefox Browser")
        
        assert "display_name = \"Firefox Browser\"" in new_block
        assert "display_name = \"Firefox\"" not in new_block

    def test_edit_integer_field(self, editor):
        """Should update integer field correctly"""
        block = editor.find_app_block("firefox")
        new_block = editor.update_field(block, "preferred_workspace", 5)
        
        assert "preferred_workspace = 5" in new_block
        assert "preferred_workspace = 3" not in new_block

    def test_edit_boolean_field(self, editor):
        """Should update boolean field correctly"""
        block = editor.find_app_block("firefox")
        new_block = editor.update_field(block, "floating", True)
        
        assert "floating = true" in new_block
        assert "floating = false" not in new_block

    def test_edit_list_field(self, editor):
        """Should update list field correctly"""
        block = editor.find_app_block("terminal")
        new_block = editor.update_field(block, "parameters", ["-e", "zsh"])
        
        assert '"-e" "zsh"' in new_block or '[ "-e" "zsh" ]' in new_block

    def test_edit_optional_field_add(self, editor):
        """Should add optional field when not present"""
        block = editor.find_app_block("terminal")
        new_block = editor.update_field(block, "preferred_monitor_role", "secondary")
        
        assert "preferred_monitor_role = \"secondary\"" in new_block

    def test_edit_optional_field_remove(self, editor):
        """Should remove optional field when set to None"""
        block = editor.find_app_block("firefox")
        new_block = editor.update_field(block, "preferred_monitor_role", None)
        
        # Field should be removed or commented out
        assert "preferred_monitor_role" not in new_block or "# preferred_monitor_role" in new_block


class TestApplicationEditing:
    """Test complete application edit workflow"""

    def test_edit_regular_app_success(self, editor):
        """Should successfully edit regular application"""
        updates = {
            "display_name": "Firefox Web Browser",
            "preferred_workspace": 5,
            "icon": "🦊"
        }
        
        result = editor.edit_application("firefox", updates)
        
        assert result.success is True
        assert result.backup_path is not None
        
        # Verify changes in file
        content = editor.read_file()
        assert "Firefox Web Browser" in content
        assert "preferred_workspace = 5" in content
        assert "🦊" in content

    def test_edit_terminal_app_success(self, editor):
        """Should successfully edit terminal application"""
        updates = {
            "display_name": "My Terminal",
            "parameters": ["-e", "tmux"]
        }
        
        result = editor.edit_application("terminal", updates)
        
        assert result.success is True
        content = editor.read_file()
        assert "My Terminal" in content
        assert "tmux" in content

    def test_edit_pwa_success(self, editor):
        """Should successfully edit PWA application"""
        updates = {
            "display_name": "YouTube Music",
            "preferred_workspace": 51
        }
        
        result = editor.edit_application("youtube-pwa", updates)
        
        assert result.success is True
        content = editor.read_file()
        assert "YouTube Music" in content
        assert "preferred_workspace = 51" in content

    def test_edit_nonexistent_app_fails(self, editor):
        """Should fail when editing nonexistent application"""
        updates = {"display_name": "New Name"}
        
        result = editor.edit_application("nonexistent-app", updates)
        
        assert result.success is False
        assert "not found" in result.error_message.lower()

    def test_edit_with_validation_error(self, editor):
        """Should fail when validation errors occur"""
        updates = {
            "preferred_workspace": 100  # Invalid workspace
        }
        
        result = editor.edit_application("firefox", updates)
        
        assert result.success is False
        assert "workspace" in result.error_message.lower()


class TestBackupAndRestore:
    """Test backup creation and restoration"""

    def test_create_backup(self, editor, temp_nix_file):
        """Should create backup file before editing"""
        original_content = editor.read_file()
        
        backup_path = editor.create_backup()
        
        assert backup_path.exists()
        assert backup_path.suffix == ".backup"
        backup_content = backup_path.read_text()
        assert backup_content == original_content

    def test_restore_from_backup(self, editor, temp_nix_file):
        """Should restore from backup after failed edit"""
        original_content = editor.read_file()
        
        # Create backup
        backup_path = editor.create_backup()
        
        # Corrupt the file
        temp_nix_file.write_text("CORRUPTED")
        
        # Restore from backup
        editor.restore_from_backup(backup_path)
        
        # Verify restoration
        restored_content = editor.read_file()
        assert restored_content == original_content

    def test_auto_backup_on_edit(self, editor):
        """Should automatically create backup on edit"""
        updates = {"display_name": "New Name"}
        
        result = editor.edit_application("firefox", updates)
        
        assert result.backup_path is not None
        assert Path(result.backup_path).exists()

    def test_cleanup_old_backups(self, editor, temp_nix_file):
        """Should clean up old backup files (keep last 5)"""
        # Create 10 backups
        backup_dir = temp_nix_file.parent / "backups"
        backup_dir.mkdir(exist_ok=True)
        
        for i in range(10):
            backup_file = backup_dir / f"backup_{i}.nix.backup"
            backup_file.write_text(f"backup {i}")
        
        editor.cleanup_old_backups(max_keep=5)
        
        remaining_backups = list(backup_dir.glob("*.backup"))
        assert len(remaining_backups) == 5


class TestNixSyntaxValidation:
    """Test Nix syntax validation after edits"""

    def test_validate_valid_nix_syntax(self, editor, temp_nix_file):
        """Should pass validation for valid Nix syntax"""
        result = editor.validate_nix_syntax(str(temp_nix_file))
        
        assert result.valid is True
        assert result.error_message == ""

    def test_validate_invalid_nix_syntax(self, editor, temp_nix_file):
        """Should fail validation for invalid Nix syntax"""
        # Corrupt the file with invalid syntax
        temp_nix_file.write_text("{ invalid nix syntax }")
        
        result = editor.validate_nix_syntax(str(temp_nix_file))
        
        assert result.valid is False
        assert len(result.error_message) > 0

    def test_auto_validate_after_edit(self, editor):
        """Should automatically validate after successful edit"""
        updates = {"display_name": "New Name"}
        
        with patch.object(editor, 'validate_nix_syntax') as mock_validate:
            mock_validate.return_value = Mock(valid=True, error_message="")
            result = editor.edit_application("firefox", updates)
            
            mock_validate.assert_called_once()

    def test_restore_backup_on_invalid_syntax(self, editor, temp_nix_file):
        """Should restore from backup if syntax becomes invalid after edit"""
        original_content = editor.read_file()
        
        # Mock validation to return invalid
        with patch.object(editor, 'validate_nix_syntax') as mock_validate:
            mock_validate.return_value = Mock(valid=False, error_message="Syntax error")
            
            updates = {"display_name": "New Name"}
            result = editor.edit_application("firefox", updates)
            
            # Should have restored from backup
            current_content = editor.read_file()
            assert current_content == original_content


class TestConcurrencyAndLocking:
    """Test file locking for concurrent edits"""

    def test_acquire_file_lock(self, editor, temp_nix_file):
        """Should acquire exclusive lock before editing"""
        with editor.acquire_lock():
            # Lock should be held
            assert editor.is_locked() is True
        
        # Lock should be released
        assert editor.is_locked() is False

    def test_fail_on_locked_file(self, editor):
        """Should fail if file is locked by another process"""
        # Simulate another process holding lock
        with editor.acquire_lock():
            # Try to edit while locked
            updates = {"display_name": "New Name"}
            result = editor.edit_application("firefox", updates, wait_for_lock=False)
            
            assert result.success is False
            assert "locked" in result.error_message.lower()


class TestErrorHandling:
    """Test error handling for various failure scenarios"""

    def test_handle_file_not_found(self):
        """Should handle missing Nix file gracefully"""
        editor = AppRegistryEditor(nix_file_path="/nonexistent/file.nix")
        
        with pytest.raises(FileNotFoundError):
            editor.read_file()

    def test_handle_permission_error(self, editor, temp_nix_file):
        """Should handle permission errors gracefully"""
        # Make file read-only
        temp_nix_file.chmod(0o444)
        
        updates = {"display_name": "New Name"}
        result = editor.edit_application("firefox", updates)
        
        assert result.success is False
        assert "permission" in result.error_message.lower()
        
        # Restore permissions for cleanup
        temp_nix_file.chmod(0o644)

    def test_handle_disk_full_error(self, editor):
        """Should handle disk full errors gracefully"""
        with patch('builtins.open', side_effect=OSError("No space left on device")):
            updates = {"display_name": "New Name"}
            result = editor.edit_application("firefox", updates)
            
            assert result.success is False
            assert "space" in result.error_message.lower()


class TestMultipleFieldEdits:
    """Test editing multiple fields at once"""

    def test_edit_multiple_fields(self, editor):
        """Should successfully edit multiple fields in one operation"""
        updates = {
            "display_name": "Firefox Browser",
            "preferred_workspace": 5,
            "icon": "🦊",
            "floating": True,
            "floating_size": "medium"
        }
        
        result = editor.edit_application("firefox", updates)
        
        assert result.success is True
        content = editor.read_file()
        assert "Firefox Browser" in content
        assert "preferred_workspace = 5" in content
        assert "🦊" in content
        assert "floating = true" in content
        assert 'floating_size = "medium"' in content

    def test_edit_preserves_unchanged_fields(self, editor):
        """Should preserve fields not included in updates"""
        updates = {"display_name": "New Firefox"}

        result = editor.edit_application("firefox", updates)

        assert result.success is True
        content = editor.read_file()
        # These fields should remain unchanged
        assert "command = \"firefox\"" in content
        assert "scope = \"global\"" in content
        assert "expected_class = \"firefox\"" in content


# =============================================================================
# User Story 8 (T071): ULID Generation Tests
# =============================================================================


class TestULIDGeneration:
    """Test ULID generation for PWAs"""

    def test_generate_ulid_returns_valid_format(self, editor):
        """Generated ULID should have valid format"""
        ulid = editor._generate_ulid()

        # ULID should be 26 characters
        assert len(ulid) == 26

        # First character must be 0-7 (timestamp constraint)
        assert ulid[0] in "01234567"

        # All characters must be Crockford Base32 (no I, L, O, U)
        valid_chars = set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        assert all(c in valid_chars for c in ulid)

    def test_generate_ulid_is_unique(self, editor):
        """Each generated ULID should be unique"""
        ulids = set()
        for _ in range(100):
            ulid = editor._generate_ulid()
            assert ulid not in ulids, f"Duplicate ULID generated: {ulid}"
            ulids.add(ulid)

    def test_ulid_format_regex_validation(self, editor):
        """ULID should match expected regex pattern"""
        import re
        ulid = editor._generate_ulid()

        # Pattern: first char 0-7, rest is Crockford Base32
        pattern = r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$'
        assert re.match(pattern, ulid), f"ULID {ulid} doesn't match expected pattern"

    def test_ulid_excludes_invalid_characters(self, editor):
        """ULID should not contain I, L, O, U characters"""
        for _ in range(50):
            ulid = editor._generate_ulid()
            assert 'I' not in ulid, "ULID should not contain 'I'"
            assert 'L' not in ulid, "ULID should not contain 'L'"
            assert 'O' not in ulid, "ULID should not contain 'O'"
            assert 'U' not in ulid, "ULID should not contain 'U'"


class TestPWACreationWithULID:
    """Test PWA creation with ULID handling"""

    def test_create_pwa_with_valid_ulid(self, editor):
        """Creating PWA with valid ULID should succeed"""
        # Generate a valid ULID for the test
        test_ulid = editor._generate_ulid()
        config = PWAConfig(
            name="test-pwa",
            display_name="Test PWA",
            command="firefoxpwa",
            parameters=["site", "launch", test_ulid],
            expected_class=f"FFPWA-{test_ulid}",
            preferred_workspace=50,
            ulid=test_ulid,
            start_url="https://test.example.com",
            scope_url="https://test.example.com/"
        )

        result = editor.add_application(config)

        assert result["status"] == "success"
        assert result["ulid"] is not None
        assert len(result["ulid"]) == 26

    def test_create_pwa_with_provided_ulid(self, editor):
        """Creating PWA with provided ULID should use it"""
        provided_ulid = "01JCYF8Z2M0N3P4Q5R6S7T8V9W"
        config = PWAConfig(
            name="custom-pwa",
            display_name="Custom PWA",
            command="firefoxpwa",
            parameters=["site", "launch", provided_ulid],
            expected_class=f"FFPWA-{provided_ulid}",
            preferred_workspace=51,
            ulid=provided_ulid,
            start_url="https://custom.example.com",
            scope_url="https://custom.example.com/"
        )

        result = editor.add_application(config)

        assert result["status"] == "success"
        content = editor.read_file()
        assert provided_ulid in content

    def test_pwa_expected_class_pattern_enforced(self, editor):
        """PWA expected_class must match FFPWA-{ULID} pattern"""
        test_ulid = editor._generate_ulid()

        # Try creating PWA with invalid expected_class (missing ULID)
        with pytest.raises(Exception) as exc_info:
            PWAConfig(
                name="invalid-class-pwa",
                display_name="Invalid Class PWA",
                command="firefoxpwa",
                parameters=["site", "launch", test_ulid],
                expected_class="FFPWA",  # Invalid - missing ULID suffix
                preferred_workspace=52,
                ulid=test_ulid,
                start_url="https://test.example.com",
                scope_url="https://test.example.com/"
            )

        # Should fail validation at model level
        assert "expected_class" in str(exc_info.value).lower() or "pattern" in str(exc_info.value).lower()


class TestULIDUniquenessValidation:
    """Test ULID uniqueness validation"""

    def test_duplicate_app_name_rejected(self, editor):
        """Should reject PWA with duplicate name"""
        test_ulid1 = editor._generate_ulid()
        test_ulid2 = editor._generate_ulid()

        # First PWA
        config1 = PWAConfig(
            name="first-pwa",
            display_name="First PWA",
            command="firefoxpwa",
            parameters=["site", "launch", test_ulid1],
            expected_class=f"FFPWA-{test_ulid1}",
            preferred_workspace=50,
            ulid=test_ulid1,
            start_url="https://first.example.com",
            scope_url="https://first.example.com/"
        )
        result1 = editor.add_application(config1)
        assert result1["status"] == "success"

        # Second PWA with same name (different ULID)
        config2 = PWAConfig(
            name="first-pwa",  # Same name as first
            display_name="First PWA Again",
            command="firefoxpwa",
            parameters=["site", "launch", test_ulid2],
            expected_class=f"FFPWA-{test_ulid2}",
            preferred_workspace=51,
            ulid=test_ulid2,
            start_url="https://first-again.example.com",
            scope_url="https://first-again.example.com/"
        )

        # Should fail due to duplicate name
        with pytest.raises(ValueError) as exc_info:
            editor.add_application(config2)

        assert "already exists" in str(exc_info.value).lower()


class TestApplicationDeletion:
    """Feature 094 US9 T090: Tests for application deletion from Nix file"""

    def test_delete_regular_app_success(self, editor, temp_nix_file):
        """Deleting a regular app should remove its mkApp block"""
        # Terminal app exists in fixture
        result = editor.delete_application("terminal")

        assert result["status"] == "success"

        # Verify it's removed from Nix file
        content = temp_nix_file.read_text()
        assert "name = \"terminal\"" not in content
        assert 'display_name = "Terminal"' not in content

        # Verify other apps still exist
        assert "name = \"firefox\"" in content
        assert "name = \"youtube-pwa\"" in content

    def test_delete_pwa_success(self, editor, temp_nix_file):
        """Deleting a PWA should remove its mkApp block"""
        result = editor.delete_application("youtube-pwa")

        assert result["status"] == "success"

        # Verify it's removed
        content = temp_nix_file.read_text()
        assert "name = \"youtube-pwa\"" not in content
        assert "01JCYF8Z2M0N3P4Q5R6S7T8V9W" not in content

        # Verify other apps still exist
        assert "name = \"firefox\"" in content
        assert "name = \"terminal\"" in content

    def test_delete_nonexistent_app_fails(self, editor):
        """Deleting a nonexistent app should fail with ValueError"""
        with pytest.raises(ValueError) as exc_info:
            editor.delete_application("nonexistent-app")

        assert "not found" in str(exc_info.value).lower()

    def test_delete_app_preserves_nix_syntax(self, editor, temp_nix_file):
        """After deletion, Nix file should have valid syntax"""
        # Delete an app
        result = editor.delete_application("terminal")
        assert result["status"] == "success"

        # Verify file can still be parsed (basic syntax check)
        content = temp_nix_file.read_text()
        # Check balanced brackets
        assert content.count("[") == content.count("]")
        assert content.count("(") == content.count(")")
        # Check it still has the array structure
        assert "[" in content
        assert "mkApp" in content

    def test_delete_returns_pwa_warning(self, editor, temp_nix_file):
        """Deleting a PWA should return warning with ULID for uninstall"""
        result = editor.delete_application("youtube-pwa")

        assert result["status"] == "success"
        # For PWA, should include pwa_warning with ULID
        assert "pwa_warning" in result
        assert "01JCYF8Z2M0N3P4Q5R6S7T8V9W" in result["pwa_warning"]
        assert "pwa-uninstall" in result["pwa_warning"]

    def test_delete_all_apps_leaves_valid_empty_list(self, editor, temp_nix_file):
        """Deleting all apps should leave valid empty list structure"""
        # Delete all three apps
        editor.delete_application("firefox")
        editor.delete_application("terminal")
        editor.delete_application("youtube-pwa")

        # Verify file structure is still valid
        content = temp_nix_file.read_text()
        assert "[" in content
        assert "]" in content
        # Should have no mkApp blocks left (or just the empty list)
        assert "name = \"firefox\"" not in content
        assert "name = \"terminal\"" not in content
        assert "name = \"youtube-pwa\"" not in content
