#!/usr/bin/env bash

# Display a compact I3PM project badge for prompts and tmux status bars.
# Supports reading context from environment variables and/or the
# active-worktree context file for tmux reliability.

set -euo pipefail

mode="plain"
source_mode="${I3PM_PROJECT_BADGE_SOURCE:-auto}"
max_len="${I3PM_PROJECT_BADGE_MAX_LEN:-22}"
active_worktree_file="${I3PM_ACTIVE_WORKTREE_FILE:-$HOME/.config/i3/active-worktree.json}"
pane_pid="${I3PM_PROJECT_BADGE_PANE_PID:-}"

project_icon=""
project_name=""
project_qualified_name=""
remote_enabled="false"
remote_host=""
remote_user=""
remote_port="22"
remote_dir=""
local_host_alias=""
icon_local="󰌽"
icon_ssh="☁"

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
    --max-len)
      shift || break
      max_len="$1"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: i3pm-project-badge.sh [--tmux|--tmux-pane|--plain] [--source auto|env|file|pane|hybrid] [--pane-pid PID] [--max-len N]

Reads I3PM_* environment variables and prints a compact badge.
Set I3PM_PROJECT_BADGE_MAX_LEN to override the default length (22 chars).
Set I3PM_PROJECT_BADGE_SOURCE to override source mode (auto/env/file/pane/hybrid).
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

derive_project_label() {
  local qualified="${1:-}"
  local display="${2:-}"
  local label=""

  if [[ -n "$qualified" ]]; then
    if [[ "$qualified" == */*:* ]]; then
      label="${qualified#*/}"
    else
      label="$qualified"
    fi
  elif [[ -n "$display" ]]; then
    label="$display"
  fi

  printf '%s' "$label"
}

hydrate_remote_from_connection_key() {
  local connection_key="${1:-}"

  if [[ -z "$connection_key" ]] || [[ "$connection_key" == local@* ]]; then
    return
  fi

  if [[ "$connection_key" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
    [[ -z "$remote_user" ]] && remote_user="${BASH_REMATCH[1]}"
    [[ -z "$remote_host" ]] && remote_host="${BASH_REMATCH[2]}"
    [[ -z "$remote_port" ]] && remote_port="${BASH_REMATCH[3]}"
    return
  fi

  if [[ "$connection_key" =~ ^([^@]+)@([^:]+)$ ]]; then
    [[ -z "$remote_user" ]] && remote_user="${BASH_REMATCH[1]}"
    [[ -z "$remote_host" ]] && remote_host="${BASH_REMATCH[2]}"
  fi
}

apply_context_variant() {
  local context_variant="${1:-}"
  local connection_key="${2:-}"

  if [[ "$context_variant" == "local" ]]; then
    remote_enabled="false"
    remote_host=""
    remote_user=""
    remote_port="22"
    remote_dir=""
    return
  fi

  if [[ "$context_variant" == "ssh" ]]; then
    remote_enabled="true"
    hydrate_remote_from_connection_key "$connection_key"
  fi
}

env_value_from_block() {
  local block="${1:-}"
  local key="${2:-}"
  printf '%s\n' "$block" | sed -n "s/^${key}=//p" | head -n1
}

load_context_from_env() {
  project_icon="${I3PM_PROJECT_ICON:-}"
  project_qualified_name="${I3PM_PROJECT_NAME:-}"
  project_name="$(derive_project_label "$project_qualified_name" "${I3PM_PROJECT_DISPLAY_NAME:-}")"
  remote_enabled="${I3PM_REMOTE_ENABLED:-false}"
  remote_host="${I3PM_REMOTE_HOST:-}"
  remote_user="${I3PM_REMOTE_USER:-}"
  remote_port="${I3PM_REMOTE_PORT:-22}"
  remote_dir="${I3PM_REMOTE_DIR:-}"
  local_host_alias="${I3PM_LOCAL_HOST_ALIAS:-$local_host_alias}"

  apply_context_variant "${I3PM_CONTEXT_VARIANT:-}" "${I3PM_CONNECTION_KEY:-}"
  if is_truthy "$remote_enabled" && [[ -z "$remote_host" ]]; then
    hydrate_remote_from_connection_key "${I3PM_CONNECTION_KEY:-}"
  fi

  if [[ -n "$project_name" ]] || is_truthy "$remote_enabled"; then
    return 0
  fi

  return 1
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

  project_icon="$(env_value_from_block "$proc_env" "I3PM_PROJECT_ICON")"
  project_qualified_name="$(env_value_from_block "$proc_env" "I3PM_PROJECT_NAME")"
  project_name="$(derive_project_label "$project_qualified_name" "$(env_value_from_block "$proc_env" "I3PM_PROJECT_DISPLAY_NAME")")"
  remote_enabled="$(env_value_from_block "$proc_env" "I3PM_REMOTE_ENABLED")"
  remote_host="$(env_value_from_block "$proc_env" "I3PM_REMOTE_HOST")"
  remote_user="$(env_value_from_block "$proc_env" "I3PM_REMOTE_USER")"
  remote_port="$(env_value_from_block "$proc_env" "I3PM_REMOTE_PORT")"
  remote_dir="$(env_value_from_block "$proc_env" "I3PM_REMOTE_DIR")"
  local_host_alias="$(env_value_from_block "$proc_env" "I3PM_LOCAL_HOST_ALIAS")"
  local_host_alias="${local_host_alias:-$(default_local_host_alias)}"

  remote_enabled="${remote_enabled:-false}"
  remote_port="${remote_port:-22}"

  local context_variant connection_key
  context_variant="$(env_value_from_block "$proc_env" "I3PM_CONTEXT_VARIANT")"
  connection_key="$(env_value_from_block "$proc_env" "I3PM_CONNECTION_KEY")"

  apply_context_variant "$context_variant" "$connection_key"
  if is_truthy "$remote_enabled" && [[ -z "$remote_host" ]]; then
    hydrate_remote_from_connection_key "$connection_key"
  fi

  if [[ -n "$project_name" ]] || is_truthy "$remote_enabled"; then
    return 0
  fi

  return 1
}

load_context_from_file() {
  if [[ ! -f "$active_worktree_file" ]]; then
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local parsed
  parsed="$(
    jq -r '
      if type != "object" then empty else
      [
        (.repo_name // ""),
        (.branch // ""),
        (.qualified_name // ""),
        (.remote.enabled // false | tostring),
        (.remote.host // ""),
        (.remote.user // ""),
        ((.remote.port // 22) | tostring),
        (.remote.remote_dir // "")
      ] | @tsv
      end
    ' "$active_worktree_file" 2>/dev/null || true
  )"

  if [[ -z "$parsed" ]]; then
    return 1
  fi

  local repo_name branch qualified_name
  IFS=$'\t' read -r repo_name branch qualified_name remote_enabled remote_host remote_user remote_port remote_dir <<<"$parsed"
  unset IFS

  project_qualified_name="$qualified_name"
  if [[ -n "$repo_name" ]] && [[ -n "$branch" ]]; then
    project_name="${repo_name}:${branch}"
  elif [[ -n "$qualified_name" ]]; then
    project_name="$(derive_project_label "$qualified_name" "")"
  else
    project_name=""
  fi

  remote_enabled="${remote_enabled:-false}"
  remote_port="${remote_port:-22}"
  local_host_alias="$(default_local_host_alias)"
  project_icon=""
  return 0
}

resolve_context() {
  case "$source_mode" in
    pane)
      load_context_from_pane || true
      ;;
    env)
      load_context_from_env || true
      ;;
    file)
      load_context_from_file || true
      ;;
    hybrid)
      if ! load_context_from_pane; then
        if ! load_context_from_env; then
          load_context_from_file || true
        fi
      fi
      ;;
    auto)
      if ! load_context_from_env; then
        load_context_from_file || true
      fi
      ;;
  esac
}

build_remote_target() {
  local host="${remote_host:-}"
  local port="${remote_port:-22}"
  if [[ -z "$host" ]]; then
    printf 'remote'
    return
  fi
  local target="$host"
  if [[ -n "$remote_user" ]]; then
    target="${remote_user}@${target}"
  fi
  if [[ -n "$port" ]] && [[ "$port" != "22" ]]; then
    printf '%s:%s' "$target" "$port"
  else
    printf '%s' "$target"
  fi
}

build_local_target() {
  local target="${local_host_alias:-}"
  if [[ -z "$target" ]]; then
    target="$(default_local_host_alias)"
  fi
  printf '%s' "$target"
}

render_plain() {
  if [[ -z "$project_name" ]]; then
    exit 0
  fi

  local badge="$project_name"
  if [[ -n "$project_icon" ]]; then
    badge="$project_icon $badge"
  fi
  badge="$(truncate_text "$badge" "$max_len")"
  printf '%s' "$badge"
}

render_tmux_status() {
  if [[ -z "$project_name" ]] && ! is_truthy "$remote_enabled"; then
    exit 0
  fi

  local project_label target_label prefix suffix_budget suffix mode_style project_style
  project_label="$(truncate_text "${project_name:-project}" "$max_len")"

  if is_truthy "$remote_enabled"; then
    target_label="$(truncate_text "$(build_remote_target)" 15)"
    prefix="${icon_ssh} ${target_label}"
    mode_style='#[fg=colour16 bg=colour114 bold]'
    project_style='#[fg=colour230 bg=colour29]'
  else
    target_label="$(truncate_text "$(build_local_target)" 12)"
    prefix="${icon_local} ${target_label}"
    mode_style='#[fg=colour16 bg=colour109 bold]'
    project_style='#[fg=colour223 bg=colour240 bold]'
  fi

  if (( ${#prefix} >= max_len )); then
    prefix="$(truncate_text "$prefix" "$max_len")"
    printf '%s %s #[fg=colour248 bg=colour237]' "$mode_style" "$prefix"
    return
  fi

  suffix_budget=$(( max_len - ${#prefix} - 1 ))
  suffix=""
  if (( suffix_budget > 0 )); then
    suffix="$(truncate_text "$project_label" "$suffix_budget")"
  fi

  if [[ -n "$suffix" ]]; then
    printf '%s %s %s %s #[fg=colour248 bg=colour237]' "$mode_style" "$prefix" "$project_style" "$suffix"
  else
    printf '%s %s #[fg=colour248 bg=colour237]' "$mode_style" "$prefix"
  fi
}

render_tmux_pane() {
  if [[ -z "$project_name" ]] && ! is_truthy "$remote_enabled"; then
    printf '#[fg=colour245 bg=colour236] %s #[fg=colour252 bg=colour238] global #[default]' "$icon_local"
    return
  fi

  local project_label remote_target
  project_label="$(truncate_text "${project_name:-project}" "$max_len")"

  if is_truthy "$remote_enabled"; then
    remote_target="$(build_remote_target)"
    remote_target="$(truncate_text "$remote_target" 14)"
    printf '#[fg=colour16 bg=colour120 bold] %s %s #[fg=colour230 bg=colour29] %s #[default]' "$icon_ssh" "$remote_target" "$project_label"
  else
    printf '#[fg=colour16 bg=colour109 bold] %s %s #[fg=colour252 bg=colour238] %s #[default]' "$icon_local" "$(truncate_text "$(build_local_target)" 10)" "$project_label"
  fi
}

resolve_context

case "$mode" in
  tmux)
    render_tmux_status
    ;;
  tmux-pane)
    render_tmux_pane
    ;;
  plain)
    render_plain
    ;;
  *)
    render_plain
    ;;
esac
