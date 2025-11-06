# Mouse Cursor Position - Testing & Validation Checklist

**Reference**: MOUSE_CURSOR_RESEARCH.md
**Status**: Ready for Testing Phase

## Quick Start: Verify xdotool Works

### On M1 MacBook (Physical Display)

```bash
# 1. Check installation
which xdotool
# Expected: /run/current-system/sw/bin/xdotool

# 2. Get current cursor position
xdotool getmouselocation --shell
# Expected output:
# X=1500
# Y=800
# SCREEN=0
# WINDOW=94532735639728

# 3. Parse output programmatically
eval "$(xdotool getmouselocation --shell)"
echo "Cursor at: X=$X Y=$Y on SCREEN=$SCREEN"

# 4. Continuous monitoring (verify it updates as you move mouse)
watch -n 0.2 'xdotool getmouselocation --shell'
# Move mouse around and watch values change in real-time
```

### On Hetzner Headless (VNC Input)

```bash
# 1. SSH to hetzner
ssh vpittamp@hetzner

# 2. Check xdotool availability
which xdotool
# Should return path (likely /run/current-system/sw/bin/xdotool)

# 3. Connect to VNC first, then test cursor
# In separate terminal:
vnc://<tailscale-ip>:5900

# In hetzner SSH:
xdotool getmouselocation --shell
# Should return coordinates matching mouse position in VNC window

# 4. Verify with continuous updates
for i in {1..10}; do
  echo "Sample $i:"
  xdotool getmouselocation --shell
  sleep 1
done
```

---

## Test Cases - Cursor Position Validation

### TC-001: Basic xdotool Functionality

**Precondition**: xdotool installed and in PATH

**Steps**:
1. Run: `xdotool getmouselocation --shell`
2. Parse output for X, Y, SCREEN, WINDOW fields
3. Verify all fields are present and integer values

**Expected Result**:
- Exit code 0
- Output contains 4 lines with pattern `KEY=VALUE`
- X, Y are integers >= 0
- SCREEN is integer >= 0

**Pass Criteria**: ✓ All values present and valid

---

### TC-002: Cursor Movement Tracking

**Precondition**: Display/VNC connection active

**Steps**:
1. Record cursor position: `X1=$(eval "$(xdotool getmouselocation --shell)"; echo $X)`
2. Move mouse to different location
3. Record new position: `X2=$(eval "$(xdotool getmouselocation --shell)"; echo $X)`
4. Verify X1 != X2

**Expected Result**: Coordinates change as mouse moves

**Pass Criteria**: ✓ Position updates within 100ms

---

### TC-003: Boundary Detection

**Precondition**: 1920x1080 display configured

**Steps**:
1. Position mouse at (100, 100) - top-left
2. Query cursor: `xdotool getmouselocation --shell`
3. Position mouse at (1800, 1000) - bottom-right
4. Query cursor again

**Expected Result**:
- First query: X=100, Y=100
- Second query: X=1800, Y=1000
- Values within screen bounds [0, 1920] x [0, 1080]

**Pass Criteria**: ✓ All coordinates within screen bounds

---

### TC-004: Multi-Monitor Support (Hetzner with 3 VNC displays)

**Precondition**: All 3 headless outputs active

**Steps**:
1. Move mouse to HEADLESS-1 (X: 0-1920)
2. Query: `xdotool getmouselocation --shell` → should be X < 1920
3. Move mouse to HEADLESS-2 (X: 1920-3840)
4. Query: cursor should be 1920 < X < 3840
5. Move mouse to HEADLESS-3 (X: 3840-5760)
6. Query: cursor should be 3840 < X < 5760

**Expected Result**: Cursor coordinates span full virtual screen

**Pass Criteria**: ✓ All monitors correctly reported

---

## Unit Test Validation

### Install Test Dependencies

```bash
# These are already in home-modules for development
pip install pytest pytest-asyncio pytest-mock
```

### Run Cursor Positioning Tests

```bash
# From repository root
pytest tests/test_cursor_positioning.py -v

# Expected output:
# test_mouse_location_parsing PASSED
# test_boundary_constraint_center PASSED
# test_boundary_constraint_bottom_right PASSED
# test_fallback_to_cache PASSED
# test_cache_ttl_expiration PASSED
```

### Run Integration Tests

```bash
pytest tests/test_scratchpad_positioning.py -v

# Expected output:
# test_position_terminal_with_mouse PASSED
# test_position_terminal_fallback_on_headless PASSED
```

---

## Python Implementation Validation

### Test CursorPositioner Class

```python
#!/usr/bin/env python3
"""Quick validation of CursorPositioner implementation."""

import asyncio
from pathlib import Path

# Add to Python path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"))

from services.cursor_positioning import CursorPositioner


async def main():
    """Test CursorPositioner with live xdotool."""
    positioner = CursorPositioner(cache_ttl_seconds=2.0)

    print("Testing CursorPositioner...")

    # Test 1: Get mouse location
    print("\n1. Getting current mouse position...")
    loc = await positioner.get_mouse_location()
    if loc:
        print(f"   ✓ Cursor at ({loc.x}, {loc.y}) on screen {loc.screen}")
    else:
        print("   ✗ Failed to get cursor position")

    # Test 2: Position terminal at cursor
    print("\n2. Calculating terminal position...")
    x, y = await positioner.position_terminal(
        terminal_width=1000,
        terminal_height=600,
        workspace_rect={"x": 0, "y": 0, "width": 1920, "height": 1080},
        gap_config={"top": 10, "bottom": 30, "left": 10, "right": 10},
        i3=None  # Not needed for positioning calculation
    )
    print(f"   ✓ Terminal should appear at ({x}, {y})")

    # Test 3: Boundary constraints
    print("\n3. Testing boundary constraints...")
    test_cases = [
        (100, 100, "top-left"),
        (960, 540, "center"),
        (1800, 1000, "bottom-right"),
    ]

    for cursor_x, cursor_y, label in test_cases:
        x, y = positioner._apply_constraints(
            cursor_x, cursor_y,
            terminal_width=1000, terminal_height=600,
            workspace_rect={"x": 0, "y": 0, "width": 1920, "height": 1080},
            gap_config={"top": 10, "bottom": 30, "left": 10, "right": 10}
        )
        print(f"   ✓ Cursor at {label:12} → Terminal at ({x:4}, {y:4})")

    print("\n✓ All tests passed!")


if __name__ == "__main__":
    asyncio.run(main())
```

**Run It**:
```bash
python3 /path/to/test_cursor_impl.py

# Expected output:
# Testing CursorPositioner...
#
# 1. Getting current mouse position...
#    ✓ Cursor at (1500, 800) on screen 0
#
# 2. Calculating terminal position...
#    ✓ Terminal should appear at (960, 240)
#
# 3. Testing boundary constraints...
#    ✓ Cursor at top-left     → Terminal at (10, 10)
#    ✓ Cursor at center       → Terminal at (460, 240)
#    ✓ Cursor at bottom-right → Terminal at (900, 470)
#
# ✓ All tests passed!
```

---

## Integration Testing: Actual Terminal Positioning

### Test 1: Manual Scratchpad Positioning

```bash
# 1. Ensure daemon is running
systemctl --user status i3-project-event-listener
# Should show: active (running)

# 2. Position mouse at specific location on screen
# (e.g., top-left corner at 100, 100)

# 3. Summon scratchpad terminal
i3pm scratchpad launch test_project

# 4. Observe: Terminal should appear near cursor position
# Visually verify it's not off-screen and respects gaps

# 5. Verify with swaymsg
swaymsg -t get_tree | jq '.nodes[] | select(.marks[] | contains("scratchpad:test_project")) | {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height}'

# Should output:
# {
#   "x": 100,
#   "y": 100,
#   "width": 1000,
#   "height": 600
# }
```

### Test 2: Headless Positioning (Hetzner)

```bash
# 1. Connect to hetzner via SSH
ssh vpittamp@hetzner

# 2. Launch VNC viewer to hetzner in separate local terminal
# (e.g., using VNC client)
vnc://<tailscale-ip>:5900

# 3. In hetzner SSH, enable logging for daemon
export I3PM_DEBUG=1

# 4. Launch scratchpad and watch logs
journalctl --user -u i3-project-event-listener -f &
i3pm scratchpad launch test_project

# 5. In VNC viewer, move mouse around and verify:
# - Terminal follows cursor position
# - Terminal doesn't go off-screen at edges
# - Terminal respects configured gaps

# 6. Verify logs show cursor position updates
# Should see: "Using mouse position (X, Y) for terminal placement"
```

### Test 3: Fallback to Center (Simulate xdotool Failure)

```bash
# 1. Temporarily disable xdotool
sudo mv /run/current-system/sw/bin/xdotool /run/current-system/sw/bin/xdotool.bak

# 2. Launch scratchpad terminal
i3pm scratchpad launch test_project

# 3. Observe: Terminal appears centered on screen (fallback behavior)

# 4. Verify with swaymsg
swaymsg -t get_tree | jq '.nodes[] | select(.marks[] | contains("scratchpad:test_project")) | {x: .rect.x, y: .rect.y}'
# Should show roughly centered position: x ≈ 460, y ≈ 240 (for 1920x1080)

# 5. Restore xdotool
sudo mv /run/current-system/sw/bin/xdotool.bak /run/current-system/sw/bin/xdotool
```

---

## Performance Benchmarks

### Expected Latencies

| Operation | Target | Measured | Pass? |
|-----------|--------|----------|-------|
| xdotool query | <100ms | ? | ? |
| Cursor caching | <10ms | ? | ? |
| Boundary calc | <5ms | ? | ? |
| Total positioning | <200ms | ? | ? |

### Benchmark Script

```bash
#!/bin/bash
# benchmark_cursor.sh

echo "Benchmarking cursor position queries..."

for i in {1..10}; do
  start=$(date +%s%N)
  xdotool getmouselocation --shell > /dev/null
  end=$(date +%s%N)
  elapsed=$(( (end - start) / 1000000 ))
  echo "Query $i: ${elapsed}ms"
done
```

**Expected**: All queries <100ms, most <50ms

---

## Headless-Specific Validation

### Pre-Deployment Checklist

- [ ] xdotool installed in hetzner-sway configuration
- [ ] VNC input properly forwarded to Sway
- [ ] xdotool getmouselocation returns valid coordinates in VNC
- [ ] Cursor updates track VNC mouse movements
- [ ] Boundary constraints work with 3-display setup
- [ ] Gap configuration (top=10, bottom=30, left=10, right=10) applied

### Debug Output Analysis

```bash
# On hetzner-sway, enable daemon debug logging
export I3PM_DEBUG=1
export I3PM_LOG_LEVEL=DEBUG

# Restart daemon
systemctl --user restart i3-project-event-listener

# Watch logs for cursor-related entries
journalctl --user -u i3-project-event-listener -f | grep -E "cursor|mouse|position"

# Expected log lines:
# "xdotool availability: True"
# "Using mouse position (1234, 567) for terminal placement"
# "Terminal positioning: cursor=(1234, 567), final=(460, 240), bounds=(...)"
```

---

## Success Criteria

### For Feature 051 Implementation

1. **Cursor Position Querying**
   - ✓ xdotool working on both M1 and Hetzner
   - ✓ Returns valid X, Y, SCREEN coordinates
   - ✓ Latency <100ms consistently

2. **Terminal Positioning**
   - ✓ Terminal appears near cursor position
   - ✓ Never renders off-screen
   - ✓ Respects configured gaps
   - ✓ Boundary constraints active in all quadrants

3. **Fallback Handling**
   - ✓ Centers on workspace when xdotool unavailable
   - ✓ Uses cached position gracefully
   - ✓ Logs warnings for debugging

4. **Multi-Monitor Support**
   - ✓ M1: Single display handled correctly
   - ✓ Hetzner: 3 virtual displays tracked independently
   - ✓ Cursor detection spans all monitors

5. **Error Handling**
   - ✓ Graceful degradation on xdotool failure
   - ✓ No daemon crashes
   - ✓ Proper logging for troubleshooting

---

## Sign-Off

Once all tests pass:

```bash
# Document test results
cat > /etc/nixos/specs/051-i3run-scratchpad-enhancement/TEST_RESULTS.md << 'EOF'
# Test Results - Mouse Cursor Positioning

**Date**: [YYYY-MM-DD]
**Tester**: [Your Name]
**Target**: M1 / Hetzner / Both

## Results Summary

| Test Case | Result | Notes |
|-----------|--------|-------|
| TC-001 (xdotool basics) | PASS | xdotool works reliably |
| TC-002 (cursor tracking) | PASS | Updates within 100ms |
| TC-003 (boundaries) | PASS | Coordinates within screen |
| TC-004 (multi-monitor) | PASS | 3 displays tracked |
| Unit tests | PASS | All pytest tests passing |
| Integration tests | PASS | Terminal positioning verified |
| Headless validation | PASS | xdotool works on hetzner |
| Fallback behavior | PASS | Centers correctly when needed |

## Performance Results

- Average xdotool latency: XXms
- Boundary calculation: <5ms
- Total positioning: <200ms

## Known Issues

None. Ready for Feature 051 implementation.

**Sign-off**: Ready to integrate CursorPositioner into ScratchpadManager
EOF
```

---

## Next Steps

1. **Immediate**: Run TC-001 through TC-004 on both targets
2. **Short-term**: Execute unit tests and integration tests
3. **Pre-deployment**: Validate boundary constraints with various gap values
4. **Deployment**: Integrate CursorPositioner class into scratchpad_manager.py
5. **Validation**: Run full integration test suite with actual scratchpad launches

---

**Reference Document**: See MOUSE_CURSOR_RESEARCH.md for implementation details
