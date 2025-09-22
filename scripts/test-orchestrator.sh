#!/usr/bin/env bash
# Test script for the multi-agent orchestrator

set -euo pipefail

echo "Testing Multi-Agent Orchestrator System"
echo "========================================"
echo ""

# Test 1: Check prerequisites
echo "Test 1: Checking prerequisites..."
if command -v claude &> /dev/null; then
    echo "  ✓ Claude is installed"
else
    echo "  ✗ Claude not found"
    exit 1
fi

if command -v tmux &> /dev/null; then
    echo "  ✓ Tmux is installed"
else
    echo "  ✗ Tmux not found"
    exit 1
fi

if command -v jq &> /dev/null; then
    echo "  ✓ jq is installed"
else
    echo "  ✗ jq not found"
    exit 1
fi

# Test 2: Check coordination directory
echo ""
echo "Test 2: Checking coordination directory..."
if [[ -d "$HOME/coordination" ]]; then
    echo "  ✓ Coordination directory exists"
    echo "  Contents:"
    ls -la "$HOME/coordination/" | head -10
else
    echo "  ✗ Coordination directory not found"
    echo "  Creating it..."
    mkdir -p "$HOME/coordination"/{agent_locks,message_queue/{orchestrator,managers,engineers},shared_memory}
fi

# Test 3: Test message system
echo ""
echo "Test 3: Testing message system..."
/etc/nixos/scripts/agent-message.sh send orchestrator test-agent "Test message" && \
    echo "  ✓ Message sent successfully" || \
    echo "  ✗ Failed to send message"

/etc/nixos/scripts/agent-message.sh read orchestrator 2>/dev/null | grep -q "Test message" && \
    echo "  ✓ Message read successfully" || \
    echo "  ✗ Failed to read message"

# Test 4: Test lock system
echo ""
echo "Test 4: Testing lock system..."
/etc/nixos/scripts/agent-lock.sh acquire test-agent "/tmp/test-file" && \
    echo "  ✓ Lock acquired successfully" || \
    echo "  ✗ Failed to acquire lock"

/etc/nixos/scripts/agent-lock.sh release test-agent "/tmp/test-file" && \
    echo "  ✓ Lock released successfully" || \
    echo "  ✗ Failed to release lock"

# Test 5: Check orchestrator script
echo ""
echo "Test 5: Testing orchestrator script..."
/etc/nixos/scripts/claude-orchestrator.sh help > /dev/null 2>&1 && \
    echo "  ✓ Orchestrator script is functional" || \
    echo "  ✗ Orchestrator script has errors"

# Test 6: Check work registry
echo ""
echo "Test 6: Checking work registry..."
if [[ -f "$HOME/coordination/active_work_registry.json" ]]; then
    echo "  ✓ Work registry exists"
    echo "  Current status:"
    jq -r '
        "    Orchestrator: " + (.orchestrator.status // "not initialized") + "\n" +
        "    Managers: " + (.managers | length | tostring) + "\n" +
        "    Engineers: " + (.engineers | length | tostring)
    ' "$HOME/coordination/active_work_registry.json" 2>/dev/null || echo "    Registry parse error"
else
    echo "  ✗ Work registry not found"
fi

# Test 7: Dry run launch (without actually starting agents)
echo ""
echo "Test 7: Testing launch configuration..."
echo "  Models configured:"
echo "    Orchestrator: ${DEFAULT_ORCHESTRATOR_MODEL:-claude-opus-4-1-20250805}"
echo "    Managers: ${DEFAULT_MANAGER_MODEL:-claude-opus-4-1-20250805}"
echo "    Engineers: ${DEFAULT_ENGINEER_MODEL:-claude-sonnet-4-20250522}"
echo "  Default managers: ${DEFAULT_MANAGERS:-nixos,backstage,stacks}"
echo "  Engineers per manager: ${DEFAULT_ENGINEERS_PER_MANAGER:-2}"

echo ""
echo "========================================"
echo "Test Complete!"
echo ""
echo "To launch the orchestrator with minimal configuration:"
echo "  /etc/nixos/scripts/claude-orchestrator.sh launch 'nixos' 1"
echo ""
echo "This will create:"
echo "  - 1 Orchestrator (opus)"
echo "  - 1 Manager for nixos project (opus)"
echo "  - 1 Engineer for nixos project (sonnet-3.5)"
echo ""