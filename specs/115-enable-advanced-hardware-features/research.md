# Research: Enable Advanced Hardware Features

**Feature**: 115-enable-advanced-hardware-features
**Date**: 2025-12-13

## Overview

This document consolidates research findings for enabling advanced hardware features on ThinkPad (Intel Core Ultra 7 155U / Intel Arc) and Ryzen desktop (AMD 7600X3D / NVIDIA RTX 5070) systems.

---

## 1. Intel Arc GPU Hardware Acceleration (ThinkPad)

### Decision
Use `intel-media-driver` (iHD backend) with `vpl-gpu-rt` for VA-API hardware video encoding/decoding on Intel Arc (Meteor Lake).

### Rationale
- Intel Arc uses the modern iHD VA-API driver (not legacy i965)
- Supports hardware decode: H.264, HEVC, VP9, AV1
- Supports hardware encode: H.264, HEVC (via QuickSync/VPL)
- Firefox uses VA-API through `media.ffmpeg.vaapi.enabled`

### Configuration

```nix
# hardware/thinkpad.nix
hardware.graphics.extraPackages = with pkgs; [
  intel-media-driver      # VA-API iHD backend
  intel-compute-runtime   # OpenCL for Intel Arc
  vpl-gpu-rt             # Intel VPL (QuickSync replacement)
  intel-ocl              # Additional OpenCL
];

# Environment variable
environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
```

### Verification Commands
```bash
vainfo                    # Should show iHD driver with decode/encode profiles
intel_gpu_top             # Real-time GPU utilization
```

### Alternatives Considered
- **i965 driver**: Legacy, not supported on Arc/Meteor Lake - REJECTED
- **Mesa VA-API**: Less complete for Intel encode - REJECTED

---

## 2. NVIDIA Hardware Video (Ryzen Desktop)

### Decision
Use NVIDIA proprietary drivers with VA-API bridge (`libva-nvidia-driver`) for hardware video decode in Firefox. Use NVENC for screen recording.

### Rationale
- NVIDIA NVDEC (6th gen on RTX 5070) provides hardware H.264/HEVC/VP9/AV1 decode
- NVIDIA NVENC (9th gen on RTX 5070) provides real-time encoding
- Firefox requires VA-API; NVIDIA provides `libva-nvidia-driver` bridge
- RTX 5070 (Blackwell) is new enough for open-source kernel modules

### Configuration

```nix
# configurations/ryzen.nix
hardware.nvidia = {
  package = config.boot.kernelPackages.nvidiaPackages.stable;
  modesetting.enable = true;
  powerManagement.enable = true;
  open = true;  # Use open-source kernel modules for RTX 30+
};

environment.sessionVariables = {
  LIBVA_DRIVER_NAME = "nvidia";
  GBM_BACKEND = "nvidia-drm";
  __GLX_VENDOR_LIBRARY_NAME = "nvidia";
};
```

### Verification Commands
```bash
nvidia-smi dmon           # Monitor decoder/encoder utilization
nvtop                     # TUI GPU monitoring
vainfo                    # Should show NVIDIA VA-API profiles
```

### Alternatives Considered
- **VDPAU only**: Firefox doesn't support VDPAU, needs VA-API - REJECTED
- **Nouveau driver**: No hardware decode support - REJECTED

---

## 3. Firefox Hardware Video Decoding

### Decision
Enable VA-API hardware decoding in Firefox via about:config settings and environment variables.

### Rationale
- Firefox 115+ has stable VA-API support on Wayland
- Hardware decode reduces CPU usage from 60%+ to <20% for 1080p60
- Works with both Intel (iHD) and NVIDIA (libva-nvidia-driver) backends

### Configuration

```nix
# home-modules/tools/firefox.nix
programs.firefox.profiles.<profile>.settings = {
  "media.ffmpeg.vaapi.enabled" = true;
  "media.hardware-video-decoding.force-enabled" = true;
  "media.av1.enabled" = true;
  "gfx.webrender.all" = true;
};

# System-wide
environment.sessionVariables.MOZ_ENABLE_WAYLAND = "1";
```

### Verification Commands
```bash
# In Firefox, navigate to:
about:support   # Check "Hardware Video Decoding" shows ENABLED
about:media     # Check video playback uses hardware decoder

# While playing video:
intel_gpu_top   # (Intel) Decoder should show utilization
nvidia-smi dmon # (NVIDIA) Dec column should show activity
```

### Known Issues
- Intel Arc (Meteor Lake) may have artifacts in Chromium/Electron (Firefox is fine)
- NVIDIA OBS NVENC doesn't work with open-source kernel modules

---

## 4. Bluetooth High-Quality Audio Codecs

### Decision
Configure WirePlumber to enable SBC-XQ, AAC, LDAC, aptX, and aptX HD codecs with automatic quality negotiation.

### Rationale
- LDAC provides 990kbps vs SBC's 328kbps (3x improvement)
- aptX HD provides 576kbps with lower latency than LDAC
- Modern Bluetooth headphones (Sony, Sennheiser) support LDAC
- WirePlumber handles codec negotiation automatically

### Configuration

```nix
# configurations/thinkpad.nix
services.pipewire.wireplumber.extraConfig."10-bluez" = {
  "monitor.bluez.properties" = {
    "bluez5.enable-sbc-xq" = true;
    "bluez5.enable-msbc" = true;
    "bluez5.enable-hw-volume" = true;
    "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "ldac" "aptx" "aptx_hd" ];
  };
};

hardware.bluetooth = {
  enable = true;
  powerOnBoot = true;
  settings.General = {
    Enable = "Source,Sink,Media,Socket";
    Experimental = true;  # Required for some codec features
  };
};
```

### Verification Commands
```bash
pactl list sinks        # Check connected Bluetooth device codec
bluetoothctl info <MAC> # Device capabilities
pw-top                  # Audio stream information
```

### Alternatives Considered
- **PulseAudio Bluetooth modules**: Less codec support than WirePlumber - REJECTED
- **Manual codec selection**: Complex, automatic negotiation works well - REJECTED

---

## 5. Webcam V4L2 Support

### Decision
Install V4L2 utilities and ensure proper udev rules for webcam access.

### Rationale
- Built-in ThinkPad webcams use standard V4L2 interface
- USB webcams on Ryzen also use V4L2
- Browser WebRTC requires proper /dev/videoN enumeration
- Camera controls (brightness, contrast) via cameractrls

### Configuration

```nix
# Already in configurations/thinkpad.nix
environment.systemPackages = with pkgs; [
  v4l-utils         # V4L2 utilities (v4l2-ctl)
  cameractrls       # Camera control GUI/CLI
];

# User in video group (already configured)
users.users.vpittamp.extraGroups = [ "video" ];
```

### Verification Commands
```bash
v4l2-ctl --list-devices          # List webcam devices
v4l2-ctl -d /dev/video0 --all    # Show camera capabilities
cameractrls -d /dev/video0       # Camera control interface
```

### Known Issues
- Intel MIPI/IPU6 drivers not yet packaged in NixOS (NixOS issue #225743)
- Workaround: Most ThinkPads use USB-attached webcams that work fine

---

## 6. Hardware Screen Recording

### Decision
Use `wf-recorder` with VAAPI (Intel) or NVENC (NVIDIA) for hardware-accelerated screen recording.

### Rationale
- wf-recorder is native Wayland screen recorder
- Supports VAAPI and NVENC hardware encoders
- Minimal CPU usage (<30%) for 1080p60 capture
- Alternative to OBS for quick recordings

### Configuration

```nix
# home-modules/tools/screen-recording.nix (new module)
environment.systemPackages = with pkgs; [
  wf-recorder       # Wayland screen recorder
  grim              # Screenshot utility
  slurp             # Region selection
];
```

### Usage Examples
```bash
# Intel QuickSync (VAAPI)
wf-recorder -c h264_vaapi -o output.mp4

# NVIDIA NVENC
wf-recorder -c h264_nvenc -o output.mp4

# Record specific output
wf-recorder -o HEADLESS-1 -f recording.mp4
```

### Alternatives Considered
- **OBS Studio**: Heavier, NVENC broken with open NVIDIA modules - ACCEPTABLE ALTERNATIVE
- **ffmpeg direct**: Less convenient than wf-recorder - REJECTED

---

## 7. Thunderbolt/USB4 Support

### Decision
Enable Bolt daemon for Thunderbolt device authorization and security management.

### Rationale
- ThinkPad has Thunderbolt 4 ports for docking stations
- Bolt daemon handles device authorization (security levels)
- Kernel modules already configured in hardware/thinkpad.nix

### Configuration

```nix
# configurations/thinkpad.nix
services.hardware.bolt.enable = true;

# Already in hardware/thinkpad.nix
boot.initrd.availableKernelModules = [
  "thunderbolt"
  "xhci_pci"
];
```

### Verification Commands
```bash
boltctl list              # List Thunderbolt devices
boltctl info <UUID>       # Device details
boltctl authorize <UUID>  # Authorize device
```

### Alternatives Considered
- **No bolt daemon**: Devices may not authorize properly - REJECTED
- **Manual sysfs access**: Less convenient than boltctl - REJECTED

---

## 8. PipeWire Low-Latency Audio

### Decision
Configure PipeWire with 256 quantum (5.3ms latency at 48kHz) for responsive audio.

### Rationale
- Low latency critical for speech-to-text and real-time audio
- 256 quantum is good balance between latency and stability
- JACK bridge enables pro audio applications
- Already configured in both thinkpad.nix and ryzen.nix

### Current Configuration

```nix
# Already in configurations/thinkpad.nix
services.pipewire = {
  enable = true;
  alsa.enable = true;
  pulse.enable = true;
  jack.enable = true;

  extraConfig.pipewire."92-low-latency" = {
    "context.properties" = {
      "default.clock.rate" = 48000;
      "default.clock.quantum" = 256;       # 5.3ms latency
      "default.clock.min-quantum" = 32;    # 0.67ms minimum
      "default.clock.max-quantum" = 1024;  # 21ms maximum
    };
  };
};

security.rtkit.enable = true;  # Real-time scheduling
```

### Verification Commands
```bash
pw-top                           # Audio latency and buffer info
pw-profiler                      # Profile audio pipeline
pactl info | grep "Default"      # Default audio devices
```

---

## 9. CUDA/OpenCL Compute (Ryzen Desktop)

### Decision
Install CUDA toolkit for GPU compute workloads. OpenCL available via NVIDIA drivers.

### Rationale
- RTX 5070 has significant compute capability for AI/ML workloads
- CUDA 12.x compatible with Blackwell architecture
- OpenCL available through NVIDIA drivers automatically

### Configuration

```nix
# configurations/ryzen.nix - ADD
environment.systemPackages = with pkgs; [
  cudaPackages.cuda_nvcc    # CUDA compiler
  clinfo                    # OpenCL verification
  vulkan-tools              # Vulkan verification
];
```

### Verification Commands
```bash
nvcc --version    # CUDA compiler version
clinfo            # OpenCL platforms and devices
vulkaninfo        # Vulkan capabilities
```

### Alternatives Considered
- **ROCm (AMD)**: Not applicable, Ryzen has NVIDIA GPU - N/A
- **CUDA via nix-shell**: Less convenient for development - ACCEPTABLE

---

## 10. Sway GPU-Accelerated Rendering

### Decision
Ensure Sway uses DRM/KMS modesetting for GPU-accelerated compositing (not pixman).

### Rationale
- Bare metal systems should use hardware GPU rendering
- Hetzner VM correctly uses pixman (software) - no change needed
- Intel uses modesetting driver (default)
- NVIDIA requires specific environment variables

### Configuration

```nix
# ThinkPad (Intel) - already using modesetting
services.xserver.videoDrivers = [ "modesetting" ];

# Ryzen (NVIDIA) - specific env vars for Wayland
environment.sessionVariables = {
  GBM_BACKEND = "nvidia-drm";
  WLR_NO_HARDWARE_CURSORS = "1";  # Hardware cursor workaround
};
```

### Verification
```bash
swaymsg -t get_outputs    # Check outputs are rendering
glxinfo | grep "renderer" # Should show GPU, not llvmpipe
```

---

## Summary of Decisions

| Feature | Decision | Status |
|---------|----------|--------|
| Intel VA-API | intel-media-driver (iHD) | ✅ Already configured |
| NVIDIA VA-API | libva-nvidia-driver via LIBVA_DRIVER_NAME=nvidia | ✅ Configured |
| Firefox HW decode | media.ffmpeg.vaapi.enabled | ⚠️ Needs verification |
| Bluetooth codecs | WirePlumber bluez5.codecs list | ✅ Already configured |
| Webcam V4L2 | v4l-utils, cameractrls | ✅ Already installed |
| Screen recording | wf-recorder with VA-API/NVENC | ⚠️ Add wf-recorder |
| Thunderbolt | services.hardware.bolt | ⚠️ Add bolt daemon |
| PipeWire latency | 256 quantum @ 48kHz | ✅ Already configured |
| CUDA/OpenCL | cudaPackages, clinfo | ⚠️ Add packages |
| Sway GPU render | DRM/KMS modesetting | ✅ Already configured |

---

## Sources

- [NixOS Wiki - Intel Graphics](https://nixos.wiki/wiki/Intel_Graphics)
- [NixOS Wiki - NVIDIA](https://nixos.wiki/wiki/Nvidia)
- [NixOS Wiki - Accelerated Video Playback](https://nixos.wiki/wiki/Accelerated_Video_Playback)
- [NixOS Wiki - Bluetooth](https://nixos.wiki/wiki/Bluetooth)
- [NixOS Wiki - CUDA](https://nixos.wiki/wiki/CUDA)
- [PipeWire Wiki - Performance Tuning](https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Performance-Tuning)
- [ArchWiki - Hardware Video Acceleration](https://wiki.archlinux.org/title/Hardware_video_acceleration)
- [wf-recorder GitHub](https://github.com/ammen99/wf-recorder)
