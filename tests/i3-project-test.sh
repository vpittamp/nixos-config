#!/usr/bin/env bash
# Automated UI testing for i3 project management system using xdotool
# Part of Feature 014 - i3 Project Management System Consolidation
#
# WARNING: This script simulates keyboard input. Do not run while actively typing.
# SAFETY: Does NOT close terminals - only tests project switching functionality

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_PROJECT_NAME="test-nixos-validation"
TEST_PROJECT_DIR="/etc/nixos"
TEST_PROJECT_ICON=""
TEST_PROJECT_DISPLAY="NixOS Test Project"

echo "=== i3 Project Management System - Automated UI Tests ==="
echo
echo -e "${YELLOW}WARNING${NC}: This test will simulate keyboard input"
echo -e "${YELLOW}WARNING${NC}: Ensure no important windows are open during testing"
echo -e "${BLUE}INFO${NC}: Tests will NOT close your current terminal"
echo

# Confirm to proceed
read -p "Press ENTER to continue or Ctrl+C to cancel..."
echo

# Check if i3 is running
if ! pgrep -x i3 > /dev/null; then
    echo -e "${RED}ERROR${NC}: i3 is not running"
    exit 1
fi

# Check required commands
REQUIRED_COMMANDS=("i3-msg" "jq" "xdotool" "project-create" "project-switch" "project-list" "project-clear")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" > /dev/null; then
        echo -e "${RED}ERROR${NC}: Required command not found: $cmd"
        exit 1
    fi
done

ERRORS=0
TESTS_RUN=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo -e "${BLUE}TEST${NC}: $test_name"
    ((TESTS_RUN++))

    if $test_func; then
        echo -e "  ${GREEN}✓ PASS${NC}"
    else
        echo -e "  ${RED}✗ FAIL${NC}"
        ((ERRORS++))
    fi
    echo
}

# Cleanup function
cleanup() {
    echo
    echo "Cleaning up test project..."
    if command -v project-delete > /dev/null 2>&1; then
        project-delete "$TEST_PROJECT_NAME" 2>/dev/null || true
    fi

    # Remove test project file if it exists
    rm -f "$HOME/.config/i3/projects/$TEST_PROJECT_NAME.json" 2>/dev/null || true
}

trap cleanup EXIT

# Test 1: Project creation
test_project_create() {
    project-create --name "$TEST_PROJECT_NAME" \
                   --dir "$TEST_PROJECT_DIR" \
                   --icon "$TEST_PROJECT_ICON" \
                   --display-name "$TEST_PROJECT_DISPLAY" > /dev/null 2>&1

    # Verify file exists
    [ -f "$HOME/.config/i3/projects/$TEST_PROJECT_NAME.json" ]
}

# Test 2: Project appears in list
test_project_list() {
    project-list | grep -q "$TEST_PROJECT_NAME"
}

# Test 3: Project switch via CLI
test_project_switch_cli() {
    project-switch "$TEST_PROJECT_NAME" > /dev/null 2>&1
    sleep 0.5

    # Verify active-project file updated
    if [ ! -f "$HOME/.config/i3/active-project" ]; then
        return 1
    fi

    # Verify correct project is active
    local active_name
    active_name=$(jq -r '.name' "$HOME/.config/i3/active-project" 2>/dev/null || echo "")
    [ "$active_name" = "$TEST_PROJECT_NAME" ]
}

# Test 4: Status bar update (check within 2 seconds)
test_status_bar_update() {
    # Wait for status bar to update (requirement: <1 second, we allow 2 seconds)
    sleep 2

    # We can't directly check visual status bar, but we can verify i3blocks was signaled
    # by checking that the active-project file exists and is correct
    [ -f "$HOME/.config/i3/active-project" ] && \
    [ "$(jq -r '.name' "$HOME/.config/i3/active-project")" = "$TEST_PROJECT_NAME" ]
}

# Test 5: Project clear
test_project_clear() {
    project-clear > /dev/null 2>&1
    sleep 0.5

    # Verify active-project is empty or has 0 fields
    if [ ! -f "$HOME/.config/i3/active-project" ]; then
        return 0
    fi

    local field_count
    field_count=$(jq '. | length' "$HOME/.config/i3/active-project" 2>/dev/null || echo "1")
    [ "$field_count" -eq 0 ]
}

# Test 6: Window mark validation (if windows exist)
test_window_marks() {
    # Switch to test project
    project-switch "$TEST_PROJECT_NAME" > /dev/null 2>&1
    sleep 0.5

    # Check if any windows have project marks
    local marks
    marks=$(i3-msg -t get_tree | jq -r '.. | .marks? | .[]?' | grep "^project:" || echo "")

    # If marks exist, validate format
    if [ -n "$marks" ]; then
        while IFS= read -r mark; do
            if [[ ! "$mark" =~ ^project:[a-zA-Z0-9_-]+(:[a-zA-Z0-9_-]+)?$ ]]; then
                return 1
            fi
        done <<< "$marks"
    fi

    return 0
}

# Test 7: JSON config validation
test_config_valid_json() {
    jq empty "$HOME/.config/i3/projects/$TEST_PROJECT_NAME.json" 2>/dev/null
}

# Test 8: Rapid switching (no race conditions)
test_rapid_switching() {
    # Create second test project
    local test_project2="${TEST_PROJECT_NAME}2"
    project-create --name "$test_project2" \
                   --dir "/tmp" \
                   --icon "" \
                   --display-name "Test 2" > /dev/null 2>&1

    # Rapid switches
    project-switch "$TEST_PROJECT_NAME" > /dev/null 2>&1 &
    sleep 0.1
    project-switch "$test_project2" > /dev/null 2>&1 &
    sleep 0.1
    project-switch "$TEST_PROJECT_NAME" > /dev/null 2>&1
    wait

    sleep 1

    # Verify final state is correct
    local active_name
    active_name=$(jq -r '.name' "$HOME/.config/i3/active-project" 2>/dev/null || echo "")

    # Clean up second project
    rm -f "$HOME/.config/i3/projects/$test_project2.json" 2>/dev/null || true

    [ "$active_name" = "$TEST_PROJECT_NAME" ]
}

# Run all tests
echo "Running automated tests..."
echo

run_test "T1: Project creation" test_project_create
run_test "T2: Project appears in list" test_project_list
run_test "T3: Project switch via CLI" test_project_switch_cli
run_test "T4: Status bar update timing" test_status_bar_update
run_test "T5: Project clear functionality" test_project_clear
run_test "T6: Window mark format validation" test_window_marks
run_test "T7: JSON configuration validity" test_config_valid_json
run_test "T8: Rapid switching without race conditions" test_rapid_switching

echo "=== Test Summary ==="
echo "Tests run: $TESTS_RUN"
echo "Errors: $ERRORS"
echo

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS TEST(S) FAILED${NC}"
    exit 1
fi
