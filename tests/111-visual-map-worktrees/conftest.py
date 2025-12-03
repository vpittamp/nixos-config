# Feature 111: Test configuration
"""pytest configuration for Feature 111 tests."""

import sys
from pathlib import Path

# Add home-modules/tools to Python path for imports
tools_path = Path(__file__).parent.parent.parent / "home-modules" / "tools"
if str(tools_path) not in sys.path:
    sys.path.insert(0, str(tools_path))
