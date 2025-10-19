#!/usr/bin/env bash
# Demo: Open VSCode on workspace 4 and Ghostty on workspace 2
# No NixOS rebuild required - uses i3-msg directly

set -euo pipefail

echo "=== Dynamic Workspace Setup Demo ==="
echo "Opening VSCode on workspace 4 and Ghostty on workspace 2..."
echo ""

# Check if i3 is running
if ! i3-msg -t get_version &>/dev/null; then
    echo "ERROR: i3 is not running"
    exit 1
fi

# Workspace 2: Ghostty
echo "1. Launching Ghostty on workspace 2..."
i3-msg "workspace number 2" &>/dev/null
sleep 0.1
i3-msg "exec --no-startup-id ghostty" &>/dev/null
sleep 0.5

# Workspace 4: VSCode
echo "2. Launching VSCode on workspace 4..."
i3-msg "workspace number 4" &>/dev/null
sleep 0.1
i3-msg "exec --no-startup-id code" &>/dev/null
sleep 0.5

# Return to workspace 2
echo "3. Returning to workspace 2..."
i3-msg "workspace number 2" &>/dev/null

echo ""
echo "✓ Setup complete!"
echo ""
echo "Current workspaces:"
i3-msg -t get_workspaces | jq -r '.[] | "  Workspace \(.num): \(.name) - \(if .focused then "FOCUSED" else "background" end)"'

# Show window distribution
echo ""
echo "Window distribution:"
for ws in 2 4; do
    WINDOW_COUNT=$(i3-msg -t get_tree | jq -r "
      .. | select(.type? == \"workspace\" and .num? == $ws)
      | .nodes[] | select(.window_properties?)
    " | jq -s 'length')
    echo "  Workspace $ws: $WINDOW_COUNT window(s)"
done

# Send notification if available
if command -v notify-send &>/dev/null; then
    notify-send -u low "Workspace Setup" "VSCode → Workspace 4\nGhostty → Workspace 2"
fi
