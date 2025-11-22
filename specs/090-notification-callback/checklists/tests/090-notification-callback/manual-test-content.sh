#!/usr/bin/env bash
# Manual Test: Notification Content Accuracy (User Story 4)
#
# PURPOSE: Verify notification displays rich context about completed Claude Code task
#
# PREREQUISITES:
# - SwayNC running
# - Claude Code stop-notification scripts installed
# - Test transcript file with various tool usage

set -euo pipefail

echo "=== Manual Test: Notification Content (US4) ===" echo ""
echo "This test verifies that notifications display rich context:"
echo "  - Message preview (first 80 chars)"
echo "  - Activity summary (tool counts: bash, edits, writes, reads)"
echo "  - Modified files (up to 3)"
echo "  - Working directory name"
echo "  - Project name (if I3PM_PROJECT_NAME set)"
echo ""

# Create a temporary test transcript with various tool usage
TEST_TRANSCRIPT=$(mktemp)
cat > "$TEST_TRANSCRIPT" << 'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"I've completed updating your NixOS configuration with the new module. The changes include enhanced error handling and performance improvements."}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"nixos-rebuild test"}}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/etc/nixos/configuration.nix"}}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/etc/nixos/modules/services/daemon.nix"}}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/etc/nixos/modules/tools/helper.nix"}}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/etc/nixos/hardware/m1.nix"}}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/etc/nixos/home-vpittamp.nix"}}]}}
EOF

echo "Step 1: Created test transcript at: $TEST_TRANSCRIPT"
echo ""

# Build notification body using the same logic as stop-notification.sh
LAST_MESSAGE=$(tac "$TEST_TRANSCRIPT" 2>/dev/null | \
    grep -m1 '"role":"assistant"' | \
    jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null | \
    head -c 150 | tr '\n' ' ' || echo "")

BASH_COUNT=$(tail -30 "$TEST_TRANSCRIPT" 2>/dev/null | grep -c '"name":"Bash"' || echo "0")
EDIT_COUNT=$(tail -30 "$TEST_TRANSCRIPT" 2>/dev/null | grep -c '"name":"Edit"' || echo "0")
WRITE_COUNT=$(tail -30 "$TEST_TRANSCRIPT" 2>/dev/null | grep -c '"name":"Write"' || echo "0")
READ_COUNT=$(tail -30 "$TEST_TRANSCRIPT" 2>/dev/null | grep -c '"name":"Read"' || echo "0")

# Build tool summary
TOOL_PARTS=()
[ "$BASH_COUNT" -gt 0 ] && TOOL_PARTS+=("$BASH_COUNT bash")
[ "$EDIT_COUNT" -gt 0 ] && TOOL_PARTS+=("$EDIT_COUNT edits")
[ "$WRITE_COUNT" -gt 0 ] && TOOL_PARTS+=("$WRITE_COUNT writes")
[ "$READ_COUNT" -gt 0 ] && TOOL_PARTS+=("$READ_COUNT reads")

TOOL_SUMMARY=""
if [ ${#TOOL_PARTS[@]} -gt 0 ]; then
    TOOL_SUMMARY=$(IFS=", "; echo "${TOOL_PARTS[*]}")
fi

# Extract files modified
FILES_MODIFIED=$(tail -30 "$TEST_TRANSCRIPT" 2>/dev/null | \
    jq -r 'select(.message.content[]?.type == "tool_use") | .message.content[] | select(.type == "tool_use") | select(.name == "Edit" or .name == "Write") | .input.file_path' 2>/dev/null | \
    sort -u | \
    head -3 | \
    awk '{print "  • " $0}' | \
    tr '\n' '\n' || echo "")

# Build notification body
NOTIFICATION_BODY="$LAST_MESSAGE"

if [ -n "$TOOL_SUMMARY" ]; then
    NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\n📊 Activity: ${TOOL_SUMMARY}"
fi

if [ -n "$FILES_MODIFIED" ]; then
    NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\n📝 Modified:\n${FILES_MODIFIED}"
fi

WORKING_DIR="/home/vpittamp/nixos-090-notification-callback"
DIR_NAME=$(basename "$WORKING_DIR")
NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\n📁 ${DIR_NAME}"

# Add project name if set
PROJECT_NAME="${I3PM_PROJECT_NAME:-}"
if [ -n "$PROJECT_NAME" ]; then
    NOTIFICATION_BODY="${NOTIFICATION_BODY}\n\n🔖 Project: ${PROJECT_NAME}"
fi

echo "Step 2: Expected notification content:"
echo "----------------------------------------"
echo -e "$NOTIFICATION_BODY"
echo "----------------------------------------"
echo ""

echo "Step 3: Triggering notification..."
echo ""

# Send notification using notify-send directly for testing
notify-send \
    -i "robot" \
    -u normal \
    --transient \
    -A "focus=🖥️  Return to Window" \
    -A "dismiss=Dismiss" \
    "Claude Code Ready" \
    "$(echo -e "$NOTIFICATION_BODY")" 2>/dev/null || true

echo "==== USER VERIFICATION REQUIRED ===="
echo ""
echo "Check the notification and verify it contains:"
echo "  ✓ Message preview: 'I've completed updating your NixOS...'"
echo "  ✓ Activity summary: '1 bash, 2 edits, 1 writes, 2 reads'"
echo "  ✓ Modified files: configuration.nix, daemon.nix, helper.nix"
echo "  ✓ Directory: nixos-090-notification-callback"
if [ -n "$PROJECT_NAME" ]; then
    echo "  ✓ Project name: $PROJECT_NAME"
fi
echo ""
echo "Does the notification display all expected content? (y/n)"
read -r RESPONSE

# Cleanup
rm -f "$TEST_TRANSCRIPT"

if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
    echo ""
    echo "✅ TEST PASSED: Notification content displays correctly"
    echo "  - Message preview shown"
    echo "  - Activity summary accurate"
    echo "  - Modified files listed"
    echo "  - Context information complete"
    exit 0
else
    echo ""
    echo "❌ TEST FAILED: Notification content incomplete or inaccurate"
    echo "  Please review the notification content manually"
    exit 1
fi
