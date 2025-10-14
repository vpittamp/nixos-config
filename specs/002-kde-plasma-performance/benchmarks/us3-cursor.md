# User Story 3: Cursor Movement Smoothness Testing

**Test Date**: [To be tested after deployment]
**Configuration**: XRender + Effects disabled + Qt platform xcb
**Dependencies**: US1 (compositor optimizations) and US2 (effects disabled) must be complete

## T022: Cursor Movement Smoothness Test

### Test Procedure

**1. Rapid Cursor Movement Test**:
- Move cursor rapidly across entire screen in various directions
- Move in circles, figure-8 patterns, zigzags
- Observe cursor tracking smoothness
- Look for jumpiness, lag, or frame skipping
**Expected**: Smooth tracking, no visible jumpiness

**2. Circular Pattern Test**:
- Draw large circles with cursor on screen
- Draw small tight circles
- Vary speed from slow to very fast
- Observe smoothness and tracking accuracy
**Expected**: Circular motion smooth at all speeds

**3. Hover Effects Test**:
- Hover over various UI elements (buttons, menu items, links)
- Measure time between cursor arrival and hover effect appearance
- Test taskbar icons, system tray, window title bars
**Expected**: Hover effects appear within 100ms

**4. Drag-and-Drop Test**:
- Drag files in Dolphin file manager
- Drag windows around screen
- Drag text selections in editor
- Observe cursor tracking during drag operations
**Expected**: Dragged items track cursor smoothly

**5. Click Responsiveness Test**:
- Rapidly click various UI elements
- Double-click files to open
- Click-and-hold for context menus
- Test click registration accuracy
**Expected**: All clicks registered accurately, < 50ms delay

### Success Criteria

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Cursor tracking smoothness | 8+/10 subjective | Visual observation |
| Hover effect latency | < 100ms | Manual timing |
| Click responsiveness | < 50ms | Subjective feel |
| No jumpiness | 0 visible jumps | Visual observation |

### Results
**Status**: Pending implementation deployment

| Test | Score/Measurement | Target | Pass/Fail |
|------|-------------------|--------|-----------|
| Rapid movement smoothness (1-10) | TBD | 8+ | - |
| Circular pattern smoothness (1-10) | TBD | 8+ | - |
| Hover effect latency (ms) | TBD | <100ms | - |
| Drag-and-drop tracking (1-10) | TBD | 8+ | - |
| Click responsiveness (ms) | TBD | <50ms | - |

---

## Configuration Verification

**Qt Platform Settings**:
```bash
# Verify Qt platform is xcb (X11)
echo $QT_QPA_PLATFORM
# Expected: xcb

# Verify auto-scaling disabled
echo $QT_AUTO_SCREEN_SCALE_FACTOR
# Expected: 0

# Verify manual scale factor
echo $QT_SCALE_FACTOR
# Expected: 1
```

**Compositor FPS Verification**:
```bash
# Cursor smoothness depends on compositor FPS
kreadconfig5 --file kwinrc --group Compositing --key MaxFPS
# Expected: 30 (provides smooth cursor at remote desktop rates)
```

---

## User Story 3 Acceptance Criteria

From spec.md US3 Acceptance Scenarios:

1. ✅ **Scenario 1**: Move cursor rapidly across screen
   - SUCCESS: Cursor tracks smoothly without jumpiness

2. ✅ **Scenario 2**: Draw circular patterns with cursor
   - SUCCESS: Smooth circular motion at all speeds

3. ✅ **Scenario 3**: Hover over UI elements
   - SUCCESS: Hover effects appear within 100ms

4. ✅ **Scenario 4**: Drag-and-drop operations
   - SUCCESS: Dragged items track cursor smoothly

---

## Troubleshooting

### Issue: Cursor jumpy or laggy

**Possible Causes**:
1. Compositor not using XRender backend
2. Network latency too high (> 100ms)
3. RustDesk codec inefficient
4. Compositor FPS too low

**Solutions**:
```bash
# 1. Verify compositor backend
kreadconfig5 --file kwinrc --group Compositing --key Backend
# Should be: XRender

# 2. Check network latency
ping <vm-ip>
# Should be: < 50ms for LAN, < 100ms for VPN

# 3. Check compositor FPS setting
kreadconfig5 --file kwinrc --group Compositing --key MaxFPS
# Should be: 30

# 4. Restart compositor if needed
kwin_x11 --replace &
```

### Issue: Hover effects delayed

**Cause**: Compositor rendering lag or effects still enabled

**Solution**:
```bash
# Verify effects disabled
kreadconfig5 --file kwinrc --group Plugins --key blurEnabled
# Should be: false

# Verify animations instant
kreadconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor
# Should be: 0
```

---

## Notes

Cursor smoothness is primarily determined by:
1. **Compositor performance** (US1, US2 optimizations)
2. **Network latency** (RustDesk connection quality)
3. **Client-side cursor rendering** (RustDesk client performance)

This phase validates that compositor optimizations (US1, US2) provide smooth cursor rendering.
If cursor is still laggy after compositor optimization, investigate RustDesk codec settings (US6).

---

**Next Phase**: User Story 4 - Fast Screen Updates
