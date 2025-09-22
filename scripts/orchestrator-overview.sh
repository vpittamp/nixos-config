#!/usr/bin/env bash
# Orchestrator Overview Panel - Shows all agent panes simultaneously
# Provides a comprehensive bird's-eye view of the entire multi-agent system

set -euo pipefail

OVERVIEW_SESSION="orchestrator-overview"
ORCHESTRATOR_SESSION="${ORCHESTRATOR_SESSION:-orchestrator-demo}"
COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"

# Colors for visual indicators
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Box drawing characters
BOX_TL='┌'
BOX_TR='┐'
BOX_BL='└'
BOX_BR='┘'
BOX_H='─'
BOX_V='│'

# Function to create the overview dashboard
create_overview() {
    echo -e "${CYAN}Creating Orchestrator Overview Panel...${NC}"

    # Kill old session if exists
    tmux kill-session -t "$OVERVIEW_SESSION" 2>/dev/null || true

    # Create new session with main overview window
    tmux new-session -d -s "$OVERVIEW_SESSION" -n "overview"

    # The overview window will have a grid of panes showing different aspects
    # Layout: 3x3 grid for comprehensive monitoring

    # === Top Row: Agent Status ===
    # Pane 1 (Top-left): Orchestrator mini-view
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${CYAN}┌─ ORCHESTRATOR ─┐${NC}\" && \
        if tmux capture-pane -t $ORCHESTRATOR_SESSION:orchestrator -p 2>/dev/null | tail -8; then \
            echo -e \"${GREEN}● Active${NC}\"; \
        else \
            echo -e \"${RED}○ Inactive${NC}\"; \
        fi'" Enter

    # Pane 2 (Top-center): Manager mini-view
    tmux split-window -t "$OVERVIEW_SESSION:overview" -h -p 66
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${MAGENTA}┌─ MANAGER ─┐${NC}\" && \
        if tmux capture-pane -t $ORCHESTRATOR_SESSION:manager-todoapp -p 2>/dev/null | tail -8; then \
            echo -e \"${GREEN}● Active${NC}\"; \
        else \
            echo -e \"${RED}○ No manager${NC}\"; \
        fi'" Enter

    # Pane 3 (Top-right): Engineers mini-view
    tmux split-window -t "$OVERVIEW_SESSION:overview" -h -p 50
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${BLUE}┌─ ENGINEERS ─┐${NC}\" && \
        if tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers -p 2>/dev/null | head -4; then \
            echo \"\"; \
            tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers -p 2>/dev/null | tail -4; \
        else \
            echo -e \"${RED}○ No engineers${NC}\"; \
        fi'" Enter

    # === Middle Row: Activity & Messages ===
    # Pane 4 (Middle-left): Message Queue Status
    tmux select-pane -t "$OVERVIEW_SESSION:overview.1"
    tmux split-window -v -p 66
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 1 -c 'echo -e \"${BOLD}${YELLOW}┌─ MESSAGES ─┐${NC}\" && \
        echo \"Orchestrator: \$(find $COORDINATION_DIR/message_queue/orchestrator -name \"*.msg\" 2>/dev/null | wc -l)\" && \
        echo \"Managers: \$(find $COORDINATION_DIR/message_queue/managers -name \"*.msg\" 2>/dev/null | wc -l)\" && \
        echo \"Engineers: \$(find $COORDINATION_DIR/message_queue/engineers -name \"*.msg\" 2>/dev/null | wc -l)\" && \
        echo \"\" && \
        echo -e \"${CYAN}Latest:${NC}\" && \
        for queue in orchestrator managers engineers; do \
            latest=\$(ls -t $COORDINATION_DIR/message_queue/\$queue/*.msg 2>/dev/null | head -1); \
            if [[ -n \"\$latest\" ]]; then \
                sender=\$(jq -r .sender \"\$latest\" 2>/dev/null | cut -c1-10); \
                echo \"\$queue: \$sender\"; \
            fi; \
        done'" Enter

    # Pane 5 (Middle-center): Active Tasks
    tmux select-pane -t "$OVERVIEW_SESSION:overview.2"
    tmux split-window -v -p 66
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 3 -c 'echo -e \"${BOLD}${GREEN}┌─ ACTIVE TASKS ─┐${NC}\" && \
        if [[ -f $COORDINATION_DIR/active_work_registry.json ]]; then \
            echo -e \"${CYAN}In Progress:${NC}\" && \
            jq -r \".pending_tasks[] | select(.status == \\\"in_progress\\\") | \\\"• \\(.id | .[0:8]): \\(.description | .[0:25])\\\"\" \
                $COORDINATION_DIR/active_work_registry.json 2>/dev/null | head -3 || echo \"None\"; \
            echo \"\" && \
            echo -e \"${YELLOW}Pending:${NC}\" && \
            jq -r \".pending_tasks[] | select(.status == \\\"pending\\\") | \\\"• \\(.id | .[0:8]): \\(.description | .[0:25])\\\"\" \
                $COORDINATION_DIR/active_work_registry.json 2>/dev/null | head -3 || echo \"None\"; \
        else \
            echo \"No registry\"; \
        fi'" Enter

    # Pane 6 (Middle-right): File Locks
    tmux select-pane -t "$OVERVIEW_SESSION:overview.3"
    tmux split-window -v -p 66
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${YELLOW}┌─ FILE LOCKS ─┐${NC}\" && \
        lock_count=\$(find $COORDINATION_DIR/agent_locks -name \"*.lock\" 2>/dev/null | wc -l); \
        echo \"Active: \$lock_count\" && \
        echo \"\" && \
        for lock in \$(ls -t $COORDINATION_DIR/agent_locks/*.lock 2>/dev/null | head -3); do \
            if [[ -f \"\$lock\" ]]; then \
                agent=\$(jq -r .agent_id \"\$lock\" 2>/dev/null | cut -c1-15); \
                file=\$(jq -r .file_path \"\$lock\" 2>/dev/null | xargs basename); \
                echo \"\$agent: \$file\"; \
            fi; \
        done; \
        if [[ \$lock_count -eq 0 ]]; then \
            echo \"No active locks\"; \
        fi'" Enter

    # === Bottom Row: System Status & Alerts ===
    # Pane 7 (Bottom-left): System Health
    tmux select-pane -t "$OVERVIEW_SESSION:overview.1"
    tmux split-window -v -p 33
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${GREEN}┌─ SYSTEM HEALTH ─┐${NC}\" && \
        echo \"\" && \
        # Check orchestrator session
        if tmux has-session -t $ORCHESTRATOR_SESSION 2>/dev/null; then \
            echo -e \"Orchestrator: ${GREEN}●${NC} Running\"; \
        else \
            echo -e \"Orchestrator: ${RED}●${NC} Down\"; \
        fi; \
        # Check monitor session
        if tmux has-session -t orchestrator-monitor 2>/dev/null; then \
            echo -e \"Monitor: ${GREEN}●${NC} Running\"; \
        else \
            echo -e \"Monitor: ${YELLOW}●${NC} Not running\"; \
        fi; \
        # Count active windows
        window_count=\$(tmux list-windows -t $ORCHESTRATOR_SESSION 2>/dev/null | wc -l); \
        echo \"Windows: \$window_count active\"; \
        # Check message queue health
        total_msgs=\$(find $COORDINATION_DIR/message_queue -name \"*.msg\" 2>/dev/null | wc -l); \
        if [[ \$total_msgs -gt 20 ]]; then \
            echo -e \"Queue: ${YELLOW}⚠${NC} High (\$total_msgs)\"; \
        else \
            echo -e \"Queue: ${GREEN}✓${NC} Normal (\$total_msgs)\"; \
        fi'" Enter

    # Pane 8 (Bottom-center): Recent Completions
    tmux select-pane -t "$OVERVIEW_SESSION:overview.2"
    tmux split-window -v -p 33
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 5 -c 'echo -e \"${BOLD}${CYAN}┌─ COMPLETIONS ─┐${NC}\" && \
        if [[ -f $COORDINATION_DIR/completed_work_log.json ]]; then \
            jq -r \".tasks[-3:] | reverse | .[] | \\\"• \\(.agent_id | .[0:10]): \\(.task | .[0:20])\\\"\" \
                $COORDINATION_DIR/completed_work_log.json 2>/dev/null | head -5 || echo \"No completions\"; \
        else \
            echo \"No completion log\"; \
        fi'" Enter

    # Pane 9 (Bottom-right): Alerts & Actions
    tmux select-pane -t "$OVERVIEW_SESSION:overview.3"
    tmux split-window -v -p 33
    tmux send-keys -t "$OVERVIEW_SESSION:overview" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${RED}┌─ ALERTS ─┐${NC}\" && \
        alert_count=0; \
        # Check for stale locks
        stale_locks=\$(find $COORDINATION_DIR/agent_locks -name \"*.lock\" -mmin +30 2>/dev/null | wc -l); \
        if [[ \$stale_locks -gt 0 ]]; then \
            echo -e \"${YELLOW}⚠ \$stale_locks stale locks${NC}\"; \
            ((alert_count++)); \
        fi; \
        # Check message buildup
        total_msgs=\$(find $COORDINATION_DIR/message_queue -name \"*.msg\" 2>/dev/null | wc -l); \
        if [[ \$total_msgs -gt 20 ]]; then \
            echo -e \"${YELLOW}⚠ High msg queue${NC}\"; \
            ((alert_count++)); \
        fi; \
        # Check for inactive agents
        if tmux has-session -t $ORCHESTRATOR_SESSION 2>/dev/null; then \
            inactive=\$(tmux list-windows -t $ORCHESTRATOR_SESSION -F \"#{window_activity}\" | \
                awk -v now=\$(date +%s) \"\\\$1 < now - 300\" | wc -l); \
            if [[ \$inactive -gt 0 ]]; then \
                echo -e \"${YELLOW}⚠ \$inactive inactive${NC}\"; \
                ((alert_count++)); \
            fi; \
        fi; \
        if [[ \$alert_count -eq 0 ]]; then \
            echo -e \"${GREEN}✓ All systems OK${NC}\"; \
        fi'" Enter

    # Set the layout to tiled for even distribution
    tmux select-layout -t "$OVERVIEW_SESSION:overview" tiled

    # Create a second window for detailed agent views
    tmux new-window -t "$OVERVIEW_SESSION" -n "agents-detail"

    # Split into 4 panes for detailed agent monitoring
    # Top-left: Full orchestrator output
    tmux send-keys -t "$OVERVIEW_SESSION:agents-detail" \
        "watch -t -n 2 'echo -e \"${BOLD}${CYAN}═══ ORCHESTRATOR DETAIL ═══${NC}\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:orchestrator -p 2>/dev/null | tail -20 || \
        echo \"Session not found\"'" Enter

    # Top-right: Full manager output
    tmux split-window -t "$OVERVIEW_SESSION:agents-detail" -h
    tmux send-keys -t "$OVERVIEW_SESSION:agents-detail" \
        "watch -t -n 2 'echo -e \"${BOLD}${MAGENTA}═══ MANAGER DETAIL ═══${NC}\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:manager-todoapp -p 2>/dev/null | tail -20 || \
        echo \"Session not found\"'" Enter

    # Bottom-left: Engineer 1 detail
    tmux select-pane -t "$OVERVIEW_SESSION:agents-detail.1"
    tmux split-window -v
    tmux send-keys -t "$OVERVIEW_SESSION:agents-detail" \
        "watch -t -n 2 'echo -e \"${BOLD}${BLUE}═══ ENGINEER 1 DETAIL ═══${NC}\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers.1 -p 2>/dev/null | tail -20 || \
        echo \"Session not found\"'" Enter

    # Bottom-right: Engineer 2 detail
    tmux select-pane -t "$OVERVIEW_SESSION:agents-detail.2"
    tmux split-window -v
    tmux send-keys -t "$OVERVIEW_SESSION:agents-detail" \
        "watch -t -n 2 'echo -e \"${BOLD}${BLUE}═══ ENGINEER 2 DETAIL ═══${NC}\" && \
        tmux capture-pane -t $ORCHESTRATOR_SESSION:engineers.2 -p 2>/dev/null | tail -20 || \
        echo \"Session not found\"'" Enter

    # Create third window for project files monitoring
    tmux new-window -t "$OVERVIEW_SESSION" -n "project"

    # Project structure and recent changes
    tmux send-keys -t "$OVERVIEW_SESSION:project" \
        "watch -t -n 3 'echo -e \"${BOLD}${YELLOW}═══ PROJECT STATUS ═══${NC}\" && \
        echo \"\" && \
        echo \"Project: ~/test-project-multiagent\" && \
        echo \"\" && \
        echo -e \"${CYAN}Recent File Changes:${NC}\" && \
        ls -lt ~/test-project-multiagent/src/*.ts 2>/dev/null | head -5 | \
            awk \"{print \\\"  \\\" \\\$9 \\\" - \\\" \\\$6 \\\" \\\" \\\$7}\" && \
        echo \"\" && \
        echo -e \"${GREEN}TypeScript Issues:${NC}\" && \
        cd ~/test-project-multiagent 2>/dev/null && \
        if command -v tsc &>/dev/null; then \
            tsc --noEmit 2>&1 | head -10 || echo \"  No TypeScript compiler\"; \
        else \
            echo \"  TypeScript not installed\"; \
        fi'" Enter

    # Split for Git status
    tmux split-window -t "$OVERVIEW_SESSION:project" -v
    tmux send-keys -t "$OVERVIEW_SESSION:project" \
        "watch -t -n 5 'echo -e \"${BOLD}${MAGENTA}═══ GIT STATUS ═══${NC}\" && \
        cd ~/test-project-multiagent 2>/dev/null && \
        git status --short 2>/dev/null || echo \"Not a git repository\" && \
        echo \"\" && \
        echo -e \"${CYAN}Recent Commits:${NC}\" && \
        git log --oneline -5 2>/dev/null || echo \"No commits\"'" Enter

    # Enable activity monitoring
    tmux set-option -t "$OVERVIEW_SESSION" -g monitor-activity on
    tmux set-option -t "$OVERVIEW_SESSION" -g visual-activity on

    # Custom status bar
    tmux set-option -t "$OVERVIEW_SESSION" -g status-left-length 40
    tmux set-option -t "$OVERVIEW_SESSION" -g status-left \
        "#[fg=cyan,bold]📊 Orchestrator Overview #[fg=white]│ "
    tmux set-option -t "$OVERVIEW_SESSION" -g status-right-length 60
    tmux set-option -t "$OVERVIEW_SESSION" -g status-right \
        "#[fg=yellow]Msgs: #(find $COORDINATION_DIR/message_queue -name '*.msg' 2>/dev/null | wc -l) #[fg=white]│ #[fg=green]Locks: #(find $COORDINATION_DIR/agent_locks -name '*.lock' 2>/dev/null | wc -l) #[fg=white]│ #[fg=cyan]%H:%M"
    tmux set-option -t "$OVERVIEW_SESSION" -g status-interval 2

    # Go back to main overview window
    tmux select-window -t "$OVERVIEW_SESSION:overview"

    echo -e "${GREEN}✓ Orchestrator overview created${NC}"
}

# Function to integrate with existing monitor
integrate_with_monitor() {
    if tmux has-session -t orchestrator-monitor 2>/dev/null; then
        echo -e "${CYAN}Adding overview window to existing monitor...${NC}"

        # Add overview as new window in monitor session
        tmux new-window -t orchestrator-monitor -n "grid-view"

        # Create grid layout in monitor session
        for i in {1..8}; do
            if [[ $i -gt 1 ]]; then
                tmux split-window -t orchestrator-monitor:grid-view
            fi
        done

        # Set to tiled layout
        tmux select-layout -t orchestrator-monitor:grid-view tiled

        # Configure each pane to show mini views
        local panes=(
            "Orchestrator:orchestrator"
            "Manager:manager-todoapp"
            "Engineers:engineers"
            "Dashboard:dashboard"
            "Messages:messages"
            "Tasks:progress"
            "Locks:locks"
            "Alerts:alerts"
        )

        for i in "${!panes[@]}"; do
            local pane_num=$((i + 1))
            local pane_info="${panes[$i]}"
            local title="${pane_info%%:*}"
            local target="${pane_info##*:}"

            tmux send-keys -t "orchestrator-monitor:grid-view.$pane_num" \
                "watch -t -n 2 'echo -e \"${BOLD}${CYAN}[$title]${NC}\" && \
                tmux capture-pane -t $ORCHESTRATOR_SESSION:$target -p 2>/dev/null | tail -10 || \
                echo \"Not available\"'" Enter
        done

        echo -e "${GREEN}✓ Grid view added to monitor${NC}"
    fi
}

# Function to attach with Konsole
attach_overview() {
    local profile="${1:-Supervisor}"

    if command -v konsole &> /dev/null; then
        konsole --profile "$profile" \
            --workdir "$HOME/test-project-multiagent" \
            -e tmux attach-session -t "$OVERVIEW_SESSION" &
        echo -e "${GREEN}Launched overview in Konsole${NC}"
    else
        tmux attach-session -t "$OVERVIEW_SESSION"
    fi
}

# Main command handler
case "${1:-create}" in
    create|start)
        create_overview
        if [[ "${2:-}" == "--integrate" ]]; then
            integrate_with_monitor
        fi
        ;;

    attach|view)
        if tmux has-session -t "$OVERVIEW_SESSION" 2>/dev/null; then
            attach_overview "${2:-Supervisor}"
        else
            echo -e "${RED}Overview not running. Start with: $0 create${NC}"
            exit 1
        fi
        ;;

    integrate)
        integrate_with_monitor
        ;;

    stop|kill)
        tmux kill-session -t "$OVERVIEW_SESSION" 2>/dev/null || true
        echo -e "${YELLOW}Overview stopped${NC}"
        ;;

    status)
        if tmux has-session -t "$OVERVIEW_SESSION" 2>/dev/null; then
            echo -e "${GREEN}Overview is running${NC}"
            tmux list-windows -t "$OVERVIEW_SESSION"
        else
            echo -e "${RED}Overview is not running${NC}"
        fi
        ;;

    help|*)
        cat <<EOF
Orchestrator Overview Panel

Usage: $0 <command> [options]

Commands:
  create [--integrate] - Create overview panel (optionally integrate with monitor)
  attach|view [profile] - Attach to overview (default: Supervisor profile)
  integrate            - Add grid view to existing monitor
  stop|kill           - Stop the overview
  status              - Check overview status
  help                - Show this help

Windows:
  1. overview      - 3x3 grid showing all system components
  2. agents-detail - Detailed view of each agent
  3. project       - Project files and git status

Grid Layout (Window 1):
  ┌─────────┬─────────┬─────────┐
  │ Orchest │ Manager │ Engineers│  Agent Status
  ├─────────┼─────────┼─────────┤
  │Messages │ Tasks   │ Locks   │  Activity
  ├─────────┼─────────┼─────────┤
  │ Health  │Complete │ Alerts  │  System Status
  └─────────┴─────────┴─────────┘

Navigation:
  Window switching: Ctrl-b + 1/2/3
  Pane switching: Ctrl-b + arrows
  Zoom pane: Ctrl-b + z
  Detach: Ctrl-b + d

Examples:
  # Create standalone overview
  $0 create

  # Create and integrate with monitor
  $0 create --integrate

  # View in Konsole
  $0 view

EOF
        ;;
esac