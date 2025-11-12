#!/usr/bin/env bash
# Helper script to run Sway integration tests
# Usage: ./run-tests.sh [test-name|all]
#
# Examples:
#   ./run-tests.sh basic          # Run basic functionality test
#   ./run-tests.sh all             # Run all tests
#   ./run-tests.sh interactive     # Launch interactive debugger

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Print usage
usage() {
    echo "Usage: $0 [test-name|all|list]"
    echo ""
    echo "Available tests:"
    echo "  basic                - Basic Sway functionality"
    echo "  windowLaunch         - Window launch and tracking"
    echo "  workspaceNavigation  - Workspace switching"
    echo "  i3pmDaemon           - i3pm daemon integration"
    echo "  multiMonitor         - Multi-monitor setup"
    echo "  swayTestFramework    - Sway-test framework integration"
    echo "  interactive          - Interactive debugging REPL"
    echo "  all                  - Run all tests"
    echo ""
    echo "Examples:"
    echo "  $0 basic"
    echo "  $0 all"
    echo "  $0 interactive"
    exit 1
}

# List available tests
list_tests() {
    echo "Available integration tests:"
    echo ""
    echo -e "${GREEN}Basic Functionality:${NC}"
    echo "  basic - Core Sway features (outputs, workspaces, IPC)"
    echo ""
    echo -e "${GREEN}Window Management:${NC}"
    echo "  windowLaunch - Launch apps and verify windows"
    echo "  workspaceNavigation - Switch between workspaces"
    echo "  multiMonitor - Multi-monitor workspace distribution"
    echo ""
    echo -e "${GREEN}Integration:${NC}"
    echo "  i3pmDaemon - Project management daemon"
    echo "  swayTestFramework - JSON-based test framework"
    echo ""
    echo -e "${GREEN}Debugging:${NC}"
    echo "  interactive - Interactive Python REPL in VM"
    echo ""
    echo -e "${GREEN}All Tests:${NC}"
    echo "  all - Run complete test suite"
}

# Run a single test
run_test() {
    local test_name=$1

    echo -e "${YELLOW}Building test: ${test_name}${NC}"

    # Use nix build if available (flakes), fallback to nix-build
    if command -v nix &> /dev/null; then
        # Try flake-based build first
        if nix build .#swayTests.${test_name} 2>/dev/null; then
            echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
            return 0
        else
            # Fallback to nix-build
            if nix-build -A ${test_name} 2>&1 | tee /tmp/test-${test_name}.log; then
                echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
                return 0
            else
                echo -e "${RED}✗ ${test_name} FAILED${NC}"
                echo "See /tmp/test-${test_name}.log for details"
                return 1
            fi
        fi
    else
        echo -e "${RED}Error: nix command not found${NC}"
        return 1
    fi
}

# Run interactive mode
run_interactive() {
    echo -e "${YELLOW}Building interactive test driver...${NC}"

    # Build the driver
    if nix-build -A interactive 2>&1 | tee /tmp/test-interactive.log; then
        local driver_path="./result/bin/nixos-test-driver"

        if [[ -f "$driver_path" ]]; then
            echo -e "${GREEN}Launching interactive test driver...${NC}"
            echo ""
            echo "Available commands in Python REPL:"
            echo "  machine.shell_interact()         # Interactive shell in VM"
            echo "  machine.succeed('command')       # Run command as root"
            echo "  machine.succeed('su - testuser -c \"command\"')  # Run as testuser"
            echo "  machine.screenshot('name')       # Take screenshot"
            echo "  machine.wait_for_unit('unit')    # Wait for systemd unit"
            echo ""
            echo "Example commands:"
            echo "  >>> machine.shell_interact()"
            echo "  >>> machine.succeed('su - testuser -c \"swaymsg -t get_tree\"')"
            echo "  >>> machine.screenshot('debug')"
            echo ""

            exec "$driver_path"
        else
            echo -e "${RED}Error: Test driver not found at $driver_path${NC}"
            return 1
        fi
    else
        echo -e "${RED}Failed to build interactive driver${NC}"
        echo "See /tmp/test-interactive.log for details"
        return 1
    fi
}

# Run all tests
run_all() {
    local tests=(
        "basic"
        "windowLaunch"
        "workspaceNavigation"
        "i3pmDaemon"
        "multiMonitor"
        "swayTestFramework"
    )

    local passed=0
    local failed=0

    echo -e "${YELLOW}Running all Sway integration tests...${NC}"
    echo ""

    for test in "${tests[@]}"; do
        if run_test "$test"; then
            ((passed++))
        else
            ((failed++))
        fi
        echo ""
    done

    # Summary
    echo "========================================"
    echo -e "Summary: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}"
    echo "========================================"

    if [[ $failed -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Main
main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    local test_name=$1

    case "$test_name" in
        list)
            list_tests
            ;;
        all)
            run_all
            ;;
        interactive)
            run_interactive
            ;;
        basic|windowLaunch|workspaceNavigation|i3pmDaemon|multiMonitor|swayTestFramework)
            run_test "$test_name"
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown test '${test_name}'${NC}"
            echo ""
            usage
            ;;
    esac
}

main "$@"
