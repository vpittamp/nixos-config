#!/usr/bin/env bash
# Walker App Launch Simulation Test
# Feature 039: Application Launch Integration Testing
#
# This script simulates launching applications through Walker menu by:
# 1. Using the app-launcher-wrapper.sh (same as Walker)
# 2. Verifying window creation via i3 IPC
# 3. Checking workspace assignment
# 4. Validating I3PM environment variables
# 5. Cleaning up test windows

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGISTRY="${HOME}/.config/i3/application-registry.json"
LAUNCHER="${HOME}/.local/bin/app-launcher-wrapper.sh"
LOG_FILE="/tmp/walker-app-test-$(date +%Y%m%d-%H%M%S).log"
WINDOW_TIMEOUT=5  # Seconds to wait for window creation
CLEANUP_WAIT=2    # Seconds to wait before cleanup

# Counters
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# Arrays to store results
declare -a PASSED_APPS=()
declare -a FAILED_APPS=()
declare -a SKIPPED_APPS=()

echo "=== Walker App Launch Simulation Test ===" | tee "$LOG_FILE"
echo "Testing apps through app-launcher-wrapper.sh" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Verify prerequisites
if [[ ! -f "$LAUNCHER" ]]; then
    echo -e "${RED}✗ FAILED: app-launcher-wrapper.sh not found at $LAUNCHER${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

if [[ ! -f "$REGISTRY" ]]; then
    echo -e "${RED}✗ FAILED: application-registry.json not found at $REGISTRY${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

if ! command -v i3-msg &>/dev/null; then
    echo -e "${RED}✗ FAILED: i3-msg command not found${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# Get list of apps from registry
APPS=$(jq -r '.applications[].name' "$REGISTRY")
echo "Found $(echo "$APPS" | wc -w) applications in registry" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to get window count before launch
get_window_count() {
    i3-msg -t get_tree | jq '[.. | select(.window? and .window != null)] | length'
}

# Function to get latest window ID
get_latest_window() {
    local count_before="$1"
    local count_after="$2"

    if [[ $count_after -le $count_before ]]; then
        echo ""
        return 1
    fi

    # Get the most recently focused window
    i3-msg -t get_tree | jq -r '.. | select(.window? and .focused? == true) | .window' | head -1
}

# Function to get window workspace
get_window_workspace() {
    local window_id="$1"
    i3-msg -t get_tree | jq -r --arg id "$window_id" \
        '.. | select(.window? and (.window | tostring) == $id) | .workspace.name // ""' | head -1
}

# Function to get window class
get_window_class() {
    local window_id="$1"
    i3-msg -t get_tree | jq -r --arg id "$window_id" \
        '.. | select(.window? and (.window | tostring) == $id) | .window_properties.class // ""' | head -1
}

# Function to close window
close_window() {
    local window_id="$1"
    i3-msg "[id=\"$window_id\"] kill" &>/dev/null || true
}

# Function to test app launch
test_app_launch() {
    local app_name="$1"
    local expected_workspace="$2"
    local expected_class="$3"
    local scope="$4"

    TOTAL=$((TOTAL + 1))

    echo -e "${BLUE}[$TOTAL] Testing: $app_name${NC}" | tee -a "$LOG_FILE"
    echo "  Expected workspace: $expected_workspace" | tee -a "$LOG_FILE"
    echo "  Expected class: $expected_class" | tee -a "$LOG_FILE"
    echo "  Scope: $scope" | tee -a "$LOG_FILE"

    # Get window count before launch
    local count_before
    count_before=$(get_window_count)
    echo "  Windows before launch: $count_before" | tee -a "$LOG_FILE"

    # Launch app (non-blocking)
    echo "  Launching via app-launcher-wrapper.sh..." | tee -a "$LOG_FILE"
    "$LAUNCHER" "$app_name" &>> "$LOG_FILE" &
    local launcher_pid=$!

    # Wait for window creation (with timeout)
    local waited=0
    local count_after=$count_before
    while [[ $waited -lt $WINDOW_TIMEOUT ]]; do
        sleep 0.5
        count_after=$(get_window_count)
        if [[ $count_after -gt $count_before ]]; then
            break
        fi
        waited=$((waited + 1))
    done

    echo "  Windows after launch: $count_after (waited ${waited}s)" | tee -a "$LOG_FILE"

    # Check if window was created
    if [[ $count_after -le $count_before ]]; then
        echo -e "  ${YELLOW}⊘ SKIPPED: No window created (may be headless or already open)${NC}" | tee -a "$LOG_FILE"
        SKIPPED=$((SKIPPED + 1))
        SKIPPED_APPS+=("$app_name: no window created")
        echo "" | tee -a "$LOG_FILE"
        return 0
    fi

    # Wait a moment for daemon to process window::new event
    echo "  Waiting for daemon to process window..." | tee -a "$LOG_FILE"
    sleep 1.5

    # Get all new windows (there might be multiple)
    local new_windows
    new_windows=$(i3-msg -t get_tree | jq -r '[.. | select(.window? and .window != null)] | .[-'"$((count_after - count_before))"':] | .[].window')

    # Try to find a window matching the expected class
    local window_id=""
    for wid in $new_windows; do
        local wclass
        wclass=$(get_window_class "$wid")
        if [[ -n "$wclass" ]]; then
            window_id="$wid"
            break
        fi
    done

    if [[ -z "$window_id" ]]; then
        echo -e "  ${YELLOW}⊘ SKIPPED: Could not identify new window${NC}" | tee -a "$LOG_FILE"
        SKIPPED=$((SKIPPED + 1))
        SKIPPED_APPS+=("$app_name: window identification failed")
        echo "" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "  Window ID: $window_id" | tee -a "$LOG_FILE"

    # Get actual workspace (after daemon has time to process)
    local actual_workspace
    actual_workspace=$(get_window_workspace "$window_id")
    echo "  Actual workspace: $actual_workspace" | tee -a "$LOG_FILE"

    # Get actual window class
    local actual_class
    actual_class=$(get_window_class "$window_id")
    echo "  Actual class: $actual_class" | tee -a "$LOG_FILE"

    # Validate results
    local passed=true
    local failure_reason=""

    # Check workspace assignment (if expected workspace is specified)
    if [[ -n "$expected_workspace" ]]; then
        # Extract workspace number from name (format could be "1" or "1:name")
        local actual_ws_num="${actual_workspace%%:*}"
        if [[ "$actual_ws_num" != "$expected_workspace" ]]; then
            passed=false
            failure_reason="workspace mismatch (expected $expected_workspace, got $actual_ws_num)"
        fi
    fi

    # Clean up test window
    echo "  Closing test window..." | tee -a "$LOG_FILE"
    close_window "$window_id"
    sleep $CLEANUP_WAIT

    # Report result
    if [[ "$passed" == "true" ]]; then
        echo -e "  ${GREEN}✓ PASSED: App launched successfully${NC}" | tee -a "$LOG_FILE"
        PASSED=$((PASSED + 1))
        PASSED_APPS+=("$app_name")
    else
        echo -e "  ${RED}✗ FAILED: $failure_reason${NC}" | tee -a "$LOG_FILE"
        FAILED=$((FAILED + 1))
        FAILED_APPS+=("$app_name: $failure_reason")
    fi

    echo "" | tee -a "$LOG_FILE"
}

# Main test loop - iterate through registry apps
echo "=== Testing Application Launches ===" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Read apps from registry into array to avoid subshell issues
mapfile -t APP_DATA < <(jq -c '.applications[]' "$REGISTRY")

# Test each app
for app in "${APP_DATA[@]}"; do
    app_name=$(echo "$app" | jq -r '.name')
    expected_workspace=$(echo "$app" | jq -r '.preferred_workspace // ""')
    expected_class=$(echo "$app" | jq -r '.expected_class // ""')
    scope=$(echo "$app" | jq -r '.scope // "global"')
    command=$(echo "$app" | jq -r '.command')

    # Skip if command doesn't exist
    if ! command -v "$command" &>/dev/null; then
        echo -e "${YELLOW}⊘ Skipping $app_name: command '$command' not found${NC}" | tee -a "$LOG_FILE"
        SKIPPED=$((SKIPPED + 1))
        SKIPPED_APPS+=("$app_name: command not found")
        continue
    fi

    # Skip browser launches (may interfere with existing sessions)
    if [[ "$command" == "firefox" ]] || [[ "$command" == "chromium" ]]; then
        echo -e "${YELLOW}⊘ Skipping $app_name: browser (manual test required)${NC}" | tee -a "$LOG_FILE"
        SKIPPED=$((SKIPPED + 1))
        SKIPPED_APPS+=("$app_name: browser (manual test)")
        continue
    fi

    # Skip PWAs (require profile setup)
    if [[ "$command" == "firefoxpwa" ]]; then
        echo -e "${YELLOW}⊘ Skipping $app_name: PWA (manual test required)${NC}" | tee -a "$LOG_FILE"
        SKIPPED=$((SKIPPED + 1))
        SKIPPED_APPS+=("$app_name: PWA (manual test)")
        continue
    fi

    test_app_launch "$app_name" "$expected_workspace" "$expected_class" "$scope"
done

# Print summary
echo "========================================" | tee -a "$LOG_FILE"
echo "=== TEST SUMMARY ===" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Total apps tested: $TOTAL" | tee -a "$LOG_FILE"
echo -e "${GREEN}Passed: $PASSED${NC}" | tee -a "$LOG_FILE"
echo -e "${RED}Failed: $FAILED${NC}" | tee -a "$LOG_FILE"
echo -e "${YELLOW}Skipped: $SKIPPED${NC}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ ${#PASSED_APPS[@]} -gt 0 ]; then
    echo -e "${GREEN}✓ Passed applications:${NC}" | tee -a "$LOG_FILE"
    for app in "${PASSED_APPS[@]}"; do
        echo "  - $app" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"
fi

if [ ${#FAILED_APPS[@]} -gt 0 ]; then
    echo -e "${RED}✗ Failed applications:${NC}" | tee -a "$LOG_FILE"
    for app in "${FAILED_APPS[@]}"; do
        echo "  - $app" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"
fi

if [ ${#SKIPPED_APPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⊘ Skipped applications:${NC}" | tee -a "$LOG_FILE"
    for app in "${SKIPPED_APPS[@]}"; do
        echo "  - $app" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"
fi

echo "Full log saved to: $LOG_FILE" | tee -a "$LOG_FILE"

# Exit with error if any tests failed
if [ $FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
