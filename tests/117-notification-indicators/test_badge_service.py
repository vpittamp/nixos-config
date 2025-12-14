#!/usr/bin/env python3
"""Unit tests for Feature 117 badge service."""

import json
import os
import sys
import tempfile
import time
from pathlib import Path

# Add daemon module to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "home-modules/desktop/i3-project-event-daemon"))
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "home-modules/tools/i3_project_manager"))


def test_badge_model():
    """Test WindowBadge Pydantic model."""
    from badge_service import WindowBadge, BadgeStateType

    # Test working badge
    badge = WindowBadge(
        window_id=12345,
        timestamp=time.time(),
        source="claude-code",
        state="working"
    )
    assert badge.window_id == 12345
    assert badge.state == "working"
    assert badge.count == 1
    print("✓ WindowBadge model works correctly")


def test_badge_state():
    """Test BadgeState manager."""
    from badge_service import BadgeState

    state = BadgeState()

    # Create badge
    badge = state.create_badge(12345, source="claude-code", state="working")
    assert badge.window_id == 12345
    assert badge.state == "working"

    # Update to stopped
    badge = state.create_badge(12345, source="claude-code", state="stopped")
    assert badge.state == "stopped"
    assert badge.count == 2  # Incremented on stopped

    # Clear badge
    cleared = state.clear_badge(12345)
    assert cleared == 2
    assert not state.has_badge(12345)

    print("✓ BadgeState manager works correctly")


def test_badge_file_operations():
    """Test file-based badge read/write."""
    from badge_service import (
        WindowBadge,
        read_badge_file,
        write_badge_file,
        delete_badge_file,
        read_all_badge_files,
        get_badge_dir,
    )

    # Use temp directory for testing
    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["XDG_RUNTIME_DIR"] = tmpdir

        # Create badge directory
        badge_dir = Path(tmpdir) / "i3pm-badges"
        badge_dir.mkdir(parents=True, exist_ok=True)

        # Create test badge
        badge = WindowBadge(
            window_id=99999,
            timestamp=time.time(),
            source="test",
            state="working"
        )

        # Write badge file
        badge_file = badge_dir / "99999.json"
        with open(badge_file, "w") as f:
            json.dump(badge.model_dump(), f)

        # Read all badges
        badges = read_all_badge_files()
        assert 99999 in badges
        assert badges[99999].state == "working"

        # Delete badge
        badge_file.unlink()
        badges = read_all_badge_files()
        assert 99999 not in badges

        print("✓ Badge file operations work correctly")


def test_constants():
    """Test badge timing constants."""
    from badge_service import BADGE_MIN_AGE_FOR_DISMISS, BADGE_MAX_AGE

    assert BADGE_MIN_AGE_FOR_DISMISS == 1.0  # 1 second
    assert BADGE_MAX_AGE == 300  # 5 minutes

    print("✓ Badge constants are correct")


def test_eww_format():
    """Test Eww JSON format conversion."""
    from badge_service import BadgeState

    state = BadgeState()
    state.create_badge(12345, source="claude-code", state="stopped")
    state.create_badge(67890, source="build", state="working")

    eww_data = state.to_eww_format()

    assert "12345" in eww_data
    assert eww_data["12345"]["state"] == "stopped"
    assert eww_data["12345"]["source"] == "claude-code"

    assert "67890" in eww_data
    assert eww_data["67890"]["state"] == "working"

    print("✓ Eww format conversion works correctly")


def main():
    """Run all tests."""
    print("\n=== Feature 117 Badge Service Tests ===\n")

    try:
        test_badge_model()
        test_badge_state()
        test_badge_file_operations()
        test_constants()
        test_eww_format()

        print("\n=== All tests passed! ===\n")
        return 0
    except Exception as e:
        print(f"\n✗ Test failed: {e}\n")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
