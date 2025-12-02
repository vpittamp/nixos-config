#!/usr/bin/env bash
# Standalone quick validation test with all dependencies
# Can be run directly without any setup
# Feature 106: Portable paths via FLAKE_ROOT

set -euo pipefail

# Feature 106: FLAKE_ROOT discovery for portable paths
FLAKE_ROOT="${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "/etc/nixos")}"

DISPLAY_NUM=99
export DISPLAY=":${DISPLAY_NUM}"

echo "========================================="
echo "i3pm Quick Validation Test (Standalone)"
echo "Started: $(date)"
echo "Display: ${DISPLAY}"
echo "========================================="
echo ""

# Cleanup function
cleanup_processes() {
    echo "Cleaning up test processes..."
    ps aux | grep -E "Xvfb.*:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "i3.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "xterm.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    echo "Cleanup complete"
}

trap cleanup_processes EXIT INT TERM
cleanup_processes
sleep 1

echo "Loading nix-shell with all dependencies..."
echo ""

cd "$FLAKE_ROOT"  # Feature 106: Portable path

# Run test in nix-shell with all required dependencies
nix-shell \
    -p python3Packages.pytest \
       python3Packages.pytest-asyncio \
       python3Packages.textual \
       python3Packages.psutil \
       xorg.xorgserver \
       i3 \
       xdotool \
       xterm \
    --run "python -m pytest tests/i3pm/integration/test_quick_validation.py::test_integration_framework_setup_only -v -s --tb=short"

TEST_EXIT_CODE=$?

echo ""
echo "========================================="
echo "Test completed: $(date)"
echo "Exit code: $TEST_EXIT_CODE"
echo "========================================="

exit $TEST_EXIT_CODE
