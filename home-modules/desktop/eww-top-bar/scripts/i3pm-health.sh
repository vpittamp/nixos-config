#!/usr/bin/env bash
# i3pm daemon health monitoring for Eww top bar widgets
#
# Checks i3pm daemon responsiveness via Unix socket with timeout measurement
# and outputs JSON with health status for defpoll consumption.
#
# Output format:
# {
#   "status": "healthy",  // "healthy" (<100ms), "slow" (100-500ms), "unhealthy" (>500ms or unresponsive)
#   "response_ms": 45     // Response time in milliseconds
# }
#
# Usage:
#   bash i3pm-health.sh
#
# Exit codes:
#   0 - Success (daemon responded)
#   1 - Daemon unavailable or unhealthy

set -euo pipefail

# i3pm daemon IPC socket path
IPC_SOCKET="/run/user/$(id -u)/i3-project-daemon/ipc.sock"

# Check if socket exists
if [ ! -S "$IPC_SOCKET" ]; then
    echo '{"status":"unhealthy","response_ms":0,"error":"daemon not running"}'
    exit 1
fi

# Send ping command to daemon and measure response time
start_time=$(date +%s%3N)  # Milliseconds since epoch

# Use timeout command to limit wait time (1 second max)
response=$(echo '{"command":"ping"}' | timeout 1 nc -U "$IPC_SOCKET" 2>/dev/null || echo "")

end_time=$(date +%s%3N)
response_ms=$((end_time - start_time))

# Check if we got a response
if [ -z "$response" ]; then
    echo '{"status":"unhealthy","response_ms":0,"error":"no response"}'
    exit 1
fi

# Determine health status based on response time thresholds
if [ "$response_ms" -lt 100 ]; then
    status="healthy"
elif [ "$response_ms" -lt 500 ]; then
    status="slow"
else
    status="unhealthy"
fi

# Output JSON result
echo "{\"status\":\"$status\",\"response_ms\":$response_ms}"
exit 0
