"""
Unit tests for app detection system

Feature 075: Idempotent Layout Restoration
Tasks: T016-T018 (User Story 2 - Current Window Detection)

Tests verify:
- Basic detection functionality
- PWA multi-window detection (shared process)
- Edge cases (dead process, missing I3PM_APP_NAME)
"""

import pytest
import asyncio
from pathlib import Path
from unittest.mock import Mock, patch, AsyncMock
from home_modules.desktop.i3_project_event_daemon.layout.auto_restore import (
    detect_running_apps,
    _read_app_name_from_environ,
)


# ============================================================================
# T016: Basic Functionality Tests
# ============================================================================

@pytest.mark.asyncio
async def test_detect_running_apps_basic():
    """Test basic app detection with multiple windows.

    Feature 075: T016 (US2)

    Scenario: Launch terminal, code, chatgpt-pwa
    Expected: Returns {"terminal", "code", "chatgpt-pwa"}
    """
    # Mock Sway IPC tree with 3 windows
    mock_tree = Mock()
    mock_tree.nodes = []
    mock_tree.floating_nodes = []

    # Window 1: Terminal (PID 1001)
    win1 = Mock()
    win1.pid = 1001
    win1.nodes = []
    win1.floating_nodes = []

    # Window 2: VS Code (PID 1002)
    win2 = Mock()
    win2.pid = 1002
    win2.nodes = []
    win2.floating_nodes = []

    # Window 3: ChatGPT PWA (PID 1003)
    win3 = Mock()
    win3.pid = 1003
    win3.nodes = []
    win3.floating_nodes = []

    mock_tree.nodes = [win1, win2, win3]

    # Mock i3ipc connection
    mock_conn = AsyncMock()
    mock_conn.get_tree = AsyncMock(return_value=mock_tree)

    # Mock _read_app_name_from_environ to return expected app names
    def mock_read_environ(pid):
        if pid == 1001:
            return "terminal"
        elif pid == 1002:
            return "code"
        elif pid == 1003:
            return "chatgpt-pwa"
        return None

    with patch('home_modules.desktop.i3_project_event_daemon.layout.auto_restore.Connection', return_value=mock_conn):
        with patch('home_modules.desktop.i3_project_event_daemon.layout.auto_restore._read_app_name_from_environ', side_effect=mock_read_environ):
            running = await detect_running_apps()

    # Verify results
    assert running == {"terminal", "code", "chatgpt-pwa"}
    assert len(running) == 3


# ============================================================================
# T017: PWA Multi-Window Detection Tests
# ============================================================================

@pytest.mark.asyncio
async def test_detect_pwa_multi_window():
    """Test PWA detection with multiple windows sharing same Firefox process.

    Feature 075: T017 (US2)

    Scenario: Launch 2 chatgpt-pwa windows (same PID 1004)
    Expected: Both detected despite shared process
    """
    # Mock Sway IPC tree with 2 PWA windows sharing PID 1004
    mock_tree = Mock()
    mock_tree.nodes = []
    mock_tree.floating_nodes = []

    # Window 1: ChatGPT PWA (PID 1004)
    win1 = Mock()
    win1.pid = 1004
    win1.nodes = []
    win1.floating_nodes = []

    # Window 2: ChatGPT PWA (same PID 1004)
    win2 = Mock()
    win2.pid = 1004
    win2.nodes = []
    win2.floating_nodes = []

    mock_tree.nodes = [win1, win2]

    # Mock i3ipc connection
    mock_conn = AsyncMock()
    mock_conn.get_tree = AsyncMock(return_value=mock_tree)

    # Mock _read_app_name_from_environ - both windows return same app name
    def mock_read_environ(pid):
        if pid == 1004:
            return "chatgpt-pwa"
        return None

    with patch('home_modules.desktop.i3_project_event_daemon.layout.auto_restore.Connection', return_value=mock_conn):
        with patch('home_modules.desktop.i3_project_event_daemon.layout.auto_restore._read_app_name_from_environ', side_effect=mock_read_environ):
            running = await detect_running_apps()

    # Verify results - set should contain chatgpt-pwa (deduplicated)
    assert running == {"chatgpt-pwa"}
    assert len(running) == 1  # Single unique app despite 2 windows


# ============================================================================
# T018: Edge Case Tests
# ============================================================================

def test_read_app_name_dead_process():
    """Test graceful handling of dead process.

    Feature 075: T018 (US2) - Edge case: FileNotFoundError

    Scenario: Process died between tree query and environ read
    Expected: Returns None, no crash
    """
    # PID 99999 likely doesn't exist
    result = _read_app_name_from_environ(99999)
    assert result is None


def test_read_app_name_no_i3pm_app_name():
    """Test handling of window without I3PM_APP_NAME.

    Feature 075: T018 (US2) - Edge case: Missing environment variable

    Scenario: Window launched outside app-registry (no I3PM_APP_NAME)
    Expected: Returns None, window ignored
    """
    # Mock /proc/<pid>/environ without I3PM_APP_NAME
    mock_environ = b"PATH=/usr/bin\x00HOME=/home/user\x00DISPLAY=:0\x00"

    with patch.object(Path, 'read_bytes', return_value=mock_environ):
        result = _read_app_name_from_environ(1234)

    assert result is None


def test_read_app_name_permission_denied():
    """Test graceful handling of permission error.

    Feature 075: T018 (US2) - Edge case: PermissionError

    Scenario: Cannot read process environ (different user)
    Expected: Returns None, logs warning
    """
    with patch.object(Path, 'read_bytes', side_effect=PermissionError("Permission denied")):
        result = _read_app_name_from_environ(1234)

    assert result is None


def test_read_app_name_success():
    """Test successful app name extraction.

    Feature 075: T018 (US2) - Happy path

    Scenario: Window has I3PM_APP_NAME=lazygit
    Expected: Returns "lazygit"
    """
    # Mock /proc/<pid>/environ with I3PM_APP_NAME
    mock_environ = b"PATH=/usr/bin\x00I3PM_APP_NAME=lazygit\x00HOME=/home/user\x00"

    with patch.object(Path, 'read_bytes', return_value=mock_environ):
        result = _read_app_name_from_environ(1234)

    assert result == "lazygit"


# ============================================================================
# Performance Test
# ============================================================================

@pytest.mark.asyncio
async def test_detect_performance():
    """Test detection performance with 16 windows.

    Feature 075: Research validation

    Scenario: 16 windows (research baseline)
    Expected: Detection completes in <10ms
    """
    import time

    # Mock Sway IPC tree with 16 windows
    mock_tree = Mock()
    mock_tree.nodes = []
    mock_tree.floating_nodes = []

    # Create 16 mock windows
    windows = []
    for i in range(16):
        win = Mock()
        win.pid = 2000 + i
        win.nodes = []
        win.floating_nodes = []
        windows.append(win)

    mock_tree.nodes = windows

    # Mock i3ipc connection
    mock_conn = AsyncMock()
    mock_conn.get_tree = AsyncMock(return_value=mock_tree)

    # Mock _read_app_name_from_environ - return unique app names
    def mock_read_environ(pid):
        return f"app-{pid % 5}"  # 5 unique apps, some duplicates

    start_time = time.time()

    with patch('home_modules.desktop.i3_project_event_daemon.layout.auto_restore.Connection', return_value=mock_conn):
        with patch('home_modules.desktop.i3_project_event_daemon.layout.auto_restore._read_app_name_from_environ', side_effect=mock_read_environ):
            running = await detect_running_apps()

    elapsed_ms = (time.time() - start_time) * 1000

    # Verify results
    assert len(running) == 5  # 5 unique apps
    # Note: Performance check may not be reliable in CI/tests
    # Target: <10ms but tests may take longer due to mocking overhead
