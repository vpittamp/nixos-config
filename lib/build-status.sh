#!/usr/bin/env bash
# Build status library for NixOS
# Provides reusable functions for build status tracking and error reporting
#
# Source this file in your scripts:
#   source /etc/nixos/lib/build-status.sh

# Ensure bash strict mode if not already set
[[ -z "${BASH_STRICT_MODE:-}" ]] && set -euo pipefail

# Library version
readonly BUILD_STATUS_LIB_VERSION="1.0.0"

# JSON helpers
json_escape() {
  local value="$1"
  # shellcheck disable=SC2001
  value=$(sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' <<< "$value")
  value=$(sed ':a;N;$!ba;s/\n/\\n/g' <<< "$value")
  printf '%s' "$value"
}

json_bool() {
  [[ "$1" == "true" || "$1" == "1" || "$1" == "yes" ]] && echo "true" || echo "false"
}

# Generation info helpers
get_current_generation() {
  if command -v nixos-generation-info &>/dev/null; then
    nixos-generation-info --export | grep "^NIXOS_GENERATION_INFO_GENERATION_RAW=" | cut -d= -f2 | tr -d "'"
  else
    echo "unknown"
  fi
}

get_current_generation_json() {
  if command -v nixos-generation-info &>/dev/null; then
    nixos-generation-info --json
  else
    echo '{}'
  fi
}

get_generation_short() {
  if command -v nixos-generation-info &>/dev/null; then
    nixos-generation-info --short
  else
    echo "unknown"
  fi
}

is_generation_in_sync() {
  if command -v nixos-generation-info &>/dev/null; then
    local status
    status=$(nixos-generation-info --status 2>/dev/null || echo "unknown")
    [[ "$status" == "in-sync" ]]
  else
    return 1  # Unknown state is treated as not in sync
  fi
}

# Build log helpers
get_last_build_status() {
  local log_dir="${1:-/var/log/nixos-builds}"
  local json_file="$log_dir/last-build.json"

  if [[ -f "$json_file" ]]; then
    cat "$json_file"
  else
    echo '{}'
  fi
}

get_last_build_exit_code() {
  local log_dir="${1:-/var/log/nixos-builds}"
  get_last_build_status "$log_dir" | jq -r '.exitCode // 999'
}

was_last_build_successful() {
  local log_dir="${1:-/var/log/nixos-builds}"
  local exit_code
  exit_code=$(get_last_build_exit_code "$log_dir")
  [[ "$exit_code" == "0" ]]
}

get_build_history() {
  local log_dir="${1:-/var/log/nixos-builds}"
  local history_file="$log_dir/build-history.json"

  if [[ -f "$history_file" ]]; then
    cat "$history_file"
  else
    echo '[]'
  fi
}

get_build_history_summary() {
  local log_dir="${1:-/var/log/nixos-builds}"
  local count="${2:-10}"

  get_build_history "$log_dir" | jq -r --arg count "$count" '
    .[-($count | tonumber):] |
    map({
      timestamp: .buildStart,
      target: .target,
      action: .action,
      exitCode: .exitCode,
      duration: .buildDuration,
      generation: .postGeneration.generationRaw
    })
  '
}

# Error extraction helpers
extract_nix_errors() {
  local build_log="$1"

  if [[ ! -f "$build_log" ]]; then
    echo "[]"
    return
  fi

  # Extract error messages from nix build output
  # This handles both legacy and JSON log formats
  local errors=()

  # Extract "error:" lines
  while IFS= read -r line; do
    if [[ "$line" =~ error: ]]; then
      errors+=("$(json_escape "$line")")
    fi
  done < <(grep -i "^error:\|^.*error:" "$build_log" || true)

  # Format as JSON array
  printf '['
  local first=1
  for error in "${errors[@]}"; do
    [[ $first -eq 0 ]] && printf ','
    printf '"%s"' "$error"
    first=0
  done
  printf ']'
}

extract_build_phase() {
  local build_log="$1"

  if [[ ! -f "$build_log" ]]; then
    echo "unknown"
    return
  fi

  # Extract the last build phase mentioned
  grep -o "building '.*'" "$build_log" | tail -1 | sed "s/building '\(.*\)'/\1/" || echo "unknown"
}

# System health checks
check_failed_units() {
  if ! command -v systemctl &>/dev/null; then
    echo "[]"
    return
  fi

  local failed_units
  failed_units=$(systemctl --failed --no-legend --no-pager 2>/dev/null | awk '{print $1}' || true)

  if [[ -z "$failed_units" ]]; then
    echo "[]"
    return
  fi

  # Convert to JSON array
  printf '['
  local first=1
  while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    [[ $first -eq 0 ]] && printf ','
    printf '"%s"' "$(json_escape "$unit")"
    first=0
  done <<< "$failed_units"
  printf ']'
}

check_journal_errors() {
  local since="${1:-1 hour ago}"

  if ! command -v journalctl &>/dev/null; then
    echo "0"
    return
  fi

  journalctl --since "$since" -p err -q --no-pager 2>/dev/null | wc -l || echo "0"
}

# Metadata helpers
get_current_commit() {
  if [[ -f "/run/current-system/etc/nixos-metadata" ]]; then
    # shellcheck disable=SC1091
    source "/run/current-system/etc/nixos-metadata" 2>/dev/null || true
    echo "${GIT_COMMIT:-unknown}"
  else
    echo "unknown"
  fi
}

get_current_nixpkgs_rev() {
  if [[ -f "/run/current-system/etc/nixos-metadata" ]]; then
    # shellcheck disable=SC1091
    source "/run/current-system/etc/nixos-metadata" 2>/dev/null || true
    echo "${NIXPKGS_REV:-unknown}"
  else
    echo "unknown"
  fi
}

get_home_manager_generation() {
  if command -v nixos-generation-info &>/dev/null; then
    nixos-generation-info --export | grep "^NIXOS_GENERATION_INFO_HOME_MANAGER_GENERATION_RAW=" | cut -d= -f2 | tr -d "'"
  else
    echo "unknown"
  fi
}

# Reporting helpers
create_status_report() {
  local format="${1:-json}"  # json or human

  local gen_json
  gen_json=$(get_current_generation_json)

  local failed_units
  failed_units=$(check_failed_units)

  local journal_errors
  journal_errors=$(check_journal_errors "1 hour ago")

  local last_build
  last_build=$(get_last_build_status)

  if [[ "$format" == "json" ]]; then
    cat <<EOF
{
  "version": "$BUILD_STATUS_LIB_VERSION",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "generation": $gen_json,
  "failedUnits": $failed_units,
  "journalErrors": $journal_errors,
  "lastBuild": $last_build,
  "commit": "$(get_current_commit)",
  "nixpkgsRev": "$(get_current_nixpkgs_rev)"
}
EOF
  else
    # Human-readable format
    cat <<EOF
=== NixOS Status Report ===
Generated: $(date)
Hostname: $(hostname)

Generation: $(get_generation_short)
Commit: $(get_current_commit)

Failed Units: $(echo "$failed_units" | jq -r 'length')
Journal Errors (1h): $journal_errors

Last Build Status: $(echo "$last_build" | jq -r 'if .success then "Success" else "Failed" end')
Last Build Time: $(echo "$last_build" | jq -r '.buildStart // "unknown"')
EOF
  fi
}

# Export functions for use in other scripts
export -f json_escape
export -f json_bool
export -f get_current_generation
export -f get_current_generation_json
export -f get_generation_short
export -f is_generation_in_sync
export -f get_last_build_status
export -f get_last_build_exit_code
export -f was_last_build_successful
export -f get_build_history
export -f get_build_history_summary
export -f extract_nix_errors
export -f extract_build_phase
export -f check_failed_units
export -f check_journal_errors
export -f get_current_commit
export -f get_current_nixpkgs_rev
export -f get_home_manager_generation
export -f create_status_report
