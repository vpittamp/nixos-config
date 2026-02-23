{ pkgs, ... }:

let
  aiTmuxViewTargetsScript = pkgs.writeShellScriptBin "ai-tmux-view-targets" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ALL_STATES=false
    INCLUDE_UNSEEN_FINISHED=true
    OTEL_FILE=""
    REVIEW_FILE=""
    MAX_TARGETS=0

    usage() {
      cat <<'USAGE'
Usage: ai-tmux-view-targets [options]

Build a normalized JSON list of tmux targets from otel-ai-monitor sessions.

Options:
  --all-states            Include idle/completed OTEL sessions in addition to running ones
  --no-unseen-finished    Exclude finished-unseen retained sessions from review ledger
  --otel-file PATH        Read sessions from PATH instead of $XDG_RUNTIME_DIR/otel-ai-sessions.json
  --review-file PATH      Read review ledger from PATH instead of $XDG_RUNTIME_DIR/eww-monitoring-panel/ai-session-review.json
  --max-targets N         Limit output to N records after dedupe/sort (0 = unlimited)
  -h, --help              Show this help message
USAGE
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all-states)
          ALL_STATES=true
          shift
          ;;
        --no-unseen-finished)
          INCLUDE_UNSEEN_FINISHED=false
          shift
          ;;
        --otel-file)
          OTEL_FILE="''${2:-}"
          shift 2
          ;;
        --review-file)
          REVIEW_FILE="''${2:-}"
          shift 2
          ;;
        --max-targets)
          MAX_TARGETS="''${2:-0}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          printf 'ai-tmux-view-targets: unknown option: %s\n' "$1" >&2
          exit 1
          ;;
      esac
    done

    if ! [[ "$MAX_TARGETS" =~ ^[0-9]+$ ]]; then
      printf 'ai-tmux-view-targets: --max-targets must be a non-negative integer\n' >&2
      exit 1
    fi

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    if [[ -z "$OTEL_FILE" ]]; then
      OTEL_FILE="$RUNTIME_DIR/otel-ai-sessions.json"
    fi
    if [[ -z "$REVIEW_FILE" ]]; then
      REVIEW_FILE="$RUNTIME_DIR/eww-monitoring-panel/ai-session-review.json"
    fi

    if ! command -v tmux >/dev/null 2>&1; then
      printf '[]\n'
      exit 0
    fi

    if [[ ! -f "$OTEL_FILE" && ! -f "$REVIEW_FILE" ]]; then
      printf '[]\n'
      exit 0
    fi

    declare -A TTY_TO_PANE=()
    declare -A PANE_TO_SESSION=()
    declare -A PANE_TO_WINDOW=()

    while IFS='|' read -r pane_tty pane_id pane_session pane_window; do
      [[ -n "$pane_id" ]] || continue
      if [[ -n "$pane_tty" ]]; then
        TTY_TO_PANE["$pane_tty"]="$pane_id"
      fi
      PANE_TO_SESSION["$pane_id"]="$pane_session"
      PANE_TO_WINDOW["$pane_id"]="$pane_window"
    done < <(
      tmux list-panes -a -F '#{pane_tty}|#{pane_id}|#{session_name}|#{window_index}:#{window_name}' 2>/dev/null || true
    )

    OTEL_JSON='{}'
    REVIEW_JSON='{}'
    if [[ -f "$OTEL_FILE" ]]; then
      OTEL_JSON=$(${pkgs.jq}/bin/jq -c '.' "$OTEL_FILE" 2>/dev/null || printf '{}')
    fi
    if [[ -f "$REVIEW_FILE" ]]; then
      REVIEW_JSON=$(${pkgs.jq}/bin/jq -c '.' "$REVIEW_FILE" 2>/dev/null || printf '{}')
    fi

    mapfile -t SESSION_ROWS < <(${pkgs.jq}/bin/jq -cn \
      --argjson otel "$OTEL_JSON" \
      --argjson review "$REVIEW_JSON" \
      --argjson all_states "$ALL_STATES" \
      --argjson include_unseen "$INCLUDE_UNSEEN_FINISHED" '
      ($otel.sessions // []) as $otel_sessions
      | ($review.sessions // {}) as $review_sessions
      | (
          $otel_sessions
          | map(. + {review_pending: false, synthetic: false, finish_marker: ""})
          | map(
              if $all_states
              then .
              else select(
                ((.state // "") | ascii_downcase) == "working"
                or ((.state // "") | ascii_downcase) == "attention"
              )
              end
            )
        ) as $otel_rows
      | (
          if $include_unseen and ($review_sessions | type == "object")
          then (
            $review_sessions
            | to_entries
            | map(.value)
            | map(
                select((.finish_marker // "") != "" and (.seen_marker // "") != (.finish_marker // ""))
                | select((.expires_at // 0) > now)
                | {
                    session_id: "",
                    native_session_id: "",
                    context_fingerprint: "",
                    tool: (.tool // "unknown"),
                    state: (.last_state // "completed"),
                    project: (.project // "unknown"),
                    window_id: (.window_id // null),
                    updated_at: (if (.finished_at // 0) > 0 then ((.finished_at // 0) | todateiso8601) else "" end),
                    review_pending: true,
                    synthetic: true,
                    finish_marker: (.finish_marker // ""),
                    terminal_context: {
                      tmux_session: (.tmux_session // ""),
                      tmux_window: (.tmux_window // ""),
                      tmux_pane: (.tmux_pane // ""),
                      pty: (.pty // "")
                    }
                  }
              )
          )
          else []
          end
        ) as $review_rows
      | ($otel_rows + $review_rows)
      | .[]
      ' 2>/dev/null || true)

    if [[ ''${#SESSION_ROWS[@]} -eq 0 ]]; then
      printf '[]\n'
      exit 0
    fi

    records=()
    for row in "''${SESSION_ROWS[@]}"; do
      tool=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.tool // "unknown"')
      state=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '(.state // "idle") | ascii_downcase')
      project=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.project // "unknown"')
      updated_at=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.updated_at // ""')
      session_id=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.session_id // ""')
      native_session_id=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.native_session_id // ""')
      context_fingerprint=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.context_fingerprint // ""')
      window_id_json=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -c '.window_id // (.terminal_context.window_id // null)')
      review_pending=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.review_pending // false')
      finish_marker=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.finish_marker // ""')

      target_pane=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.terminal_context.tmux_pane // ""')
      pty=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.terminal_context.pty // ""')
      tmux_session=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.terminal_context.tmux_session // ""')
      tmux_window=$(printf '%s' "$row" | ${pkgs.jq}/bin/jq -r '.terminal_context.tmux_window // ""')

      if [[ -n "$target_pane" && -z "''${PANE_TO_SESSION[$target_pane]:-}" ]]; then
        target_pane=""
      fi

      if [[ -z "$target_pane" && -n "$pty" ]]; then
        target_pane="''${TTY_TO_PANE[$pty]:-}"
      fi

      [[ -n "$target_pane" ]] || continue

      if [[ -z "$tmux_session" ]]; then
        tmux_session="''${PANE_TO_SESSION[$target_pane]:-}"
      fi
      if [[ -z "$tmux_window" ]]; then
        tmux_window="''${PANE_TO_WINDOW[$target_pane]:-}"
      fi

      if [[ "$review_pending" == "true" ]]; then
        display_state="finished"
        priority=1
      else
        display_state="$state"
        case "$state" in
          attention)
            priority=3
            ;;
          working)
            priority=2
            ;;
          completed)
            priority=1
            ;;
          *)
            priority=0
            ;;
        esac
      fi

      case "$tool" in
        claude-code)
          tool_label="Claude"
          ;;
        codex)
          tool_label="Codex"
          ;;
        gemini)
          tool_label="Gemini"
          ;;
        *)
          tool_label="AI"
          ;;
      esac

      session_key="$tool|$project|$target_pane"
      label="$tool_label · $display_state · $project · $target_pane"

      record=$( ${pkgs.jq}/bin/jq -nc \
        --arg session_key "$session_key" \
        --arg tool "$tool" \
        --arg state "$state" \
        --arg display_state "$display_state" \
        --arg project "$project" \
        --arg target_pane "$target_pane" \
        --arg tmux_session "$tmux_session" \
        --arg tmux_window "$tmux_window" \
        --arg pty "$pty" \
        --arg updated_at "$updated_at" \
        --arg session_id "$session_id" \
        --arg native_session_id "$native_session_id" \
        --arg context_fingerprint "$context_fingerprint" \
        --arg finish_marker "$finish_marker" \
        --arg label "$label" \
        --argjson priority "$priority" \
        --argjson window_id "$window_id_json" \
        --argjson review_pending "$review_pending" \
        '{
          session_key: $session_key,
          tool: $tool,
          state: $state,
          display_state: $display_state,
          project: $project,
          window_id: $window_id,
          target_pane: $target_pane,
          tmux_session: $tmux_session,
          tmux_window: $tmux_window,
          pty: $pty,
          updated_at: $updated_at,
          priority: $priority,
          session_id: $session_id,
          native_session_id: $native_session_id,
          context_fingerprint: $context_fingerprint,
          finish_marker: $finish_marker,
          review_pending: $review_pending,
          label: $label
        }'
      )
      records+=("$record")
    done

    if [[ ''${#records[@]} -eq 0 ]]; then
      printf '[]\n'
      exit 0
    fi

    printf '%s\n' "''${records[@]}" \
      | ${pkgs.jq}/bin/jq -sc --argjson max_targets "$MAX_TARGETS" '
        map(. + {updated_epoch: ((.updated_at | fromdateiso8601?) // 0)})
        | sort_by(.target_pane, -(.priority // 0), -(.updated_epoch // 0))
        | group_by(.target_pane)
        | map(first)
        | sort_by(-(.priority // 0), -(.updated_epoch // 0), (.project // ""), (.tool // ""))
        | (if $max_targets > 0 then .[:$max_targets] else . end)
        | map(del(.updated_epoch))
      '
  '';

  aiTmuxViewPaneScript = pkgs.writeShellScriptBin "ai-tmux-view-pane" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SOURCE_PANE=""
    LABEL=""
    LINES=120
    INTERVAL="0.6"

    usage() {
      cat <<'USAGE'
Usage: ai-tmux-view-pane --source <pane_id> [--label text] [--lines N] [--interval seconds]
USAGE
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --source)
          SOURCE_PANE="''${2:-}"
          shift 2
          ;;
        --label)
          LABEL="''${2:-}"
          shift 2
          ;;
        --lines)
          LINES="''${2:-120}"
          shift 2
          ;;
        --interval)
          INTERVAL="''${2:-0.6}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          printf 'ai-tmux-view-pane: unknown option: %s\n' "$1" >&2
          exit 1
          ;;
      esac
    done

    if [[ -z "$SOURCE_PANE" ]]; then
      printf 'ai-tmux-view-pane: --source is required\n' >&2
      exit 1
    fi

    if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
      printf 'ai-tmux-view-pane: --lines must be an integer\n' >&2
      exit 1
    fi

    while true; do
      now="$(${pkgs.coreutils}/bin/date +%H:%M:%S)"
      printf '\033[2J\033[H'
      printf 'AI Session Mirror\n'
      if [[ -n "$LABEL" ]]; then
        printf '%s\n' "$LABEL"
      fi
      printf 'Source pane: %s | Updated: %s\n\n' "$SOURCE_PANE" "$now"

      if tmux display-message -p -t "$SOURCE_PANE" '#{pane_id}' >/dev/null 2>&1; then
        pane_dead=$(tmux display-message -p -t "$SOURCE_PANE" '#{pane_dead}' 2>/dev/null || printf '1')
        if [[ "$pane_dead" == "1" ]]; then
          printf 'Source pane is no longer active.\n'
        else
          tmux capture-pane -ep -t "$SOURCE_PANE" -S "-$LINES" 2>/dev/null || printf 'Unable to capture source pane output.\n'
        fi
      else
        printf 'Source pane was not found in tmux.\n'
      fi

      ${pkgs.coreutils}/bin/sleep "$INTERVAL"
    done
  '';

  aiTmuxViewSyncScript = pkgs.writeShellScriptBin "ai-tmux-view-sync" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGETS_CMD="${aiTmuxViewTargetsScript}/bin/ai-tmux-view-targets"
    PANE_CMD="${aiTmuxViewPaneScript}/bin/ai-tmux-view-pane"

    WATCH_MODE=false
    ALL_STATES=false
    NO_UNSEEN_FINISHED=false
    SESSION_NAME="''${AI_TMUX_VIEW_SESSION:-ai-monitor}"
    WINDOW_NAME="''${AI_TMUX_VIEW_WINDOW:-overview}"
    WATCH_INTERVAL="''${AI_TMUX_VIEW_WATCH_INTERVAL:-1.5}"
    PANE_LINES="''${AI_TMUX_VIEW_LINES:-120}"
    PANE_INTERVAL="''${AI_TMUX_VIEW_INTERVAL:-0.6}"
    MAX_PANES="''${AI_TMUX_VIEW_MAX_PANES:-9}"
    OTEL_FILE=""

    usage() {
      cat <<'USAGE'
Usage: ai-tmux-view-sync [options]

Reconcile the AI tmux overview window with current active sessions.

Options:
  --once                  Run one reconciliation pass (default)
  --watch                 Keep reconciling in a loop
  --all-states            Include idle/completed sessions
  --no-unseen-finished    Exclude finished-unseen retained sessions
  --session NAME          Target tmux session name (default: ai-monitor)
  --window NAME           Target tmux window name (default: overview)
  --watch-interval SEC    Loop interval when --watch is enabled (default: 1.5)
  --lines N               Captured lines per mirrored pane (default: 120)
  --pane-interval SEC     Mirror refresh interval (default: 0.6)
  --max-panes N           Maximum panes to render (default: 9)
  --otel-file PATH        Read sessions from explicit file path
  -h, --help              Show this help message
USAGE
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --once)
          WATCH_MODE=false
          shift
          ;;
        --watch)
          WATCH_MODE=true
          shift
          ;;
        --all-states)
          ALL_STATES=true
          shift
          ;;
        --no-unseen-finished)
          NO_UNSEEN_FINISHED=true
          shift
          ;;
        --session)
          SESSION_NAME="''${2:-}"
          shift 2
          ;;
        --window)
          WINDOW_NAME="''${2:-}"
          shift 2
          ;;
        --watch-interval)
          WATCH_INTERVAL="''${2:-1.5}"
          shift 2
          ;;
        --lines)
          PANE_LINES="''${2:-120}"
          shift 2
          ;;
        --pane-interval)
          PANE_INTERVAL="''${2:-0.6}"
          shift 2
          ;;
        --max-panes)
          MAX_PANES="''${2:-9}"
          shift 2
          ;;
        --otel-file)
          OTEL_FILE="''${2:-}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          printf 'ai-tmux-view-sync: unknown option: %s\n' "$1" >&2
          exit 1
          ;;
      esac
    done

    if ! [[ "$MAX_PANES" =~ ^[0-9]+$ ]] || [[ "$MAX_PANES" -lt 1 ]]; then
      printf 'ai-tmux-view-sync: --max-panes must be an integer >= 1\n' >&2
      exit 1
    fi

    if ! [[ "$PANE_LINES" =~ ^[0-9]+$ ]] || [[ "$PANE_LINES" -lt 1 ]]; then
      printf 'ai-tmux-view-sync: --lines must be an integer >= 1\n' >&2
      exit 1
    fi

    ensure_window() {
      tmux start-server >/dev/null 2>&1 || true

      if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" \
          "${pkgs.bash}/bin/bash -lc 'while true; do printf \"\\033[2J\\033[HAI tmux view initializing...\\n\"; ${pkgs.coreutils}/bin/sleep 2; done'" >/dev/null
      fi

      if ! tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' 2>/dev/null | ${pkgs.gnugrep}/bin/grep -Fxq "$WINDOW_NAME"; then
        tmux new-window -d -t "$SESSION_NAME" -n "$WINDOW_NAME" \
          "${pkgs.bash}/bin/bash -lc 'while true; do printf \"\\033[2J\\033[HAI tmux view waiting for sessions...\\n\"; ${pkgs.coreutils}/bin/sleep 2; done'" >/dev/null
      fi

      tmux set-window-option -t "$SESSION_NAME:$WINDOW_NAME" automatic-rename off >/dev/null
      tmux set-window-option -t "$SESSION_NAME:$WINDOW_NAME" remain-on-exit off >/dev/null
    }

    collect_targets() {
      local -a cmd=("$TARGETS_CMD" "--max-targets" "$MAX_PANES")
      if [[ "$ALL_STATES" == "true" ]]; then
        cmd+=("--all-states")
      fi
      if [[ "$NO_UNSEEN_FINISHED" == "true" ]]; then
        cmd+=("--no-unseen-finished")
      fi
      if [[ -n "$OTEL_FILE" ]]; then
        cmd+=("--otel-file" "$OTEL_FILE")
      fi
      "''${cmd[@]}" 2>/dev/null || printf '[]\n'
    }

    reconcile_once() {
      local target_window targets_json target_count pane_target_count fingerprint current_fp
      target_window="$SESSION_NAME:$WINDOW_NAME"

      ensure_window

      targets_json=$(collect_targets)
      if ! printf '%s' "$targets_json" | ${pkgs.jq}/bin/jq -e 'type == "array"' >/dev/null 2>&1; then
        targets_json='[]'
      fi

      target_count=$(printf '%s' "$targets_json" | ${pkgs.jq}/bin/jq 'length')
      fingerprint=$(printf '%s' "$targets_json" | ${pkgs.jq}/bin/jq -c '[.[] | .session_key]')
      current_fp=$(tmux show-options -w -t "$target_window" -v @ai_tmux_view_fingerprint 2>/dev/null || true)

      if [[ "$fingerprint" == "$current_fp" ]]; then
        return 0
      fi

      mapfile -t panes < <(tmux list-panes -t "$target_window" -F '#{pane_id}')
      pane_target_count="$target_count"
      if [[ "$pane_target_count" -lt 1 ]]; then
        pane_target_count=1
      fi

      while [[ ''${#panes[@]} -lt $pane_target_count ]]; do
        tmux split-window -d -t "$target_window" >/dev/null
        mapfile -t panes < <(tmux list-panes -t "$target_window" -F '#{pane_id}')
      done

      while [[ ''${#panes[@]} -gt $pane_target_count ]]; do
        last_idx=$(( ''${#panes[@]} - 1 ))
        tmux kill-pane -t "''${panes[$last_idx]}" >/dev/null
        mapfile -t panes < <(tmux list-panes -t "$target_window" -F '#{pane_id}')
      done

      tmux select-layout -t "$target_window" tiled >/dev/null 2>&1 || true
      mapfile -t panes < <(tmux list-panes -t "$target_window" -F '#{pane_id}')

      if [[ "$target_count" -eq 0 ]]; then
        empty_cmd="${pkgs.bash}/bin/bash -lc 'while true; do printf \"\\033[2J\\033[HAI Session Overview\\n\\nNo active or unread sessions right now.\\n\"; ${pkgs.coreutils}/bin/sleep 2; done'"
        tmux respawn-pane -k -t "''${panes[0]}" "$empty_cmd" >/dev/null
        tmux select-pane -t "''${panes[0]}" -T "idle" >/dev/null 2>&1 || true
        tmux set-option -w -t "$target_window" @ai_tmux_view_fingerprint "$fingerprint" >/dev/null
        return 0
      fi

      for idx in "''${!panes[@]}"; do
        target=$(printf '%s' "$targets_json" | ${pkgs.jq}/bin/jq -c ".[$idx]")
        source_pane=$(printf '%s' "$target" | ${pkgs.jq}/bin/jq -r '.target_pane // ""')
        label=$(printf '%s' "$target" | ${pkgs.jq}/bin/jq -r '.label // "AI Session"')
        state=$(printf '%s' "$target" | ${pkgs.jq}/bin/jq -r '.state // "idle"')
        tool=$(printf '%s' "$target" | ${pkgs.jq}/bin/jq -r '.tool // "ai"')

        quoted_source=$(printf '%q' "$source_pane")
        quoted_label=$(printf '%q' "$label")
        pane_cmd="$PANE_CMD --source $quoted_source --label $quoted_label --lines $PANE_LINES --interval $PANE_INTERVAL"

        tmux respawn-pane -k -t "''${panes[$idx]}" "$pane_cmd" >/dev/null
        tmux select-pane -t "''${panes[$idx]}" -T "[$state] $tool" >/dev/null 2>&1 || true
      done

      tmux set-option -w -t "$target_window" @ai_tmux_view_fingerprint "$fingerprint" >/dev/null
      tmux set-option -w -t "$target_window" @ai_tmux_view_updated "$(${pkgs.coreutils}/bin/date +%s)" >/dev/null
    }

    if [[ "$WATCH_MODE" == "true" ]]; then
      while true; do
        reconcile_once || true
        ${pkgs.coreutils}/bin/sleep "$WATCH_INTERVAL"
      done
    else
      reconcile_once
    fi
  '';

  aiTmuxViewActionScript = pkgs.writeShellScriptBin "ai-tmux-view-action" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SYNC_CMD="${aiTmuxViewSyncScript}/bin/ai-tmux-view-sync"

    SESSION_NAME="''${AI_TMUX_VIEW_SESSION:-ai-monitor}"
    WINDOW_NAME="''${AI_TMUX_VIEW_WINDOW:-overview}"
    WATCH_INTERVAL="''${AI_TMUX_VIEW_WATCH_INTERVAL:-1.5}"
    MAX_PANES="''${AI_TMUX_VIEW_MAX_PANES:-9}"
    ALL_STATES=false
    NO_UNSEEN_FINISHED=false
    OTEL_FILE=""

    usage() {
      cat <<'USAGE'
Usage: ai-tmux-view-action [options]

Open a tmux popup that mirrors all active AI sessions in one view.

Options:
  --all-states            Include idle/completed sessions
  --no-unseen-finished    Exclude finished-unseen retained sessions
  --session NAME          Dashboard tmux session name (default: ai-monitor)
  --window NAME           Dashboard tmux window name (default: overview)
  --watch-interval SEC    Sync loop interval while popup is open (default: 1.5)
  --max-panes N           Maximum panes to render (default: 9)
  --otel-file PATH        Read sessions from explicit file path
  -h, --help              Show this help message
USAGE
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all-states)
          ALL_STATES=true
          shift
          ;;
        --no-unseen-finished)
          NO_UNSEEN_FINISHED=true
          shift
          ;;
        --session)
          SESSION_NAME="''${2:-}"
          shift 2
          ;;
        --window)
          WINDOW_NAME="''${2:-}"
          shift 2
          ;;
        --watch-interval)
          WATCH_INTERVAL="''${2:-1.5}"
          shift 2
          ;;
        --max-panes)
          MAX_PANES="''${2:-9}"
          shift 2
          ;;
        --otel-file)
          OTEL_FILE="''${2:-}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          printf 'ai-tmux-view-action: unknown option: %s\n' "$1" >&2
          exit 1
          ;;
      esac
    done

    sync_args=(
      --once
      --session "$SESSION_NAME"
      --window "$WINDOW_NAME"
      --max-panes "$MAX_PANES"
    )
    if [[ "$ALL_STATES" == "true" ]]; then
      sync_args+=(--all-states)
    fi
    if [[ "$NO_UNSEEN_FINISHED" == "true" ]]; then
      sync_args+=(--no-unseen-finished)
    fi
    if [[ -n "$OTEL_FILE" ]]; then
      sync_args+=(--otel-file "$OTEL_FILE")
    fi

    "$SYNC_CMD" "''${sync_args[@]}" >/dev/null 2>&1 || true

    if [[ -z "''${TMUX:-}" ]]; then
      exec env TMUX= tmux attach-session -r -t "$SESSION_NAME:$WINDOW_NAME"
    fi

    watch_args=(
      --watch
      --session "$SESSION_NAME"
      --window "$WINDOW_NAME"
      --watch-interval "$WATCH_INTERVAL"
      --max-panes "$MAX_PANES"
    )
    if [[ "$ALL_STATES" == "true" ]]; then
      watch_args+=(--all-states)
    fi
    if [[ "$NO_UNSEEN_FINISHED" == "true" ]]; then
      watch_args+=(--no-unseen-finished)
    fi
    if [[ -n "$OTEL_FILE" ]]; then
      watch_args+=(--otel-file "$OTEL_FILE")
    fi

    WATCH_PID=""
    cleanup() {
      if [[ -n "$WATCH_PID" ]] && kill -0 "$WATCH_PID" 2>/dev/null; then
        kill "$WATCH_PID" >/dev/null 2>&1 || true
        wait "$WATCH_PID" >/dev/null 2>&1 || true
      fi
    }
    trap cleanup EXIT INT TERM

    "$SYNC_CMD" "''${watch_args[@]}" >/dev/null 2>&1 &
    WATCH_PID=$!

    popup_cmd="env TMUX= tmux attach-session -r -t '$SESSION_NAME:$WINDOW_NAME'"
    if ! tmux display-popup -E -w 97% -h 92% -T "AI Sessions Overview" "$popup_cmd"; then
      tmux display-message "Popup unavailable, switching to AI overview window"
      tmux switch-client -t "$SESSION_NAME:$WINDOW_NAME" >/dev/null 2>&1 || true
      ${pkgs.coreutils}/bin/sleep 0.5
    fi
  '';
in
{
  inherit aiTmuxViewTargetsScript aiTmuxViewPaneScript aiTmuxViewSyncScript aiTmuxViewActionScript;
}
