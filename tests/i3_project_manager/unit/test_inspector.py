"""Unit tests for window inspector functionality.

Tests window selection modes, property extraction, and classification logic
without launching the full TUI.
"""

import pytest
from unittest.mock import Mock, patch, MagicMock
from subprocess import CompletedProcess


class TestWindowSelectionModes:
    """Unit tests for window selection modes.

    T068: Verify click mode uses xdotool selectwindow, focused mode uses i3 IPC
    FR-112: Window selection modes (click, focused, by ID)
    """

    def test_click_mode_uses_xdotool_selectwindow(self):
        """Verify click mode launches xdotool selectwindow and parses output."""
        try:
            from i3_project_manager.tui.inspector import inspect_window_click
        except ImportError:
            pytest.skip("inspect_window_click not yet implemented")

        # Mock xdotool subprocess call
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = CompletedProcess(
                args=['xdotool', 'selectwindow'],
                returncode=0,
                stdout=b'94489280512\n',
                stderr=b'',
            )

            # Call click mode
            window_id = inspect_window_click()

            # Verify xdotool was called
            mock_run.assert_called_once()
            args = mock_run.call_args[0][0]
            assert args[0] == 'xdotool'
            assert 'selectwindow' in args

            # Verify window ID extracted
            assert window_id == 94489280512

    def test_click_mode_handles_user_cancellation(self):
        """Verify click mode returns None when user cancels (Escape pressed)."""
        try:
            from i3_project_manager.tui.inspector import inspect_window_click
        except ImportError:
            pytest.skip("inspect_window_click not yet implemented")

        # Mock xdotool returning exit code 1 (cancelled)
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = CompletedProcess(
                args=['xdotool', 'selectwindow'],
                returncode=1,
                stdout=b'',
                stderr=b'',
            )

            # Call click mode
            window_id = inspect_window_click()

            # Verify None returned
            assert window_id is None

    @pytest.mark.asyncio
    async def test_focused_mode_uses_i3_ipc_find_focused(self):
        """Verify focused mode uses i3 GET_TREE and find_focused()."""
        try:
            from i3_project_manager.tui.inspector import inspect_window_focused
        except ImportError:
            pytest.skip("inspect_window_focused not yet implemented")

        # Mock i3 connection and tree
        mock_container = Mock()
        mock_container.id = 94489280512
        mock_container.window_class = "Code"
        mock_container.name = "main.py - VSCode"

        mock_tree = Mock()
        mock_tree.find_focused.return_value = mock_container

        mock_i3 = Mock()
        mock_i3.get_tree.return_value = mock_tree

        with patch('i3_project_manager.tui.inspector.Connection') as mock_conn:
            mock_conn.return_value.__aenter__.return_value = mock_i3

            # Call focused mode
            props = await inspect_window_focused()

            # Verify i3 GET_TREE called
            mock_i3.get_tree.assert_called_once()
            mock_tree.find_focused.assert_called_once()

            # Verify window properties extracted
            assert props.window_id == 94489280512
            assert props.window_class == "Code"
            assert props.title == "main.py - VSCode"

    @pytest.mark.asyncio
    async def test_by_id_mode_uses_i3_ipc_find_by_id(self):
        """Verify by-ID mode uses i3 GET_TREE and find_by_id()."""
        try:
            from i3_project_manager.tui.inspector import inspect_window_by_id
        except ImportError:
            pytest.skip("inspect_window_by_id not yet implemented")

        # Mock i3 connection and container
        mock_container = Mock()
        mock_container.id = 94489280512
        mock_container.window_class = "firefox"
        mock_container.name = "Mozilla Firefox"

        mock_tree = Mock()
        mock_tree.find_by_id.return_value = mock_container

        mock_i3 = Mock()
        mock_i3.get_tree.return_value = mock_tree

        with patch('i3_project_manager.tui.inspector.Connection') as mock_conn:
            mock_conn.return_value.__aenter__.return_value = mock_i3

            # Call by-ID mode
            props = await inspect_window_by_id(94489280512)

            # Verify i3 GET_TREE called with ID
            mock_i3.get_tree.assert_called_once()
            mock_tree.find_by_id.assert_called_once_with(94489280512)

            # Verify window properties extracted
            assert props.window_id == 94489280512
            assert props.window_class == "firefox"

    @pytest.mark.asyncio
    async def test_by_id_mode_raises_error_for_invalid_window_id(self):
        """Verify by-ID mode raises error when window not found."""
        try:
            from i3_project_manager.tui.inspector import inspect_window_by_id
        except ImportError:
            pytest.skip("inspect_window_by_id not yet implemented")

        # Mock i3 returning None (window not found)
        mock_tree = Mock()
        mock_tree.find_by_id.return_value = None

        mock_i3 = Mock()
        mock_i3.get_tree.return_value = mock_tree

        with patch('i3_project_manager.tui.inspector.Connection') as mock_conn:
            mock_conn.return_value.__aenter__.return_value = mock_i3

            # Call by-ID mode with invalid ID
            with pytest.raises(ValueError, match="Window not found"):
                await inspect_window_by_id(99999999999)


class TestPropertyExtraction:
    """Unit tests for window property extraction from i3 containers.

    T069: Verify WindowProperties populated from i3 container
    FR-113: Extract all window properties
    FR-114: Extract classification status
    """

    @pytest.mark.asyncio
    async def test_extract_basic_window_properties(self):
        """Verify basic properties extracted from i3 container."""
        try:
            from i3_project_manager.tui.inspector import extract_window_properties
        except ImportError:
            pytest.skip("extract_window_properties not yet implemented")

        # Mock i3 container
        mock_container = Mock()
        mock_container.id = 94489280512
        mock_container.window_class = "Ghostty"
        mock_container.window_instance = "ghostty"
        mock_container.name = "nvim /etc/nixos/configuration.nix"
        mock_container.marks = ["nixos", "urgent"]
        mock_container.floating = "user_on"  # i3 floating states
        mock_container.fullscreen_mode = 0  # 0 = not fullscreen
        mock_container.focused = True

        # Mock workspace
        mock_workspace = Mock()
        mock_workspace.name = "1"
        mock_workspace.ipc_data = {"output": "eDP-1"}
        mock_container.workspace.return_value = mock_workspace

        # Extract properties
        props = await extract_window_properties(mock_container)

        # Verify all properties extracted
        assert props.window_id == 94489280512
        assert props.window_class == "Ghostty"
        assert props.instance == "ghostty"
        assert props.title == "nvim /etc/nixos/configuration.nix"
        assert props.marks == ["nixos", "urgent"]
        assert props.workspace == "1"
        assert props.output == "eDP-1"
        assert props.floating is True
        assert props.fullscreen is False
        assert props.focused is True

    @pytest.mark.asyncio
    async def test_extract_classification_properties(self):
        """Verify classification status extracted and reasoned."""
        try:
            from i3_project_manager.tui.inspector import extract_window_properties
            from i3_project_manager.core.config import AppClassConfig
        except ImportError:
            pytest.skip("Inspector not yet implemented")

        # Create config with known classification
        config = AppClassConfig()
        config.scoped_classes = {"Ghostty", "Code"}
        config.global_classes = {"firefox", "chrome"}

        # Mock container
        mock_container = Mock()
        mock_container.id = 94489280512
        mock_container.window_class = "Ghostty"
        mock_container.window_instance = "ghostty"
        mock_container.name = "terminal"
        mock_container.marks = ["nixos"]
        mock_container.focused = True
        mock_container.floating = "auto_off"
        mock_container.fullscreen_mode = 0

        mock_workspace = Mock()
        mock_workspace.name = "1"
        mock_workspace.ipc_data = {"output": "eDP-1"}
        mock_container.workspace.return_value = mock_workspace

        # Extract with config context
        with patch('i3_project_manager.tui.inspector.AppClassConfig', return_value=config):
            props = await extract_window_properties(mock_container)

        # Verify classification determined
        assert props.current_classification == "scoped"
        assert props.classification_source == "explicit"
        assert "scoped_classes" in props.reasoning.lower()

    @pytest.mark.asyncio
    async def test_handle_missing_window_class(self):
        """Verify graceful handling when WM_CLASS is None."""
        try:
            from i3_project_manager.tui.inspector import extract_window_properties
        except ImportError:
            pytest.skip("Inspector not yet implemented")

        # Mock container with None window_class
        mock_container = Mock()
        mock_container.id = 94489280512
        mock_container.window_class = None
        mock_container.window_instance = None
        mock_container.name = "popup"
        mock_container.marks = []
        mock_container.focused = False
        mock_container.floating = "user_on"
        mock_container.fullscreen_mode = 0

        mock_workspace = Mock()
        mock_workspace.name = "1"
        mock_workspace.ipc_data = {"output": "eDP-1"}
        mock_container.workspace.return_value = mock_workspace

        # Extract properties
        props = await extract_window_properties(mock_container)

        # Verify None handled gracefully
        assert props.window_class is None or props.window_class == "Unknown"
        assert props.current_classification == "unclassified"
        assert "no WM_CLASS" in props.reasoning.lower() or "unknown" in props.reasoning.lower()
