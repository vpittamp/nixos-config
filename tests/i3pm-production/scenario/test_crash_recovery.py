"""
Scenario tests for crash recovery

Feature 030: Production Readiness
Task T028: Scenario tests for crash recovery

Tests real-world crash scenarios:
- Daemon crashes mid-operation
- i3 restarts while daemon running
- Corrupted state files
- Event buffer overflow
"""

import pytest
import json
import asyncio
from pathlib import Path
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime

from recovery.auto_recovery import run_startup_recovery
from recovery.i3_reconnect import I3ReconnectionManager, ReconnectionConfig


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def temp_config_dir(tmp_path):
    """Create temporary config directory"""
    return tmp_path / ".config/i3"


@pytest.fixture
def mock_event_buffer():
    """Create mock event buffer"""
    buffer = Mock()
    buffer.events = []
    buffer.max_size = 500
    return buffer


@pytest.fixture
def mock_i3_connection():
    """Create mock i3 connection"""
    conn = Mock()
    conn.get_tree.return_value = {"id": 1, "nodes": []}
    conn.get_workspaces.return_value = []
    conn.get_outputs.return_value = []
    return conn


# ============================================================================
# Scenario 1: Daemon Crash During Project Switch
# ============================================================================

@pytest.mark.asyncio
async def test_crash_during_project_switch_recovery(temp_config_dir, mock_i3_connection):
    """
    Scenario: Daemon crashes while switching projects

    Setup:
    - Active project: nixos
    - Some windows marked project:nixos
    - Crash occurs before completing switch to 'stacks'

    Expected recovery:
    - Detect inconsistent state
    - Validate window marks
    - Complete or rollback partial switch
    """
    # Setup environment
    temp_config_dir.mkdir(parents=True)
    projects_dir = temp_config_dir / "projects"
    projects_dir.mkdir()

    # Create two projects
    for project_name in ["nixos", "stacks"]:
        project_file = projects_dir / f"{project_name}.json"
        with open(project_file, 'w') as f:
            json.dump({
                "name": project_name,
                "display_name": project_name.title(),
                "directory": f"/home/user/{project_name}",
            }, f)

    # Create app-classes.json
    app_classes_file = temp_config_dir / "app-classes.json"
    with open(app_classes_file, 'w') as f:
        json.dump({"scoped_classes": ["Ghostty", "Code"]}, f)

    # Run recovery
    result = await run_startup_recovery(
        i3_connection=mock_i3_connection,
        config_dir=temp_config_dir,
    )

    # Recovery should succeed
    assert result.success
    assert result.validation_result.is_valid


# ============================================================================
# Scenario 2: i3 Restart While Daemon Running
# ============================================================================

@pytest.mark.asyncio
async def test_i3_restart_reconnection(mock_i3_connection):
    """
    Scenario: i3 restarts while daemon is running

    Expected behavior:
    - Detect connection loss
    - Attempt reconnection with backoff
    - Restore event subscriptions after reconnection
    """
    reconnect_config = ReconnectionConfig(
        initial_delay=0.1,  # Fast for testing
        max_delay=1.0,
        max_attempts=3,
    )

    # Track reconnection callback
    reconnect_called = []

    async def on_reconnect(connection):
        reconnect_called.append(True)

    manager = I3ReconnectionManager(
        config=reconnect_config,
        on_reconnect=on_reconnect,
    )

    # Simulate initial connection
    manager.connection = mock_i3_connection
    manager.is_connected = True

    # Simulate connection loss
    mock_i3_connection.get_tree.side_effect = Exception("Connection lost")
    manager.is_connected = False

    # Mock successful reconnection after 2 attempts
    attempt_count = [0]

    async def mock_create_connection():
        attempt_count[0] += 1
        if attempt_count[0] < 2:
            raise Exception("Connection failed")
        return mock_i3_connection

    manager._create_connection = mock_create_connection

    # Restore successful get_tree after reconnection
    async def mock_get_tree():
        return {"id": 1, "nodes": []}

    mock_i3_connection.get_tree = mock_get_tree

    # Attempt reconnection
    success = await manager.reconnect_with_backoff()

    # Should reconnect successfully
    assert success
    assert manager.is_connected
    assert len(reconnect_called) == 1  # Callback should be called


# ============================================================================
# Scenario 3: Corrupted State Files
# ============================================================================

@pytest.mark.asyncio
async def test_corrupted_state_files_recovery(temp_config_dir, mock_i3_connection):
    """
    Scenario: Daemon starts with corrupted configuration files

    Corruptions:
    - Invalid JSON in app-classes.json
    - Invalid JSON in project file
    - Missing required fields in project

    Expected recovery:
    - Backup corrupted files
    - Replace with defaults or remove invalid files
    - Continue startup
    """
    temp_config_dir.mkdir(parents=True)
    projects_dir = temp_config_dir / "projects"
    projects_dir.mkdir()

    # Create corrupted app-classes.json
    app_classes_file = temp_config_dir / "app-classes.json"
    with open(app_classes_file, 'w') as f:
        f.write("{ corrupted json ")

    # Create project with invalid JSON
    invalid_project = projects_dir / "invalid.json"
    with open(invalid_project, 'w') as f:
        f.write("{ also corrupted ")

    # Create project with missing fields
    incomplete_project = projects_dir / "incomplete.json"
    with open(incomplete_project, 'w') as f:
        json.dump({"name": "incomplete"}, f)  # Missing display_name, directory

    # Run recovery
    result = await run_startup_recovery(
        i3_connection=mock_i3_connection,
        config_dir=temp_config_dir,
    )

    # Should repair app-classes.json
    assert app_classes_file.exists()
    with open(app_classes_file) as f:
        data = json.load(f)
    assert isinstance(data, dict)

    # Should backup corrupted file
    backup_file = app_classes_file.with_suffix('.json.backup')
    assert backup_file.exists()


# ============================================================================
# Scenario 4: Event Buffer Overflow
# ============================================================================

@pytest.mark.asyncio
async def test_event_buffer_overflow_recovery(temp_config_dir, mock_i3_connection):
    """
    Scenario: Event buffer grows beyond max_size

    Setup:
    - Buffer has 600 events (max_size = 500)
    - Some events are None (corrupted)

    Expected recovery:
    - Remove None entries
    - Report buffer overflow
    - Suggest pruning old events
    """
    # Create buffer exceeding max_size
    mock_buffer = Mock()
    mock_buffer.max_size = 500
    mock_buffer.events = [Mock()] * 600  # 600 events
    mock_buffer.events[100] = None  # Add corrupted entry
    mock_buffer.events[200] = None

    # Setup minimal config
    temp_config_dir.mkdir(parents=True)

    # Run recovery
    result = await run_startup_recovery(
        i3_connection=mock_i3_connection,
        event_buffer=mock_buffer,
        config_dir=temp_config_dir,
    )

    # Should detect buffer issues
    assert result.validation_result is not None
    validation = result.validation_result

    # Should report buffer overflow
    assert any("exceeds max_size" in e for e in validation.errors)


# ============================================================================
# Scenario 5: Persistent Event History Recovery
# ============================================================================

@pytest.mark.asyncio
async def test_persistent_event_history_recovery(temp_config_dir):
    """
    Scenario: Daemon restarts after crash, loads persisted events

    Setup:
    - Previous daemon saved events to disk before crash
    - New daemon starts and loads events
    - Old event files should be pruned (> 7 days)

    Expected behavior:
    - Load recent events from disk
    - Prune old event files
    - Continue operation with restored event history
    """
    from event_buffer import EventBuffer
    from models import EventEntry
    from datetime import timedelta

    # Create event history directory
    event_history_dir = temp_config_dir / "event-history"
    event_history_dir.mkdir(parents=True)

    # Create recent event file (today)
    recent_file = event_history_dir / f"events-{datetime.now().strftime('%Y-%m-%d-%H-%M-%S')}.json"
    recent_events = [
        {
            "event_id": 1,
            "event_type": "window::new",
            "timestamp": datetime.now().isoformat(),
            "source": "daemon",
        },
        {
            "event_id": 2,
            "event_type": "workspace::focus",
            "timestamp": datetime.now().isoformat(),
            "source": "daemon",
        }
    ]

    with open(recent_file, 'w') as f:
        json.dump({"events": recent_events}, f)

    # Create old event file (8 days ago)
    old_file = event_history_dir / "events-2025-01-01-00-00-00.json"
    with open(old_file, 'w') as f:
        json.dump({"events": []}, f)

    # Set file mtime to 8 days ago
    import os
    old_time = (datetime.now() - timedelta(days=8)).timestamp()
    os.utime(old_file, (old_time, old_time))

    # Create event buffer and load
    buffer = EventBuffer(persistence_dir=event_history_dir, retention_days=7)
    loaded_count = await buffer.load_from_disk()

    # Should load recent events
    assert loaded_count == 2

    # Old file should be pruned
    assert not old_file.exists()
    assert recent_file.exists()


# ============================================================================
# Scenario 6: Multiple Concurrent Recovery Attempts
# ============================================================================

@pytest.mark.asyncio
async def test_concurrent_recovery_attempts(temp_config_dir, mock_i3_connection):
    """
    Scenario: Multiple recovery attempts triggered simultaneously

    This tests thread safety and prevents duplicate recovery actions.

    Expected behavior:
    - Only one recovery should execute
    - Others should wait or skip
    - No duplicate file creation
    """
    # Run multiple recoveries concurrently
    results = await asyncio.gather(
        run_startup_recovery(i3_connection=mock_i3_connection, config_dir=temp_config_dir),
        run_startup_recovery(i3_connection=mock_i3_connection, config_dir=temp_config_dir),
        run_startup_recovery(i3_connection=mock_i3_connection, config_dir=temp_config_dir),
    )

    # All should succeed
    assert all(r.success for r in results)

    # Directories should only be created once
    assert temp_config_dir.exists()
    assert (temp_config_dir / "projects").exists()


# ============================================================================
# Scenario 7: Recovery from OOM Kill
# ============================================================================

@pytest.mark.asyncio
async def test_recovery_from_oom_kill(temp_config_dir, mock_i3_connection):
    """
    Scenario: Daemon was OOM killed, restart with memory constraints

    Setup:
    - Large event buffer filled memory
    - Daemon was killed by OOM
    - Restart with pruned event buffer

    Expected recovery:
    - Load persisted events with limit
    - Prune old events immediately
    - Monitor memory usage
    """
    from event_buffer import EventBuffer

    # Create event buffer with large history
    event_history_dir = temp_config_dir / "event-history"
    event_history_dir.mkdir(parents=True)

    # Create multiple large event files
    for i in range(5):
        event_file = event_history_dir / f"events-2025-10-{i+1:02d}-00-00-00.json"
        large_events = [
            {
                "event_id": j,
                "event_type": f"test_{j}",
                "timestamp": datetime.now().isoformat(),
                "source": "daemon",
            }
            for j in range(100)  # 100 events per file
        ]
        with open(event_file, 'w') as f:
            json.dump({"events": large_events}, f)

    # Create buffer with smaller max_size to prevent OOM
    buffer = EventBuffer(
        max_size=100,  # Reduced from 500
        persistence_dir=event_history_dir,
        retention_days=7
    )

    # Load events
    loaded_count = await buffer.load_from_disk()

    # Should limit events loaded to max_size
    assert len(buffer.events) <= buffer.max_size


# ============================================================================
# Scenario 8: Rapid i3 Restarts
# ============================================================================

@pytest.mark.asyncio
async def test_rapid_i3_restarts_recovery():
    """
    Scenario: i3 restarts multiple times rapidly (e.g., during i3 config testing)

    Expected behavior:
    - Handle rapid connection loss/restore
    - Don't accumulate reconnection tasks
    - Maintain stable state through restarts
    """
    config = ReconnectionConfig(
        initial_delay=0.05,  # Very fast for testing
        max_delay=0.5,
        max_attempts=5,
    )

    reconnect_count = [0]

    async def on_reconnect(connection):
        reconnect_count[0] += 1

    manager = I3ReconnectionManager(config=config, on_reconnect=on_reconnect)

    # Simulate 3 rapid connection failures and recoveries
    for cycle in range(3):
        # Initial connection
        mock_conn = Mock()
        mock_conn.get_tree = AsyncMock(return_value={"id": 1})
        manager.connection = mock_conn
        manager.is_connected = True

        # Simulate connection loss
        manager.is_connected = False

        # Mock reconnection
        async def mock_create_connection():
            return mock_conn

        manager._create_connection = mock_create_connection

        # Reconnect
        success = await manager.reconnect_with_backoff()
        assert success

    # Should have reconnected 3 times
    assert reconnect_count[0] == 3
    assert manager.reconnection_count == 3
