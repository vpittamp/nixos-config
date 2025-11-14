"""Unit tests for FocusTracker service.

Feature 074: Session Management
Tests for workspace and window focus tracking (T021-T025, US1, US4)
"""

import pytest
import asyncio
import json
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock

# Import directly from modules to avoid relative import issues
import sys
from pathlib import Path as ImportPath
sys.path.insert(0, str(ImportPath(__file__).parent.parent.parent / "services"))
sys.path.insert(0, str(ImportPath(__file__).parent.parent.parent / "models"))
from focus_tracker import FocusTracker
from legacy import DaemonState


class MockStateManager:
    """Mock StateManager for testing FocusTracker."""

    def __init__(self):
        self.state = DaemonState()


@pytest.fixture
def temp_config_dir():
    """Create temporary config directory for tests."""
    temp_dir = Path(tempfile.mkdtemp())
    yield temp_dir
    shutil.rmtree(temp_dir)


@pytest.fixture
def state_manager():
    """Create mock StateManager."""
    return MockStateManager()


@pytest.fixture
def focus_tracker(state_manager, temp_config_dir):
    """Create FocusTracker instance with temp config dir."""
    return FocusTracker(state_manager, config_dir=temp_config_dir)


# ============================================================================
# FocusTracker Initialization Tests
# ============================================================================

class TestFocusTrackerInit:
    """Test FocusTracker initialization."""

    def test_initialization(self, temp_config_dir):
        """Test basic FocusTracker initialization."""
        state_manager = MockStateManager()
        tracker = FocusTracker(state_manager, config_dir=temp_config_dir)

        assert tracker.state_manager == state_manager
        assert tracker.config_dir == temp_config_dir
        assert tracker.config_dir.exists()
        assert tracker.project_focus_file == temp_config_dir / "project-focus-state.json"
        assert tracker.workspace_focus_file == temp_config_dir / "workspace-focus-state.json"

    def test_creates_config_dir_if_missing(self):
        """Test FocusTracker creates config directory if it doesn't exist."""
        with tempfile.TemporaryDirectory() as temp_dir:
            config_dir = Path(temp_dir) / "subdir" / "i3"
            assert not config_dir.exists()

            state_manager = MockStateManager()
            tracker = FocusTracker(state_manager, config_dir=config_dir)

            assert config_dir.exists()
            assert config_dir.is_dir()


# ============================================================================
# Workspace Focus Tracking Tests (T022-T023, US1)
# ============================================================================

class TestWorkspaceFocusTracking:
    """Test workspace focus tracking methods."""

    @pytest.mark.asyncio
    async def test_track_workspace_focus(self, focus_tracker, state_manager):
        """Test track_workspace_focus() updates state and persists (T022, US1)."""
        await focus_tracker.track_workspace_focus("nixos", 3)

        # Check state was updated
        assert state_manager.state.get_focused_workspace("nixos") == 3

        # Check persistence file was written
        assert focus_tracker.project_focus_file.exists()
        persisted_data = json.loads(focus_tracker.project_focus_file.read_text())
        assert persisted_data["nixos"] == 3

    @pytest.mark.asyncio
    async def test_track_multiple_projects(self, focus_tracker, state_manager):
        """Test tracking focus for multiple projects."""
        await focus_tracker.track_workspace_focus("nixos", 3)
        await focus_tracker.track_workspace_focus("dotfiles", 5)
        await focus_tracker.track_workspace_focus("personal", 7)

        assert state_manager.state.get_focused_workspace("nixos") == 3
        assert state_manager.state.get_focused_workspace("dotfiles") == 5
        assert state_manager.state.get_focused_workspace("personal") == 7

        # Check all persisted
        persisted_data = json.loads(focus_tracker.project_focus_file.read_text())
        assert persisted_data["nixos"] == 3
        assert persisted_data["dotfiles"] == 5
        assert persisted_data["personal"] == 7

    @pytest.mark.asyncio
    async def test_track_workspace_focus_update_existing(self, focus_tracker, state_manager):
        """Test updating focus for existing project."""
        await focus_tracker.track_workspace_focus("nixos", 3)
        assert state_manager.state.get_focused_workspace("nixos") == 3

        await focus_tracker.track_workspace_focus("nixos", 5)
        assert state_manager.state.get_focused_workspace("nixos") == 5

        # Check persistence reflects update
        persisted_data = json.loads(focus_tracker.project_focus_file.read_text())
        assert persisted_data["nixos"] == 5

    @pytest.mark.asyncio
    async def test_get_project_focused_workspace(self, focus_tracker, state_manager):
        """Test get_project_focused_workspace() retrieves workspace (T023, US1)."""
        # No focus history initially
        workspace_num = await focus_tracker.get_project_focused_workspace("nixos")
        assert workspace_num is None

        # Set focus
        await focus_tracker.track_workspace_focus("nixos", 3)

        # Retrieve focus
        workspace_num = await focus_tracker.get_project_focused_workspace("nixos")
        assert workspace_num == 3

    @pytest.mark.asyncio
    async def test_thread_safety_workspace_focus(self, focus_tracker):
        """Test concurrent workspace focus tracking is thread-safe."""
        async def track_focus(project, workspace):
            await focus_tracker.track_workspace_focus(project, workspace)

        # Run multiple concurrent updates
        await asyncio.gather(
            track_focus("nixos", 1),
            track_focus("dotfiles", 2),
            track_focus("personal", 3),
        )

        # All should be persisted
        assert focus_tracker.project_focus_file.exists()
        persisted_data = json.loads(focus_tracker.project_focus_file.read_text())
        assert len(persisted_data) == 3


# ============================================================================
# Window Focus Tracking Tests (T065-T066, US4)
# ============================================================================

class TestWindowFocusTracking:
    """Test window focus tracking methods."""

    @pytest.mark.asyncio
    async def test_track_window_focus(self, focus_tracker, state_manager):
        """Test track_window_focus() updates state and persists (T065, US4)."""
        await focus_tracker.track_window_focus(workspace_num=3, window_id=12345)

        # Check state was updated
        assert state_manager.state.get_focused_window(3) == 12345

        # Check persistence file was written
        assert focus_tracker.workspace_focus_file.exists()
        persisted_data = json.loads(focus_tracker.workspace_focus_file.read_text())
        assert persisted_data["3"] == 12345

    @pytest.mark.asyncio
    async def test_track_multiple_workspace_windows(self, focus_tracker, state_manager):
        """Test tracking focused windows for multiple workspaces."""
        await focus_tracker.track_window_focus(workspace_num=1, window_id=11111)
        await focus_tracker.track_window_focus(workspace_num=2, window_id=22222)
        await focus_tracker.track_window_focus(workspace_num=3, window_id=33333)

        assert state_manager.state.get_focused_window(1) == 11111
        assert state_manager.state.get_focused_window(2) == 22222
        assert state_manager.state.get_focused_window(3) == 33333

        # Check all persisted
        persisted_data = json.loads(focus_tracker.workspace_focus_file.read_text())
        assert persisted_data["1"] == 11111
        assert persisted_data["2"] == 22222
        assert persisted_data["3"] == 33333

    @pytest.mark.asyncio
    async def test_track_window_focus_update_existing(self, focus_tracker, state_manager):
        """Test updating focused window for existing workspace."""
        await focus_tracker.track_window_focus(workspace_num=3, window_id=12345)
        assert state_manager.state.get_focused_window(3) == 12345

        await focus_tracker.track_window_focus(workspace_num=3, window_id=67890)
        assert state_manager.state.get_focused_window(3) == 67890

        # Check persistence reflects update
        persisted_data = json.loads(focus_tracker.workspace_focus_file.read_text())
        assert persisted_data["3"] == 67890

    @pytest.mark.asyncio
    async def test_get_workspace_focused_window(self, focus_tracker, state_manager):
        """Test get_workspace_focused_window() retrieves window ID (T066, US4)."""
        # No focus history initially
        window_id = await focus_tracker.get_workspace_focused_window(3)
        assert window_id is None

        # Set focus
        await focus_tracker.track_window_focus(workspace_num=3, window_id=12345)

        # Retrieve focus
        window_id = await focus_tracker.get_workspace_focused_window(3)
        assert window_id == 12345


# ============================================================================
# Persistence Tests (T024-T025, US1)
# ============================================================================

class TestFocusPersistence:
    """Test focus state persistence and loading."""

    @pytest.mark.asyncio
    async def test_persist_focus_state(self, focus_tracker, state_manager):
        """Test persist_focus_state() writes JSON files (T024, US1)."""
        # Set up state
        state_manager.state.set_focused_workspace("nixos", 3)
        state_manager.state.set_focused_workspace("dotfiles", 5)
        state_manager.state.set_focused_window(3, 12345)
        state_manager.state.set_focused_window(5, 67890)

        # Persist
        await focus_tracker.persist_focus_state()

        # Check project focus file
        assert focus_tracker.project_focus_file.exists()
        project_data = json.loads(focus_tracker.project_focus_file.read_text())
        assert project_data == {"nixos": 3, "dotfiles": 5}

        # Check workspace focus file
        assert focus_tracker.workspace_focus_file.exists()
        workspace_data = json.loads(focus_tracker.workspace_focus_file.read_text())
        assert workspace_data == {"3": 12345, "5": 67890}

    @pytest.mark.asyncio
    async def test_load_focus_state(self, focus_tracker, state_manager, temp_config_dir):
        """Test load_focus_state() restores from JSON files (T025, US1)."""
        # Create JSON files manually
        project_focus_data = {"nixos": 3, "dotfiles": 5}
        (temp_config_dir / "project-focus-state.json").write_text(json.dumps(project_focus_data))

        workspace_focus_data = {"3": 12345, "5": 67890}
        (temp_config_dir / "workspace-focus-state.json").write_text(json.dumps(workspace_focus_data))

        # Load state
        await focus_tracker.load_focus_state()

        # Check state was restored
        assert state_manager.state.get_focused_workspace("nixos") == 3
        assert state_manager.state.get_focused_workspace("dotfiles") == 5
        assert state_manager.state.get_focused_window(3) == 12345
        assert state_manager.state.get_focused_window(5) == 67890

    @pytest.mark.asyncio
    async def test_load_focus_state_missing_files(self, focus_tracker, state_manager):
        """Test load_focus_state() handles missing files gracefully."""
        # Files don't exist initially
        assert not focus_tracker.project_focus_file.exists()
        assert not focus_tracker.workspace_focus_file.exists()

        # Should not raise exception
        await focus_tracker.load_focus_state()

        # State should be empty
        assert state_manager.state.project_focused_workspace == {}
        assert state_manager.state.workspace_focused_window == {}

    @pytest.mark.asyncio
    async def test_load_focus_state_corrupt_json(self, focus_tracker, state_manager, temp_config_dir):
        """Test load_focus_state() handles corrupt JSON gracefully."""
        # Write invalid JSON
        (temp_config_dir / "project-focus-state.json").write_text("not valid json{")
        (temp_config_dir / "workspace-focus-state.json").write_text("also not valid")

        # Should not raise exception
        await focus_tracker.load_focus_state()

        # State should remain empty (graceful degradation)
        assert state_manager.state.project_focused_workspace == {}
        assert state_manager.state.workspace_focused_window == {}

    @pytest.mark.asyncio
    async def test_persist_and_load_round_trip(self, focus_tracker, state_manager):
        """Test complete round trip: persist then load."""
        # Set up state
        await focus_tracker.track_workspace_focus("nixos", 3)
        await focus_tracker.track_workspace_focus("dotfiles", 5)
        await focus_tracker.track_window_focus(3, 12345)
        await focus_tracker.track_window_focus(5, 67890)

        # Create new state manager (simulating daemon restart)
        new_state_manager = MockStateManager()
        new_tracker = FocusTracker(new_state_manager, config_dir=focus_tracker.config_dir)

        # Load state
        await new_tracker.load_focus_state()

        # Verify state was restored
        assert new_state_manager.state.get_focused_workspace("nixos") == 3
        assert new_state_manager.state.get_focused_workspace("dotfiles") == 5
        assert new_state_manager.state.get_focused_window(3) == 12345
        assert new_state_manager.state.get_focused_window(5) == 67890


# ============================================================================
# Integration Tests
# ============================================================================

class TestFocusTrackerIntegration:
    """Integration tests for FocusTracker with multiple components."""

    @pytest.mark.asyncio
    async def test_complete_workflow(self, focus_tracker, state_manager):
        """Test complete focus tracking workflow."""
        # Scenario: User works on nixos project on workspace 3
        await focus_tracker.track_workspace_focus("nixos", 3)
        await focus_tracker.track_window_focus(3, 12345)

        # Switch to dotfiles project on workspace 5
        await focus_tracker.track_workspace_focus("dotfiles", 5)
        await focus_tracker.track_window_focus(5, 67890)

        # Verify current state
        assert await focus_tracker.get_project_focused_workspace("nixos") == 3
        assert await focus_tracker.get_project_focused_workspace("dotfiles") == 5
        assert await focus_tracker.get_workspace_focused_window(3) == 12345
        assert await focus_tracker.get_workspace_focused_window(5) == 67890

        # Verify persistence
        assert focus_tracker.project_focus_file.exists()
        assert focus_tracker.workspace_focus_file.exists()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
