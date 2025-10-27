#!/usr/bin/env bash
# End-to-end validation script for IPC Launch Context feature
#
# Feature 041: IPC Launch Context - T042
#
# Purpose:
# - Run all user story test scenarios sequentially
# - Check success criteria (SC-001 through SC-010) validation
# - Generate comprehensive test report with pass/fail and statistics
#
# Usage:
#   ./validate_launch_context.sh [--verbose] [--json]
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Script error (missing dependencies, permissions, etc.)

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/etc/nixos"
SCENARIO_DIR="${SCRIPT_DIR}/scenarios/launch_context"

# Output formatting
VERBOSE=false
JSON_OUTPUT=false
USE_COLOR=true

# Test results tracking
declare -A TEST_RESULTS
declare -A TEST_TIMES
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
START_TIME=$(date +%s)

# Color codes
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --json|-j)
                JSON_OUTPUT=true
                USE_COLOR=false
                RED=''
                GREEN=''
                YELLOW=''
                BLUE=''
                BOLD=''
                NC=''
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -v, --verbose    Show detailed test output"
                echo "  -j, --json       Output results in JSON format"
                echo "  -h, --help       Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 2
                ;;
        esac
    done
}

# Print message with formatting
log() {
    local level="$1"
    shift
    local message="$*"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        return  # Suppress logs in JSON mode
    fi

    case "$level" in
        info)
            echo -e "${BLUE}ℹ${NC} ${message}"
            ;;
        success)
            echo -e "${GREEN}✓${NC} ${message}"
            ;;
        error)
            echo -e "${RED}✗${NC} ${message}"
            ;;
        warn)
            echo -e "${YELLOW}⚠${NC} ${message}"
            ;;
        header)
            echo -e "${BOLD}${message}${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Run a single test scenario
run_test() {
    local test_name="$1"
    local test_file="$2"
    local description="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    log info "Running: ${test_name} - ${description}"

    local test_start=$(date +%s.%N)
    local output
    local exit_code

    if [[ "$VERBOSE" == "true" ]]; then
        # Run with output visible
        python "$test_file" && exit_code=$? || exit_code=$?
    else
        # Capture output
        output=$(python "$test_file" 2>&1) && exit_code=$? || exit_code=$?
    fi

    local test_end=$(date +%s.%N)
    local duration=$(echo "$test_end - $test_start" | bc)

    TEST_TIMES["$test_name"]="$duration"

    if [[ $exit_code -eq 0 ]]; then
        TEST_RESULTS["$test_name"]="PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log success "${test_name} - PASSED (${duration}s)"
    else
        TEST_RESULTS["$test_name"]="FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log error "${test_name} - FAILED (${duration}s)"

        if [[ "$VERBOSE" == "false" ]]; then
            echo "--- Test output ---"
            echo "$output"
            echo "--- End output ---"
        fi
    fi

    echo ""
}

# Check prerequisites
check_prerequisites() {
    log info "Checking prerequisites..."

    # Check Python is available
    if ! command -v python &> /dev/null; then
        log error "Python not found. Please install Python 3."
        exit 2
    fi

    # Check test scenario directory exists
    if [[ ! -d "$SCENARIO_DIR" ]]; then
        log error "Test scenario directory not found: $SCENARIO_DIR"
        exit 2
    fi

    # Check all test files exist
    local missing_tests=()
    for test_file in \
        "$SCENARIO_DIR/sequential_launches.py" \
        "$SCENARIO_DIR/rapid_launches.py" \
        "$SCENARIO_DIR/timeout_handling.py" \
        "$SCENARIO_DIR/multi_app_types.py" \
        "$SCENARIO_DIR/workspace_disambiguation.py" \
        "$SCENARIO_DIR/edge_cases.py"
    do
        if [[ ! -f "$test_file" ]]; then
            missing_tests+=("$(basename "$test_file")")
        fi
    done

    if [[ ${#missing_tests[@]} -gt 0 ]]; then
        log error "Missing test files: ${missing_tests[*]}"
        exit 2
    fi

    log success "Prerequisites check passed"
    echo ""
}

# Run all test scenarios
run_all_tests() {
    log header "═══════════════════════════════════════════════════════════════"
    log header "Feature 041: IPC Launch Context - Validation Test Suite"
    log header "═══════════════════════════════════════════════════════════════"
    echo ""

    # User Story 1: Sequential Application Launches (P1 - MVP)
    run_test \
        "US1-Sequential" \
        "$SCENARIO_DIR/sequential_launches.py" \
        "Sequential launches >2s apart (SC-001)"

    # User Story 2: Rapid Application Launches (P2)
    run_test \
        "US2-Rapid" \
        "$SCENARIO_DIR/rapid_launches.py" \
        "Rapid launches <0.5s apart (SC-002)"

    # User Story 3: Launch Timeout Handling (P2)
    run_test \
        "US3-Timeout" \
        "$SCENARIO_DIR/timeout_handling.py" \
        "Timeout and expiration handling (SC-005)"

    # User Story 4: Multiple Application Types (P3)
    run_test \
        "US4-MultiApp" \
        "$SCENARIO_DIR/multi_app_types.py" \
        "Multi-app correlation (SC-009)"

    # User Story 5: Workspace-Based Disambiguation (P3)
    run_test \
        "US5-Workspace" \
        "$SCENARIO_DIR/workspace_disambiguation.py" \
        "Workspace signal boost (FR-018)"

    # Edge Cases: Comprehensive Coverage
    run_test \
        "EdgeCases" \
        "$SCENARIO_DIR/edge_cases.py" \
        "Edge case coverage (SC-010)"
}

# Generate test report
generate_report() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        generate_json_report "$total_duration"
    else
        generate_text_report "$total_duration"
    fi
}

# Generate text report
generate_text_report() {
    local total_duration="$1"

    log header "═══════════════════════════════════════════════════════════════"
    log header "Test Results Summary"
    log header "═══════════════════════════════════════════════════════════════"
    echo ""

    # Test results table
    echo "Test Scenario                      | Status | Duration"
    echo "-----------------------------------|--------|----------"
    for test_name in $(echo "${!TEST_RESULTS[@]}" | tr ' ' '\n' | sort); do
        local status="${TEST_RESULTS[$test_name]}"
        local duration="${TEST_TIMES[$test_name]}"

        if [[ "$status" == "PASS" ]]; then
            printf "${GREEN}%-35s${NC} | ${GREEN}%-6s${NC} | %8.2fs\n" "$test_name" "$status" "$duration"
        else
            printf "${RED}%-35s${NC} | ${RED}%-6s${NC} | %8.2fs\n" "$test_name" "$status" "$duration"
        fi
    done

    echo ""
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed:      ${GREEN}$TESTS_PASSED${NC}"
    echo "Failed:      ${RED}$TESTS_FAILED${NC}"
    echo "Duration:    ${total_duration}s"
    echo ""

    # Success criteria validation
    log header "Success Criteria Validation"
    log header "═══════════════════════════════════════════════════════════════"
    echo ""

    # Map test scenarios to success criteria
    validate_success_criterion "SC-001" "US1-Sequential" "Sequential launches achieve 100% accuracy with HIGH confidence"
    validate_success_criterion "SC-002" "US2-Rapid" "Rapid launches achieve 95% accuracy with MEDIUM+ confidence"
    validate_success_criterion "SC-005" "US3-Timeout" "Timeout expires within 5±0.5s with 100% accuracy"
    validate_success_criterion "SC-009" "US4-MultiApp" "100% pure IPC-based correlation (no fallback)"
    validate_success_criterion "SC-010" "EdgeCases" "100% edge case coverage"

    echo ""

    # Final verdict
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log header "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        log header "${GREEN}✓ ALL TESTS PASSED - FEATURE READY FOR DEPLOYMENT${NC}"
        log header "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    else
        log header "${RED}═══════════════════════════════════════════════════════════════${NC}"
        log header "${RED}✗ TESTS FAILED - FEATURE NEEDS FIXES${NC}"
        log header "${RED}═══════════════════════════════════════════════════════════════${NC}"
    fi
}

# Validate individual success criterion
validate_success_criterion() {
    local criterion="$1"
    local test_name="$2"
    local description="$3"

    if [[ "${TEST_RESULTS[$test_name]}" == "PASS" ]]; then
        log success "$criterion: $description"
    else
        log error "$criterion: $description (test failed)"
    fi
}

# Generate JSON report
generate_json_report() {
    local total_duration="$1"

    echo "{"
    echo "  \"feature\": \"041-ipc-launch-context\","
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"duration\": $total_duration,"
    echo "  \"summary\": {"
    echo "    \"total\": $TESTS_TOTAL,"
    echo "    \"passed\": $TESTS_PASSED,"
    echo "    \"failed\": $TESTS_FAILED,"
    echo "    \"success_rate\": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc)"
    echo "  },"
    echo "  \"tests\": ["

    local first=true
    for test_name in $(echo "${!TEST_RESULTS[@]}" | tr ' ' '\n' | sort); do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        local status="${TEST_RESULTS[$test_name]}"
        local duration="${TEST_TIMES[$test_name]}"

        echo -n "    {"
        echo -n "\"name\": \"$test_name\", "
        echo -n "\"status\": \"$status\", "
        echo -n "\"duration\": $duration"
        echo -n "}"
    done

    echo ""
    echo "  ],"
    echo "  \"success_criteria\": {"
    echo "    \"SC-001\": \"${TEST_RESULTS['US1-Sequential']}\","
    echo "    \"SC-002\": \"${TEST_RESULTS['US2-Rapid']}\","
    echo "    \"SC-005\": \"${TEST_RESULTS['US3-Timeout']}\","
    echo "    \"SC-009\": \"${TEST_RESULTS['US4-MultiApp']}\","
    echo "    \"SC-010\": \"${TEST_RESULTS['EdgeCases']}\""
    echo "  }"
    echo "}"
}

# Main execution
main() {
    parse_args "$@"
    check_prerequisites
    run_all_tests
    generate_report

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
