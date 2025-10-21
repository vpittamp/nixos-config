"""Pytest configuration for i3 project manager tests."""

import sys
from pathlib import Path

# Add i3_project_manager package to Python path BEFORE test collection
package_root = Path(__file__).parent.parent / "home-modules" / "tools"
if str(package_root) not in sys.path:
    sys.path.insert(0, str(package_root))


def pytest_configure(config):
    """Configure pytest before test collection."""
    # Ensure path is set even earlier
    if str(package_root) not in sys.path:
        sys.path.insert(0, str(package_root))
