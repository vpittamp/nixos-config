"""
Unit tests for event buffer persistence

Feature 030: Production Readiness
Task T019: Event persistence tests

Tests save/load functionality and automatic pruning.
"""

import pytest
import tempfile
import json
from pathlib import Path
from datetime import datetime, timedelta
from unittest.mock import Mock

# Import event buffer and models from daemon (sys.path configured in conftest.py)
from event_buffer import EventBuffer
from models import EventEntry


# ============================================================================
# Test Fixtures
# ============================================================================

@pytest.fixture
def temp_persistence_dir(tmp_path):
    """Create temporary persistence directory"""
    return tmp_path / "event-history"


@pytest.fixture
def event_buffer(temp_persistence_dir):
    """Create event buffer with temporary persistence directory"""
    return EventBuffer(
        max_size=100,
        persistence_dir=temp_persistence_dir,
        retention_days=7
    )


@pytest.fixture
def sample_events():
    """Create sample events for testing"""
    events = []
    base_time = datetime.now()

    for i in range(10):
        event = EventEntry(
            event_id=i,
            event_type=f"test_event_{i}",
            timestamp=base_time - timedelta(minutes=i),
            source="daemon",  # Use valid source value
        )
        events.append(event)

    return events


# ============================================================================
# Save to Disk Tests
# ============================================================================

@pytest.mark.asyncio
async def test_save_to_disk_basic(event_buffer, sample_events, temp_persistence_dir):
    """Test basic save functionality"""
    # Add events to buffer
    for event in sample_events:
        await event_buffer.add_event(event)

    # Save to disk
    await event_buffer.save_to_disk()

    # Verify file was created
    event_files = list(temp_persistence_dir.glob("events-*.json"))
    assert len(event_files) == 1

    # Verify file contents
    with open(event_files[0]) as f:
        data = json.load(f)

    assert data["event_count"] == len(sample_events)
    assert len(data["events"]) == len(sample_events)
    assert "saved_at" in data


@pytest.mark.asyncio
async def test_save_empty_buffer(event_buffer, temp_persistence_dir):
    """Test saving empty buffer (should not create file)"""
    await event_buffer.save_to_disk()

    # No file should be created
    event_files = list(temp_persistence_dir.glob("events-*.json"))
    assert len(event_files) == 0


@pytest.mark.asyncio
async def test_save_creates_directory(tmp_path):
    """Test that save creates persistence directory if it doesn't exist"""
    persistence_dir = tmp_path / "new" / "nested" / "dir"
    event_buffer = EventBuffer(persistence_dir=persistence_dir)

    # Add an event
    event = EventEntry(
        event_id=1,
        event_type="test",
        timestamp=datetime.now(),
        source="daemon"
    )
    await event_buffer.add_event(event)

    # Save should create directory
    await event_buffer.save_to_disk()

    assert persistence_dir.exists()
    assert persistence_dir.is_dir()


@pytest.mark.asyncio
async def test_save_serialization(event_buffer, temp_persistence_dir):
    """Test that datetime objects are properly serialized"""
    event = EventEntry(
        event_id=1,
        event_type="test",
        timestamp=datetime.now(),
        source="daemon",
        project_name="test-project",
    )
    await event_buffer.add_event(event)

    await event_buffer.save_to_disk()

    # Load and verify
    event_files = list(temp_persistence_dir.glob("events-*.json"))
    with open(event_files[0]) as f:
        data = json.load(f)

    # Timestamp should be ISO string
    assert isinstance(data["events"][0]["timestamp"], str)
    assert "T" in data["events"][0]["timestamp"]  # ISO format marker


# ============================================================================
# Load from Disk Tests
# ============================================================================

@pytest.mark.asyncio
async def test_load_from_disk_basic(event_buffer, sample_events, temp_persistence_dir):
    """Test basic load functionality"""
    # Save events
    for event in sample_events:
        await event_buffer.add_event(event)
    await event_buffer.save_to_disk()

    # Create new buffer and load
    new_buffer = EventBuffer(persistence_dir=temp_persistence_dir)
    loaded_count = await new_buffer.load_from_disk()

    assert loaded_count == len(sample_events)
    assert len(new_buffer.events) == len(sample_events)


@pytest.mark.asyncio
async def test_load_nonexistent_directory(tmp_path):
    """Test loading when persistence directory doesn't exist"""
    persistence_dir = tmp_path / "nonexistent"
    event_buffer = EventBuffer(persistence_dir=persistence_dir)

    loaded_count = await event_buffer.load_from_disk()

    assert loaded_count == 0
    assert len(event_buffer.events) == 0


@pytest.mark.asyncio
async def test_load_multiple_files(event_buffer, temp_persistence_dir):
    """Test loading events from multiple files"""
    # Create multiple event files manually
    for i in range(3):
        filepath = temp_persistence_dir / f"events-2025-10-{i+1:02d}-12-00-00.json"
        temp_persistence_dir.mkdir(parents=True, exist_ok=True)

        events_data = [
            {
                "event_id": i * 10 + j,
                "event_type": f"test_{i}_{j}",
                "timestamp": datetime.now().isoformat(),
                "source": "daemon",
            }
            for j in range(5)
        ]

        with open(filepath, 'w') as f:
            json.dump({"events": events_data}, f)

    # Load all files
    loaded_count = await event_buffer.load_from_disk()

    assert loaded_count == 15  # 3 files * 5 events each


@pytest.mark.asyncio
async def test_load_event_reconstruction(event_buffer, sample_events, temp_persistence_dir):
    """Test that loaded events are properly reconstructed as EventEntry objects"""
    # Save events
    for event in sample_events:
        await event_buffer.add_event(event)
    await event_buffer.save_to_disk()

    # Load into new buffer
    new_buffer = EventBuffer(persistence_dir=temp_persistence_dir)
    await new_buffer.load_from_disk()

    # Verify events are EventEntry instances
    for event in new_buffer.events:
        assert isinstance(event, EventEntry)
        assert hasattr(event, "event_id")
        assert hasattr(event, "event_type")
        assert hasattr(event, "timestamp")
        assert isinstance(event.timestamp, datetime)


# ============================================================================
# Pruning Tests
# ============================================================================

@pytest.mark.asyncio
async def test_prune_old_files(event_buffer, temp_persistence_dir):
    """Test that old event files are pruned on load"""
    # Create old file (8 days ago)
    old_filepath = temp_persistence_dir / "events-old.json"
    temp_persistence_dir.mkdir(parents=True, exist_ok=True)

    with open(old_filepath, 'w') as f:
        json.dump({"events": [{"event_id": 1, "event_type": "old", "timestamp": datetime.now().isoformat(), "source": "daemon"}]}, f)

    # Set file mtime to 8 days ago
    old_time = (datetime.now() - timedelta(days=8)).timestamp()
    import os
    os.utime(old_filepath, (old_time, old_time))

    # Load - should prune old file
    loaded_count = await event_buffer.load_from_disk()

    assert loaded_count == 0
    assert not old_filepath.exists()  # Old file should be deleted


@pytest.mark.asyncio
async def test_prune_old_events_in_memory(event_buffer):
    """Test pruning old events from memory"""
    # Add old events
    old_time = datetime.now() - timedelta(days=10)
    for i in range(5):
        event = EventEntry(
            event_id=i,
            event_type="old_event",
            timestamp=old_time,
            source="daemon",
        )
        await event_buffer.add_event(event)

    # Add recent events
    recent_time = datetime.now()
    for i in range(5, 10):
        event = EventEntry(
            event_id=i,
            event_type="recent_event",
            timestamp=recent_time,
            source="daemon",
        )
        await event_buffer.add_event(event)

    # Prune old events
    pruned_count = await event_buffer.prune_old_events()

    assert pruned_count == 5  # 5 old events removed
    assert len(event_buffer.events) == 5  # 5 recent events remain


@pytest.mark.asyncio
async def test_prune_old_events_method(event_buffer, temp_persistence_dir):
    """Test the prune_old_events method"""
    # Create old and new files
    old_filepath = temp_persistence_dir / "events-old.json"
    new_filepath = temp_persistence_dir / "events-new.json"
    temp_persistence_dir.mkdir(parents=True, exist_ok=True)

    with open(old_filepath, 'w') as f:
        json.dump({"events": []}, f)
    with open(new_filepath, 'w') as f:
        json.dump({"events": []}, f)

    # Set old file mtime
    old_time = (datetime.now() - timedelta(days=10)).timestamp()
    import os
    os.utime(old_filepath, (old_time, old_time))

    # Prune
    await event_buffer.prune_old_events()

    # Old file should be gone, new file should remain
    assert not old_filepath.exists()
    assert new_filepath.exists()


@pytest.mark.asyncio
async def test_retention_period_respected(temp_persistence_dir):
    """Test that retention period setting is respected"""
    # Create buffer with 3-day retention
    event_buffer = EventBuffer(
        persistence_dir=temp_persistence_dir,
        retention_days=3
    )

    # Create file that's 4 days old (should be pruned)
    old_filepath = temp_persistence_dir / "events-old.json"
    temp_persistence_dir.mkdir(parents=True, exist_ok=True)

    with open(old_filepath, 'w') as f:
        json.dump({"events": [{"event_id": 1, "event_type": "test", "timestamp": datetime.now().isoformat(), "source": "daemon"}]}, f)

    # Set file mtime to 4 days ago
    old_time = (datetime.now() - timedelta(days=4)).timestamp()
    import os
    os.utime(old_filepath, (old_time, old_time))

    # Load - should prune
    await event_buffer.load_from_disk()

    assert not old_filepath.exists()


# ============================================================================
# Error Handling Tests
# ============================================================================

@pytest.mark.asyncio
async def test_save_handles_errors_gracefully(event_buffer, temp_persistence_dir):
    """Test that save handles errors without crashing"""
    # Add event with invalid data
    event = EventEntry(
        event_id=1,
        event_type="test",
        timestamp=datetime.now(),
        source="daemon",
    )
    await event_buffer.add_event(event)

    # Make directory read-only to trigger error
    temp_persistence_dir.mkdir(parents=True, exist_ok=True)
    import os
    os.chmod(temp_persistence_dir, 0o444)

    try:
        # Should not raise exception
        await event_buffer.save_to_disk()
    finally:
        # Restore permissions
        os.chmod(temp_persistence_dir, 0o755)


@pytest.mark.asyncio
async def test_load_handles_corrupted_file(event_buffer, temp_persistence_dir):
    """Test that load handles corrupted JSON gracefully"""
    # Create corrupted file
    temp_persistence_dir.mkdir(parents=True, exist_ok=True)
    corrupted_file = temp_persistence_dir / "events-corrupted.json"

    with open(corrupted_file, 'w') as f:
        f.write("{ invalid json }")

    # Should not raise exception
    loaded_count = await event_buffer.load_from_disk()

    assert loaded_count == 0  # No events loaded from corrupted file


# ============================================================================
# Integration Tests
# ============================================================================

@pytest.mark.asyncio
async def test_full_persistence_cycle(sample_events, temp_persistence_dir):
    """Test complete save/shutdown/load cycle"""
    # Create buffer and add events
    buffer1 = EventBuffer(persistence_dir=temp_persistence_dir)
    for event in sample_events:
        await buffer1.add_event(event)

    # Simulate shutdown - save events
    await buffer1.save_to_disk()

    # Simulate restart - create new buffer and load
    buffer2 = EventBuffer(persistence_dir=temp_persistence_dir)
    loaded_count = await buffer2.load_from_disk()

    # Verify events were preserved
    assert loaded_count == len(sample_events)
    assert len(buffer2.events) == len(sample_events)

    # Verify event data integrity
    for i, event in enumerate(buffer2.events):
        assert event.event_type == f"test_event_{i}"


@pytest.mark.asyncio
async def test_persistence_with_buffer_overflow(temp_persistence_dir):
    """Test persistence when buffer exceeds max_size"""
    # Create buffer with small max_size
    event_buffer = EventBuffer(
        max_size=5,
        persistence_dir=temp_persistence_dir
    )

    # Add more events than max_size
    for i in range(10):
        event = EventEntry(
            event_id=i,
            event_type=f"event_{i}",
            timestamp=datetime.now(),
            source="daemon",
        )
        await event_buffer.add_event(event)

    # Buffer should only have last 5 events
    assert len(event_buffer.events) == 5

    # Save and load
    await event_buffer.save_to_disk()

    new_buffer = EventBuffer(persistence_dir=temp_persistence_dir)
    loaded_count = await new_buffer.load_from_disk()

    # Should load only the 5 events that were in buffer
    assert loaded_count == 5
