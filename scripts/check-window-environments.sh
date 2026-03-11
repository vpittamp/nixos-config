#!/usr/bin/env bash
#
# Check I3PM_* Environment Variables for Running Windows
#
# This script inspects daemon-tracked windows
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

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
DAEMON_SOCKET="${DAEMON_SOCKET:-$RUNTIME_DIR/i3-project-daemon/ipc.sock}"

rpc_request() {
    local method="$1"
    local params_json="$2"
    local request response error_json

    request=$(jq -nc \
        --arg method "$method" \
        --argjson params "$params_json" \
        '{jsonrpc:"2.0", method:$method, params:$params, id:1}')

    [[ -S "$DAEMON_SOCKET" ]] || {
        echo -e "${RED}ERROR: daemon socket not found: $DAEMON_SOCKET${NC}" >&2
        exit 1
    }

    response=$(printf '%s\n' "$request" | socat - UNIX-CONNECT:"$DAEMON_SOCKET")
    error_json=$(jq -c '.error // empty' <<< "$response")
    if [[ -n "$error_json" ]]; then
        echo -e "${RED}ERROR: daemon request failed: $error_json${NC}" >&2
        exit 1
    fi

    jq -c '.result' <<< "$response"
}

echo -e "${GREEN}Fetching window list from daemon...${NC}"
echo ""

window_count=0
windows_with_env=0
windows_without_env=0

while IFS= read -r line; do
    window_id=$(echo "$line" | jq -r '.window_id // empty')
    window_name=$(echo "$line" | jq -r '.title // empty')
    window_class=$(echo "$line" | jq -r '.class // empty')

    if [[ -z "$window_id" ]]; then
        continue
    fi

    ((window_count++))

    state_json=$(rpc_request "windows.getState" "$(jq -nc --argjson window_id "$window_id" '{window_id:$window_id}')")
    pid=$(echo "$state_json" | jq -r '.pid // empty')
    env_vars=$(echo "$state_json" | jq -r '.i3pm_env // {} | to_entries[]? | "\(.key)=\(.value)"')

    if [[ -z "$pid" || "$pid" == "" ]]; then
        echo -e "${YELLOW}Window $window_count: ${window_class:-Unknown} - ${window_name}${NC}"
        echo "  No PID found"
        echo ""
        continue
    fi

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Window $window_count:${NC}"
    echo "  Class: ${window_class:-Unknown}"
    echo "  Title: ${window_name}"
    echo "  PID: $pid"
    echo "  Window ID: $window_id"

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
        echo "  (Window is not carrying managed I3PM environment)"
        ((windows_without_env++))
    fi

    echo ""
done < <(rpc_request "get_windows" '{}' | jq -c '.windows[]?')

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
    echo "     i3pm worktree switch vpittamp/nixos-config:main"
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
