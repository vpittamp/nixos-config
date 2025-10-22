#!/usr/bin/env bash
# Run integration tests in background (survives terminal disconnect)
#
# Usage:
#   ./run_background.sh [test_file]
#
# This script:
# - Runs tests using nohup (survives SSH disconnect)
# - Logs to file that can be tailed
# - Returns immediately, tests run in background
# - Provides commands to monitor progress

set -euo pipefail

LOG_DIR="/tmp/i3pm_integration_tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/background_${TIMESTAMP}.log"
PID_FILE="${LOG_DIR}/background.pid"

mkdir -p "$LOG_DIR"

# Get test file
TEST_FILE="${1:-tests/i3pm/integration/test_real_apps.py}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "Starting integration tests in background"
echo "========================================="
echo ""
echo "Test file: $TEST_FILE"
echo "Log file:  $LOG_FILE"
echo ""

# Check if already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "⚠️  Tests already running (PID: $OLD_PID)"
        echo ""
        echo "To monitor progress:"
        echo "  tail -f $LOG_FILE"
        echo ""
        echo "To stop:"
        echo "  kill $OLD_PID"
        echo ""
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

# Run in background with nohup
nohup "$SCRIPT_DIR/run_integration_tests.sh" "$TEST_FILE" > "$LOG_FILE" 2>&1 &
BG_PID=$!

# Save PID
echo $BG_PID > "$PID_FILE"

echo "✅ Tests started in background (PID: $BG_PID)"
echo ""
echo "Monitor progress:"
echo "  tail -f $LOG_FILE"
echo ""
echo "Check status:"
echo "  ps -p $BG_PID"
echo ""
echo "Stop tests:"
echo "  kill $BG_PID"
echo ""
echo "View results when complete:"
echo "  cat $LOG_FILE"
echo ""

# Wait a moment to see if it starts successfully
sleep 2

if ps -p $BG_PID > /dev/null; then
    echo "✅ Tests running successfully"
    echo ""
    echo "Showing first few lines of output:"
    echo "-----------------------------------"
    head -20 "$LOG_FILE" 2>/dev/null || echo "(log not yet available)"
else
    echo "❌ Tests failed to start"
    echo ""
    cat "$LOG_FILE" 2>/dev/null || echo "(no log available)"
    rm -f "$PID_FILE"
    exit 1
fi
