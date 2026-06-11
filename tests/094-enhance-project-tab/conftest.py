"""Quarantine retired project-tab/Eww-era tests.

The active desktop surface is QuickShell plus daemon/i3pm health checks. These
tests target an older project-tab workflow with stale PWA/worktree validation
expectations, so they are intentionally skipped instead of maintained as a
blocking suite.
"""

import pytest


def pytest_collection_modifyitems(items):
    skip_retired = pytest.mark.skip(
        reason=(
            "retired project-tab/Eww-era suite; validate active desktop state "
            "with QuickShell, i3pm health, and focused daemon tests"
        )
    )
    for item in items:
        item.add_marker(skip_retired)
