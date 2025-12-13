# Quickstart: Enable Advanced Hardware Features

**Feature**: 115-enable-advanced-hardware-features
**Date**: 2025-12-13

## Overview

This guide provides verification commands and troubleshooting steps for advanced hardware features on ThinkPad (Intel Arc) and Ryzen (NVIDIA RTX 5070) systems.

---

## Build & Apply Configuration

### Step 1: Dry Build (Required)

```bash
# ThinkPad
sudo nixos-rebuild dry-build --flake .#thinkpad

# Ryzen
sudo nixos-rebuild dry-build --flake .#ryzen
```

### Step 2: Apply Configuration

```bash
# ThinkPad
sudo nixos-rebuild switch --flake .#thinkpad

# Ryzen
sudo nixos-rebuild switch --flake .#ryzen
```

---

## Feature Verification

### 1. GPU Hardware Acceleration

**Intel (ThinkPad)**:
```bash
# Check VA-API driver
vainfo
# Expected: VAProfileH264*, VAProfileHEVC*, VAEntrypointEncSlice

# Monitor GPU usage
intel_gpu_top
# Expected: Shows Video, Render, Blitter engines

# Check OpenCL
clinfo | head -20
# Expected: Platform: Intel(R) OpenCL Graphics
```

**NVIDIA (Ryzen)**:
```bash
# Check NVIDIA driver
nvidia-smi
# Expected: Shows RTX 5070, driver version

# Check VA-API via NVIDIA
vainfo
# Expected: VAProfileH264*, VAProfileHEVC*

# Monitor GPU usage
nvtop
# Expected: Interactive GPU monitoring

# Check Vulkan
vulkaninfo | grep -i "gpu"
# Expected: GeForce RTX 5070
```

---

### 2. Firefox Hardware Video Decoding

**Verification Steps**:

1. Open Firefox
2. Navigate to `about:support`
3. Look for "Hardware Video Decoding": **ENABLED**
4. Play a YouTube video (1080p60 or 4K)
5. Monitor GPU:
   - Intel: `intel_gpu_top` - Video engine shows activity
   - NVIDIA: `nvidia-smi dmon` - Dec column shows activity
6. Monitor CPU: Should be <20% during playback

**Troubleshooting**:
```bash
# Check environment variable
echo $LIBVA_DRIVER_NAME
# Expected: "iHD" (Intel) or "nvidia" (NVIDIA)

# Check Firefox Wayland
echo $MOZ_ENABLE_WAYLAND
# Expected: "1"
```

---

### 3. Webcam (V4L2)

```bash
# List video devices
v4l2-ctl --list-devices
# Expected: Shows /dev/video0, /dev/video1, etc.

# Show camera capabilities
v4l2-ctl -d /dev/video0 --all
# Expected: Shows resolution, formats, controls

# Test camera (optional)
ffplay /dev/video0
# Expected: Live camera preview

# Camera controls
cameractrls -d /dev/video0 --list-ctrls
# Expected: Lists brightness, contrast, etc.
```

**Browser Test**:
1. Open Firefox
2. Navigate to https://meet.google.com (or any video call site)
3. Check camera settings - webcam should be listed
4. Enable camera - video should appear

---

### 4. Bluetooth Audio (ThinkPad)

```bash
# List paired devices
bluetoothctl devices
# Expected: Lists paired Bluetooth devices

# Check device info (replace MAC)
bluetoothctl info XX:XX:XX:XX:XX:XX
# Expected: Shows codec capabilities

# Check active audio sink
pactl list sinks | grep -A5 "bluez"
# Expected: Shows codec (LDAC, aptX, AAC, or SBC)

# Check PipeWire Bluetooth
pw-top
# Expected: Shows Bluetooth audio stream with codec info
```

**Codec Priority Verification**:
1. Pair high-quality headphones (Sony WH-1000XM, etc.)
2. Play audio
3. Check codec: `pactl list sinks | grep -i codec`
4. Expected: LDAC (990kbps) if device supports it

---

### 5. Hardware Screen Recording

**wf-recorder with Hardware Encoding**:

```bash
# Intel (VAAPI)
wf-recorder -c h264_vaapi -f recording.mp4

# NVIDIA (NVENC)
wf-recorder -c h264_nvenc -f recording.mp4

# Record specific output
wf-recorder -o eDP-1 -f recording.mp4

# Record region
wf-recorder -g "$(slurp)" -f recording.mp4
```

**Verification**:
1. Start recording with hardware encoder
2. Monitor CPU usage: Should be <30% for 1080p60
3. Check encoder usage:
   - Intel: `intel_gpu_top` - Video engine active
   - NVIDIA: `nvidia-smi dmon` - Enc column active

---

### 6. PipeWire Low-Latency Audio

```bash
# Check PipeWire status
systemctl --user status pipewire pipewire-pulse wireplumber

# Check audio configuration
pw-top
# Expected: Quantum ~256, Rate 48000

# Check latency
pw-profiler
# Expected: <15ms round-trip latency

# List audio devices
pactl list sinks short
pactl list sources short
```

**JACK Applications**:
```bash
# Verify JACK bridge
pw-jack jack_lsp
# Expected: Lists JACK ports through PipeWire
```

---

### 7. Thunderbolt/USB4 (ThinkPad)

```bash
# List Thunderbolt devices
boltctl list
# Expected: Lists connected Thunderbolt devices

# Check device authorization
boltctl info <UUID>
# Expected: Shows authorization status

# Authorize device (if needed)
boltctl authorize <UUID>
```

**Dock Verification**:
1. Connect Thunderbolt dock
2. Check outputs: `swaymsg -t get_outputs`
3. Check USB: `lsusb`
4. Check network (if dock has Ethernet): `ip link`

---

### 8. CUDA/OpenCL (Ryzen)

```bash
# Check CUDA compiler
nvcc --version
# Expected: CUDA 12.x

# Check OpenCL platforms
clinfo
# Expected: Platform: NVIDIA CUDA

# Simple CUDA test (if nvcc available)
echo 'int main() { return 0; }' > test.cu && nvcc test.cu -o test && ./test && echo "CUDA works"
```

---

## Common Issues & Solutions

### VA-API Not Working

**Symptom**: `vainfo` shows no profiles or errors

**Solutions**:
```bash
# Check driver name
echo $LIBVA_DRIVER_NAME

# Intel: Should be "iHD"
export LIBVA_DRIVER_NAME=iHD

# NVIDIA: Should be "nvidia"
export LIBVA_DRIVER_NAME=nvidia

# Verify packages installed
nix-store -q --requisites /run/current-system | grep -E "intel-media|libva-nvidia"
```

### Firefox Still Using Software Decode

**Symptom**: High CPU during video playback

**Solutions**:
1. Check `about:config`:
   - `media.ffmpeg.vaapi.enabled` = true
   - `media.hardware-video-decoding.force-enabled` = true
2. Restart Firefox
3. Check `about:support` for "Hardware Video Decoding"

### Bluetooth Codec Stuck on SBC

**Symptom**: `pactl` shows SBC instead of LDAC/aptX

**Solutions**:
```bash
# Restart WirePlumber
systemctl --user restart wireplumber

# Check codec config
cat /etc/wireplumber/wireplumber.conf.d/*.conf | grep -i codec

# Verify device supports higher codecs
bluetoothctl info <MAC>
```

### NVIDIA Wayland Issues

**Symptom**: Black screen, cursor issues, or crashes

**Solutions**:
```bash
# Verify kernel parameters
cat /proc/cmdline | grep nvidia
# Expected: nvidia-drm.modeset=1

# Check environment
echo $GBM_BACKEND  # Should be nvidia-drm
echo $WLR_NO_HARDWARE_CURSORS  # Should be 1

# Start Sway with debug
sway --unsupported-gpu 2>&1 | tee sway.log
```

---

## Quick Reference Card

| Feature | Verification Command | Expected |
|---------|---------------------|----------|
| Intel VA-API | `vainfo` | iHD driver, H264/HEVC profiles |
| NVIDIA VA-API | `vainfo` | nvidia driver, H264/HEVC profiles |
| GPU Rendering | `glxinfo \| grep renderer` | GPU name (not llvmpipe) |
| Firefox HW | `about:support` | Hardware Video Decoding: ENABLED |
| Webcam | `v4l2-ctl --list-devices` | /dev/video0 listed |
| Bluetooth | `pactl list sinks` | LDAC/aptX codec shown |
| Audio Latency | `pw-top` | Quantum ~256 |
| Thunderbolt | `boltctl list` | Devices listed |
| CUDA | `nvcc --version` | CUDA 12.x |
| OpenCL | `clinfo` | NVIDIA/Intel platform |

---

## Performance Targets

| Metric | Target | Verification |
|--------|--------|--------------|
| Video CPU usage | <20% for 1080p60 | `htop` during YouTube |
| Screen recording CPU | <30% for 1080p60 | `htop` during wf-recorder |
| Audio latency | <15ms | `pw-profiler` |
| Compositor FPS | 60fps | `swaymsg -t get_outputs` |
| Bluetooth codec | LDAC (990kbps) | `pactl list sinks` |
