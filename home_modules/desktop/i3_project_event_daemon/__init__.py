"""Compatibility package for `i3-project-event-daemon` sources."""

from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[3]
_REAL_DAEMON_DIR = _REPO_ROOT / "home-modules" / "desktop" / "i3-project-event-daemon"

__path__ = [str(_REAL_DAEMON_DIR)]

