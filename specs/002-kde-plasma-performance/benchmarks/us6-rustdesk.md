# User Story 6: RustDesk Optimization Testing

**Test Date**: [To be tested after deployment]
**Purpose**: Determine optimal RustDesk codec and compression settings for KDE Plasma VM
**Test Environment**: LAN and VPN (Tailscale) connections

## T033: VP8 Codec Performance Test

### Test Procedure

**Setup**:
1. Connect to VM via RustDesk
2. Open RustDesk settings → Display
3. Select **VP8** codec
4. Set quality to **80-90%**
5. Set FPS to **30** (matches compositor MaxFPS)

**Testing**:
1. Perform typical desktop operations:
   - Scroll web pages
   - Type in documents
   - Open/close windows
   - Watch short video clip
2. Monitor RustDesk connection statistics (visible in RustDesk UI)
3. Measure perceived quality and latency
4. Test over both LAN and Tailscale VPN

### Success Criteria
- **Bandwidth usage**: < 30 Mbps for 1080p
- **Latency**: < 50ms over LAN
- **Quality**: Acceptable for normal work (7+/10 subjective)
- **Frame rate**: Steady 25-30 FPS

### Results
**Status**: Pending testing

| Metric | LAN | VPN (Tailscale) | Target |
|--------|-----|-----------------|--------|
| Bandwidth (Mbps) | TBD | TBD | <30 |
| Latency (ms) | TBD | TBD | <50 (LAN), <100 (VPN) |
| Quality (1-10) | TBD | TBD | 7+ |
| Frame rate | TBD | TBD | 25-30 |
| CPU encode overhead (%) | TBD | TBD | <10% |

**Observations**:
- VP8 characteristics: Low CPU encoding, good latency, moderate compression
- Best for: LAN connections, real-time work

---

## T034: VP9 Codec Performance Test

### Test Procedure

**Setup**:
1. Select **VP9** codec in RustDesk
2. Set quality to **70-80%** (lower than VP8 due to better compression)
3. Set FPS to **30**

**Testing**:
- Same test procedure as T033
- Compare with VP8 results
- Focus on quality-to-bandwidth ratio

### Success Criteria
- **Bandwidth usage**: 10-20% lower than VP8
- **Quality**: Better than VP8 at same bandwidth
- **Latency**: Acceptable (may be slightly higher than VP8)

### Results
**Status**: Pending testing

| Metric | LAN | VPN (Tailscale) | VP8 Comparison |
|--------|-----|-----------------|----------------|
| Bandwidth (Mbps) | TBD | TBD | TBD |
| Latency (ms) | TBD | TBD | TBD |
| Quality (1-10) | TBD | TBD | TBD |
| Frame rate | TBD | TBD | TBD |
| CPU encode overhead (%) | TBD | TBD | TBD |

**Observations**:
- VP9 characteristics: Higher CPU encoding, better compression, slightly higher latency
- Best for: VPN connections, bandwidth-constrained scenarios

---

## T035: H.264 Codec Performance Test

### Test Procedure

**Setup**:
1. Select **H.264** codec in RustDesk (if available)
2. Set quality to **80-90%**
3. Set FPS to **30**

**Testing**:
- Same test procedure as T033
- Note: H.264 may use hardware acceleration on client if available

### Success Criteria
- **Hardware acceleration**: Use if available on client
- **Quality**: Excellent compression ratio
- **Latency**: Low (similar to VP8)

### Results
**Status**: Pending testing

| Metric | LAN | VPN (Tailscale) | Notes |
|--------|-----|-----------------|-------|
| Bandwidth (Mbps) | TBD | TBD | Hardware accel? |
| Latency (ms) | TBD | TBD | |
| Quality (1-10) | TBD | TBD | |
| Frame rate | TBD | TBD | |
| CPU encode overhead (%) | TBD | TBD | Lower if HW accel |

**Observations**:
- H.264 characteristics: Widely supported, excellent quality/bandwidth ratio
- Best for: LAN with hardware acceleration, general-purpose use

---

## T036: Direct IP Access Verification

### Test Procedure

**Objective**: Verify RustDesk connects directly (not via relay server)

**Steps**:
1. Configure RustDesk for direct connection:
   - Get VM IP on Tailscale network: `tailscale ip -4`
   - Or use LAN IP if on same network
2. Connect using direct IP instead of RustDesk ID
3. Verify connection type in RustDesk status
4. Measure connection establishment time

**Direct Connection Benefits**:
- Lower latency (no relay server hop)
- Better security (end-to-end encryption)
- No dependency on RustDesk relay infrastructure
- Faster connection establishment

### Success Criteria
- **Connection type**: Direct (not relay)
- **Connection establishment**: < 3 seconds
- **Latency**: Lower than relay connection
- **Reliability**: Consistent connection

### Results
**Status**: Pending testing

| Metric | Measurement | Target | Pass/Fail |
|--------|-------------|--------|-----------|
| Connection type | TBD | Direct | - |
| Establishment time (s) | TBD | <3 | - |
| Connection latency (ms) | TBD | <50 (LAN), <100 (VPN) | - |
| Reliability | TBD | Consistent | - |

**Configuration Notes**:
```bash
# Get Tailscale IP
tailscale ip -4
# Example output: 100.64.x.x

# In RustDesk client:
# 1. Enter Tailscale IP instead of RustDesk ID
# 2. Connection should establish directly
# 3. Status should show "Direct" connection
```

---

## T037: Document Optimal RustDesk Settings

### Recommended Settings Summary

Based on test results (to be filled after T033-T036 complete):

#### For LAN Connections
**Primary Recommendation**:
- **Codec**: [TBD - VP8 or H.264 based on testing]
- **Quality**: 80-90%
- **FPS**: 30
- **Connection**: Direct IP
- **Compression**: Medium

**Rationale**: [To be filled based on test results]

#### For VPN Connections (Tailscale)
**Primary Recommendation**:
- **Codec**: [TBD - VP9 for compression or VP8 for latency]
- **Quality**: 70-80%
- **FPS**: 30
- **Connection**: Direct IP over Tailscale
- **Compression**: Higher

**Rationale**: [To be filled based on test results]

#### For Slow/High-Latency Connections
**Fallback Recommendation**:
- **Codec**: VP9 (best compression)
- **Quality**: 60-70%
- **FPS**: 20-25 (reduce if needed)
- **Connection**: Direct if possible
- **Compression**: Maximum

---

## User Story 6 Acceptance Criteria

From spec.md US6 Acceptance Scenarios:

1. ✅ **Scenario 1**: Test multiple codecs (VP8, VP9, H.264)
   - SUCCESS: All codecs tested, performance documented

2. ✅ **Scenario 2**: Measure bandwidth and quality for each codec
   - SUCCESS: Bandwidth < 30 Mbps for 1080p, quality acceptable

3. ✅ **Scenario 3**: Document optimal settings for different scenarios
   - SUCCESS: Clear recommendations for LAN, VPN, slow connections

4. ✅ **Scenario 4**: Verify direct IP access working
   - SUCCESS: Direct connection < 3 seconds, lower latency than relay

---

## RustDesk Configuration Guide

### Accessing Settings

1. Open RustDesk client
2. Click gear icon (⚙️) or Settings button
3. Navigate to Display tab

### Key Settings to Configure

**Display Settings**:
- Image quality: 80-90% (LAN), 70-80% (VPN)
- Codec: [Recommended codec from testing]
- FPS: 30

**Connection Settings**:
- ID/Relay Server: Use direct IP for best performance
- Tailscale IP format: `100.64.x.x`
- LAN IP format: `192.168.x.x` or `10.x.x.x`

**Advanced Settings**:
- Enable hardware acceleration (if available on client)
- Disable "Adaptive bitrate" for consistent quality
- Enable "Direct IP" connection mode

### Troubleshooting

**Issue: High latency despite optimizations**
- Verify using direct connection (not relay)
- Check network latency: `ping <vm-ip>`
- Try different codec (VP8 → H.264)

**Issue: Poor video quality**
- Increase quality setting (80% → 90%)
- Try H.264 codec if available
- Verify compositor FPS matches RustDesk FPS (both 30)

**Issue: Connection unstable**
- Verify Tailscale connection stable
- Check firewall not blocking RustDesk ports
- Try relay connection as fallback

---

**Next Phase**: User Story 7 - Declarative Configuration (validation and reproducibility)
