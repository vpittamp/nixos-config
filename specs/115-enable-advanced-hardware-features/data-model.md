# Data Model: Enable Advanced Hardware Features

**Feature**: 115-enable-advanced-hardware-features
**Date**: 2025-12-13

## Overview

This feature involves NixOS configuration changes, not traditional application data models. This document describes the configuration entities, their relationships, and validation rules.

---

## Configuration Entities

### 1. Hardware Profile

Represents platform-specific hardware configuration.

**Entity**: `hardware/<platform>.nix`

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `platform` | string | Hardware platform identifier | `thinkpad`, `ryzen` |
| `graphics.enable` | bool | Enable hardware graphics | Required `true` for GPU acceleration |
| `graphics.enable32Bit` | bool | Enable 32-bit graphics support | Optional, for Wine/Steam |
| `graphics.extraPackages` | list[package] | GPU-specific packages | Platform-dependent |
| `cpu.updateMicrocode` | bool | Enable CPU microcode updates | Recommended `true` |

**ThinkPad-Specific Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `graphics.extraPackages` | list | `intel-media-driver`, `intel-compute-runtime`, `vpl-gpu-rt` |

**Ryzen-Specific Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `nvidia.package` | package | NVIDIA driver package |
| `nvidia.modesetting.enable` | bool | DRM modesetting for Wayland |
| `nvidia.open` | bool | Use open-source kernel modules |

---

### 2. Target Configuration

Represents complete system configuration for a deployment target.

**Entity**: `configurations/<target>.nix`

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `hostName` | string | System hostname | Required |
| `services.pipewire` | attrset | Audio configuration | See PipeWire section |
| `services.bare-metal` | attrset | Bare metal features | See Bare Metal section |
| `hardware.bluetooth` | attrset | Bluetooth configuration | Optional (laptop only) |
| `environment.sessionVariables` | attrset | Environment variables | Platform-specific |

---

### 3. PipeWire Configuration

Audio pipeline configuration with low-latency and codec support.

**Entity**: `services.pipewire` (NixOS option)

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `enable` | bool | Enable PipeWire | `true` |
| `alsa.enable` | bool | ALSA compatibility | `true` |
| `pulse.enable` | bool | PulseAudio compatibility | `true` |
| `jack.enable` | bool | JACK compatibility | `true` |
| `extraConfig.pipewire."92-low-latency".context.properties."default.clock.quantum"` | int | Buffer size | `256` |
| `extraConfig.pipewire."92-low-latency".context.properties."default.clock.rate"` | int | Sample rate | `48000` |
| `wireplumber.extraConfig."10-bluez".monitor.bluez.properties.bluez5.codecs` | list[string] | Bluetooth codecs | See below |

**Bluetooth Codec Priority** (WirePlumber):
```
["sbc", "sbc_xq", "aac", "ldac", "aptx", "aptx_hd"]
```

---

### 4. Bare Metal Features

Hardware-specific features not available on VMs.

**Entity**: `services.bare-metal` (custom NixOS option)

| Field | Type | Description | ThinkPad | Ryzen |
|-------|------|-------------|----------|-------|
| `enable` | bool | Enable module | `true` | `true` |
| `enableVirtualization` | bool | KVM/libvirt | `true` | `true` |
| `enablePodman` | bool | Container runtime | `true` | `true` |
| `enablePrinting` | bool | CUPS printing | `true` | `true` |
| `enableFingerprint` | bool | Fingerprint auth | `true` | `false` |
| `enableGaming` | bool | Steam/GameMode | `false` | `false` |
| `enableScanning` | bool | SANE scanner | `false` | `false` |

---

### 5. Firefox Hardware Acceleration

Browser settings for hardware video decoding.

**Entity**: `programs.firefox.profiles.<name>.settings` (home-manager option)

| Setting | Type | Description | Value |
|---------|------|-------------|-------|
| `media.ffmpeg.vaapi.enabled` | bool | Enable VA-API decode | `true` |
| `media.hardware-video-decoding.force-enabled` | bool | Force HW decode | `true` |
| `media.av1.enabled` | bool | Enable AV1 codec | `true` |
| `gfx.webrender.all` | bool | GPU WebRender | `true` |

---

### 6. Environment Variables

Platform-specific environment configuration.

**Entity**: `environment.sessionVariables` (NixOS option)

**Intel (ThinkPad)**:
| Variable | Value | Purpose |
|----------|-------|---------|
| `LIBVA_DRIVER_NAME` | `iHD` | VA-API backend |
| `MOZ_ENABLE_WAYLAND` | `1` | Firefox Wayland |

**NVIDIA (Ryzen)**:
| Variable | Value | Purpose |
|----------|-------|---------|
| `LIBVA_DRIVER_NAME` | `nvidia` | VA-API via NVIDIA |
| `GBM_BACKEND` | `nvidia-drm` | GBM backend |
| `__GLX_VENDOR_LIBRARY_NAME` | `nvidia` | GLX vendor |
| `WLR_NO_HARDWARE_CURSORS` | `1` | Cursor workaround |
| `NIXOS_OZONE_WL` | `1` | Electron Wayland |

---

## Relationships

```
┌──────────────────────────────────────────────────────────────┐
│                    Target Configuration                       │
│               (configurations/thinkpad.nix)                   │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐    ┌─────────────────┐                  │
│  │ Hardware Profile │    │ nixos-hardware  │                  │
│  │ (hardware/*.nix) │    │    modules      │                  │
│  └────────┬────────┘    └────────┬────────┘                  │
│           │                      │                            │
│           └──────────┬───────────┘                            │
│                      ▼                                        │
│  ┌─────────────────────────────────────────┐                 │
│  │          Hardware Graphics              │                 │
│  │  • GPU drivers (intel-media/nvidia)     │                 │
│  │  • VA-API packages                       │                 │
│  │  • OpenCL runtime                        │                 │
│  └─────────────────────────────────────────┘                 │
│                                                               │
│  ┌─────────────────┐    ┌─────────────────┐                  │
│  │    PipeWire     │    │   Bluetooth     │                  │
│  │  • Low latency  │    │  • Codecs       │                  │
│  │  • JACK bridge  │    │  • WirePlumber  │                  │
│  └─────────────────┘    └─────────────────┘                  │
│                                                               │
│  ┌─────────────────┐    ┌─────────────────┐                  │
│  │  Bare Metal     │    │   Environment   │                  │
│  │  • TPM          │    │   Variables     │                  │
│  │  • Thunderbolt  │    │  • VA-API       │                  │
│  │  • Fingerprint  │    │  • Wayland      │                  │
│  └─────────────────┘    └─────────────────┘                  │
│                                                               │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                    Home Manager                               │
│                (home-vpittamp.nix)                            │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────────────────────────┐                 │
│  │           Firefox Settings              │                 │
│  │  • media.ffmpeg.vaapi.enabled           │                 │
│  │  • gfx.webrender.all                    │                 │
│  └─────────────────────────────────────────┘                 │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## State Transitions

### Video Playback State (Firefox)

```
┌──────────────┐     Browser Start     ┌──────────────────┐
│   Disabled   │ ────────────────────► │  Software Decode │
│              │                       │   (CPU 60%+)     │
└──────────────┘                       └────────┬─────────┘
                                                │
                                    VA-API Available?
                                                │
                           ┌────────────────────┴────────────────────┐
                           │ Yes                                     │ No
                           ▼                                         ▼
                 ┌──────────────────┐                     ┌──────────────────┐
                 │  Hardware Decode │                     │  Software Decode │
                 │   (CPU <20%)     │                     │   (CPU 60%+)     │
                 └──────────────────┘                     └──────────────────┘
```

### Bluetooth Audio Codec Negotiation

```
┌──────────────┐   Device Connected   ┌──────────────────┐
│  Bluetooth   │ ────────────────────►│ Codec Negotiation│
│  Pairing     │                      │                  │
└──────────────┘                      └────────┬─────────┘
                                               │
                                   Device Capabilities
                                               │
      ┌────────────┬────────────┬────────────┬─┴──────────┬──────────┐
      │ LDAC       │ aptX HD    │ aptX       │ AAC        │ SBC      │
      ▼            ▼            ▼            ▼            ▼          │
  ┌────────┐  ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐     │
  │ 990kbps│  │ 576kbps│   │ 352kbps│   │ 256kbps│   │ 328kbps│     │
  │ HQ     │  │ HD     │   │ Standard│  │ Standard│  │ Fallback│◄────┘
  └────────┘  └────────┘   └────────┘   └────────┘   └────────┘
      ▲
      └── Preferred (highest quality available)
```

---

## Validation Rules

### Configuration Build Validation

| Rule | Validation | Error |
|------|------------|-------|
| Hardware profile exists | `hardware/<platform>.nix` exists | Build fails with missing import |
| Graphics packages valid | All packages in extraPackages exist | Build fails with undefined |
| NVIDIA driver compatible | Package matches kernel | Build fails with version mismatch |
| Environment variables set | Required env vars defined | Runtime: VA-API unavailable |

### Runtime Validation

| Check | Command | Expected |
|-------|---------|----------|
| VA-API available | `vainfo` | Lists decode/encode profiles |
| GPU rendering | `glxinfo \| grep renderer` | Shows GPU name |
| Bluetooth codec | `pactl list sinks` | Shows LDAC/aptX codec |
| Webcam detected | `v4l2-ctl --list-devices` | Lists /dev/video* |
| Audio latency | `pw-top` | Quantum ~256 samples |

---

## Package Requirements by Platform

### ThinkPad (Intel Arc)

```nix
environment.systemPackages = [
  intel-gpu-tools    # GPU monitoring (intel_gpu_top)
  libva-utils        # VA-API verification (vainfo)
  vdpauinfo          # VDPAU verification
  v4l-utils          # Webcam utilities
  cameractrls        # Camera controls
  wf-recorder        # Screen recording
];
```

### Ryzen (NVIDIA RTX 5070)

```nix
environment.systemPackages = [
  nvtopPackages.nvidia  # GPU monitoring TUI
  libva-utils           # VA-API verification
  vulkan-tools          # Vulkan verification
  clinfo                # OpenCL verification
  cudaPackages.cuda_nvcc # CUDA compiler
  wf-recorder           # Screen recording
];
```

### Shared (Both Platforms)

```nix
environment.systemPackages = [
  grim                  # Screenshots
  slurp                 # Region selection
  wl-clipboard          # Clipboard utilities
];
```
