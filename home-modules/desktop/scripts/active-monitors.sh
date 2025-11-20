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
  - Requires running inside an active Sway session (swaymsg must work).
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

SWAYMSG_BIN="$(command -v swaymsg || true)"
if [[ -z "$SWAYMSG_BIN" ]]; then
  echo "swaymsg not found; ensure Sway is installed and in PATH." >&2
  exit 1
fi

# Feature 084: Detect hybrid mode (M1 with physical + virtual displays)
is_hybrid_mode=0
if [[ "$(hostname)" == "nixos-m1" ]]; then
  is_hybrid_mode=1
fi

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
outputs_json="$("$SWAYMSG_BIN" -t get_outputs)"
mapfile -t active_outputs < <(printf '%s' "$outputs_json" | jq -r '.[] | select(.active == true) | .name')
mapfile -t all_outputs < <(printf '%s' "$outputs_json" | jq -r '.[] | .name')

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
    "$SWAYMSG_BIN" "output $out disable" >/dev/null || true
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
      "$SWAYMSG_BIN" create_output >/dev/null 2>&1 || true
      echo "Created virtual output: $vout"
    fi
  done
  # Refresh output list after creation
  outputs_json="$("$SWAYMSG_BIN" -t get_outputs)"
  mapfile -t all_outputs < <(printf '%s' "$outputs_json" | jq -r '.[] | .name')
fi

# Enable requested outputs and configure them
# Feature 084: Use different settings for physical vs virtual displays
pos_x=0
for out in "${want[@]}"; do
  "$SWAYMSG_BIN" "output $out enable" >/dev/null || true

  if (( is_hybrid_mode )); then
    if [[ "$out" == "eDP-1" ]]; then
      # Physical display - Retina resolution with 2x scaling
      "$SWAYMSG_BIN" "output $out mode 2560x1600@60Hz position 0,0 scale 2.0" >/dev/null || true
      pos_x=1280  # Account for logical width (2560/2)
    else
      # Virtual display - VNC resolution
      "$SWAYMSG_BIN" "output $out mode 1920x1080@60Hz position ${pos_x},0 scale 1.0" >/dev/null || true
      systemctl --user start "wayvnc@$out.service" 2>/dev/null || true
      pos_x=$((pos_x + 1920))
    fi
  else
    # Headless mode - all outputs are virtual
    "$SWAYMSG_BIN" "output $out mode 1920x1200@60Hz position ${pos_x},0 scale 1.0" >/dev/null || true
    systemctl --user start "wayvnc@$out.service" 2>/dev/null || true
    pos_x=$((pos_x + 1920))
  fi
done

echo "Active outputs set to: ${want[*]}"

# Sway emits an output change event for the daemon; no extra trigger needed.
exit 0
