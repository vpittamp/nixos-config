"""
Unit tests for WindowCommand and CommandBatch models.
Feature 091: Optimize i3pm Project Switching Performance
"""

import pytest
from home_modules.desktop.i3_project_event_daemon.models.window_command import (
    WindowCommand,
    CommandBatch,
    CommandType,
)


class TestWindowCommand:
    """Tests for WindowCommand model."""

    def test_move_workspace_command(self):
        """Test generating move workspace command."""
        cmd = WindowCommand(
            window_id=12345,
            command_type=CommandType.MOVE_WORKSPACE,
            params={"workspace_number": 3},
        )
        assert cmd.to_sway_command() == "[con_id=12345] move workspace number 3"

    def test_move_scratchpad_command(self):
        """Test generating move scratchpad command."""
        cmd = WindowCommand(
            window_id=12345,
            command_type=CommandType.MOVE_SCRATCHPAD,
            params={},
        )
        assert cmd.to_sway_command() == "[con_id=12345] move scratchpad"

    def test_floating_enable_command(self):
        """Test generating floating enable command."""
        cmd = WindowCommand(
            window_id=12345,
            command_type=CommandType.FLOATING_ENABLE,
            params={},
        )
        assert cmd.to_sway_command() == "[con_id=12345] floating enable"

    def test_resize_command(self):
        """Test generating resize command."""
        cmd = WindowCommand(
            window_id=12345,
            command_type=CommandType.RESIZE,
            params={"width": 800, "height": 600},
        )
        assert cmd.to_sway_command() == "[con_id=12345] resize set 800 px 600 px"

    def test_move_position_command(self):
        """Test generating move position command."""
        cmd = WindowCommand(
            window_id=12345,
            command_type=CommandType.MOVE_POSITION,
            params={"x": 100, "y": 200},
        )
        assert cmd.to_sway_command() == "[con_id=12345] move position 100 px 200 px"

    def test_missing_params_raises_error(self):
        """Test that missing required params raises ValueError."""
        cmd = WindowCommand(
            window_id=12345,
            command_type=CommandType.MOVE_WORKSPACE,
            params={},  # Missing workspace_number
        )
        with pytest.raises(ValueError, match="workspace_number"):
            cmd.to_sway_command()

    def test_immutable_command(self):
        """Test that WindowCommand is frozen (immutable)."""
        cmd = WindowCommand(
            window_id=12345,
            command_type=CommandType.MOVE_SCRATCHPAD,
            params={},
        )
        with pytest.raises(Exception):  # Pydantic frozen model raises exception
            cmd.window_id = 99999


class TestCommandBatch:
    """Tests for CommandBatch model."""

    def test_from_window_state_tiled(self):
        """Test creating batch for tiled window restoration."""
        batch = CommandBatch.from_window_state(
            window_id=12345,
            workspace_num=3,
            is_floating=False,
            geometry=None,
        )

        assert batch.window_id == 12345
        assert len(batch.commands) == 2  # move + floating disable
        assert batch.commands[0].command_type == CommandType.MOVE_WORKSPACE
        assert batch.commands[1].command_type == CommandType.FLOATING_DISABLE
        assert batch.can_batch is True

    def test_from_window_state_floating_no_geometry(self):
        """Test creating batch for floating window without geometry."""
        batch = CommandBatch.from_window_state(
            window_id=12345,
            workspace_num=3,
            is_floating=True,
            geometry=None,
        )

        assert batch.window_id == 12345
        assert len(batch.commands) == 2  # move + floating enable
        assert batch.commands[0].command_type == CommandType.MOVE_WORKSPACE
        assert batch.commands[1].command_type == CommandType.FLOATING_ENABLE

    def test_from_window_state_floating_with_geometry(self):
        """Test creating batch for floating window with geometry."""
        batch = CommandBatch.from_window_state(
            window_id=12345,
            workspace_num=3,
            is_floating=True,
            geometry={"x": 100, "y": 200, "width": 800, "height": 600},
        )

        assert batch.window_id == 12345
        assert len(batch.commands) == 4  # move + floating + resize + position
        assert batch.commands[0].command_type == CommandType.MOVE_WORKSPACE
        assert batch.commands[1].command_type == CommandType.FLOATING_ENABLE
        assert batch.commands[2].command_type == CommandType.RESIZE
        assert batch.commands[3].command_type == CommandType.MOVE_POSITION

    def test_to_batched_command(self):
        """Test generating batched Sway command with semicolons."""
        batch = CommandBatch.from_window_state(
            window_id=12345,
            workspace_num=3,
            is_floating=True,
            geometry={"x": 100, "y": 200, "width": 800, "height": 600},
        )

        batched = batch.to_batched_command()

        # Should have single selector and semicolon-separated commands
        assert batched.startswith("[con_id=12345]")
        assert ";" in batched
        assert "move workspace number 3" in batched
        assert "floating enable" in batched
        assert "resize set 800 px 600 px" in batched
        assert "move position 100 px 200 px" in batched

    def test_batched_command_order(self):
        """Test that batched commands maintain correct order."""
        batch = CommandBatch.from_window_state(
            window_id=12345,
            workspace_num=5,
            is_floating=True,
            geometry={"x": 50, "y": 75, "width": 1024, "height": 768},
        )

        batched = batch.to_batched_command()

        # Verify order: workspace first, then floating, resize, position
        workspace_idx = batched.index("move workspace number 5")
        floating_idx = batched.index("floating enable")
        resize_idx = batched.index("resize set 1024 px 768 px")
        position_idx = batched.index("move position 50 px 75 px")

        assert workspace_idx < floating_idx < resize_idx < position_idx

    def test_mixed_window_ids_raises_error(self):
        """Test that batching commands for different windows raises error."""
        commands = [
            WindowCommand(
                window_id=123,
                command_type=CommandType.MOVE_WORKSPACE,
                params={"workspace_number": 1},
            ),
            WindowCommand(
                window_id=456,  # Different window!
                command_type=CommandType.FLOATING_ENABLE,
                params={},
            ),
        ]

        batch = CommandBatch(window_id=123, commands=commands, can_batch=True)

        with pytest.raises(ValueError, match="same window"):
            batch.to_batched_command()
