#!/usr/bin/env bash
# Integration test runner with proper process management
# Feature 106: Portable paths via FLAKE_ROOT
#
# Usage:
#   ./run_integration_tests.sh [test_file]
#
# Features:
# - Runs in background with nohup (survives terminal disconnect)
# - Comprehensive logging to file
# - Automatic cleanup of Xvfb/i3 processes
# - Returns detailed test results

set -euo pipefail

# Feature 106: FLAKE_ROOT discovery for portable paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="${FLAKE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "/etc/nixos")}"

# Configuration
DISPLAY_NUM=99
LOG_DIR="/tmp/i3pm_integration_tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/test_run_${TIMESTAMP}.log"
PID_FILE="${LOG_DIR}/test_runner.pid"

# Create log directory
mkdir -p "$LOG_DIR"

# Cleanup function
cleanup() {
    echo "=== Cleanup started at $(date) ===" | tee -a "$LOG_FILE"

    # Kill any processes on our display
    echo "Killing processes on display :${DISPLAY_NUM}..." | tee -a "$LOG_FILE"

    # Kill i3 instances
    pkill -f "i3.*DISPLAY=:${DISPLAY_NUM}" || true

    # Kill Xvfb instances
    pkill -f "Xvfb :${DISPLAY_NUM}" || true

    # Kill any xterm instances
    pkill -f "xterm.*DISPLAY=:${DISPLAY_NUM}" || true

    # Remove PID file
    rm -f "$PID_FILE"

    echo "Cleanup complete at $(date)" | tee -a "$LOG_FILE"
}

# Register cleanup on exit
trap cleanup EXIT INT TERM

# Check if another test runner is running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "ERROR: Another test runner is already running (PID: $OLD_PID)" | tee -a "$LOG_FILE"
        echo "To force cleanup: kill $OLD_PID && rm $PID_FILE" | tee -a "$LOG_FILE"
        exit 1
    else
        echo "Removing stale PID file" | tee -a "$LOG_FILE"
        rm -f "$PID_FILE"
    fi
fi

# Save our PID
echo $$ > "$PID_FILE"

# Ensure clean state before starting
cleanup

echo "==================================================================" | tee -a "$LOG_FILE"
echo "i3pm Integration Test Runner" | tee -a "$LOG_FILE"
echo "Started at: $(date)" | tee -a "$LOG_FILE"
echo "Display: :${DISPLAY_NUM}" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "==================================================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check required tools
echo "Checking required tools..." | tee -a "$LOG_FILE"
MISSING_TOOLS=()

for tool in Xvfb i3 xdotool xterm pytest; do
    if ! command -v "$tool" &> /dev/null; then
        MISSING_TOOLS+=("$tool")
        echo "  ✗ $tool: NOT FOUND" | tee -a "$LOG_FILE"
    else
        TOOL_PATH=$(which "$tool")
        echo "  ✓ $tool: $TOOL_PATH" | tee -a "$LOG_FILE"
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "ERROR: Missing required tools: ${MISSING_TOOLS[*]}" | tee -a "$LOG_FILE"
    echo "Please install missing tools and try again." | tee -a "$LOG_FILE"
    exit 1
fi

echo "" | tee -a "$LOG_FILE"

# Determine test file
TEST_FILE="${1:-tests/i3pm/integration/test_real_apps.py}"

if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: Test file not found: $TEST_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Running tests from: $TEST_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run tests with proper environment
echo "==================================================================" | tee -a "$LOG_FILE"
echo "Starting pytest..." | tee -a "$LOG_FILE"
echo "==================================================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Export display for tests
export DISPLAY=":${DISPLAY_NUM}"

# Run pytest with:
# - Integration test markers
# - Verbose output
# - Capture output
# - Timeout for safety
# - Append to log file
cd "$FLAKE_ROOT"  # Feature 106: Portable path

nix-shell -p \
    python3Packages.pytest \
    python3Packages.pytest-asyncio \
    python3Packages.pytest-timeout \
    python3Packages.textual \
    python3Packages.psutil \
    xorg.xorgserver \
    i3 \
    xdotool \
    xterm \
    --run "python -m pytest $TEST_FILE -v -s -m integration --timeout=60 --tb=short" 2>&1 | tee -a "$LOG_FILE"

TEST_EXIT_CODE=${PIPESTATUS[0]}

echo "" | tee -a "$LOG_FILE"
echo "==================================================================" | tee -a "$LOG_FILE"
echo "Test run completed at: $(date)" | tee -a "$LOG_FILE"
echo "Exit code: $TEST_EXIT_CODE" | tee -a "$LOG_FILE"
echo "==================================================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Print summary
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✅ ALL TESTS PASSED" | tee -a "$LOG_FILE"
else
    echo "❌ TESTS FAILED (exit code: $TEST_EXIT_CODE)" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Full log available at: $LOG_FILE" | tee -a "$LOG_FILE"

# List recent log files
echo "" | tee -a "$LOG_FILE"
echo "Recent test runs:" | tee -a "$LOG_FILE"
ls -lth "$LOG_DIR"/test_run_*.log 2>/dev/null | head -5 | tee -a "$LOG_FILE"

exit $TEST_EXIT_CODE
