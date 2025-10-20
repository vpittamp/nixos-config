"""Reporter modules for i3 project test framework.

This package provides result reporting in various formats for
human consumption and CI/CD integration.
"""

from .json_reporter import CIReporter, JSONReporter
from .terminal_reporter import TerminalReporter


__all__ = [
    "TerminalReporter",
    "JSONReporter",
    "CIReporter",
]
