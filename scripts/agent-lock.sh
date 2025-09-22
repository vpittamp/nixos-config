#!/usr/bin/env bash
# Agent lock management for conflict prevention

set -euo pipefail

COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"
LOCK_DIR="$COORDINATION_DIR/agent_locks"

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Function to acquire file lock
acquire_file_lock() {
    local agent_id="$1"
    local file_path="$2"
    local lock_file="$LOCK_DIR/file_$(echo "$file_path" | md5sum | cut -d' ' -f1).lock"

    # Check if lock exists
    if [[ -f "$lock_file" ]]; then
        local current_owner=$(jq -r '.agent_id' "$lock_file" 2>/dev/null || echo "unknown")
        local lock_age_minutes=$(( ($(date +%s) - $(stat -c %Y "$lock_file")) / 60 ))

        # Auto-release stale locks (older than 30 minutes)
        if [[ $lock_age_minutes -gt 30 ]]; then
            echo "Releasing stale lock on $file_path (age: ${lock_age_minutes}m)"
            rm "$lock_file"
        else
            echo "File is locked by: $current_owner (age: ${lock_age_minutes}m)"
            return 1
        fi
    fi

    # Create lock
    cat > "$lock_file" <<EOF
{
    "agent_id": "$agent_id",
    "file_path": "$file_path",
    "locked_at": "$(date -Iseconds)",
    "pid": $$
}
EOF

    echo "Lock acquired on $file_path for $agent_id"
    return 0
}

# Function to release file lock
release_file_lock() {
    local agent_id="$1"
    local file_path="$2"
    local lock_file="$LOCK_DIR/file_$(echo "$file_path" | md5sum | cut -d' ' -f1).lock"

    if [[ ! -f "$lock_file" ]]; then
        echo "No lock found for $file_path"
        return 1
    fi

    local current_owner=$(jq -r '.agent_id' "$lock_file" 2>/dev/null || echo "unknown")

    if [[ "$current_owner" != "$agent_id" ]]; then
        echo "Cannot release lock owned by: $current_owner"
        return 1
    fi

    rm "$lock_file"
    echo "Lock released on $file_path"
    return 0
}

# Function to list all locks
list_locks() {
    local lock_type="${1:-all}"  # all, agent, file

    echo "Current Locks:"
    echo "=============="

    case "$lock_type" in
        agent)
            echo "Agent Locks:"
            for lock in "$LOCK_DIR"/*.lock; do
                if [[ -f "$lock" ]] && [[ "$(basename "$lock")" != file_* ]]; then
                    local agent_id=$(jq -r '.agent_id' "$lock" 2>/dev/null || echo "unknown")
                    local created=$(jq -r '.created_at' "$lock" 2>/dev/null || echo "unknown")
                    echo "  • $agent_id (created: $created)"
                fi
            done
            ;;

        file)
            echo "File Locks:"
            for lock in "$LOCK_DIR"/file_*.lock; do
                if [[ -f "$lock" ]]; then
                    local agent_id=$(jq -r '.agent_id' "$lock" 2>/dev/null || echo "unknown")
                    local file_path=$(jq -r '.file_path' "$lock" 2>/dev/null || echo "unknown")
                    echo "  • $file_path locked by $agent_id"
                fi
            done
            ;;

        all|*)
            # Show both types
            "$0" list agent
            echo ""
            "$0" list file
            ;;
    esac
}

# Function to clean stale locks
clean_stale_locks() {
    local max_age_minutes="${1:-120}"  # Default: 2 hours

    echo "Cleaning locks older than $max_age_minutes minutes..."

    local cleaned=0
    for lock in "$LOCK_DIR"/*.lock; do
        if [[ -f "$lock" ]]; then
            local lock_age_minutes=$(( ($(date +%s) - $(stat -c %Y "$lock")) / 60 ))

            if [[ $lock_age_minutes -gt $max_age_minutes ]]; then
                echo "Removing stale lock: $(basename "$lock") (age: ${lock_age_minutes}m)"
                rm "$lock"
                ((cleaned++))
            fi
        fi
    done

    echo "Cleaned $cleaned stale locks"
}

# Function to check if agent can work on file
can_work_on() {
    local agent_id="$1"
    local file_path="$2"
    local lock_file="$LOCK_DIR/file_$(echo "$file_path" | md5sum | cut -d' ' -f1).lock"

    if [[ ! -f "$lock_file" ]]; then
        echo "true"  # No lock, can work
        return 0
    fi

    local current_owner=$(jq -r '.agent_id' "$lock_file" 2>/dev/null || echo "unknown")

    if [[ "$current_owner" == "$agent_id" ]]; then
        echo "true"  # Own the lock, can work
        return 0
    fi

    echo "false"  # Locked by someone else
    return 1
}

# Main command handler
case "${1:-help}" in
    acquire)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 acquire <agent-id> <file-path>"
            exit 1
        fi
        acquire_file_lock "$2" "$3"
        ;;

    release)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 release <agent-id> <file-path>"
            exit 1
        fi
        release_file_lock "$2" "$3"
        ;;

    check)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 check <agent-id> <file-path>"
            exit 1
        fi
        can_work_on "$2" "$3"
        ;;

    list)
        list_locks "${2:-all}"
        ;;

    clean)
        clean_stale_locks "${2:-120}"
        ;;

    help|*)
        cat <<EOF
Agent Lock Manager

Usage: $0 <command> [options]

Commands:
  acquire <agent> <file>  - Acquire lock on file
  release <agent> <file>  - Release lock on file
  check <agent> <file>    - Check if agent can work on file
  list [type]            - List locks (all/agent/file)
  clean [minutes]        - Clean stale locks
  help                   - Show this help

Environment:
  COORDINATION_DIR - Coordination directory (default: ~/coordination)

Examples:
  # Acquire lock on file
  $0 acquire engineer-001 /etc/nixos/configuration.nix

  # Check if can work
  $0 check engineer-002 /etc/nixos/configuration.nix

  # List all locks
  $0 list

  # Clean locks older than 1 hour
  $0 clean 60

EOF
        ;;
esac