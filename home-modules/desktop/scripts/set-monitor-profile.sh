#!/usr/bin/env bash
# set-monitor-profile - Apply a monitor profile and persist selection.

set -euo pipefail

PROFILE_DIR="${HOME}/.config/sway/monitor-profiles"
CURRENT_FILE="${HOME}/.config/sway/monitor-profile.current"
STATE_FILE="${HOME}/.config/sway/output-states.json"
ALL_HEADLESS_OUTPUTS="${ALL_HEADLESS_OUTPUTS:-HEADLESS-1 HEADLESS-2 HEADLESS-3}"

usage() {
  cat <<'USAGE'
Usage: set-monitor-profile [--apply-only] PROFILE

Options:
  --apply-only    Apply outputs without updating monitor-profile.current
  -h, --help      Show this help message

Examples:
  set-monitor-profile single
  set-monitor-profile dual
USAGE
}

APPLY_ONLY=0
PROFILE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply-only)
      APPLY_ONLY=1
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
      PROFILE_NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "$PROFILE_NAME" ]]; then
  usage
  exit 1
fi

PROFILE_NAME="${PROFILE_NAME%.json}"
PROFILE_PATH="$PROFILE_DIR/${PROFILE_NAME}.json"

if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "set-monitor-profile: profile '$PROFILE_NAME' not found in $PROFILE_DIR" >&2
  exit 1
fi

mapfile -t PROFILE_OUTPUTS < <(jq -r '.outputs[]' "$PROFILE_PATH" 2>/dev/null)

if [[ ${#PROFILE_OUTPUTS[@]} -eq 0 ]]; then
  echo "set-monitor-profile: profile '$PROFILE_NAME' has no outputs" >&2
  exit 1
fi

# Apply via active-monitors (handles WayVNC + layout)
"${HOME}/.local/bin/active-monitors" --profile "$PROFILE_NAME"

# Feature 083: The daemon now handles output-states.json updates.
# The daemon watches monitor-profile.current for changes and automatically
# updates output-states.json via MonitorProfileService.handle_profile_change().
# This removes the need for embedded Python in this script.

mkdir -p "$(dirname "$CURRENT_FILE")"
if [[ -f "$CURRENT_FILE" && ! -w "$CURRENT_FILE" ]]; then
  chmod u+rw "$CURRENT_FILE" >/dev/null 2>&1 || true
fi
if (( APPLY_ONLY == 0 )); then
  printf "%s\n" "$PROFILE_NAME" > "$CURRENT_FILE"
else
  if [[ ! -f "$CURRENT_FILE" ]]; then
    printf "%s\n" "$PROFILE_NAME" > "$CURRENT_FILE"
  fi
fi
