#!/usr/bin/env bash
# SwayNC Action Callback for Claude Code Notifications
# Feature 090: Enhanced Notification Callback
#
# This script is triggered by SwayNC when the user clicks the "Return to Window"
# action button or presses Enter on a Claude Code notification.
#
# SwayNC provides environment variables:
#   SWAYNC_BODY - Notification body text
#   SWAYNC_SUMMARY - Notification summary/title
#   SWAYNC_ID - Notification ID
#
# We store the window context in a state file that the notification can reference.

set -euo pipefail

# Parse notification metadata from SWAYNC_BODY
# The stop-notification.sh script embeds metadata in the body as:
# WINDOW_ID:PROJECT_NAME:TMUX_SESSION:TMUX_WINDOW

# Extract metadata file path from notification ID
STATE_FILE="/tmp/claude-code-notification-${SWAYNC_ID}.meta"

if [ ! -f "$STATE_FILE" ]; then
    # No metadata file - try to extract from notification body
    # This is a fallback in case the state file was cleaned up
    notify-send -u low "Claude Code" "Window context lost - please return to terminal manually"
    exit 0
fi

# Read metadata
WINDOW_ID=$(grep "^WINDOW_ID=" "$STATE_FILE" | cut -d= -f2)
PROJECT_NAME=$(grep "^PROJECT_NAME=" "$STATE_FILE" | cut -d= -f2)
TMUX_SESSION=$(grep "^TMUX_SESSION=" "$STATE_FILE" | cut -d= -f2)
TMUX_WINDOW=$(grep "^TMUX_WINDOW=" "$STATE_FILE" | cut -d= -f2)

# Clean up state file
rm -f "$STATE_FILE"

# Check if window still exists
WINDOW_EXISTS=$(swaymsg -t get_tree | jq -r --arg id "$WINDOW_ID" '
    .. | objects | select(.type=="con") | select(.id == ($id | tonumber)) | .id
' | head -1)

if [ -z "$WINDOW_EXISTS" ]; then
    notify-send -u critical "Claude Code Terminal Unavailable" \
        "The terminal window running Claude Code has been closed."
    exit 0
fi

# Switch to i3pm project if specified
if [ -n "$PROJECT_NAME" ]; then
    if systemctl --user is-active i3-project-event-listener >/dev/null 2>&1; then
        # Feature 091 US3 T033: Log project switch timing
        SWITCH_START=$(date +%s%N)

        i3pm project switch "$PROJECT_NAME" 2>/dev/null || true

        # Feature 091: Wait for project switch to complete
        # With Feature 091 optimizations, project switching completes in <200ms.
        # We wait 1 second to ensure the switch is fully complete before focusing.
        # Previous requirement: Would have been 6s for 5.3s baseline performance.
        # Current requirement: 1s is sufficient with <200ms optimized switching.
        sleep 1

        # Feature 091 US3 T033: Calculate total callback time
        SWITCH_END=$(date +%s%N)
        SWITCH_DURATION_MS=$(( (SWITCH_END - SWITCH_START) / 1000000 ))

        # Log to systemd journal (visible with: journalctl --user -t claude-callback)
        logger -t claude-callback "[Feature 091] Notification callback completed in ${SWITCH_DURATION_MS}ms (project: $PROJECT_NAME)"
    fi
fi

# Focus terminal window
swaymsg "[con_id=$WINDOW_ID] focus" >/dev/null 2>&1 || true

# Select tmux window if specified
if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
    fi
fi

exit 0
