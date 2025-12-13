# Implementation Plan: Enable Advanced Hardware Features

**Branch**: `115-enable-advanced-hardware-features` | **Date**: 2025-12-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/115-enable-advanced-hardware-features/spec.md`

## Summary

Enable advanced hardware features on ThinkPad (Intel Core Ultra 7 155U / Intel Arc) and Ryzen desktop (AMD 7600X3D / NVIDIA RTX 5070) that were previously unavailable on Hetzner VM. Primary enhancements: GPU-accelerated video decoding in Firefox/PWAs (VA-API/NVDEC), webcam V4L2 support, Bluetooth high-quality audio codecs (LDAC/aptX), hardware screen recording (QuickSync/NVENC), Thunderbolt/USB4 dock support, CUDA/OpenCL compute, low-latency PipeWire audio, and GPU-accelerated Sway compositor rendering.

## Technical Context

**Language/Version**: Nix (NixOS 25.11), Bash 5.0+ for helper scripts
**Primary Dependencies**: nixos-hardware modules, home-manager, PipeWire, Firefox, NVIDIA drivers, Intel media-driver
**Storage**: N/A (configuration management, no data storage)
**Testing**: `nixos-rebuild dry-build` for configuration validation, manual hardware verification
**Target Platform**: NixOS on x86_64 bare metal (ThinkPad Intel, Ryzen AMD/NVIDIA)
**Project Type**: NixOS configuration modules (single project - flake-based)
**Performance Goals**: <20% CPU for 1080p video playback, <15ms audio latency, 60fps compositor
**Constraints**: Must not break Hetzner VM configuration, must support conditional hardware detection
**Scale/Scope**: 2 target configurations (thinkpad, ryzen), ~10 module files affected

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Hardware features added via existing modules (`hardware/*.nix`, `configurations/*.nix`) |
| II. Reference Implementation | ✅ PASS | Hetzner remains reference; ThinkPad/Ryzen are platform-specific enhancements |
| III. Test-Before-Apply | ✅ PASS | All changes will be validated via `nixos-rebuild dry-build` |
| IV. Override Priority | ✅ PASS | Use `lib.mkDefault` for overrideable GPU settings, `lib.mkIf` for conditional hardware |
| V. Platform Flexibility | ✅ PASS | Conditional features detect hardware (Intel vs NVIDIA, laptop vs desktop) |
| VI. Declarative Configuration | ✅ PASS | All settings in Nix expressions, no imperative scripts |
| VII. Documentation as Code | ✅ PASS | CLAUDE.md will be updated with hardware verification commands |
| X. Python Standards | ⚠️ N/A | No Python code in this feature |
| XI. i3 IPC Alignment | ⚠️ N/A | No daemon changes in this feature |
| XII. Forward-Only | ✅ PASS | No backwards compatibility needed - new features on new hardware |
| XIII. Deno CLI Standards | ⚠️ N/A | No CLI tools in this feature |
| XIV. Test-Driven | ⚠️ PARTIAL | Hardware testing requires manual verification; dry-build covers config |
| XV. Sway Test Framework | ⚠️ N/A | No window management logic changes |

**Gate Result**: ✅ PASS - No constitutional violations. Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/115-enable-advanced-hardware-features/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output - hardware research
├── data-model.md        # Phase 1 output - configuration model
├── quickstart.md        # Phase 1 output - verification guide
├── contracts/           # Phase 1 output - N/A for NixOS config
│   └── README.md        # Explanation of why contracts not applicable
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
# NixOS Configuration Structure (existing layout)
configurations/
├── thinkpad.nix         # MODIFY: Intel Arc GPU, webcam, Bluetooth, Thunderbolt
├── ryzen.nix            # MODIFY: NVIDIA NVENC/NVDEC, CUDA, OpenCL
├── base.nix             # NO CHANGE: Base configuration
└── hetzner-sway.nix     # NO CHANGE: Reference configuration (software rendering)

hardware/
├── thinkpad.nix         # MODIFY: Intel graphics packages, VA-API
└── ryzen.nix            # MODIFY: NVIDIA kernel params, DRM

modules/
├── services/
│   └── bare-metal.nix   # REVIEW: May need webcam/V4L2 additions
└── desktop/
    └── sway.nix         # REVIEW: Hardware cursor, DRM/KMS settings

home-modules/
└── tools/
    └── firefox.nix      # MODIFY: Hardware video decoding settings
```

**Structure Decision**: Existing NixOS flake structure is preserved. Changes are distributed across hardware configs, target configs, and home-manager modules. No new directories needed.

## Complexity Tracking

> No violations requiring justification. This feature adds hardware-specific configurations within existing module structure.

| Area | Complexity Level | Justification |
|------|------------------|---------------|
| Intel graphics | Low | Standard nixos-hardware modules + packages |
| NVIDIA Wayland | Medium | NVIDIA on Wayland requires specific env vars and kernel params |
| Bluetooth codecs | Low | WirePlumber configuration in existing PipeWire setup |
| Webcam V4L2 | Low | Package additions + udev rules |
| CUDA/OpenCL | Medium | Package additions, may need cudaPackages overlay |
| Thunderbolt | Low | Bolt daemon + kernel modules (already in hardware config) |

## Implementation Phases

### Phase 0: Research (Complete)

See `research.md` for detailed findings on:
- Intel Arc VA-API configuration (intel-media-driver, vpl-gpu-rt)
- NVIDIA NVDEC/NVENC for Firefox hardware video decoding
- Bluetooth codec priorities (LDAC > aptX HD > aptX > AAC > SBC)
- V4L2 webcam enumeration and permissions
- Hardware screen recording tools (wf-recorder with VA-API/NVENC)
- Thunderbolt bolt daemon configuration
- PipeWire low-latency quantum settings

### Phase 1: Design

See `data-model.md` for configuration structure and `quickstart.md` for verification commands.

### Phase 2: Tasks

Generated by `/speckit.tasks` command - not included in this plan.
