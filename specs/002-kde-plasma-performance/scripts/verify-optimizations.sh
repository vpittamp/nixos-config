#!/usr/bin/env bash
# Verification Script for KDE Plasma Optimizations
# Task: T043 - Complete verification script
# Purpose: Verify all performance optimizations are correctly applied

set -euo pipefail

echo "=== KDE Plasma Optimization Verification ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track overall status
PASS_COUNT=0
FAIL_COUNT=0

# Helper function for checks
check() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓${NC} $name: $actual"
        ((PASS_COUNT++))
        return 0
    else
        echo -e "${RED}✗${NC} $name: Expected '$expected', got '$actual'"
        ((FAIL_COUNT++))
        return 1
    fi
}

# 1. Check Compositor Backend
echo "1. Compositor Configuration"
echo "----------------------------"
BACKEND=$(kreadconfig5 --file kwinrc --group Compositing --key Backend 2>/dev/null || echo "unknown")
check "Compositor Backend" "XRender" "$BACKEND"

MAXFPS=$(kreadconfig5 --file kwinrc --group Compositing --key MaxFPS 2>/dev/null || echo "unknown")
check "Compositor MaxFPS" "30" "$MAXFPS"

VSYNC=$(kreadconfig5 --file kwinrc --group Compositing --key VSync 2>/dev/null || echo "unknown")
check "VSync Disabled" "false" "$VSYNC"

echo ""

# 2. Check Visual Effects
echo "2. Visual Effects"
echo "----------------------------"
BLUR=$(kreadconfig5 --file kwinrc --group Plugins --key blurEnabled 2>/dev/null || echo "unknown")
check "Blur Disabled" "false" "$BLUR"

CONTRAST=$(kreadconfig5 --file kwinrc --group Plugins --key contrastEnabled 2>/dev/null || echo "unknown")
check "Contrast Disabled" "false" "$CONTRAST"

TRANSLUCENCY=$(kreadconfig5 --file kwinrc --group Plugins --key kwin4_effect_translucencyEnabled 2>/dev/null || echo "unknown")
check "Translucency Disabled" "false" "$TRANSLUCENCY"

WOBBLY=$(kreadconfig5 --file kwinrc --group Plugins --key wobblywindowsEnabled 2>/dev/null || echo "unknown")
check "Wobbly Windows Disabled" "false" "$WOBBLY"

echo ""

# 3. Check Animations
echo "3. Animation Configuration"
echo "----------------------------"
ANIM_FACTOR=$(kreadconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor 2>/dev/null || echo "unknown")
check "Animation Duration Factor" "0" "$ANIM_FACTOR"

echo ""

# 4. Check Services
echo "4. Background Services"
echo "----------------------------"
if pgrep -f baloo_file > /dev/null 2>&1; then
    echo -e "${RED}✗${NC} Baloo: Running (should be stopped)"
    ((FAIL_COUNT++))
else
    echo -e "${GREEN}✓${NC} Baloo: Stopped"
    ((PASS_COUNT++))
fi

if pgrep -f akonadi > /dev/null 2>&1; then
    echo -e "${RED}✗${NC} Akonadi: Running (should be stopped)"
    ((FAIL_COUNT++))
else
    echo -e "${GREEN}✓${NC} Akonadi: Stopped"
    ((PASS_COUNT++))
fi

BALOO_ENABLED=$(kreadconfig5 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled" 2>/dev/null || echo "unknown")
check "Baloo Indexing Disabled" "false" "$BALOO_ENABLED"

echo ""

# 5. Check Qt Platform
echo "5. Qt Platform Configuration"
echo "----------------------------"
QT_PLATFORM="${QT_QPA_PLATFORM:-unknown}"
check "Qt Platform" "xcb" "$QT_PLATFORM"

echo ""

# 6. Check Resource Usage
echo "6. Resource Usage"
echo "----------------------------"
if command -v htop > /dev/null 2>&1; then
    # Get kwin_x11 CPU usage (this is approximate)
    KWIN_PID=$(pgrep kwin_x11 || echo "")
    if [ -n "$KWIN_PID" ]; then
        KWIN_CPU=$(ps -p $KWIN_PID -o %cpu= | xargs)
        echo "KWin CPU usage: ${KWIN_CPU}% (target: < 20%)"

        # Check if below threshold
        if (( $(echo "$KWIN_CPU < 20" | bc -l 2>/dev/null || echo "0") )); then
            echo -e "${GREEN}✓${NC} CPU usage acceptable"
            ((PASS_COUNT++))
        else
            echo -e "${YELLOW}⚠${NC} CPU usage may be high (target < 20%)"
        fi
    else
        echo -e "${YELLOW}⚠${NC} KWin not running (cannot measure CPU)"
    fi
else
    echo "htop not available - skipping CPU check"
fi

# RAM usage
FREE_RAM=$(free -h | grep Mem | awk '{print $7}')
echo "Available RAM: $FREE_RAM"

echo ""

# 7. Summary
echo "=== Verification Summary ==="
echo "----------------------------"
echo -e "Passed checks: ${GREEN}$PASS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "Failed checks: ${RED}$FAIL_COUNT${NC}"
    echo ""
    echo "Some optimizations are not applied correctly."
    echo "Please review the failed checks above."
    exit 1
else
    echo -e "Failed checks: ${GREEN}0${NC}"
    echo ""
    echo -e "${GREEN}✅ All optimizations verified successfully!${NC}"
    exit 0
fi
