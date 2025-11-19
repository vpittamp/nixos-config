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

# Update output-states.json so daemon respects the selection
export PROFILE_OUTPUTS_JSON="$(jq -c '.outputs' "$PROFILE_PATH" 2>/dev/null)"
export STATE_FILE
export ALL_HEADLESS_OUTPUTS
python3 - <<'PY'
import json
import os
from datetime import datetime
from pathlib import Path

selected = json.loads(os.environ["PROFILE_OUTPUTS_JSON"])
all_outputs = os.environ.get("ALL_HEADLESS_OUTPUTS", "").split()
state_path = Path(os.environ["STATE_FILE"])
state_path.parent.mkdir(parents=True, exist_ok=True)

try:
    data = json.loads(state_path.read_text())
except Exception:
    data = {}

outputs = data.get("outputs")
if not isinstance(outputs, dict):
    outputs = {}
    data["outputs"] = outputs

changed = False
for name in all_outputs:
    should_enable = name in selected
    entry = outputs.get(name, {})
    current = None
    if isinstance(entry, dict):
        current = entry.get("enabled")
    elif isinstance(entry, bool):
        current = entry
    if current is None or bool(current) != should_enable:
        changed = True
    outputs[name] = {"enabled": should_enable}

if data.get("version") != "1.0":
    data["version"] = "1.0"
    changed = True

if data.get("managed_by") != "monitor-profile":
    data["managed_by"] = "monitor-profile"
    changed = True

if changed:
    data["last_updated"] = datetime.now().isoformat()
    state_path.write_text(json.dumps(data, indent=2))
PY

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
