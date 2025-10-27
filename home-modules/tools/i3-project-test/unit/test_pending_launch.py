"""Unit tests for PendingLaunch model.

Feature 041: IPC Launch Context - T016

These tests validate the PendingLaunch Pydantic model including:
- age() method calculation
- is_expired() with various timeouts
- timestamp validation (reject future timestamps)
- workspace_number validation (1-70 range)

TDD: These tests should FAIL initially before implementation.
"""

import time
from pathlib import Path

import pytest
from pydantic import ValidationError

# Import from the daemon package
import sys
from pathlib import Path

# Add daemon directory to path for imports
daemon_path = Path(__file__).parent.parent.parent.parent / "desktop" / "i3-project-event-daemon"
sys.path.insert(0, str(daemon_path))

from models import PendingLaunch


class TestPendingLaunchValidation:
    """Test PendingLaunch model field validation."""

    def test_valid_pending_launch_creation(self):
        """Test creating a valid PendingLaunch instance."""
        now = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=now,
            expected_class="Code",
        )

        assert launch.app_name == "vscode"
        assert launch.project_name == "nixos"
        assert launch.project_directory == Path("/etc/nixos").resolve()
        assert launch.launcher_pid == 12345
        assert launch.workspace_number == 2
        assert launch.timestamp == now
        assert launch.expected_class == "Code"
        assert launch.matched is False  # Default value

    def test_workspace_number_validation_minimum(self):
        """Test workspace_number must be >= 1."""
        now = time.time()

        with pytest.raises(ValidationError) as exc_info:
            PendingLaunch(
                app_name="vscode",
                project_name="nixos",
                project_directory=Path("/etc/nixos"),
                launcher_pid=12345,
                workspace_number=0,  # Invalid: below minimum
                timestamp=now,
                expected_class="Code",
            )

        # Verify the error mentions workspace_number
        assert "workspace_number" in str(exc_info.value)

    def test_workspace_number_validation_maximum(self):
        """Test workspace_number must be <= 70."""
        now = time.time()

        with pytest.raises(ValidationError) as exc_info:
            PendingLaunch(
                app_name="vscode",
                project_name="nixos",
                project_directory=Path("/etc/nixos"),
                launcher_pid=12345,
                workspace_number=71,  # Invalid: above maximum
                timestamp=now,
                expected_class="Code",
            )

        # Verify the error mentions workspace_number
        assert "workspace_number" in str(exc_info.value)

    def test_workspace_number_validation_boundaries(self):
        """Test workspace_number boundary values 1 and 70 are valid."""
        now = time.time()

        # Test minimum boundary (1)
        launch_min = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=1,
            timestamp=now,
            expected_class="Code",
        )
        assert launch_min.workspace_number == 1

        # Test maximum boundary (70)
        launch_max = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=70,
            timestamp=now,
            expected_class="Code",
        )
        assert launch_max.workspace_number == 70

    def test_launcher_pid_validation_positive(self):
        """Test launcher_pid must be > 0."""
        now = time.time()

        with pytest.raises(ValidationError) as exc_info:
            PendingLaunch(
                app_name="vscode",
                project_name="nixos",
                project_directory=Path("/etc/nixos"),
                launcher_pid=0,  # Invalid: must be positive
                workspace_number=2,
                timestamp=now,
                expected_class="Code",
            )

        # Verify the error mentions launcher_pid
        assert "launcher_pid" in str(exc_info.value)

    def test_timestamp_validation_future(self):
        """Test timestamp cannot be in the future (beyond clock skew tolerance)."""
        future_time = time.time() + 10.0  # 10 seconds in the future

        with pytest.raises(ValidationError) as exc_info:
            PendingLaunch(
                app_name="vscode",
                project_name="nixos",
                project_directory=Path("/etc/nixos"),
                launcher_pid=12345,
                workspace_number=2,
                timestamp=future_time,
                expected_class="Code",
            )

        # Verify the error mentions timestamp or future
        error_str = str(exc_info.value).lower()
        assert "timestamp" in error_str or "future" in error_str

    def test_timestamp_validation_clock_skew_tolerance(self):
        """Test timestamp allows small clock skew (1 second tolerance)."""
        # Timestamp just within tolerance (0.5 seconds in future)
        near_future = time.time() + 0.5

        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=near_future,
            expected_class="Code",
        )

        # Should succeed - within 1 second tolerance
        assert launch.timestamp == near_future

    def test_required_fields_validation(self):
        """Test all required fields must be provided."""
        with pytest.raises(ValidationError) as exc_info:
            PendingLaunch()  # type: ignore

        error_str = str(exc_info.value)
        # Should mention multiple missing required fields
        assert "app_name" in error_str
        assert "project_name" in error_str
        assert "project_directory" in error_str


class TestPendingLaunchMethods:
    """Test PendingLaunch instance methods."""

    def test_age_calculation(self):
        """Test age() method calculates time since launch correctly."""
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Age should be very small immediately after creation
        age_immediate = launch.age(launch_time)
        assert age_immediate == 0.0

        # Age after 2.5 seconds
        age_after = launch.age(launch_time + 2.5)
        assert age_after == 2.5

        # Age after 5 seconds
        age_five = launch.age(launch_time + 5.0)
        assert age_five == 5.0

    def test_age_with_past_timestamp(self):
        """Test age() with a launch from the past."""
        five_seconds_ago = time.time() - 5.0
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=five_seconds_ago,
            expected_class="Code",
        )

        # Age should be approximately 5 seconds
        current_age = launch.age(time.time())
        assert 4.9 <= current_age <= 5.1  # Allow small timing variance

    def test_is_expired_default_timeout(self):
        """Test is_expired() with default 5-second timeout."""
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Not expired immediately
        assert launch.is_expired(launch_time) is False

        # Not expired at 4 seconds
        assert launch.is_expired(launch_time + 4.0) is False

        # Not expired at exactly 5 seconds (boundary)
        assert launch.is_expired(launch_time + 5.0) is False

        # Expired at 5.1 seconds (just over timeout)
        assert launch.is_expired(launch_time + 5.1) is True

        # Expired at 10 seconds
        assert launch.is_expired(launch_time + 10.0) is True

    def test_is_expired_custom_timeout(self):
        """Test is_expired() with custom timeout values."""
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Custom timeout: 2 seconds
        assert launch.is_expired(launch_time + 1.5, timeout=2.0) is False
        assert launch.is_expired(launch_time + 2.0, timeout=2.0) is False
        assert launch.is_expired(launch_time + 2.1, timeout=2.0) is True

        # Custom timeout: 10 seconds
        assert launch.is_expired(launch_time + 9.0, timeout=10.0) is False
        assert launch.is_expired(launch_time + 10.0, timeout=10.0) is False
        assert launch.is_expired(launch_time + 10.1, timeout=10.0) is True

    def test_is_expired_zero_timeout(self):
        """Test is_expired() with zero timeout (immediate expiration)."""
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        # Even with zero timeout, exact time should not be expired
        assert launch.is_expired(launch_time, timeout=0.0) is False

        # Any time after launch should be expired with zero timeout
        assert launch.is_expired(launch_time + 0.001, timeout=0.0) is True

    def test_matched_field_default_and_update(self):
        """Test matched field defaults to False and can be updated."""
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="Code",
        )

        # Default should be False
        assert launch.matched is False

        # Can be created with matched=True
        matched_launch = PendingLaunch(
            app_name="terminal",
            project_name="stacks",
            project_directory=Path("/home/user/stacks"),
            launcher_pid=54321,
            workspace_number=3,
            timestamp=time.time(),
            expected_class="Alacritty",
            matched=True,
        )
        assert matched_launch.matched is True


class TestPendingLaunchPathHandling:
    """Test PendingLaunch path normalization and validation."""

    def test_project_directory_normalization(self):
        """Test project_directory is resolved to absolute path."""
        # Relative path should be resolved
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("."),  # Current directory
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="Code",
        )

        # Should be converted to absolute path
        assert launch.project_directory.is_absolute()

    def test_project_directory_string_conversion(self):
        """Test project_directory accepts string paths."""
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory="/etc/nixos",  # String path
            launcher_pid=12345,
            workspace_number=2,
            timestamp=time.time(),
            expected_class="Code",
        )

        # Should be converted to Path object
        assert isinstance(launch.project_directory, Path)
        assert launch.project_directory == Path("/etc/nixos").resolve()


class TestPendingLaunchStringRepresentation:
    """Test PendingLaunch __str__ method."""

    def test_string_representation(self):
        """Test __str__ produces readable output with key fields."""
        launch_time = time.time()
        launch = PendingLaunch(
            app_name="vscode",
            project_name="nixos",
            project_directory=Path("/etc/nixos"),
            launcher_pid=12345,
            workspace_number=2,
            timestamp=launch_time,
            expected_class="Code",
        )

        str_repr = str(launch)

        # Should include key identifying information
        assert "vscode" in str_repr
        assert "nixos" in str_repr
        assert "workspace=2" in str_repr or "2" in str_repr
        assert "age=" in str_repr
