#!/usr/bin/env bash
# Comprehensive integration test runner for systemd
# Runs full user workflow tests

set -euo pipefail

DISPLAY_NUM=99
export DISPLAY=":${DISPLAY_NUM}"

echo "========================================="
echo "i3pm Comprehensive Integration Tests"
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

# Run comprehensive user workflow tests
echo "Running comprehensive user workflow tests..."
echo "This will test:"
echo "  - Project creation via CLI"
echo "  - Project switching"
echo "  - Opening applications in project context"
echo "  - Saving and restoring layouts"
echo "  - Multi-project workflows"
echo "  - Full user session simulation"
echo ""

cd /etc/nixos

# Run all workflow tests with nix-shell to ensure dependencies
nix-shell \
    -p python3Packages.pytest \
       python3Packages.pytest-asyncio \
       python3Packages.textual \
       python3Packages.psutil \
       xorg.xorgserver \
       i3 \
       xdotool \
       xterm \
    --run "python -m pytest tests/i3pm/integration/test_user_workflows.py -v -s --tb=short -m integration"

TEST_EXIT_CODE=$?

echo ""
echo "========================================="
echo "Test completed: $(date)"
echo "Exit code: $TEST_EXIT_CODE"
echo "========================================="

exit $TEST_EXIT_CODE
