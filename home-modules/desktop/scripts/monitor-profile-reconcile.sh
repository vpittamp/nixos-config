#!/usr/bin/env bash
# monitor-profile-reconcile - keep Sway outputs aligned with the selected profile.
#
# Used by desktop profile-managed hosts such as Ryzen. Unlike the ThinkPad
# lid-clamshell watcher, this never infers a laptop lid state and never calls
# lid-clamshell; it simply reapplies ~/.config/sway/monitor-profile.current when
# Sway has drifted from that declarative profile.
set -uo pipefail

CONFIG_DIR="${HOME}/.config/sway"
PROFILE_DIR="${CONFIG_DIR}/monitor-profiles"
CURRENT_FILE="${CONFIG_DIR}/monitor-profile.current"
DEFAULT_FILE="${CONFIG_DIR}/monitor-profile.default"

log() {
  printf 'monitor-profile-reconcile: %s\n' "$*" >&2
}

read_profile_name() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  tr -d '\r[:space:]' < "$file" | head -n1
}

current_profile() {
  local profile default_profile

  profile="$(read_profile_name "$CURRENT_FILE" 2>/dev/null || true)"
  if [[ -z "$profile" ]]; then
    profile="$(read_profile_name "$DEFAULT_FILE" 2>/dev/null || true)"
  fi

  if [[ -n "$profile" && -f "$PROFILE_DIR/${profile}.json" ]]; then
    printf '%s\n' "$profile"
    return 0
  fi

  default_profile="$(read_profile_name "$DEFAULT_FILE" 2>/dev/null || true)"
  if [[ -n "$default_profile" && -f "$PROFILE_DIR/${default_profile}.json" ]]; then
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$default_profile" > "$CURRENT_FILE"
    chmod 600 "$CURRENT_FILE" 2>/dev/null || true
    log "replaced invalid profile '${profile:-<empty>}' with default '$default_profile'"
    printf '%s\n' "$default_profile"
    return 0
  fi

  return 1
}

profile_drifted() {
  local profile="$1"
  local profile_path="$PROFILE_DIR/${profile}.json"
  local outputs_json

  [[ -f "$profile_path" ]] || return 1
  outputs_json="$(swaymsg -t get_outputs 2>/dev/null || printf '[]')"

  jq -e --argjson live "$outputs_json" '
    def millis(v): ((v // 0) | tonumber * 1000 | round);
    ($live | map(select(.name != null)) | map({key: .name, value: .}) | from_entries) as $by_name
    | any(.outputs[]?;
        .name as $name
        | (.enabled // true) as $want_enabled
        | ($by_name[$name] // null) as $live_output
        | if $live_output == null then
            false
          elif $want_enabled then
            (($live_output.active // false) | not)
            or (
              (.position // {}) as $pos
              | (($pos.x? != null) and ((($live_output.rect.x // 0) | tonumber) != ($pos.x | tonumber)))
                or (($pos.y? != null) and ((($live_output.rect.y // 0) | tonumber) != ($pos.y | tonumber)))
                or (($pos.width? != null) and ((($live_output.current_mode.width // 0) | tonumber) != ($pos.width | tonumber)))
                or (($pos.height? != null) and ((($live_output.current_mode.height // 0) | tonumber) != ($pos.height | tonumber)))
            )
            or ((.scale? != null) and (millis($live_output.scale) != millis(.scale)))
          else
            ($live_output.active // false)
          end
      )
  ' "$profile_path" >/dev/null 2>&1
}

apply_current_profile() {
  local profile="$1"

  if ! command -v i3pm >/dev/null 2>&1; then
    log "i3pm not found; cannot apply profile '$profile'"
    return 1
  fi

  if ! i3pm display apply "$profile" >/dev/null 2>&1; then
    log "failed to apply profile '$profile'"
    return 1
  fi
}

run_once() {
  local profile

  profile="$(current_profile 2>/dev/null || true)"
  [[ -n "$profile" ]] || return 0

  if profile_drifted "$profile"; then
    apply_current_profile "$profile" || true
  fi
}

case "${1:-watch}" in
  --once|once)
    run_once
    exit 0
    ;;
  --watch|watch)
    ;;
  -h|--help)
    echo "usage: monitor-profile-reconcile [--once|--watch]" >&2
    exit 0
    ;;
  *)
    echo "usage: monitor-profile-reconcile [--once|--watch]" >&2
    exit 1
    ;;
esac

sleep 1
run_once

swaymsg -t subscribe -m '["output"]' 2>/dev/null | while read -r _; do
  sleep 0.4
  run_once
done
