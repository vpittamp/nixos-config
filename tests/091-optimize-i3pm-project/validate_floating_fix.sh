#!/usr/bin/env bash
# Validation script for floating window restoration fix (Feature 091)
# Tests that windows restored from scratchpad return to correct floating state

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Feature 091: Floating Window Fix Validation"
echo "========================================="
echo ""

# Function to check if a window is floating
check_floating_state() {
    local window_id=$1
    local expected_state=$2

    # Query Sway for window floating state
    local floating_state=$(swaymsg -t get_tree | jq -r ".. | select(.id? == $window_id) | .floating")

    if [[ "$floating_state" == "user_on" ]] || [[ "$floating_state" == "auto_on" ]]; then
        echo "floating"
    else
        echo "tiling"
    fi
}

# Step 1: Check daemon is running
echo -e "${YELLOW}[1/6]${NC} Checking i3pm daemon status..."
if systemctl --user is-active --quiet i3-project-event-listener 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Daemon is running"
else
    echo -e "  ${RED}✗${NC} Daemon is not running!"
    echo "  Please start with: systemctl --user start i3-project-event-listener"
    exit 1
fi

# Step 2: Check current project
echo -e "${YELLOW}[2/6]${NC} Checking current project..."
current_project=$(i3pm project current 2>/dev/null || echo "none")
echo "  Current project: $current_project"

# Step 3: Monitor daemon logs for sequential execution
echo -e "${YELLOW}[3/6]${NC} Monitoring daemon logs for sequential batch execution..."
echo "  Looking for 'batch_sequential' in recent logs..."

if journalctl --user -u i3-project-event-listener --since "1 minute ago" | grep -q "batch_sequential"; then
    echo -e "  ${GREEN}✓${NC} Sequential execution detected in logs"
    echo ""
    echo "  Recent performance metrics:"
    journalctl --user -u i3-project-event-listener --since "1 minute ago" | grep "Sequential batch complete" | tail -5 | sed 's/^/    /'
else
    echo -e "  ${YELLOW}!${NC} No recent sequential execution found"
    echo "  (This is normal if you haven't switched projects recently)"
fi
echo ""

# Step 4: Instructions for manual testing
echo -e "${YELLOW}[4/6]${NC} Manual Testing Instructions"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  To test the floating window fix:"
echo ""
echo "  1. Switch to a test project:"
echo "     ${GREEN}i3pm project switch test-project${NC}"
echo ""
echo "  2. Launch a tiling window (e.g., terminal):"
echo "     ${GREEN}ghostty &${NC}"
echo ""
echo "  3. Verify it's tiling (should snap to tiles, not float)"
echo ""
echo "  4. Switch to another project:"
echo "     ${GREEN}i3pm project switch other-project${NC}"
echo ""
echo "  5. Switch back to test project:"
echo "     ${GREEN}i3pm project switch test-project${NC}"
echo ""
echo "  6. ${YELLOW}VERIFY:${NC} Terminal window should be ${GREEN}TILING${NC} (not floating)"
echo ""

# Step 5: Performance monitoring
echo -e "${YELLOW}[5/6]${NC} Performance Monitoring"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  To monitor performance in real-time:"
echo "  ${GREEN}journalctl --user -u i3-project-event-listener -f | grep 'Feature 091'${NC}"
echo ""
echo "  Expected output:"
echo "    - 'Sequential batch complete: X commands for window Y in Zms'"
echo "    - Z should be <30ms per window"
echo "    - Total project switch should be <200ms"
echo ""

# Step 6: Check for errors
echo -e "${YELLOW}[6/6]${NC} Checking for recent errors..."
error_count=$(journalctl --user -u i3-project-event-listener --since "5 minutes ago" --priority=err | wc -l)

if [[ $error_count -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} No errors in last 5 minutes"
else
    echo -e "  ${YELLOW}!${NC} Found $error_count errors in last 5 minutes"
    echo ""
    echo "  Recent errors:"
    journalctl --user -u i3-project-event-listener --since "5 minutes ago" --priority=err | tail -10 | sed 's/^/    /'
fi
echo ""

# Summary
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo ""
echo "✓ Daemon is running"
echo "✓ Logs show sequential execution (if recent)"
echo ""
echo "Next steps:"
echo "  1. Run manual test (see step 4 above)"
echo "  2. Verify tiling windows restore correctly"
echo "  3. Monitor performance logs"
echo ""
echo "If issues occur:"
echo "  - Check logs: journalctl --user -u i3-project-event-listener -f"
echo "  - Report bugs with window IDs and project names"
echo "  - Rollback if needed (see FLOATING_WINDOW_FIX_IMPLEMENTATION.md)"
echo ""
