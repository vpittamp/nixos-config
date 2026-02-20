#!/usr/bin/env bash

# Display a compact I3PM project badge for prompts and tmux status bars.
# Supports reading context from environment variables and/or the
# active-worktree context file for tmux reliability.

set -euo pipefail

mode="plain"
source_mode="${I3PM_PROJECT_BADGE_SOURCE:-auto}"
max_len="${I3PM_PROJECT_BADGE_MAX_LEN:-22}"
active_worktree_file="${I3PM_ACTIVE_WORKTREE_FILE:-$HOME/.config/i3/active-worktree.json}"

project_icon=""
project_name=""
remote_enabled="false"
remote_host=""
remote_user=""
remote_port="22"
remote_dir=""

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
    --max-len)
      shift || break
      max_len="$1"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: i3pm-project-badge.sh [--tmux|--tmux-pane|--plain] [--source auto|env|file] [--max-len N]

Reads I3PM_* environment variables and prints a compact badge.
Set I3PM_PROJECT_BADGE_MAX_LEN to override the default length (22 chars).
Set I3PM_PROJECT_BADGE_SOURCE to override source mode (auto/env/file).
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

if ! [[ "$source_mode" =~ ^(auto|env|file)$ ]]; then
  source_mode="auto"
fi

if (( max_len < 1 )); then
  max_len=1
fi

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

load_context_from_env() {
  project_icon="${I3PM_PROJECT_ICON:-}"
  project_name="${I3PM_PROJECT_DISPLAY_NAME:-${I3PM_PROJECT_NAME:-}}"
  remote_enabled="${I3PM_REMOTE_ENABLED:-false}"
  remote_host="${I3PM_REMOTE_HOST:-}"
  remote_user="${I3PM_REMOTE_USER:-}"
  remote_port="${I3PM_REMOTE_PORT:-22}"
  remote_dir="${I3PM_REMOTE_DIR:-}"

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

  if [[ -n "$repo_name" ]] && [[ -n "$branch" ]]; then
    project_name="${repo_name}:${branch}"
  elif [[ -n "$qualified_name" ]]; then
    project_name="$qualified_name"
  else
    project_name=""
  fi

  project_icon=""
  return 0
}

resolve_context() {
  case "$source_mode" in
    env)
      load_context_from_env || true
      ;;
    file)
      load_context_from_file || true
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
  if [[ -n "$port" ]] && [[ "$port" != "22" ]]; then
    printf '%s:%s' "$host" "$port"
  else
    printf '%s' "$host"
  fi
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

  local project_label remote_target prefix suffix_budget suffix
  project_label="$(truncate_text "${project_name:-project}" "$max_len")"

  if is_truthy "$remote_enabled"; then
    remote_target="$(build_remote_target)"
    prefix="SSH ${remote_target}"
    if (( ${#prefix} >= max_len )); then
      prefix="$(truncate_text "$prefix" "$max_len")"
      printf '#[fg=colour16 bg=colour114 bold] %s #[fg=colour248 bg=colour237]' "$prefix"
      return
    fi

    suffix_budget=$(( max_len - ${#prefix} - 1 ))
    suffix=""
    if (( suffix_budget > 0 )); then
      suffix="$(truncate_text "$project_label" "$suffix_budget")"
    fi

    if [[ -n "$suffix" ]]; then
      printf '#[fg=colour16 bg=colour114 bold] %s #[fg=colour230 bg=colour29] %s #[fg=colour248 bg=colour237]' "$prefix" "$suffix"
    else
      printf '#[fg=colour16 bg=colour114 bold] %s #[fg=colour248 bg=colour237]' "$prefix"
    fi
    return
  fi

  printf '#[fg=colour223 bg=colour240 bold] %s #[fg=colour248 bg=colour237]' "$project_label"
}

render_tmux_pane() {
  if [[ -z "$project_name" ]] && ! is_truthy "$remote_enabled"; then
    printf '#[fg=colour245 bg=colour236] LOCAL #[fg=colour252 bg=colour238] global #[default]'
    return
  fi

  local project_label remote_target
  project_label="$(truncate_text "${project_name:-project}" "$max_len")"

  if is_truthy "$remote_enabled"; then
    remote_target="$(build_remote_target)"
    remote_target="$(truncate_text "$remote_target" 20)"
    printf '#[fg=colour16 bg=colour120 bold] SSH #[fg=colour16 bg=colour151 bold] %s #[fg=colour230 bg=colour29] %s #[default]' "$remote_target" "$project_label"
  else
    printf '#[fg=colour16 bg=colour109 bold] LOCAL #[fg=colour252 bg=colour238] %s #[default]' "$project_label"
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
