#!/usr/bin/env python3
"""
Simple test runner for Sway Configuration Manager tests.

Feature 047 US5 T055: Validation error test suite runner

This script runs the validation tests without requiring package installation,
which is useful in NixOS read-only environments.
"""

import sys
from pathlib import Path

# Add the package directory to Python path
package_dir = Path(__file__).parent
sys.path.insert(0, str(package_dir))

# Now run pytest
if __name__ == "__main__":
    import pytest

    # Pass through command line arguments
    args = sys.argv[1:] if len(sys.argv) > 1 else ["tests/", "-v"]

    sys.exit(pytest.main(args))
