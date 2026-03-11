#!/usr/bin/env bash
# Outputs JSON summary of current Sway outputs based on state file
# Example:
# {"active":["HEADLESS-1"],"enabled":["HEADLESS-1"],"all":["HEADLESS-1","HEADLESS-2","HEADLESS-3"],"active_count":1}
#
# Uses ~/.config/sway/output-states.json to determine which outputs are "active"
# since headless outputs cannot be disabled via DPMS or power commands.

set -euo pipefail

STATE_FILE="${HOME}/.config/sway/output-states.json"
DAEMON_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

daemon_outputs_state() {
  local request response
  request="$(jq -nc '{jsonrpc:"2.0", method:"outputs.get_state", params:{}, id:1}')"
  [[ -S "$DAEMON_SOCKET" ]] || return 1
  response="$(timeout 2s socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)"
  [[ -n "$response" ]] || return 1
  jq -ec '.result' <<< "$response"
}

# Get outputs from daemon cache
outputs_state="$(daemon_outputs_state || echo '{"outputs":{},"active_outputs":[]}')"
outputs_json="$(printf '%s\n' "$outputs_state" | jq -c '[.outputs[]?]')"

# Get all output names from daemon
all_outputs=$(echo "$outputs_json" | jq -r '.[].name')

# Read state file (create default if not exists)
if [[ -f "$STATE_FILE" ]]; then
  state_json=$(cat "$STATE_FILE")
else
  # Default: all outputs enabled
  state_json='{"version": "1.0", "outputs": {}}'
fi

# Build active list based on state file (enabled outputs that are also active in Sway)
active=""
for out in $all_outputs; do
  # Check if output is active in Sway
  is_sway_active=$(echo "$outputs_json" | jq -r --arg o "$out" '.[] | select(.name==$o) | .active')
  # Check if output is enabled in state file (default to true)
  is_state_enabled=$(echo "$state_json" | jq -r --arg o "$out" '.outputs[$o].enabled // true')

  if [[ "$is_sway_active" == "true" && "$is_state_enabled" == "true" ]]; then
    [[ -n "$active" ]] && active="${active},"
    active="${active}${out}"
  fi
done

# Build enabled list (outputs that are enabled in state file)
enabled=""
for out in $all_outputs; do
  is_state_enabled=$(echo "$state_json" | jq -r --arg o "$out" '.outputs[$o].enabled // true')
  if [[ "$is_state_enabled" == "true" ]]; then
    [[ -n "$enabled" ]] && enabled="${enabled},"
    enabled="${enabled}${out}"
  fi
done

# Build all list
all=$(echo "$all_outputs" | paste -sd, -)

# Build JSON arrays
active_list=()
IFS=',' read -ra active_arr <<< "${active}"
for o in "${active_arr[@]}"; do [[ -n "$o" ]] && active_list+=("\"$o\""); done

enabled_list=()
IFS=',' read -ra enabled_arr <<< "${enabled}"
for o in "${enabled_arr[@]}"; do [[ -n "$o" ]] && enabled_list+=("\"$o\""); done

all_list=()
IFS=',' read -ra all_arr <<< "${all}"
for o in "${all_arr[@]}"; do [[ -n "$o" ]] && all_list+=("\"$o\""); done

# Build per-output active map
declare -A amap
for o in "${all_arr[@]}"; do
  [[ -z "$o" ]] && continue
  amap[$o]=false
done
for o in "${active_arr[@]}"; do
  [[ -z "$o" ]] && continue
  amap[$o]=true
done

map_entries=()
for o in "${!amap[@]}"; do
  val=${amap[$o]}
  map_entries+=("\"$o\":${val}")
done
map_json=$(IFS=','; echo "${map_entries[*]}")

printf '{'
printf '"active":[%s],' "$(IFS=,; echo "${active_list[*]}")"
printf '"enabled":[%s],' "$(IFS=,; echo "${enabled_list[*]}")"
printf '"all":[%s],' "$(IFS=,; echo "${all_list[*]}")"
printf '"active_count":%d,' "${#active_list[@]}"
printf '"map":{%s}' "$map_json"
printf '}\n'
