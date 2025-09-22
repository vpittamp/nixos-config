#!/usr/bin/env bash
# Minimal test launch of orchestrator with echo instead of claude

set -euo pipefail

echo "Creating minimal test orchestrator session..."
echo "============================================="
echo ""

# Kill any existing test session
tmux kill-session -t test-orchestrator 2>/dev/null || true

# Create test session
tmux new-session -d -s test-orchestrator -n dashboard

# Dashboard window
tmux send-keys -t test-orchestrator:dashboard "clear" Enter
tmux send-keys -t test-orchestrator:dashboard "echo '═══════════════════════════════════════'" Enter
tmux send-keys -t test-orchestrator:dashboard "echo '    TEST ORCHESTRATOR DASHBOARD'" Enter
tmux send-keys -t test-orchestrator:dashboard "echo '═══════════════════════════════════════'" Enter
tmux send-keys -t test-orchestrator:dashboard "echo ''" Enter
tmux send-keys -t test-orchestrator:dashboard "echo 'This simulates the multi-agent system'" Enter
tmux send-keys -t test-orchestrator:dashboard "echo 'without actually launching Claude'" Enter

# Create orchestrator window
tmux new-window -t test-orchestrator -n "orchestrator"
tmux send-keys -t test-orchestrator:orchestrator "clear" Enter
tmux send-keys -t test-orchestrator:orchestrator "echo '═══ ORCHESTRATOR (opus-4.1) ═══'" Enter
tmux send-keys -t test-orchestrator:orchestrator "echo 'Role: Master coordinator'" Enter
tmux send-keys -t test-orchestrator:orchestrator "echo 'Model: claude-opus-4-1-20250805'" Enter
tmux send-keys -t test-orchestrator:orchestrator "echo ''" Enter
tmux send-keys -t test-orchestrator:orchestrator "echo 'Would run: claude --model claude-opus-4-1-20250805 --dangerously-skip-permissions --system-prompt ...'" Enter
tmux send-keys -t test-orchestrator:orchestrator "echo ''" Enter
tmux send-keys -t test-orchestrator:orchestrator "echo 'Monitoring all projects...'" Enter

# Create manager window for nixos
tmux new-window -t test-orchestrator -n "nixos-manager"
tmux send-keys -t test-orchestrator:nixos-manager "clear" Enter
tmux send-keys -t test-orchestrator:nixos-manager "echo '═══ MANAGER: NixOS (opus-4.1) ═══'" Enter
tmux send-keys -t test-orchestrator:nixos-manager "echo 'Role: Project manager for NixOS'" Enter
tmux send-keys -t test-orchestrator:nixos-manager "echo 'Model: claude-opus-4-1-20250805'" Enter
tmux send-keys -t test-orchestrator:nixos-manager "echo ''" Enter
tmux send-keys -t test-orchestrator:nixos-manager "echo 'Would run: claude --model claude-opus-4-1-20250805 --dangerously-skip-permissions --system-prompt ...'" Enter
tmux send-keys -t test-orchestrator:nixos-manager "echo ''" Enter
tmux send-keys -t test-orchestrator:nixos-manager "echo 'Managing NixOS engineers...'" Enter

# Create engineer window
tmux new-window -t test-orchestrator -n "nixos-eng-1"
tmux send-keys -t test-orchestrator:nixos-eng-1 "clear" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1 "echo '═══ ENGINEER 1: NixOS (sonnet-4) ═══'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1 "echo 'Role: Engineer for NixOS project'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1 "echo 'Model: claude-sonnet-4-20250522'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1 "echo ''" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1 "echo 'Would run: claude --model claude-sonnet-4-20250522 --dangerously-skip-permissions --system-prompt ...'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1 "echo ''" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1 "echo 'Awaiting task assignment...'" Enter

# Add a second engineer (split pane)
tmux split-window -t test-orchestrator:nixos-eng-1 -v
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "clear" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "echo '═══ ENGINEER 2: NixOS (sonnet-4) ═══'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "echo 'Role: Engineer for NixOS project'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "echo 'Model: claude-sonnet-4-20250522'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "echo ''" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "echo 'Would run: claude --model claude-sonnet-4-20250522 --dangerously-skip-permissions --system-prompt ...'" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "echo ''" Enter
tmux send-keys -t test-orchestrator:nixos-eng-1.2 "echo 'Awaiting task assignment...'" Enter

tmux select-layout -t test-orchestrator:nixos-eng-1 even-vertical

echo "Test orchestrator session created!"
echo ""
echo "Session structure:"
echo "  • Dashboard (monitoring view)"
echo "  • Orchestrator (opus-4.1) - Master coordinator"
echo "  • NixOS Manager (opus-4.1) - Project manager"
echo "  • NixOS Engineer 1 (sonnet-4) - Task executor"
echo "  • NixOS Engineer 2 (sonnet-4) - Task executor"
echo ""
echo "To view: tmux attach -t test-orchestrator"
echo "To close: tmux kill-session -t test-orchestrator"
echo ""

# Test message passing
echo "Testing message passing between agents..."
/etc/nixos/scripts/agent-message.sh send managers orchestrator-test "Task: Review NixOS configuration"
/etc/nixos/scripts/agent-message.sh send engineers manager-nixos-test "Assignment: Fix type errors in flake.nix"

echo ""
echo "Messages queued. Check with:"
echo "  agent-message read managers"
echo "  agent-message read engineers"
echo ""