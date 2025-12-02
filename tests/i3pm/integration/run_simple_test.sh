#!/usr/bin/env bash
# Simple integration test runner for systemd
# Minimal dependencies, reliable execution
# Feature 106: Portable paths via FLAKE_ROOT

set -euo pipefail

# Feature 106: FLAKE_ROOT discovery for portable paths
FLAKE_ROOT="${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "/etc/nixos")}"

DISPLAY_NUM=99
export DISPLAY=":${DISPLAY_NUM}"

echo "========================================="
echo "i3pm Integration Test Runner"
echo "Started: $(date)"
echo "Display: ${DISPLAY}"
echo "========================================="
echo ""

# Simple cleanup using full paths
cleanup_processes() {
    echo "Cleaning up test processes..."

    # Use ps and grep instead of pkill
    ps aux | grep -E "Xvfb.*:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "i3.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
    ps aux | grep -E "xterm.*DISPLAY=:${DISPLAY_NUM}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true

    echo "Cleanup complete"
}

# Cleanup on exit
trap cleanup_processes EXIT INT TERM

# Initial cleanup
cleanup_processes
sleep 1

# Run pytest
echo "Running tests..."
echo ""

cd "$FLAKE_ROOT"  # Feature 106: Portable path

python -m pytest \
    tests/i3pm/integration/test_quick_validation.py::test_integration_framework_setup_only \
    -v -s --tb=short

TEST_EXIT_CODE=$?

echo ""
echo "========================================="
echo "Test completed: $(date)"
echo "Exit code: $TEST_EXIT_CODE"
echo "========================================="

exit $TEST_EXIT_CODE
