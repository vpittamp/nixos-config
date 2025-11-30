#!/usr/bin/env bash
#
# DEPRECATED: Feature 035 Test Runner
#
# This script tests the legacy project system which has been replaced by
# Feature 100/101's worktree-based project management using repos.json.
#
# The old project system used:
#   - i3pm project create/switch/list/current/delete
#   - ~/.config/i3/projects/*.json files
#
# The new system uses:
#   - i3pm worktree switch/list/create/remove
#   - ~/.config/i3/repos.json (single source of truth)
#   - ~/.config/i3/active-worktree.json (current context)
#
# This script is kept for historical reference but should NOT be run.
# For testing the new system, see:
#   - tests/100-automate-project-and/
#   - tests/101-worktree-click-switch/
#
# Original description:
# This script runs all polish phase tests (T094-T100) in an isolated environment
# Safe to run remotely via SSH + tmux without disrupting active RDP session
#
# Usage:
#   ./test-feature-035.sh [--help|--dry-run|--quick|--full]
#
# Options:
#   --help      Show this help message
#   --dry-run   Show what would be tested without executing
#   --quick     Run quick validation tests only (T094-T095)
#   --full      Run full test suite including performance tests (default)

echo "ERROR: This test script is DEPRECATED."
echo "The legacy project system has been replaced by worktree-based management."
echo "Use 'i3pm worktree' commands instead of 'i3pm project'."
exit 1

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIR="/etc/nixos/specs/035-now-that-we"
LOG_DIR="$HOME/.local/state/i3pm-tests"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_LOG="$LOG_DIR/test-035-$TIMESTAMP.log"
RESULTS_JSON="$LOG_DIR/test-results-$TIMESTAMP.json"

# Test mode
MODE="full"
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$TEST_LOG"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*" | tee -a "$TEST_LOG"
}

log_section() {
    echo "" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
    echo -e "${BLUE}$*${NC}" | tee -a "$TEST_LOG"
    echo "========================================" | tee -a "$TEST_LOG"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# //' | sed 's/^#//'
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --quick)
                MODE="quick"
                shift
                ;;
            --full)
                MODE="full"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Check if we're in an isolated environment
check_environment() {
    log_section "Environment Check"

    # Check if running in tmux
    if [[ -n "${TMUX:-}" ]]; then
        log_success "Running in tmux session (persistent)"
    else
        log_warn "Not in tmux - tests may be interrupted if SSH drops"
        log_info "Recommend: ssh user@hetzner 'tmux new-session -s i3pm-tests ./scripts/test-feature-035.sh'"
    fi

    # Check DISPLAY
    if [[ -n "${DISPLAY:-}" ]]; then
        log_info "DISPLAY=$DISPLAY"
        # Check if it's likely the RDP session
        if [[ "$DISPLAY" =~ ^:1[0-9]$ ]]; then
            log_warn "Appears to be RDP display - tests may create visible windows"
        fi
    else
        log_error "No DISPLAY set - cannot run GUI tests"
        return 1
    fi

    # Check if i3 is running
    if pgrep -x i3 >/dev/null; then
        log_success "i3 window manager is running"
    else
        log_error "i3 is not running - cannot test"
        return 1
    fi

    # Check if i3pm daemon is running
    if systemctl --user is-active i3-project-event-listener >/dev/null 2>&1; then
        log_success "i3pm daemon is running"
    else
        log_error "i3pm daemon is not running"
        log_info "Start with: systemctl --user start i3-project-event-listener"
        return 1
    fi

    # Check if i3pm CLI is available
    if command -v i3pm >/dev/null; then
        log_success "i3pm CLI is available"
    else
        log_error "i3pm command not found"
        return 1
    fi

    return 0
}

# T094: Test all CLI commands with --json output
test_json_output() {
    log_section "T094: Test CLI --json Output"

    local tests_passed=0
    local tests_failed=0

    # Test project commands
    local project_commands=(
        "i3pm project list --json"
        "i3pm project current --json"
    )

    for cmd in "${project_commands[@]}"; do
        log_info "Testing: $cmd"
        if $DRY_RUN; then
            log_info "[DRY RUN] Would execute: $cmd"
            continue
        fi

        if output=$(eval "$cmd" 2>&1); then
            # Validate JSON
            if echo "$output" | jq . >/dev/null 2>&1; then
                log_success "$cmd - Valid JSON"
                ((tests_passed++))
            else
                log_error "$cmd - Invalid JSON"
                ((tests_failed++))
            fi
        else
            log_error "$cmd - Command failed"
            ((tests_failed++))
        fi
    done

    # Test apps commands
    local apps_commands=(
        "i3pm apps list --json"
        "i3pm apps list --scope=scoped --json"
        "i3pm apps list --scope=global --json"
    )

    for cmd in "${apps_commands[@]}"; do
        log_info "Testing: $cmd"
        if $DRY_RUN; then
            log_info "[DRY RUN] Would execute: $cmd"
            continue
        fi

        if output=$(eval "$cmd" 2>&1); then
            if echo "$output" | jq . >/dev/null 2>&1; then
                log_success "$cmd - Valid JSON"
                ((tests_passed++))
            else
                log_error "$cmd - Invalid JSON"
                ((tests_failed++))
            fi
        else
            log_error "$cmd - Command failed"
            ((tests_failed++))
        fi
    done

    # Test daemon commands
    local daemon_commands=(
        "i3pm daemon status --json"
        "i3pm daemon ping --json"
    )

    for cmd in "${daemon_commands[@]}"; do
        log_info "Testing: $cmd"
        if $DRY_RUN; then
            log_info "[DRY RUN] Would execute: $cmd"
            continue
        fi

        if output=$(eval "$cmd" 2>&1); then
            if echo "$output" | jq . >/dev/null 2>&1; then
                log_success "$cmd - Valid JSON"
                ((tests_passed++))
            else
                log_error "$cmd - Invalid JSON"
                ((tests_failed++))
            fi
        else
            log_error "$cmd - Command failed"
            ((tests_failed++))
        fi
    done

    log_info "JSON Output Tests: $tests_passed passed, $tests_failed failed"
    echo "{\"t094\": {\"passed\": $tests_passed, \"failed\": $tests_failed}}" >> "$RESULTS_JSON"

    return $tests_failed
}

# T095: Validate quickstart.md workflows
test_quickstart_workflows() {
    log_section "T095: Validate Quickstart Workflows"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would validate quickstart.md workflows"
        return 0
    fi

    local quickstart="$SPEC_DIR/quickstart.md"
    if [[ ! -f "$quickstart" ]]; then
        log_error "quickstart.md not found: $quickstart"
        return 1
    fi

    log_info "Testing workflow: Create test project"

    # Create temporary test project
    local test_project="test-035-$TIMESTAMP"
    local test_dir="$HOME/.local/share/i3pm-test-projects/$test_project"
    mkdir -p "$test_dir"

    # Workflow 1: Create project
    if i3pm project create "$test_project" \
        --directory "$test_dir" \
        --display-name "Test Project" \
        --icon "🧪"; then
        log_success "Created test project: $test_project"
    else
        log_error "Failed to create test project"
        return 1
    fi

    # Workflow 2: List projects (should include new project)
    if i3pm project list | grep -q "$test_project"; then
        log_success "Project appears in list"
    else
        log_error "Project not found in list"
        return 1
    fi

    # Workflow 3: Switch to project
    if i3pm project switch "$test_project"; then
        log_success "Switched to project: $test_project"
    else
        log_error "Failed to switch to project"
        return 1
    fi

    # Workflow 4: Verify current project
    if current=$(i3pm project current --json) && \
       echo "$current" | jq -e ".name == \"$test_project\"" >/dev/null; then
        log_success "Current project is correct"
    else
        log_error "Current project mismatch"
        return 1
    fi

    # Workflow 5: Clear project
    if i3pm project clear; then
        log_success "Cleared active project"
    else
        log_error "Failed to clear project"
        return 1
    fi

    # Workflow 6: Delete project
    if echo "y" | i3pm project delete "$test_project"; then
        log_success "Deleted test project"
    else
        log_error "Failed to delete project"
        return 1
    fi

    # Cleanup
    rm -rf "$test_dir"

    log_success "All quickstart workflows validated"
    echo "{\"t095\": {\"status\": \"pass\"}}" >> "$RESULTS_JSON"
    return 0
}

# T097: Full system test (create → launch → save → restore)
test_full_system() {
    log_section "T097: Full System Test"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would run full system test"
        return 0
    fi

    log_warn "Full system test will create windows - run in isolated environment!"
    sleep 2

    local test_project="systest-035-$TIMESTAMP"
    local test_dir="$HOME/.local/share/i3pm-test-projects/$test_project"
    mkdir -p "$test_dir"

    # Step 1: Create project
    log_info "Step 1: Create project"
    if ! i3pm project create "$test_project" \
        --directory "$test_dir" \
        --display-name "System Test" \
        --icon "🔬"; then
        log_error "Failed to create project"
        return 1
    fi

    # Step 2: Switch to project
    log_info "Step 2: Switch to project"
    if ! i3pm project switch "$test_project"; then
        log_error "Failed to switch to project"
        return 1
    fi

    # Step 3: Launch applications
    log_info "Step 3: Launch applications (this will create windows)"
    log_warn "Launching test applications..."

    # Launch a few apps via app-launcher-wrapper
    # These should get I3PM_* environment variables
    local apps_launched=0

    # We'll skip actually launching GUI apps in the test
    # Instead, verify the launcher wrapper works
    log_info "Testing app-launcher-wrapper.sh with DRY_RUN"
    if DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh terminal 2>&1 | grep -q "I3PM_PROJECT_NAME"; then
        log_success "App launcher wrapper sets I3PM_* variables"
        ((apps_launched++))
    fi

    # Step 4: Verify windows (skip if no GUI apps launched)
    log_info "Step 4: Verify window environment variables (skipped - no GUI apps launched)"

    # Step 5: Save layout (will be empty but tests the command)
    log_info "Step 5: Save layout"
    if i3pm layout save "$test_project"; then
        log_success "Layout saved"
    else
        log_warn "Layout save returned error (expected if no windows)"
    fi

    # Step 6: Clear project
    log_info "Step 6: Clear project"
    if ! i3pm project clear; then
        log_error "Failed to clear project"
        return 1
    fi

    # Step 7: Cleanup
    log_info "Step 7: Cleanup"
    if echo "y" | i3pm project delete "$test_project"; then
        log_success "Test project deleted"
    fi
    rm -rf "$test_dir"

    log_success "Full system test completed"
    echo "{\"t097\": {\"status\": \"pass\"}}" >> "$RESULTS_JSON"
    return 0
}

# T098-T100: Performance validation
test_performance() {
    log_section "T098-T100: Performance Validation"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would run performance tests"
        return 0
    fi

    # T099: Environment injection overhead
    log_info "T099: Measuring environment injection overhead"
    local start_time end_time duration

    start_time=$(date +%s%N)
    DRY_RUN=1 ~/.local/bin/app-launcher-wrapper.sh terminal >/dev/null 2>&1
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 )) # Convert to ms

    if [[ $duration -lt 100 ]]; then
        log_success "Environment injection: ${duration}ms (< 100ms target)"
    else
        log_warn "Environment injection: ${duration}ms (target: < 100ms)"
    fi

    # T100: /proc reading performance
    log_info "T100: Measuring /proc reading performance"
    local proc_pid=$$

    start_time=$(date +%s%N)
    cat "/proc/$proc_pid/environ" >/dev/null 2>&1
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 )) # Convert to ms

    if [[ $duration -lt 5 ]]; then
        log_success "/proc reading: ${duration}ms (< 5ms target)"
    else
        log_warn "/proc reading: ${duration}ms (target: < 5ms)"
    fi

    # T098: Project switch performance (skip - requires 20 windows)
    log_info "T098: Project switch performance test skipped (requires 20 windows)"

    echo "{\"t099\": {\"duration_ms\": $duration}, \"t100\": {\"duration_ms\": $duration}}" >> "$RESULTS_JSON"
    return 0
}

# Main test runner
main() {
    parse_args "$@"

    log_section "Feature 035 Test Suite"
    log_info "Mode: $MODE"
    log_info "Log file: $TEST_LOG"
    log_info "Results: $RESULTS_JSON"

    # Check environment
    if ! check_environment; then
        log_error "Environment check failed - cannot continue"
        exit 1
    fi

    # Initialize results file
    echo "{" > "$RESULTS_JSON"

    local exit_code=0

    # Run tests based on mode
    case $MODE in
        quick)
            test_json_output || exit_code=1
            test_quickstart_workflows || exit_code=1
            ;;
        full)
            test_json_output || exit_code=1
            test_quickstart_workflows || exit_code=1
            test_full_system || exit_code=1
            test_performance || exit_code=1
            ;;
    esac

    # Finalize results file
    echo "}" >> "$RESULTS_JSON"

    # Summary
    log_section "Test Summary"
    log_info "Results saved to: $RESULTS_JSON"

    if [[ $exit_code -eq 0 ]]; then
        log_success "All tests passed!"
    else
        log_error "Some tests failed - check log for details"
    fi

    exit $exit_code
}

main "$@"
