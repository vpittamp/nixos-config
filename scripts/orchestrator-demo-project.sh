#!/usr/bin/env bash
# Multi-Agent Orchestrator Demo Project
# Creates a test project with tasks for multiple agents to collaborate on

set -euo pipefail

COORDINATION_DIR="${COORDINATION_DIR:-$HOME/coordination}"
PROJECT_DIR="$HOME/test-project-multiagent"
ORCHESTRATOR_SESSION="${ORCHESTRATOR_SESSION:-orchestrator-demo}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Function to create test project structure
create_test_project() {
    echo -e "${CYAN}Creating test project: Multi-Agent TODO App${NC}"

    # Clean up old project if exists
    if [[ -d "$PROJECT_DIR" ]]; then
        echo -e "${YELLOW}Removing existing project directory${NC}"
        rm -rf "$PROJECT_DIR"
    fi

    mkdir -p "$PROJECT_DIR"/{src,tests,docs,config}

    # Create a simple TODO app that needs work from multiple agents
    cat > "$PROJECT_DIR/README.md" <<'EOF'
# Multi-Agent TODO App Project

This is a test project for demonstrating multi-agent orchestration.

## Project Structure
- `src/` - Application source code
- `tests/` - Test files
- `docs/` - Documentation
- `config/` - Configuration files

## Tasks to Complete
1. Fix TypeScript errors in todo.ts
2. Add validation to API endpoints
3. Write missing unit tests
4. Update documentation
5. Configure deployment settings

## Agent Assignments
- **Orchestrator**: Coordinates all work
- **Manager**: Assigns specific tasks
- **Engineer 1**: Code fixes and features
- **Engineer 2**: Tests and documentation
EOF

    # Create TypeScript file with intentional issues
    cat > "$PROJECT_DIR/src/todo.ts" <<'EOF'
// TODO App Main Module - Needs fixes

interface Todo {
    id: number;
    title: string;
    completed: boolean;
    dueDate?: Date;
}

class TodoManager {
    private todos: Todo[] = [];

    // BUG: Missing type annotation
    addTodo(title, completed = false) {
        const newTodo: Todo = {
            id: this.todos.length + 1,
            title: title,
            completed: completed
            // BUG: Missing dueDate initialization
        };
        this.todos.push(newTodo);
        return newTodo;
    }

    // BUG: Return type not specified
    getTodos() {
        return this.todos;
    }

    // TODO: Implement validation
    updateTodo(id: number, updates: Partial<Todo>) {
        // Missing implementation
    }

    // TODO: Add error handling
    deleteTodo(id: number): boolean {
        const index = this.todos.findIndex(t => t.id === id);
        if (index > -1) {
            this.todos.splice(index, 1);
            return true;
        }
        return false;
    }
}

export { Todo, TodoManager };
EOF

    # Create API file needing work
    cat > "$PROJECT_DIR/src/api.ts" <<'EOF'
// API Endpoints - Needs validation and error handling

import { TodoManager } from './todo';

const todoManager = new TodoManager();

// TODO: Add input validation
function handleAddTodo(req: any): any {
    const { title, completed } = req.body;
    // Missing validation
    return todoManager.addTodo(title, completed);
}

// TODO: Add error handling
function handleGetTodos(): any {
    return todoManager.getTodos();
}

// TODO: Implement update endpoint
function handleUpdateTodo(req: any): any {
    // Not implemented
    return { error: "Not implemented" };
}

// TODO: Add authorization check
function handleDeleteTodo(req: any): any {
    const { id } = req.params;
    return todoManager.deleteTodo(parseInt(id));
}

export {
    handleAddTodo,
    handleGetTodos,
    handleUpdateTodo,
    handleDeleteTodo
};
EOF

    # Create empty test file
    cat > "$PROJECT_DIR/tests/todo.test.ts" <<'EOF'
// TODO: Write comprehensive tests

import { TodoManager } from '../src/todo';

describe('TodoManager', () => {
    // TODO: Add test cases
    test('should create instance', () => {
        const manager = new TodoManager();
        expect(manager).toBeDefined();
    });

    // TODO: Test addTodo
    // TODO: Test getTodos
    // TODO: Test updateTodo
    // TODO: Test deleteTodo
});
EOF

    # Create package.json
    cat > "$PROJECT_DIR/package.json" <<'EOF'
{
  "name": "multiagent-todo-app",
  "version": "1.0.0",
  "description": "Test project for multi-agent orchestration",
  "main": "src/index.ts",
  "scripts": {
    "test": "jest",
    "build": "tsc",
    "lint": "eslint src/",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "@types/jest": "^29.0.0",
    "@types/node": "^20.0.0",
    "jest": "^29.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

    # Create tsconfig.json
    cat > "$PROJECT_DIR/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
EOF

    echo -e "${GREEN}✓ Test project created at $PROJECT_DIR${NC}"
}

# Function to initialize task registry
initialize_task_registry() {
    echo -e "${CYAN}Initializing work registry with tasks...${NC}"

    cat > "$COORDINATION_DIR/active_work_registry.json" <<EOF
{
  "version": "1.0.0",
  "project": "multiagent-todo-app",
  "orchestrator": {
    "id": "orchestrator-001",
    "status": "active",
    "current_task": "coordinating_todo_app_development",
    "started_at": "$(date -Iseconds)"
  },
  "managers": {
    "manager-todoapp-001": {
      "status": "active",
      "current_task": "managing_todo_app_tasks",
      "assigned_engineers": ["engineer-todoapp-1", "engineer-todoapp-2"],
      "updated_at": "$(date -Iseconds)"
    }
  },
  "engineers": {
    "engineer-todoapp-1": {
      "status": "idle",
      "current_task": null,
      "capabilities": ["typescript", "testing"],
      "updated_at": "$(date -Iseconds)"
    },
    "engineer-todoapp-2": {
      "status": "idle",
      "current_task": null,
      "capabilities": ["documentation", "api"],
      "updated_at": "$(date -Iseconds)"
    }
  },
  "pending_tasks": [
    {
      "id": "task-001",
      "description": "Fix TypeScript type errors in todo.ts",
      "priority": "high",
      "assigned_to": null,
      "status": "pending"
    },
    {
      "id": "task-002",
      "description": "Implement updateTodo method",
      "priority": "high",
      "assigned_to": null,
      "status": "pending"
    },
    {
      "id": "task-003",
      "description": "Add input validation to API endpoints",
      "priority": "medium",
      "assigned_to": null,
      "status": "pending"
    },
    {
      "id": "task-004",
      "description": "Write unit tests for TodoManager",
      "priority": "medium",
      "assigned_to": null,
      "status": "pending"
    },
    {
      "id": "task-005",
      "description": "Document API endpoints",
      "priority": "low",
      "assigned_to": null,
      "status": "pending"
    }
  ]
}
EOF

    echo -e "${GREEN}✓ Work registry initialized${NC}"
}

# Function to create initial messages
seed_message_queues() {
    echo -e "${CYAN}Seeding message queues...${NC}"

    # Message from orchestrator to managers
    cat > "$COORDINATION_DIR/message_queue/managers/$(date +%s)-001.msg" <<EOF
{
  "sender": "orchestrator-001",
  "recipient_type": "managers",
  "timestamp": "$(date -Iseconds)",
  "message": "New project: TODO App. Please review $PROJECT_DIR and assign tasks to engineers. Focus on TypeScript fixes first, then tests."
}
EOF

    # Message from manager to engineers
    cat > "$COORDINATION_DIR/message_queue/engineers/$(date +%s)-002.msg" <<EOF
{
  "sender": "manager-todoapp-001",
  "recipient_type": "engineers",
  "timestamp": "$(date -Iseconds)",
  "message": "Engineers, please review the TODO app codebase at $PROJECT_DIR. Engineer-1: Focus on TypeScript fixes. Engineer-2: Prepare to write tests."
}
EOF

    echo -e "${GREEN}✓ Message queues seeded${NC}"
}

# Function to launch demo orchestrator
launch_demo_orchestrator() {
    echo -e "${CYAN}Launching demo orchestrator session...${NC}"

    # Kill any existing demo session
    tmux kill-session -t "$ORCHESTRATOR_SESSION" 2>/dev/null || true

    # Create orchestrator session
    tmux new-session -d -s "$ORCHESTRATOR_SESSION" -n "dashboard"

    # Dashboard window - Project overview
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" "clear" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:dashboard" \
        "watch -t -n 2 -c 'echo -e \"${BOLD}${CYAN}═══ TODO APP PROJECT DASHBOARD ═══${NC}\" && \
        echo \"\" && \
        echo -e \"${YELLOW}Project:${NC} $PROJECT_DIR\" && \
        echo \"\" && \
        echo -e \"${GREEN}Tasks Status:${NC}\" && \
        if [[ -f $COORDINATION_DIR/active_work_registry.json ]]; then \
            jq -r \".pending_tasks[] | \\\"  [\(.status)] \(.id): \(.description)\\\"\" $COORDINATION_DIR/active_work_registry.json 2>/dev/null | head -10; \
        fi && \
        echo \"\" && \
        echo -e \"${BLUE}Recent Activity:${NC}\" && \
        ls -lt $PROJECT_DIR/src/*.ts 2>/dev/null | head -5 | awk \"{print \\\"  \\\" \\\$9 \\\" - Modified: \\\" \\\$6 \\\" \\\" \\\$7}\"'" Enter

    # Orchestrator window
    tmux new-window -t "$ORCHESTRATOR_SESSION" -n "orchestrator"
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "clear" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo -e '${BOLD}${CYAN}═══ ORCHESTRATOR (opus-4.1) ═══${NC}'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo 'Model: claude-opus-4-1-20250805'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo 'Status: Active - Coordinating TODO App Development'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo 'Current Focus:'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo '  1. Monitoring TypeScript fixes'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo '  2. Coordinating test development'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo '  3. Ensuring code quality'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo 'Ready to launch with:'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:orchestrator" "echo 'claude --model claude-opus-4-1-20250805 --dangerously-skip-permissions --dir $PROJECT_DIR'" Enter

    # Manager window
    tmux new-window -t "$ORCHESTRATOR_SESSION" -n "manager-todoapp"
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "clear" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo -e '${BOLD}${MAGENTA}═══ PROJECT MANAGER: TODO App (opus-4.1) ═══${NC}'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo 'Model: claude-opus-4-1-20250805'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo 'Managing: 2 engineers'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo 'Task Assignments:'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo '  Engineer-1: TypeScript fixes (todo.ts)'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo '  Engineer-2: API validation (api.ts)'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo 'Ready to launch with:'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:manager-todoapp" "echo 'claude --model claude-opus-4-1-20250805 --dangerously-skip-permissions --dir $PROJECT_DIR'" Enter

    # Engineers window (split)
    tmux new-window -t "$ORCHESTRATOR_SESSION" -n "engineers"

    # Engineer 1
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "clear" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo -e '${BOLD}${BLUE}═══ ENGINEER 1: TypeScript (sonnet-4) ═══${NC}'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Model: claude-sonnet-4-20250522'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Specialization: TypeScript, Testing'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Assigned Task: Fix type errors in todo.ts'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Status: Ready'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Ready to launch with:'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'claude --model claude-sonnet-4-20250522 --dangerously-skip-permissions --dir $PROJECT_DIR'" Enter

    # Engineer 2 (split pane)
    tmux split-window -t "$ORCHESTRATOR_SESSION:engineers" -h
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "clear" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo -e '${BOLD}${BLUE}═══ ENGINEER 2: API/Docs (sonnet-4) ═══${NC}'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Model: claude-sonnet-4-20250522'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Specialization: API, Documentation'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Assigned Task: Add validation to API'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Status: Ready'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo ''" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'Ready to launch with:'" Enter
    tmux send-keys -t "$ORCHESTRATOR_SESSION:engineers" "echo 'claude --model claude-sonnet-4-20250522 --dangerously-skip-permissions --dir $PROJECT_DIR'" Enter

    # Code review window
    tmux new-window -t "$ORCHESTRATOR_SESSION" -n "code-review"
    tmux send-keys -t "$ORCHESTRATOR_SESSION:code-review" \
        "watch -t -n 3 'echo -e \"${BOLD}${YELLOW}═══ CODE CHANGES ═══${NC}\" && \
        echo \"\" && \
        echo \"Latest modifications:\" && \
        cd $PROJECT_DIR && \
        git status --short 2>/dev/null || ls -lt src/*.ts | head -5'" Enter

    echo -e "${GREEN}✓ Demo orchestrator session created${NC}"
}

# Function to launch monitoring dashboard
launch_monitor() {
    echo -e "${CYAN}Launching orchestrator monitor...${NC}"

    # Set the session for monitoring
    export ORCHESTRATOR_SESSION="$ORCHESTRATOR_SESSION"

    /etc/nixos/scripts/orchestrator-monitor.sh create

    echo -e "${GREEN}✓ Monitor dashboard created${NC}"
}

# Function to simulate agent activity
simulate_activity() {
    echo -e "${CYAN}Simulating initial agent activity...${NC}"

    # Simulate engineer 1 starting work
    cat > "$COORDINATION_DIR/message_queue/orchestrator/$(date +%s)-003.msg" <<EOF
{
  "sender": "engineer-todoapp-1",
  "recipient_type": "orchestrator",
  "timestamp": "$(date -Iseconds)",
  "message": "Starting work on TypeScript fixes in todo.ts. Found 3 type errors to resolve."
}
EOF

    # Update work registry to show engineer is working
    jq '.engineers["engineer-todoapp-1"].status = "active" |
        .engineers["engineer-todoapp-1"].current_task = "fixing_typescript_errors"' \
        "$COORDINATION_DIR/active_work_registry.json" > /tmp/registry.tmp && \
        mv /tmp/registry.tmp "$COORDINATION_DIR/active_work_registry.json"

    # Create a lock for the file being worked on
    /etc/nixos/scripts/agent-lock.sh acquire "engineer-todoapp-1" "$PROJECT_DIR/src/todo.ts"

    echo -e "${GREEN}✓ Activity simulation complete${NC}"
}

# Main execution
main() {
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}   Multi-Agent Orchestrator Demo Project${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo ""

    # Step 1: Create test project
    create_test_project

    # Step 2: Initialize task registry
    initialize_task_registry

    # Step 3: Seed message queues
    seed_message_queues

    # Step 4: Launch orchestrator
    launch_demo_orchestrator

    # Step 5: Simulate some activity
    simulate_activity

    # Step 6: Launch monitor
    launch_monitor

    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}        Demo Setup Complete!${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Project Location:${NC} $PROJECT_DIR"
    echo ""
    echo -e "${CYAN}View the orchestrator:${NC}"
    echo "  tmux attach -t $ORCHESTRATOR_SESSION"
    echo ""
    echo -e "${CYAN}View the monitor dashboard:${NC}"
    echo "  tmux attach -t orchestrator-monitor"
    echo ""
    echo -e "${CYAN}Or view both in Konsole (small font):${NC}"
    echo "  orchestrator-monitor attach"
    echo ""
    echo -e "${YELLOW}Navigation:${NC}"
    echo "  • Switch tmux windows: Ctrl-b + number"
    echo "  • Switch tmux sessions: Ctrl-b + s"
    echo "  • Detach from tmux: Ctrl-b + d"
    echo ""
    echo -e "${GREEN}To start actual Claude agents:${NC}"
    echo "  1. In orchestrator window: claude --model claude-opus-4-1-20250805 --dangerously-skip-permissions --dir $PROJECT_DIR"
    echo "  2. In manager window: claude --model claude-opus-4-1-20250805 --dangerously-skip-permissions --dir $PROJECT_DIR"
    echo "  3. In engineer panes: claude --model claude-sonnet-4-20250522 --dangerously-skip-permissions --dir $PROJECT_DIR"
    echo ""
    echo -e "${MAGENTA}Monitor Features:${NC}"
    echo "  • Window 1 (agents): Live agent status"
    echo "  • Window 2 (messages): Message flow"
    echo "  • Window 3 (progress): Task progress"
    echo "  • Window 4 (alerts): System alerts"
    echo ""
}

# Run main
main "$@"