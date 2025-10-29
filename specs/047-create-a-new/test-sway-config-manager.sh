#!/usr/bin/env bash
# Automated Testing Script for Sway Configuration Manager (Feature 047)
# Tests daemon startup, IPC communication, validation, reload, and rollback

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

run_test() {
    local test_name="$1"
    ((TESTS_RUN++))
    log_info "Test $TESTS_RUN: $test_name"
}

# Test 1: Check if daemon is running
test_daemon_running() {
    run_test "Daemon is running"

    if systemctl --user is-active sway-config-manager.service > /dev/null 2>&1; then
        log_success "Daemon is running"
        return 0
    else
        log_error "Daemon is not running"
        log_info "Starting daemon..."
        systemctl --user start sway-config-manager.service
        sleep 2

        if systemctl --user is-active sway-config-manager.service > /dev/null 2>&1; then
            log_success "Daemon started successfully"
            return 0
        else
            log_error "Failed to start daemon"
            systemctl --user status sway-config-manager.service
            return 1
        fi
    fi
}

# Test 2: Check if CLI is available
test_cli_available() {
    run_test "CLI command is available"

    if command -v swayconfig > /dev/null 2>&1; then
        log_success "CLI command 'swayconfig' is available"
        return 0
    else
        log_error "CLI command 'swayconfig' not found"
        return 1
    fi
}

# Test 3: Test IPC ping
test_ipc_ping() {
    run_test "IPC communication (ping)"

    if output=$(swayconfig ping 2>&1); then
        if echo "$output" | grep -q "Daemon is responsive"; then
            log_success "IPC ping successful"
            return 0
        else
            log_error "Unexpected ping response: $output"
            return 1
        fi
    else
        log_error "IPC ping failed"
        return 1
    fi
}

# Test 4: Test configuration validation
test_config_validate() {
    run_test "Configuration validation"

    if output=$(swayconfig validate 2>&1); then
        if echo "$output" | grep -q "Configuration is valid" || echo "$output" | grep -q "✅"; then
            log_success "Configuration validation successful"
            return 0
        else
            log_error "Configuration validation returned unexpected output: $output"
            return 1
        fi
    else
        log_error "Configuration validation failed: $output"
        return 1
    fi
}

# Test 5: Test configuration show
test_config_show() {
    run_test "Configuration show command"

    if output=$(swayconfig show 2>&1); then
        if echo "$output" | grep -q "keybindings" || echo "$output" | grep -q "Keybindings"; then
            log_success "Configuration show successful"
            return 0
        else
            log_error "Configuration show returned unexpected output"
            return 1
        fi
    else
        log_error "Configuration show failed"
        return 1
    fi
}

# Test 6: Test configuration reload (dry-run)
test_config_reload_dry_run() {
    run_test "Configuration reload (dry-run)"

    if output=$(swayconfig reload --validate-only 2>&1); then
        if echo "$output" | grep -q "Validation successful" || echo "$output" | grep -q "✅"; then
            log_success "Configuration reload dry-run successful"
            return 0
        else
            log_error "Configuration reload dry-run returned unexpected output: $output"
            return 1
        fi
    else
        log_error "Configuration reload dry-run failed: $output"
        return 1
    fi
}

# Test 7: Test actual configuration reload
test_config_reload() {
    run_test "Configuration reload (actual)"

    # Skip commit for testing
    if output=$(swayconfig reload --skip-commit 2>&1); then
        if echo "$output" | grep -q "successfully" || echo "$output" | grep -q "✅"; then
            log_success "Configuration reload successful"
            return 0
        else
            log_error "Configuration reload returned unexpected output: $output"
            return 1
        fi
    else
        log_error "Configuration reload failed: $output"
        return 1
    fi
}

# Test 8: Test version history
test_config_versions() {
    run_test "Configuration version history"

    if output=$(swayconfig versions 2>&1); then
        # Version history might be empty on first run, that's okay
        log_success "Configuration versions command successful"
        return 0
    else
        log_error "Configuration versions command failed"
        return 1
    fi
}

# Test 9: Check configuration files exist
test_config_files_exist() {
    run_test "Configuration files exist"

    local all_exist=true
    local config_dir="$HOME/.config/sway"

    if [ ! -f "$config_dir/keybindings.toml" ]; then
        log_error "keybindings.toml does not exist"
        all_exist=false
    fi

    if [ ! -f "$config_dir/window-rules.json" ]; then
        log_error "window-rules.json does not exist"
        all_exist=false
    fi

    if [ ! -f "$config_dir/workspace-assignments.json" ]; then
        log_error "workspace-assignments.json does not exist"
        all_exist=false
    fi

    if [ ! -d "$config_dir/projects" ]; then
        log_error "projects directory does not exist"
        all_exist=false
    fi

    if $all_exist; then
        log_success "All configuration files exist"
        return 0
    else
        return 1
    fi
}

# Test 10: Check keybindings file content
test_keybindings_content() {
    run_test "Keybindings file has workspace navigation"

    local keybindings_file="$HOME/.config/sway/keybindings.toml"

    if [ ! -f "$keybindings_file" ]; then
        log_error "Keybindings file does not exist"
        return 1
    fi

    # Check for workspace keybindings
    if grep -q '"Mod+1".*workspace number 1' "$keybindings_file" && \
       grep -q '"Mod+0".*workspace number 10' "$keybindings_file"; then
        log_success "Keybindings file contains workspace navigation (1-10)"
        return 0
    else
        log_error "Keybindings file missing workspace navigation"
        return 1
    fi
}

# Test 11: Check daemon logs for errors
test_daemon_logs() {
    run_test "Daemon logs show no critical errors"

    if logs=$(journalctl --user -u sway-config-manager.service -n 50 --no-pager 2>&1); then
        if echo "$logs" | grep -qi "critical\|fatal\|exception"; then
            log_error "Daemon logs contain critical errors"
            echo "$logs" | grep -i "critical\|fatal\|exception"
            return 1
        else
            log_success "Daemon logs show no critical errors"
            return 0
        fi
    else
        log_error "Failed to retrieve daemon logs"
        return 1
    fi
}

# Main test execution
main() {
    echo "========================================"
    echo "Sway Configuration Manager Test Suite"
    echo "Feature 047: Dynamic Configuration Management"
    echo "========================================"
    echo ""

    log_info "Starting automated tests..."
    echo ""

    # Run all tests
    test_daemon_running
    test_cli_available
    test_ipc_ping
    test_config_files_exist
    test_keybindings_content
    test_config_validate
    test_config_show
    test_config_reload_dry_run
    test_config_reload
    test_config_versions
    test_daemon_logs

    # Summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests Run:    $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
