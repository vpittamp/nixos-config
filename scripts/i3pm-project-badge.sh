#!/usr/bin/env bash

# Display a compact I3PM/tmux context badge for prompts, tmux status bars,
# and pane borders. Tmux-facing modes intentionally resolve from pane/tmux
# metadata only so they do not drift from the actual pane being rendered.

set -euo pipefail

mode="plain"
source_mode="${I3PM_PROJECT_BADGE_SOURCE:-auto}"
max_len="${I3PM_PROJECT_BADGE_MAX_LEN:-22}"
pane_pid="${I3PM_PROJECT_BADGE_PANE_PID:-}"
pane_id="${I3PM_PROJECT_BADGE_PANE_ID:-${TMUX_PANE:-}}"
active_context_file="${I3PM_ACTIVE_WORKTREE_FILE:-${HOME}/.config/i3/active-worktree.json}"

project_name=""
project_qualified_name=""
context_variant=""
connection_key=""
terminal_role=""

remote_enabled="false"
remote_host=""
remote_user=""
remote_port="22"

bridge_enabled="false"
bridge_host=""
bridge_user=""
bridge_port="22"
bridge_tmux_pane=""

local_host_alias=""
tmux_window_index=""
tmux_window_name=""
tmux_session_name=""
tmux_pane_id=""

icon_local="󰌽"
icon_ssh="☁"
icon_alias="◈"
icon_role="▣"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmux)
      mode="tmux"
      shift
      ;;
    --tmux-pane)
      mode="tmux-pane"
      shift
      ;;
    --prompt)
      mode="prompt"
      shift
      ;;
    --plain)
      mode="plain"
      shift
      ;;
    --source)
      shift || break
      source_mode="$1"
      shift
      ;;
    --pane-pid)
      shift || break
      pane_pid="$1"
      shift
      ;;
    --pane-id)
      shift || break
      pane_id="$1"
      shift
      ;;
    --max-len)
      shift || break
      max_len="$1"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: i3pm-project-badge.sh [--prompt|--tmux|--tmux-pane|--plain] [--source auto|env|file|pane|hybrid] [--pane-pid PID] [--pane-id %N] [--max-len N]

Modes:
  --prompt     Compact shell-prompt context for tmux panes
  --tmux       Status-line context chip
  --tmux-pane  Pane-border context chip
  --plain      Non-tmux project label fallback

Tmux-facing modes resolve from pane/tmux metadata first and do not fall back to
global daemon context, to avoid stale or cross-pane drift.
EOF
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if ! [[ "$max_len" =~ ^[0-9]+$ ]]; then
  max_len=22
fi

if ! [[ "$source_mode" =~ ^(auto|env|file|pane|hybrid)$ ]]; then
  source_mode="auto"
fi

if (( max_len < 1 )); then
  max_len=1
fi

default_local_host_alias() {
  local host="${I3PM_LOCAL_HOST_ALIAS:-${HOSTNAME:-}}"
  if [[ -z "$host" ]]; then
    host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  fi
  if [[ -z "$host" ]]; then
    host="localhost"
  fi
  printf '%s' "${host,,}"
}

local_host_alias="$(default_local_host_alias)"

is_truthy() {
  local value="${1:-}"
  shopt -s nocasematch
  if [[ "$value" =~ ^(1|true|yes|on)$ ]]; then
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  return 1
}

truncate_text() {
  local text="${1:-}"
  local limit="${2:-22}"
  if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
    limit=22
  fi
  if (( limit < 1 )); then
    limit=1
  fi
  if (( ${#text} <= limit )); then
    printf '%s' "$text"
    return
  fi
  if (( limit == 1 )); then
    printf '…'
    return
  fi
  printf '%s…' "${text:0:limit-1}"
}

env_value_from_block() {
  local block="${1:-}"
  local key="${2:-}"
  printf '%s\n' "$block" | sed -n "s/^${key}=//p" | head -n1
}

derive_project_label() {
  local qualified="${1:-}"
  local label=""

  if [[ -n "$qualified" ]]; then
    if [[ "$qualified" == */*:* ]]; then
      label="${qualified#*/}"
    else
      label="$qualified"
    fi
  fi

  printf '%s' "$label"
}

normalize_role_label() {
  local role="${1:-}"
  case "$role" in
    project-main|main)
      printf 'main'
      ;;
    remote-attach|bridge-attach)
      printf 'attach'
      ;;
    project-app:*)
      printf '%s' "${role#project-app:}"
      ;;
    scratchpad* )
      printf 'scratch'
      ;;
    "" )
      printf ''
      ;;
    * )
      printf '%s' "$role"
      ;;
  esac
}

parse_connection_key() {
  local raw="${1:-}"
  if [[ "$raw" =~ ^local@(.+)$ ]]; then
    printf '%s\t%s\t%s\n' "" "${BASH_REMATCH[1],,}" "22"
    return
  fi
  if [[ "$raw" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
    printf '%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2],,}" "${BASH_REMATCH[3]}"
    return
  fi
  if [[ "$raw" =~ ^([^@]+)@([^:]+)$ ]]; then
    printf '%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2],,}" "22"
    return
  fi
  printf '%s\t%s\t%s\n' "" "" "22"
}

hydrate_remote_from_connection_key() {
  local raw="${1:-}"
  local parsed user host port
  parsed="$(parse_connection_key "$raw")"
  IFS=$'\t' read -r user host port <<<"$parsed"
  unset IFS
  [[ -n "$host" ]] || return 0
  [[ -n "$remote_user" ]] || remote_user="$user"
  [[ -n "$remote_host" ]] || remote_host="$host"
  [[ -n "$remote_port" ]] || remote_port="$port"
}

hydrate_bridge_from_connection_key() {
  local raw="${1:-}"
  local parsed user host port
  parsed="$(parse_connection_key "$raw")"
  IFS=$'\t' read -r user host port <<<"$parsed"
  unset IFS
  [[ -n "$host" ]] || return 0
  [[ -n "$bridge_user" ]] || bridge_user="$user"
  [[ -n "$bridge_host" ]] || bridge_host="$host"
  [[ -n "$bridge_port" ]] || bridge_port="$port"
}

load_context_from_block() {
  local block="${1:-}"

  local value

  value="$(env_value_from_block "$block" "I3PM_PROJECT_NAME")"
  [[ -n "$value" ]] && project_qualified_name="$value"

  value="$(env_value_from_block "$block" "I3PM_CONTEXT_VARIANT")"
  [[ -n "$value" ]] && context_variant="$value"

  value="$(env_value_from_block "$block" "I3PM_CONNECTION_KEY")"
  [[ -n "$value" ]] && connection_key="$value"

  value="$(env_value_from_block "$block" "I3PM_LOCAL_HOST_ALIAS")"
  [[ -n "$value" ]] && local_host_alias="${value,,}"

  value="$(env_value_from_block "$block" "I3PM_TERMINAL_ROLE")"
  [[ -n "$value" ]] && terminal_role="$value"

  value="$(env_value_from_block "$block" "I3PM_REMOTE_ENABLED")"
  [[ -n "$value" ]] && remote_enabled="$value"

  value="$(env_value_from_block "$block" "I3PM_REMOTE_HOST")"
  [[ -n "$value" ]] && remote_host="${value,,}"

  value="$(env_value_from_block "$block" "I3PM_REMOTE_USER")"
  [[ -n "$value" ]] && remote_user="$value"

  value="$(env_value_from_block "$block" "I3PM_REMOTE_PORT")"
  [[ -n "$value" ]] && remote_port="$value"

  value="$(env_value_from_block "$block" "I3PM_REMOTE_SESSION_KEY")"
  if [[ -n "$value" ]]; then
    bridge_enabled="true"
  fi

  value="$(env_value_from_block "$block" "I3PM_REMOTE_SURFACE_KEY")"
  if [[ -n "$value" ]]; then
    bridge_enabled="true"
  fi

  value="$(env_value_from_block "$block" "I3PM_REMOTE_CONNECTION_KEY")"
  if [[ -n "$value" ]]; then
    bridge_enabled="true"
    hydrate_bridge_from_connection_key "$value"
  fi

  value="$(env_value_from_block "$block" "I3PM_REMOTE_HOST")"
  if [[ -n "$value" && "$bridge_enabled" == "true" ]]; then
    bridge_host="${value,,}"
  fi

  value="$(env_value_from_block "$block" "I3PM_REMOTE_USER")"
  [[ -n "$value" && "$bridge_enabled" == "true" ]] && bridge_user="$value"

  value="$(env_value_from_block "$block" "I3PM_REMOTE_PORT")"
  [[ -n "$value" && "$bridge_enabled" == "true" ]] && bridge_port="$value"

  value="$(env_value_from_block "$block" "I3PM_REMOTE_TMUX_PANE")"
  if [[ -n "$value" ]]; then
    bridge_enabled="true"
    bridge_tmux_pane="$value"
  fi

  if [[ -z "$project_name" && -n "$project_qualified_name" ]]; then
    project_name="$(derive_project_label "$project_qualified_name")"
  fi

  if [[ "$context_variant" == "ssh" ]]; then
    remote_enabled="true"
  fi

  if is_truthy "$remote_enabled" && [[ -z "$remote_host" ]]; then
    hydrate_remote_from_connection_key "$connection_key"
  fi
}

load_context_from_env() {
  local env_block
  env_block="$(
    env | awk -F= '
      /^I3PM_(PROJECT_NAME|CONTEXT_VARIANT|CONNECTION_KEY|LOCAL_HOST_ALIAS|TERMINAL_ROLE|REMOTE_ENABLED|REMOTE_HOST|REMOTE_USER|REMOTE_PORT|REMOTE_SESSION_KEY|REMOTE_CONNECTION_KEY|REMOTE_TMUX_PANE)=/ {
        print $0
      }
    '
  )"
  if [[ -z "$env_block" ]]; then
    return 1
  fi
  load_context_from_block "$env_block"
  [[ -n "$project_name" || -n "$tmux_pane_id" || "$bridge_enabled" == "true" ]]
}

load_context_from_pane() {
  local pid="${pane_pid:-}"
  if ! [[ "$pid" =~ ^[0-9]+$ ]] || (( pid <= 1 )); then
    return 1
  fi
  if [[ ! -r "/proc/${pid}/environ" ]]; then
    return 1
  fi

  local proc_env
  proc_env="$(tr '\0' '\n' < "/proc/${pid}/environ" 2>/dev/null || true)"
  if [[ -z "$proc_env" ]]; then
    return 1
  fi

  load_context_from_block "$proc_env"

  local value
  value="$(env_value_from_block "$proc_env" "TMUX_PANE")"
  [[ -n "$value" ]] && tmux_pane_id="$value"

  [[ -n "$project_name" || -n "$tmux_pane_id" || "$bridge_enabled" == "true" ]]
}

tmux_display_message() {
  local format="$1"
  if ! command -v tmux >/dev/null 2>&1; then
    return 1
  fi
  if [[ -n "$pane_id" ]]; then
    tmux display-message -p -t "$pane_id" "$format" 2>/dev/null || true
  else
    tmux display-message -p "$format" 2>/dev/null || true
  fi
}

load_tmux_native() {
  local parsed
  parsed="$(tmux_display_message '#{pane_id}|#{pane_pid}|#{window_index}|#{window_name}|#{session_name}')"
  if [[ -z "$parsed" ]]; then
    return 1
  fi

  local native_pane_id native_pane_pid
  IFS='|' read -r native_pane_id native_pane_pid tmux_window_index tmux_window_name tmux_session_name <<<"$parsed"
  unset IFS

  [[ -n "$pane_id" ]] || pane_id="$native_pane_id"
  [[ -n "$pane_pid" ]] || pane_pid="$native_pane_pid"
  [[ -n "$tmux_pane_id" ]] || tmux_pane_id="$native_pane_id"

  [[ -n "$native_pane_id" ]]
}

load_context_from_tmux_metadata() {
  load_tmux_native || return 1
  [[ -n "$tmux_session_name" ]] || return 1

  local session_env
  session_env="$(tmux show-environment -t "$tmux_session_name" 2>/dev/null || true)"
  if [[ -n "$session_env" ]]; then
    load_context_from_block "$session_env"
  fi

  local option_value
  option_value="$(tmux show-options -t "$tmux_session_name" -qv @i3pm_project_name 2>/dev/null || true)"
  [[ -n "$project_qualified_name" ]] || project_qualified_name="$option_value"
  option_value="$(tmux show-options -t "$tmux_session_name" -qv @i3pm_context_key 2>/dev/null || true)"
  if [[ -n "$option_value" && -z "$connection_key" ]]; then
    connection_key="${option_value##*::}"
  fi
  option_value="$(tmux show-options -t "$tmux_session_name" -qv @i3pm_terminal_role 2>/dev/null || true)"
  [[ -n "$terminal_role" ]] || terminal_role="$option_value"

  if [[ -z "$project_name" && -n "$project_qualified_name" ]]; then
    project_name="$(derive_project_label "$project_qualified_name")"
  fi
  if is_truthy "$remote_enabled" && [[ -z "$remote_host" ]]; then
    hydrate_remote_from_connection_key "$connection_key"
  fi

  [[ -n "$project_name" || -n "$tmux_pane_id" ]]
}

load_context_from_file() {
  local payload=""
  if [[ -f "$active_context_file" ]]; then
    payload="$(cat "$active_context_file" 2>/dev/null || true)"
  elif command -v i3pm >/dev/null 2>&1; then
    payload="$(i3pm context current --json 2>/dev/null || true)"
  fi

  if [[ -z "$payload" ]] || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local parsed
  parsed="$(
    jq -r '
      if type != "object" then empty else
      [
        (.qualified_name // ""),
        (.execution_mode // "local"),
        (.connection_key // ""),
        (.remote.host // ""),
        (.remote.user // ""),
        ((.remote.port // 22) | tostring)
      ] | @tsv
      end
    ' <(printf '%s' "$payload") 2>/dev/null || true
  )"
  if [[ -z "$parsed" ]]; then
    return 1
  fi

  IFS=$'\t' read -r project_qualified_name context_variant connection_key remote_host remote_user remote_port <<<"$parsed"
  unset IFS

  project_name="$(derive_project_label "$project_qualified_name")"
  if [[ "$context_variant" == "ssh" ]]; then
    remote_enabled="true"
  fi
  if is_truthy "$remote_enabled" && [[ -z "$remote_host" ]]; then
    hydrate_remote_from_connection_key "$connection_key"
  fi
  local_host_alias="$(default_local_host_alias)"
  [[ -n "$project_name" ]]
}

resolve_context() {
  case "$mode" in
    tmux|tmux-pane|prompt)
      case "$source_mode" in
        env)
          load_context_from_env || true
          load_tmux_native || true
          ;;
        pane)
          load_context_from_pane || true
          load_context_from_tmux_metadata || true
          ;;
        file)
          load_context_from_tmux_metadata || true
          ;;
        hybrid|auto)
          if ! load_context_from_pane; then
            if ! load_context_from_env; then
              load_context_from_tmux_metadata || true
            else
              load_tmux_native || true
            fi
          else
            load_tmux_native || true
          fi
          ;;
      esac
      ;;
    plain)
      case "$source_mode" in
        env)
          load_context_from_env || true
          ;;
        pane)
          load_context_from_pane || true
          ;;
        file)
          load_context_from_file || true
          ;;
        hybrid|auto)
          if ! load_context_from_env; then
            load_context_from_file || true
          fi
          ;;
      esac
      ;;
  esac

  [[ -n "$project_name" ]] || project_name="$(derive_project_label "$project_qualified_name")"
  terminal_role="$(normalize_role_label "$terminal_role")"
}

primary_host_label() {
  if is_truthy "$bridge_enabled" && [[ -n "$bridge_host" ]]; then
    printf '%s' "$bridge_host"
    return
  fi
  if is_truthy "$remote_enabled" && [[ -n "$remote_host" ]]; then
    printf '%s' "$remote_host"
    return
  fi
  printf '%s' "${local_host_alias:-$(default_local_host_alias)}"
}

primary_pane_id() {
  if is_truthy "$bridge_enabled" && [[ -n "$bridge_tmux_pane" ]]; then
    printf '%s' "$bridge_tmux_pane"
    return
  fi
  if [[ -n "$tmux_pane_id" ]]; then
    printf '%s' "$tmux_pane_id"
    return
  fi
  if [[ -n "$pane_id" ]]; then
    printf '%s' "$pane_id"
    return
  fi
  printf ''
}

host_monogram() {
  local host="${1:-}"
  host="${host##*@}"
  host="${host%%.*}"
  if [[ -z "$host" ]]; then
    printf '?'
    return
  fi
  printf '%s' "${host:0:1}" | tr '[:lower:]' '[:upper:]'
}

build_alias() {
  local pane_ref host_label
  pane_ref="$(primary_pane_id)"
  host_label="$(primary_host_label)"
  if [[ -z "$pane_ref" ]]; then
    printf ''
    return
  fi
  printf '%s%s' "$(host_monogram "$host_label")" "$pane_ref"
}

build_mode_label() {
  local host_label
  host_label="$(primary_host_label)"
  if is_truthy "$bridge_enabled"; then
    printf 'ssh %s' "$host_label"
    return
  fi
  if [[ "$context_variant" == "ssh" ]]; then
    printf 'ssh %s' "$host_label"
    return
  fi
  printf 'local %s' "$host_label"
}

render_plain() {
  if [[ -z "$project_name" ]]; then
    exit 0
  fi
  printf '%s' "$(truncate_text "$project_name" "$max_len")"
}

render_prompt() {
  local alias_label mode_label output
  alias_label="$(build_alias)"
  mode_label="$(build_mode_label)"

  if [[ -z "$alias_label" && -z "$project_name" ]]; then
    exit 0
  fi

  output=""
  [[ -n "$alias_label" ]] && output="$alias_label"
  [[ -n "$project_name" ]] && output="${output:+$output }$project_name"
  [[ -n "$mode_label" ]] && output="${output:+$output }$mode_label"
  printf '%s' "$(truncate_text "$output" "$max_len")"
}

render_tmux_status() {
  local alias_label mode_label project_label
  alias_label="$(build_alias)"
  mode_label="$(truncate_text "$(build_mode_label)" 18)"
  project_label="$(truncate_text "${project_name:-global}" "$max_len")"

  if [[ "$context_variant" == "ssh" || "$bridge_enabled" == "true" ]]; then
    printf '#[fg=colour16 bg=colour114 bold] %s %s ' "$icon_ssh" "$mode_label"
  else
    printf '#[fg=colour16 bg=colour109 bold] %s %s ' "$icon_local" "$mode_label"
  fi

  if [[ -n "$alias_label" ]]; then
    printf '#[fg=colour16 bg=colour159 bold] %s %s ' "$icon_alias" "$alias_label"
  fi
  printf '#[fg=colour230 bg=colour238 bold] %s ' "$project_label"
  printf '#[default]'
}

render_tmux_pane() {
  local alias_label project_label role_label output
  alias_label="$(build_alias)"
  project_label="$(truncate_text "${project_name:-global}" "$max_len")"
  role_label="$(truncate_text "${terminal_role:-pane}" 10)"

  if [[ -n "$terminal_role" ]]; then
    printf '#[fg=colour16 bg=colour180 bold] %s %s ' "$icon_role" "$role_label"
  fi
  if [[ -n "$alias_label" ]]; then
    printf '#[fg=colour16 bg=colour159 bold] %s %s ' "$icon_alias" "$alias_label"
  fi
  printf '#[fg=colour252 bg=colour238] %s #[default]' "$project_label"
}

resolve_context

case "$mode" in
  tmux)
    render_tmux_status
    ;;
  tmux-pane)
    render_tmux_pane
    ;;
  prompt)
    render_prompt
    ;;
  plain)
    render_plain
    ;;
  *)
    render_plain
    ;;
esac
