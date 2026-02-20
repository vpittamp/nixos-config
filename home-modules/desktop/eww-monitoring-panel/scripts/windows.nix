{ pkgs, config, ... }:

let
  # Full path to i3pm (user profile binary, not in standard PATH for EWW onclick commands)
  i3pm = "${config.home.profileDirectory}/bin/i3pm";

  focusWindowScript = pkgs.writeShellScriptBin "focus-window-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 093: Focus window with automatic project switching
    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    WINDOW_ID="''${2:-}"

    # Validate inputs (T010)
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Action Failed" "No project name provided"
        exit 1
    fi

    if [[ -z "$WINDOW_ID" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Action Failed" "No window ID provided"
        exit 1
    fi

    # Lock file mechanism for debouncing (T011) with timeout
    # Use timestamp-based lock to prevent stale locks from blocking forever
    LOCK_FILE="/tmp/eww-monitoring-focus-''${WINDOW_ID}.lock"
    CURRENT_TIME=$(date +%s)

    if [[ -f "$LOCK_FILE" ]]; then
        LOCK_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$((CURRENT_TIME - LOCK_TIME))
        # Allow retry after 5 seconds (stale lock timeout)
        if [[ $TIME_DIFF -lt 5 ]]; then
            # Silently ignore if previous action still in progress
            exit 1
        fi
    fi

    echo "$CURRENT_TIME" > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT INT TERM

    # Get current project (T012) - Read from active-worktree.json (Feature 101 single source of truth)
    CURRENT_PROJECT=$(${pkgs.jq}/bin/jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")

    # Conditional project switch (T013)
    if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
        if ! ${i3pm} worktree switch "$PROJECT_NAME"; then
            EXIT_CODE=$?
            ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" \
                "Failed to switch to project $PROJECT_NAME (exit code: $EXIT_CODE)"
            exit 1
        fi
    fi

    # Focus window (T014)
    if ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] focus"; then
        # Success path (T015) - Visual feedback only, no notification
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=$WINDOW_ID
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=0) &
        exit 0
    else
        # Failure path - Keep critical notification for actual errors
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Failed" "Window no longer available"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=0
        exit 1
    fi
  '';

  # Feature 093: Switch project action script (T016-T020)
  # Switches to a different project context by name
  switchProjectScript = pkgs.writeShellScriptBin "switch-project-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 093: Switch to a different project context
    set -euo pipefail

    PROJECT_NAME="''${1:-}"

    # Validate input (T017)
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" "No project name provided"
        exit 1
    fi

    # Lock file mechanism for debouncing (T018) with timeout
    # Sanitize project name (replace / with _) to create valid file path
    # Use timestamp-based lock to prevent stale locks from blocking forever
    LOCK_FILE="/tmp/eww-monitoring-project-''${PROJECT_NAME//\//_}.lock"
    CURRENT_TIME=$(date +%s)

    if [[ -f "$LOCK_FILE" ]]; then
        LOCK_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$((CURRENT_TIME - LOCK_TIME))
        # Allow retry after 5 seconds (stale lock timeout)
        if [[ $TIME_DIFF -lt 5 ]]; then
            ${pkgs.libnotify}/bin/notify-send -u low "Project Switch" "Previous action still in progress"
            exit 1
        fi
    fi

    echo "$CURRENT_TIME" > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT INT TERM

    # Get current project (T019) - Read from active-worktree.json (Feature 101 single source of truth)
    CURRENT_PROJECT=$(${pkgs.jq}/bin/jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")

    # Check if already in target project
    if [[ "$PROJECT_NAME" == "$CURRENT_PROJECT" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Already in project $PROJECT_NAME"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="") &
        exit 0
    fi

    # Execute project switch (T020)
    if ${i3pm} worktree switch "$PROJECT_NAME"; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Switched to project $PROJECT_NAME"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="") &
        exit 0
    else
        EXIT_CODE=$?
        ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" \
            "Failed to switch to $PROJECT_NAME (exit code: $EXIT_CODE)"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project=""
        exit 1
    fi
  '';

  # Close worktree action script - closes all windows for a specific project/worktree
  # Feature 119: Improved close worktree script with rate limiting and error handling
  closeWorktreeScript = pkgs.writeShellScriptBin "close-worktree-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 119: Close all windows belonging to a specific worktree/project
    # Improved with rate limiting, error handling, and state validation
    set -euo pipefail

    PROJECT_NAME="''${1:-}"

    # Validate input
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Close Worktree Failed" "No project name provided"
        exit 1
    fi

    # Feature 119: Rate limiting instead of lock file (1 second debounce for batch operations)
    LOCK_FILE="/tmp/eww-close-worktree-''${PROJECT_NAME//\//_}.lock"
    CURRENT_TIME=$(date +%s%N)

    if [[ -f "$LOCK_FILE" ]]; then
        LAST_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$(( (CURRENT_TIME - LAST_TIME) / 1000000000 ))  # Convert to seconds
        if [[ $TIME_DIFF -lt 1 ]]; then
            # Within rate limit window, silently ignore
            exit 0
        fi
    fi

    # Update lock file with current timestamp
    echo "$CURRENT_TIME" > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    # Get all window IDs with marks matching this project
    # Feature 119: Marks are in format: scoped:<app_name>:<project_name>:<window_id>
    # The regex must skip the app name component between scoped: and project name
    WINDOW_IDS=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" '
      .. | objects | select(.marks? != null) |
      select(.marks | map(test("^scoped:[^:]+:" + $proj + ":")) | any) |
      .id
    ' 2>/dev/null || echo "")

    if [[ -z "$WINDOW_IDS" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Close Worktree" "No windows found for $PROJECT_NAME"
        exit 0
    fi

    # Count windows to close
    WINDOW_COUNT=$(echo "$WINDOW_IDS" | wc -l)

    # Feature 119: Close each window with explicit error handling
    CLOSED=0
    FAILED=0
    for WID in $WINDOW_IDS; do
        if ${pkgs.sway}/bin/swaymsg "[con_id=$WID] kill" 2>/dev/null; then
            ((CLOSED++)) || true
        else
            ((FAILED++)) || true
            # Log failure but continue
            echo "Failed to close window $WID" >&2
        fi
    done

    # Feature 119: Re-query sway tree to confirm close
    sleep 0.2  # Brief wait for window close to propagate
    REMAINING=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" '
      .. | objects | select(.marks? != null) |
      select(.marks | map(test("^scoped:" + $proj + ":")) | any) |
      .id
    ' 2>/dev/null | wc -l || echo "0")

    # Feature 119: Send notification with actual close count
    if [[ "$REMAINING" -gt 0 ]]; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Worktree Closed" \
            "Closed $CLOSED/$WINDOW_COUNT windows for $PROJECT_NAME\n$REMAINING windows still open"
    else
        ${pkgs.libnotify}/bin/notify-send -u normal "Worktree Closed" \
            "Closed all $CLOSED windows for $PROJECT_NAME"
    fi
  '';

  # Feature 119: Improved close all windows script with rate limiting and error handling
  closeAllWindowsScript = pkgs.writeShellScriptBin "close-all-windows-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 119: Close all windows tracked by the monitoring panel
    # Improved with rate limiting, error handling, and state validation
    set -euo pipefail

    # Feature 119: Rate limiting instead of lock file (1 second debounce)
    LOCK_FILE="/tmp/eww-close-all-windows.lock"
    CURRENT_TIME=$(date +%s%N)

    if [[ -f "$LOCK_FILE" ]]; then
        LAST_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$(( (CURRENT_TIME - LAST_TIME) / 1000000000 ))  # Convert to seconds
        if [[ $TIME_DIFF -lt 1 ]]; then
            # Within rate limit window, silently ignore
            exit 0
        fi
    fi

    # Update lock file with current timestamp
    echo "$CURRENT_TIME" > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT

    # Get all window IDs with i3pm marks (scoped windows)
    WINDOW_IDS=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '
      .. | objects | select(.marks? != null) |
      select(.marks | map(startswith("scoped:")) | any) |
      .id
    ' 2>/dev/null || echo "")

    if [[ -z "$WINDOW_IDS" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Close All" "No scoped windows to close"
        exit 0
    fi

    # Count windows to close
    WINDOW_COUNT=$(echo "$WINDOW_IDS" | wc -l)

    # Feature 119: Close each window with explicit error handling
    CLOSED=0
    FAILED=0
    for WID in $WINDOW_IDS; do
        if ${pkgs.sway}/bin/swaymsg "[con_id=$WID] kill" 2>/dev/null; then
            ((CLOSED++)) || true
        else
            ((FAILED++)) || true
            echo "Failed to close window $WID" >&2
        fi
    done

    # Feature 119: Re-query sway tree to confirm close
    sleep 0.2  # Brief wait for window close to propagate
    REMAINING=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '
      .. | objects | select(.marks? != null) |
      select(.marks | map(startswith("scoped:")) | any) |
      .id
    ' 2>/dev/null | wc -l || echo "0")

    # Feature 119: Send notification with actual close count
    if [[ "$REMAINING" -gt 0 ]]; then
        ${pkgs.libnotify}/bin/notify-send -u normal "All Windows Closed" \
            "Closed $CLOSED/$WINDOW_COUNT scoped windows\n$REMAINING windows still open"
    else
        ${pkgs.libnotify}/bin/notify-send -u normal "All Windows Closed" \
            "Closed all $CLOSED scoped windows"
    fi
  '';

  # Feature 119: Close individual window script with rate limiting
  # Prevents double-click race conditions and handles missing windows gracefully
  closeWindowScript = pkgs.writeShellScriptBin "close-window-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 119: Close individual window with rate limiting and error handling
    set -euo pipefail

    WINDOW_ID="''${1:-}"

    # Validate input
    if [[ -z "$WINDOW_ID" ]] || [[ "$WINDOW_ID" == "0" ]]; then
        exit 1
    fi

    # Rate limiting: Use lock file with timestamp check (200ms debounce)
    LOCK_FILE="/tmp/eww-close-window-''${WINDOW_ID}.lock"
    CURRENT_TIME=$(date +%s%N)

    if [[ -f "$LOCK_FILE" ]]; then
        LAST_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        TIME_DIFF=$(( (CURRENT_TIME - LAST_TIME) / 1000000 ))  # Convert to ms
        if [[ $TIME_DIFF -lt 200 ]]; then
            # Within rate limit window, silently ignore
            exit 0
        fi
    fi

    # Update lock file with current timestamp
    echo "$CURRENT_TIME" > "$LOCK_FILE"

    # Clear context menu state first (optimistic update)
    ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_window_id=0 &

    # Check if window still exists before trying to close
    WINDOW_EXISTS=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg id "$WINDOW_ID" '
        .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
    ' 2>/dev/null | head -1 || echo "")

    if [[ -z "$WINDOW_EXISTS" ]]; then
        # Window already gone, just clean up state
        rm -f "$LOCK_FILE"
        exit 0
    fi

    # Close the window
    if ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] kill" 2>/dev/null; then
        # Success - clean up lock file after brief delay
        (sleep 0.5 && rm -f "$LOCK_FILE") &
        exit 0
    else
        # Failed to close - clean up lock file
        rm -f "$LOCK_FILE"
        exit 1
    fi
  '';

  # Toggle context menu for project in Windows view
  toggleProjectContextScript = pkgs.writeShellScriptBin "toggle-project-context" ''
    #!${pkgs.bash}/bin/bash
    # Toggle the project context menu in monitoring panel
    PROJECT_NAME="''${1:-}"
    if [[ -z "$PROJECT_NAME" ]]; then
        exit 1
    fi

    # Get current value
    CURRENT=$(${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel get context_menu_project 2>/dev/null || echo "")

    if [[ "$CURRENT" == "$PROJECT_NAME" ]]; then
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_project='''
    else
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update "context_menu_project=$PROJECT_NAME"
    fi
  '';

  # Toggle individual project expand/collapse in Windows view
  # Handles: "all" mode (switch to array), array mode (add/remove project)
  toggleWindowsProjectExpandScript = pkgs.writeShellScriptBin "toggle-windows-project-expand" ''
    #!${pkgs.bash}/bin/bash
    # Toggle individual project expand/collapse state
    PROJECT_NAME="''${1:-}"
    if [[ -z "$PROJECT_NAME" ]]; then
        exit 1
    fi

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current state
    CURRENT=$($EWW get windows_expanded_projects 2>/dev/null || echo "all")

    if [[ "$CURRENT" == "all" ]]; then
        # Currently all expanded - clicking collapses this one only
        # Get all project names and remove the clicked one
        ALL_PROJECTS=$($EWW get monitoring_data 2>/dev/null | ${pkgs.jq}/bin/jq -r '[.projects[].name]')
        NEW_LIST=$(echo "$ALL_PROJECTS" | ${pkgs.jq}/bin/jq -c --arg name "$PROJECT_NAME" '[.[] | select(. != $name)]')
        $EWW update "windows_expanded_projects=$NEW_LIST" "windows_all_expanded=false"
    else
        # Array mode - toggle this project in/out
        IS_EXPANDED=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -e --arg name "$PROJECT_NAME" '. | index($name) != null' 2>/dev/null || echo "false")

        if [[ "$IS_EXPANDED" == "true" ]]; then
            # Remove from array
            NEW_LIST=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c --arg name "$PROJECT_NAME" '[.[] | select(. != $name)]')
        else
            # Add to array
            NEW_LIST=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c --arg name "$PROJECT_NAME" '. + [$name]')
        fi

        # Check if all projects are now expanded
        PROJECT_COUNT=$($EWW get monitoring_data 2>/dev/null | ${pkgs.jq}/bin/jq '.projects | length')
        EXPANDED_COUNT=$(echo "$NEW_LIST" | ${pkgs.jq}/bin/jq 'length')

        if [[ "$EXPANDED_COUNT" -ge "$PROJECT_COUNT" ]]; then
            # All expanded - switch to "all" mode
            $EWW update "windows_expanded_projects=all" "windows_all_expanded=true"
        else
            $EWW update "windows_expanded_projects=$NEW_LIST" "windows_all_expanded=false"
        fi
    fi
  '';

  # SwayNC toggle wrapper - DISABLED pending removal
  copyWindowJsonScript = pkgs.writeShellScript "copy-window-json" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    JSON_BASE64="''${1:-}"
    WINDOW_ID="''${2:-0}"

    if [[ -z "$JSON_BASE64" ]]; then
      echo "Usage: copy-window-json <window-json-b64> <window-id>" >&2
      exit 1
    fi

    # Decode payload and copy to clipboard
    ${pkgs.coreutils}/bin/printf %s "$JSON_BASE64" \
      | ${pkgs.coreutils}/bin/base64 -d \
      | ${pkgs.wl-clipboard}/bin/wl-copy

    # Toggle copied state for visual feedback
    $EWW_CMD update copied_window_id="$WINDOW_ID"
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update copied_window_id=0) &
  '';

  # Feature 096: Copy project JSON to clipboard (similar to window JSON)
  copyTraceDataScript = pkgs.writeShellScript "copy-trace-data" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TRACE_ID="''${1:-}"

    if [[ -z "$TRACE_ID" ]]; then
      echo "Usage: copy-trace-data <trace-id>" >&2
      exit 1
    fi

    # Query daemon for full trace data in timeline format
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      echo "Daemon not running" >&2
      exit 1
    fi

    # Request trace with timeline format for LLM-friendly output
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"trace.get","params":{"trace_id":"%s","format":"timeline"},"id":1}\n' "$TRACE_ID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Extract timeline text and copy to clipboard
    TIMELINE=$(${pkgs.jq}/bin/jq -r '.result.timeline // "Error: Could not fetch trace"' <<< "$RESPONSE")
    ${pkgs.coreutils}/bin/printf '%s' "$TIMELINE" | ${pkgs.wl-clipboard}/bin/wl-copy

    # Toggle copied state for visual feedback
    $EWW_CMD update copied_trace_id="$TRACE_ID"
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update copied_trace_id="") &
  '';

  # Feature 099: Fetch window environment variables via IPC
  # This script queries the daemon for environment variables and updates Eww state
  fetchWindowEnvScript = pkgs.writeShellScript "fetch-window-env" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    WINDOW_PID="''${1:-}"
    WINDOW_ID="''${2:-0}"

    if [[ -z "$WINDOW_PID" ]] || [[ "$WINDOW_PID" == "0" ]] || [[ "$WINDOW_PID" == "null" ]]; then
      # No PID available - update state to show error
      $EWW_CMD update env_window_id="$WINDOW_ID"
      $EWW_CMD update env_loading=false
      $EWW_CMD update env_error="No process ID available for this window"
      $EWW_CMD update env_i3pm_vars="[]"
      $EWW_CMD update env_other_vars="[]"
      exit 0
    fi

    # Set loading state
    $EWW_CMD update env_window_id="$WINDOW_ID"
    $EWW_CMD update env_loading=true
    $EWW_CMD update env_error=""

    # Query daemon for environment variables
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      $EWW_CMD update env_loading=false
      $EWW_CMD update env_error="Daemon not running"
      $EWW_CMD update env_i3pm_vars="[]"
      $EWW_CMD update env_other_vars="[]"
      exit 0
    fi

    # Send JSON-RPC request and parse response
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"window.get_env","params":{"pid":%s},"id":1}\n' "$WINDOW_PID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Extract result using jq
    ERROR=$(${pkgs.jq}/bin/jq -r '.result.error // .error.message // ""' <<< "$RESPONSE")
    I3PM_VARS=$(${pkgs.jq}/bin/jq -c '.result.i3pm_vars // []' <<< "$RESPONSE")
    OTHER_VARS=$(${pkgs.jq}/bin/jq -c '.result.other_vars // []' <<< "$RESPONSE")

    # Update Eww state
    $EWW_CMD update env_loading=false
    $EWW_CMD update env_error="$ERROR"
    $EWW_CMD update env_i3pm_vars="$I3PM_VARS"
    $EWW_CMD update env_other_vars="$OTHER_VARS"
  '';

  # Feature 101: Start tracing a window by ID
  # Uses the window's Sway container ID as the deterministic identifier
  startWindowTraceScript = pkgs.writeShellScript "start-window-trace" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    WINDOW_ID="''${1:-}"
    WINDOW_TITLE="''${2:-Window}"

    if [[ -z "$WINDOW_ID" ]] || [[ "$WINDOW_ID" == "0" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Failed" "No window ID provided"
      exit 1
    fi

    # Close the context menu
    $EWW_CMD update context_menu_window_id=0

    # Start trace using window ID (most deterministic identifier)
    RESULT=$(${i3pm} trace start --id "$WINDOW_ID" 2>&1) || {
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Failed" "$RESULT"
      exit 1
    }

    # Extract trace ID from result
    TRACE_ID=$(echo "$RESULT" | ${pkgs.gnugrep}/bin/grep -oP 'trace-\d+-\d+' | head -1)

    # Show success notification
    ${pkgs.libnotify}/bin/notify-send -t 3000 "Trace Started" "Tracing window: $WINDOW_TITLE\nTrace ID: $TRACE_ID"

    # Switch to Traces tab to show the new trace (index 5)
    $EWW_CMD update current_view_index=5
  '';

  # Feature 101: Fetch trace events for expanded trace card
  # Toggles expansion and fetches events via IPC
  fetchTraceEventsScript = pkgs.writeShellScript "fetch-trace-events" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TRACE_ID="''${1:-}"

    if [[ -z "$TRACE_ID" ]]; then
      exit 1
    fi

    # Check if already expanded - if so, collapse
    CURRENT_EXPANDED=$($EWW_CMD get expanded_trace_id 2>/dev/null || echo "")
    if [[ "$CURRENT_EXPANDED" == "$TRACE_ID" ]]; then
      # Collapse: clear expanded state
      $EWW_CMD update expanded_trace_id=""
      $EWW_CMD update trace_events="[]"
      exit 0
    fi

    # Expand: set loading state and fetch events
    $EWW_CMD update expanded_trace_id="$TRACE_ID"
    $EWW_CMD update trace_events_loading=true
    $EWW_CMD update trace_events="[]"

    # Query daemon for trace events
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      $EWW_CMD update trace_events_loading=false
      $EWW_CMD update trace_events='[{"time_display":"Error","event_type":"error","description":"Daemon not running"}]'
      exit 0
    fi

    # Send JSON-RPC request
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"trace.get","params":{"trace_id":"%s"},"id":1}\n' "$TRACE_ID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Extract and format events using jq
    EVENTS=$(${pkgs.jq}/bin/jq -c '[.result.trace.events[] | {
      time_display: (.time_iso | split("T")[1] | split(".")[0]),
      event_type: .event_type,
      description: .description,
      changes: (
        if .state_before and .state_after then
          (
            (if .state_before.floating != .state_after.floating then ["floating: \(.state_before.floating) → \(.state_after.floating)"] else [] end) +
            (if .state_before.focused != .state_after.focused then ["focused: \(.state_before.focused) → \(.state_after.focused)"] else [] end) +
            (if .state_before.hidden != .state_after.hidden then ["hidden: \(.state_before.hidden) → \(.state_after.hidden)"] else [] end) +
            (if .state_before.workspace_num != .state_after.workspace_num then ["workspace: \(.state_before.workspace_num) → \(.state_after.workspace_num)"] else [] end) +
            (if .state_before.output != .state_after.output then ["output: \(.state_before.output) → \(.state_after.output)"] else [] end)
          ) | join(", ")
        else
          ""
        end
      )
    }]' <<< "$RESPONSE" 2>/dev/null || echo '[]')

    # Handle empty/error response
    if [[ "$EVENTS" == "[]" ]] || [[ "$EVENTS" == "null" ]]; then
      EVENTS='[{"time_display":"--:--:--","event_type":"info","description":"No events recorded","changes":""}]'
    fi

    # Update Eww state
    $EWW_CMD update trace_events_loading=false
    $EWW_CMD update trace_events="$EVENTS"
  '';

  # Feature 102 (T029-T031): Navigate between Log and Traces tabs with highlight
  # Used for click-to-navigate from trace indicator to Traces tab, and vice versa
  navigateToTraceScript = pkgs.writeShellScript "navigate-to-trace" ''
    #!/usr/bin/env bash
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TRACE_ID="''${1:-}"

    if [[ -z "$TRACE_ID" ]]; then
      exit 0
    fi

    # Set highlight state and switch to traces tab (index 5)
    $EWW_CMD update highlight_trace_id="$TRACE_ID"
    $EWW_CMD update current_view_index=5

    # Clear highlight after 2 seconds
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update highlight_trace_id="") &
  '';

  # Feature 102 (T029-T031): Navigate from Traces tab to Log tab and highlight event
  navigateToEventScript = pkgs.writeShellScript "navigate-to-event" ''
    #!/usr/bin/env bash
    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    EVENT_ID="''${1:-}"

    if [[ -z "$EVENT_ID" ]]; then
      exit 0
    fi

    # Set highlight state and switch to events tab (index 4)
    $EWW_CMD update highlight_event_id="$EVENT_ID"
    $EWW_CMD update current_view_index=4

    # Clear highlight after 2 seconds
    (${pkgs.coreutils}/bin/sleep 2 && $EWW_CMD update highlight_event_id="") &
  '';

  # Feature 102 T059: Start trace from template
  startTraceFromTemplateScript = pkgs.writeShellScript "start-trace-from-template" ''
    #!/usr/bin/env bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"
    TEMPLATE_ID="''${1:-}"

    if [[ -z "$TEMPLATE_ID" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "No template ID provided"
      exit 1
    fi

    # Close the dropdown
    $EWW_CMD update template_dropdown_open=false

    # Query daemon to start trace from template
    # Feature 117: User socket only (daemon runs as user service)
    SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"
    if [[ ! -S "$SOCKET" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "i3pm daemon not running"
      exit 1
    fi

    # Send JSON-RPC request
    RESPONSE=$(${pkgs.coreutils}/bin/printf '{"jsonrpc":"2.0","method":"traces.start_from_template","params":{"template_id":"%s"},"id":1}\n' "$TEMPLATE_ID" \
      | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null || echo '{"error":"Connection failed"}')

    # Check for error
    ERROR=$(${pkgs.jq}/bin/jq -r '.error.message // .result.error // empty' <<< "$RESPONSE" 2>/dev/null)
    if [[ -n "$ERROR" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "$ERROR"
      exit 1
    fi

    # Extract trace ID
    TRACE_ID=$(${pkgs.jq}/bin/jq -r '.result.trace_id // empty' <<< "$RESPONSE" 2>/dev/null)
    if [[ -z "$TRACE_ID" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Trace Error" "Failed to start trace"
      exit 1
    fi

    # Show success notification
    TEMPLATE_NAME=$(${pkgs.jq}/bin/jq -r '.result.template_name // "Template"' <<< "$RESPONSE" 2>/dev/null)
    ${pkgs.libnotify}/bin/notify-send -t 3000 "Trace Started" "Template: $TEMPLATE_NAME\nTrace ID: $TRACE_ID"
  '';

  # Open Langfuse trace in browser
  openLangfuseTraceScript = pkgs.writeShellScriptBin "open-langfuse-trace" ''
    #!${pkgs.bash}/bin/bash
    # Open AI session trace in Langfuse web UI
    TRACE_ID="''${1:-}"

    # Debug log
    echo "$(date): open-langfuse-trace called with: '$TRACE_ID'" >> /tmp/langfuse-debug.log

    if [[ -z "$TRACE_ID" ]]; then
      echo "$(date): Empty trace_id, exiting" >> /tmp/langfuse-debug.log
      exit 0
    fi

    # Get hostname for Langfuse URL
    HOSTNAME=$(${pkgs.hostname}/bin/hostname)

    # Langfuse project (could be made configurable)
    LANGFUSE_PROJECT="i3pm-worktree-agents"

    # Build URL
    URL="https://langfuse-''${HOSTNAME}.tail286401.ts.net/project/''${LANGFUSE_PROJECT}/traces/''${TRACE_ID}"

    echo "$(date): Opening URL: $URL" >> /tmp/langfuse-debug.log

    # Open in Firefox with new tab (xdg-open can fail with running Firefox)
    ${pkgs.sway}/bin/swaymsg exec "firefox --new-tab '$URL'" >> /tmp/langfuse-debug.log 2>&1 || \
      ${pkgs.xdg-utils}/bin/xdg-open "$URL" &
  '';

  # Keyboard handler script for view switching (Alt+1-7 or just 1-7)

in
{
  inherit focusWindowScript switchProjectScript closeWorktreeScript
          closeAllWindowsScript closeWindowScript toggleProjectContextScript
          toggleWindowsProjectExpandScript copyWindowJsonScript copyTraceDataScript
          fetchWindowEnvScript startWindowTraceScript fetchTraceEventsScript
          navigateToTraceScript navigateToEventScript startTraceFromTemplateScript
          openLangfuseTraceScript;
}
