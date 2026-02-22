"""Compatibility namespace for desktop modules."""

from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_REAL_DESKTOP_DIR = _REPO_ROOT / "home-modules" / "desktop"

__path__ = [str(_REAL_DESKTOP_DIR)]

