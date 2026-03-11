{ pkgs, config, ... }:

let
  # Full path to i3pm (user profile binary, not in standard PATH for EWW onclick commands)
  i3pm = "${config.home.profileDirectory}/bin/i3pm";
  daemonRpcHelpers = ''
    DAEMON_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/i3-project-daemon/ipc.sock"

    rpc_request() {
      local method="$1"
      local params_json="''${2:-{}}"
      local request response error_json

      request=$(${pkgs.jq}/bin/jq -nc \
        --arg method "$method" \
        --argjson params "$params_json" \
        '{jsonrpc:"2.0", method:$method, params:$params, id:1}')

      [[ -S "$DAEMON_SOCKET" ]] || return 1
      response=$(${pkgs.coreutils}/bin/timeout 2s ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)
      [[ -n "$response" ]] || return 1

      error_json=$(${pkgs.jq}/bin/jq -c '.error // empty' <<< "$response" 2>/dev/null || true)
      [[ -z "$error_json" ]] || return 1

      ${pkgs.jq}/bin/jq -c '.result' <<< "$response"
    }

    get_current_context_json() {
      rpc_request "context.get_active" '{}' || printf '%s\n' '{"qualified_name":"","execution_mode":"global","connection_key":"global","is_global":true}'
    }
  '';

  variantSwitchHelpers = ''
    ${daemonRpcHelpers}

    get_current_variant() {
      local context_json variant
      context_json=$(get_current_context_json)
      variant=$(printf '%s\n' "$context_json" | ${pkgs.jq}/bin/jq -r '
        if ((.execution_mode // "") == "local") or ((.execution_mode // "") == "ssh") then (.execution_mode // "")
        elif (.is_global // false) then "local"
        else "local"
        end
      ' 2>/dev/null || echo "local")

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
      local start_ts now_ts current_project current_variant context_json

      start_ts=$(date +%s)
      while true; do
        context_json=$(get_current_context_json)
        current_project=$(printf '%s\n' "$context_json" | ${pkgs.jq}/bin/jq -r '.qualified_name // "global"' 2>/dev/null || echo "global")
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

    if [[ -z "$WINDOW_ID" ]] || [[ ! "$WINDOW_ID" =~ ^-?[0-9]+$ ]]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Action Failed" "Invalid window ID"
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

    log_stage() {
      local stage="$1"
      printf 'focus-window-action stage=%s project=%s window=%s variant=%s\n' \
        "$stage" "$PROJECT_NAME" "$WINDOW_ID" "''${TARGET_VARIANT:-auto}" >&2
    }

    FOCUS_PARAMS=$(${pkgs.jq}/bin/jq -nc \
      --arg project_name "$PROJECT_NAME" \
      --argjson window_id "$WINDOW_ID" \
      --arg target_variant "$TARGET_VARIANT" \
      '{project_name:$project_name, window_id:$window_id, target_variant:$target_variant}')
    FOCUS_RESULT=$(rpc_request "window.focus" "$FOCUS_PARAMS" || true)

    if [[ -n "$FOCUS_RESULT" ]] && printf '%s\n' "$FOCUS_RESULT" | ${pkgs.jq}/bin/jq -e '.success == true' >/dev/null 2>&1; then
        log_stage "focus_tiled_ok"
        ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=$WINDOW_ID
        (sleep 2 && ${pkgs.eww}/bin/eww --config $HOME/.config/eww-monitoring-panel update clicked_window_id=0) &
        exit 0
    else
        log_stage "focus_tiled_fail"
        ERROR_MSG=$(printf '%s\n' "''${FOCUS_RESULT:-{}}" | ${pkgs.jq}/bin/jq -r '.error // "Window unavailable or failed to focus"' 2>/dev/null || echo "Window unavailable or failed to focus")
        ${pkgs.libnotify}/bin/notify-send -u critical "Focus Failed" "$ERROR_MSG"
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
    CONNECTION_KEY="''${4:-}"
    TMUX_PANE="''${5:-}"
    TMUX_SESSION="''${6:-}"
    TMUX_WINDOW="''${7:-}"
    TMUX_PTY="''${8:-}"

    if [[ -z "$PROJECT_NAME" ]]; then
      exit 1
    fi
    if [[ -z "$WINDOW_ID" ]] || [[ ! "$WINDOW_ID" =~ ^-?[0-9]+$ ]]; then
      exit 1
    fi
    if [[ "$TARGET_VARIANT" != "local" && "$TARGET_VARIANT" != "ssh" ]]; then
      TARGET_VARIANT="local"
    fi

    RECORD_FOCUS_METRIC="${recordAiFocusMetricScript}/bin/record-ai-focus-metric-action"
    TMUX_TARGET_MODE="none"
    TMUX_TARGET_STATUS="skipped"
    SSH_USER=""
    SSH_HOST=""
    SSH_PORT=""

    log_stage() {
      local stage="$1"
      printf 'focus-ai-session-action stage=%s project=%s window=%s variant=%s connection=%s session=%s pane=%s\n' \
        "$stage" "$PROJECT_NAME" "$WINDOW_ID" "$TARGET_VARIANT" "''${CONNECTION_KEY:-none}" "''${TMUX_SESSION:-none}" "''${TMUX_PANE:-none}" >&2
    }

    parse_ssh_connection_key() {
      local raw="''${1:-}"
      local user_host port user host
      [[ -n "$raw" ]] || return 1
      if [[ "$raw" == local@* || "$raw" == "global" || "$raw" == "unknown" ]]; then
        return 1
      fi

      user_host="$raw"
      port="22"
      if [[ "$raw" == *:* ]]; then
        port="''${raw##*:}"
        user_host="''${raw%:*}"
      fi
      [[ "$port" =~ ^[0-9]+$ ]] || return 1

      if [[ "$user_host" == *@* ]]; then
        user="''${user_host%@*}"
        host="''${user_host#*@}"
      else
        user="$(${pkgs.coreutils}/bin/id -un)"
        host="$user_host"
      fi

      [[ -n "$user" && -n "$host" ]] || return 1
      SSH_USER="$user"
      SSH_HOST="$host"
      SSH_PORT="$port"
      return 0
    }

    run_remote_tmux() {
      ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=2 \
        -p "$SSH_PORT" \
        "''${SSH_USER}@''${SSH_HOST}" \
        -- tmux "$@"
    }

    tmux_window_index() {
      local raw="''${1:-}"
      if [[ "$raw" == *:* ]]; then
        printf '%s\n' "''${raw%%:*}"
      else
        printf '%s\n' "$raw"
      fi
    }

    resolve_remote_pane_by_tty() {
      local tty="''${1:-}"
      [[ -n "$tty" ]] || return 1
      run_remote_tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null \
        | ${pkgs.gawk}/bin/awk -v tty="$tty" '$2 == tty {print $1; exit}'
    }

    resolve_local_pane_by_tty() {
      local tty="''${1:-}"
      [[ -n "$tty" ]] || return 1
      tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null \
        | ${pkgs.gawk}/bin/awk -v tty="$tty" '$2 == tty {print $1; exit}'
    }

    validate_remote_tmux_target() {
      local expected_session="''${1:-}"
      local expected_window="''${2:-}"
      local expected_pane="''${3:-}"
      local expected_tty="''${4:-}"
      local target scope actual_session actual_window actual_pane actual_tty

      scope="$expected_session"
      [[ -n "$scope" ]] || scope="$expected_window"
      [[ -n "$scope" ]] || return 0

      target="$scope"
      actual_session=$(run_remote_tmux display-message -p -t "$target" '#{session_name}' 2>/dev/null || true)
      actual_window=$(run_remote_tmux display-message -p -t "$target" '#{window_index}' 2>/dev/null || true)
      actual_pane=$(run_remote_tmux display-message -p -t "$target" '#{pane_id}' 2>/dev/null || true)
      actual_tty=$(run_remote_tmux display-message -p -t "$target" '#{pane_tty}' 2>/dev/null || true)

      [[ -z "$expected_session" || "$actual_session" == "$expected_session" ]] || return 1
      [[ -z "$expected_window" || "$actual_window" == "$expected_window" ]] || return 1
      [[ -z "$expected_pane" || "$actual_pane" == "$expected_pane" ]] || return 1
      [[ -z "$expected_tty" || "$actual_tty" == "$expected_tty" ]] || return 1
      return 0
    }

    validate_local_tmux_target() {
      local expected_session="''${1:-}"
      local expected_window="''${2:-}"
      local expected_pane="''${3:-}"
      local expected_tty="''${4:-}"
      local target scope actual_session actual_window actual_pane actual_tty

      scope="$expected_session"
      [[ -n "$scope" ]] || scope="$expected_window"
      [[ -n "$scope" ]] || return 0

      target="$scope"
      actual_session=$(tmux display-message -p -t "$target" '#{session_name}' 2>/dev/null || true)
      actual_window=$(tmux display-message -p -t "$target" '#{window_index}' 2>/dev/null || true)
      actual_pane=$(tmux display-message -p -t "$target" '#{pane_id}' 2>/dev/null || true)
      actual_tty=$(tmux display-message -p -t "$target" '#{pane_tty}' 2>/dev/null || true)

      [[ -z "$expected_session" || "$actual_session" == "$expected_session" ]] || return 1
      [[ -z "$expected_window" || "$actual_window" == "$expected_window" ]] || return 1
      [[ -z "$expected_pane" || "$actual_pane" == "$expected_pane" ]] || return 1
      [[ -z "$expected_tty" || "$actual_tty" == "$expected_tty" ]] || return 1
      return 0
    }

    select_local_tmux_target() {
      local LOCAL_TMUX_OK=true WINDOW_SELECTOR TARGET_WINDOW TARGET_PANE

      command -v tmux >/dev/null 2>&1 || return 1

      if [[ -n "$TMUX_SESSION" ]]; then
        tmux has-session -t "$TMUX_SESSION" >/dev/null 2>&1 || LOCAL_TMUX_OK=false
      fi

      WINDOW_SELECTOR=$(tmux_window_index "$TMUX_WINDOW")
      if [[ "$LOCAL_TMUX_OK" == "true" && -n "$WINDOW_SELECTOR" ]]; then
        TARGET_WINDOW="$WINDOW_SELECTOR"
        if [[ -n "$TMUX_SESSION" ]]; then
          TARGET_WINDOW="''${TMUX_SESSION}:''${WINDOW_SELECTOR}"
        fi
        tmux select-window -t "$TARGET_WINDOW" >/dev/null 2>&1 || LOCAL_TMUX_OK=false
      fi

      TARGET_PANE="$TMUX_PANE"
      if [[ "$LOCAL_TMUX_OK" == "true" && -z "$TARGET_PANE" && -n "$TMUX_PTY" ]]; then
        TARGET_PANE=$(resolve_local_pane_by_tty "$TMUX_PTY" || true)
      fi

      if [[ "$LOCAL_TMUX_OK" == "true" && -n "$TARGET_PANE" ]]; then
        if ! tmux select-pane -t "$TARGET_PANE" >/dev/null 2>&1; then
          if [[ -n "$TMUX_PTY" ]]; then
            TARGET_PANE=$(resolve_local_pane_by_tty "$TMUX_PTY" || true)
          fi
          if [[ -n "$TARGET_PANE" ]]; then
            tmux select-pane -t "$TARGET_PANE" >/dev/null 2>&1 || LOCAL_TMUX_OK=false
          else
            LOCAL_TMUX_OK=false
          fi
        fi
      fi

      if [[ "$LOCAL_TMUX_OK" == "true" ]]; then
        validate_local_tmux_target "$TMUX_SESSION" "$WINDOW_SELECTOR" "$TARGET_PANE" "$TMUX_PTY" || LOCAL_TMUX_OK=false
      fi

      [[ "$LOCAL_TMUX_OK" == "true" ]]
    }

    FOCUS_OK=true

    # Reuse shared daemon-owned focus protocol first (switch -> focus -> tiled state).
    if ${focusWindowScript}/bin/focus-window-action "$PROJECT_NAME" "$WINDOW_ID" "$TARGET_VARIANT" >/dev/null 2>&1; then
      log_stage "focus_protocol_ok"
    else
      log_stage "focus_protocol_fail"
      FOCUS_OK=false
    fi

    # If this AI session reports tmux context, jump to that pane/window.
    if [[ "$TARGET_VARIANT" == "ssh" ]]; then
      TMUX_TARGET_MODE="remote"
      if ! parse_ssh_connection_key "$CONNECTION_KEY"; then
        TMUX_TARGET_STATUS="fail"
        log_stage "tmux_remote_connection_invalid"
      else
        REMOTE_TMUX_OK=true
        if [[ -n "$TMUX_SESSION" ]]; then
          if ! run_remote_tmux has-session -t "$TMUX_SESSION" >/dev/null 2>&1; then
            REMOTE_TMUX_OK=false
          fi
        fi

        WINDOW_SELECTOR=$(tmux_window_index "$TMUX_WINDOW")
        if [[ "$REMOTE_TMUX_OK" == "true" && -n "$WINDOW_SELECTOR" ]]; then
          TARGET_WINDOW="$WINDOW_SELECTOR"
          if [[ -n "$TMUX_SESSION" ]]; then
            TARGET_WINDOW="''${TMUX_SESSION}:''${WINDOW_SELECTOR}"
          fi
          if ! run_remote_tmux select-window -t "$TARGET_WINDOW" >/dev/null 2>&1; then
            REMOTE_TMUX_OK=false
          fi
        fi

        TARGET_PANE="$TMUX_PANE"
        if [[ "$REMOTE_TMUX_OK" == "true" && -z "$TARGET_PANE" && -n "$TMUX_PTY" ]]; then
          TARGET_PANE=$(resolve_remote_pane_by_tty "$TMUX_PTY" || true)
        fi

        if [[ "$REMOTE_TMUX_OK" == "true" && -n "$TARGET_PANE" ]]; then
          if ! run_remote_tmux select-pane -t "$TARGET_PANE" >/dev/null 2>&1; then
            if [[ -n "$TMUX_PTY" ]]; then
              TARGET_PANE=$(resolve_remote_pane_by_tty "$TMUX_PTY" || true)
            fi
            if [[ -n "$TARGET_PANE" ]]; then
              run_remote_tmux select-pane -t "$TARGET_PANE" >/dev/null 2>&1 || REMOTE_TMUX_OK=false
            else
              REMOTE_TMUX_OK=false
            fi
          fi
        fi

        if [[ "$REMOTE_TMUX_OK" == "true" ]]; then
          if ! validate_remote_tmux_target "$TMUX_SESSION" "$WINDOW_SELECTOR" "$TARGET_PANE" "$TMUX_PTY"; then
            REMOTE_TMUX_OK=false
          fi
        fi

        if [[ "$REMOTE_TMUX_OK" == "true" ]]; then
          TMUX_TARGET_STATUS="success"
          log_stage "tmux_target_remote_ok"
        else
          TMUX_TARGET_STATUS="fail"
          log_stage "tmux_target_remote_fail"
        fi
      fi
    elif command -v tmux >/dev/null 2>&1; then
      TMUX_TARGET_MODE="local"
      if select_local_tmux_target; then
        TMUX_TARGET_STATUS="success"
        log_stage "tmux_target_local_ok"
      else
        TMUX_TARGET_STATUS="fail"
        log_stage "tmux_target_local_fail"
      fi
    else
      TMUX_TARGET_MODE="local"
      TMUX_TARGET_STATUS="missing"
      log_stage "tmux_missing"
    fi

    if [[ ("$TMUX_PANE" != "" || "$TMUX_SESSION" != "" || "$TMUX_WINDOW" != "" || "$TMUX_PTY" != "") && "$TMUX_TARGET_STATUS" != "success" ]]; then
      FOCUS_OK=false
      log_stage "tmux_target_required_fail"
    fi

    # Final safeguard: tmux targeting can alter focus context; enforce tiled state again.
    if ! ensure_window_focus_tiled 3 0.1; then
      FOCUS_OK=false
      log_stage "post_tmux_focus_tiled_fail"
    else
      log_stage "post_tmux_focus_tiled_ok"
    fi

    if [[ "$FOCUS_OK" == "true" ]]; then
      "$RECORD_FOCUS_METRIC" success "$PROJECT_NAME" "$WINDOW_ID" "$TARGET_VARIANT" "$TMUX_TARGET_MODE" "$TMUX_TARGET_STATUS" "$CONNECTION_KEY" >/dev/null 2>&1 || true
      exit 0
    fi

    "$RECORD_FOCUS_METRIC" fail "$PROJECT_NAME" "$WINDOW_ID" "$TARGET_VARIANT" "$TMUX_TARGET_MODE" "$TMUX_TARGET_STATUS" "$CONNECTION_KEY" >/dev/null 2>&1 || true
    exit 1
  '';

  # Feature 143: Persist focus metrics for AI diagnostics view.
  recordAiFocusMetricScript = pkgs.writeShellScriptBin "record-ai-focus-metric-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    STATUS="''${1:-}"
    PROJECT_NAME="''${2:-}"
    WINDOW_ID="''${3:-}"
    EXECUTION_MODE="''${4:-local}"
    TMUX_TARGET_MODE="''${5:-none}"
    TMUX_TARGET_STATUS="''${6:-skipped}"
    CONNECTION_KEY="''${7:-}"
    if [[ "$STATUS" != "success" && "$STATUS" != "fail" ]]; then
      exit 1
    fi

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    STATE_DIR="$RUNTIME_DIR/eww-monitoring-panel"
    METRICS_FILE="$STATE_DIR/ai-monitor-metrics.json"
    TMP_FILE="$METRICS_FILE.tmp"
    ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"

    if [[ ! -f "$METRICS_FILE" ]]; then
      printf '{"focus_attempts":0,"focus_success":0,"focus_fail":0,"last_focus":{}}\n' > "$METRICS_FILE"
    fi

    NOW=$(${pkgs.coreutils}/bin/date +%s)
    ${pkgs.jq}/bin/jq -c \
      --arg status "$STATUS" \
      --arg project "$PROJECT_NAME" \
      --arg window "$WINDOW_ID" \
      --arg mode "$EXECUTION_MODE" \
      --arg tmux_mode "$TMUX_TARGET_MODE" \
      --arg tmux_status "$TMUX_TARGET_STATUS" \
      --arg connection "$CONNECTION_KEY" \
      --argjson ts "$NOW" '
      .focus_attempts = ((.focus_attempts // 0) + 1)
      | if $status == "success"
        then .focus_success = ((.focus_success // 0) + 1)
        else .focus_fail = ((.focus_fail // 0) + 1)
        end
      | .last_focus = {
          status: $status,
          project: $project,
          window_id: $window,
          execution_mode: $mode,
          connection_key: $connection,
          tmux_target_mode: $tmux_mode,
          tmux_target_status: $tmux_status,
          timestamp: $ts
        }
      | .updated_at = $ts
      ' "$METRICS_FILE" > "$TMP_FILE"
    ${pkgs.coreutils}/bin/mv "$TMP_FILE" "$METRICS_FILE"
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

  # Persist explicit "seen" acknowledgement for the currently focused AI session.
  ackAiSessionSeenScript = pkgs.writeShellScriptBin "ack-ai-session-seen-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SESSION_KEY="''${1:-}"
    FINISH_MARKER="''${2:-}"
    [[ -n "$SESSION_KEY" ]] || exit 1

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    STATE_DIR="$RUNTIME_DIR/eww-monitoring-panel"
    EVENTS_FILE="$STATE_DIR/ai-session-seen-events.jsonl"
    ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"

    NOW=$(${pkgs.coreutils}/bin/date +%s)
    EVENT_JSON=$(
      ${pkgs.jq}/bin/jq -cn \
        --arg session_key "$SESSION_KEY" \
        --arg finish_marker "$FINISH_MARKER" \
        --argjson timestamp "$NOW" \
        '{session_key:$session_key, finish_marker:$finish_marker, timestamp:$timestamp}'
    )
    printf '%s\n' "$EVENT_JSON" >> "$EVENTS_FILE"
  '';

  # Feature 138: Focus active AI session by collision-safe session key.
  # Resolves from monitoring_data.active_ai_sessions and delegates to focus-ai-session-action.
  focusActiveAiSessionScript = pkgs.writeShellScriptBin "focus-active-ai-session-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SESSION_KEY="''${1:-}"
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
            ($s.focus_project // $s.window_project // $s.project // ""),
            (($s.window_id // 0) | tostring),
            ($s.focus_execution_mode // $s.execution_mode // "local"),
            ($s.focus_connection_key // $s.connection_key // ""),
            ($s.tmux_pane // ""),
            ($s.tmux_session // ""),
            ($s.tmux_window // ""),
            ($s.pty // ""),
            ($s.finish_marker // "")
          ] | @tsv
        end
    ' <<< "$MONITORING_DATA")

    [[ -n "$SESSION_TSV" ]] || exit 1
    IFS=$'\t' read -r PROJECT_NAME WINDOW_ID EXECUTION_MODE CONNECTION_KEY TMUX_PANE TMUX_SESSION TMUX_WINDOW TMUX_PTY FINISH_MARKER <<< "$SESSION_TSV"

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
      "$CONNECTION_KEY" \
      "$TMUX_PANE" \
      "$TMUX_SESSION" \
      "$TMUX_WINDOW" \
      "$TMUX_PTY"
    ${ackAiSessionSeenScript}/bin/ack-ai-session-seen-action "$SESSION_KEY" "$FINISH_MARKER" >/dev/null 2>&1 || true
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

    infer_current_session_key() {
      local focused_window_id candidates_tsv candidate_count
      focused_window_id=$(${pkgs.jq}/bin/jq -r '
        first(.projects[]?.windows[]? | select((.focused // false) == true) | ((.id // 0) | tostring)) // ""
      ' <<< "$MONITORING_DATA")
      [[ -n "$focused_window_id" && "$focused_window_id" != "0" ]] || return 1

      candidates_tsv=$(${pkgs.jq}/bin/jq -r --arg wid "$focused_window_id" '
        (.active_ai_sessions // [])
        | map(select((.window_id // 0 | tostring) == $wid))
        | map([(.session_key // ""), (.tmux_session // ""), (.tmux_pane // ""), (.updated_at // "")] | @tsv)
        | .[]
      ' <<< "$MONITORING_DATA")
      [[ -n "$candidates_tsv" ]] || return 1

      candidate_count=$(printf '%s\n' "$candidates_tsv" | ${pkgs.coreutils}/bin/wc -l)
      if (( candidate_count == 1 )); then
        printf '%s\n' "$candidates_tsv" | ${pkgs.coreutils}/bin/cut -f1
        return 0
      fi

      if command -v tmux >/dev/null 2>&1; then
        while IFS=$'\t' read -r candidate_key candidate_session candidate_pane _; do
          local client_pane
          [[ -n "$candidate_key" ]] || continue
          [[ -n "$candidate_session" ]] || continue
          [[ -n "$candidate_pane" ]] || continue

          client_pane=$(
            tmux list-clients -t "$candidate_session" -F '#{client_activity} #{pane_id}' 2>/dev/null \
              | ${pkgs.coreutils}/bin/sort -nr -k1,1 \
              | ${pkgs.coreutils}/bin/head -n 1 \
              | ${pkgs.gawk}/bin/awk '{print $2}'
          )
          if [[ -n "$client_pane" && "$candidate_pane" == "$client_pane" ]]; then
            printf '%s\n' "$candidate_key"
            return 0
          fi
        done <<< "$candidates_tsv"
      fi

      # Conservative fallback: assume the first focused-window candidate is current.
      printf '%s\n' "$candidates_tsv" | ${pkgs.coreutils}/bin/head -n 1 | ${pkgs.coreutils}/bin/cut -f1
      return 0
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

    if (( CURRENT_IDX < 0 )); then
      INFERRED_KEY=$(infer_current_session_key || true)
      if [[ -n "$INFERRED_KEY" ]]; then
        CURRENT_KEY="$INFERRED_KEY"
        for i in "''${!SESSION_KEYS[@]}"; do
          if [[ "''${SESSION_KEYS[$i]}" == "$CURRENT_KEY" ]]; then
            CURRENT_IDX=$i
            break
          fi
        done
      fi
    fi

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
                ($s.focus_project // $s.window_project // $s.project // ""),
                (($s.window_id // 0) | tostring),
                ($s.focus_execution_mode // $s.execution_mode // "local"),
                ($s.focus_connection_key // $s.connection_key // ""),
                ($s.tmux_pane // ""),
                ($s.tmux_session // ""),
                ($s.tmux_window // ""),
              ($s.pty // ""),
              ($s.finish_marker // "")
            ] | @tsv
        end
      ' <<< "$MONITORING_DATA")
      if [[ -z "$SESSION_TSV" ]]; then
        continue
      fi
      IFS=$'\t' read -r PROJECT_NAME WINDOW_ID EXECUTION_MODE CONNECTION_KEY TMUX_PANE TMUX_SESSION TMUX_WINDOW TMUX_PTY FINISH_MARKER <<< "$SESSION_TSV"

      if ${focusActiveAiSessionScript}/bin/focus-active-ai-session-action \
        "$TARGET_KEY" >/dev/null 2>&1; then
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

    CURRENT_PROJECT=$(get_current_context_json | ${pkgs.jq}/bin/jq -r '.qualified_name // "global"' 2>/dev/null || echo "global")

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

    CURRENT_PROJECT=$(get_current_context_json | ${pkgs.jq}/bin/jq -r '.qualified_name // "global"' 2>/dev/null || echo "global")

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
    ${daemonRpcHelpers}

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

    WINDOW_TREE=$(rpc_request "get_windows" '{}' || echo '[]')
    WINDOW_IDS=$(printf '%s\n' "$WINDOW_TREE" | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" --arg ctx "$TARGET_CONTEXT_KEY" '
      .. | objects
      | select((.id? // 0) > 0)
      | select(((.project // "") == $proj) and (($ctx == "") or ((.context_key // "") == $ctx)))
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
        if rpc_request "window.action" "$(${pkgs.jq}/bin/jq -nc --argjson window_id "$WID" '{window_id:$window_id, action:"kill"}')" >/dev/null; then
            ((CLOSED++)) || true
        else
            ((FAILED++)) || true
            # Log failure but continue
            echo "Failed to close window $WID" >&2
        fi
    done

    # Feature 119: Re-query sway tree to confirm close
    sleep 0.2  # Brief wait for window close to propagate
    WINDOW_TREE=$(rpc_request "get_windows" '{}' || echo '[]')
    REMAINING=$(printf '%s\n' "$WINDOW_TREE" | ${pkgs.jq}/bin/jq -r --arg proj "$PROJECT_NAME" --arg ctx "$TARGET_CONTEXT_KEY" '
      [.. | objects
       | select((.id? // 0) > 0)
       | select(((.project // "") == $proj) and (($ctx == "") or ((.context_key // "") == $ctx)))] | length
    ' 2>/dev/null || echo "0")

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
    ${daemonRpcHelpers}

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

    WINDOW_TREE=$(rpc_request "get_windows" '{}' || echo '[]')
    WINDOW_IDS=$(printf '%s\n' "$WINDOW_TREE" | ${pkgs.jq}/bin/jq -r '
      .. | objects
      | select((.id? // 0) > 0)
      | select((.project // "") != "")
      | .id
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
        if rpc_request "window.action" "$(${pkgs.jq}/bin/jq -nc --argjson window_id "$WID" '{window_id:$window_id, action:"kill"}')" >/dev/null; then
            ((CLOSED++)) || true
        else
            ((FAILED++)) || true
            echo "Failed to close window $WID" >&2
        fi
    done

    # Feature 119: Re-query sway tree to confirm close
    sleep 0.2  # Brief wait for window close to propagate
    WINDOW_TREE=$(rpc_request "get_windows" '{}' || echo '[]')
    REMAINING=$(printf '%s\n' "$WINDOW_TREE" | ${pkgs.jq}/bin/jq -r '
      [.. | objects | select((.id? // 0) > 0) | select((.project // "") != "")] | length
    ' 2>/dev/null || echo "0")

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
    ${daemonRpcHelpers}

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
    WINDOW_TREE=$(rpc_request "get_windows" '{}' || echo '[]')
    WINDOW_EXISTS=$(printf '%s\n' "$WINDOW_TREE" | ${pkgs.jq}/bin/jq -r --argjson id "$WINDOW_ID" '
        .. | objects | select((.id? // 0) == $id) | .id
    ' 2>/dev/null | head -1 || echo "")

    if [[ -z "$WINDOW_EXISTS" ]]; then
        # Window already gone, just clean up state
        rm -f "$LOCK_FILE"
        exit 0
    fi

    # Close the window
    if rpc_request "window.action" "$(${pkgs.jq}/bin/jq -nc --argjson window_id "$WINDOW_ID" '{window_id:$window_id, action:"kill"}')" >/dev/null; then
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

    # Open detached without Sway IPC.
    ${pkgs.systemd}/bin/systemd-run --user --quiet --collect firefox --new-tab "$URL" >> /tmp/langfuse-debug.log 2>&1 || \
      ${pkgs.xdg-utils}/bin/xdg-open "$URL" &
  '';

  # Keyboard handler script for view switching (Alt+1-7 or just 1-7)

in
{
  inherit focusWindowScript focusAiSessionScript recordAiSessionMruScript
          ackAiSessionSeenScript
          recordAiFocusMetricScript
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
