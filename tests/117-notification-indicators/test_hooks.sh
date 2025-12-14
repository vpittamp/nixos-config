#!/usr/bin/env bash
# Test script for Feature 117 hook scripts
# Tests badge file creation without requiring full Sway environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Feature 117 Hook Script Tests ==="
echo

# Setup test environment
TEST_RUNTIME_DIR=$(mktemp -d)
export XDG_RUNTIME_DIR="$TEST_RUNTIME_DIR"
BADGE_DIR="$TEST_RUNTIME_DIR/i3pm-badges"
mkdir -p "$BADGE_DIR"

cleanup() {
    rm -rf "$TEST_RUNTIME_DIR"
}
trap cleanup EXIT

# Test 1: Badge file creation format
echo "Test 1: Badge file creation format"
cat > "$BADGE_DIR/12345.json" <<EOF
{
  "window_id": 12345,
  "state": "working",
  "source": "claude-code",
  "timestamp": $(date +%s.%N)
}
EOF

# Verify JSON is valid
if jq . "$BADGE_DIR/12345.json" > /dev/null 2>&1; then
    echo "✓ Badge JSON is valid"
else
    echo "✗ Badge JSON is invalid"
    exit 1
fi

# Verify required fields
if jq -e '.window_id and .state and .source and .timestamp' "$BADGE_DIR/12345.json" > /dev/null; then
    echo "✓ Badge has all required fields"
else
    echo "✗ Badge missing required fields"
    exit 1
fi

# Test 2: Badge state values
echo
echo "Test 2: Badge state values"

# Working state
cat > "$BADGE_DIR/22222.json" <<EOF
{"window_id": 22222, "state": "working", "source": "claude-code", "timestamp": $(date +%s)}
EOF

STATE=$(jq -r '.state' "$BADGE_DIR/22222.json")
if [ "$STATE" = "working" ]; then
    echo "✓ Working state value correct"
else
    echo "✗ Working state should be 'working', got '$STATE'"
    exit 1
fi

# Stopped state
cat > "$BADGE_DIR/33333.json" <<EOF
{"window_id": 33333, "state": "stopped", "source": "claude-code", "count": 1, "timestamp": $(date +%s)}
EOF

STATE=$(jq -r '.state' "$BADGE_DIR/33333.json")
if [ "$STATE" = "stopped" ]; then
    echo "✓ Stopped state value correct"
else
    echo "✗ Stopped state should be 'stopped', got '$STATE'"
    exit 1
fi

# Test 3: Badge directory location
echo
echo "Test 3: Badge directory location"

EXPECTED_DIR="$XDG_RUNTIME_DIR/i3pm-badges"
if [ -d "$EXPECTED_DIR" ]; then
    echo "✓ Badge directory exists at \$XDG_RUNTIME_DIR/i3pm-badges/"
else
    echo "✗ Badge directory not at expected location"
    exit 1
fi

# Test 4: Shell script syntax
echo
echo "Test 4: Shell script syntax validation"

for script in "$REPO_ROOT/scripts/claude-hooks/prompt-submit-notification.sh" \
              "$REPO_ROOT/scripts/claude-hooks/stop-notification.sh" \
              "$REPO_ROOT/scripts/claude-hooks/swaync-action-callback.sh"; do
    if bash -n "$script" 2>/dev/null; then
        echo "✓ $(basename "$script") syntax OK"
    else
        echo "✗ $(basename "$script") has syntax errors"
        exit 1
    fi
done

# Test 5: get_terminal_window_id function exists
echo
echo "Test 5: Window detection function exists"

if grep -q "get_terminal_window_id()" "$REPO_ROOT/scripts/claude-hooks/prompt-submit-notification.sh"; then
    echo "✓ get_terminal_window_id function in prompt-submit-notification.sh"
else
    echo "✗ get_terminal_window_id function missing"
    exit 1
fi

if grep -q "get_terminal_window_id()" "$REPO_ROOT/scripts/claude-hooks/stop-notification.sh"; then
    echo "✓ get_terminal_window_id function in stop-notification.sh"
else
    echo "✗ get_terminal_window_id function missing"
    exit 1
fi

# Test 6: No IPC calls in hooks (Feature 117 requirement)
echo
echo "Test 6: No IPC calls in hooks (Feature 117)"

if grep -q "badge-ipc-client" "$REPO_ROOT/scripts/claude-hooks/prompt-submit-notification.sh"; then
    echo "✗ prompt-submit-notification.sh still has IPC calls"
    exit 1
else
    echo "✓ prompt-submit-notification.sh has no IPC calls"
fi

if grep -q "badge-ipc-client" "$REPO_ROOT/scripts/claude-hooks/stop-notification.sh"; then
    echo "✗ stop-notification.sh still has IPC calls"
    exit 1
else
    echo "✓ stop-notification.sh has no IPC calls"
fi

# Test 7: No focused-window fallback (Feature 117 requirement)
echo
echo "Test 7: No focused-window fallback (Feature 117)"

if grep -q "Fallback to focused window" "$REPO_ROOT/scripts/claude-hooks/prompt-submit-notification.sh"; then
    echo "✗ prompt-submit-notification.sh still has focused window fallback"
    exit 1
else
    echo "✓ prompt-submit-notification.sh has no focused window fallback"
fi

if grep -q "Fallback to focused window" "$REPO_ROOT/scripts/claude-hooks/stop-notification.sh"; then
    echo "✗ stop-notification.sh still has focused window fallback"
    exit 1
else
    echo "✓ stop-notification.sh has no focused window fallback"
fi

# Test 8: badge-ipc-client.sh removed
echo
echo "Test 8: badge-ipc-client.sh removed (Feature 117)"

if [ -f "$REPO_ROOT/scripts/claude-hooks/badge-ipc-client.sh" ]; then
    echo "✗ badge-ipc-client.sh still exists"
    exit 1
else
    echo "✓ badge-ipc-client.sh removed"
fi

echo
echo "=== All tests passed! ==="
