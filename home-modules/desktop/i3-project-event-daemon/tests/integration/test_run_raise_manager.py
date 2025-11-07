"""Integration tests for RunRaiseManager (Feature 051)."""

import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from pathlib import Path

from services.run_raise_manager import RunRaiseManager
from models.window_state import WindowState, WindowStateInfo


@pytest.fixture
def mock_sway():
    """Create mock Sway connection."""
    mock = AsyncMock()
    mock.get_tree = AsyncMock()
    mock.get_workspaces = AsyncMock()
    mock.command = AsyncMock(return_value=[MagicMock(success=True)])
    return mock


@pytest.fixture
def mock_workspace_tracker():
    """Create mock WorkspaceTracker."""
    tracker = MagicMock()
    tracker.track_window = MagicMock()
    tracker.get_window_state = MagicMock(return_value=None)
    return tracker


@pytest.fixture
def manager(mock_sway, mock_workspace_tracker):
    """Create RunRaiseManager instance with mocks."""
    with patch('shutil.which', return_value='/usr/bin/app-launcher-wrapper'):
        return RunRaiseManager(
            sway=mock_sway,
            workspace_tracker=mock_workspace_tracker,
            app_launcher_path='/usr/bin/app-launcher-wrapper'
        )


class TestWindowRegistration:
    """Test window registration and tracking."""

    def test_register_window(self, manager):
        """Test registering a window."""
        manager.register_window("firefox", 12345)
        assert manager._get_window_id_by_app_name("firefox") == 12345

    def test_unregister_window(self, manager):
        """Test unregistering a window."""
        manager.register_window("firefox", 12345)
        manager.unregister_window("firefox")
        assert manager._get_window_id_by_app_name("firefox") is None

    def test_get_nonexistent_window(self, manager):
        """Test getting window_id for unregistered app."""
        assert manager._get_window_id_by_app_name("nonexistent") is None


class TestWindowStateDetection:
    """Test window state detection logic."""

    @pytest.mark.asyncio
    async def test_detect_not_found(self, manager, mock_sway):
        """Test detecting NOT_FOUND state."""
        # Setup: No window registered
        mock_tree = MagicMock()
        mock_focused = MagicMock()
        mock_workspace = MagicMock()
        mock_workspace.name = "1"
        mock_focused.workspace = MagicMock(return_value=mock_workspace)
        mock_tree.find_focused = MagicMock(return_value=mock_focused)
        mock_sway.get_tree.return_value = mock_tree

        state_info = await manager.detect_window_state("firefox")

        assert state_info.state == WindowState.NOT_FOUND
        assert state_info.window is None
        assert state_info.window_id is None

    @pytest.mark.asyncio
    async def test_detect_scratchpad(self, manager, mock_sway):
        """Test detecting SCRATCHPAD state."""
        # Setup: Window in scratchpad
        manager.register_window("firefox", 12345)

        mock_window = MagicMock()
        mock_window.id = 12345
        mock_window_workspace = MagicMock()
        mock_window_workspace.name = "__i3_scratch"
        mock_window.workspace = MagicMock(return_value=mock_window_workspace)

        mock_tree = MagicMock()
        mock_focused = MagicMock()
        mock_current_workspace = MagicMock()
        mock_current_workspace.name = "1"
        mock_focused.workspace = MagicMock(return_value=mock_current_workspace)
        mock_tree.find_focused = MagicMock(return_value=mock_focused)
        mock_tree.find_by_id = MagicMock(return_value=mock_window)
        mock_sway.get_tree.return_value = mock_tree

        state_info = await manager.detect_window_state("firefox")

        assert state_info.state == WindowState.SCRATCHPAD
        assert state_info.window_workspace == "__i3_scratch"

    @pytest.mark.asyncio
    async def test_detect_different_workspace(self, manager, mock_sway):
        """Test detecting DIFFERENT_WORKSPACE state."""
        # Setup: Window on workspace 2, current workspace 1
        manager.register_window("firefox", 12345)

        mock_window = MagicMock()
        mock_window.id = 12345
        mock_window.focused = False
        mock_window_workspace = MagicMock()
        mock_window_workspace.name = "2"
        mock_window.workspace = MagicMock(return_value=mock_window_workspace)

        mock_tree = MagicMock()
        mock_focused = MagicMock()
        mock_current_workspace = MagicMock()
        mock_current_workspace.name = "1"
        mock_focused.workspace = MagicMock(return_value=mock_current_workspace)
        mock_tree.find_focused = MagicMock(return_value=mock_focused)
        mock_tree.find_by_id = MagicMock(return_value=mock_window)
        mock_sway.get_tree.return_value = mock_tree

        state_info = await manager.detect_window_state("firefox")

        assert state_info.state == WindowState.DIFFERENT_WORKSPACE
        assert state_info.current_workspace == "1"
        assert state_info.window_workspace == "2"

    @pytest.mark.asyncio
    async def test_detect_same_workspace_focused(self, manager, mock_sway):
        """Test detecting SAME_WORKSPACE_FOCUSED state."""
        # Setup: Window on same workspace and focused
        manager.register_window("firefox", 12345)

        mock_window = MagicMock()
        mock_window.id = 12345
        mock_window.focused = True
        mock_window_workspace = MagicMock()
        mock_window_workspace.name = "1"
        mock_window.workspace = MagicMock(return_value=mock_window_workspace)

        mock_tree = MagicMock()
        mock_focused = MagicMock()
        mock_current_workspace = MagicMock()
        mock_current_workspace.name = "1"
        mock_focused.workspace = MagicMock(return_value=mock_current_workspace)
        mock_tree.find_focused = MagicMock(return_value=mock_focused)
        mock_tree.find_by_id = MagicMock(return_value=mock_window)
        mock_sway.get_tree.return_value = mock_tree

        state_info = await manager.detect_window_state("firefox")

        assert state_info.state == WindowState.SAME_WORKSPACE_FOCUSED
        assert state_info.is_focused is True

    @pytest.mark.asyncio
    async def test_detect_same_workspace_unfocused(self, manager, mock_sway):
        """Test detecting SAME_WORKSPACE_UNFOCUSED state."""
        # Setup: Window on same workspace but not focused
        manager.register_window("firefox", 12345)

        mock_window = MagicMock()
        mock_window.id = 12345
        mock_window.focused = False
        mock_window_workspace = MagicMock()
        mock_window_workspace.name = "1"
        mock_window.workspace = MagicMock(return_value=mock_window_workspace)

        mock_tree = MagicMock()
        mock_focused = MagicMock()
        mock_current_workspace = MagicMock()
        mock_current_workspace.name = "1"
        mock_focused.workspace = MagicMock(return_value=mock_current_workspace)
        mock_tree.find_focused = MagicMock(return_value=mock_focused)
        mock_tree.find_by_id = MagicMock(return_value=mock_window)
        mock_sway.get_tree.return_value = mock_tree

        state_info = await manager.detect_window_state("firefox")

        assert state_info.state == WindowState.SAME_WORKSPACE_UNFOCUSED
        assert state_info.is_focused is False


class TestTransitions:
    """Test state transition methods."""

    @pytest.mark.asyncio
    async def test_transition_focus(self, manager, mock_sway):
        """Test _transition_focus executes correct Sway command."""
        mock_window = MagicMock()
        mock_window.id = 12345

        result = await manager._transition_focus(mock_window)

        mock_sway.command.assert_called_once_with('[con_id=12345] focus')
        assert result["action"] == "focused"
        assert result["window_id"] == 12345
        assert result["focused"] is True

    @pytest.mark.asyncio
    async def test_transition_goto(self, manager, mock_sway):
        """Test _transition_goto switches workspace and focuses."""
        mock_window = MagicMock()
        mock_window.id = 12345
        mock_workspace = MagicMock()
        mock_workspace.name = "2"
        mock_window.workspace = MagicMock(return_value=mock_workspace)

        result = await manager._transition_goto(mock_window)

        # Should switch to workspace then focus
        assert mock_sway.command.call_count == 2
        calls = [str(call) for call in mock_sway.command.call_args_list]
        assert any("workspace 2" in str(call) for call in calls)
        assert any("focus" in str(call) for call in calls)

        assert result["action"] == "focused"
        assert result["window_id"] == 12345

    @pytest.mark.asyncio
    async def test_transition_summon_floating(self, manager, mock_sway):
        """Test _transition_summon preserves floating geometry."""
        mock_rect = MagicMock()
        mock_rect.x, mock_rect.y = 100, 200
        mock_rect.width, mock_rect.height = 1600, 900

        mock_window = MagicMock()
        mock_window.id = 12345
        mock_window.type = "floating_con"
        mock_window.floating = "user_on"
        mock_window.rect = mock_rect

        result = await manager._transition_summon(mock_window, "1")

        # Should move, focus, set floating, and restore geometry
        assert mock_sway.command.call_count >= 4
        calls = [str(call) for call in mock_sway.command.call_args_list]

        # Verify key commands were called
        assert any("move container to workspace" in str(call) for call in calls)
        assert any("focus" in str(call) for call in calls)
        assert any("floating enable" in str(call) for call in calls)

        assert result["action"] == "summoned"
        assert result["focused"] is True

    @pytest.mark.asyncio
    async def test_transition_hide(self, manager, mock_sway, mock_workspace_tracker):
        """Test _transition_hide stores state and moves to scratchpad."""
        mock_rect = MagicMock()
        mock_rect.x, mock_rect.y = 100, 200
        mock_rect.width, mock_rect.height = 1600, 900

        mock_window = MagicMock()
        mock_window.id = 12345
        mock_window.type = "floating_con"
        mock_window.floating = "user_on"
        mock_window.rect = mock_rect

        result = await manager._transition_hide(mock_window, "firefox")

        # Should track window state
        mock_workspace_tracker.track_window.assert_called_once()
        call_args = mock_workspace_tracker.track_window.call_args[1]
        assert call_args["window_id"] == 12345
        assert call_args["workspace"] == "__i3_scratch"
        assert call_args["is_floating"] is True
        assert call_args["geometry"]["x"] == 100
        assert call_args["geometry"]["y"] == 200

        # Should move to scratchpad
        mock_sway.command.assert_called_with('[con_id=12345] move scratchpad')

        assert result["action"] == "hidden"
        assert result["focused"] is False

    @pytest.mark.asyncio
    async def test_transition_show(self, manager, mock_sway, mock_workspace_tracker):
        """Test _transition_show restores state from storage."""
        # Setup: Stored state with geometry
        mock_workspace_tracker.get_window_state.return_value = {
            "is_floating": True,
            "geometry": {"x": 100, "y": 200, "width": 1600, "height": 900}
        }

        mock_window = MagicMock()
        mock_window.id = 12345

        result = await manager._transition_show(mock_window, "firefox")

        # Should show from scratchpad
        assert any("scratchpad show" in str(call)
                  for call in mock_sway.command.call_args_list)

        # Should restore floating state
        assert any("floating enable" in str(call)
                  for call in mock_sway.command.call_args_list)

        # Should restore geometry
        calls_str = " ".join(str(call) for call in mock_sway.command.call_args_list)
        assert "move position 100 200" in calls_str
        assert "resize set 1600 900" in calls_str

        assert result["action"] == "shown"
        assert result["focused"] is True


class TestExecuteTransition:
    """Test execute_transition dispatcher logic."""

    @pytest.mark.asyncio
    async def test_force_launch_bypasses_state(self, manager):
        """Test force_launch skips state detection."""
        state_info = WindowStateInfo(
            state=WindowState.SAME_WORKSPACE_FOCUSED,
            window=MagicMock(id=12345),
            current_workspace="1",
            window_workspace="1",
            is_focused=True
        )

        with patch.object(manager, '_transition_launch', new_callable=AsyncMock) as mock_launch:
            mock_launch.return_value = {
                "action": "launched",
                "window_id": None,
                "focused": False,
                "message": "Launched"
            }

            result = await manager.execute_transition(
                app_name="firefox",
                state_info=state_info,
                force_launch=True
            )

            # Should launch even though window exists and is focused
            mock_launch.assert_called_once()
            assert result["action"] == "launched"

    @pytest.mark.asyncio
    async def test_summon_mode_different_workspace(self, manager):
        """Test summon mode calls _transition_summon."""
        mock_window = MagicMock(id=12345)
        state_info = WindowStateInfo(
            state=WindowState.DIFFERENT_WORKSPACE,
            window=mock_window,
            current_workspace="1",
            window_workspace="2",
            is_focused=False
        )

        with patch.object(manager, '_transition_summon', new_callable=AsyncMock) as mock_summon:
            mock_summon.return_value = {"action": "summoned", "window_id": 12345, "focused": True, "message": ""}

            result = await manager.execute_transition(
                app_name="firefox",
                state_info=state_info,
                mode="summon"
            )

            mock_summon.assert_called_once_with(mock_window, "1")

    @pytest.mark.asyncio
    async def test_hide_mode_focused_window(self, manager):
        """Test hide mode hides focused window."""
        mock_window = MagicMock(id=12345)
        state_info = WindowStateInfo(
            state=WindowState.SAME_WORKSPACE_FOCUSED,
            window=mock_window,
            current_workspace="1",
            window_workspace="1",
            is_focused=True
        )

        with patch.object(manager, '_transition_hide', new_callable=AsyncMock) as mock_hide:
            mock_hide.return_value = {"action": "hidden", "window_id": 12345, "focused": False, "message": ""}

            result = await manager.execute_transition(
                app_name="firefox",
                state_info=state_info,
                mode="hide"
            )

            mock_hide.assert_called_once()

    @pytest.mark.asyncio
    async def test_nohide_mode_focused_window(self, manager):
        """Test nohide mode does nothing when window focused."""
        mock_window = MagicMock(id=12345)
        state_info = WindowStateInfo(
            state=WindowState.SAME_WORKSPACE_FOCUSED,
            window=mock_window,
            current_workspace="1",
            window_workspace="1",
            is_focused=True
        )

        result = await manager.execute_transition(
            app_name="firefox",
            state_info=state_info,
            mode="nohide"
        )

        # Should return "none" action - window already focused
        assert result["action"] == "none"
        assert result["focused"] is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
