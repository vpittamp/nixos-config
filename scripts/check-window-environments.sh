#!/usr/bin/env bash
#
# Check I3PM_* Environment Variables for Running Windows
#
# This script inspects all currently running windows in i3
# and displays their I3PM_* environment variables

set -euo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}i3 Window Environment Inspector${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if i3 is running
if ! pgrep -x i3 >/dev/null; then
    echo -e "${RED}ERROR: i3 is not running${NC}"
    exit 1
fi

# Get window list from i3
echo -e "${GREEN}Fetching window list from i3...${NC}"
echo ""

# Use i3-msg to get window tree and extract window IDs
window_count=0
windows_with_env=0
windows_without_env=0

while IFS= read -r line; do
    # Parse JSON line for window info
    window_id=$(echo "$line" | jq -r '.id // empty')
    window_name=$(echo "$line" | jq -r '.name // empty')
    window_class=$(echo "$line" | jq -r '.window_properties.class // empty')

    if [[ -z "$window_id" ]]; then
        continue
    fi

    ((window_count++))

    # Get window PID using xprop
    pid=$(xprop -id "$window_id" _NET_WM_PID 2>/dev/null | awk '{print $3}')

    if [[ -z "$pid" || "$pid" == "" ]]; then
        echo -e "${YELLOW}Window $window_count: ${window_class:-Unknown} - ${window_name}${NC}"
        echo "  No PID found (xprop failed)"
        echo ""
        continue
    fi

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Window $window_count:${NC}"
    echo "  Class: ${window_class:-Unknown}"
    echo "  Title: ${window_name}"
    echo "  PID: $pid"
    echo "  Window ID: $window_id"

    # Check if /proc/<pid>/environ is readable
    if [[ ! -r "/proc/$pid/environ" ]]; then
        echo -e "  ${YELLOW}Cannot read /proc/$pid/environ (permission denied)${NC}"
        echo ""
        continue
    fi

    # Read environment variables
    env_vars=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "^I3PM_" || true)

    if [[ -n "$env_vars" ]]; then
        echo -e "  ${GREEN}✓ I3PM Environment Variables Found:${NC}"
        while IFS= read -r var; do
            var_name=$(echo "$var" | cut -d= -f1)
            var_value=$(echo "$var" | cut -d= -f2-)

            # Color code based on variable
            case "$var_name" in
                I3PM_PROJECT_NAME)
                    if [[ -n "$var_value" ]]; then
                        echo -e "    ${GREEN}$var_name${NC} = ${YELLOW}$var_value${NC}"
                    else
                        echo -e "    ${GREEN}$var_name${NC} = ${RED}(empty - global mode)${NC}"
                    fi
                    ;;
                I3PM_APP_ID)
                    echo -e "    ${GREEN}$var_name${NC} = ${BLUE}$var_value${NC}"
                    ;;
                I3PM_SCOPE)
                    if [[ "$var_value" == "scoped" ]]; then
                        echo -e "    ${GREEN}$var_name${NC} = ${YELLOW}$var_value${NC}"
                    else
                        echo -e "    ${GREEN}$var_name${NC} = ${BLUE}$var_value${NC}"
                    fi
                    ;;
                *)
                    echo -e "    ${GREEN}$var_name${NC} = $var_value"
                    ;;
            esac
        done <<< "$env_vars"
        ((windows_with_env++))
    else
        echo -e "  ${RED}✗ No I3PM_* variables found${NC}"
        echo "  (Window not launched via app-launcher-wrapper.sh)"
        ((windows_without_env++))
    fi

    echo ""
done < <(i3-msg -t get_tree | jq -r '.. | select(.window?) | @json')

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Summary:${NC}"
echo "  Total windows: $window_count"
echo "  With I3PM variables: $windows_with_env"
echo "  Without I3PM variables: $windows_without_env"
echo ""

if [[ $windows_with_env -eq 0 ]] && [[ $window_count -gt 0 ]]; then
    echo -e "${YELLOW}No windows have I3PM_* variables.${NC}"
    echo ""
    echo "This is normal if windows were opened before Feature 035 was implemented."
    echo "To test environment injection:"
    echo ""
    echo "  1. Switch to a project:"
    echo "     i3pm project switch nixos"
    echo ""
    echo "  2. Launch an app via app-launcher-wrapper:"
    echo "     ~/.local/bin/app-launcher-wrapper.sh terminal"
    echo ""
    echo "  3. Run this script again to see I3PM_* variables"
elif [[ $windows_with_env -gt 0 ]]; then
    echo -e "${GREEN}✓ Environment injection is working!${NC}"
    echo ""
    echo "Windows launched via app-launcher-wrapper.sh have I3PM_* variables."
fi
