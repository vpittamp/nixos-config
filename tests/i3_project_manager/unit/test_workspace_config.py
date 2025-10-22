"""Unit tests for WorkspaceConfig model."""

import pytest
from pathlib import Path
import json
import tempfile
import sys

# Add i3pm to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "home-modules/tools"))
from i3_project_manager.models.workspace import WorkspaceConfig, load_workspace_config, _default_workspace_configs


class TestWorkspaceConfig:
    """Test WorkspaceConfig model."""

    def test_valid_workspace_config(self):
        """Test creating valid workspace config."""
        ws = WorkspaceConfig(
            number=1,
            name="Terminal",
            icon="󰨊",
            default_output_role="primary"
        )
        
        assert ws.number == 1
        assert ws.name == "Terminal"
        assert ws.icon == "󰨊"
        assert ws.default_output_role == "primary"

    def test_workspace_number_validation_low(self):
        """Test workspace number must be >= 1."""
        with pytest.raises(ValueError, match="Workspace number must be 1-9"):
            WorkspaceConfig(number=0)

    def test_workspace_number_validation_high(self):
        """Test workspace number must be <= 9."""
        with pytest.raises(ValueError, match="Workspace number must be 1-9"):
            WorkspaceConfig(number=10)

    def test_invalid_output_role(self):
        """Test output role validation."""
        with pytest.raises(ValueError, match="Invalid output role"):
            WorkspaceConfig(number=1, default_output_role="invalid")

    def test_valid_output_roles(self):
        """Test all valid output roles."""
        valid_roles = ["auto", "primary", "secondary", "tertiary"]
        
        for role in valid_roles:
            ws = WorkspaceConfig(number=1, default_output_role=role)
            assert ws.default_output_role == role

    def test_default_values(self):
        """Test default field values."""
        ws = WorkspaceConfig(number=5)
        
        assert ws.number == 5
        assert ws.name is None
        assert ws.icon is None
        assert ws.default_output_role == "auto"

    def test_to_json(self):
        """Test JSON serialization."""
        ws = WorkspaceConfig(
            number=2,
            name="Editor",
            icon="",
            default_output_role="primary"
        )
        
        result = ws.to_json()
        
        assert result == {
            "number": 2,
            "name": "Editor",
            "icon": "",
            "default_output_role": "primary"
        }

    def test_from_json(self):
        """Test JSON deserialization."""
        data = {
            "number": 3,
            "name": "Browser",
            "icon": "󰈹",
            "default_output_role": "secondary"
        }
        
        ws = WorkspaceConfig.from_json(data)
        
        assert ws.number == 3
        assert ws.name == "Browser"
        assert ws.icon == "󰈹"
        assert ws.default_output_role == "secondary"

    def test_from_json_minimal(self):
        """Test JSON deserialization with minimal data."""
        data = {"number": 7}
        
        ws = WorkspaceConfig.from_json(data)
        
        assert ws.number == 7
        assert ws.name is None
        assert ws.icon is None
        assert ws.default_output_role == "auto"

    def test_roundtrip_serialization(self):
        """Test serialization roundtrip."""
        original = WorkspaceConfig(
            number=4,
            name="Media",
            icon="",
            default_output_role="secondary"
        )
        
        # Serialize and deserialize
        data = original.to_json()
        restored = WorkspaceConfig.from_json(data)
        
        assert restored.number == original.number
        assert restored.name == original.name
        assert restored.icon == original.icon
        assert restored.default_output_role == original.default_output_role


class TestLoadWorkspaceConfig:
    """Test workspace config loading."""

    def test_load_from_file(self):
        """Test loading workspace config from file."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            config_data = [
                {"number": 1, "name": "Terminal", "icon": "󰨊", "default_output_role": "primary"},
                {"number": 2, "name": "Editor", "icon": "", "default_output_role": "primary"}
            ]
            json.dump(config_data, f)
            config_path = f.name

        try:
            configs = load_workspace_config(config_path)
            
            assert len(configs) == 2
            assert configs[0].number == 1
            assert configs[0].name == "Terminal"
            assert configs[1].number == 2
            assert configs[1].name == "Editor"
        finally:
            Path(config_path).unlink()

    def test_load_nonexistent_file(self):
        """Test loading from non-existent file returns defaults."""
        configs = load_workspace_config("/tmp/nonexistent-workspace-config.json")
        
        assert len(configs) == 9
        assert configs[0].number == 1
        assert configs[0].name == "Terminal"

    def test_load_invalid_json(self):
        """Test loading invalid JSON raises error."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write("{invalid json")
            config_path = f.name

        try:
            with pytest.raises(ValueError, match="Invalid JSON"):
                load_workspace_config(config_path)
        finally:
            Path(config_path).unlink()

    def test_load_non_array_json(self):
        """Test loading non-array JSON raises error."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump({"not": "an array"}, f)
            config_path = f.name

        try:
            with pytest.raises(ValueError, match="must be a JSON array"):
                load_workspace_config(config_path)
        finally:
            Path(config_path).unlink()

    def test_default_configs(self):
        """Test default workspace configurations."""
        defaults = _default_workspace_configs()
        
        assert len(defaults) == 9
        assert defaults[0].number == 1
        assert defaults[0].name == "Terminal"
        assert defaults[0].icon == "󰨊"
        assert defaults[0].default_output_role == "primary"
        
        assert defaults[8].number == 9
        assert defaults[8].name == "Misc"
