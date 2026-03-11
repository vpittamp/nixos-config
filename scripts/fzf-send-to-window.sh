#!/usr/bin/env bash
# FZF-based launcher that sends commands to another window
# Usage: fzf-send-to-window.sh [target_workspace]

TARGET_WORKSPACE="${1:-4}"  # Default to workspace 4
DAEMON_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

rpc_request() {
    local method="$1"
    local params_json="${2:-{}}"
    local request response
    request=$(jq -nc --arg method "$method" --argjson params "$params_json" \
      '{jsonrpc:"2.0", method:$method, params:$params, id:1}')
    [[ -S "$DAEMON_SOCKET" ]] || return 1
    response=$(timeout 2s socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)
    [[ -n "$response" ]] || return 1
    jq -c '.result' <<< "$response"
}

# FZF options
OPTS='--info=inline --print-query --expect=ctrl-space --bind=tab:replace-query'

# Header with instructions
HEADER="Send command to workspace $TARGET_WORKSPACE | Enter=selected | Ctrl+Space=typed | Tab=replace"

# Run fzf and capture output
OUTPUT=$(compgen -c | fzf $OPTS --header="$HEADER")

# Parse output - fzf with --expect outputs:
# Line 1: The key that was pressed (empty for Enter)
# Line 2: The query (what user typed)
# Line 3: The selected item
KEY=$(echo "$OUTPUT" | sed -n '1p')
QUERY=$(echo "$OUTPUT" | sed -n '2p')
SELECTED=$(echo "$OUTPUT" | sed -n '3p')

# Determine the command to send
if [ "$KEY" = "ctrl-space" ]; then
    # Ctrl+Space: use exactly what was typed
    COMMAND="$QUERY"
elif [ -n "$SELECTED" ]; then
    # Enter: use selected item
    COMMAND="$SELECTED"
else
    # No selection: use query
    COMMAND="$QUERY"
fi

# Exit if no command
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Get first window info for the target workspace from daemon tree
WINDOW_INFO=$(rpc_request "get_windows" '{}' | jq -r --argjson workspace "$TARGET_WORKSPACE" '
  [.. | objects
   | select((.workspace? | tonumber? // -1) == $workspace)
   | {window: .id, class: (.class // .app_id // "unknown"), name: (.title // .name // "(untitled)")}]
  | .[0]
')

if [ "$WINDOW_INFO" == "null" ] || [ -z "$WINDOW_INFO" ]; then
    notify-send -u critical "Send to Window" "No window found in workspace $TARGET_WORKSPACE"
    exit 1
fi

WINDOW_CLASS=$(echo "$WINDOW_INFO" | jq -r '.class')
WINDOW_NAME=$(echo "$WINDOW_INFO" | jq -r '.name')

# Focus the workspace via daemon
rpc_request "workspace.focus" "$(jq -nc --argjson workspace "$TARGET_WORKSPACE" '{workspace:$workspace}')" > /dev/null 2>&1 || true

# Give i3 a moment to switch
sleep 0.1

# Type the command using xdotool
xdotool type --clearmodifiers "$COMMAND"

# Press Enter to execute
xdotool key Return

# Show notification
notify-send -u low "Sent to Workspace $TARGET_WORKSPACE" "$COMMAND\n→ $WINDOW_CLASS"
