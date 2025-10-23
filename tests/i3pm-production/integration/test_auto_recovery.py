"""
Integration tests for automatic recovery

Feature 030: Production Readiness
Task T027: Integration tests for recovery scenarios

Tests complete recovery workflows including state validation,
automatic fixes, and re-validation.
"""

import pytest
import json
from pathlib import Path
from unittest.mock import Mock, AsyncMock
import tempfile

from recovery.auto_recovery import AutoRecovery, RecoveryResult, run_startup_recovery
from validation.state_validator import ValidationResult


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def temp_config_dir(tmp_path):
    """Create temporary config directory"""
    return tmp_path / ".config/i3"


@pytest.fixture
def recovery_system(temp_config_dir):
    """Create auto recovery system with temp config dir"""
    return AutoRecovery(config_dir=temp_config_dir)


# ============================================================================
# RecoveryResult Tests
# ============================================================================

def test_recovery_result_defaults():
    """Test RecoveryResult default state"""
    result = RecoveryResult()
    assert result.success is True
    assert len(result.actions_taken) == 0
    assert len(result.errors) == 0


def test_recovery_result_add_action():
    """Test recording recovery action"""
    result = RecoveryResult()
    result.add_action("Created config directory")

    assert result.success is True
    assert "Created config directory" in result.actions_taken


def test_recovery_result_add_error():
    """Test recording recovery error"""
    result = RecoveryResult()
    result.add_error("Failed to create file")

    assert result.success is False
    assert "Failed to create file" in result.errors


def test_recovery_result_to_dict():
    """Test RecoveryResult serialization"""
    result = RecoveryResult()
    result.add_action("Action 1")
    result.add_error("Error 1")

    data = result.to_dict()

    assert data["success"] is False
    assert "Action 1" in data["actions_taken"]
    assert "Error 1" in data["errors"]
    assert "timestamp" in data


# ============================================================================
# Config Directory Recovery Tests
# ============================================================================

@pytest.mark.asyncio
async def test_recover_missing_config_directory(recovery_system, temp_config_dir):
    """Test recovery creates missing config directory"""
    # Ensure directory doesn't exist
    assert not temp_config_dir.exists()

    # Run recovery
    result = await recovery_system.recover_on_startup()

    # Should create directory
    assert temp_config_dir.exists()
    assert temp_config_dir.is_dir()
    assert any("Created config directory" in a for a in result.actions_taken)


@pytest.mark.asyncio
async def test_recover_missing_projects_directory(recovery_system, temp_config_dir):
    """Test recovery with missing projects directory (warning only)"""
    # Create config dir but not projects dir
    temp_config_dir.mkdir(parents=True)
    projects_dir = temp_config_dir / "projects"
    assert not projects_dir.exists()

    # Run recovery
    result = await recovery_system.recover_on_startup()

    # Missing projects directory is a warning, not an error - no action taken
    assert result.success
    assert result.validation_result.is_valid


@pytest.mark.asyncio
async def test_recover_missing_app_classes_file(recovery_system, temp_config_dir):
    """Test recovery with missing app-classes.json (warning only)"""
    temp_config_dir.mkdir(parents=True)
    app_classes_file = temp_config_dir / "app-classes.json"
    assert not app_classes_file.exists()

    # Run recovery
    result = await recovery_system.recover_on_startup()

    # Missing app-classes file is a warning, not an error - no action taken
    assert result.success
    assert result.validation_result.is_valid


# ============================================================================
# Config File Repair Tests
# ============================================================================

@pytest.mark.asyncio
async def test_recover_corrupted_app_classes_file(recovery_system, temp_config_dir):
    """Test recovery detects corrupted app-classes.json"""
    temp_config_dir.mkdir(parents=True)
    app_classes_file = temp_config_dir / "app-classes.json"

    # Create corrupted file
    with open(app_classes_file, 'w') as f:
        f.write("{ invalid json }")

    # Run recovery
    result = await recovery_system.recover_on_startup()

    # Should detect error but not automatically fix (manual intervention required)
    assert not result.success
    assert any("invalid JSON" in e for e in result.validation_result.errors)


# ============================================================================
# Event Buffer Recovery Tests
# ============================================================================

@pytest.mark.asyncio
async def test_recover_event_buffer_with_none_entries(recovery_system):
    """Test recovery removes None entries from event buffer"""
    # Create buffer with None entries
    mock_buffer = Mock()
    mock_buffer.events = [Mock(), None, Mock(), None, Mock()]
    mock_buffer.max_size = 500

    # Run recovery
    result = await recovery_system.recover_on_startup(event_buffer=mock_buffer)

    # Should remove None entries
    assert None not in mock_buffer.events
    assert len(mock_buffer.events) == 3
    assert any("Repaired event buffer" in a for a in result.actions_taken)


# ============================================================================
# Full Recovery Workflow Tests
# ============================================================================

@pytest.mark.asyncio
async def test_full_recovery_workflow_success(recovery_system, temp_config_dir):
    """Test complete recovery workflow from invalid to valid state"""
    # Start with invalid state (missing everything)
    assert not temp_config_dir.exists()

    # Mock healthy i3 connection
    mock_conn = Mock()
    mock_conn.get_tree.return_value = {"id": 1, "nodes": []}

    # Mock healthy event buffer
    mock_buffer = Mock()
    mock_buffer.events = [Mock(), Mock()]
    mock_buffer.max_size = 500

    # Run recovery
    result = await recovery_system.recover_on_startup(
        i3_connection=mock_conn,
        event_buffer=mock_buffer,
    )

    # Should succeed
    assert result.success
    assert result.validation_result.is_valid

    # Should have created required directories and files
    assert temp_config_dir.exists()
    assert (temp_config_dir / "projects").exists()
    assert (temp_config_dir / "app-classes.json").exists()


@pytest.mark.asyncio
async def test_full_recovery_workflow_with_multiple_issues(recovery_system, temp_config_dir):
    """Test recovery handles multiple issues simultaneously"""
    # Create temp_config_dir with resolvable issues only
    temp_config_dir.mkdir(parents=True)

    # Missing projects directory (warning)
    projects_dir = temp_config_dir / "projects"

    # Mock unhealthy event buffer (fixable error)
    mock_buffer = Mock()
    mock_buffer.events = [Mock(), None, None, Mock()]
    mock_buffer.max_size = 500

    # Run recovery
    result = await recovery_system.recover_on_startup(event_buffer=mock_buffer)

    # Should fix event buffer issue
    assert len(result.actions_taken) >= 1  # At least event buffer repair
    assert None not in mock_buffer.events
    assert any("Repaired event buffer" in a for a in result.actions_taken)


@pytest.mark.asyncio
async def test_recovery_no_action_needed_for_valid_state(recovery_system, temp_config_dir):
    """Test recovery does nothing when state is already valid"""
    # Setup valid state
    temp_config_dir.mkdir(parents=True)
    (temp_config_dir / "projects").mkdir()

    app_classes_file = temp_config_dir / "app-classes.json"
    with open(app_classes_file, 'w') as f:
        json.dump({"scoped_classes": []}, f)

    # Mock healthy components
    mock_conn = Mock()
    mock_conn.get_tree.return_value = {"id": 1, "nodes": []}

    mock_buffer = Mock()
    mock_buffer.events = [Mock(), Mock()]
    mock_buffer.max_size = 500

    # Run recovery
    result = await recovery_system.recover_on_startup(
        i3_connection=mock_conn,
        event_buffer=mock_buffer,
    )

    # Should report no action needed
    assert result.success
    assert any("No recovery needed" in a for a in result.actions_taken)


# ============================================================================
# Error Handling Tests
# ============================================================================

@pytest.mark.asyncio
async def test_recovery_handles_permission_errors():
    """Test recovery handles permission errors gracefully"""
    from recovery.auto_recovery import AutoRecovery

    # Use a directory we can't access
    recovery_system = AutoRecovery(config_dir=Path("/root/.config/i3"))

    # Run recovery - should handle permission error gracefully
    try:
        result = await recovery_system.recover_on_startup()
        # Should either fail with error or detect permission issue
        assert not result.success or len(result.errors) > 0
    except PermissionError:
        # Permission error is also acceptable - test passes
        pass


# ============================================================================
# Convenience Function Tests
# ============================================================================

@pytest.mark.asyncio
async def test_run_startup_recovery_convenience_function(temp_config_dir):
    """Test run_startup_recovery convenience function"""
    # Ensure directory doesn't exist
    assert not temp_config_dir.exists()

    # Run recovery
    result = await run_startup_recovery(config_dir=temp_config_dir)

    # Should work same as AutoRecovery
    assert isinstance(result, RecoveryResult)
    assert temp_config_dir.exists()
