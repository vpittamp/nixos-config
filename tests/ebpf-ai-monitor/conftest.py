"""Pytest configuration and fixtures for eBPF AI Monitor tests."""

import pytest
from pathlib import Path
from typing import Generator
import tempfile
import os


@pytest.fixture
def temp_badge_dir() -> Generator[Path, None, None]:
    """Create a temporary directory for badge files.

    Yields:
        Path to temporary badge directory.
    """
    with tempfile.TemporaryDirectory(prefix="i3pm-badges-") as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def mock_xdg_runtime_dir(tmp_path: Path) -> Generator[Path, None, None]:
    """Mock XDG_RUNTIME_DIR environment variable.

    Args:
        tmp_path: Pytest's temporary path fixture.

    Yields:
        Path to mocked XDG_RUNTIME_DIR.
    """
    old_xdg = os.environ.get("XDG_RUNTIME_DIR")
    os.environ["XDG_RUNTIME_DIR"] = str(tmp_path)
    try:
        yield tmp_path
    finally:
        if old_xdg is not None:
            os.environ["XDG_RUNTIME_DIR"] = old_xdg
        else:
            os.environ.pop("XDG_RUNTIME_DIR", None)


@pytest.fixture
def sample_process_info() -> dict:
    """Sample process information for testing.

    Returns:
        Dict with sample process data matching MonitoredProcess fields.
    """
    return {
        "pid": 12345,
        "comm": "claude",
        "window_id": 67890,
        "project_name": "nixos-config",
        "parent_chain": [12345, 12340, 12300, 1],
    }
