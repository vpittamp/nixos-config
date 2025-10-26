#!/usr/bin/env bash
# Test script to verify all applications in app-registry-data.nix can launch
# Feature 039: Application Launch Validation

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# Arrays to store results
declare -a PASSED_APPS=()
declare -a FAILED_APPS=()
declare -a SKIPPED_APPS=()

# Log file
LOG_FILE="/tmp/app-launch-test-$(date +%Y%m%d-%H%M%S).log"

echo "=== Application Launch Test ===" | tee "$LOG_FILE"
echo "Testing all applications from app-registry-data.nix" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to test if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to test app launch
test_app() {
    local name="$1"
    local command="$2"
    local params="$3"
    local expected_class="$4"
    local scope="$5"

    TOTAL=$((TOTAL + 1))

    echo -e "${BLUE}[$TOTAL] Testing: $name${NC}" | tee -a "$LOG_FILE"
    echo "  Command: $command $params" | tee -a "$LOG_FILE"
    echo "  Expected class: $expected_class" | tee -a "$LOG_FILE"
    echo "  Scope: $scope" | tee -a "$LOG_FILE"

    # Check if command exists
    if ! command_exists "$command"; then
        echo -e "  ${RED}✗ FAILED: Command '$command' not found${NC}" | tee -a "$LOG_FILE"
        FAILED=$((FAILED + 1))
        FAILED_APPS+=("$name: command not found ($command)")
        echo "" | tee -a "$LOG_FILE"
        return 1
    fi

    # Special handling for different app types
    case "$command" in
        "code")
            # VS Code - test with --version
            if code --version &>> "$LOG_FILE"; then
                echo -e "  ${GREEN}✓ PASSED: Command executable${NC}" | tee -a "$LOG_FILE"
                PASSED=$((PASSED + 1))
                PASSED_APPS+=("$name")
            else
                echo -e "  ${RED}✗ FAILED: Command failed${NC}" | tee -a "$LOG_FILE"
                FAILED=$((FAILED + 1))
                FAILED_APPS+=("$name: command failed")
            fi
            ;;

        "firefoxpwa")
            # Firefox PWA - test if firefoxpwa exists
            if firefoxpwa --version &>> "$LOG_FILE"; then
                echo -e "  ${GREEN}✓ PASSED: Command executable${NC}" | tee -a "$LOG_FILE"
                PASSED=$((PASSED + 1))
                PASSED_APPS+=("$name")
            else
                echo -e "  ${RED}✗ FAILED: Command failed${NC}" | tee -a "$LOG_FILE"
                FAILED=$((FAILED + 1))
                FAILED_APPS+=("$name: firefoxpwa not working")
            fi
            ;;

        "firefox"|"chromium")
            # Browsers - test with --version
            if $command --version &>> "$LOG_FILE"; then
                echo -e "  ${GREEN}✓ PASSED: Command executable${NC}" | tee -a "$LOG_FILE"
                PASSED=$((PASSED + 1))
                PASSED_APPS+=("$name")
            else
                echo -e "  ${RED}✗ FAILED: Command failed${NC}" | tee -a "$LOG_FILE"
                FAILED=$((FAILED + 1))
                FAILED_APPS+=("$name: command failed")
            fi
            ;;

        "ghostty"|"alacritty")
            # Terminals - test with --version
            if $command --version &>> "$LOG_FILE"; then
                echo -e "  ${GREEN}✓ PASSED: Command executable${NC}" | tee -a "$LOG_FILE"
                PASSED=$((PASSED + 1))
                PASSED_APPS+=("$name")
            else
                echo -e "  ${RED}✗ FAILED: Command failed${NC}" | tee -a "$LOG_FILE"
                FAILED=$((FAILED + 1))
                FAILED_APPS+=("$name: command failed")
            fi
            ;;

        "yazi"|"thunar"|"pcmanfm")
            # File managers - just check if command exists
            if command_exists "$command"; then
                echo -e "  ${GREEN}✓ PASSED: Command found${NC}" | tee -a "$LOG_FILE"
                PASSED=$((PASSED + 1))
                PASSED_APPS+=("$name")
            else
                echo -e "  ${RED}✗ FAILED: Command not found${NC}" | tee -a "$LOG_FILE"
                FAILED=$((FAILED + 1))
                FAILED_APPS+=("$name: command not found")
            fi
            ;;

        "slack"|"discord")
            # Communication apps - may not be installed on all systems
            if command_exists "$command"; then
                echo -e "  ${GREEN}✓ PASSED: Command found${NC}" | tee -a "$LOG_FILE"
                PASSED=$((PASSED + 1))
                PASSED_APPS+=("$name")
            else
                echo -e "  ${YELLOW}⊘ SKIPPED: Optional app not installed${NC}" | tee -a "$LOG_FILE"
                SKIPPED=$((SKIPPED + 1))
                SKIPPED_APPS+=("$name: optional")
            fi
            ;;

        *)
            # Default: just check if command exists
            if command_exists "$command"; then
                echo -e "  ${GREEN}✓ PASSED: Command found${NC}" | tee -a "$LOG_FILE"
                PASSED=$((PASSED + 1))
                PASSED_APPS+=("$name")
            else
                echo -e "  ${RED}✗ FAILED: Command not found${NC}" | tee -a "$LOG_FILE"
                FAILED=$((FAILED + 1))
                FAILED_APPS+=("$name: command not found")
            fi
            ;;
    esac

    echo "" | tee -a "$LOG_FILE"
}

# Test all applications from the registry
# Format: test_app "name" "command" "parameters" "expected_class" "scope"

echo "=== Development Tools ===" | tee -a "$LOG_FILE"
test_app "vscode" "code" "--new-window" "Code" "scoped"
test_app "neovim" "ghostty" "-e nvim /etc/nixos/home-vpittamp.nix" "com.mitchellh.ghostty" "scoped"

echo "=== Browsers ===" | tee -a "$LOG_FILE"
test_app "firefox" "firefox" "" "firefox" "global"
test_app "chromium" "chromium" "" "Chromium" "global"

echo "=== Terminals ===" | tee -a "$LOG_FILE"
test_app "ghostty" "ghostty" "-e sesh connect" "com.mitchellh.ghostty" "scoped"
test_app "terminal" "ghostty" "-e sesh" "com.mitchellh.ghostty" "global"
test_app "alacritty" "alacritty" "--working-directory" "Alacritty" "scoped"

echo "=== Git Tools ===" | tee -a "$LOG_FILE"
test_app "lazygit" "ghostty" "-e lazygit" "com.mitchellh.ghostty" "scoped"
test_app "gitui" "ghostty" "-e gitui" "com.mitchellh.ghostty" "scoped"

echo "=== File Managers ===" | tee -a "$LOG_FILE"
test_app "yazi" "yazi" "" "yazi" "scoped"
test_app "thunar" "thunar" "" "Thunar" "scoped"
test_app "pcmanfm" "pcmanfm" "" "Pcmanfm" "scoped"

echo "=== System Tools ===" | tee -a "$LOG_FILE"
test_app "htop" "ghostty" "-e htop" "com.mitchellh.ghostty" "global"
test_app "btop" "ghostty" "-e btop" "com.mitchellh.ghostty" "global"
test_app "k9s" "ghostty" "-e k9s" "com.mitchellh.ghostty" "global"

echo "=== Communication ===" | tee -a "$LOG_FILE"
test_app "slack" "slack" "" "Slack" "global"
test_app "discord" "discord" "" "discord" "global"

echo "=== PWA Applications ===" | tee -a "$LOG_FILE"
test_app "youtube-pwa" "firefoxpwa" "site launch 01K666N2V6BQMDSBMX3AY74TY7" "FFPWA-01K666N2V6BQMDSBMX3AY74TY7" "global"
test_app "google-ai-pwa" "firefoxpwa" "site launch 01K665SPD8EPMP3JTW02JM1M0Z" "FFPWA-01K665SPD8EPMP3JTW02JM1M0Z" "global"
test_app "chatgpt-pwa" "firefoxpwa" "site launch 01K772ZBM45JD68HXYNM193CVW" "FFPWA-01K772ZBM45JD68HXYNM193CVW" "global"
test_app "github-codespaces-pwa" "firefoxpwa" "site launch 01K772Z7AY5J36Q3NXHH9RYGC0" "FFPWA-01K772Z7AY5J36Q3NXHH9RYGC0" "global"

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
