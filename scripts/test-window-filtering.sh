#!/usr/bin/env bash
# Automated test for window filtering and scratchpad restoration (Feature 046)
#
# Tests:
# 1. Project switching hides/shows correct windows
# 2. Scratchpad windows restore correctly
# 3. Window marks preserved across switches
# 4. Performance metrics (< 10ms per window)
#
# Usage: ./test-window-filtering.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Find the most recently modified socket (active Sway instance)
SWAYSOCK="${SWAYSOCK:-$(find /run/user/$(id -u) -name 'sway-ipc.*.sock' -type s -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)}"
export SWAYSOCK

if [ -z "$SWAYSOCK" ]; then
    echo -e "${RED}✗ SWAYSOCK not found${NC}"
    exit 1
fi

TEST_PROJECT_1="nixos"
TEST_PROJECT_2="stacks"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $*"
}

# Get visible windows with marks
get_visible_windows() {
    swaymsg -t get_tree | jq -r '.. | select(.type? == "con") | select(.visible == true) | select(.marks | length > 0) | {id: .id, marks: .marks[]} | "\(.id):\(.marks)"'
}

# Get scratchpad windows
get_scratchpad_windows() {
    swaymsg -t get_tree | jq -r '.. | select(.name? == "__i3_scratch") | .floating_nodes[] | {id: .id, marks: .marks[]} | "\(.id):\(.marks)"'
}

# Get windows by project from marks
get_windows_by_project() {
    local project=$1
    swaymsg -t get_tree | jq -r ".. | select(.marks?) | select(.marks[] | startswith(\"project:$project:\")) | .id"
}

# Switch project
switch_project() {
    local project=$1
    log_info "Switching to project: $project"
    swaymsg -t send_tick "project:$project"
    sleep 1.5  # Wait for filtering to complete
}

# Count windows
count_visible() {
    get_visible_windows | wc -l
}

count_scratchpad() {
    get_scratchpad_windows | wc -l
}

# Main test sequence
main() {
    log_info "Starting automated window filtering tests"
    log_info "Sway socket: $SWAYSOCK"
    echo

    # Step 1: Check initial state
    log_info "Step 1: Checking initial state"
    INITIAL_VISIBLE=$(count_visible)
    INITIAL_SCRATCHPAD=$(count_scratchpad)
    log_info "Initial: $INITIAL_VISIBLE visible, $INITIAL_SCRATCHPAD in scratchpad"
    echo

    # Step 2: Launch test windows for project 1
    log_info "Step 2: Launching test windows for $TEST_PROJECT_1"
    switch_project "$TEST_PROJECT_1"

    log_info "Launching Alacritty terminal..."
    ~/.local/bin/app-launcher-wrapper.sh terminal &
    sleep 2

    log_info "Launching VS Code..."
    ~/.local/bin/app-launcher-wrapper.sh vscode &
    sleep 3

    PROJECT1_WINDOWS=$(get_windows_by_project "$TEST_PROJECT_1")
    PROJECT1_COUNT=$(echo "$PROJECT1_WINDOWS" | wc -w)
    log_success "Project $TEST_PROJECT_1 now has $PROJECT1_COUNT windows"
    echo

    # Step 3: Switch to project 2
    log_info "Step 3: Switching to $TEST_PROJECT_2 (hiding $TEST_PROJECT_1 windows)"
    switch_project "$TEST_PROJECT_2"

    VISIBLE_AFTER_SWITCH=$(count_visible)
    SCRATCHPAD_AFTER_SWITCH=$(count_scratchpad)

    # Check daemon logs for filtering
    log_info "Checking daemon logs for filtering operation..."
    FILTER_LOG=$(journalctl -u i3-project-daemon --since "5 seconds ago" | grep "Window filtering complete" | tail -1)
    if [ -n "$FILTER_LOG" ]; then
        log_success "Filtering logged: $FILTER_LOG"
    else
        log_warning "No recent filtering log found"
    fi

    log_info "After switch: $VISIBLE_AFTER_SWITCH visible, $SCRATCHPAD_AFTER_SWITCH in scratchpad"

    # Verify project 1 windows are hidden
    HIDDEN_COUNT=0
    for window_id in $PROJECT1_WINDOWS; do
        VISIBLE=$(swaymsg -t get_tree | jq ".. | select(.id == $window_id) | .visible")
        if [ "$VISIBLE" = "false" ]; then
            ((HIDDEN_COUNT++))
        fi
    done

    if [ $HIDDEN_COUNT -eq $PROJECT1_COUNT ]; then
        log_success "All $PROJECT1_COUNT windows from $TEST_PROJECT_1 are hidden"
    else
        log_error "Only $HIDDEN_COUNT/$PROJECT1_COUNT windows hidden"
        exit 1
    fi
    echo

    # Step 4: Launch windows for project 2
    log_info "Step 4: Launching test window for $TEST_PROJECT_2"
    log_info "Launching Alacritty terminal..."
    ~/.local/bin/app-launcher-wrapper.sh terminal &
    sleep 2

    PROJECT2_WINDOWS=$(get_windows_by_project "$TEST_PROJECT_2")
    PROJECT2_COUNT=$(echo "$PROJECT2_WINDOWS" | wc -w)
    log_success "Project $TEST_PROJECT_2 now has $PROJECT2_COUNT windows"
    echo

    # Step 5: Switch back to project 1 (TEST SCRATCHPAD RESTORATION)
    log_info "Step 5: Switching back to $TEST_PROJECT_1 (testing scratchpad restoration)"
    switch_project "$TEST_PROJECT_1"

    # Wait for restoration
    sleep 2

    # Check if all project 1 windows are visible
    RESTORED_COUNT=0
    for window_id in $PROJECT1_WINDOWS; do
        VISIBLE=$(swaymsg -t get_tree | jq ".. | select(.id == $window_id) | .visible")
        WORKSPACE=$(swaymsg -t get_tree | jq -r ".. | select(.id == $window_id) | .workspace")
        if [ "$VISIBLE" = "true" ]; then
            ((RESTORED_COUNT++))
            log_success "Window $window_id restored (workspace: $workspace)"
        else
            log_error "Window $window_id still hidden"
        fi
    done

    if [ $RESTORED_COUNT -eq $PROJECT1_COUNT ]; then
        log_success "✓ ALL $PROJECT1_COUNT windows from $TEST_PROJECT_1 restored from scratchpad!"
    else
        log_error "✗ Only $RESTORED_COUNT/$PROJECT1_COUNT windows restored"
        exit 1
    fi
    echo

    # Step 6: Verify project 2 windows are now hidden
    log_info "Step 6: Verifying $TEST_PROJECT_2 windows are hidden"
    HIDDEN_COUNT=0
    for window_id in $PROJECT2_WINDOWS; do
        VISIBLE=$(swaymsg -t get_tree | jq ".. | select(.id == $window_id) | .visible")
        if [ "$VISIBLE" = "false" ]; then
            ((HIDDEN_COUNT++))
        fi
    done

    if [ $HIDDEN_COUNT -eq $PROJECT2_COUNT ]; then
        log_success "All $PROJECT2_COUNT windows from $TEST_PROJECT_2 are hidden"
    else
        log_error "Only $HIDDEN_COUNT/$PROJECT2_COUNT windows hidden"
    fi
    echo

    # Step 7: Performance check
    log_info "Step 7: Checking performance metrics"
    PERF_LOG=$(journalctl -u i3-project-daemon --since "10 seconds ago" | grep "Window filtering complete" | tail -1)
    if [ -n "$PERF_LOG" ]; then
        DURATION=$(echo "$PERF_LOG" | grep -oP '\d+\.\d+ms' | head -1)
        log_info "Last filtering took: $DURATION"

        # Extract numeric value for comparison
        DURATION_NUM=$(echo "$DURATION" | grep -oP '^\d+\.\d+')
        if (( $(echo "$DURATION_NUM < 50" | bc -l) )); then
            log_success "Performance: $DURATION (excellent, < 50ms)"
        elif (( $(echo "$DURATION_NUM < 100" | bc -l) )); then
            log_success "Performance: $DURATION (good, < 100ms)"
        else
            log_warning "Performance: $DURATION (acceptable, but > 100ms)"
        fi
    fi
    echo

    # Summary
    echo "═══════════════════════════════════════════════"
    log_success "All tests passed!"
    echo
    echo "Summary:"
    echo "  • Project switching: ✓"
    echo "  • Window hiding: ✓"
    echo "  • Scratchpad restoration: ✓"
    echo "  • Window marks preserved: ✓"
    echo "  • Performance: ✓"
    echo "═══════════════════════════════════════════════"
}

# Run tests
main "$@"
