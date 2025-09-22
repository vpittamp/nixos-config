#!/usr/bin/env bash
# Multi-Agent Claude/Codex Orchestrator
# Manages hierarchical AI agents using tmux for coordination

set -euo pipefail

# Configuration
ORCHESTRATOR_SESSION="agent-orchestrator"
COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"
ORCHESTRATOR_CLI="${ORCHESTRATOR_CLI:-claude}"  # Can be 'claude' or 'codex-cli'
DEBUG="${DEBUG:-0}"

# Default agent settings
DEFAULT_ORCHESTRATOR_MODEL="${DEFAULT_ORCHESTRATOR_MODEL:-claude-opus-4-1-20250805}"
DEFAULT_MANAGER_MODEL="${DEFAULT_MANAGER_MODEL:-claude-opus-4-1-20250805}"
DEFAULT_ENGINEER_MODEL="${DEFAULT_ENGINEER_MODEL:-claude-sonnet-4-20250522}"
DEFAULT_MANAGERS="${DEFAULT_MANAGERS:-nixos,backstage,stacks}"
DEFAULT_ENGINEERS_PER_MANAGER="${DEFAULT_ENGINEERS_PER_MANAGER:-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_debug() {
    [[ "$DEBUG" -eq 1 ]] && echo -e "${CYAN}[DEBUG]${NC} $*" >&2
}

# Check prerequisites
check_prerequisites() {
    local missing_tools=()

    # Check for tmux
    if ! command -v tmux &> /dev/null; then
        missing_tools+=("tmux")
    fi

    # Check for the selected CLI tool
    if ! command -v "$ORCHESTRATOR_CLI" &> /dev/null; then
        missing_tools+=("$ORCHESTRATOR_CLI")
    fi

    # Check for jq for JSON manipulation
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them first"
        exit 1
    fi

    # Ensure coordination directory exists
    if [[ ! -d "$COORDINATION_DIR" ]]; then
        log_info "Creating coordination directory: $COORDINATION_DIR"
        mkdir -p "$COORDINATION_DIR"/{agent_locks,message_queue/{orchestrator,managers,engineers},shared_memory}

        # Initialize registry files if they don't exist
        if [[ ! -f "$COORDINATION_DIR/active_work_registry.json" ]]; then
            echo '{"version":"1.0.0","orchestrator":{},"managers":{},"engineers":{},"assignments":[],"locks":[]}' \
                > "$COORDINATION_DIR/active_work_registry.json"
        fi

        if [[ ! -f "$COORDINATION_DIR/completed_work_log.json" ]]; then
            echo '{"version":"1.0.0","completed_tasks":[]}' \
                > "$COORDINATION_DIR/completed_work_log.json"
        fi
    fi
}

# Generate unique agent ID
generate_agent_id() {
    local agent_type="$1"
    local agent_name="${2:-default}"
    echo "${agent_type}-${agent_name}-$$-$(date +%s)"
}

# Create agent lock
create_agent_lock() {
    local agent_id="$1"
    local lock_file="$COORDINATION_DIR/agent_locks/${agent_id}.lock"

    if [[ -f "$lock_file" ]]; then
        log_warning "Lock already exists for $agent_id"
        return 1
    fi

    cat > "$lock_file" <<EOF
{
    "agent_id": "$agent_id",
    "pid": $$,
    "created_at": "$(date -Iseconds)",
    "tmux_session": "$ORCHESTRATOR_SESSION",
    "host": "$(hostname)"
}
EOF
    log_debug "Created lock for $agent_id"
}

# Remove agent lock
remove_agent_lock() {
    local agent_id="$1"
    local lock_file="$COORDINATION_DIR/agent_locks/${agent_id}.lock"

    if [[ -f "$lock_file" ]]; then
        rm "$lock_file"
        log_debug "Removed lock for $agent_id"
    fi
}

# Clean up stale locks (older than 2 hours)
cleanup_stale_locks() {
    log_info "Cleaning up stale locks..."
    find "$COORDINATION_DIR/agent_locks" -name "*.lock" -type f -mmin +120 -delete
}

# Update work registry
update_registry() {
    local agent_id="$1"
    local agent_type="$2"
    local status="$3"
    local task="${4:-null}"

    local registry_file="$COORDINATION_DIR/active_work_registry.json"
    local timestamp=$(date -Iseconds)

    # Use jq to update the registry
    jq --arg id "$agent_id" \
       --arg type "$agent_type" \
       --arg status "$status" \
       --arg task "$task" \
       --arg ts "$timestamp" \
       '.last_updated = $ts |
        if $type == "orchestrator" then
            .orchestrator = {"id": $id, "status": $status, "current_task": $task}
        elif $type == "manager" then
            .managers[$id] = {"status": $status, "current_task": $task, "updated_at": $ts}
        elif $type == "engineer" then
            .engineers[$id] = {"status": $status, "current_task": $task, "updated_at": $ts}
        else . end' \
        "$registry_file" > "${registry_file}.tmp" && mv "${registry_file}.tmp" "$registry_file"
}

# Send message to agent
send_message_to_agent() {
    local target_pane="$1"
    local message="$2"

    log_debug "Sending to $target_pane: $message"

    # Send message via tmux
    tmux send-keys -t "$ORCHESTRATOR_SESSION:$target_pane" "$message" Enter 2>/dev/null || {
        log_error "Failed to send message to $target_pane"
        return 1
    }
}

# Write message to queue
write_to_queue() {
    local queue_dir="$1"
    local sender="$2"
    local message="$3"

    local msg_file="$COORDINATION_DIR/message_queue/$queue_dir/$(date +%s%N)_${sender}.msg"

    cat > "$msg_file" <<EOF
{
    "sender": "$sender",
    "timestamp": "$(date -Iseconds)",
    "message": "$message"
}
EOF

    log_debug "Message queued in $queue_dir from $sender"
}

# Launch orchestrator agent
launch_orchestrator() {
    local agent_id=$(generate_agent_id "orchestrator" "main")

    log_info "Launching orchestrator: $agent_id"

    # Create tmux window for orchestrator
    tmux new-window -t "$ORCHESTRATOR_SESSION" -n "orchestrator"

    # Set up orchestrator environment
    local orchestrator_prompt="You are the ORCHESTRATOR agent. Your role is to:
1. Monitor and coordinate all project managers
2. Allocate resources and set priorities
3. Share insights across projects
4. Handle escalations and conflicts
5. Ensure overall system health

Coordination directory: $COORDINATION_DIR
Your ID: $agent_id

Monitor the message queue at: $COORDINATION_DIR/message_queue/orchestrator/
Update work registry at: $COORDINATION_DIR/active_work_registry.json
"

    # Launch the CLI tool with the orchestrator prompt
    local launch_cmd
    if [[ "$ORCHESTRATOR_CLI" == "claude" ]]; then
        launch_cmd="claude --model $DEFAULT_ORCHESTRATOR_MODEL --system-prompt '$orchestrator_prompt'"
    elif [[ "$ORCHESTRATOR_CLI" == "codex-cli" ]]; then
        launch_cmd="codex-cli --prompt '$orchestrator_prompt'"
    else
        log_error "Unknown CLI tool: $ORCHESTRATOR_CLI"
        return 1
    fi

    # Send launch command to tmux pane
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" \
        "export AGENT_ID='$agent_id' && export AGENT_TYPE='orchestrator' && $launch_cmd" Enter

    # Create lock and update registry
    create_agent_lock "$agent_id"
    update_registry "$agent_id" "orchestrator" "active" "monitoring"

    log_success "Orchestrator launched: $agent_id"
}

# Launch project manager
launch_manager() {
    local project_name="$1"
    local manager_pane="${2:-$project_name-manager}"
    local agent_id=$(generate_agent_id "manager" "$project_name")

    log_info "Launching project manager for $project_name: $agent_id"

    # Create tmux window for manager
    tmux new-window -t "$ORCHESTRATOR_SESSION" -n "$manager_pane"

    # Set up manager environment
    local manager_prompt="You are a PROJECT MANAGER agent for the $project_name project. Your role is to:
1. Assign tasks to engineer agents
2. Monitor progress in your project
3. Enforce specifications and quality
4. Report to the orchestrator
5. Coordinate engineer efforts

Project: $project_name
Coordination directory: $COORDINATION_DIR
Your ID: $agent_id

Monitor the message queue at: $COORDINATION_DIR/message_queue/managers/
Send reports to: $COORDINATION_DIR/message_queue/orchestrator/
Update work registry at: $COORDINATION_DIR/active_work_registry.json
"

    # Launch the CLI tool with the manager prompt
    local launch_cmd
    if [[ "$ORCHESTRATOR_CLI" == "claude" ]]; then
        launch_cmd="claude --model $DEFAULT_MANAGER_MODEL --system-prompt '$manager_prompt'"
    elif [[ "$ORCHESTRATOR_CLI" == "codex-cli" ]]; then
        launch_cmd="codex-cli --prompt '$manager_prompt'"
    else
        log_error "Unknown CLI tool: $ORCHESTRATOR_CLI"
        return 1
    fi

    # Send launch command to tmux pane
    tmux send-keys -t "$ORCHESTRATOR_SESSION:$manager_pane" \
        "export AGENT_ID='$agent_id' && export AGENT_TYPE='manager' && export PROJECT='$project_name' && $launch_cmd" Enter

    # Create lock and update registry
    create_agent_lock "$agent_id"
    update_registry "$agent_id" "manager" "active" "managing_$project_name"

    log_success "Manager launched for $project_name: $agent_id"
}

# Launch engineer agent
launch_engineer() {
    local project_name="$1"
    local engineer_index="$2"
    local engineer_pane="${project_name}-eng-${engineer_index}"
    local agent_id=$(generate_agent_id "engineer" "${project_name}-${engineer_index}")

    log_info "Launching engineer $engineer_index for $project_name: $agent_id"

    # Create tmux pane for engineer (split existing window)
    if [[ $engineer_index -eq 1 ]]; then
        # First engineer gets a new window
        tmux new-window -t "$ORCHESTRATOR_SESSION" -n "$engineer_pane"
    else
        # Subsequent engineers split the window
        tmux split-window -t "$ORCHESTRATOR_SESSION:${project_name}-eng-1" -v
        tmux select-layout -t "$ORCHESTRATOR_SESSION:${project_name}-eng-1" tiled
    fi

    # Set up engineer environment
    local engineer_prompt="You are an ENGINEER agent for the $project_name project. Your role is to:
1. Execute specific tasks assigned by your manager
2. Write code and fix bugs
3. Report completion status
4. Request help when blocked
5. Follow project specifications

Project: $project_name
Coordination directory: $COORDINATION_DIR
Your ID: $agent_id
Engineer Index: $engineer_index

Monitor the message queue at: $COORDINATION_DIR/message_queue/engineers/
Report to: $COORDINATION_DIR/message_queue/managers/
Update work registry at: $COORDINATION_DIR/active_work_registry.json
"

    # Launch the CLI tool with the engineer prompt
    local launch_cmd
    if [[ "$ORCHESTRATOR_CLI" == "claude" ]]; then
        launch_cmd="claude --model $DEFAULT_ENGINEER_MODEL --system-prompt '$engineer_prompt'"
    elif [[ "$ORCHESTRATOR_CLI" == "codex-cli" ]]; then
        launch_cmd="codex-cli --prompt '$engineer_prompt'"
    else
        log_error "Unknown CLI tool: $ORCHESTRATOR_CLI"
        return 1
    fi

    # Get the correct pane to send to
    local target_pane
    if [[ $engineer_index -eq 1 ]]; then
        target_pane="$engineer_pane"
    else
        # For split panes, target the last created pane
        target_pane="${project_name}-eng-1.$((engineer_index))"
    fi

    # Send launch command to tmux pane
    tmux send-keys -t "$ORCHESTRATOR_SESSION:$target_pane" \
        "export AGENT_ID='$agent_id' && export AGENT_TYPE='engineer' && export PROJECT='$project_name' && export ENGINEER_INDEX='$engineer_index' && $launch_cmd" Enter

    # Create lock and update registry
    create_agent_lock "$agent_id"
    update_registry "$agent_id" "engineer" "active" "awaiting_assignment"

    log_success "Engineer $engineer_index launched for $project_name: $agent_id"
}

# Launch complete hierarchy
launch_hierarchy() {
    local managers="${1:-$DEFAULT_MANAGERS}"
    local engineers_per_manager="${2:-$DEFAULT_ENGINEERS_PER_MANAGER}"

    log_info "Launching agent hierarchy..."
    log_info "Managers: $managers"
    log_info "Engineers per manager: $engineers_per_manager"

    # Kill existing session if it exists
    tmux kill-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null || true

    # Create new session
    tmux new-session -d -s "$ORCHESTRATOR_SESSION" -n "dashboard"

    # Set up dashboard
    setup_dashboard

    # Launch orchestrator
    launch_orchestrator

    # Launch managers and their engineers
    IFS=',' read -ra MANAGER_ARRAY <<< "$managers"
    for manager in "${MANAGER_ARRAY[@]}"; do
        launch_manager "$manager"

        # Launch engineers for this manager
        for ((i=1; i<=engineers_per_manager; i++)); do
            launch_engineer "$manager" "$i"
        done
    done

    log_success "Agent hierarchy launched successfully!"
    log_info "Session: $ORCHESTRATOR_SESSION"
    log_info "Coordination directory: $COORDINATION_DIR"
}

# Setup monitoring dashboard
setup_dashboard() {
    log_info "Setting up monitoring dashboard..."

    # Dashboard shows status and logs
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" "clear" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "echo '═══════════════════════════════════════════════════════════════'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "echo '           MULTI-AGENT ORCHESTRATOR DASHBOARD'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "echo '═══════════════════════════════════════════════════════════════'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "echo 'Monitoring coordination directory: $COORDINATION_DIR'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "echo 'CLI Tool: $ORCHESTRATOR_CLI'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "watch -n 2 'echo \"Active Agents:\"; ls -1 $COORDINATION_DIR/agent_locks/*.lock 2>/dev/null | wc -l; echo \"\"; echo \"Recent Messages:\"; ls -lt $COORDINATION_DIR/message_queue/*/*.msg 2>/dev/null | head -5; echo \"\"; echo \"Work Registry:\"; jq -r \".orchestrator.status // \\\"No orchestrator\\\"\" $COORDINATION_DIR/active_work_registry.json'" Enter
}

# Broadcast message to all agents
broadcast_message() {
    local message="$1"

    log_info "Broadcasting: $message"

    # Get all agent windows/panes
    local panes=$(tmux list-panes -a -t "$ORCHESTRATOR_SESSION" -F '#{window_name}.#{pane_index}' | grep -v dashboard)

    for pane in $panes; do
        send_message_to_agent "$pane" "$message"
    done

    log_success "Message broadcast to all agents"
}

# Send message to specific project
broadcast_to_project() {
    local project="$1"
    local message="$2"

    log_info "Broadcasting to $project: $message"

    # Send to manager
    send_message_to_agent "${project}-manager" "$message"

    # Send to all engineers of this project
    local engineer_panes=$(tmux list-windows -t "$ORCHESTRATOR_SESSION" -F '#{window_name}' | grep "${project}-eng")
    for pane in $engineer_panes; do
        send_message_to_agent "$pane" "$message"
    done

    log_success "Message broadcast to $project project"
}

# Monitor and display agent status
monitor_agents() {
    log_info "Monitoring agents..."

    while true; do
        clear
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}           AGENT STATUS MONITOR${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""

        # Show active agents
        echo -e "${BLUE}Active Agents:${NC}"
        for lock_file in "$COORDINATION_DIR"/agent_locks/*.lock; do
            if [[ -f "$lock_file" ]]; then
                local agent_info=$(jq -r '.agent_id + " (PID: " + (.pid | tostring) + ")"' "$lock_file")
                echo "  • $agent_info"
            fi
        done

        echo ""

        # Show recent messages
        echo -e "${BLUE}Recent Messages:${NC}"
        find "$COORDINATION_DIR/message_queue" -name "*.msg" -type f -mmin -5 -exec basename {} \; | head -5 | while read msg; do
            echo "  • $msg"
        done

        echo ""

        # Show work registry summary
        echo -e "${BLUE}Work Registry:${NC}"
        if [[ -f "$COORDINATION_DIR/active_work_registry.json" ]]; then
            local orchestrator_status=$(jq -r '.orchestrator.status // "inactive"' "$COORDINATION_DIR/active_work_registry.json")
            local manager_count=$(jq -r '.managers | length' "$COORDINATION_DIR/active_work_registry.json")
            local engineer_count=$(jq -r '.engineers | length' "$COORDINATION_DIR/active_work_registry.json")

            echo "  Orchestrator: $orchestrator_status"
            echo "  Active Managers: $manager_count"
            echo "  Active Engineers: $engineer_count"
        fi

        echo ""
        echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}"
        sleep 5
    done
}

# Attach to orchestrator session
attach_session() {
    if tmux has-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null; then
        log_info "Attaching to orchestrator session..."
        tmux attach-session -t "$ORCHESTRATOR_SESSION"
    else
        log_error "No orchestrator session found. Launch it first with: $0 launch"
        exit 1
    fi
}

# Stop all agents
stop_all_agents() {
    log_warning "Stopping all agents..."

    # Remove all locks
    rm -f "$COORDINATION_DIR"/agent_locks/*.lock

    # Kill tmux session
    tmux kill-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null || true

    # Clear message queues
    find "$COORDINATION_DIR/message_queue" -name "*.msg" -delete

    # Reset registry
    echo '{"version":"1.0.0","orchestrator":{},"managers":{},"engineers":{},"assignments":[],"locks":[]}' \
        > "$COORDINATION_DIR/active_work_registry.json"

    log_success "All agents stopped"
}

# Main command handler
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        launch)
            check_prerequisites
            cleanup_stale_locks
            launch_hierarchy "$@"
            ;;

        attach)
            attach_session
            ;;

        orchestrator)
            check_prerequisites
            launch_orchestrator
            ;;

        manager)
            check_prerequisites
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: $0 manager <project-name>"
                exit 1
            fi
            launch_manager "$1"
            ;;

        engineer)
            check_prerequisites
            if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 engineer <project-name> <engineer-index>"
                exit 1
            fi
            launch_engineer "$1" "$2"
            ;;

        broadcast)
            if [[ -z "${1:-}" ]]; then
                log_error "Usage: $0 broadcast <message>"
                exit 1
            fi
            broadcast_message "$*"
            ;;

        broadcast-project)
            if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 broadcast-project <project> <message>"
                exit 1
            fi
            local project="$1"
            shift
            broadcast_to_project "$project" "$*"
            ;;

        monitor)
            monitor_agents
            ;;

        stop)
            stop_all_agents
            ;;

        status)
            if [[ -f "$COORDINATION_DIR/active_work_registry.json" ]]; then
                jq . "$COORDINATION_DIR/active_work_registry.json"
            else
                log_error "No work registry found"
            fi
            ;;

        help|--help|-h)
            cat <<EOF
Multi-Agent Orchestrator - Hierarchical AI Agent Management

Usage: $0 <command> [options]

Commands:
  launch [managers] [engineers]  - Launch complete hierarchy (default: nixos,backstage,stacks with 2 engineers each)
  attach                         - Attach to orchestrator session
  orchestrator                   - Launch only the orchestrator
  manager <project>             - Launch a project manager
  engineer <project> <index>    - Launch an engineer
  broadcast <message>           - Send message to all agents
  broadcast-project <p> <msg>   - Send message to project agents
  monitor                       - Monitor agent status
  stop                         - Stop all agents
  status                       - Show work registry
  help                         - Show this help

Environment Variables:
  ORCHESTRATOR_CLI             - CLI tool to use (claude/codex-cli, default: claude)
  COORDINATION_DIR            - Coordination directory (default: ~/coordination)
  DEFAULT_ORCHESTRATOR_MODEL  - Model for orchestrator (default: claude-opus-4-1-20250805)
  DEFAULT_MANAGER_MODEL       - Model for managers (default: claude-opus-4-1-20250805)
  DEFAULT_ENGINEER_MODEL      - Model for engineers (default: claude-sonnet-4-20250522)
  DEBUG                      - Enable debug output (0/1, default: 0)

Examples:
  # Launch with defaults
  $0 launch

  # Launch with custom configuration
  $0 launch "nixos,web,api" 3

  # Use codex-cli instead of claude
  ORCHESTRATOR_CLI=codex-cli $0 launch

  # Send message to all agents
  $0 broadcast "New priority: Focus on security fixes"

  # Monitor agents
  $0 monitor

EOF
            ;;

        *)
            log_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"