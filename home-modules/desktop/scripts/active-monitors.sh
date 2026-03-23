#!/usr/bin/env bash
# active-monitors - Toggle which headless outputs are active and sync wayvnc units
# Usage:
#   active-monitors HEADLESS-1 [HEADLESS-2 ...]
#   active-monitors --profile NAME
#   active-monitors --list-profiles
#
# Designed for hetzner-sway (headless wlroots backend with virtual outputs).
# Steps:
#   1) Enable the requested outputs (create/enable + set layout)
#   2) Disable any other active outputs
#   3) Start/stop matching wayvnc@<output>.service units if they exist
#   4) Output changes automatically trigger sway-config-manager to reassign
#      workspaces using its fallback logic.

set -euo pipefail
DAEMON_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock"

rpc_request() {
  local method="$1"
  local params_json="${2:-{}}"
  local request response
  request=$(jq -nc --arg method "$method" --argjson params "$params_json" \
    '{jsonrpc:"2.0", method:$method, params:$params, id:1}')
  [[ -S "$DAEMON_SOCKET" ]] || { echo "daemon socket not found: $DAEMON_SOCKET" >&2; exit 1; }
  response=$(timeout 2s socat - UNIX-CONNECT:"$DAEMON_SOCKET" <<< "$request" 2>/dev/null || true)
  [[ -n "$response" ]] || { echo "no response from daemon for $method" >&2; exit 1; }
  jq -c '.result' <<< "$response"
}

usage() {
  cat <<'EOF'
Usage:
  active-monitors OUTPUT [OUTPUT...]
  active-monitors --profile NAME
  active-monitors --list-profiles

Options:
  --profile NAME       Load outputs from ~/.config/sway/monitor-profiles/NAME.json
  --list-profiles      List available monitor profiles and exit
  -h, --help           Show this help message

Examples:
  active-monitors HEADLESS-1 HEADLESS-2
  active-monitors --profile triple

Notes:
  - Requires the i3pm daemon to be running in the active session.
  - WayVNC units are started/stopped to match selected outputs when present.
EOF
}

profile_dir="$HOME/.config/sway/monitor-profiles"
profile_name=""
list_profiles=0
declare -a positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      profile_name="${2:-}"
      if [[ -z "$profile_name" ]]; then
        echo "active-monitors: --profile requires a name" >&2
        exit 1
      fi
      shift 2
      ;;
    --list-profiles)
      list_profiles=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if (( list_profiles )); then
  if [[ -d "$profile_dir" ]]; then
    for file in "$profile_dir"/*.json; do
      [[ -f "$file" ]] || continue
      name=$(basename "$file" .json)
      desc=$(jq -r '.description // ""' "$file" 2>/dev/null)
      if [[ -n "$desc" && "$desc" != "null" ]]; then
        printf '%s\t%s\n' "$name" "$desc"
      else
        printf '%s\n' "$name"
      fi
    done
  else
    echo "No monitor profiles found in $profile_dir" >&2
  fi
  exit 0
fi

is_hybrid_mode=0

if [[ -n "$profile_name" ]]; then
  profile_path="$profile_dir/${profile_name%.json}.json"
  if [[ ! -f "$profile_path" ]]; then
    echo "active-monitors: profile '$profile_name' not found in $profile_dir" >&2
    exit 1
  fi

  # Feature 084: Handle both simple (headless) and nested (hybrid) profile formats
  # Simple format: outputs: ["HEADLESS-1", "HEADLESS-2"]
  # Hybrid format: outputs: [{name: "eDP-1", type: "physical", ...}, ...]
  first_output=$(jq -r '.outputs[0]' "$profile_path" 2>/dev/null)
  if [[ "$first_output" == "{"* ]] || jq -e '.outputs[0].name' "$profile_path" >/dev/null 2>&1; then
    is_hybrid_mode=1
    # Hybrid mode profile - extract output names from nested objects
    mapfile -t want < <(jq -r '.outputs[] | .name' "$profile_path" 2>/dev/null)
    # Also extract virtual outputs for create_output
    mapfile -t virtual_outputs < <(jq -r '.outputs[] | select(.type == "virtual") | .name' "$profile_path" 2>/dev/null)
  else
    # Simple headless profile - outputs are just strings
    mapfile -t want < <(jq -r '.outputs[]' "$profile_path" 2>/dev/null)
    virtual_outputs=()
  fi

  if [[ ${#want[@]} -eq 0 ]]; then
    echo "active-monitors: profile '$profile_name' has no outputs" >&2
    exit 1
  fi
elif [[ ${#positional[@]} -gt 0 ]]; then
  want=(${positional[@]})
  virtual_outputs=()
else
  usage
  exit 1
fi

# Capture current outputs (active + all known)
outputs_json="$(rpc_request "outputs.get_state" '{}')"
mapfile -t active_outputs < <(printf '%s' "$outputs_json" | jq -r '.active_outputs[]?')
mapfile -t all_outputs < <(printf '%s' "$outputs_json" | jq -r '.outputs | keys[]')

# Deduplicate requested outputs
declare -A seen
want_unique=()
for o in "${want[@]}"; do
  if [[ -z "${seen[$o]+x}" ]]; then
    seen["$o"]=1
    want_unique+=("$o")
  fi
done
want=("${want_unique[@]}")

# Disable outputs that are currently active but not requested
for out in "${active_outputs[@]}"; do
  skip=false
  for w in "${want[@]}"; do
    [[ "$out" == "$w" ]] && skip=true && break
  done
  if ! $skip; then
    rpc_request "output.configure" "$(jq -nc --arg output_name "$out" '{output_name:$output_name, enabled:false}')" >/dev/null || true
    systemctl --user stop "wayvnc@$out.service" 2>/dev/null || true
  fi
done

# Feature 084: Create virtual outputs dynamically for hybrid mode
if (( is_hybrid_mode )); then
  # Check which virtual outputs need to be created
  for vout in "${virtual_outputs[@]}"; do
    output_exists=false
    for existing in "${all_outputs[@]}"; do
      if [[ "$existing" == "$vout" ]]; then
        output_exists=true
        break
      fi
    done
    if ! $output_exists; then
      # Create the virtual output
      rpc_request "output.create_virtual" '{}' >/dev/null 2>&1 || true
      echo "Created virtual output: $vout"
    fi
  done
  # Refresh output list after creation
  outputs_json="$(rpc_request "outputs.get_state" '{}')"
  mapfile -t all_outputs < <(printf '%s' "$outputs_json" | jq -r '.outputs | keys[]')
fi

# Enable requested outputs and configure them
# Feature 084: Use different settings for physical vs virtual displays
pos_x=0
for out in "${want[@]}"; do
  if (( is_hybrid_mode )); then
    if [[ "$out" == "eDP-1" ]]; then
      # Physical display - Retina resolution with 2x scaling
      rpc_request "output.configure" "$(jq -nc --arg output_name "$out" '{output_name:$output_name, enabled:true, mode:"2560x1600@60Hz", position_x:0, position_y:0, scale:2.0}')" >/dev/null || true
      pos_x=1280  # Account for logical width (2560/2)
    else
      # Virtual display - VNC resolution
      rpc_request "output.configure" "$(jq -nc --arg output_name "$out" --argjson position_x "$pos_x" '{output_name:$output_name, enabled:true, mode:"1920x1080@60Hz", position_x:$position_x, position_y:0, scale:1.0}')" >/dev/null || true
      systemctl --user start "wayvnc@$out.service" 2>/dev/null || true
      pos_x=$((pos_x + 1920))
    fi
  else
    # Headless mode - all outputs are virtual
    rpc_request "output.configure" "$(jq -nc --arg output_name "$out" --argjson position_x "$pos_x" '{output_name:$output_name, enabled:true, mode:"1920x1200@60Hz", position_x:$position_x, position_y:0, scale:1.0}')" >/dev/null || true
    systemctl --user start "wayvnc@$out.service" 2>/dev/null || true
    pos_x=$((pos_x + 1920))
  fi
done

echo "Active outputs set to: ${want[*]}"

# Sway emits an output change event for the daemon; no extra trigger needed.
exit 0
