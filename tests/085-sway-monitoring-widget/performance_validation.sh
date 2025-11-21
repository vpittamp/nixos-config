#!/usr/bin/env bash
# Performance Validation for Feature 085: Sway Monitoring Widget
# Measures toggle latency, update latency, and memory usage
# Targets: Toggle <200ms, Update <100ms, Memory <50MB for 30 windows

set -euo pipefail

RESULTS_FILE="/tmp/085-performance-results.json"
PASS_COUNT=0
FAIL_COUNT=0

echo "=== Feature 085 Performance Validation ==="
echo

# Utility: Measure execution time in milliseconds
measure_time() {
    local start=$(date +%s%3N)
    "$@" > /dev/null 2>&1
    local end=$(date +%s%3N)
    echo $((end - start))
}

# Utility: Record result
record_result() {
    local test_name="$1"
    local measured="$2"
    local target="$3"
    local unit="$4"
    local passed="$5"

    if [ "$passed" = "true" ]; then
        echo "✅ PASS: $test_name - ${measured}${unit} (target: <${target}${unit})"
        ((PASS_COUNT++))
    else
        echo "❌ FAIL: $test_name - ${measured}${unit} (target: <${target}${unit})"
        ((FAIL_COUNT++))
    fi
}

# Test 1: Panel Toggle Latency
echo "Test 1: Panel Toggle Latency (Target: <200ms)"
echo "---------------------------------------------"

# Ensure panel is closed
eww --config "$HOME/.config/eww-monitoring-panel" close-all > /dev/null 2>&1 || true
sleep 0.5

# Measure open latency
OPEN_LATENCY=$(measure_time eww --config "$HOME/.config/eww-monitoring-panel" open monitoring-panel)
echo "  Open latency: ${OPEN_LATENCY}ms"

# Measure close latency
CLOSE_LATENCY=$(measure_time eww --config "$HOME/.config/eww-monitoring-panel" close monitoring-panel)
echo "  Close latency: ${CLOSE_LATENCY}ms"

# Average toggle latency
AVG_TOGGLE_LATENCY=$(( (OPEN_LATENCY + CLOSE_LATENCY) / 2 ))
echo "  Average toggle latency: ${AVG_TOGGLE_LATENCY}ms"

if [ "$AVG_TOGGLE_LATENCY" -lt 200 ]; then
    record_result "Toggle Latency" "$AVG_TOGGLE_LATENCY" "200" "ms" "true"
else
    record_result "Toggle Latency" "$AVG_TOGGLE_LATENCY" "200" "ms" "false"
fi
echo

# Test 2: Backend Data Query Latency
echo "Test 2: Backend Data Query Latency (Target: <100ms)"
echo "---------------------------------------------------"

# Ensure panel is open for data query
eww --config "$HOME/.config/eww-monitoring-panel" open monitoring-panel > /dev/null 2>&1
sleep 0.5

# Measure time to retrieve monitoring data from Eww
QUERY_LATENCY=$(measure_time eww --config "$HOME/.config/eww-monitoring-panel" get monitoring_data)
echo "  Data retrieval latency: ${QUERY_LATENCY}ms"

if [ "$QUERY_LATENCY" -lt 100 ]; then
    record_result "Data Query Latency" "$QUERY_LATENCY" "100" "ms" "true"
else
    record_result "Data Query Latency" "$QUERY_LATENCY" "100" "ms" "false"
fi
echo

# Test 3: Memory Usage
echo "Test 3: Memory Usage (Target: <50MB for Eww daemon)"
echo "---------------------------------------------------"

# Restart Eww daemon for clean measurement
systemctl --user restart eww-monitoring-panel
sleep 2

# Open panel to load data
eww --config "$HOME/.config/eww-monitoring-panel" open monitoring-panel
sleep 1

# Get Eww daemon PID
EWW_PID=$(pgrep -f "eww.*eww-monitoring-panel.*daemon" | head -1)

if [ -n "$EWW_PID" ]; then
    # Get memory usage in MB (RSS - Resident Set Size)
    MEMORY_MB=$(ps -p "$EWW_PID" -o rss= | awk '{print int($1/1024)}')
    echo "  Eww daemon memory usage: ${MEMORY_MB}MB (PID: $EWW_PID)"

    if [ "$MEMORY_MB" -lt 50 ]; then
        record_result "Memory Usage" "$MEMORY_MB" "50" "MB" "true"
    else
        record_result "Memory Usage" "$MEMORY_MB" "50" "MB" "false"
    fi
else
    echo "  ⚠️  WARNING: Eww daemon PID not found, skipping"
    MEMORY_MB="N/A"
fi
echo

# Test 4: Update Frequency Validation
echo "Test 4: Defpoll Update Frequency (Target: 10s interval)"
echo "-------------------------------------------------------"

# Check defpoll configuration
DEFPOLL_INTERVAL=$(grep -A2 "defpoll monitoring_data" "$HOME/.config/eww-monitoring-panel/eww.yuck" | grep ":interval" | grep -oP '\d+s')
echo "  Configured interval: $DEFPOLL_INTERVAL"

if [ "$DEFPOLL_INTERVAL" = "10s" ]; then
    record_result "Defpoll Interval" "10" "10" "s" "true"
else
    record_result "Defpoll Interval" "${DEFPOLL_INTERVAL//s/}" "10" "s" "false"
fi
echo

# Test 5: Data Payload Size
echo "Test 5: JSON Data Payload Size"
echo "-------------------------------"

# Get current monitoring data
PAYLOAD_SIZE=$(eww --config "$HOME/.config/eww-monitoring-panel" get monitoring_data | wc -c)
PAYLOAD_KB=$((PAYLOAD_SIZE / 1024))
echo "  Current payload size: ${PAYLOAD_KB}KB (${PAYLOAD_SIZE} bytes)"
echo "  Window count: $(eww --config "$HOME/.config/eww-monitoring-panel" get monitoring_data | jq -r '.window_count')"
echo

# Summary
echo "=== Performance Validation Summary ==="
echo "Total tests: $((PASS_COUNT + FAIL_COUNT))"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo

# Save results to JSON
cat > "$RESULTS_FILE" <<EOF
{
  "feature": "085-sway-monitoring-widget",
  "timestamp": "$(date -Iseconds)",
  "results": {
    "toggle_latency_ms": $AVG_TOGGLE_LATENCY,
    "backend_query_latency_ms": "$QUERY_LATENCY",
    "memory_usage_mb": "$MEMORY_MB",
    "defpoll_interval": "$DEFPOLL_INTERVAL",
    "payload_size_bytes": $PAYLOAD_SIZE
  },
  "tests_passed": $PASS_COUNT,
  "tests_failed": $FAIL_COUNT,
  "overall_result": "$([ $FAIL_COUNT -eq 0 ] && echo PASS || echo FAIL)"
}
EOF

echo "Results saved to: $RESULTS_FILE"

# Cleanup
eww --config "$HOME/.config/eww-monitoring-panel" close-all

# Exit with appropriate code
if [ $FAIL_COUNT -eq 0 ]; then
    echo
    echo "✅ All performance targets met!"
    exit 0
else
    echo
    echo "❌ Some performance targets not met. See failures above."
    exit 1
fi
