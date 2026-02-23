{ pkgs, config, ... }:

let
  # Full path to i3pm (user profile binary, not in standard PATH for EWW onclick commands)
  i3pm = "${config.home.profileDirectory}/bin/i3pm";

  variantSwitchHelpers = ''
    get_current_variant() {
      local variant
      variant=$(${pkgs.jq}/bin/jq -r '
        if ((.execution_mode // "") == "local") or ((.execution_mode // "") == "ssh") then (.execution_mode // "")
        elif (.remote != null and (.remote.enabled // false)) then "ssh"
        else "local"
        end
      ' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "local")

      case "$variant" in
        local|ssh)
          printf '%s\n' "$variant"
          ;;
        *)
          printf 'local\n'
          ;;
      esac
    }

    switch_project_variant() {
      local project_name="$1"
      local variant="$2"
      local switch_cmd=("${i3pm}" worktree switch)

      if [[ "$variant" == "local" ]]; then
        switch_cmd+=(--local)
      fi
      switch_cmd+=("$project_name")
      "''${switch_cmd[@]}"
    }

    wait_for_project_variant() {
      local expected_project="$1"
      local expected_variant="''${2:-}"
      local timeout_seconds="''${3:-4}"
      local start_ts now_ts current_project current_variant

      start_ts=$(date +%s)
      while true; do
        current_project=$(${pkgs.jq}/bin/jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")
        current_variant=$(get_current_variant)

        if [[ "$current_project" == "$expected_project" ]]; then
          if [[ -z "$expected_variant" || "$current_variant" == "$expected_variant" ]]; then
            return 0
          fi
        fi

        now_ts=$(date +%s)
        if [[ $((now_ts - start_ts)) -ge "$timeout_seconds" ]]; then
          return 1
        fi

        sleep 0.1
      done
    }
  '';

  focusWindowScript = pkgs.writeShellScriptBin "focus-window-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 093: Focus window with automatic project switching
    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    WINDOW_ID="''${2:-}"
    TARGET_VARIANT="''${3:-}"
    if [[ "$TARGET_VARIANT" != "local" && "$TARGET_VARIANT" != "ssh" ]]; then
      TARGET_VARIANT=""
    fi

    ${variantSwitchHelpers}

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

    # Conditional project switch (T013) with deterministic variant alignment.
    # For variant-targeted actions (local/ssh), always run switch to re-apply
    # context-aware filtering and prevent mixed local+SSH windows on one workspace.
    NEEDS_SWITCH=false
    if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
        NEEDS_SWITCH=true
    fi
    if [[ -n "$TARGET_VARIANT" ]]; then
        NEEDS_SWITCH=true
    fi

    if [[ "$NEEDS_SWITCH" == "true" ]]; then
        if ! switch_project_variant "$PROJECT_NAME" "$TARGET_VARIANT"; then
            EXIT_CODE=$?
            ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" \
                "Failed to switch to project $PROJECT_NAME''${TARGET_VARIANT:+ ($TARGET_VARIANT)} (exit code: $EXIT_CODE)"
            exit 1
        fi
        if ! wait_for_project_variant "$PROJECT_NAME" "$TARGET_VARIANT" 4; then
            ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Timeout" \
                "Context did not converge to $PROJECT_NAME''${TARGET_VARIANT:+ ($TARGET_VARIANT)}"
            exit 1
        fi
    fi

    # Focus window (T014)
    ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] scratchpad show" >/dev/null 2>&1 || true
    FOCUS_RESULT=$(${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] focus" 2>/dev/null || true)
    if printf '%s\n' "$FOCUS_RESULT" | ${pkgs.jq}/bin/jq -e 'type == "array" and any(.[]; .success == true)' >/dev/null 2>&1; then
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

  # Focus AI session indicator target:
  # - Focuses the owning terminal window/project context
  # - If tmux pane/session metadata is available, selects that pane
  focusAiSessionScript = pkgs.writeShellScriptBin "focus-ai-session-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    WINDOW_ID="''${2:-}"
    TARGET_VARIANT="''${3:-local}"
    TMUX_PANE="''${4:-}"
    TMUX_SESSION="''${5:-}"
    TMUX_WINDOW="''${6:-}"
    TMUX_PTY="''${7:-}"

    if [[ -z "$PROJECT_NAME" ]]; then
      exit 1
    fi
    if [[ -z "$WINDOW_ID" ]] || [[ ! "$WINDOW_ID" =~ ^-?[0-9]+$ ]]; then
      exit 1
    fi
    if [[ "$TARGET_VARIANT" != "local" && "$TARGET_VARIANT" != "ssh" ]]; then
      TARGET_VARIANT="local"
    fi

    # Reuse existing project-aware window focus flow.
    ${focusWindowScript}/bin/focus-window-action "$PROJECT_NAME" "$WINDOW_ID" "$TARGET_VARIANT" >/dev/null 2>&1 || true

    # Extra direct focus attempt to maximize reliability.
    ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] scratchpad show" >/dev/null 2>&1 || true
    ${pkgs.sway}/bin/swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true

    # If this AI session reports tmux context, jump to that pane/window.
    if command -v tmux >/dev/null 2>&1; then
      if [[ -n "$TMUX_SESSION" ]]; then
        tmux has-session -t "$TMUX_SESSION" >/dev/null 2>&1 || TMUX_SESSION=""
      fi

      if [[ -n "$TMUX_WINDOW" ]]; then
        WINDOW_SELECTOR="$TMUX_WINDOW"
        if [[ "$WINDOW_SELECTOR" == *:* ]]; then
          WINDOW_SELECTOR="''${WINDOW_SELECTOR%%:*}"
        fi
        if [[ -n "$WINDOW_SELECTOR" ]]; then
          TARGET_WINDOW="$WINDOW_SELECTOR"
          if [[ -n "$TMUX_SESSION" ]]; then
            TARGET_WINDOW="''${TMUX_SESSION}:''${WINDOW_SELECTOR}"
          fi
          tmux select-window -t "$TARGET_WINDOW" >/dev/null 2>&1 || true
        fi
      fi

      TARGET_PANE="$TMUX_PANE"
      if [[ -z "$TARGET_PANE" && -n "$TMUX_PTY" ]]; then
        TARGET_PANE=$(tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null | awk -v tty="$TMUX_PTY" '$2 == tty {print $1; exit}')
      fi

      if [[ -n "$TARGET_PANE" ]]; then
        tmux select-pane -t "$TARGET_PANE" >/dev/null 2>&1 || true
      fi
    fi

    exit 0
  '';

  # Feature 139: Maintain MRU ordering for fast AI session switching.
  recordAiSessionMruScript = pkgs.writeShellScriptBin "record-ai-session-mru-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SESSION_KEY="''${1:-}"
    if [[ -z "$SESSION_KEY" ]]; then
      exit 1
    fi

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    STATE_DIR="$RUNTIME_DIR/eww-monitoring-panel"
    MRU_FILE="$STATE_DIR/ai-session-mru.json"
    TMP_FILE="$MRU_FILE.tmp"
    ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"

    if [[ ! -f "$MRU_FILE" ]]; then
      printf '[]\n' > "$MRU_FILE"
    fi

    ${pkgs.jq}/bin/jq -c --arg key "$SESSION_KEY" '
      ([ $key ] + (. // [] | map(select(. != $key))))[:64]
    ' "$MRU_FILE" > "$TMP_FILE" 2>/dev/null || printf '[%s]\n' "$(${pkgs.jq}/bin/jq -Rn --arg key "$SESSION_KEY" '$key')" > "$TMP_FILE"
    ${pkgs.coreutils}/bin/mv "$TMP_FILE" "$MRU_FILE"
  '';

  # Feature 138: Focus active AI session by collision-safe session key.
  # Resolves from monitoring_data.active_ai_sessions and delegates to focus-ai-session-action.
  focusActiveAiSessionScript = pkgs.writeShellScriptBin "focus-active-ai-session-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SESSION_KEY="''${1:-}"
    FALLBACK_PROJECT="''${2:-}"
    FALLBACK_WINDOW_ID="''${3:-}"
    FALLBACK_EXECUTION_MODE="''${4:-local}"
    FALLBACK_TMUX_PANE="''${5:-}"
    FALLBACK_TMUX_SESSION="''${6:-}"
    FALLBACK_TMUX_WINDOW="''${7:-}"
    FALLBACK_TMUX_PTY="''${8:-}"
    if [[ -z "$SESSION_KEY" ]]; then
      exit 1
    fi

    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
    eww_update_retry() {
      local -a kv=("$@")
      local i
      for i in 1 2 3; do
        $EWW_CMD update "''${kv[@]}" >/dev/null 2>&1 && return 0
        ${pkgs.coreutils}/bin/sleep 0.08
      done
      return 1
    }
    MONITORING_DATA=$($EWW_CMD get monitoring_data 2>/dev/null || echo "{}")

    SESSION_TSV=$(${pkgs.jq}/bin/jq -r --arg key "$SESSION_KEY" '
      ((.active_ai_sessions // []) | map(select((.session_key // "") == $key)) | first) as $s
      | if $s == null then "" else
          [
            ($s.project // ""),
            (($s.window_id // 0) | tostring),
            ($s.execution_mode // "local"),
            ($s.tmux_pane // ""),
            ($s.tmux_session // ""),
            ($s.tmux_window // ""),
            ($s.pty // "")
          ] | @tsv
        end
    ' <<< "$MONITORING_DATA")

    if [[ -n "$SESSION_TSV" ]]; then
      IFS=$'\t' read -r PROJECT_NAME WINDOW_ID EXECUTION_MODE TMUX_PANE TMUX_SESSION TMUX_WINDOW TMUX_PTY <<< "$SESSION_TSV"
    else
      PROJECT_NAME="$FALLBACK_PROJECT"
      WINDOW_ID="$FALLBACK_WINDOW_ID"
      EXECUTION_MODE="$FALLBACK_EXECUTION_MODE"
      TMUX_PANE="$FALLBACK_TMUX_PANE"
      TMUX_SESSION="$FALLBACK_TMUX_SESSION"
      TMUX_WINDOW="$FALLBACK_TMUX_WINDOW"
      TMUX_PTY="$FALLBACK_TMUX_PTY"
    fi

    if [[ "$EXECUTION_MODE" != "local" && "$EXECUTION_MODE" != "ssh" ]]; then
      EXECUTION_MODE="local"
    fi

    if [[ -z "$PROJECT_NAME" || -z "$WINDOW_ID" || "$WINDOW_ID" == "0" ]]; then
      exit 1
    fi

    SELECTED_KEY_JSON=$(${pkgs.jq}/bin/jq -Rn --arg key "$SESSION_KEY" '$key')
    eww_update_retry "ai_sessions_selected_key=$SELECTED_KEY_JSON" || true
    ${focusAiSessionScript}/bin/focus-ai-session-action \
      "$PROJECT_NAME" \
      "$WINDOW_ID" \
      "$EXECUTION_MODE" \
      "$TMUX_PANE" \
      "$TMUX_SESSION" \
      "$TMUX_WINDOW" \
      "$TMUX_PTY"
    ${recordAiSessionMruScript}/bin/record-ai-session-mru-action "$SESSION_KEY" >/dev/null 2>&1 || true
  '';

  # Feature 138: Cycle through active AI sessions in deterministic order.
  cycleActiveAiSessionScript = pkgs.writeShellScriptBin "cycle-active-ai-session-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    DIRECTION="''${1:-next}"
    ORDER_MODE="''${2:-priority}"
    if [[ "$DIRECTION" != "next" && "$DIRECTION" != "prev" ]]; then
      DIRECTION="next"
    fi
    if [[ "$ORDER_MODE" != "priority" && "$ORDER_MODE" != "mru" ]]; then
      ORDER_MODE="priority"
    fi

    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
    eww_update_retry() {
      local -a kv=("$@")
      local i
      for i in 1 2 3; do
        $EWW_CMD update "''${kv[@]}" >/dev/null 2>&1 && return 0
        ${pkgs.coreutils}/bin/sleep 0.08
      done
      return 1
    }
    eww_get_retry() {
      local key="$1"
      local i out=""
      for i in 1 2 3; do
        out=$($EWW_CMD get "$key" 2>/dev/null) && {
          printf '%s' "$out"
          return 0
        }
        ${pkgs.coreutils}/bin/sleep 0.08
      done
      return 1
    }
    MONITORING_DATA=$($EWW_CMD get monitoring_data 2>/dev/null || echo "{}")
    if [[ "$ORDER_MODE" == "mru" ]]; then
      mapfile -t SESSION_KEYS < <(${pkgs.jq}/bin/jq -r '(.active_ai_sessions_mru // .active_ai_sessions // []) | .[].session_key // empty' <<< "$MONITORING_DATA")
    else
      mapfile -t SESSION_KEYS < <(${pkgs.jq}/bin/jq -r '.active_ai_sessions // [] | .[].session_key // empty' <<< "$MONITORING_DATA")
    fi

    SESSION_COUNT=''${#SESSION_KEYS[@]}
    if (( SESSION_COUNT == 0 )); then
      eww_update_retry 'ai_sessions_selected_key=""' 'ai_mru_switcher_visible=false' || true
      exit 0
    fi

    CURRENT_KEY_RAW=$(eww_get_retry ai_sessions_selected_key || echo "")
    CURRENT_KEY=""
    if [[ -n "$CURRENT_KEY_RAW" ]]; then
      CURRENT_KEY=$(
        printf '%s' "$CURRENT_KEY_RAW" \
          | ${pkgs.jq}/bin/jq -r 'if type == "string" then . else tostring end' 2>/dev/null \
          || printf '%s' "$CURRENT_KEY_RAW"
      )
    fi
    CURRENT_IDX=-1
    for i in "''${!SESSION_KEYS[@]}"; do
      if [[ "''${SESSION_KEYS[$i]}" == "$CURRENT_KEY" ]]; then
        CURRENT_IDX=$i
        break
      fi
    done

    BASE_IDX=$CURRENT_IDX
    if (( BASE_IDX < 0 )); then
      if [[ "$DIRECTION" == "prev" ]]; then
        BASE_IDX=0
      else
        BASE_IDX=-1
      fi
    fi

    for (( offset=1; offset<=SESSION_COUNT; offset++ )); do
      if [[ "$DIRECTION" == "prev" ]]; then
        TARGET_IDX=$(( (BASE_IDX - offset + SESSION_COUNT) % SESSION_COUNT ))
      else
        TARGET_IDX=$(( (BASE_IDX + offset + SESSION_COUNT) % SESSION_COUNT ))
      fi
      TARGET_KEY="''${SESSION_KEYS[$TARGET_IDX]}"
      if [[ -z "$TARGET_KEY" ]]; then
        continue
      fi

      SESSION_TSV=$(${pkgs.jq}/bin/jq -r --arg key "$TARGET_KEY" '
        ((.active_ai_sessions // []) | map(select((.session_key // "") == $key)) | first) as $s
        | if $s == null then "" else
            [
              ($s.project // ""),
              (($s.window_id // 0) | tostring),
              ($s.execution_mode // "local"),
              ($s.tmux_pane // ""),
              ($s.tmux_session // ""),
              ($s.tmux_window // ""),
              ($s.pty // "")
            ] | @tsv
          end
      ' <<< "$MONITORING_DATA")
      if [[ -z "$SESSION_TSV" ]]; then
        continue
      fi
      IFS=$'\t' read -r PROJECT_NAME WINDOW_ID EXECUTION_MODE TMUX_PANE TMUX_SESSION TMUX_WINDOW TMUX_PTY <<< "$SESSION_TSV"

      if ${focusActiveAiSessionScript}/bin/focus-active-ai-session-action \
        "$TARGET_KEY" \
        "$PROJECT_NAME" \
        "$WINDOW_ID" \
        "$EXECUTION_MODE" \
        "$TMUX_PANE" \
        "$TMUX_SESSION" \
        "$TMUX_WINDOW" \
        "$TMUX_PTY" >/dev/null 2>&1; then
        exit 0
      fi
    done

    exit 1
  '';

  # Feature 139: One-shot MRU switcher popover + cycle action (Alt+Tab style).
  showAiMruSwitcherScript = pkgs.writeShellScriptBin "show-ai-mru-switcher-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    DIRECTION="''${1:-next}"
    if [[ "$DIRECTION" != "next" && "$DIRECTION" != "prev" ]]; then
      DIRECTION="next"
    fi

    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
    eww_update_retry() {
      local -a kv=("$@")
      local i
      for i in 1 2 3; do
        $EWW_CMD update "''${kv[@]}" >/dev/null 2>&1 && return 0
        ${pkgs.coreutils}/bin/sleep 0.08
      done
      return 1
    }
    eww_update_retry 'ai_mru_switcher_visible=true' || true

    ${cycleActiveAiSessionScript}/bin/cycle-active-ai-session-action "$DIRECTION" mru >/dev/null 2>&1 || true

    (
      ${pkgs.coreutils}/bin/sleep 1.25
      eww_update_retry 'ai_mru_switcher_visible=false' || true
    ) &
  '';

  # Feature 141: Toggle collapsed state for grouped Active AI rail sections.
  toggleAiGroupCollapseScript = pkgs.writeShellScriptBin "toggle-ai-group-collapse-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    GROUP_KEY="''${1:-}"
    if [[ -z "$GROUP_KEY" ]]; then
      exit 1
    fi

    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
    eww_update_retry() {
      local -a kv=("$@")
      local i
      for i in 1 2 3; do
        $EWW_CMD update "''${kv[@]}" >/dev/null 2>&1 && return 0
        ${pkgs.coreutils}/bin/sleep 0.08
      done
      return 1
    }
    CURRENT_RAW=$($EWW_CMD get ai_group_collapsed_projects 2>/dev/null || echo "[]")
    CURRENT_JSON=$(
      printf '%s' "$CURRENT_RAW" \
        | ${pkgs.jq}/bin/jq -c 'if type == "array" then . else [] end' 2>/dev/null \
        || echo "[]"
    )

    UPDATED_JSON=$(
      ${pkgs.jq}/bin/jq -c --arg key "$GROUP_KEY" '
        (if type == "array" then . else [] end) as $arr
        | if ($arr | index($key)) != null
          then [$arr[] | select(. != $key)]
          else ($arr + [$key])
          end
      ' <<< "$CURRENT_JSON"
    )
    eww_update_retry "ai_group_collapsed_projects=$UPDATED_JSON" || true
  '';

  # Feature 140: Jump back to previous AI session (toggles between last two MRU entries).
  toggleLastAiSessionScript = pkgs.writeShellScriptBin "toggle-last-ai-session-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
    eww_get_retry() {
      local key="$1"
      local i out=""
      for i in 1 2 3; do
        out=$($EWW_CMD get "$key" 2>/dev/null) && {
          printf '%s' "$out"
          return 0
        }
        ${pkgs.coreutils}/bin/sleep 0.08
      done
      return 1
    }
    MONITORING_DATA=$($EWW_CMD get monitoring_data 2>/dev/null || echo "{}")

    mapfile -t SESSION_KEYS < <(${pkgs.jq}/bin/jq -r '(.active_ai_sessions_mru // .active_ai_sessions // []) | .[].session_key // empty' <<< "$MONITORING_DATA")
    SESSION_COUNT=''${#SESSION_KEYS[@]}
    if (( SESSION_COUNT == 0 )); then
      exit 0
    fi

    CURRENT_KEY_RAW=$(eww_get_retry ai_sessions_selected_key || echo "")
    CURRENT_KEY=""
    if [[ -n "$CURRENT_KEY_RAW" ]]; then
      CURRENT_KEY=$(
        printf '%s' "$CURRENT_KEY_RAW" \
          | ${pkgs.jq}/bin/jq -r 'if type == "string" then . else tostring end' 2>/dev/null \
          || printf '%s' "$CURRENT_KEY_RAW"
      )
    fi

    TARGET_KEY="''${SESSION_KEYS[0]}"
    if (( SESSION_COUNT > 1 )) && [[ "$CURRENT_KEY" == "''${SESSION_KEYS[0]}" ]]; then
      TARGET_KEY="''${SESSION_KEYS[1]}"
    fi

    [[ -n "$TARGET_KEY" ]] || exit 0
    ${focusActiveAiSessionScript}/bin/focus-active-ai-session-action "$TARGET_KEY" >/dev/null 2>&1 || true
  '';

  # Feature 142: Toggle pinned state for a specific AI session key.
  toggleAiSessionPinScript = pkgs.writeShellScriptBin "toggle-ai-session-pin-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SESSION_KEY="''${1:-}"
    [[ -n "$SESSION_KEY" ]] || exit 1

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    STATE_DIR="$RUNTIME_DIR/eww-monitoring-panel"
    PIN_FILE="$STATE_DIR/ai-session-pins.json"
    TMP_FILE="$PIN_FILE.tmp"
    ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"
    [[ -f "$PIN_FILE" ]] || printf '[]\n' > "$PIN_FILE"

    ${pkgs.jq}/bin/jq -c --arg key "$SESSION_KEY" '
      (if type == "array" then . else [] end) as $pins
      | if ($pins | index($key)) != null
        then [$pins[] | select(. != $key)]
        else ($pins + [$key])
        end
    ' "$PIN_FILE" > "$TMP_FILE"
    ${pkgs.coreutils}/bin/mv "$TMP_FILE" "$PIN_FILE"
  '';

  # Feature 142: Toggle pin on currently selected AI session.
  toggleSelectedAiSessionPinScript = pkgs.writeShellScriptBin "toggle-selected-ai-session-pin-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    EWW_CMD="${pkgs.eww}/bin/eww --no-daemonize --config $HOME/.config/eww-monitoring-panel"
    eww_get_retry() {
      local key="$1"
      local i out=""
      for i in 1 2 3; do
        out=$($EWW_CMD get "$key" 2>/dev/null) && {
          printf '%s' "$out"
          return 0
        }
        ${pkgs.coreutils}/bin/sleep 0.08
      done
      return 1
    }
    CURRENT_KEY_RAW=$(eww_get_retry ai_sessions_selected_key || echo "")
    CURRENT_KEY=""
    if [[ -n "$CURRENT_KEY_RAW" ]]; then
      CURRENT_KEY=$(
        printf '%s' "$CURRENT_KEY_RAW" \
          | ${pkgs.jq}/bin/jq -r 'if type == "string" then . else tostring end' 2>/dev/null \
          || printf '%s' "$CURRENT_KEY_RAW"
      )
    fi
    [[ -n "$CURRENT_KEY" ]] || exit 0
    ${toggleAiSessionPinScript}/bin/toggle-ai-session-pin-action "$CURRENT_KEY"
  '';

  # Open remote session item action:
  # - Ensures project context is active
  # - Launches project terminal (app-launcher-wrapper handles SSH sesh attach)
  openRemoteSessionWindowScript = pkgs.writeShellScriptBin "open-remote-session-window-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    REMOTE_SESSION_NAME="''${2:-}"
    TARGET_VARIANT="''${3:-ssh}"
    if [[ "$TARGET_VARIANT" != "local" && "$TARGET_VARIANT" != "ssh" ]]; then
      TARGET_VARIANT="ssh"
    fi

    ${variantSwitchHelpers}
    if [[ -z "$PROJECT_NAME" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u critical "Remote Session Open Failed" "No project name provided"
      exit 1
    fi

    CURRENT_PROJECT=$(${pkgs.jq}/bin/jq -r '.qualified_name // "global"' "$HOME/.config/i3/active-worktree.json" 2>/dev/null || echo "global")

    NEEDS_SWITCH=false
    if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
      NEEDS_SWITCH=true
    fi
    if [[ -n "$TARGET_VARIANT" ]]; then
      NEEDS_SWITCH=true
    fi

    if [[ "$NEEDS_SWITCH" == "true" ]]; then
      if ! switch_project_variant "$PROJECT_NAME" "$TARGET_VARIANT" >/dev/null 2>&1; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" "Failed to switch to $PROJECT_NAME"
        exit 1
      fi
      if ! wait_for_project_variant "$PROJECT_NAME" "$TARGET_VARIANT" 4; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Timeout" \
          "Context did not converge to $PROJECT_NAME ($TARGET_VARIANT)"
        exit 1
      fi
    fi

    if [[ -x "$HOME/.local/bin/app-launcher-wrapper.sh" ]]; then
      if [[ -n "$REMOTE_SESSION_NAME" ]]; then
        I3PM_CONTEXT_VARIANT_OVERRIDE="$TARGET_VARIANT" \
        I3PM_REMOTE_SESSION_NAME_OVERRIDE="$REMOTE_SESSION_NAME" \
          "$HOME/.local/bin/app-launcher-wrapper.sh" terminal >/dev/null 2>&1 &
      else
        I3PM_CONTEXT_VARIANT_OVERRIDE="$TARGET_VARIANT" \
          "$HOME/.local/bin/app-launcher-wrapper.sh" terminal >/dev/null 2>&1 &
      fi
      exit 0
    fi

    ${pkgs.libnotify}/bin/notify-send -u critical "Remote Session Open Failed" "app-launcher-wrapper.sh not found"
    exit 1
  '';

  # Feature 093: Switch project action script (T016-T020)
  # Switches to a different project context by name
  switchProjectScript = pkgs.writeShellScriptBin "switch-project-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 093: Switch to a different project context
    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    TARGET_VARIANT="''${2:-}"
    if [[ "$TARGET_VARIANT" != "local" && "$TARGET_VARIANT" != "ssh" ]]; then
      TARGET_VARIANT=""
    fi

    ${variantSwitchHelpers}

    # Validate input (T017)
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Project Switch Failed" "No project name provided"
        exit 1
    fi

    # Lock file mechanism for debouncing (T018) with timeout
    # Sanitize project name (replace / with _) to create valid file path
    # Use timestamp-based lock to prevent stale locks from blocking forever
    LOCK_SUFFIX=""
    if [[ -n "$TARGET_VARIANT" ]]; then
      LOCK_SUFFIX="-''${TARGET_VARIANT}"
    fi
    LOCK_FILE="/tmp/eww-monitoring-project-''${PROJECT_NAME//\//_}''${LOCK_SUFFIX}.lock"
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

    CURRENT_VARIANT=$(get_current_variant)
    NEEDS_SWITCH=false
    if [[ "$PROJECT_NAME" != "$CURRENT_PROJECT" ]]; then
      NEEDS_SWITCH=true
    elif [[ -n "$TARGET_VARIANT" ]] && [[ "$CURRENT_VARIANT" != "$TARGET_VARIANT" ]]; then
      NEEDS_SWITCH=true
    fi

    # Check if already in target project + target variant
    if [[ "$NEEDS_SWITCH" == "false" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u low "Already in project $PROJECT_NAME''${TARGET_VARIANT:+ ($TARGET_VARIANT)}"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="$PROJECT_NAME"
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_project="") &
        exit 0
    fi

    # Execute project switch (T020)
    if switch_project_variant "$PROJECT_NAME" "$TARGET_VARIANT"; then
        ${pkgs.libnotify}/bin/notify-send -u normal "Switched to project $PROJECT_NAME''${TARGET_VARIANT:+ ($TARGET_VARIANT)}"
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
  # Supports optional context scoping (execution_mode + connection_key) so a
  # local/SSH project card only closes windows from that specific context.
  # Feature 119: Improved close worktree script with rate limiting and error handling
  closeWorktreeScript = pkgs.writeShellScriptBin "close-worktree-action" ''
    #!${pkgs.bash}/bin/bash
    # Feature 119: Close all windows belonging to a specific worktree/project
    # Improved with rate limiting, error handling, and state validation
    set -euo pipefail

    PROJECT_NAME="''${1:-}"
    TARGET_VARIANT="''${2:-}"
    TARGET_CONNECTION_KEY="''${3:-}"

    if [[ "$TARGET_VARIANT" != "local" && "$TARGET_VARIANT" != "ssh" ]]; then
        TARGET_VARIANT=""
    fi

    TARGET_CONTEXT_KEY=""
    if [[ -n "$TARGET_VARIANT" && -n "$TARGET_CONNECTION_KEY" ]]; then
        TARGET_CONTEXT_KEY="''${PROJECT_NAME}::''${TARGET_VARIANT}::''${TARGET_CONNECTION_KEY}"
    fi

    # Validate input
    if [[ -z "$PROJECT_NAME" ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Close Worktree Failed" "No project name provided"
        exit 1
    fi

    # Feature 119: Rate limiting instead of lock file (1 second debounce for batch operations)
    LOCK_KEY="$PROJECT_NAME"
    if [[ -n "$TARGET_CONTEXT_KEY" ]]; then
        LOCK_KEY="''${LOCK_KEY}::''${TARGET_CONTEXT_KEY}"
    fi
    LOCK_SAFE=$(printf '%s' "$LOCK_KEY" | ${pkgs.coreutils}/bin/tr '/:@' '___' | ${pkgs.coreutils}/bin/tr -cd '[:alnum:]_.-')
    LOCK_FILE="/tmp/eww-close-worktree-''${LOCK_SAFE}.lock"
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

    # Get all window IDs with marks matching this project.
    # Mark format: <scope>:<app>:<project>:<window_id>, where project may contain ':'.
    # Optional ctx filtering keeps local/SSH cards isolated.
    WINDOW_IDS=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" --arg ctx "$TARGET_CONTEXT_KEY" '
      def is_project_mark:
        (startswith("scoped:") or startswith("global:")) and ((split(":") | length) >= 4);
      def project_from_mark:
        (split(":")) as $parts | ($parts[2:($parts | length - 1)] | join(":"));
      def has_ctx_mark:
        any(.marks[]?; startswith("ctx:"));
      def matches_ctx:
        ($ctx == "")
        or any(.marks[]?; . == ("ctx:" + $ctx))
        or (has_ctx_mark | not);

      .. | objects | select(.marks? != null)
      | select(
          (any(.marks[]?; (is_project_mark and (project_from_mark == $proj))))
          and matches_ctx
        )
      | .id
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
    REMAINING=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" --arg ctx "$TARGET_CONTEXT_KEY" '
      def is_project_mark:
        (startswith("scoped:") or startswith("global:")) and ((split(":") | length) >= 4);
      def project_from_mark:
        (split(":")) as $parts | ($parts[2:($parts | length - 1)] | join(":"));
      def has_ctx_mark:
        any(.marks[]?; startswith("ctx:"));
      def matches_ctx:
        ($ctx == "")
        or any(.marks[]?; . == ("ctx:" + $ctx))
        or (has_ctx_mark | not);

      .. | objects | select(.marks? != null)
      | select(
          (any(.marks[]?; (is_project_mark and (project_from_mark == $proj))))
          and matches_ctx
        )
      | .id
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
    PROJECT_KEY="''${1:-}"
    if [[ -z "$PROJECT_KEY" ]]; then
        exit 1
    fi

    # Get current value
    CURRENT=$(${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel get context_menu_project 2>/dev/null || echo "")

    if [[ "$CURRENT" == "$PROJECT_KEY" ]]; then
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update context_menu_project='''
    else
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update "context_menu_project=$PROJECT_KEY"
    fi
  '';

  # Toggle individual project expand/collapse in Windows view
  # Handles: "all" mode (switch to array), array mode (add/remove project)
  toggleWindowsProjectExpandScript = pkgs.writeShellScriptBin "toggle-windows-project-expand" ''
    #!${pkgs.bash}/bin/bash
    # Toggle individual project expand/collapse state
    PROJECT_KEY="''${1:-}"
    if [[ -z "$PROJECT_KEY" ]]; then
        exit 1
    fi

    EWW="${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel"

    # Get current state
    CURRENT_RAW=$($EWW get windows_expanded_projects 2>/dev/null || echo "all")
    CURRENT=$(printf '%s' "$CURRENT_RAW" | ${pkgs.coreutils}/bin/tr -d '\r\n')
    [[ -z "$CURRENT" ]] && CURRENT="all"

    if [[ "$CURRENT" == "all" ]]; then
        # Currently all expanded - clicking collapses this one only
        # Use card_id for uniqueness; fall back to name for older payloads.
        ALL_PROJECTS=$($EWW get monitoring_data 2>/dev/null | ${pkgs.jq}/bin/jq -c '
          if type == "object" then
            [.projects[]? | (.card_id // .name)]
          elif type == "string" then
            (try (fromjson | [.projects[]? | (.card_id // .name)]) catch [])
          else
            []
          end
        ' 2>/dev/null || echo "[]")
        NEW_LIST=$(echo "$ALL_PROJECTS" | ${pkgs.jq}/bin/jq -c --arg key "$PROJECT_KEY" '[.[] | select(. != $key)]' 2>/dev/null || echo "[]")
        $EWW update "windows_expanded_projects=$NEW_LIST" "windows_all_expanded=false"
    else
        # Array mode - toggle this project in/out
        CURRENT_ARRAY=$(echo "$CURRENT" | ${pkgs.jq}/bin/jq -c '
          if type == "array" then .
          elif type == "string" then (try fromjson catch [])
          else []
          end
        ' 2>/dev/null || echo "[]")
        IS_EXPANDED=$(echo "$CURRENT_ARRAY" | ${pkgs.jq}/bin/jq -r --arg key "$PROJECT_KEY" 'index($key) != null' 2>/dev/null || echo "false")

        if [[ "$IS_EXPANDED" == "true" ]]; then
            # Remove from array
            NEW_LIST=$(echo "$CURRENT_ARRAY" | ${pkgs.jq}/bin/jq -c --arg key "$PROJECT_KEY" '[.[] | select(. != $key)]' 2>/dev/null || echo "[]")
        else
            # Add to array
            NEW_LIST=$(echo "$CURRENT_ARRAY" | ${pkgs.jq}/bin/jq -c --arg key "$PROJECT_KEY" '. + [$key]' 2>/dev/null || ${pkgs.jq}/bin/jq -nc --arg key "$PROJECT_KEY" '[$key]')
        fi

        # Keep array mode for reliable per-project expansion behavior.
        $EWW update "windows_expanded_projects=$NEW_LIST" "windows_all_expanded=false"
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
  inherit focusWindowScript focusAiSessionScript recordAiSessionMruScript
          focusActiveAiSessionScript cycleActiveAiSessionScript showAiMruSwitcherScript
          toggleLastAiSessionScript toggleAiSessionPinScript
          toggleSelectedAiSessionPinScript toggleAiGroupCollapseScript
          switchProjectScript closeWorktreeScript
          closeAllWindowsScript closeWindowScript toggleProjectContextScript
          toggleWindowsProjectExpandScript
          copyWindowJsonScript copyTraceDataScript
          fetchWindowEnvScript startWindowTraceScript fetchTraceEventsScript
          navigateToTraceScript navigateToEventScript startTraceFromTemplateScript
          openRemoteSessionWindowScript
          openLangfuseTraceScript;
}
