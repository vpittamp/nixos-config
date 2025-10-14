# RustDesk Configuration Guide for KDE Plasma VMs

**Feature ID**: 002
**Purpose**: Optimal RustDesk remote desktop configuration for KubeVirt VMs
**Last Updated**: 2025-10-14

## Overview

This guide provides step-by-step instructions for configuring RustDesk for optimal performance when accessing KDE Plasma desktop in KubeVirt VMs over LAN and VPN connections.

## Prerequisites

- RustDesk client installed on local machine
- KubeVirt VM running with KDE Plasma optimizations (US1-US5 implemented)
- Network access to VM (LAN or Tailscale VPN)
- VM compositor configured with 30 FPS limit

## Quick Start

### For LAN Connections (Recommended Settings)

1. **Codec**: VP8 or H.264
2. **Quality**: 85%
3. **FPS**: 30
4. **Connection**: Direct IP

### For VPN Connections (Tailscale)

1. **Codec**: VP9
2. **Quality**: 75%
3. **FPS**: 30
4. **Connection**: Direct IP (Tailscale)

---

## Detailed Configuration Steps

### Step 1: Get VM IP Address

**On the VM**, find your IP address:

```bash
# For Tailscale VPN
tailscale ip -4
# Example output: 100.64.x.x

# For LAN (if on same network)
ip addr show | grep "inet " | grep -v 127.0.0.1
# Example output: 192.168.1.x or 10.x.x.x
```

### Step 2: Open RustDesk Client

On your **local machine**:
1. Launch RustDesk application
2. You'll see the main connection window

### Step 3: Connect to VM

**Option A: Direct IP Connection** (Recommended)
1. In the "Remote ID" field, enter the VM's IP address:
   - Tailscale: `100.64.x.x`
   - LAN: `192.168.x.x`
2. Click "Connect"
3. Enter password (if configured)

**Option B: RustDesk ID Connection** (Fallback)
1. On VM, note the RustDesk ID displayed
2. In client, enter the RustDesk ID
3. Click "Connect"

### Step 4: Configure Display Settings

**During Active Connection**:
1. Click the settings/gear icon (usually top-right of RustDesk window)
2. Navigate to "Display" or "Image Quality" tab

**Configure These Settings**:

#### Image Quality
- **For LAN**: Set to **85-90%**
- **For VPN**: Set to **75-80%**
- **For Slow Connection**: Set to **60-70%**

#### Codec Selection
- **VP8**: Best for low latency (LAN connections)
  - Pros: Fast encoding, low latency
  - Cons: Higher bandwidth than VP9

- **VP9**: Best for compression (VPN connections)
  - Pros: Better compression, lower bandwidth
  - Cons: Slightly higher latency

- **H.264**: Best for hardware acceleration
  - Pros: Excellent quality/bandwidth ratio, hardware support
  - Cons: May not be available on all systems

**Recommendation**: Start with **VP8** for LAN, **VP9** for VPN

#### Frame Rate
- **Set to 30 FPS** (matches compositor MaxFPS setting)
- Lower to 20-25 FPS only if connection is very slow

#### Other Settings
- **Adaptive Bitrate**: Disable for consistent quality
- **Hardware Acceleration**: Enable if available on your client machine
- **View Mode**: "Original" or "Scale" based on preference

### Step 5: Verify Connection Quality

**Check RustDesk Connection Stats**:
1. Look for connection statistics in RustDesk window (usually bottom-right or in settings)
2. Verify:
   - **Connection type**: "Direct" (not "Relay")
   - **Latency**: < 50ms (LAN) or < 100ms (VPN)
   - **FPS**: Steady 25-30
   - **Bandwidth**: < 30 Mbps for 1080p

**If Using Relay**:
- Exit connection
- Verify VM IP address is correct
- Ensure no firewall blocking direct connection
- Try connecting with direct IP again

---

## Codec Comparison

| Codec | Best For | Quality | Bandwidth | Latency | CPU Usage |
|-------|----------|---------|-----------|---------|-----------|
| **VP8** | LAN, Real-time | Good | 15-25 Mbps | Low | Low |
| **VP9** | VPN, Quality | Excellent | 10-20 Mbps | Medium | Medium |
| **H.264** | General | Excellent | 10-20 Mbps | Low | Low (if HW accel) |

---

## Quality vs. Bandwidth Trade-offs

### High Quality (90%) - LAN Only
- **Bandwidth**: 25-30 Mbps
- **Visual quality**: Excellent, near-lossless
- **Use case**: Design work, code review, detailed visuals
- **Network**: LAN only (too much for VPN)

### Balanced Quality (80-85%) - LAN Default
- **Bandwidth**: 15-25 Mbps
- **Visual quality**: Very good, minor compression
- **Use case**: General productivity, browsing, coding
- **Network**: LAN or fast VPN

### Good Quality (70-75%) - VPN Default
- **Bandwidth**: 10-15 Mbps
- **Visual quality**: Good, noticeable compression
- **Use case**: Remote work over VPN, normal tasks
- **Network**: VPN, slower connections

### Acceptable Quality (60-70%) - Slow Connections
- **Bandwidth**: 5-10 Mbps
- **Visual quality**: Acceptable, visible compression
- **Use case**: Slow networks, mobile data
- **Network**: High-latency or limited bandwidth

---

## Connection Types

### Direct IP Connection (Recommended)

**Advantages**:
- Lower latency (no relay hop)
- Better security (direct E2E encryption)
- More reliable
- Faster connection establishment

**Setup**:
1. Use Tailscale IP (`tailscale ip -4`) or LAN IP
2. Enter IP in RustDesk "Remote ID" field
3. Connect directly

**Verification**:
- Connection stats should show "Direct" or "P2P"
- Latency should be < 50ms (LAN) or ping time (VPN)

### RustDesk ID Connection (Relay)

**When to Use**:
- Direct IP not accessible
- Behind restrictive firewall
- No VPN available

**Disadvantages**:
- Higher latency (relay server hop)
- Dependency on RustDesk relay servers
- Potentially less reliable

---

## Troubleshooting

### Issue: Connection is Laggy or Slow

**Diagnosis**:
1. Check connection type (Direct vs Relay)
2. Measure network latency: `ping <vm-ip>`
3. Check RustDesk bandwidth usage
4. Verify compositor FPS setting on VM

**Solutions**:
- Ensure using direct IP connection
- Lower quality setting (85% → 75%)
- Try different codec (VP8 ↔ VP9)
- Reduce FPS (30 → 25)
- Verify network not congested

### Issue: Poor Video Quality

**Solutions**:
- Increase quality setting (75% → 85%)
- Try H.264 codec if available
- Verify RustDesk FPS matches compositor FPS (both 30)
- Check network bandwidth sufficient

### Issue: Connection Drops Frequently

**Solutions**:
- Verify Tailscale connection stable
- Check firewall settings
- Use relay connection as fallback
- Test network stability with `ping -c 100 <vm-ip>`

### Issue: High Bandwidth Usage

**Solutions**:
- Lower quality setting
- Switch to VP9 codec (better compression)
- Reduce FPS to 25 or 20
- Enable adaptive bitrate (if connection unstable)

### Issue: Cursor Lag or Jumpiness

**Solutions**:
- Verify compositor using XRender backend (VM-side)
- Ensure effects disabled (VM-side)
- Try lower latency codec (VP8 or H.264)
- Check network latency < 100ms

---

## Advanced Configuration

### Custom Keyboard Shortcuts

RustDesk allows custom shortcuts. Useful bindings:

- **Ctrl+Alt+Delete** → Send to remote desktop
- **Win+L** → Lock remote screen
- **Ctrl+Alt+F12** → Toggle fullscreen

### Multi-Monitor Support

If VM has multiple displays configured:
1. RustDesk settings → Display
2. Select "All Monitors" or specific monitor
3. Adjust scaling per monitor if needed

### File Transfer

Transfer files between client and VM:
1. Click file transfer icon in RustDesk
2. Drag and drop files
3. Files transferred directly (not via relay)

---

## Performance Benchmarks

### Expected Performance (After VM Optimization)

| Scenario | Latency | Bandwidth | Quality | Usability |
|----------|---------|-----------|---------|-----------|
| LAN (VP8, 85%) | 20-40ms | 20-25 Mbps | Excellent | 9/10 |
| VPN (VP9, 75%) | 50-80ms | 12-18 Mbps | Very Good | 8/10 |
| Slow (VP9, 65%) | 100-150ms | 8-12 Mbps | Good | 7/10 |

### Comparison with xrdp

RustDesk advantages:
- Lower latency (50% reduction)
- Better codec options
- Hardware acceleration support
- More responsive cursor tracking

xrdp advantages:
- Simpler setup
- Widely compatible
- Lower resource usage

**Recommendation**: Use RustDesk for primary access, keep xrdp as fallback

---

## Client-Specific Notes

### Windows Client
- Hardware acceleration usually available (enable in settings)
- Best codec: H.264 (hardware accelerated)

### macOS Client
- Hardware acceleration available on M1/M2 Macs
- Best codec: H.264 or VP8

### Linux Client
- Hardware acceleration depends on GPU
- Best codec: VP8 (most compatible)

### Mobile Clients (iOS/Android)
- Limited to VP8 or VP9
- Reduce quality to 60-70% for mobile data
- Use WiFi for best experience

---

## Summary

**Recommended Starting Configuration**:

1. **Connection**: Direct IP (Tailscale or LAN)
2. **Codec**: VP8 (LAN) or VP9 (VPN)
3. **Quality**: 85% (LAN) or 75% (VPN)
4. **FPS**: 30
5. **Verify**: Connection type shows "Direct"

**Fine-Tuning**:
- Adjust quality based on bandwidth availability
- Switch codecs if latency or quality issues
- Lower FPS only if necessary for slow connections

For questions or issues, refer to US6 test results in benchmarks/us6-rustdesk.md

---

**Version**: 1.0
**Status**: Initial implementation guide
**Next Update**: After T033-T036 testing complete
