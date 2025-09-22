#!/usr/bin/env bash
# Simplified Tmux Supervisor Dashboard

set -euo pipefail

SUPERVISOR_SESSION="supervisor-dashboard"

# Kill old session if exists
tmux kill-session -t "$SUPERVISOR_SESSION" 2>/dev/null || true

# Create new session
tmux new-session -d -s "$SUPERVISOR_SESSION" -n main

# Get list of sessions (excluding supervisor)
sessions=($(tmux ls -F '#{session_name}' | grep -v "^$SUPERVISOR_SESSION$" || true))

if [[ ${#sessions[@]} -eq 0 ]]; then
    echo "No sessions to monitor"
    exit 1
fi

echo "Monitoring ${#sessions[@]} sessions: ${sessions[*]}"

# Create a pane for each session
for i in "${!sessions[@]}"; do
    session="${sessions[$i]}"

    # Skip first pane (already exists)
    if [[ $i -gt 0 ]]; then
        tmux split-window -t "$SUPERVISOR_SESSION:main" -v
        tmux select-layout -t "$SUPERVISOR_SESSION:main" tiled
    fi

    # Get the pane index for the current pane
    pane_idx=$(( i + 1 ))

    # Show session info in the pane
    tmux send-keys -t "$SUPERVISOR_SESSION:main.$pane_idx" "echo '═══ Session: $session ═══'" Enter
    tmux send-keys -t "$SUPERVISOR_SESSION:main.$pane_idx" "watch -n 2 'tmux capture-pane -t $session -p 2>/dev/null | head -20'" Enter
done

# Add command pane at bottom
tmux split-window -t "$SUPERVISOR_SESSION:main" -v -l 5
cmd_pane=$(tmux list-panes -t "$SUPERVISOR_SESSION:main" -F '#{pane_index}' | tail -1)

tmux send-keys -t "$SUPERVISOR_SESSION:main.$cmd_pane" "echo '═══ COMMAND CENTER ═══'" Enter
tmux send-keys -t "$SUPERVISOR_SESSION:main.$cmd_pane" "echo 'Use: /etc/nixos/scripts/tmux-supervisor/tmux-supervisor-simple.sh broadcast \"message\"'" Enter
tmux send-keys -t "$SUPERVISOR_SESSION:main.$cmd_pane" "echo 'Ready...'" Enter

# Rebalance layout
tmux select-layout -t "$SUPERVISOR_SESSION:main" tiled

# Handle commands
case "${1:-}" in
    broadcast)
        shift
        message="$*"
        echo "Broadcasting: $message"
        for session in "${sessions[@]}"; do
            tmux send-keys -t "$session" "$message" Enter 2>/dev/null || true
        done
        ;;
    attach)
        tmux attach -t "$SUPERVISOR_SESSION"
        ;;
    *)
        echo "Dashboard created. Attach with: tmux attach -t $SUPERVISOR_SESSION"
        ;;
esac