"""Unit tests for run-raise-hide models (Feature 051)."""

import pytest
from pydantic import ValidationError

from models.window_state import (
    WindowState,
    WindowStateInfo,
    RunMode,
    RunRequest,
    RunResponse,
)


class TestWindowState:
    """Test WindowState enum."""

    def test_window_state_values(self):
        """Test all 5 window states are defined."""
        assert WindowState.NOT_FOUND.value == "not_found"
        assert WindowState.DIFFERENT_WORKSPACE.value == "different_workspace"
        assert WindowState.SAME_WORKSPACE_UNFOCUSED.value == "same_workspace_unfocused"
        assert WindowState.SAME_WORKSPACE_FOCUSED.value == "same_workspace_focused"
        assert WindowState.SCRATCHPAD.value == "scratchpad"

    def test_window_state_count(self):
        """Test exactly 5 states exist."""
        assert len(WindowState) == 5


class TestRunMode:
    """Test RunMode enum."""

    def test_run_mode_values(self):
        """Test all 3 run modes are defined."""
        assert RunMode.SUMMON.value == "summon"
        assert RunMode.HIDE.value == "hide"
        assert RunMode.NOHIDE.value == "nohide"

    def test_run_mode_count(self):
        """Test exactly 3 modes exist."""
        assert len(RunMode) == 3


class TestRunRequest:
    """Test RunRequest Pydantic model."""

    def test_run_request_valid(self):
        """Test valid RunRequest creation."""
        req = RunRequest(
            app_name="firefox",
            mode="summon",
            force_launch=False
        )
        assert req.app_name == "firefox"
        assert req.mode == "summon"
        assert req.force_launch is False

    def test_run_request_defaults(self):
        """Test RunRequest default values."""
        req = RunRequest(app_name="firefox")
        assert req.mode == "summon"
        assert req.force_launch is False

    def test_run_request_all_modes(self):
        """Test all valid modes are accepted."""
        for mode in ["summon", "hide", "nohide"]:
            req = RunRequest(app_name="firefox", mode=mode)
            assert req.mode == mode

    def test_run_request_missing_app_name(self):
        """Test RunRequest requires app_name."""
        with pytest.raises(ValidationError):
            RunRequest()

    def test_run_request_json_serialization(self):
        """Test RunRequest serializes to JSON."""
        req = RunRequest(app_name="firefox", mode="hide", force_launch=True)
        data = req.model_dump()
        assert data["app_name"] == "firefox"
        assert data["mode"] == "hide"
        assert data["force_launch"] is True


class TestRunResponse:
    """Test RunResponse Pydantic model."""

    def test_run_response_valid(self):
        """Test valid RunResponse creation."""
        resp = RunResponse(
            action="launched",
            window_id=12345,
            focused=True,
            message="Launched Firefox"
        )
        assert resp.action == "launched"
        assert resp.window_id == 12345
        assert resp.focused is True
        assert resp.message == "Launched Firefox"

    def test_run_response_all_actions(self):
        """Test all valid actions."""
        actions = ["launched", "focused", "summoned", "moved", "hidden", "shown", "none"]
        for action in actions:
            resp = RunResponse(
                action=action,
                window_id=None,
                focused=False,
                message=f"Action: {action}"
            )
            assert resp.action == action

    def test_run_response_optional_window_id(self):
        """Test RunResponse with None window_id."""
        resp = RunResponse(
            action="launched",
            window_id=None,
            focused=False,
            message="Launched"
        )
        assert resp.window_id is None

    def test_run_response_json_serialization(self):
        """Test RunResponse serializes to JSON."""
        resp = RunResponse(
            action="focused",
            window_id=12345,
            focused=True,
            message="Focused Firefox"
        )
        data = resp.model_dump()
        assert data["action"] == "focused"
        assert data["window_id"] == 12345
        assert data["focused"] is True
        assert data["message"] == "Focused Firefox"


class TestWindowStateInfo:
    """Test WindowStateInfo dataclass."""

    def test_window_state_info_not_found(self):
        """Test WindowStateInfo for NOT_FOUND state."""
        info = WindowStateInfo(
            state=WindowState.NOT_FOUND,
            window=None,
            current_workspace="1",
            window_workspace=None,
            is_focused=False
        )
        assert info.state == WindowState.NOT_FOUND
        assert info.window is None
        assert info.window_id is None
        assert info.is_floating is False
        assert info.geometry is None

    def test_window_state_info_properties(self):
        """Test WindowStateInfo derived properties."""
        # Create mock window object
        class MockRect:
            x, y, width, height = 100, 200, 1600, 900

        class MockWindow:
            id = 12345
            floating = "user_on"
            rect = MockRect()

        info = WindowStateInfo(
            state=WindowState.SAME_WORKSPACE_FOCUSED,
            window=MockWindow(),
            current_workspace="1",
            window_workspace="1",
            is_focused=True
        )

        assert info.window_id == 12345
        assert info.is_floating is True
        assert info.geometry == {
            "x": 100,
            "y": 200,
            "width": 1600,
            "height": 900
        }

    def test_window_state_info_tiled_window(self):
        """Test WindowStateInfo for tiled window (no geometry)."""
        class MockWindow:
            id = 12345
            floating = "auto_off"
            rect = None

        info = WindowStateInfo(
            state=WindowState.SAME_WORKSPACE_UNFOCUSED,
            window=MockWindow(),
            current_workspace="1",
            window_workspace="1",
            is_focused=False
        )

        assert info.is_floating is False
        assert info.geometry is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
