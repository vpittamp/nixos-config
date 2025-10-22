"""Entry point for i3pm TUI when run as module."""

import sys
from i3_project_manager.tui.app import run_tui

if __name__ == "__main__":
    sys.exit(run_tui())
