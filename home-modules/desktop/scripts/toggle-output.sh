#!/usr/bin/env bash
# Toggle a single Sway output on/off via state file and restart matching wayvnc
#
# Uses ~/.config/sway/output-states.json to track enabled/disabled state
# since headless outputs in Sway cannot be disabled via DPMS or power commands.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: toggle-output OUTPUT_NAME" >&2
  exit 1
fi

OUT="$1"
STATE_FILE="${HOME}/.config/sway/output-states.json"

# Ensure state file directory exists
mkdir -p "$(dirname "$STATE_FILE")"

# Initialize state file if it doesn't exist
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"version": "1.0", "outputs": {}, "last_updated": "'"$(date -Iseconds)"'"}' > "$STATE_FILE"
fi

# Read current state (default to enabled if not present)
# Note: Can't use // because it treats false as falsy. Use if-then-else instead.
current_state=$(jq -r --arg o "$OUT" 'if .outputs[$o].enabled == null then true else .outputs[$o].enabled end' "$STATE_FILE")

# Toggle state
if [[ "$current_state" == "true" ]]; then
  new_state="false"
  action="disabled"
else
  new_state="true"
  action="enabled"
fi

# Update state file atomically
tmp_file=$(mktemp)
jq --arg o "$OUT" --argjson enabled "$new_state" '
  .outputs[$o] = {enabled: $enabled} |
  .last_updated = (now | todate)
' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"

# Start/stop wayvnc service accordingly
if [[ "$new_state" == "true" ]]; then
  systemctl --user start "wayvnc@$OUT.service" 2>/dev/null || true
else
  systemctl --user stop "wayvnc@$OUT.service" 2>/dev/null || true
fi

echo "$OUT $action"
