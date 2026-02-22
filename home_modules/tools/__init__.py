"""Compatibility namespace for tools modules."""

from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_REAL_TOOLS_DIR = _REPO_ROOT / "home-modules" / "tools"

__path__ = [str(_REAL_TOOLS_DIR)]

