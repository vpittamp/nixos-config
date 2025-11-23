#!/usr/bin/env bash
# SwayNC Action Callback for Claude Code Notifications
# Feature 090: Enhanced Notification Callback
#
# This script is called directly by stop-notification.sh when the user clicks
# the "Return to Window" action button.
#
# Metadata is passed via environment variables (set by stop-notification.sh):
#   CALLBACK_WINDOW_ID - Sway window ID to focus
#   CALLBACK_PROJECT_NAME - i3pm project name to switch to
#   CALLBACK_TMUX_SESSION - tmux session name
#   CALLBACK_TMUX_WINDOW - tmux window index

set -euo pipefail

# Read metadata from environment variables
WINDOW_ID="${CALLBACK_WINDOW_ID:-}"
PROJECT_NAME="${CALLBACK_PROJECT_NAME:-}"
TMUX_SESSION="${CALLBACK_TMUX_SESSION:-}"
TMUX_WINDOW="${CALLBACK_TMUX_WINDOW:-}"

# Validate we have at least a window ID or project name
if [ -z "$WINDOW_ID" ] && [ -z "$PROJECT_NAME" ]; then
    notify-send -u low "Claude Code" "Window context lost - please return to terminal manually"
    exit 0
fi

# Step 1: Switch to i3pm project if specified
# This automatically restores all scoped windows including the Claude Code terminal
# The i3pm daemon will handle ALL window restoration and focusing
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

# Step 2: DO NOT manually focus the window
# If we do `swaymsg [con_id=$ID] focus` on a scratchpad/floating window,
# Sway will bring it to the CURRENT workspace instead of switching to its
# original workspace. This defeats the purpose of project switching.
# The i3pm daemon already handles window focusing as part of project restoration.

# Step 3: Select tmux window if specified
if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ]; then
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux select-window -t "${TMUX_SESSION}:${TMUX_WINDOW}" 2>/dev/null || true
    fi
fi

exit 0
