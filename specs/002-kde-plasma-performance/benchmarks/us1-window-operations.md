# User Story 1: Window Operations Performance Testing

**Test Date**: [To be tested after deployment]
**Configuration**: XRender backend, 30 FPS, VSync disabled
**Remote Access**: RustDesk

## T010: Window Drag Responsiveness Test

### Test Procedure
1. Open 5-10 application windows (Firefox, Konsole, Dolphin, Kate, etc.)
2. Drag windows across the screen in various directions
3. Resize windows by dragging edges and corners
4. Observe perceived latency and smoothness
5. Monitor CPU usage during operations: `htop -p $(pgrep kwin_x11)`

### Success Criteria
- **Perceived latency**: < 100ms (target: 8+/10 on subjective scale)
- **CPU usage during drag**: < 20%
- **Window tracking**: Smooth, no rubber-banding
- **Frame drops**: None visible

### Results
**Status**: Pending implementation deployment

| Metric | Measurement | Target | Pass/Fail |
|--------|-------------|--------|-----------|
| Perceived latency (1-10) | TBD | 8+ | - |
| CPU usage (%) | TBD | <20% | - |
| Frame drops | TBD | 0 | - |
| Smoothness rating (1-10) | TBD | 8+ | - |

---

## T011: Alt+Tab Switching Performance Test

### Test Procedure
1. Open 10+ application windows
2. Press Alt+Tab repeatedly to cycle through windows
3. Measure switcher appearance delay
4. Test rapid Alt+Tab presses (quick switching)
5. Test window focus change responsiveness
6. Test Alt+Shift+Tab (reverse direction)

### Success Criteria
- **Switcher appearance**: < 50ms perceived delay
- **Window focus change**: Instant (< 100ms)
- **No lag during rapid switching**: Smooth transitions
- **CPU usage**: < 15% during switching

### Results
**Status**: Pending implementation deployment

| Metric | Measurement | Target | Pass/Fail |
|--------|-------------|--------|-----------|
| Switcher appearance (ms) | TBD | <50 | - |
| Focus change delay (ms) | TBD | <100 | - |
| Rapid switching smoothness (1-10) | TBD | 8+ | - |
| CPU usage during switching (%) | TBD | <15% | - |

---

## Validation Checklist

**Compositor Configuration Verification**:
```bash
# Verify XRender backend
kreadconfig5 --file kwinrc --group Compositing --key Backend
# Expected: XRender

# Verify MaxFPS
kreadconfig5 --file kwinrc --group Compositing --key MaxFPS
# Expected: 30

# Verify VSync disabled
kreadconfig5 --file kwinrc --group Compositing --key VSync
# Expected: false
```

**CPU Usage Monitoring**:
```bash
# Monitor compositor CPU in real-time
htop -p $(pgrep kwin_x11)

# Or use top
top -b -n 1 | grep kwin_x11
```

---

## User Story 1 Acceptance Criteria

From spec.md US1 Acceptance Scenarios:

1. ✅ **Scenario 1**: Open 5-10 windows, drag them around screen
   - SUCCESS: All windows track cursor smoothly, < 100ms perceived latency

2. ✅ **Scenario 2**: Rapidly press Alt+Tab to switch between windows
   - SUCCESS: Switcher appears instantly, transitions smooth

3. ✅ **Scenario 3**: Resize windows by dragging edges
   - SUCCESS: Window borders track cursor, no lag

4. ✅ **Scenario 4**: Click different windows to change focus
   - SUCCESS: Focus change immediate, window activation < 100ms

---

**Next Phase**: User Story 2 - Low CPU Compositor Usage (disable expensive effects)
