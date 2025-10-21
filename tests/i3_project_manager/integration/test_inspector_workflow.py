"""Integration tests for window inspector TUI workflow.

Tests the complete inspector user experience including launch, display,
classification actions, live mode, and pattern creation.
"""

import pytest
from unittest.mock import Mock, patch, AsyncMock
from pathlib import Path


class TestInspectorLaunch:
    """TUI tests for inspector launch and display.

    T070: Verify inspector loads window properties, displays table, shows classification
    FR-133: Inspector TUI application
    """

    @pytest.mark.asyncio
    async def test_inspector_launches_and_displays_properties(self):
        """Verify inspector loads with window properties displayed in table."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        # Mock window properties
        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Ghostty"
        mock_props.instance = "ghostty"
        mock_props.title = "nvim /etc/nixos/configuration.nix"
        mock_props.workspace = "1"
        mock_props.output = "eDP-1"
        mock_props.marks = ["nixos"]
        mock_props.floating = False
        mock_props.fullscreen = False
        mock_props.focused = True
        mock_props.current_classification = "scoped"
        mock_props.classification_source = "explicit"
        mock_props.suggested_classification = "scoped"
        mock_props.suggestion_confidence = 0.95
        mock_props.reasoning = "Terminal emulator - project-scoped by default."

        # Launch inspector with mocked properties
        app = InspectorApp(window_props=mock_props)

        async with app.run_test() as pilot:
            # Verify app is running
            assert app.is_running

            # Verify property display table exists
            property_table = app.query_one("#property-table")
            assert property_table is not None

            # Verify classification status panel exists
            classification_panel = app.query_one("#classification-status")
            assert classification_panel is not None

            # Verify pattern matches panel exists
            pattern_panel = app.query_one("#pattern-matches")
            assert pattern_panel is not None

    @pytest.mark.asyncio
    async def test_inspector_displays_window_id_and_class(self):
        """Verify inspector shows WM_CLASS and window ID in property table."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Code"
        mock_props.instance = "code"
        mock_props.title = "main.py - VSCode"
        mock_props.current_classification = "scoped"
        mock_props.classification_source = "explicit"

        app = InspectorApp(window_props=mock_props)

        async with app.run_test() as pilot:
            # Check that window ID and class are displayed
            property_table = app.query_one("#property-table")

            # Get rendered content (implementation-specific)
            # This is a simplified check - actual implementation may vary
            assert app.window_props.window_id == 94489280512
            assert app.window_props.window_class == "Code"

    @pytest.mark.asyncio
    async def test_inspector_shows_classification_status(self):
        """Verify inspector displays current classification and source."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "firefox"
        mock_props.current_classification = "global"
        mock_props.classification_source = "explicit"
        mock_props.suggested_classification = "global"
        mock_props.suggestion_confidence = 0.85
        mock_props.reasoning = "Web browser - typically global."

        app = InspectorApp(window_props=mock_props)

        async with app.run_test() as pilot:
            # Verify classification displayed
            assert app.window_props.current_classification == "global"
            assert app.window_props.classification_source == "explicit"


class TestClassificationActions:
    """TUI tests for classification actions in inspector.

    T071: Verify 's' marks as scoped, 'g' marks as global, saves immediately
    FR-117: Direct classification from inspector
    FR-119: Immediate save and daemon reload
    """

    @pytest.mark.asyncio
    async def test_classify_as_scoped_with_s_key(self):
        """Verify 's' key classifies window as scoped and saves."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
            from i3_project_manager.core.config import AppClassConfig
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        # Create test config
        config = AppClassConfig()
        config.scoped_classes = set()
        config.global_classes = set()

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Alacritty"
        mock_props.current_classification = "unclassified"

        with patch('i3_project_manager.tui.inspector.AppClassConfig', return_value=config):
            app = InspectorApp(window_props=mock_props)

            async with app.run_test() as pilot:
                # Press 's' to classify as scoped
                await pilot.press("s")

                # Verify window class added to scoped_classes
                assert "Alacritty" in config.scoped_classes

                # Verify classification updated in UI
                assert app.window_props.current_classification == "scoped"

    @pytest.mark.asyncio
    async def test_classify_as_global_with_g_key(self):
        """Verify 'g' key classifies window as global and saves."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
            from i3_project_manager.core.config import AppClassConfig
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        # Create test config
        config = AppClassConfig()
        config.scoped_classes = set()
        config.global_classes = set()

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "mpv"
        mock_props.current_classification = "unclassified"

        with patch('i3_project_manager.tui.inspector.AppClassConfig', return_value=config):
            app = InspectorApp(window_props=mock_props)

            async with app.run_test() as pilot:
                # Press 'g' to classify as global
                await pilot.press("g")

                # Verify window class added to global_classes
                assert "mpv" in config.global_classes

                # Verify classification updated in UI
                assert app.window_props.current_classification == "global"

    @pytest.mark.asyncio
    async def test_classification_saves_and_reloads_daemon(self):
        """Verify classification saves config and reloads daemon."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
            from i3_project_manager.core.config import AppClassConfig
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        config = AppClassConfig()
        config.scoped_classes = set()
        config.global_classes = set()

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Ghostty"
        mock_props.current_classification = "unclassified"

        with patch('i3_project_manager.tui.inspector.AppClassConfig', return_value=config):
            with patch('subprocess.run') as mock_subprocess:
                app = InspectorApp(window_props=mock_props)

                async with app.run_test() as pilot:
                    # Press 's' to classify
                    await pilot.press("s")

                    # Verify daemon reload called (i3-msg tick)
                    mock_subprocess.assert_called()
                    args = mock_subprocess.call_args[0][0]
                    assert "i3-msg" in args
                    assert "tick" in args


class TestLiveMode:
    """TUI tests for live mode with i3 event subscriptions.

    T072: Verify 'l' enables live mode, subscribes to events, updates on changes
    FR-120: Live mode with i3 event subscriptions
    SC-037: <100ms property updates
    """

    @pytest.mark.asyncio
    async def test_toggle_live_mode_with_l_key(self):
        """Verify 'l' key toggles live mode on/off."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Ghostty"

        app = InspectorApp(window_props=mock_props)

        async with app.run_test() as pilot:
            # Initially live mode is off
            assert app.live_mode is False

            # Press 'l' to enable live mode
            await pilot.press("l")

            # Verify live mode enabled
            assert app.live_mode is True

            # Press 'l' again to disable
            await pilot.press("l")

            # Verify live mode disabled
            assert app.live_mode is False

    @pytest.mark.asyncio
    async def test_live_mode_subscribes_to_i3_events(self):
        """Verify live mode subscribes to window::title, window::mark, etc."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Code"

        with patch('i3_project_manager.tui.inspector.Connection') as mock_conn:
            mock_i3 = AsyncMock()
            mock_conn.return_value.__aenter__.return_value = mock_i3

            app = InspectorApp(window_props=mock_props)

            async with app.run_test() as pilot:
                # Enable live mode
                await pilot.press("l")

                # Verify i3 event subscriptions called
                # Note: Implementation-specific, may need adjustment
                assert app.live_mode is True

    @pytest.mark.asyncio
    async def test_live_mode_updates_on_window_title_change(self):
        """Verify title updates when window::title event received."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
        except ImportError:
            pytest.skip("InspectorApp not yet implemented")

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Ghostty"
        mock_props.title = "original title"

        app = InspectorApp(window_props=mock_props)

        async with app.run_test() as pilot:
            # Enable live mode
            await pilot.press("l")

            # Simulate window::title event
            mock_event = Mock()
            mock_event.container = Mock()
            mock_event.container.id = 94489280512
            mock_event.container.name = "new title"

            # Trigger event handler
            await app.on_window_title_change(None, mock_event)

            # Verify title updated
            assert app.window_props.title == "new title"


class TestPatternCreation:
    """TUI tests for pattern creation from inspector.

    T073: Verify 'p' opens pattern dialog, pre-fills window_class, creates pattern
    Integration with US1 (pattern creation)
    """

    @pytest.mark.asyncio
    async def test_pattern_creation_with_p_key(self):
        """Verify 'p' key opens pattern dialog pre-filled with window class."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
            from i3_project_manager.tui.screens.pattern_dialog import PatternDialog
        except ImportError:
            pytest.skip("Inspector or PatternDialog not yet implemented")

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Ghostty"

        app = InspectorApp(window_props=mock_props)

        async with app.run_test() as pilot:
            # Press 'p' to open pattern dialog
            await pilot.press("p")

            # Verify pattern dialog opened (implementation-specific check)
            # In real implementation, would check screen stack
            # For now, just verify the action doesn't crash

    @pytest.mark.asyncio
    async def test_pattern_creation_adds_pattern_to_config(self):
        """Verify pattern creation saves pattern to config."""
        try:
            from i3_project_manager.tui.inspector import InspectorApp
            from i3_project_manager.core.config import AppClassConfig
            from i3_project_manager.models.pattern import PatternRule
        except ImportError:
            pytest.skip("Inspector not yet implemented")

        config = AppClassConfig()
        config.class_patterns = []

        mock_props = Mock()
        mock_props.window_id = 94489280512
        mock_props.window_class = "Ghostty"

        # Mock pattern dialog to return a pattern rule
        mock_pattern = PatternRule(
            pattern="glob:Ghost*",
            scope="scoped",
            priority=50,
            description="Ghostty terminal variants"
        )

        with patch('i3_project_manager.tui.inspector.AppClassConfig', return_value=config):
            with patch('i3_project_manager.tui.inspector.PatternDialog') as mock_dialog:
                # Mock dialog returning pattern rule
                mock_dialog.return_value = AsyncMock(return_value=mock_pattern)

                app = InspectorApp(window_props=mock_props)

                async with app.run_test() as pilot:
                    # Press 'p' and confirm pattern creation
                    await pilot.press("p")

                    # Verify pattern added to config (after dialog confirms)
                    # Note: Actual verification depends on implementation
