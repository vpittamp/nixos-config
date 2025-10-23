"""
Unit tests for state validation

Feature 030: Production Readiness
Task T026: Unit tests for recovery logic

Tests state validator for detecting corruption and suggesting fixes.
"""

import pytest
import tempfile
import json
from pathlib import Path
from unittest.mock import Mock, AsyncMock

from validation.state_validator import StateValidator, ValidationResult, validate_daemon_state


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def temp_config_dir(tmp_path):
    """Create temporary config directory"""
    return tmp_path / ".config/i3"


@pytest.fixture
def validator(temp_config_dir):
    """Create state validator with temp config dir"""
    return StateValidator(config_dir=temp_config_dir)


# ============================================================================
# ValidationResult Tests
# ============================================================================

def test_validation_result_defaults():
    """Test ValidationResult default state"""
    result = ValidationResult()
    assert result.is_valid is True
    assert len(result.errors) == 0
    assert len(result.warnings) == 0
    assert len(result.fixes) == 0


def test_validation_result_add_error():
    """Test adding error invalidates result"""
    result = ValidationResult()
    result.add_error("Test error", fix="Test fix")

    assert result.is_valid is False
    assert "Test error" in result.errors
    assert "Test fix" in result.fixes


def test_validation_result_add_warning():
    """Test adding warning doesn't invalidate result"""
    result = ValidationResult()
    result.add_warning("Test warning")

    assert result.is_valid is True
    assert "Test warning" in result.warnings


def test_validation_result_to_dict():
    """Test ValidationResult serialization"""
    result = ValidationResult()
    result.add_error("Error 1")
    result.add_warning("Warning 1")

    data = result.to_dict()

    assert data["is_valid"] is False
    assert "Error 1" in data["errors"]
    assert "Warning 1" in data["warnings"]
    assert "timestamp" in data


# ============================================================================
# Config Directory Validation Tests
# ============================================================================

def test_validate_config_directory_missing(validator, temp_config_dir):
    """Test validation fails when config directory doesn't exist"""
    result = ValidationResult()
    validator._validate_config_directory(result)

    assert not result.is_valid
    assert any("Config directory does not exist" in e for e in result.errors)
    assert any("mkdir" in f for f in result.fixes)


def test_validate_config_directory_exists(validator, temp_config_dir):
    """Test validation passes when config directory exists"""
    temp_config_dir.mkdir(parents=True)

    result = ValidationResult()
    validator._validate_config_directory(result)

    assert result.is_valid


def test_validate_config_directory_is_file(validator, temp_config_dir):
    """Test validation fails when config path is a file"""
    temp_config_dir.parent.mkdir(parents=True, exist_ok=True)
    temp_config_dir.touch()  # Create as file instead of directory

    result = ValidationResult()
    validator._validate_config_directory(result)

    assert not result.is_valid
    assert any("not a directory" in e for e in result.errors)


# ============================================================================
# Projects Directory Validation Tests
# ============================================================================

def test_validate_projects_directory_missing(validator, temp_config_dir):
    """Test warning when projects directory doesn't exist"""
    temp_config_dir.mkdir(parents=True)

    result = ValidationResult()
    validator._validate_projects_directory(result)

    # Missing projects directory is a warning, not an error
    assert result.is_valid
    assert any("Projects directory does not exist" in w for w in result.warnings)


def test_validate_projects_directory_exists(validator, temp_config_dir):
    """Test validation passes when projects directory exists"""
    temp_config_dir.mkdir(parents=True)
    (temp_config_dir / "projects").mkdir()

    result = ValidationResult()
    validator._validate_projects_directory(result)

    assert result.is_valid
    assert len(result.warnings) == 0


# ============================================================================
# App Classes File Validation Tests
# ============================================================================

def test_validate_app_classes_file_missing(validator, temp_config_dir):
    """Test warning when app-classes.json doesn't exist"""
    temp_config_dir.mkdir(parents=True)

    result = ValidationResult()
    validator._validate_app_classes_file(result)

    assert result.is_valid
    assert any("App classes file does not exist" in w for w in result.warnings)


def test_validate_app_classes_file_valid(validator, temp_config_dir):
    """Test validation passes with valid app-classes.json"""
    temp_config_dir.mkdir(parents=True)
    app_classes_file = temp_config_dir / "app-classes.json"

    with open(app_classes_file, 'w') as f:
        json.dump({"scoped_classes": ["Ghostty", "Code"]}, f)

    result = ValidationResult()
    validator._validate_app_classes_file(result)

    assert result.is_valid


def test_validate_app_classes_file_invalid_json(validator, temp_config_dir):
    """Test error when app-classes.json has invalid JSON"""
    temp_config_dir.mkdir(parents=True)
    app_classes_file = temp_config_dir / "app-classes.json"

    with open(app_classes_file, 'w') as f:
        f.write("{ invalid json }")

    result = ValidationResult()
    validator._validate_app_classes_file(result)

    assert not result.is_valid
    assert any("invalid JSON" in e for e in result.errors)


def test_validate_app_classes_file_not_object(validator, temp_config_dir):
    """Test error when app-classes.json is not an object"""
    temp_config_dir.mkdir(parents=True)
    app_classes_file = temp_config_dir / "app-classes.json"

    with open(app_classes_file, 'w') as f:
        json.dump(["not", "an", "object"], f)

    result = ValidationResult()
    validator._validate_app_classes_file(result)

    assert not result.is_valid
    assert any("not a JSON object" in e for e in result.errors)


def test_validate_app_classes_file_invalid_structure(validator, temp_config_dir):
    """Test error when scoped_classes is not a list"""
    temp_config_dir.mkdir(parents=True)
    app_classes_file = temp_config_dir / "app-classes.json"

    with open(app_classes_file, 'w') as f:
        json.dump({"scoped_classes": "not a list"}, f)

    result = ValidationResult()
    validator._validate_app_classes_file(result)

    assert not result.is_valid
    assert any("must be a list" in e for e in result.errors)


# ============================================================================
# i3 Connection Validation Tests
# ============================================================================

def test_validate_i3_connection_healthy(validator):
    """Test validation passes with healthy i3 connection"""
    mock_conn = Mock()
    mock_conn.get_tree.return_value = {"id": 1, "nodes": []}

    result = ValidationResult()
    validator._validate_i3_connection(result, mock_conn)

    assert result.is_valid


def test_validate_i3_connection_invalid_object(validator):
    """Test error when i3 connection object is invalid"""
    mock_conn = Mock(spec=[])  # No get_tree method

    result = ValidationResult()
    validator._validate_i3_connection(result, mock_conn)

    assert not result.is_valid
    assert any("invalid" in e for e in result.errors)


def test_validate_i3_connection_returns_none(validator):
    """Test error when i3 connection returns None"""
    mock_conn = Mock()
    mock_conn.get_tree.return_value = None

    result = ValidationResult()
    validator._validate_i3_connection(result, mock_conn)

    assert not result.is_valid
    assert any("returned None" in e for e in result.errors)


def test_validate_i3_connection_exception(validator):
    """Test error when i3 connection raises exception"""
    mock_conn = Mock()
    mock_conn.get_tree.side_effect = Exception("Connection failed")

    result = ValidationResult()
    validator._validate_i3_connection(result, mock_conn)

    assert not result.is_valid
    assert any("not responding" in e for e in result.errors)


# ============================================================================
# Project Configuration Validation Tests
# ============================================================================

@pytest.mark.asyncio
async def test_validate_projects_no_directory(validator):
    """Test validation skips when projects directory doesn't exist"""
    result = ValidationResult()
    await validator._validate_projects(result, None)

    # Should not error - just skip validation
    assert result.is_valid


@pytest.mark.asyncio
async def test_validate_projects_valid(validator, temp_config_dir):
    """Test validation passes with valid project files"""
    projects_dir = temp_config_dir / "projects"
    projects_dir.mkdir(parents=True)

    project_file = projects_dir / "nixos.json"
    with open(project_file, 'w') as f:
        json.dump({
            "name": "nixos",
            "display_name": "NixOS",
            "directory": "/etc/nixos",
        }, f)

    result = ValidationResult()
    await validator._validate_projects(result, None)

    # Missing directory is a warning, not an error
    assert result.is_valid or len(result.errors) == 0


@pytest.mark.asyncio
async def test_validate_projects_missing_field(validator, temp_config_dir):
    """Test error when project file missing required field"""
    projects_dir = temp_config_dir / "projects"
    projects_dir.mkdir(parents=True)

    project_file = projects_dir / "invalid.json"
    with open(project_file, 'w') as f:
        json.dump({"name": "test"}, f)  # Missing display_name and directory

    result = ValidationResult()
    await validator._validate_projects(result, None)

    assert not result.is_valid
    assert any("missing required field" in e for e in result.errors)


@pytest.mark.asyncio
async def test_validate_projects_invalid_json(validator, temp_config_dir):
    """Test error when project file has invalid JSON"""
    projects_dir = temp_config_dir / "projects"
    projects_dir.mkdir(parents=True)

    project_file = projects_dir / "invalid.json"
    with open(project_file, 'w') as f:
        f.write("{ invalid json }")

    result = ValidationResult()
    await validator._validate_projects(result, None)

    assert not result.is_valid
    assert any("invalid JSON" in e for e in result.errors)


# ============================================================================
# Event Buffer Validation Tests
# ============================================================================

def test_validate_event_buffer_valid(validator):
    """Test validation passes with valid event buffer"""
    mock_buffer = Mock()
    mock_buffer.events = [Mock(), Mock(), Mock()]
    mock_buffer.max_size = 500

    result = ValidationResult()
    validator._validate_event_buffer(result, mock_buffer)

    assert result.is_valid


def test_validate_event_buffer_invalid_object(validator):
    """Test error when event buffer object is invalid"""
    mock_buffer = Mock(spec=[])  # No events attribute

    result = ValidationResult()
    validator._validate_event_buffer(result, mock_buffer)

    assert not result.is_valid
    assert any("invalid" in e for e in result.errors)


def test_validate_event_buffer_exceeds_max_size(validator):
    """Test error when buffer size exceeds max_size"""
    mock_buffer = Mock()
    mock_buffer.events = [Mock()] * 600  # 600 events
    mock_buffer.max_size = 500

    result = ValidationResult()
    validator._validate_event_buffer(result, mock_buffer)

    assert not result.is_valid
    assert any("exceeds max_size" in e for e in result.errors)


def test_validate_event_buffer_contains_none(validator):
    """Test error when buffer contains None entries"""
    mock_buffer = Mock()
    mock_buffer.events = [Mock(), None, Mock(), None]
    mock_buffer.max_size = 500

    result = ValidationResult()
    validator._validate_event_buffer(result, mock_buffer)

    assert not result.is_valid
    assert any("None entries" in e for e in result.errors)


# ============================================================================
# Full Validation Tests
# ============================================================================

@pytest.mark.asyncio
async def test_validate_all_success(validator, temp_config_dir):
    """Test full validation with all components healthy"""
    # Setup valid environment
    temp_config_dir.mkdir(parents=True)
    (temp_config_dir / "projects").mkdir()

    app_classes_file = temp_config_dir / "app-classes.json"
    with open(app_classes_file, 'w') as f:
        json.dump({"scoped_classes": []}, f)

    # Mock healthy i3 connection
    mock_conn = Mock()
    mock_conn.get_tree.return_value = {"id": 1, "nodes": []}

    # Mock healthy event buffer
    mock_buffer = Mock()
    mock_buffer.events = [Mock(), Mock()]
    mock_buffer.max_size = 500

    result = await validator.validate_all(
        i3_connection=mock_conn,
        event_buffer=mock_buffer,
    )

    assert result.is_valid


@pytest.mark.asyncio
async def test_validate_all_multiple_errors(validator):
    """Test full validation with multiple errors"""
    # Mock unhealthy i3 connection
    mock_conn = Mock()
    mock_conn.get_tree.side_effect = Exception("Connection failed")

    # Mock unhealthy event buffer
    mock_buffer = Mock()
    mock_buffer.events = [None, None]
    mock_buffer.max_size = 500

    result = await validator.validate_all(
        i3_connection=mock_conn,
        event_buffer=mock_buffer,
    )

    assert not result.is_valid
    assert len(result.errors) > 1  # Multiple errors detected
