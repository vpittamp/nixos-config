"""Testing framework for i3pm TUI.

Provides automated testing capabilities using Textual Pilot API
and full integration testing with real applications.
"""

# Lazy imports to avoid dependency issues
__all__ = ["TestFramework", "IntegrationTestFramework"]


def __getattr__(name):
    """Lazy import to handle optional dependencies."""
    if name == "TestFramework":
        from .framework import TestFramework
        return TestFramework
    elif name == "IntegrationTestFramework":
        from .integration import IntegrationTestFramework
        return IntegrationTestFramework
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
