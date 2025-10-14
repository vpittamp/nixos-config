# User Story 4: Screen Update Performance Testing

**Test Date**: [To be tested after deployment]
**Configuration**: XRender + 30 FPS + Effects disabled
**Dependencies**: US1, US2, US3 compositor optimizations complete

## T023: Browser Scrolling Performance Test

### Test Procedure
1. Open Firefox browser
2. Navigate to long web page (e.g., Wikipedia article, news site)
3. Scroll rapidly using:
   - Mouse wheel
   - Scrollbar dragging
   - Page Down key
   - Touchpad gestures (if applicable)
4. Observe visual smoothness and frame rate
5. Check for tearing or artifacts

### Success Criteria
- **Smoothness**: 25-30 FPS rendering
- **Tearing**: None visible
- **Frame drops**: Minimal (< 5% frames dropped)
- **Scrolling feel**: Smooth, not choppy

### Results
**Status**: Pending implementation deployment

| Metric | Measurement | Target | Pass/Fail |
|--------|-------------|--------|-----------|
| Perceived FPS | TBD | 25-30 | - |
| Tearing visible | TBD | No | - |
| Frame drops (%) | TBD | <5% | - |
| Smoothness rating (1-10) | TBD | 8+ | - |

---

## T024: Document Editor Typing Latency Test

### Test Procedure
1. Open text editor (Kate or LibreOffice Writer)
2. Type rapidly (aim for 80-100 WPM)
3. Type long paragraphs continuously
4. Measure perceived latency between keypress and character appearance
5. Test with syntax highlighting (Kate) and rich formatting (LibreOffice)

### Success Criteria
- **Typing latency**: < 50ms perceived delay
- **No lag during fast typing**: Characters appear immediately
- **No dropped keystrokes**: All characters registered
- **Syntax highlighting update**: Immediate

### Results
**Status**: Pending implementation deployment

| Metric | Measurement | Target | Pass/Fail |
|--------|-------------|--------|-----------|
| Perceived latency (ms) | TBD | <50ms | - |
| Dropped keystrokes | TBD | 0 | - |
| Fast typing smoothness (1-10) | TBD | 8+ | - |
| Syntax highlighting lag | TBD | None | - |

---

## T025: File Manager Scrolling Test

### Test Procedure
1. Open Dolphin file manager
2. Navigate to directory with many files (100+ items)
3. Switch to different view modes:
   - Icons view
   - Compact view
   - Details view
4. Scroll through list rapidly using mouse wheel
5. Observe smoothness and rendering performance

### Success Criteria
- **Scrolling smoothness**: No visible choppiness
- **Icon rendering**: Smooth, no pop-in delays
- **Frame rate**: Steady 25-30 FPS
- **CPU usage**: < 25% during scrolling

### Results
**Status**: Pending implementation deployment

| Metric | Measurement | Target | Pass/Fail |
|--------|-------------|--------|-----------|
| Scrolling smoothness (1-10) | TBD | 8+ | - |
| Icon pop-in delay | TBD | None | - |
| Frame rate consistency | TBD | Steady | - |
| CPU usage (%) | TBD | <25% | - |

---

## T026: RustDesk Screen Update Compression Test

### Test Procedure
1. Connect to VM via RustDesk from remote client
2. Perform screen update operations:
   - Scroll web page
   - Type in document
   - Open/close windows
   - Play short video clip (if applicable)
3. Measure delay between local action and remote screen update
4. Monitor RustDesk connection statistics:
   - Bandwidth usage
   - Frame rate
   - Latency
   - Codec efficiency

### Success Criteria
- **Screen update delay**: < 100ms over LAN
- **Screen update delay**: < 150ms over VPN
- **Bandwidth usage**: < 30 Mbps for 1080p
- **Frame rate**: Steady 25-30 FPS

### Results
**Status**: Pending implementation deployment

| Metric | Measurement (LAN) | Measurement (VPN) | Target | Pass/Fail |
|--------|-------------------|-------------------|--------|-----------|
| Update delay (ms) | TBD | TBD | <100ms (LAN), <150ms (VPN) | - |
| Bandwidth (Mbps) | TBD | TBD | <30 Mbps | - |
| Frame rate | TBD | TBD | 25-30 FPS | - |
| Connection quality (1-10) | TBD | TBD | 8+ | - |

**RustDesk Connection Stats** (from RustDesk UI):
```
Codec: [TBD - VP8/VP9/H.264]
Quality: [TBD - %]
FPS: [TBD]
Bandwidth: [TBD - Mbps]
Latency: [TBD - ms]
Connection type: [TBD - direct/relay]
```

---

## Configuration Verification

**Compositor FPS Settings**:
```bash
# Verify MaxFPS set to 30
kreadconfig5 --file kwinrc --group Compositing --key MaxFPS
# Expected: 30

# Verify VSync disabled (lower latency)
kreadconfig5 --file kwinrc --group Compositing --key VSync
# Expected: false
```

**RustDesk FPS Alignment**:
- Compositor MaxFPS: 30
- RustDesk client FPS: Should also be set to 30
- **Why**: Matching FPS prevents frame drops or wasted rendering

---

## User Story 4 Acceptance Criteria

From spec.md US4 Acceptance Scenarios:

1. ✅ **Scenario 1**: Scroll through long document in browser
   - SUCCESS: Smooth 25-30 FPS rendering, no visible tearing

2. ✅ **Scenario 2**: Type rapidly in document editor
   - SUCCESS: Text appears immediately, < 50ms latency

3. ✅ **Scenario 3**: Scroll through large file list in Dolphin
   - SUCCESS: Smooth scrolling, no frame drops

4. ✅ **Scenario 4**: Monitor screen update latency over RustDesk
   - SUCCESS: Screen updates appear within 100ms

---

## Troubleshooting

### Issue: Choppy scrolling in browser

**Possible Causes**:
1. Compositor FPS too low
2. Browser GPU acceleration conflicting with software rendering
3. Network latency

**Solutions**:
```bash
# 1. Verify compositor FPS
kreadconfig5 --file kwinrc --group Compositing --key MaxFPS
# Should be: 30

# 2. Test Firefox GPU acceleration settings
# In Firefox: about:config
# layers.acceleration.force-enabled = false (force software rendering)

# 3. Check network latency
ping <vm-ip>
```

### Issue: Typing lag in editors

**Possible Causes**:
1. Compositor overhead
2. Syntax highlighting too expensive
3. Font rendering issues

**Solutions**:
```bash
# 1. Verify effects disabled
kreadconfig5 --file kwinrc --group Plugins --key blurEnabled
# Should be: false

# 2. In Kate: Disable resource-heavy highlighting
# Settings → Configure Kate → Editor → Appearance → Scheme: Breeze Light/Dark (simpler)

# 3. Restart compositor
kwin_x11 --replace &
```

### Issue: High latency over RustDesk

**Possible Causes**:
1. Using relay server instead of direct connection
2. Inefficient codec
3. Network congestion

**Solutions**:
- Check RustDesk connection type (should be "direct")
- Try different codecs (VP8 → H.264)
- Test over Tailscale VPN if using internet connection
- Reduce RustDesk quality setting if bandwidth limited

---

## Performance Analysis

**Screen Update Pipeline**:
```
User action → Compositor (30 FPS) → Screen buffer → RustDesk encode → Network → RustDesk client → Display
   ↑                  ↑                    ↑                 ↑
   0ms             16-33ms             33-50ms           50-100ms (total)
```

**Bottleneck Identification**:
1. **Compositor**: Optimized in US1/US2 (XRender + no effects)
2. **Screen buffer**: XRender renders to buffer at 30 FPS
3. **RustDesk encode**: Codec efficiency (test in US6)
4. **Network**: Latency and bandwidth (infrastructure dependent)

**Expected total latency**: 50-100ms for local action to appear on remote display

---

**Next Phase**: User Story 5 - Minimal Resource Overhead (Service optimization)
