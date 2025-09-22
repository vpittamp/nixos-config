#!/usr/bin/env bash
# Helper script for agent messaging

set -euo pipefail

COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"

# Function to send message
send_message() {
    local recipient_type="$1"  # orchestrator, managers, engineers
    local sender="$2"
    local message="$3"

    local timestamp=$(date +%s%N)
    local msg_file="$COORDINATION_DIR/message_queue/$recipient_type/${timestamp}_${sender}.msg"

    cat > "$msg_file" <<EOF
{
    "sender": "$sender",
    "recipient_type": "$recipient_type",
    "timestamp": "$(date -Iseconds)",
    "message": "$message"
}
EOF

    echo "Message sent to $recipient_type queue from $sender"
}

# Function to read messages
read_messages() {
    local queue_type="$1"  # orchestrator, managers, engineers
    local agent_id="${2:-*}"  # Optional: filter by recipient

    local queue_dir="$COORDINATION_DIR/message_queue/$queue_type"

    if [[ ! -d "$queue_dir" ]]; then
        echo "No queue directory: $queue_dir"
        return 1
    fi

    for msg_file in "$queue_dir"/*.msg; do
        if [[ -f "$msg_file" ]]; then
            echo "--- Message ---"
            jq . "$msg_file"
            echo ""

            # Option to mark as read (move to processed)
            if [[ "${MARK_AS_READ:-0}" -eq 1 ]]; then
                mkdir -p "$queue_dir/processed"
                mv "$msg_file" "$queue_dir/processed/"
            fi
        fi
    done
}

# Function to broadcast to all
broadcast() {
    local sender="$1"
    local message="$2"

    send_message "orchestrator" "$sender" "$message"
    send_message "managers" "$sender" "$message"
    send_message "engineers" "$sender" "$message"

    echo "Broadcast sent from $sender"
}

# Main command handler
case "${1:-help}" in
    send)
        if [[ $# -lt 4 ]]; then
            echo "Usage: $0 send <recipient-type> <sender-id> <message>"
            exit 1
        fi
        send_message "$2" "$3" "$4"
        ;;

    read)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 read <queue-type> [agent-id]"
            exit 1
        fi
        read_messages "$2" "${3:-*}"
        ;;

    broadcast)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 broadcast <sender-id> <message>"
            exit 1
        fi
        broadcast "$2" "$3"
        ;;

    clean)
        # Clean processed messages older than 1 hour
        find "$COORDINATION_DIR/message_queue/*/processed" -name "*.msg" -mmin +60 -delete 2>/dev/null || true
        echo "Cleaned old processed messages"
        ;;

    help|*)
        cat <<EOF
Agent Message Helper

Usage: $0 <command> [options]

Commands:
  send <type> <sender> <msg>  - Send message to queue
  read <type> [agent]        - Read messages from queue
  broadcast <sender> <msg>    - Send to all queues
  clean                      - Clean old processed messages
  help                       - Show this help

Queue Types:
  orchestrator - Messages for the orchestrator
  managers     - Messages for project managers
  engineers    - Messages for engineers

Environment:
  COORDINATION_DIR    - Coordination directory (default: ~/coordination)
  MARK_AS_READ       - Move messages to processed after reading (0/1)

Examples:
  # Send message to orchestrator
  $0 send orchestrator manager-nixos-001 "Project completed"

  # Read manager queue
  $0 read managers

  # Broadcast from orchestrator
  $0 broadcast orchestrator-001 "System maintenance at 2 PM"

EOF
        ;;
esac